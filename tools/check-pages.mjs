#!/usr/bin/env node
// Checks Jeste's browser build (tools/build-pages.sh) in headless browsers.
//
//   node tools/check-pages.mjs <url> [--browser chromium|firefox|all] [--full]
//                              [--timeout SECONDS] [--out DIR]
//
// Default: load <url> in headless Chromium and wait for the game to reach its
// title screen (the game sets <body data-jeste-screen="title">). Exits 0 only
// when it gets there with no console errors, page errors or failed requests.
// --full also plays: it checks that sound starts after the first key press,
// changes Options > Graphics, reloads to see the setting kept, and climbs into
// the first level and runs Mira about. Screenshots and a JSON report go to
// --out (default build/pages-work/check/<browser>/).
//
// No npm packages: Chromium is driven over the DevTools protocol and Firefox
// over WebDriver BiDi, with Node's built-in WebSocket (Node 22+). Browsers:
// $CHROMIUM (else the newest Playwright chromium_headless_shell or chromium in
// ~/.cache/ms-playwright, else chromium/google-chrome on PATH) and $FIREFOX
// (else firefox on PATH). Each run uses a fresh throwaway profile, deleted
// afterwards, so it starts with no save and never touches a real one.

import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------------ arguments

const argv = process.argv.slice(2);
const opt = { url: '', browser: 'chromium', full: false, timeout: 180, out: '' };
for (let i = 0; i < argv.length; i++) {
	const a = argv[i];
	if (a === '--browser') opt.browser = argv[++i];
	else if (a === '--full') opt.full = true;
	else if (a === '--timeout') opt.timeout = Number(argv[++i]);
	else if (a === '--out') opt.out = argv[++i];
	else if (a === '-h' || a === '--help') { usage(0); }
	else if (!a.startsWith('--') && !opt.url) opt.url = a;
	else { console.error(`unknown argument: ${a}`); usage(2); }
}
if (!opt.url || !['chromium', 'firefox', 'all'].includes(opt.browser) || !(opt.timeout > 0)) usage(2);

function usage(code) {
	console.error('usage: node tools/check-pages.mjs <url> [--browser chromium|firefox|all] [--full] [--timeout SECONDS] [--out DIR]');
	process.exit(code);
}

// ------------------------------------------------------------------- browsers

function newest(glob, rel) {
	const base = path.join(os.homedir(), '.cache', 'ms-playwright');
	if (!fs.existsSync(base)) return null;
	const dirs = fs.readdirSync(base).filter((d) => d.startsWith(glob + '-'))
		.sort((a, b) => Number(b.split('-').pop()) - Number(a.split('-').pop()));
	for (const d of dirs) {
		const p = path.join(base, d, rel);
		if (fs.existsSync(p)) return p;
	}
	return null;
}

function onPath(names) {
	for (const n of names) {
		try { return execFileSync('which', [n], { encoding: 'utf8' }).trim(); } catch { /* next */ }
	}
	return null;
}

function findChromium() {
	return process.env.CHROMIUM
		|| newest('chromium_headless_shell', 'chrome-headless-shell-linux64/chrome-headless-shell')
		|| newest('chromium', 'chrome-linux64/chrome')
		|| onPath(['chromium', 'chromium-browser', 'google-chrome-stable', 'google-chrome']);
}

function findFirefox() {
	return process.env.FIREFOX || onPath(['firefox']);
}

function freePort() {
	return new Promise((resolve, reject) => {
		const s = net.createServer();
		s.unref();
		s.on('error', reject);
		s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); });
	});
}

// Launches a browser and waits for the line it prints with its debugging URL.
function launch(exe, args, pattern, env) {
	return new Promise((resolve, reject) => {
		const proc = spawn(exe, args, { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...env } });
		let buf = '';
		const timer = setTimeout(() => { reject(new Error(`${path.basename(exe)} did not start:\n${buf.slice(-2000)}`)); }, 120000);
		const onData = (d) => {
			buf += d;
			if (buf.length > 200000) buf = buf.slice(-100000);
			const m = buf.match(pattern);
			if (m) { clearTimeout(timer); resolve({ proc, url: m[1], output: () => buf }); }
		};
		proc.stdout.on('data', onData);
		proc.stderr.on('data', onData);
		proc.on('exit', (code) => { clearTimeout(timer); reject(new Error(`${path.basename(exe)} exited (${code}):\n${buf.slice(-2000)}`)); });
	});
}

class Socket {
	constructor(url) { this.url = url; this.id = 0; this.pending = new Map(); this.listeners = []; }
	open() {
		return new Promise((resolve, reject) => {
			this.ws = new WebSocket(this.url);
			this.ws.onopen = () => resolve();
			this.ws.onerror = (e) => reject(new Error(`websocket ${this.url}: ${e.message || 'error'}`));
			this.ws.onmessage = (m) => {
				const msg = JSON.parse(m.data);
				if (msg.id !== undefined && this.pending.has(msg.id)) {
					const { resolve: ok, reject: no, method } = this.pending.get(msg.id);
					this.pending.delete(msg.id);
					if (msg.error) no(new Error(`${method}: ${typeof msg.error === 'string' ? msg.error + ' ' + (msg.message || '') : JSON.stringify(msg.error)}`));
					else ok(msg.result);
				} else {
					for (const f of this.listeners) f(msg);
				}
			};
		});
	}
	send(method, params = {}, extra = {}) {
		const id = ++this.id;
		this.ws.send(JSON.stringify({ id, method, params, ...extra }));
		return new Promise((resolve, reject) => {
			this.pending.set(id, { resolve, reject, method });
			// generous: a single-threaded page can be busy for a while loading a level
			setTimeout(() => { if (this.pending.delete(id)) reject(new Error(`${method}: no reply in ${opt.timeout}s`)); }, opt.timeout * 1000);
		});
	}
	close() { try { this.ws.close(); } catch { /* gone */ } }
}

// Key name -> [DOM key, DOM code, Windows keyCode, WebDriver key].
const KEYS = {
	Enter: ['Enter', 'Enter', 13, '\uE006'], Backspace: ['Backspace', 'Backspace', 8, '\uE003'],
	ArrowLeft: ['ArrowLeft', 'ArrowLeft', 37, '\uE012'], ArrowUp: ['ArrowUp', 'ArrowUp', 38, '\uE013'],
	ArrowRight: ['ArrowRight', 'ArrowRight', 39, '\uE014'], ArrowDown: ['ArrowDown', 'ArrowDown', 40, '\uE015'],
	c: ['c', 'KeyC', 67, 'c'], x: ['x', 'KeyX', 88, 'x'],
};

// The page as both drivers present it: evaluate, keys, a click, screenshots.
class ChromiumPage {
	static async start(profile, log) {
		const exe = findChromium();
		if (!exe) throw new Error('no Chromium found (set $CHROMIUM)');
		const port = await freePort();
		const args = ['--headless', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
			'--no-first-run', '--no-default-browser-check', '--window-size=1280,720',
			'--autoplay-policy=user-gesture-required',   // sound may start only after input, as for a visitor
			'--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', 'about:blank'];
		const b = await launch(exe, args, /DevTools listening on (ws:\/\/\S+)/);
		const p = new ChromiumPage(b, exe, log);
		await p.init();
		return p;
	}
	constructor(b, exe, log) { this.b = b; this.exe = exe; this.log = log; this.name = 'chromium'; }
	async init() {
		this.ws = new Socket(this.b.url);
		await this.ws.open();
		const v = await this.ws.send('Browser.getVersion');
		this.version = v.product;
		const { targetId } = await this.ws.send('Target.createTarget', { url: 'about:blank' });
		const { sessionId } = await this.ws.send('Target.attachToTarget', { targetId, flatten: true });
		this.sid = sessionId;
		this.ws.listeners.push((m) => this.event(m));
		for (const d of ['Page', 'Runtime', 'Log', 'Network']) await this.cmd(`${d}.enable`);
		await this.cmd('Page.addScriptToEvaluateOnNewDocument', { source: AUTOPLAY_BLOCK + PRELOAD });
	}
	cmd(method, params = {}) { return this.ws.send(method, params, { sessionId: this.sid }); }
	event(m) {
		const p = m.params || {};
		switch (m.method) {
			case 'Runtime.consoleAPICalled': {
				const text = (p.args || []).map((a) => a.value ?? a.description ?? '').join(' ');
				this.log.console(p.type === 'warning' ? 'warn' : p.type, text);
				break;
			}
			case 'Runtime.exceptionThrown':
				this.log.error('page error: ' + (p.exceptionDetails.exception?.description || p.exceptionDetails.text));
				break;
			case 'Log.entryAdded':
				if (p.entry.level === 'error') this.log.error(`${p.entry.source}: ${p.entry.text} ${p.entry.url || ''}`);
				break;
			case 'Network.responseReceived':
				if (p.response.status >= 400) this.log.error(`HTTP ${p.response.status} ${p.response.url}`);
				break;
			case 'Network.loadingFailed':
				if (!p.canceled) this.log.error(`request failed: ${p.errorText} (${p.type})`);
				break;
		}
	}
	async goto(url) { await this.cmd('Page.navigate', { url }); }
	async reload() { await this.cmd('Page.reload', {}); }
	async eval(expr) {
		const r = await this.cmd('Runtime.evaluate', { expression: `(async () => JSON.stringify(await (${expr})))()`, awaitPromise: true, returnByValue: true });
		if (r.exceptionDetails) throw new Error('eval: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
		return r.result.value === undefined ? undefined : JSON.parse(r.result.value);
	}
	async key(name, holdMs = 60) {
		const [key, code, kc] = KEYS[name];
		const base = { key, code, windowsVirtualKeyCode: kc, nativeVirtualKeyCode: kc };
		await this.cmd('Input.dispatchKeyEvent', { type: 'keyDown', ...base, ...(key.length === 1 ? { text: key } : {}) });
		await sleep(holdMs);
		await this.cmd('Input.dispatchKeyEvent', { type: 'keyUp', ...base });
	}
	async keyDown(name) { const [key, code, kc] = KEYS[name]; await this.cmd('Input.dispatchKeyEvent', { type: 'keyDown', key, code, windowsVirtualKeyCode: kc }); }
	async keyUp(name) { const [key, code, kc] = KEYS[name]; await this.cmd('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: kc }); }
	async click(x, y) {
		await this.cmd('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
		await this.cmd('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
		await this.cmd('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
	}
	async screenshot(file) {
		const r = await this.cmd('Page.captureScreenshot', { format: 'png' });
		fs.writeFileSync(file, Buffer.from(r.data, 'base64'));
	}
	async close() { try { await this.ws.send('Browser.close'); } catch { /* gone */ } this.ws.close(); await stop(this.b.proc); }
}

class FirefoxPage {
	static async start(profile, log) {
		const exe = findFirefox();
		if (!exe) throw new Error('no Firefox found (set $FIREFOX)');
		fs.mkdirSync(profile, { recursive: true });
		fs.writeFileSync(path.join(profile, 'user.js'), [
			'user_pref("media.autoplay.default", 1);',          // block sound until input, as for a visitor
			'user_pref("media.autoplay.blocking_policy", 0);',
			'user_pref("browser.shell.checkDefaultBrowser", false);',
			'user_pref("datareporting.policy.dataSubmissionEnabled", false);',
			'user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);',
			'user_pref("browser.aboutwelcome.enabled", false);',
			'user_pref("app.update.disabledForTesting", true);',
			'user_pref("remote.prefs.recommended", true);',
			'user_pref("webgl.force-enabled", true);',
		].join('\n') + '\n');
		const port = await freePort();
		const args = ['--headless', '--no-remote', '--profile', profile, '--remote-debugging-port', String(port),
			'--width', '1280', '--height', '720', 'about:blank'];
		const b = await launch(exe, args, /WebDriver BiDi listening on (ws:\/\/\S+)/, { MOZ_CRASHREPORTER_DISABLE: '1' });
		const p = new FirefoxPage(b, exe, log);
		await p.init();
		return p;
	}
	constructor(b, exe, log) { this.b = b; this.exe = exe; this.log = log; this.name = 'firefox'; }
	async init() {
		this.ws = new Socket(this.b.url.replace(/\/?$/, '/session'));
		await this.ws.open();
		const s = await this.ws.send('session.new', { capabilities: { alwaysMatch: { webSocketUrl: true } } });
		this.version = `${s.capabilities.browserName} ${s.capabilities.browserVersion}`;
		this.ws.listeners.push((m) => this.event(m));
		await this.ws.send('session.subscribe', { events: ['log.entryAdded', 'network.responseCompleted', 'network.fetchError'] });
		const tree = await this.ws.send('browsingContext.getTree', {});
		this.ctx = tree.contexts[0].context;
		await this.ws.send('browsingContext.setViewport', { context: this.ctx, viewport: { width: 1280, height: 720 } });
		await this.ws.send('script.addPreloadScript', { functionDeclaration: `() => {${PRELOAD}}` });
	}
	event(m) {
		const p = m.params || {};
		switch (m.method) {
			case 'log.entryAdded':
				if (p.type === 'javascript') this.log.error('page error: ' + p.text);
				else this.log.console(p.level === 'warn' ? 'warn' : p.level, p.text || (p.args || []).map((a) => a.value ?? '').join(' '));
				break;
			case 'network.responseCompleted':
				if (p.response.status >= 400) this.log.error(`HTTP ${p.response.status} ${p.response.url}`);
				break;
			case 'network.fetchError':
				if (!/NS_BINDING_ABORTED/.test(p.errorText)) this.log.error(`request failed: ${p.errorText} ${p.request.url}`);
				break;
		}
	}
	async goto(url) { await this.ws.send('browsingContext.navigate', { context: this.ctx, url, wait: 'complete' }); }
	async reload() { await this.ws.send('browsingContext.reload', { context: this.ctx, wait: 'complete' }); }
	async eval(expr) {
		const r = await this.ws.send('script.evaluate', { expression: `(async () => JSON.stringify(await (${expr})))()`, target: { context: this.ctx }, awaitPromise: true });
		if (r.type === 'exception') throw new Error('eval: ' + r.exceptionDetails.text);
		return r.result.type === 'undefined' ? undefined : JSON.parse(r.result.value);
	}
	async actions(list) { await this.ws.send('input.performActions', { context: this.ctx, actions: list }); }
	async key(name, holdMs = 60) {
		const v = KEYS[name][3];
		await this.actions([{ type: 'key', id: 'kb', actions: [{ type: 'keyDown', value: v }, { type: 'pause', duration: holdMs }, { type: 'keyUp', value: v }] }]);
	}
	async keyDown(name) { await this.actions([{ type: 'key', id: 'kb', actions: [{ type: 'keyDown', value: KEYS[name][3] }] }]); }
	async keyUp(name) { await this.actions([{ type: 'key', id: 'kb', actions: [{ type: 'keyUp', value: KEYS[name][3] }] }]); }
	async click(x, y) {
		await this.actions([{ type: 'pointer', id: 'mouse', parameters: { pointerType: 'mouse' }, actions: [
			{ type: 'pointerMove', x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 50 }, { type: 'pointerUp', button: 0 }] }]);
	}
	async screenshot(file) {
		const r = await this.ws.send('browsingContext.captureScreenshot', { context: this.ctx });
		fs.writeFileSync(file, Buffer.from(r.data, 'base64'));
	}
	async close() { try { await this.ws.send('browser.close', {}); } catch { /* gone */ } this.ws.close(); await stop(this.b.proc); }
}

async function stop(proc) {
	if (proc.exitCode !== null) return;
	const gone = new Promise((r) => proc.once('exit', r));
	await Promise.race([gone, sleep(5000)]);
	if (proc.exitCode === null) { proc.kill('SIGTERM'); await Promise.race([gone, sleep(5000)]); }
	if (proc.exitCode === null) proc.kill('SIGKILL');
}

// Headless Chromium lets Web Audio play without a user gesture whatever the
// --autoplay-policy flag says, so for it the page gets a browser's usual rule
// back: an AudioContext stays suspended until a real key, click or touch.
// (Headless Firefox enforces the real policy; see media.autoplay.* above.)
const AUTOPLAY_BLOCK = `
(() => {
	const AC = window.AudioContext;
	if (!AC || AC.__jesteBlocked) return;
	let gesture = false;
	for (const t of ['keydown', 'mousedown', 'pointerdown', 'touchend']) {
		window.addEventListener(t, (e) => { if (e.isTrusted) gesture = true; }, true);
	}
	class Blocked extends AC {
		constructor(...a) { super(...a); if (!gesture) super.suspend(); }
		resume() { return gesture ? super.resume() : Promise.resolve(); }
	}
	Blocked.__jesteBlocked = true;
	window.AudioContext = Blocked;
	window.webkitAudioContext = Blocked;
})();
`;

// Runs in the page before any of its scripts: taps every Web Audio graph's
// output with an analyser, so the check can hear whether sound is playing.
const PRELOAD = `
(() => {
	const AC = window.AudioContext || window.webkitAudioContext;
	if (!AC || window.__jesteAudio) return;
	const taps = [];
	window.__jesteAudio = taps;
	const connect = AudioNode.prototype.connect;
	AudioNode.prototype.connect = function (dest, ...rest) {
		const r = connect.call(this, dest, ...rest);
		try {
			if (dest instanceof AudioDestinationNode) {
				let t = taps.find((x) => x.ctx === this.context);
				if (!t) { t = { ctx: this.context, an: this.context.createAnalyser() }; t.an.fftSize = 2048; taps.push(t); }
				connect.call(this, t.an);
			}
		} catch (e) { /* not ours to break */ }
		return r;
	};
	window.__jesteAudioState = () => taps.map((t) => {
		const d = new Float32Array(t.an.fftSize);
		t.an.getFloatTimeDomainData(d);
		let peak = 0;
		for (const v of d) peak = Math.max(peak, Math.abs(v));
		return { state: t.ctx.state, time: t.ctx.currentTime, peak };
	});
})();
`;

// ---------------------------------------------------------------------- checks

class Log {
	constructor(file) { this.file = file; this.errors = []; this.lines = 0; fs.writeFileSync(file, ''); }
	write(s) {
		if (this.lines++ > 5000) return;   // capped
		fs.appendFileSync(this.file, `${new Date().toISOString()} ${s}\n`);
	}
	note(s) { console.log(`  ${s}`); this.write(`NOTE ${s}`); }
	console(level, text) {
		this.write(`console.${level} ${text}`);
		if (level === 'error' || level === 'assert') this.errors.push(`console.error: ${text}`);
	}
	error(s) { this.write(`ERROR ${s}`); this.errors.push(s); }
}

const screen = (p) => p.eval('document.body ? document.body.dataset : {}');

async function waitFor(p, what, test, seconds) {
	const until = Date.now() + seconds * 1000;
	let d = {};
	while (Date.now() < until) {
		if (p.log.errors.length) throw new Error(`error(s) while waiting for ${what}:\n    ${p.log.errors.slice(0, 10).join('\n    ')}`);
		d = await screen(p).catch(() => ({}));
		if (test(d)) return d;
		if (d.jesteScreen === 'error') throw new Error(`page shows an error: ${d.jesteError}`);
		await sleep(250);
	}
	throw new Error(`timed out after ${seconds}s waiting for ${what} (page state: ${JSON.stringify(d)})`);
}

async function check(browser, outDir) {
	fs.mkdirSync(outDir, { recursive: true });
	const log = new Log(path.join(outDir, 'console.log'));
	const profile = fs.mkdtempSync(path.join(ROOT, 'build', 'pages-work', `profile-${browser}-`));
	const report = { browser, url: opt.url, full: opt.full, steps: [], ok: false };
	let p = null;
	const step = (name, data = {}) => { report.steps.push({ name, ...data }); log.note(`${name} ${Object.keys(data).length ? JSON.stringify(data) : ''}`); };
	try {
		p = await (browser === 'firefox' ? FirefoxPage : ChromiumPage).start(profile, log);
		report.version = p.version;
		step('browser', { version: p.version });
		const t0 = Date.now();
		await p.goto(opt.url);
		const gl = await p.eval(`(() => { const g = document.createElement('canvas').getContext('webgl2'); if (!g) return null; const x = g.getExtension('WEBGL_debug_renderer_info'); return x ? g.getParameter(x.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER); })()`);
		step('webgl2', { renderer: gl });
		const title = await waitFor(p, 'the title screen', (d) => d.jesteScreen === 'title', opt.timeout);
		const loadMs = Date.now() - t0;
		await sleep(1500);   // let the title settle (and any late errors arrive)
		const bytes = await p.eval(`performance.getEntriesByType('resource').concat(performance.getEntriesByType('navigation')).reduce((s, e) => s + (e.transferSize || e.encodedBodySize || 0), 0)`);
		const frames = await p.eval(`new Promise((r) => { let n = 0; const t = performance.now(); const f = () => { if (++n < 120) requestAnimationFrame(f); else r(Math.round(1000 * n / (performance.now() - t))); }; requestAnimationFrame(f); })`);
		step('title', { loadMs, engineStartMs: await p.eval('window.jesteLoadMs'), transferredMB: +(bytes / 1048576).toFixed(1), fps: frames, fidelity: title.jesteFidelity });
		await p.screenshot(path.join(outDir, '1-title.png'));

		if (opt.full) {
			// Sound: silent (suspended) before any input, playing after a key.
			const before = await p.eval('window.__jesteAudioState()');
			step('audio before input', { contexts: before });
			await p.key('ArrowDown');   // Climb -> Options
			await sleep(2500);
			const after = await p.eval('window.__jesteAudioState()');
			step('audio after a key', { contexts: after });
			const playing = after.some((c) => c.state === 'running' && c.peak > 0.001);
			if (!after.length) throw new Error('the game made no Web Audio context');
			if (before.some((c) => c.state === 'running' && c.peak > 0.001)) throw new Error('sound played before any input (autoplay policy not in force?)');
			if (!playing) throw new Error('no sound after the first key press');

			// Options > Graphics one step down, back out (saves), reload.
			const was = title.jesteFidelity;
			await p.key('Enter');                       // open Options
			await sleep(600);
			for (let i = 0; i < 2; i++) { await p.key('ArrowDown'); await sleep(200); }   // Music, Sound, Fullscreen
			await p.key('Enter');                       // Fullscreen on (a key press may ask the browser)
			await sleep(1500);
			const fsOn = await p.eval('!!document.fullscreenElement');
			await p.key('Enter');                       // and off
			await sleep(1500);
			const fsOff = await p.eval('!!document.fullscreenElement');
			step('fullscreen', { on: fsOn, offAgain: !fsOff });
			await p.key('ArrowDown');                   // Graphics
			await sleep(200);
			await p.key('ArrowLeft');
			await sleep(400);
			await p.screenshot(path.join(outDir, '2-options.png'));
			await p.key('Backspace');                   // back to the menu: saves the settings
			await sleep(2000);                          // IndexedDB sync
			await p.reload();
			const again = await waitFor(p, 'the title after reload', (d) => d.jesteScreen === 'title', opt.timeout);
			step('setting after reload', { before: was, after: again.jesteFidelity });
			if (again.jesteFidelity === was) throw new Error(`Graphics went back to ${was} after reload`);
			await sleep(1200);

			// Climb: title -> chapter select -> the first level, then run about.
			await p.key('Enter');                       // Climb
			let lv = null;
			let entered = 0;
			for (let i = 0; i < 20 && !lv; i++) {
				await sleep(800);
				const d = await screen(p);
				if (d.jesteScreen === 'level') lv = d;
				else { await p.key('Enter'); entered = Date.now(); }   // the chapter select's Climb
			}
			if (!lv) throw new Error('never reached a level from the title');
			step('level', { loadMs: Date.now() - entered, room: lv.jesteRoom });
			await sleep(2000);
			await p.screenshot(path.join(outDir, '3-level.png'));
			let start = null;
			for (let i = 0; i < 8; i++) {               // hold Enter (Pause) to skip each scene
				const d = await screen(p);
				if (d.jesteMode === 'play') { start = d; break; }
				await p.key('Enter', 1500);
				await sleep(1200);
			}
			if (!start) throw new Error(`the level never got to play mode (${JSON.stringify(await screen(p))})`);
			await p.keyDown('ArrowRight');
			await sleep(1200);
			await p.key('c', 150);                      // jump
			await sleep(600);
			await p.keyUp('ArrowRight');
			await sleep(1000);                          // the page hears about it every 30 frames
			const moved = await screen(p);
			step('play', { room: moved.jesteRoom, mode: moved.jesteMode, from: [start.jesteX, start.jesteY], to: [moved.jesteX, moved.jesteY], deaths: moved.jesteDeaths });
			if (moved.jesteRoom === start.jesteRoom && Math.abs(Number(moved.jesteX) - Number(start.jesteX)) < 8) throw new Error('Mira did not move');
			await p.screenshot(path.join(outDir, '4-play.png'));
		}
		await sleep(500);
		if (log.errors.length) throw new Error(`${log.errors.length} error(s):\n    ${log.errors.slice(0, 10).join('\n    ')}`);
		report.ok = true;
	} catch (e) {
		report.error = String(e.message || e);
		log.write(`FAIL ${report.error}`);
		if (p) await p.screenshot(path.join(outDir, 'fail.png')).catch(() => {});
	} finally {
		report.errors = log.errors;
		if (p) await p.close();
		fs.rmSync(profile, { recursive: true, force: true });
		fs.writeFileSync(path.join(outDir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
	}
	console.log(`${report.ok ? 'PASS' : 'FAIL'} ${browser}${report.ok ? '' : ': ' + report.error} (log: ${path.relative(process.cwd(), log.file)})`);
	return report.ok;
}

fs.mkdirSync(path.join(ROOT, 'build', 'pages-work'), { recursive: true });
let ok = true;
for (const b of opt.browser === 'all' ? ['chromium', 'firefox'] : [opt.browser]) {
	console.log(`${b}: ${opt.url}${opt.full ? ' (full)' : ''}`);
	ok = (await check(b, opt.out ? path.join(opt.out, b) : path.join(ROOT, 'build', 'pages-work', 'check', b))) && ok;
}
process.exit(ok ? 0 : 1);
