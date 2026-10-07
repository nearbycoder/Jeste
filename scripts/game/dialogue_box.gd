class_name DialogueBox
extends Node2D
## Runs a cutscene script: typewriter dialogue with portraits plus simple
## commands delegated to the Level (shake, flash, npc visibility...).

signal finished(id: String)

var level: Node
var active := false
var script_id := ""
var lines: Array = []
var idx := 0
var cur: Dictionary = {}
var shown := 0.0
var wait := 0.0
var time := 0.0
var box_open := 0.0
var blip_timer := 0
var wrapped := PackedStringArray()
const CPS := 45.0
## Holding Pause for SKIP_HOLD seconds skips the rest of the scene.
const SKIP_HOLD := 0.6
var skip_t := 0.0
var skip_armed := false        # Pause was pressed during this scene (not held over from before)
var skipping := false          # running the remaining lines instantly
const BOX := Rect2(8, 11, 304, 48)


func play(id: String) -> void:
	skip_t = 0.0
	skip_armed = false
	lines = Story.get_script_lines(id)
	script_id = id
	idx = -1
	active = true
	_next()


func _next() -> void:
	while true:
		idx += 1
		if idx >= lines.size():
			_finish()
			return
		var l: Dictionary = lines[idx]
		if l.type == "say":
			cur = l.duplicate()
			# {jump} / {dash} / {grab} show the player's current key bindings
			var txt: String = cur.text
			for a in ["jump", "dash", "grab"]:
				txt = txt.replace("{%s}" % a, Game.key_label(a))
			cur.text = txt
			shown = 0.0
			wrapped = PixelText.wrap(txt, int(BOX.size.x - 52))
			return
		var w := 0.0
		if level and level.has_method("cutscene_command"):
			w = level.cutscene_command(l.cmd, l.args)
		if w > 0.0:
			wait = w
			cur = {}
			return


func _finish() -> void:
	active = false
	cur = {}
	finished.emit(script_id)


## Runs the remaining lines instantly (fast / test mode, or a held skip).
## Commands still run, so the scene leaves the world exactly as reading it would.
func skip_all() -> void:
	skipping = true
	while active:
		wait = 0.0
		_next()
	skipping = false


func _total_chars() -> int:
	var n := 0
	for l in wrapped:
		n += l.length()
	return n


func _process(delta: float) -> void:
	time += delta
	var target := 1.0 if (active and not cur.is_empty()) else 0.0
	box_open = move_toward(box_open, target, delta * 6.0)
	if not active:
		queue_redraw()
		return
	if skip_armed and Input.is_action_pressed("pause"):
		skip_t += delta / maxf(Engine.time_scale, 0.01)
		if skip_t >= SKIP_HOLD:
			skip_t = 0.0
			skip_armed = false
			Sfx.play("text_next")
			skip_all()
			queue_redraw()
			return
	else:
		skip_t = maxf(skip_t - delta * 3.0, 0.0)
	if wait > 0.0:
		wait -= delta
		if wait <= 0.0:
			wait = 0.0
			_next()
	elif not cur.is_empty():
		var before := int(shown)
		shown = minf(shown + CPS * delta, _total_chars())
		if int(shown) != before:
			blip_timer -= 1
			if blip_timer <= 0:
				blip_timer = 3
				Sfx.play_voice(cur.who)
	queue_redraw()


func handle_input(ev: InputEvent) -> bool:
	if not active:
		return false
	if ev is InputEventMouse:
		ev = UIKit.click_action(ev)   # a left click reads as Confirm
		if ev == null:
			return true
	if ev.is_action_pressed("pause"):
		skip_armed = true
		return true
	if cur.is_empty():
		return true
	if ev.is_action_pressed("confirm") or ev.is_action_pressed("dash"):
		if shown < _total_chars():
			shown = _total_chars()
		else:
			Sfx.play("text_next")
			_next()
	return true


func _draw() -> void:
	if active and box_open > 0.5:
		_draw_skip_hint(clampf((box_open - 0.5) * 2.0, 0.0, 1.0))
	if box_open <= 0.0 or cur.is_empty():
		return
	var who: String = cur.who
	var r := BOX
	# slide down from above with a small overshoot
	var k := ease(box_open, 0.4)
	var over := sin(k * PI) * 3.0 * (1.0 - k * 0.5)
	r.position.y = lerpf(-r.size.y - 4.0, r.position.y, k) + (over if box_open < 1.0 else 0.0)
	var a := clampf(box_open * 1.5, 0.0, 1.0)
	# shared framed panel (accent tinted per speaker)
	var accent := UIKit.GOLD
	if who == "grin":
		accent = Color("e8506a")
	elif who == "sign" or who == "narrator":
		accent = Color("c8b89a")
	UIKit.panel(self, Rect2(r.position.round(), r.size), a, accent)
	if box_open < 0.9:
		return
	var left_side := who == "mira" or who == "nana"
	var has_port := Art.has_portrait(who)
	var text_x := r.position.x + 8
	var typing := shown < _total_chars()
	if has_port:
		var expr: String = cur.expr
		var blink := fmod(time + (0.7 if left_side else 0.0), 3.3) < 0.13
		var talk := typing and int(time * 11.0) % 2 == 0
		var variant := (1 if blink else 0) + (2 if talk else 0)
		var pr := Art.portrait_rect(who, expr, variant)
		var px := r.position.x + 6 if left_side else r.end.x - 38
		var bob := roundf(sin(time * 2.2) * 0.6) + (-1.0 if talk else 0.0)
		var frame_r := Rect2(px - 1, r.position.y + 8, 34, 34)
		draw_rect(frame_r, Color(0.14, 0.09, 0.2))
		UIKit.frame(self, frame_r.grow(1), UIKit.INK)
		UIKit.frame(self, frame_r, Color(accent, 0.8))
		_draw_portrait(Rect2(px, r.position.y + 9 + bob, 32, 32), pr, who)
		if left_side:
			text_x = px + 40
	var name: String = Story.NAMES.get(who, who.capitalize())
	if name != "":
		# name plate
		var nw := PixelText.width(name) + 10
		var plate := Rect2(roundf(text_x - 4), roundf(r.position.y - 5), nw, 12)
		var pc := UIKit.CRIMSON.darkened(0.25) if who != "grin" else Color("5a1830")
		draw_rect(plate.grow(1), UIKit.INK)
		draw_rect(plate, pc)
		draw_rect(Rect2(plate.position.x, plate.position.y, plate.size.x, 1), pc.lightened(0.35))
		PixelText.draw_outlined(self, Vector2(plate.position.x + 5, plate.position.y + 2), name, UIKit.CREAM, UIKit.INK)
	var remaining := int(shown)
	var y := r.position.y + (12 if name != "" else 8)
	var col := Color.WHITE if who != "sign" else Color("d0e8ff")
	if who == "grin":
		col = Color("ffb0c0")
	elif who == "narrator":
		col = Color("e8dcc8")
	var shaky: bool = cur.expr in ["angry", "frantic", "scared"]
	var drawn := 0
	for line in wrapped:
		if remaining <= 0:
			break
		var n := mini(remaining, line.length())
		var x := text_x
		for i in n:
			var ch := line[i]
			var off := Vector2.ZERO
			var idx := drawn + i
			# newest letters pop up into place
			var age := shown - idx
			if age < 3.0:
				off.y = -roundf((3.0 - age) * 0.5)
			if shaky and ch != " ":
				off.y += roundf(sin(time * 24.0 + idx * 1.7) * 0.6)
			PixelText.draw(self, Vector2(x, y) + off, ch, col, Color(0, 0, 0, 0.7))
			x += PixelText.char_width(ch) + 1
		drawn += line.length()
		remaining -= line.length()
		y += PixelText.LINE_H
	if not typing:
		var bob2 := int(time * 4.0) % 2
		draw_colored_polygon(PackedVector2Array([Vector2(r.end.x - 11, r.end.y - 9 + bob2), Vector2(r.end.x - 5, r.end.y - 9 + bob2), Vector2(r.end.x - 8, r.end.y - 6 + bob2)]), Color("f2c14e"))


## "Hold Esc  Skip" under the box, with a ring that fills while held.
func _draw_skip_hint(a: float) -> void:
	var key := "Start" if Game.using_pad else "Esc"
	var label := "Hold to skip"
	var w := PixelText.width(label)
	var x := BOX.end.x - w - 4
	var y := BOX.end.y + 5
	UIKit.keycap(self, Vector2(x - PixelText.width(key) - 12, y), key, a * 0.75)
	PixelText.draw_outlined(self, Vector2(x, y), label, Color(UIKit.CREAM, a * 0.75), Color(UIKit.INK, a * 0.75))
	if skip_t > 0.0:
		var c := Vector2(x - PixelText.width(key) - 22, y + 5)
		draw_arc(c, 5.0, 0.0, TAU, 20, Color(UIKit.INK, a), 4.0)
		draw_arc(c, 5.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(skip_t / SKIP_HOLD, 0.0, 1.0), 20, Color(UIKit.GOLD, a), 2.0)


func _exit_tree() -> void:
	_mira_tex = null


func _draw_portrait(dst: Rect2, src: Rect2, who: String) -> void:
	var tex := Art.portraits()
	if who == "mira":
		# cap key colour -> jester red
		var img := Art.image("res://assets/sprites/portraits.png")
		var tex2 := _mira_portrait_tex(img)
		draw_texture_rect_region(tex2, dst, src)
	else:
		draw_texture_rect_region(tex, dst, src)


var _mira_tex: Texture2D
func _mira_portrait_tex(img: Image) -> Texture2D:
	if _mira_tex:
		return _mira_tex
	var copy := img.duplicate() as Image
	for y in copy.get_height():
		for x in copy.get_width():
			var c := copy.get_pixel(x, y)
			if c.a > 0.5 and c.is_equal_approx(Color.html("#ff00ff")):
				copy.set_pixel(x, y, Color("e03a5a"))
			elif c.a > 0.5 and c.is_equal_approx(Color.html("#c000c0")):
				copy.set_pixel(x, y, Color("9c2440"))
	_mira_tex = ImageTexture.create_from_image(copy)
	return _mira_tex
