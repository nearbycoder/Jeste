#!/usr/bin/env node
// Checks Jeste's browser build (tools/build-pages.sh) on phones and tablets,
// as far as headless browsers can stand in for them: WebKit with iPhone and
// iPad profiles and Chromium with an Android phone profile, through
// Playwright, with touch enabled.
//
//   node tools/check-mobile.mjs [--profiles iphone,ipad,...] [--dir build/pages]
//                               [--out DIR] [--timeout SECONDS]
//
// Profiles: iphone, iphone-portrait, ipad, ipad-portrait, pixel,
// pixel-portrait (default: all). Each serves --dir from a local server on a
// free port (gzip, as GitHub Pages sends it), loads it in a fresh browser
// context and:
//   - waits for the title screen and records the load time, the bytes sent,
//     the frame rate and memory: the WebAssembly heap, WebGL textures, buffers
//     and renderbuffers (counted by wrapping the WebGL calls), the canvas
//     size, and the browser's own processes (peak RSS, and GPU memory from
//     the amdgpu/i915 fdinfo where the kernel reports it);
//   - taps through the menus with real touch events (Climb, the chapter card)
//     into the first level;
//   - when the page shows on-screen controls (#touch), uses them: holds Pause
//     to skip the opening scene, runs and jumps with the d-pad and Jump,
//     dashes, grabs, and opens and closes the pause menu with its button. A
//     stick plus a button at once needs two fingers: Chromium gets real
//     multi-touch over the DevTools protocol; WebKit (Playwright has no
//     multi-touch there) gets pointer events built in the page, after one real
//     tap per button to check the real path;
//   - in portrait on a phone, checks that the page asks to turn the device.
// Screenshots, a log and report.json per profile go to --out (default
// build/pages-work/mobile/<profile>/); a summary prints at the end.
//
// Playwright isn't a dependency of this repo: $PLAYWRIGHT_CORE points at a
// playwright-core package (default: the one in ~/Sites/blog), and WebKit runs
// from $WEBKIT (default ~/.cache/webkit-libs/webkit-2359/pw_run.sh) when that
// exists. Every browser runs headless with a throwaway profile.

import { createRequire } from 'node:module';
import http from 'node:http';
import zlib from 'node:zlib';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const argv = process.argv.slice(2);
const ALL = ['iphone', 'iphone-portrait', 'ipad', 'ipad-portrait', 'pixel', 'pixel-portrait'];
const opt = { profiles: ALL, dir: path.join(ROOT, 'build', 'pages'), out: path.join(ROOT, 'build', 'pages-work', 'mobile'), timeout: 240 };
for (let i = 0; i < argv.length; i++) {
	const a = argv[i];
	if (a === '--profiles') opt.profiles = argv[++i].split(',');
	else if (a === '--dir') opt.dir = path.resolve(argv[++i]);
	else if (a === '--out') opt.out = path.resolve(argv[++i]);
	else if (a === '--timeout') opt.timeout = Number(argv[++i]);
	else { console.error(`unknown argument: ${a}\nusage: node tools/check-mobile.mjs [--profiles ${ALL.join(',')}] [--dir DIR] [--out DIR] [--timeout SECONDS]`); process.exit(2); }
}
for (const p of opt.profiles) if (!ALL.includes(p)) { console.error(`unknown profile ${p}`); process.exit(2); }

const require = createRequire(import.meta.url);
const PW = process.env.PLAYWRIGHT_CORE || path.join(os.homedir(), 'Sites', 'blog', 'node_modules', 'playwright-core');
const { webkit, chromium, devices } = require(PW);
const WEBKIT = process.env.WEBKIT || path.join(os.homedir(), '.cache', 'webkit-libs', 'webkit-2359', 'pw_run.sh');

// Chromium: $CHROMIUM, else the newest Playwright headless shell or Chromium
// in ~/.cache/ms-playwright (Playwright's own pinned build may not be there).
function newestChromium() {
	const base = path.join(os.homedir(), '.cache', 'ms-playwright');
	if (!fs.existsSync(base)) return null;
	for (const [glob, rel] of [['chromium_headless_shell', 'chrome-headless-shell-linux64/chrome-headless-shell'], ['chromium', 'chrome-linux64/chrome']]) {
		const dirs = fs.readdirSync(base).filter((d) => d.startsWith(glob + '-')).sort((a, b) => Number(b.split('-').pop()) - Number(a.split('-').pop()));
		for (const d of dirs) if (fs.existsSync(path.join(base, d, rel))) return path.join(base, d, rel);
	}
	return null;
}
const CHROMIUM = process.env.CHROMIUM || newestChromium();

const PROFILES = {
	'iphone': { engine: 'webkit', device: 'iPhone 15 landscape' },
	'iphone-portrait': { engine: 'webkit', device: 'iPhone 15', portrait: true },
	'ipad': { engine: 'webkit', device: 'iPad Pro 11 landscape' },
	'ipad-portrait': { engine: 'webkit', device: 'iPad Pro 11', portrait: true },
	'pixel': { engine: 'chromium', device: 'Pixel 7 landscape' },
	'pixel-portrait': { engine: 'chromium', device: 'Pixel 7', portrait: true },
};

// ------------------------------------------------------------------- server

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
const gz = new Map();
let sent = 0;
function serve() {
	const server = http.createServer((req, res) => {
		const rel = decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/^\/+/, '') || 'index.html';
		const file = path.join(opt.dir, rel);
		if (!file.startsWith(opt.dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
		const ext = path.extname(file);
		let body = fs.readFileSync(file);
		const headers = { 'Content-Type': TYPES[ext] || 'application/octet-stream', 'Cache-Control': 'no-store' };
		if (/gzip/.test(req.headers['accept-encoding'] || '') && ext !== '.png') {
			if (!gz.has(file)) gz.set(file, zlib.gzipSync(body, { level: 6 }));
			body = gz.get(file);
			headers['Content-Encoding'] = 'gzip';
		}
		headers['Content-Length'] = body.length;
		res.writeHead(200, headers);
		res.end(body);
		sent += body.length;
	});
	return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// ------------------------------------------------------- in-page measuring

// Runs before the page's own scripts. Wraps WebAssembly memory and the WebGL
// calls that allocate GPU memory, so the page can report what it holds.
const INSTRUMENT = `
(() => {
	if (window.__jm) return;
	const S = window.__jm = { mems: [], wasm: 0, wasmPeak: 0, tex: 0, texPeak: 0, buf: 0, bufPeak: 0, rb: 0, rbPeak: 0, textures: 0, gl: 0, glPeak: 0 };
	const M = WebAssembly.Memory;
	const add = (m) => { if (m instanceof M && !S.mems.includes(m)) S.mems.push(m); };
	const Wrapped = function (d) { const m = new M(d); add(m); return m; };
	Wrapped.prototype = M.prototype;
	WebAssembly.Memory = Wrapped;
	for (const name of ['instantiate', 'instantiateStreaming']) {
		const f = WebAssembly[name];
		if (!f) continue;
		WebAssembly[name] = function (...a) {
			return f.apply(WebAssembly, a).then((r) => {
				const inst = r.instance || r;
				try { for (const v of Object.values(inst.exports || {})) add(v); } catch (e) { /* not an instance */ }
				return r;
			});
		};
	}
	S.sample = () => {
		let t = 0;
		for (const m of S.mems) t += m.buffer.byteLength;
		S.wasm = t;
		S.wasmPeak = Math.max(S.wasmPeak, t);
		return t;
	};
	setInterval(S.sample, 100);

	// Web Audio buffers (Godot plays each sound as a decoded sample): bytes
	// made, and bytes still alive (dropped once garbage-collected).
	S.audio = 0; S.audioPeak = 0; S.audioMade = 0;
	const AC = window.AudioContext || window.webkitAudioContext;
	if (AC && AC.prototype.createBuffer) {
		const gone = window.FinalizationRegistry ? new FinalizationRegistry((n) => { S.audio -= n; }) : null;
		const cb = AC.prototype.createBuffer;
		AC.prototype.createBuffer = function (ch, len, rate) {
			const b = cb.call(this, ch, len, rate);
			const n = ch * len * 4;
			S.audio += n; S.audioMade += n; S.audioPeak = Math.max(S.audioPeak, S.audio);
			if (n > 262144) console.log('audio buffer: ' + (n / 1048576).toFixed(1) + ' MB (' + ch + ' ch, ' + len + ' frames at ' + rate + ' Hz)');
			if (gone) gone.register(b, n);
			return b;
		};
	}

	// Taps every Web Audio graph's output with an analyser, to hear whether
	// sound plays (as tools/check-pages.mjs does).
	const taps = [];
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
	S.sound = () => taps.map((t) => {
		const d = new Float32Array(t.an.fftSize);
		t.an.getFloatTimeDomainData(d);
		let peak = 0;
		for (const v of d) peak = Math.max(peak, Math.abs(v));
		return { state: t.ctx.state, rate: t.ctx.sampleRate, peak: +peak.toFixed(4) };
	});

	const G = window.WebGL2RenderingContext;
	if (!G) return;
	const P = G.prototype;
	const BPP = { 0x8058: 4, 0x8051: 4, 0x8C43: 4, 0x8C41: 4, 0x8229: 1, 0x822B: 2, 0x881A: 8, 0x881B: 8, 0x822D: 2, 0x822F: 4, 0x822E: 4, 0x8230: 8,
		0x8814: 16, 0x8815: 16, 0x8059: 4, 0x8C3A: 4, 0x8C3D: 4, 0x81A6: 4, 0x88F0: 4, 0x8CAC: 4, 0x8CAD: 8, 0x81A5: 2, 0x1908: 4, 0x1907: 4, 0x1906: 1, 0x1909: 1, 0x190A: 2, 0x8227: 2, 0x1903: 1, 0x8D62: 2, 0x8056: 2, 0x8057: 2, 0x8D48: 1 };
	const bpp = (f) => BPP[f] || 4;
	const st = new WeakMap();
	const state = (gl) => { let s = st.get(gl); if (!s) { s = { unit: 0, tex: new Map(), buf: new Map(), rb: null }; st.set(gl, s); } return s; };
	const sizes = new Map();   // object -> Map(key -> bytes)
	const bump = (kind, d) => {
		S[kind] += d;
		S[kind + 'Peak'] = Math.max(S[kind + 'Peak'], S[kind]);
		S.gl = S.tex + S.buf + S.rb;
		S.glPeak = Math.max(S.glPeak, S.gl);
	};
	const setSize = (kind, obj, key, bytes) => {
		if (!obj) return;
		let m = sizes.get(obj);
		if (!m) { m = new Map(); sizes.set(obj, m); }
		bump(kind, bytes - (m.get(key) || 0));
		m.set(key, bytes);
	};
	const drop = (kind, obj) => {
		const m = sizes.get(obj);
		if (!m) return;
		let t = 0;
		for (const v of m.values()) t += v;
		bump(kind, -t);
		sizes.delete(obj);
	};
	const CUBE0 = 0x8515;
	const texTarget = (t) => (t >= CUBE0 && t < CUBE0 + 6) ? 0x8513 : t;
	const bound = (gl, target) => state(gl).tex.get(state(gl).unit + ':' + texTarget(target));
	const wrap = (name, f) => { const o = P[name]; if (o) P[name] = function (...a) { f.call(this, ...a); return o.apply(this, a); }; };
	wrap('activeTexture', function (u) { state(this).unit = u; });
	wrap('bindTexture', function (t, tex) { state(this).tex.set(state(this).unit + ':' + t, tex); });
	wrap('createTexture', function () { S.textures++; });
	wrap('deleteTexture', function (tex) { if (tex) { S.textures--; drop('tex', tex); } });
	wrap('texImage2D', function (target, level, ifmt, ...a) {
		let w, h;
		if (a.length >= 6) { w = a[0]; h = a[1]; } else { const src = a[2] || {}; w = src.videoWidth || src.width || 0; h = src.videoHeight || src.height || 0; }
		setSize('tex', bound(this, target), target + ':' + level, w * h * bpp(ifmt));
	});
	wrap('texImage3D', function (target, level, ifmt, w, h, d) { setSize('tex', bound(this, target), target + ':' + level, w * h * d * bpp(ifmt)); });
	wrap('compressedTexImage2D', function (target, level, ifmt, w, h, border, data) { // eslint-disable-line
		setSize('tex', bound(this, target), target + ':' + level, span(data, arguments[7], arguments[8]));
	});
	wrap('texStorage2D', function (target, levels, ifmt, w, h) {
		let t = 0;
		for (let l = 0; l < levels; l++) t += Math.max(1, w >> l) * Math.max(1, h >> l) * bpp(ifmt);
		setSize('tex', bound(this, target), 'storage', t * (target === 0x8513 ? 6 : 1));
	});
	wrap('texStorage3D', function (target, levels, ifmt, w, h, d) {
		let t = 0;
		for (let l = 0; l < levels; l++) t += Math.max(1, w >> l) * Math.max(1, h >> l) * d * bpp(ifmt);
		setSize('tex', bound(this, target), 'storage', t);
	});
	wrap('bindBuffer', function (t, b) { state(this).buf.set(t, b); });
	// (data, usage, srcOffset, length): Emscripten passes a view of the whole heap
	const span = (d, off, len, el) => typeof d === 'number' ? d : !d ? 0 : len ? len * (el || d.BYTES_PER_ELEMENT || 1) : off !== undefined ? d.byteLength - off * (d.BYTES_PER_ELEMENT || 1) : d.byteLength;
	wrap('bufferData', function (t, d, usage, off, len) { setSize('buf', state(this).buf.get(t), 'data', span(d, off, len)); });
	wrap('deleteBuffer', function (b) { if (b) drop('buf', b); });
	wrap('bindRenderbuffer', function (t, r) { state(this).rb = r; });
	wrap('renderbufferStorage', function (t, f, w, h) { setSize('rb', state(this).rb, 's', w * h * bpp(f)); });
	wrap('renderbufferStorageMultisample', function (t, n, f, w, h) { setSize('rb', state(this).rb, 's', w * h * bpp(f) * Math.max(1, n)); });
	wrap('deleteRenderbuffer', function (r) { if (r) drop('rb', r); });
})();
`;

const KNOWN_WEBKIT = /glBlitFramebuffer: Read and write color attachments cannot be the same image/;
const MB = (n) => +(n / 1048576).toFixed(1);

// The browser's own processes: every process under this one (Playwright
// starts the browsers as children). Peak summed RSS, the largest single
// process, and GPU memory where the kernel reports it per client.
function procTree() {
	const kids = new Map();
	for (const d of fs.readdirSync('/proc')) {
		if (!/^\d+$/.test(d)) continue;
		try {
			const s = fs.readFileSync(`/proc/${d}/stat`, 'utf8');
			const ppid = Number(s.slice(s.lastIndexOf(')') + 2).split(' ')[1]);
			if (!kids.has(ppid)) kids.set(ppid, []);
			kids.get(ppid).push(Number(d));
		} catch { /* gone */ }
	}
	const out = [];
	const walk = (p) => { for (const c of kids.get(p) || []) { out.push(c); walk(c); } };
	walk(process.pid);
	return out;
}

function procSample() {
	let rss = 0, top = { name: '', rss: 0 }, vram = 0, gtt = 0;
	const clients = new Set();
	for (const pid of procTree()) {
		try {
			const st = fs.readFileSync(`/proc/${pid}/status`, 'utf8');
			const kb = Number((st.match(/VmRSS:\s+(\d+)/) || [0, 0])[1]) * 1024;
			const name = (st.match(/Name:\s+(\S+)/) || [0, '?'])[1];
			rss += kb;
			if (kb > top.rss) top = { name, rss: kb };
			for (const fd of fs.readdirSync(`/proc/${pid}/fdinfo`)) {
				let info;
				try { info = fs.readFileSync(`/proc/${pid}/fdinfo/${fd}`, 'utf8'); } catch { continue; }
				const id = info.match(/drm-client-id:\s+(\d+)/);
				if (!id || clients.has(id[1])) continue;
				clients.add(id[1]);
				const unit = (m) => (m ? Number(m[1]) * ({ KiB: 1024, MiB: 1048576, GiB: 1073741824 }[m[2]] || 1) : 0);
				vram += unit(info.match(/drm-memory-vram:\s+(\d+)\s*(\w+)?/));
				gtt += unit(info.match(/drm-memory-gtt:\s+(\d+)\s*(\w+)?/));
			}
		} catch { /* gone */ }
	}
	return { rss, top, vram, gtt };
}

// Where the largest process's resident memory sits, by mapping: anonymous
// (heaps, the wasm heap, JIT code), GPU driver mappings, shared memory, files.
function smapsOf(name) {
	let best = null, bestRss = 0;
	for (const pid of procTree()) {
		try {
			const st = fs.readFileSync(`/proc/${pid}/status`, 'utf8');
			const kb = Number((st.match(/VmRSS:\s+(\d+)/) || [0, 0])[1]);
			if ((st.match(/Name:\s+(\S+)/) || [0, ''])[1] === name && kb > bestRss) { best = pid; bestRss = kb; }
		} catch { /* gone */ }
	}
	if (!best) return null;
	const cat = {};
	let cur = 'anon';
	try {
		for (const line of fs.readFileSync(`/proc/${best}/smaps`, 'utf8').split('\n')) {
			const m = line.match(/^[0-9a-f]+-[0-9a-f]+ \S+ \S+ \S+ \S+\s*(.*)$/);
			if (m) {
				const f = m[1];
				cur = !f || f.startsWith('[heap]') || f.startsWith('[anon') ? 'anon' : /dri|drm|amdgpu|i915/.test(f) ? 'gpu-driver' : /memfd|SYSV|dev\/shm|\/dmabuf/.test(f) ? 'shared' : f.startsWith('[') ? 'other' : 'files';
				continue;
			}
			const r = line.match(/^Rss:\s+(\d+)/);
			if (r) cat[cur] = (cat[cur] || 0) + Number(r[1]) * 1024;
		}
	} catch { return null; }
	return Object.fromEntries(Object.entries(cat).map(([k, v]) => [k, MB(v)]));
}

// ---------------------------------------------------------------- the check

class Run {
	constructor(name, prof) {
		this.name = name;
		this.prof = prof;
		this.dir = path.join(opt.out, name);
		fs.rmSync(this.dir, { recursive: true, force: true });
		fs.mkdirSync(this.dir, { recursive: true });
		this.logFile = path.join(this.dir, 'console.log');
		fs.writeFileSync(this.logFile, '');
		this.lines = 0;
		this.errors = [];
		this.report = { profile: name, device: prof.device, engine: prof.engine, steps: [], ok: false, cannot: [] };
		this.peak = { rss: 0, top: { name: '', rss: 0 }, vram: 0, gtt: 0 };
		this.shots = 0;
	}
	write(s) { if (this.lines++ < 5000) fs.appendFileSync(this.logFile, `${new Date().toISOString()} ${s}\n`); }
	step(name, data = {}) { this.report.steps.push({ name, ...data }); this.write(`STEP ${name} ${JSON.stringify(data)}`); console.log(`  ${this.name}: ${name} ${JSON.stringify(data)}`); }
	cannot(what) { this.report.cannot.push(what); this.write(`CANNOT ${what}`); console.log(`  ${this.name}: cannot ${what}`); }
	sampleProc() {
		const s = procSample();
		if (s.rss > this.peak.rss) this.peak.rss = s.rss;
		if (s.top.rss > this.peak.top.rss) this.peak.top = s.top;
		this.peak.vram = Math.max(this.peak.vram, s.vram);
		this.peak.gtt = Math.max(this.peak.gtt, s.gtt);
	}
	async shot(label) { await this.page.screenshot({ path: path.join(this.dir, `${++this.shots}-${label}.png`) }).catch((e) => this.write(`screenshot failed: ${e.message}`)); }
	async data() { return this.page.evaluate(() => ({ ...document.body.dataset })).catch(() => ({})); }
	async waitFor(what, test, seconds = opt.timeout) {
		const until = Date.now() + seconds * 1000;
		let d = {};
		while (Date.now() < until) {
			if (this.crashed) throw new Error(`the page crashed while waiting for ${what}`);
			d = await this.data();
			if (test(d)) return d;
			if (d.jesteScreen === 'error') throw new Error(`page shows an error: ${d.jesteError}`);
			await sleep(250);
		}
		throw new Error(`timed out after ${seconds}s waiting for ${what} (page state: ${JSON.stringify(d)})`);
	}
	async mem() {
		if (this.cdp) {   // Chromium: collect garbage first, so dropped audio buffers count as gone
			await this.cdp.send('HeapProfiler.collectGarbage').catch(() => {});
			await sleep(300);
		}
		const m = await this.page.evaluate(() => {
			const j = window.__jm;
			if (!j) return null;
			j.sample();
			const c = document.getElementById('canvas');
			return { audio: j.audio, audioPeak: j.audioPeak, audioMade: j.audioMade, wasm: j.wasm, wasmPeak: j.wasmPeak, gl: j.gl, glPeak: j.glPeak, texPeak: j.texPeak, bufPeak: j.bufPeak, rbPeak: j.rbPeak, textures: j.textures,
				canvas: c ? [c.width, c.height] : null, dpr: window.devicePixelRatio, jsHeap: performance.memory ? performance.memory.usedJSHeapSize : null };
		}).catch(() => null);
		this.sampleProc();
		if (!m) return null;
		const top = this.peak.top.name;
		return { audioLiveMB: MB(m.audio), audioPeakMB: MB(m.audioPeak), audioMadeMB: MB(m.audioMade), topNowByMapping: smapsOf(top), wasmMB: MB(m.wasm), wasmPeakMB: MB(m.wasmPeak), webglMB: MB(m.gl), webglPeakMB: MB(m.glPeak), texturesPeakMB: MB(m.texPeak), buffersPeakMB: MB(m.bufPeak),
			renderbuffersPeakMB: MB(m.rbPeak), textures: m.textures, canvas: m.canvas, canvasMB: m.canvas ? MB(m.canvas[0] * m.canvas[1] * 4 * 3) : null, dpr: m.dpr,
			jsHeapMB: m.jsHeap ? MB(m.jsHeap) : null, procPeakMB: MB(this.peak.rss), procTop: `${this.peak.top.name} ${MB(this.peak.top.rss)}`, gpuVramPeakMB: MB(this.peak.vram), gpuGttPeakMB: MB(this.peak.gtt) };
	}
	async fps(ms = 3000) {
		return this.page.evaluate((ms) => new Promise((r) => { let n = 0; const t = performance.now(); const f = () => { n++; if (performance.now() - t < ms) requestAnimationFrame(f); else r(Math.round(1000 * n / (performance.now() - t))); }; requestAnimationFrame(f); }), ms).catch(() => null);
	}

	// Game pixel (320x180, integer scaled and centred in the canvas) -> page CSS pixel.
	async gp(gx, gy) {
		return this.page.evaluate(([gx, gy]) => {
			const c = document.getElementById('canvas');
			const r = c.getBoundingClientRect();
			const s = Math.max(1, Math.floor(Math.min(c.width / 320, c.height / 180)));
			const k = r.width / c.width;
			return [r.left + ((c.width - 320 * s) / 2 + gx * s) * k, r.top + ((c.height - 180 * s) / 2 + gy * s) * k];
		}, [gx, gy]);
	}
	async tapGame(gx, gy) { const [x, y] = await this.gp(gx, gy); await this.page.touchscreen.tap(x, y); }

	// The centre of an on-screen control, or null when it isn't shown.
	async ctl(id) {
		return this.page.evaluate((id) => {
			const e = document.getElementById(id);
			if (!e) return null;
			const r = e.getBoundingClientRect();
			const st = getComputedStyle(e);
			if (!r.width || !r.height || st.visibility === 'hidden' || st.display === 'none') return null;
			for (let a = e.parentElement; a; a = a.parentElement) if (getComputedStyle(a).display === 'none') return null;
			return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height };
		}, id);
	}

	// Multi-touch: real over CDP in Chromium, pointer events built in the page
	// for WebKit.
	async touches(type, points) {
		if (this.cdp) {
			// touchStart / touchMove carry every finger down; touchEnd the one lifted
			const pts = type === 'touchEnd' ? points : [...this.active.values()];
			await this.cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts.map((p) => ({ x: p.x, y: p.y, id: p.id, radiusX: 8, radiusY: 8, force: 1 })) });
			return;
		}
		await this.page.evaluate(([type, points]) => {
			const map = { touchStart: 'pointerdown', touchMove: 'pointermove', touchEnd: 'pointerup' };
			window.__synthTargets = window.__synthTargets || {};
			for (const p of points) {
				let t = type === 'touchStart' ? document.elementFromPoint(p.x, p.y) : window.__synthTargets[p.id];
				if (!t) continue;
				window.__synthTargets[p.id] = t;
				t.dispatchEvent(new PointerEvent(map[type], { pointerId: 100 + p.id, pointerType: 'touch', isPrimary: false, clientX: p.x, clientY: p.y, bubbles: true, cancelable: true, buttons: type === 'touchEnd' ? 0 : 1 }));
			}
		}, [type, points]);
	}
	async down(id, x, y) { this.active.set(id, { id, x, y }); await this.touches('touchStart', [{ id, x, y }]); }
	async move(id, x, y) { this.active.set(id, { id, x, y }); await this.touches('touchMove', [{ id, x, y }]); }
	async up(id) { const p = this.active.get(id); this.active.delete(id); await this.touches('touchEnd', [p]); }
	async press(ctlId, ms, id = 1) { const c = await this.ctl(ctlId); if (!c) throw new Error(`no #${ctlId} on screen`); await this.down(id, c.x, c.y); await sleep(ms); await this.up(id); }
	async touchActions() { const d = await this.data(); return d.jesteTouchHeld || ''; }
}

async function runProfile(name, server) {
	const prof = PROFILES[name];
	const run = new Run(name, prof);
	const url = `http://127.0.0.1:${server.address().port}/index.html`;
	const device = devices[prof.device];
	let browser = null;
	const sampler = setInterval(() => run.sampleProc(), 500);
	const started = Date.now();
	try {
		const launchOpts = { headless: true };
		if (prof.engine === 'webkit' && fs.existsSync(WEBKIT)) launchOpts.executablePath = WEBKIT;
		if (prof.engine === 'chromium' && CHROMIUM) launchOpts.executablePath = CHROMIUM;
		// Chromium headless draws WebGL in software (SwiftShader) unless told to use the GPU
		if (prof.engine === 'chromium') launchOpts.args = ['--enable-gpu', '--use-angle=gl-egl', '--ignore-gpu-blocklist'];
		browser = await (prof.engine === 'webkit' ? webkit : chromium).launch(launchOpts);
		run.step('browser', { engine: prof.engine, version: browser.version(), device: prof.device, viewport: device.viewport, dpr: device.deviceScaleFactor });
		const ctx = await browser.newContext({ ...device });
		await ctx.addInitScript(INSTRUMENT);
		const page = run.page = await ctx.newPage();
		run.active = new Map();
		if (prof.engine === 'chromium') run.cdp = await ctx.newCDPSession(page);
		page.on('console', (m) => {
			run.write(`console.${m.type()} ${m.text()}`);
			if (m.type() !== 'error') return;
			// Headless WebKit (WPE) reports this while the engine boots, though
			// none of the game's own blitFramebuffer calls reads and writes one
			// image and the frames come out right: counted, not failed.
			if (KNOWN_WEBKIT.test(m.text()) && prof.engine === 'webkit') run.report.webkitBlitWarnings = (run.report.webkitBlitWarnings || 0) + 1;
			else run.errors.push(m.text());
		});
		page.on('pageerror', (e) => {
			run.write(`pageerror ${e.message}`);
			// This headless WebKit has no audio device: every AudioContext.resume()
			// fails, the engine's included. Counted; sound is checked in Chromium.
			if (prof.engine === 'webkit' && /Failed to start the audio device/.test(e.message)) run.report.webkitNoAudioDevice = (run.report.webkitNoAudioDevice || 0) + 1;
			else run.errors.push(e.message);
		});
		page.on('crash', () => { run.crashed = true; run.write('PAGE CRASHED'); });
		sent = 0;
		const t0 = Date.now();
		await page.goto(url);
		run.step('media', await page.evaluate(() => ({ coarse: matchMedia('(pointer: coarse)').matches, fine: matchMedia('(any-pointer: fine)').matches, hoverNone: matchMedia('(hover: none)').matches,
			webgl2: (() => { const g = document.createElement('canvas').getContext('webgl2'); if (!g) return false; const x = g.getExtension('WEBGL_debug_renderer_info'); return x ? g.getParameter(x.UNMASKED_RENDERER_WEBGL) : true; })(), webgpu: !!navigator.gpu, touchPoints: navigator.maxTouchPoints })));

		if (prof.portrait && device.viewport.width < 600) {
			// a phone held upright: the page should ask to turn it
			await run.waitFor('the title (or the rotate prompt)', (d) => d.jesteScreen === 'title' || d.jesteRotate === 'on');
			await sleep(2000);
			const d = await run.data();
			const prompt = await run.ctl('rotate');
			run.step('portrait', { rotatePrompt: !!prompt, screen: d.jesteScreen, touch: d.jesteTouch || 'none' });
			await run.shot('portrait');
			if (!prompt) run.cannot('ask to turn the phone sideways (no rotate prompt in portrait)');
			run.report.memory = await run.mem();
			run.report.ok = !!prompt && !run.errors.length && !run.crashed;
			return run;
		}

		const title = await run.waitFor('the title screen', (d) => d.jesteScreen === 'title');
		const loadMs = Date.now() - t0;
		await sleep(1500);
		run.step('title', { loadMs, sentMB: MB(sent), fps: await run.fps(), fidelity: title.jesteFidelity, touch: title.jesteTouch || 'none' });
		run.report.atTitle = await run.mem();
		run.step('memory at title', run.report.atTitle);
		await run.shot('title');

		// Menus by tap: Climb (title row 0), then the chapter card.
		await run.tapGame(86, 106);
		let d = await run.waitFor('the chapter select', (d) => d.jesteScreen !== 'title', 8).catch(() => null);
		const touch = (await run.data()).jesteTouch || 'none';
		run.step('tap Climb', { screen: d ? d.jesteScreen : 'not reported (see the screenshot)', touch });
		await sleep(1500);
		await run.shot('chapters');
		const enteredAt = Date.now();
		for (let i = 0; i < 4 && (await run.data()).jesteScreen !== 'level'; i++) {
			await run.tapGame(230, 80);   // the chapter card (right of the postcard)
			await sleep(2500);
		}
		d = await run.waitFor('the first level', (d) => d.jesteScreen === 'level', 90).catch(() => null);
		run.step('tap the chapter card', { reachedLevel: !!d, ms: Date.now() - enteredAt });
		if (!d) { run.cannot('start a chapter by tapping'); throw new Error('never reached a level by tapping'); }
		await sleep(2500);
		run.report.inLevel = await run.mem();
		run.step('memory in the level', run.report.inLevel);
		await run.shot('level');

		const hasControls = !!(await run.ctl('t-jump'));
		run.step('on-screen controls', { shown: hasControls, touch: (await run.data()).jesteTouch || 'none' });

		// Through the opening scene: hold Pause (skips a scene), else tap.
		let play = null;
		for (let i = 0; i < (hasControls ? 10 : 40); i++) {
			d = await run.data();
			if (d.jesteMode === 'play') { play = d; break; }
			if (hasControls) await run.press('t-pause', 1700);
			else await run.tapGame(160, 60);
			await sleep(hasControls ? 1200 : 700);
		}
		// a hold that lands just as the scene ends opens the pause menu: Dash backs out
		for (let i = 0; i < 3 && hasControls && (await run.data()).jestePaused === 'true'; i++) {
			await run.press('t-dash', 150);
			await sleep(800);
		}
		run.step('opening scene', { play: !!play, via: hasControls ? 'hold Pause' : 'taps', mode: (await run.data()).jesteMode });
		if (!play) throw new Error('the level never got to play mode');
		if (!hasControls) {
			run.cannot('move, jump, dash, grab or pause: there are no on-screen controls');
			run.step('fps in play', { fps: await run.fps() });
			run.report.memory = await run.mem();
			run.report.ok = !run.errors.length && !run.crashed;
			await run.shot('play');
			return run;
		}

		// Real single taps on each button first (Godot counts what it got).
		for (const b of ['t-jump', 't-dash', 't-grab']) {
			const c = await run.ctl(b);
			await run.page.touchscreen.tap(c.x, c.y);
			await sleep(300);
		}
		run.step('real taps on Jump, Dash, Grab', { counts: (await run.data()).jesteTouchCount || '' });
		// sound: playing after taps (music streams through the worklet on a phone)
		let snd = [];
		for (let i = 0; i < 8; i++) {
			snd = await run.page.evaluate(() => window.__jm.sound());
			if (snd.some((c) => c.state === 'running' && c.peak > 0.001)) break;
			await sleep(500);
		}
		run.step('sound after taps', { contexts: snd });
		run.report.sound = snd.some((c) => c.state === 'running' && c.peak > 0.001);

		// Back in play mode before each test: a scene can start as she walks
		// on (hold Pause through it), and a hold that lands as one ends opens
		// the pause menu (Dash backs out). The page hears about the game every
		// 30 frames, so every wait is on what the game reports, not a clock.
		const toPlay = async (what) => {
			for (let i = 0; i < 12; i++) {
				const d = await run.data();
				if (d.jestePaused === 'true') await run.press('t-dash', 150);
				else if (d.jesteMode === 'play') return d;
				else if (d.jesteMode === 'dialogue') await run.press('t-pause', 1700);
				await sleep(900);
			}
			throw new Error(`never back in play mode (${what})`);
		};
		const held = (re, what, seconds = 15) => run.waitFor(what, (d) => re.test(d.jesteTouchHeld || ''), seconds).then((d) => d.jesteTouchHeld);

		// Run right with the d-pad, jump on the way.
		const pad = await run.ctl('t-pad');
		const r = pad.w / 2;
		const p0 = await toPlay('before running');
		await run.down(1, pad.x, pad.y);
		await run.move(1, pad.x + r * 0.7, pad.y);
		const heldRight = await held(/right/, 'the game to hold Right');
		const p1 = await run.waitFor('Mira to run right', (d) => d.jesteRoom !== p0.jesteRoom || Number(d.jesteX) - Number(p0.jesteX) >= 8, 30).catch(() => null);
		await run.press('t-jump', 180, 2);
		const jumpLetGo = await held(/^(?!.*jump)(?=.*right)/, 'Jump let go with Right still held', 10).catch(() => null);
		await run.shot('run-and-jump');
		// up-right + Dash
		await run.move(1, pad.x + r * 0.6, pad.y - r * 0.6);
		const heldDiag = await held(/^(?=.*right)(?=.*up)/, 'the game to hold Up-Right');
		await run.press('t-dash', 120, 2);
		await sleep(500);
		await run.up(1);
		await sleep(1500);
		const p2 = await run.data();
		run.step('d-pad + Jump + Dash', { heldRight, jumpLetGo, heldDiag, from: [p0.jesteX, p0.jesteY], afterRun: p1 ? [p1.jesteX, p1.jesteY] : null, later: [p2.jesteX, p2.jesteY], room: p2.jesteRoom, deaths: p2.jesteDeaths, counts: p2.jesteTouchCount });
		if (!p1) throw new Error('Mira did not move with the d-pad');
		if (jumpLetGo === null) throw new Error('Jump stayed held after its finger lifted (with the d-pad still held)');
		const c = JSON.parse(p2.jesteTouchCount || '{}');
		if (!(c.jump >= 2 && c.dash >= 2)) throw new Error(`the game didn't get the Jump and Dash presses (${p2.jesteTouchCount})`);
		// Grab: hold it with a direction held, and read what the game holds.
		await toPlay('before grabbing');
		await run.down(1, pad.x - r * 0.7, pad.y);
		const g = await run.ctl('t-grab');
		await run.down(2, g.x, g.y);
		const heldGrab = await held(/^(?=.*left)(?=.*grab)/, 'the game to hold Left + Grab').catch((e) => `none (${e.message})`);
		await run.up(2);
		await run.up(1);
		run.step('d-pad left + Grab held', { held: heldGrab });
		if (!/grab/.test(heldGrab) || !/left/.test(heldGrab)) throw new Error(`the game didn't hold left + grab (${heldGrab})`);
		run.step('fps in play', { fps: await run.fps() });

		// Pause button: opens the pause menu; Resume by tapping its row.
		await toPlay('before pausing');
		await run.press('t-pause', 150);
		const pz = await run.waitFor('the pause menu', (d) => d.jestePaused === 'true', 20).catch(() => null);
		await sleep(500);
		await run.shot('paused');
		await run.tapGame(160, 48);   // Resume (first pause row)
		const rs = await run.waitFor('play again', (d) => d.jestePaused === 'false', 20).catch(() => null);
		run.step('pause button, Resume by tap', { paused: !!pz, resumed: !!rs });
		if (!pz || !rs) throw new Error('the pause button or tapping Resume did not work');
		await run.shot('resumed');
		run.report.memory = await run.mem();
		run.report.ok = !run.errors.length && !run.crashed;
	} catch (e) {
		run.report.error = String(e.message || e);
		run.write(`FAIL ${run.report.error}`);
		if (run.page) await run.shot('fail');
		if (run.page && !run.report.memory) run.report.memory = await run.mem();
	} finally {
		clearInterval(sampler);
		run.report.errors = run.errors.slice(0, 20);
		run.report.crashed = !!run.crashed;
		run.report.seconds = Math.round((Date.now() - started) / 1000);
		if (browser) await browser.close().catch(() => {});
		fs.writeFileSync(path.join(run.dir, 'report.json'), JSON.stringify(run.report, null, 2) + '\n');
		console.log(`${run.report.ok ? 'PASS' : 'FAIL'} ${name}${run.report.ok ? '' : ': ' + (run.report.error || run.errors.slice(0, 3).join(' | ') || 'see the log')} (log: ${path.relative(process.cwd(), run.logFile)})`);
	}
	return run;
}

const server = await serve();
const files = fs.readdirSync(opt.dir).filter((f) => fs.statSync(path.join(opt.dir, f)).isFile());
const sizes = Object.fromEntries(files.map((f) => [f, MB(fs.statSync(path.join(opt.dir, f)).size)]));
console.log(`serving ${opt.dir} on 127.0.0.1:${server.address().port}; files (MB): ${JSON.stringify(sizes)}`);
let ok = true;
const summary = [];
for (const name of opt.profiles) {
	console.log(`${name}: ${PROFILES[name].device} (${PROFILES[name].engine})`);
	const run = await runProfile(name, server);
	ok = run.report.ok && ok;
	const m = run.report.memory || {};
	summary.push({ profile: name, ok: run.report.ok, error: run.report.error, title: run.report.steps.find((s) => s.name === 'title'), memory: m, cannot: run.report.cannot });
}
server.close();
fs.mkdirSync(opt.out, { recursive: true });
fs.writeFileSync(path.join(opt.out, 'summary.json'), JSON.stringify({ dir: opt.dir, files: sizes, gzipMB: Object.fromEntries([...gz].map(([f, b]) => [path.basename(f), MB(b.length)])), runs: summary }, null, 2) + '\n');
console.log(`summary: ${path.relative(process.cwd(), path.join(opt.out, 'summary.json'))}`);
process.exit(ok ? 0 : 1);
