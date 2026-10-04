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
	_layer(Art.bg(chapter, "far"), 0.06, 0.03)
	_shafts()
	_layer(Art.bg(chapter, "mid"), 0.16, 0.08)
	_fog(0)
	_layer(Art.bg(chapter, "near"), 0.32, 0.14)
	_fog(1)
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


const FOG := {
	0: [Color(0.95, 0.55, 0.5, 0.10), Color(0.25, 0.15, 0.3, 0.12)],
	1: [Color(0.45, 0.5, 0.8, 0.10), Color(0.1, 0.12, 0.25, 0.14)],
	2: [Color(0.9, 0.4, 0.7, 0.10), Color(0.3, 0.08, 0.3, 0.14)],
	3: [Color(0.9, 0.5, 0.4, 0.08), Color(0.2, 0.06, 0.15, 0.14)],
	4: [Color(1, 1, 1, 0.12), Color(0.85, 0.92, 1, 0.10)],
	5: [Color(0.4, 0.8, 0.8, 0.08), Color(0.05, 0.12, 0.14, 0.16)],
	6: [Color(0.2, 0.8, 0.7, 0.07), Color(0.02, 0.08, 0.14, 0.18)],
	7: [Color(1, 0.85, 0.8, 0.14), Color(1, 0.9, 0.95, 0.12)],
	8: [Color(1, 0.95, 0.85, 0.08), Color(0.6, 0.75, 0.5, 0.08)],
}


## Soft horizontal fog bands drifting slowly (pixel-dithered edges).
func _fog(band: int) -> void:
	var col: Color = FOG.get(chapter, FOG[1])[band]
	var base_y := 118.0 if band == 0 else 150.0
	var speed := 4.0 if band == 0 else 9.0
	for x in range(0, 320, 2):
		var wx := x + time * speed + cam_pos.x * (0.12 if band == 0 else 0.3)
		var hgt := 10.0 + 6.0 * sin(wx * 0.021) + 4.0 * sin(wx * 0.053 + 1.3)
		var top := base_y - hgt - clampf(-cam_pos.y * 0.04, -10.0, 10.0)
		draw_rect(Rect2(x, int(top), 2, 180 - int(top)), col)
		draw_rect(Rect2(x, int(top) - 2, 2, 2), Color(col.r, col.g, col.b, col.a * 0.5))


## Slow, faint light shafts for bright / magical chapters.
func _shafts() -> void:
	if not chapter in [0, 2, 4, 5, 7]:
		return
	var col := Color(1, 0.92, 0.75, 0.05)
	if chapter == 2:
		col = Color(1, 0.6, 0.9, 0.05)
	elif chapter == 5:
		col = Color(0.7, 0.95, 1, 0.05)
	for i in 4:
		var x := fposmod(i * 97.0 + time * 3.0 - cam_pos.x * 0.04, 420.0) - 50.0
		var wv := 14.0 + 6.0 * sin(time * 0.4 + i)
		var a := col.a * (0.6 + 0.4 * sin(time * 0.7 + i * 1.7))
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + wv, 0), Vector2(x + wv + 60, 180), Vector2(x + 60, 180)])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, a))


func _layer(tex: Texture2D, fx: float, fy: float) -> void:
	if tex == null:
		return
	var w := tex.get_width()
	var ox := -fposmod(cam_pos.x * fx, w)
	var oy := clampf(-cam_pos.y * fy * 0.3, -20.0, 10.0)
	draw_texture(tex, Vector2(roundf(ox), roundf(oy)), tint)
	draw_texture(tex, Vector2(roundf(ox + w), roundf(oy)), tint)
