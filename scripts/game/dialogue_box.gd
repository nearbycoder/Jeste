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
const BOX := Rect2(8, 6, 304, 50)


func play(id: String) -> void:
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
			cur = l
			shown = 0.0
			wrapped = PixelText.wrap(l.text, int(BOX.size.x - 52))
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


## Runs the remaining lines instantly (fast / test mode).
func skip_all() -> void:
	while active:
		wait = 0.0
		_next()


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
	if box_open <= 0.0 or cur.is_empty():
		return
	var who: String = cur.who
	var r := BOX
	var h := r.size.y * ease(box_open, 0.5)
	var rr := Rect2(r.position.x, r.position.y + (r.size.y - h) / 2.0, r.size.x, h)
	draw_rect(rr, Color(0.05, 0.03, 0.09, 0.94))
	draw_rect(rr, Color("f2c14e"), false, 1.0)
	if box_open < 1.0:
		return
	var left_side := who == "mira" or who == "nana"
	var has_port := Art.has_portrait(who)
	var text_x := r.position.x + 8
	if has_port:
		var expr: String = cur.expr
		var pr := Art.portrait_rect(who, expr)
		var px := r.position.x + 6 if left_side else r.end.x - 38
		var bob := roundf(sin(time * 3.0) * 0.5)
		draw_rect(Rect2(px - 1, r.position.y + 8, 34, 34), Color(0.12, 0.08, 0.18))
		_draw_portrait(Rect2(px, r.position.y + 9 + bob, 32, 32), pr, who)
		if left_side:
			text_x = px + 40
	var name: String = Story.NAMES.get(who, who.capitalize())
	if name != "":
		var nx := text_x
		PixelText.draw(self, Vector2(nx, r.position.y + 4), name, Color("f2c14e"))
	var remaining := int(shown)
	var y := r.position.y + (15 if name != "" else 8)
	var col := Color.WHITE if who != "sign" else Color("d0e8ff")
	if who == "grin":
		col = Color("ffb0c0")
	for line in wrapped:
		if remaining <= 0:
			break
		var shake := Vector2.ZERO
		if cur.expr in ["angry", "frantic", "scared"]:
			shake = Vector2(randi_range(0, 1) * 0.0, 0)
		PixelText.draw(self, Vector2(text_x, y) + shake, line, col, Color(0, 0, 0, 0.7), remaining)
		remaining -= line.length()
		y += PixelText.LINE_H
	if shown >= _total_chars():
		var bob2 := int(time * 4.0) % 2
		draw_colored_polygon(PackedVector2Array([Vector2(r.end.x - 10, r.end.y - 8 + bob2), Vector2(r.end.x - 4, r.end.y - 8 + bob2), Vector2(r.end.x - 7, r.end.y - 5 + bob2)]), Color("f2c14e"))


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
