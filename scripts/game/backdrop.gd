class_name Backdrop
extends Node2D
## Parallax background (drawn in screen space inside a CanvasLayer) plus
## chapter-specific ambient particles (snow, petals, embers, bubbles...).

var chapter := 0
var cam_pos := Vector2.ZERO
var time := 0.0
var ambient: Array = []
var ambient_kind := "none"
var wind := Vector2.ZERO
var tint := Color.WHITE


func setup(ch: int) -> void:
	chapter = ch
	ambient.clear()
	match ch:
		0: ambient_kind = "leaves"
		1: ambient_kind = "snow"
		2: ambient_kind = "stars"
		3: ambient_kind = "confetti"
		4: ambient_kind = "wind"
		5: ambient_kind = "dust"
		6: ambient_kind = "bubbles"
		7: ambient_kind = "snow"
		8: ambient_kind = "petals"
	for i in 60:
		ambient.append({"p": Vector2(randf() * 320, randf() * 180), "s": randf_range(0.5, 1.0), "ph": randf() * TAU})


func _process(delta: float) -> void:
	time += delta
	for a in ambient:
		var v := Vector2.ZERO
		match ambient_kind:
			"snow": v = Vector2(-8 + sin(time + a.ph) * 6, 18) * a.s
			"leaves": v = Vector2(-14 + sin(time * 2 + a.ph) * 10, 10) * a.s
			"stars": v = Vector2(0, -4) * a.s
			"confetti": v = Vector2(sin(time * 3 + a.ph) * 12, 16) * a.s
			"wind": v = Vector2(-160, sin(time * 4 + a.ph) * 6) * a.s
			"dust": v = Vector2(sin(time * 0.5 + a.ph) * 3, -2) * a.s
			"bubbles": v = Vector2(sin(time * 2 + a.ph) * 6, -14) * a.s
			"petals": v = Vector2(-10 + sin(time * 2 + a.ph) * 8, 9) * a.s
		v += wind * 0.5
		a.p += v * delta
		a.p.x = fposmod(a.p.x, 320.0)
		a.p.y = fposmod(a.p.y, 180.0)
	queue_redraw()


func _draw() -> void:
	var sky := Art.bg(chapter, "sky")
	if sky:
		draw_texture(sky, Vector2.ZERO, tint)
	_layer(Art.bg(chapter, "far"), 0.12, 0.05)
	_layer(Art.bg(chapter, "near"), 0.3, 0.12)
	for a in ambient:
		var p: Vector2 = a.p
		var s: float = a.s
		match ambient_kind:
			"snow":
				draw_rect(Rect2(int(p.x), int(p.y), 1 + int(s > 0.8), 1 + int(s > 0.8)), Color(1, 1, 1, 0.5 + 0.4 * s))
			"leaves":
				draw_rect(Rect2(int(p.x), int(p.y), 2, 1), Color("e0884a") if s > 0.75 else Color("c8644a"))
			"stars":
				var tw := 0.5 + 0.5 * sin(time * 3 + a.ph)
				draw_rect(Rect2(int(p.x), int(p.y), 1, 1), Color(1, 0.85, 1, tw * s))
			"confetti":
				var cols := [Color("ff5a6e"), Color("ffd25a"), Color("5ad2ff"), Color("8aff6e")]
				draw_rect(Rect2(int(p.x), int(p.y), 1 + int(sin(time * 6 + a.ph) > 0), 1), cols[int(a.ph * 10) % 4])
			"wind":
				draw_rect(Rect2(int(p.x), int(p.y), int(6 * s), 1), Color(1, 1, 1, 0.25 * s))
			"dust":
				draw_rect(Rect2(int(p.x), int(p.y), 1, 1), Color(0.8, 1, 1, 0.35 * s))
			"bubbles":
				draw_arc(p, 1.5 * s + 0.5, 0, TAU, 8, Color(0.6, 1, 0.95, 0.4 * s), 1.0)
			"petals":
				draw_rect(Rect2(int(p.x), int(p.y), 2, 1), Color("ffb8d8"))


func _layer(tex: Texture2D, fx: float, fy: float) -> void:
	if tex == null:
		return
	var w := tex.get_width()
	var ox := -fposmod(cam_pos.x * fx, w)
	var oy := clampf(-cam_pos.y * fy * 0.3, -20.0, 10.0)
	draw_texture(tex, Vector2(roundf(ox), roundf(oy)), tint)
	draw_texture(tex, Vector2(roundf(ox + w), roundf(oy)), tint)
