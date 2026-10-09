class_name UIKit
extends RefCounted
## Shared drawing kit for every menu: framed panels, animated menu rows,
## keycap glyphs, toggles / sliders, the diamond screen wipe, a procedural
## campfire and the JESTE logo (block letters with bevel, outline and
## extrusion, built once into textures).

const GOLD := Color("f2c14e")
const GOLD_DK := Color("a8702a")
const CREAM := Color("fff1d6")
const INK := Color("140c1c")
const CRIMSON := Color("d8344f")
const MUTED := Color(0.78, 0.74, 0.86)


static func frame(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var x0 := roundf(r.position.x)
	var y0 := roundf(r.position.y)
	var w := roundf(r.size.x)
	var h := roundf(r.size.y)
	ci.draw_rect(Rect2(x0, y0, w, 1), col)
	ci.draw_rect(Rect2(x0, y0 + h - 1, w, 1), col)
	ci.draw_rect(Rect2(x0, y0, 1, h), col)
	ci.draw_rect(Rect2(x0 + w - 1, y0, 1, h), col)


static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var p := c.round()
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)


## A framed panel: soft drop shadow, vertical gradient body, ink outline,
## gold inner border, corner studs and a faint top sheen.
static func panel(ci: CanvasItem, r: Rect2, a: float = 1.0, accent: Color = GOLD) -> void:
	r = Rect2(r.position.round(), r.size.round())
	ci.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.35 * a))
	var top := Color(0.13, 0.08, 0.19, 0.94 * a)
	var bot := Color(0.05, 0.03, 0.08, 0.94 * a)
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bot, bot]))
	frame(ci, r.grow(1), Color(INK, a))
	frame(ci, r.grow(-1), Color(accent, 0.9 * a))
	frame(ci, r.grow(-2), Color(accent.darkened(0.55), 0.6 * a))
	ci.draw_rect(Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 1), Color(1, 1, 1, 0.07 * a))
	for c in [r.position + Vector2(1, 1), Vector2(r.end.x - 2, r.position.y + 1), Vector2(r.position.x + 1, r.end.y - 2), r.end - Vector2(2, 2)]:
		diamond(ci, c, 2.0, Color(accent.lightened(0.3), a))


## Title strip on top of a panel.
static func panel_title(ci: CanvasItem, r: Rect2, text: String, a: float = 1.0) -> void:
	var w := PixelText.width(text) + 16
	var tr := Rect2(roundf(r.get_center().x - w / 2.0), r.position.y - 6, w, 12)
	ci.draw_rect(tr.grow(1), Color(INK, a))
	ci.draw_rect(tr, Color(CRIMSON.darkened(0.25), a))
	ci.draw_rect(Rect2(tr.position.x, tr.position.y, tr.size.x, 1), Color(CRIMSON.lightened(0.3), a))
	PixelText.draw_centered(ci, tr.get_center().x, tr.position.y + 2, text, Color(CREAM, a), Color(INK, 0.8 * a))


## Options (title and pause): what the highlighted row does, for its current
## value where that matters. Drawn in a box beside the panel (help_box).
static func option_help(item: String) -> String:
	match item:
		"Music Volume":
			return "How loud the music is."
		"Sound Volume":
			return "How loud the sound effects, voices and ambience are."
		"Fullscreen":
			if OS.has_feature("web"):
				return "Fill the screen, or play in the browser page. Esc leaves fullscreen."
			return "Fill the screen, or play in a window. F11 or Alt+Enter also switch, anywhere in the game."
		"Window Size":
			if OS.has_feature("web"):
				return "The browser page sets the size of the game."
			if int(Game.settings.get("window_scale", 0)) <= 0:
				return "Auto: about three quarters of your screen. Or 2x and up: each game pixel that many screen pixels wide."
			return "Each game pixel %d screen pixels wide. Auto sizes the window to about three quarters of your screen." % Game.window_scale()
		"Graphics":
			match Game.fidelity():
				Game.FIDELITY_LOW: return "Low: no glow or colour grading, fog or light shafts, and half the particles. For weak GPUs."
				Game.FIDELITY_MEDIUM: return "Medium: a lighter glow, no light shafts and fewer particles than High."
				Game.FIDELITY_ULTRA: return "Ultra: High plus a wide soft glow, terrain shadows, depth of field, finer lights and more particles."
			return "High: the full look, with glow, colour grading, fog, light shafts and particles."
		"Smooth Motion":
			match str(Game.settings.get("smooth_motion", "auto")):
				"on": return "Draws movement between the game's 60 steps a second: smoother on 144 Hz screens, up to 17 ms later."
				"off": return "Draws only the game's 60 steps a second: no added delay, but movement can judder on 144 Hz screens."
			if OS.has_feature("web"):
				return "On in a browser, which doesn't report your screen's refresh rate. Off saves up to 17 ms on 60 Hz screens."
			return "On when your screen isn't a multiple of 60 Hz (144, 165...) or Game Speed is below 100%%. It is %s now." % ("on" if Game.smooth_motion() else "off")
		"Screen Shake":
			return "The camera shakes on dashes, deaths, broken walls, bumpers and gates."
		"Reduce Flashing":
			return "Dims full-screen flashes (bells, deaths, mask swaps...) and the dash shimmer to a fifth."
		"Rumble":
			return "The gamepad vibrates on jumps off walls, landings, dashes, springs and deaths."
		"Speedrun Timer":
			return "Shows the chapter's time in the corner while you climb."
		"Controls":
			return "Rebind keys and pad buttons, and choose whether Grab is held or toggled."
		"Erase Save":
			return "Erases every berry, bell, best time and checkpoint. It asks first."
	return "Settings are saved as you change them."


const OPTION_STEP := 11.0        # Options rows (title and pause), top to top
const HELP_BOX_W := 142          # the Options help box, beside the panel
const HELP_TEXT_W := HELP_BOX_W - 14

const HELP_HEADINGS := {"Graphics": "Graphics Fidelity"}   # a row's full name, where the row is short of room


## The help box beside the Options panel: the row's name and its help text.
static func help_box(ci: CanvasItem, pos: Vector2, item: String, a: float) -> void:
	var lines := PixelText.wrap(option_help(item), HELP_TEXT_W)
	var r := Rect2(pos, Vector2(HELP_BOX_W, help_box_height(item)))
	panel(ci, r, a)
	var heading: String = HELP_HEADINGS.get(item, item)
	PixelText.draw_outlined(ci, r.position + Vector2(7, 7), heading, Color(GOLD, a), Color(INK, a))
	ci.draw_rect(Rect2(r.position.x + 7, r.position.y + 18, PixelText.width(heading), 1), Color(GOLD_DK, 0.8 * a))
	for i in lines.size():
		PixelText.draw_outlined(ci, r.position + Vector2(7, 22 + i * PixelText.LINE_H), lines[i], Color(CREAM, 0.9 * a), Color(INK, a))


static func help_box_height(item: String) -> float:
	return 26.0 + PixelText.wrap(option_help(item), HELP_TEXT_W).size() * PixelText.LINE_H


## Mouse in menus: the row under `p` for rows drawn by menu_row() at
## (x, y0 + i * step), w wide, or -1. Rows are hit from just above their text
## to the next row, plus the selection marker's margin on the left.
static func row_at(p: Vector2, x: float, y0: float, w: float, step: float, n: int) -> int:
	if p.x < x - 10.0 or p.x > x + w:
		return -1
	var i := floori((p.y - y0 + 3.0) / step)
	return i if i >= 0 and i < n else -1


## A left click on a menu row confirms it and a right click goes back: the
## click becomes the matching action press, so menus handle it as they would
## a key. Returns null for anything else.
static func click_action(ev: InputEvent) -> InputEventAction:
	if not (ev is InputEventMouseButton) or not ev.pressed:
		return null
	var b := (ev as InputEventMouseButton).button_index
	if b != MOUSE_BUTTON_LEFT and b != MOUSE_BUTTON_RIGHT:
		return null
	return press("confirm" if b == MOUSE_BUTTON_LEFT else "back")


## A pressed action event, for turning mouse input into what a key would do.
static func press(action: String) -> InputEventAction:
	var a := InputEventAction.new()
	a.action = action
	a.pressed = true
	return a


## A vertical mouse wheel event (either direction, pressed or released).
static func is_wheel(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton and ((ev as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP \
		or (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN)


static var _wheel_acc := 0.0

## Mouse wheel: -1 for a notch up, +1 for a notch down, 0 otherwise. A
## touchpad scrolls in small steps (the event's factor); they add up to a
## notch, and a fast fling still moves one step per event.
static func wheel_step(ev: InputEvent) -> int:
	if not is_wheel(ev) or not ev.pressed:
		return 0
	var mb := ev as InputEventMouseButton
	var d := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
	if signf(_wheel_acc) != float(d):
		_wheel_acc = 0.0   # changed direction
	_wheel_acc += d * (mb.factor if mb.factor > 0.0 else 1.0)
	if absf(_wheel_acc) < 0.999:
		return 0
	_wheel_acc = 0.0
	return d


## A wheel event as the action to handle: `up` for a notch up, `down` for a
## notch down, or null.
static func wheel_action(ev: InputEvent, up: String, down: String) -> InputEventAction:
	var d := wheel_step(ev)
	return null if d == 0 else press(up if d < 0 else down)


## Rows whose value the wheel steps when the pointer is on them (elsewhere in
## a list it moves the selection).
const WHEEL_VALUE_ROWS := ["Music Volume", "Sound Volume", "Window Size", "Graphics", "Smooth Motion", "Game Speed", "Air Dashes", "Route Ghost", "Stick Deadzone"]


## Wheel on a menu list: over a row in WHEEL_VALUE_ROWS it steps that value
## (up = more, as Right), otherwise it moves the selection. `hovered` is the
## row under the pointer (-1 for none).
static func wheel_menu(ev: InputEvent, items: Array, hovered: int) -> InputEventAction:
	if hovered >= 0 and WHEEL_VALUE_ROWS.has(items[hovered]):
		return wheel_action(ev, "right", "left")
	return wheel_action(ev, "up", "down")


## Menu row. `k` is the 0..1 animated selection amount.
static func menu_row(ci: CanvasItem, x: float, y: float, w: float, text: String, k: float, t: float, a: float = 1.0, centered := false) -> void:
	var e := ease(clampf(k, 0.0, 1.0), 0.4)
	if e > 0.01:
		var x0 := x - 10.0
		var c0 := Color(GOLD, 0.30 * e * a)
		var c1 := Color(GOLD, 0.0)
		if centered:
			var cx := x + w / 2.0
			ci.draw_polygon(PackedVector2Array([Vector2(cx - w / 2.0 - 12, y - 2), Vector2(cx, y - 2), Vector2(cx, y + 9), Vector2(cx - w / 2.0 - 12, y + 9)]),
				PackedColorArray([c1, c0, c0, c1]))
			ci.draw_polygon(PackedVector2Array([Vector2(cx, y - 2), Vector2(cx + w / 2.0 + 12, y - 2), Vector2(cx + w / 2.0 + 12, y + 9), Vector2(cx, y + 9)]),
				PackedColorArray([c0, c1, c1, c0]))
		else:
			ci.draw_polygon(PackedVector2Array([Vector2(x0, y - 2), Vector2(x0 + w, y - 2), Vector2(x0 + w, y + 9), Vector2(x0, y + 9)]),
				PackedColorArray([c0, c1, c1, c0]))
			ci.draw_rect(Rect2(x0, y - 2, 2, 11), Color(GOLD, e * a))
	var col := MUTED.lerp(CREAM, e)
	var tx := x + roundf(4.0 * e) if not centered else x + w / 2.0 - PixelText.width(text) / 2.0
	PixelText.draw_outlined(ci, Vector2(roundf(tx), y), text, Color(col, a * (0.8 + 0.2 * e)), Color(INK, 0.9 * a))
	if e > 0.5:
		var bx := (x - 5.0 if not centered else x + w / 2.0 - PixelText.width(text) / 2.0 - 7.0) + sin(t * 6.0) * 1.0
		diamond(ci, Vector2(bx, y + 4), 2.0, Color(GOLD, a))


## A keyboard / pad key glyph; returns its width.
static func keycap(ci: CanvasItem, pos: Vector2, label: String, a: float = 1.0) -> float:
	var w := maxf(PixelText.width(label) + 6.0, 9.0)
	var r := Rect2(pos.round() + Vector2(0, -1), Vector2(w, 12))
	ci.draw_rect(r.grow(1), Color(INK, 0.9 * a))
	ci.draw_rect(r, Color(0.86, 0.82, 0.9, a))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), Color(0.55, 0.5, 0.64, a))
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), Color(1, 1, 1, a))
	PixelText.draw(ci, Vector2(r.position.x + roundf((w - PixelText.width(label)) / 2.0), r.position.y + 1), label, Color(INK, a))
	return w


## Row of [key, label] hints. Returns the total width.
static func hints(ci: CanvasItem, pos: Vector2, pairs: Array, a: float = 1.0) -> float:
	var x := pos.x
	for p in pairs:
		x += keycap(ci, Vector2(x, pos.y), str(p[0]), a) + 3.0
		PixelText.draw_outlined(ci, Vector2(x, pos.y + 1), str(p[1]), Color(CREAM, 0.9 * a), Color(INK, 0.85 * a))
		x += PixelText.width(str(p[1])) + 9.0
	return x - pos.x


## Mouse: the index of the [key, label] pair under `p` in a row drawn by
## hints() at `pos`, or -1.
static func hint_at(p: Vector2, pos: Vector2, pairs: Array) -> int:
	if p.y < pos.y - 3.0 or p.y > pos.y + 12.0:
		return -1
	var x := pos.x
	for i in pairs.size():
		var w := maxf(PixelText.width(str(pairs[i][0])) + 6.0, 9.0) + 3.0 + PixelText.width(str(pairs[i][1]))
		if p.x >= x - 2.0 and p.x <= x + w + 2.0:
			return i
		x += w + 9.0
	return -1


static func hints_width(pairs: Array) -> float:
	var x := 0.0
	for p in pairs:
		x += maxf(PixelText.width(str(p[0])) + 6.0, 9.0) + 3.0 + PixelText.width(str(p[1])) + 9.0
	return x - 9.0


## A toggle switch. With a `key` (the row's name) its knob slides and its
## colour fades between off and on instead of snapping (see eased).
static func toggle(ci: CanvasItem, pos: Vector2, on: bool, a: float = 1.0, key := "") -> void:
	var k := eased("toggle:" + key, 1.0 if on else 0.0) if key != "" else (1.0 if on else 0.0)
	var r := Rect2(pos.round(), Vector2(15, 7))
	ci.draw_rect(r.grow(1), Color(INK, a))
	ci.draw_rect(r, Color(Color("3a3448").lerp(Color("4fae5a"), k), a))
	var kx := roundf(r.position.x + 1.0 + 8.0 * k)
	ci.draw_rect(Rect2(kx, r.position.y + 1, 5, 5), Color(CREAM, a))
	ci.draw_rect(Rect2(kx, r.position.y + 5, 5, 1), Color(MUTED.darkened(0.3), a))


# Menu animation state that callers don't keep: per key, the value shown and
# when it was last drawn (eased), and the last text and when it changed
# (value_flash). A key not drawn for a moment (a panel just opened) snaps.
static var _anim := {}
static var _flash := {}
const ANIM_SNAP_MS := 200


## The shown value for `key`, moved toward `target` at `speed` per second
## since it was last drawn.
static func eased(key: String, target: float, speed := 9.0) -> float:
	var now := Time.get_ticks_msec()
	var st: Array = _anim.get(key, [target, now])
	var gap := now - int(st[1])
	var v := target if gap > ANIM_SNAP_MS else move_toward(float(st[0]), target, gap / 1000.0 * speed)
	_anim[key] = [v, now]
	return v


## 1 right after the text drawn for `key` changes, fading to 0 over 0.3 s.
static func value_flash(key: String, text: String) -> float:
	var now := Time.get_ticks_msec()
	var st: Array = _flash.get(key, [text, now, -100000])
	var changed := int(st[2])
	if str(st[0]) != text and now - int(st[1]) <= ANIM_SNAP_MS:
		changed = now
	_flash[key] = [text, now, changed]
	return clampf(1.0 - (now - changed) / 300.0, 0.0, 1.0)


## A setting's value, right-aligned at `right` in gold; it flashes toward
## white and hops a pixel when it changes.
static func value_text(ci: CanvasItem, right: Vector2, key: String, text: String, a: float = 1.0) -> void:
	var f := value_flash(key, text)
	PixelText.draw_outlined(ci, Vector2(right.x - PixelText.width(text), right.y - roundf(f)), text, Color(GOLD.lerp(Color.WHITE, f * 0.8), a), Color(INK, a))


## Options > Graphics (fidelity)'s value, right-aligned at `right`: a meter of
## four rising bars (lit up to the current step) and the step's name. The
## meter sits at a fixed place, so a click on a bar sets that step
## (fidelity_at).
const FIDELITY_NAME_W := 28.0    # the widest step name ("Medium")


static func fidelity_meter_x(right_x: float) -> float:
	return right_x - FIDELITY_NAME_W - 19.0


static func fidelity_value(ci: CanvasItem, right: Vector2, a: float = 1.0) -> void:
	value_text(ci, right, "Graphics", Game.fidelity_label(), a)
	var x0 := fidelity_meter_x(right.x)
	for i in Game.FIDELITY_NAMES.size():
		var h := 3.0 + i * 1.5
		var r := Rect2(x0 + i * 4, right.y + 8 - h, 3, h)
		ci.draw_rect(r.grow(1), Color(INK, a))
		ci.draw_rect(r, Color(GOLD if i <= Game.fidelity() else Color("3a3448"), a))


## Mouse: the Graphics step under a click at x on a meter drawn by
## fidelity_value() at right_x, or -1 off the meter.
static func fidelity_at(x: float, right_x: float) -> int:
	var x0 := fidelity_meter_x(right_x)
	if x < x0 - 1.0 or x >= x0 + Game.FIDELITY_NAMES.size() * 4.0:
		return -1
	return clampi(floori((x - x0 + 1.0) / 4.0), 0, Game.FIDELITY_NAMES.size() - 1)


## Mouse: the value (0..1, in tenths) a click at x sets on a slider drawn at
## x0 by slider(): up to the bar clicked, 0 just left of the first. -1 when
## the click is off the slider.
static func slider_at(x: float, x0: float) -> float:
	if x < x0 - 4.0 or x >= x0 + 40.0:
		return -1.0
	return clampf(floorf((x - x0) / 4.0) + 1.0, 0.0, 10.0) / 10.0


static func slider(ci: CanvasItem, pos: Vector2, v: float, a: float = 1.0) -> void:
	var n := 10
	var lit := int(round(v * n))
	for i in n:
		var r := Rect2(pos.x + i * 4, pos.y + 6 - (1 + i / 2), 3, 1 + i / 2)
		r.size.y = 2 + i * 0.5
		r.position.y = pos.y + 7 - r.size.y
		ci.draw_rect(r.grow(1), Color(INK, a))
		ci.draw_rect(r, Color(GOLD if i < lit else Color("3a3448"), a))


## Diamond screen wipe. k: 0 clear .. 1 covered. dir flips the sweep.
static func wipe(ci: CanvasItem, k: float, dir: float = 1.0, col: Color = Color("0d0a14")) -> void:
	if k <= 0.0:
		return
	if k >= 1.0:
		ci.draw_rect(Rect2(0, 0, 320, 180), col)
		return
	var size := 20.0
	for gy in range(0, 11):
		for gx in range(0, 18):
			var cx := gx * size + (size / 2.0 if gy % 2 == 1 else 0.0)
			var cy := gy * size
			var order := (gx + gy) / 27.0 if dir > 0.0 else 1.0 - (gx + gy) / 27.0
			var s := clampf((k * 1.6 - order * 0.6), 0.0, 1.0) * size * 0.75
			if s < 0.75:
				continue
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - s), Vector2(cx + s, cy), Vector2(cx, cy + s), Vector2(cx - s, cy)]), col)


## Little gold bell (used as an icon / on the logo cap tips).
static func bell(ci: CanvasItem, c: Vector2, angle: float = 0.0, s: float = 1.0) -> void:
	ci.draw_set_transform(c.round(), angle, Vector2(s, s))
	ci.draw_circle(Vector2(0, 0.5), 3.4, INK)
	ci.draw_circle(Vector2(0, 0), 2.6, GOLD)
	ci.draw_rect(Rect2(-2.6, 0, 5.2, 2.2), GOLD_DK)
	ci.draw_rect(Rect2(-1.5, -1.5, 1, 1), Color("fff4b0"))
	ci.draw_rect(Rect2(-0.5, 2.2, 1, 1.2), INK)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Procedural campfire: stones, crossed logs, three flickering flame tongues.
static func campfire(ci: CanvasItem, base: Vector2, t: float) -> void:
	var b := base.round()
	# stones
	for i in 5:
		var sx := -9.0 + i * 4.5
		ci.draw_rect(Rect2(b.x + sx - 1, b.y - 2, 4, 3), INK)
		ci.draw_rect(Rect2(b.x + sx, b.y - 2, 3, 2), Color("6a6478"))
		ci.draw_rect(Rect2(b.x + sx, b.y - 2, 2, 1), Color("9a94a8"))
	# logs
	for sgn in [-1.0, 1.0]:
		var p0 := b + Vector2(-7 * sgn, -1)
		var p1 := b + Vector2(5 * sgn, -5)
		ci.draw_line(p0, p1, INK, 4.0)
		ci.draw_line(p0, p1, Color("5a3420"), 2.0)
		ci.draw_line(p0 + Vector2(0, -1), p1 + Vector2(0, -1), Color("8a5634"), 1.0)
	# flames: outer, mid, core
	var layers := [[Color("d8342a"), 1.0, 0.0], [Color("ff8a2a"), 0.72, 1.7], [Color("ffd860"), 0.45, 3.1], [Color("fffbe0"), 0.22, 4.4]]
	for L in layers:
		var col: Color = L[0]
		var sc: float = L[1]
		var ph: float = L[2]
		var hgt := (13.0 + 2.5 * sin(t * 13.0 + ph) + 1.5 * sin(t * 21.0 + ph * 2.0)) * sc
		var wid := 6.0 * sc + 0.6
		var sway := sin(t * 7.0 + ph) * 1.6 * sc
		var pts := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var a := PI * i / n
			pts.append(b + Vector2(cos(a) * wid, -3.0 + sin(a) * 2.0 * sc))
		pts.append(b + Vector2(-wid * 0.6 + sway * 0.4, -3.0 - hgt * 0.55))
		pts.append(b + Vector2(sway, -3.0 - hgt))
		pts.append(b + Vector2(wid * 0.55 + sway * 0.6, -3.0 - hgt * 0.5))
		var out := PackedVector2Array()
		for p in pts:
			out.append(p.round())
		ci.draw_colored_polygon(out, col)


# ---------------------------------------------------------------- logo

const LOGO_GLYPHS := {
	"J": [
		"..#######",
		"..#######",
		".....###.",
		".....###.",
		".....###.",
		".....###.",
		".....###.",
		".....###.",
		"##...###.",
		"###.####.",
		".######..",
		"..####...",
	],
	"E": [
		"#########",
		"#########",
		"###......",
		"###......",
		"###......",
		"#######..",
		"#######..",
		"###......",
		"###......",
		"###......",
		"#########",
		"#########",
	],
	"S": [
		"..######.",
		".########",
		"###....##",
		"###......",
		"####.....",
		".#######.",
		"..#######",
		".....####",
		"......###",
		"##....###",
		"########.",
		".######..",
	],
	"T": [
		"###########",
		"###########",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
	],
}

const LOGO_SCALE := 2
const LOGO_EXTRUDE := 3
static var _logo: Array = []


## Returns [{tex, w, h}] for J E S T E; each texture includes outline and
## extrusion margins (2 px left/top, 2 + LOGO_EXTRUDE right/bottom).
static func logo_letters() -> Array:
	if not _logo.is_empty():
		return _logo
	var fill := [Color("ffffff"), Color("fff6dc"), Color("ffe7a0"), Color("f8cc5a"), Color("eaa83e"), Color("d8843a"), Color("b8602a")]
	for ch in ["J", "E", "S", "T", "E"]:
		var g: Array = LOGO_GLYPHS[ch]
		var gw: int = (g[0] as String).length() * LOGO_SCALE
		var gh: int = g.size() * LOGO_SCALE
		var m := 2
		var W := gw + m * 2 + LOGO_EXTRUDE
		var H := gh + m * 2 + LOGO_EXTRUDE
		var mask := PackedByteArray()
		mask.resize(W * H)
		for y in gh:
			var row: String = g[y / LOGO_SCALE]
			for x in gw:
				if row[x / LOGO_SCALE] == "#":
					mask[(y + m) * W + x + m] = 1
		var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var at := func(x: int, y: int) -> int:
			if x < 0 or y < 0 or x >= W or y >= H:
				return 0
			return mask[y * W + x]
		# extrusion (deep crimson, darker further back)
		for e in range(LOGO_EXTRUDE, 0, -1):
			for y in H:
				for x in W:
					if at.call(x - e, y - e) == 1 and at.call(x, y) == 0:
						img.set_pixel(x, y, Color("5a1028") if e > 1 else Color("8a1e3a"))
		# outline around letter + extrusion
		var occ := func(x: int, y: int) -> bool:
			if x < 0 or y < 0 or x >= W or y >= H:
				return false
			return img.get_pixel(x, y).a > 0.0 or mask[y * W + x] == 1
		var outline := Image.create(W, H, false, Image.FORMAT_RGBA8)
		outline.fill(Color(0, 0, 0, 0))
		for y in H:
			for x in W:
				if occ.call(x, y):
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if occ.call(x + d.x, y + d.y):
						outline.set_pixel(x, y, INK)
						break
		# fill: vertical gradient with bevel highlight / shadow
		for y in H:
			for x in W:
				if mask[y * W + x] == 0:
					continue
				var ty := float(y - m) / float(gh - 1)
				var bay: int = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][(y % 4) * 4 + (x % 4)]
				var idx := int(floor(ty * 5.0 + bay / 16.0)) + 1
				if at.call(x, y - 1) == 0:
					idx = 0
				elif at.call(x, y - 2) == 0:
					idx = mini(idx, 1)
				if at.call(x, y + 1) == 0:
					idx = 6
				elif at.call(x + 1, y) == 0:
					idx = maxi(idx, 5)
				elif at.call(x - 1, y) == 0:
					idx = maxi(idx - 1, 1)
				img.set_pixel(x, y, fill[clampi(idx, 0, 6)])
		for y in H:
			for x in W:
				var o := outline.get_pixel(x, y)
				if o.a > 0.0 and img.get_pixel(x, y).a == 0.0:
					img.set_pixel(x, y, o)
		_logo.append({"tex": ImageTexture.create_from_image(img), "w": gw, "h": gh, "m": m})
	return _logo


## Jester cap texture that sits on the J (two horns, red and gold).
static var _cap_tex: Texture2D
static func logo_cap() -> Texture2D:
	if _cap_tex:
		return _cap_tex
	var W := 40
	var H := 26
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var red := [Color("ff8a9a"), Color("e8506a"), Color("c22c48"), Color("8a1830")]
	var gold := [Color("fff4b0"), Color("f8d060"), Color("d8a038"), Color("9a6420")]
	var light := Vector2(-0.6, -0.8).normalized()
	# two floppy points that rise and droop outward: (start, control, end, r0, r1, ramp)
	var horns := [
		[Vector2(23, 21), Vector2(33, -2), Vector2(38, 14), 5.0, 1.4, gold],
		[Vector2(17, 21), Vector2(5, -3), Vector2(2, 14), 5.5, 1.4, red],
	]
	for hn in horns:
		for i in 61:
			var t := i / 60.0
			var a0: Vector2 = hn[0]
			var cc: Vector2 = hn[1]
			var e: Vector2 = hn[2]
			var p := a0.lerp(cc, t).lerp(cc.lerp(e, t), t)
			var r: float = lerpf(hn[3], hn[4], t)
			var ramp: Array = hn[5]
			for y in range(int(p.y - r) - 1, int(p.y + r) + 2):
				for x in range(int(p.x - r) - 1, int(p.x + r) + 2):
					if x < 0 or y < 0 or x >= W or y >= H:
						continue
					var d := Vector2(x + 0.5 - p.x, y + 0.5 - p.y)
					if d.length() > r:
						continue
					var nz := sqrt(maxf(0.0, 1.0 - d.length_squared() / (r * r)))
					var lum := d.x / r * light.x + d.y / r * light.y + nz * 0.6
					var k := 0 if lum > 0.85 else (1 if lum > 0.35 else (2 if lum > -0.1 else 3))
					img.set_pixel(x, y, ramp[k])
	# band across the base, diamonds alternating
	for y in range(19, 25):
		for x in range(9, 31):
			var k := 0 if y == 19 else (1 if y < 23 else 3)
			var c: Color = gold[k] if ((x - 9) / 4) % 2 == 0 else red[k]
			img.set_pixel(x, y, c)
	var out := img.duplicate()
	for y in H:
		for x in W:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx: int = x + d.x
				var yy: int = y + d.y
				if xx >= 0 and yy >= 0 and xx < W and yy < H and img.get_pixel(xx, yy).a > 0.0:
					out.set_pixel(x, y, INK)
					break
	_cap_tex = ImageTexture.create_from_image(out)
	return _cap_tex


## Total logo width in pixels (letters + 2px spacing).
static func logo_width() -> int:
	var w := 0
	for L in logo_letters():
		w += int(L.w) + 2
	return w - 2
