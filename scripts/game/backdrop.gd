class_name Backdrop
extends Node2D
## Parallax background (drawn in screen space inside a CanvasLayer) plus
## chapter-specific ambient particles (snow, petals, embers, bubbles...).
## Options > Graphics sets how much of it is drawn: Low drops the fog bands
## and light shafts and two thirds of the particles, Medium the shafts and a
## third, and Ultra adds a farther, fainter layer of particles, depth of field
## on distant ridges and a few soft motes in front (draw_motes).

var chapter := 0
var cam_pos := Vector2.ZERO
var time := 0.0
var ambient: Array = []
var ambient_kind := "none"
var wind := Vector2.ZERO
var tint := Color.WHITE
var fidelity := Game.FIDELITY_HIGH
var motes: Array = []
const AMBIENT_N := [20, 40, 60, 60]   # Ultra adds 60 farther ones (setup)
static var _dof := {}                 # [texture, halvings] -> blurred copy
# Ultra's depth of field is for far layers that are plain distant ridges; the
# title's mountain, the balloons, the stained glass and the stalactites are
# set pieces and stay sharp.
const DOF_CHAPTERS := [1, 3, 4, 7, 8]


func _ready() -> void:
	Game.fidelity_changed.connect(_on_fidelity_changed)


func _on_fidelity_changed() -> void:
	setup(chapter)


func setup(ch: int) -> void:
	chapter = ch
	fidelity = Game.fidelity()
	ambient.clear()
	motes.clear()
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
	ambient.resize(AMBIENT_N[fidelity])   # every step draws the same numbers, so the rest of the game's stay in step
	if fidelity >= Game.FIDELITY_ULTRA:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + chapter
		for i in 60:   # a farther layer: smaller, slower, fainter
			ambient.append({"p": Vector2(rng.randf() * 320, rng.randf() * 180), "s": rng.randf_range(0.25, 0.5), "ph": rng.randf() * TAU})
		for i in 7:
			motes.append({"p": Vector2(rng.randf() * 400 - 40, rng.randf() * 180), "r": rng.randf_range(7.0, 15.0), "ph": rng.randf() * TAU})


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
	for m in motes:
		m.p += (Vector2(sin(time * 0.3 + m.ph) * 4.0, -3.0 + cos(time * 0.4 + m.ph) * 2.0) + wind * 0.3) * delta
	queue_redraw()


func _draw() -> void:
	var sky := Art.bg(chapter, "sky")
	if sky:
		draw_texture(sky, Vector2.ZERO, tint)
	var ultra := fidelity >= Game.FIDELITY_ULTRA
	_layer(_soft(Art.bg(chapter, "far"), 1) if ultra and chapter in DOF_CHAPTERS else Art.bg(chapter, "far"), 0.06, 0.03)
	if fidelity >= Game.FIDELITY_HIGH:
		_shafts()
	_layer(Art.bg(chapter, "mid"), 0.16, 0.08)
	if fidelity >= Game.FIDELITY_MEDIUM:
		_fog(0)
	_layer(Art.bg(chapter, "near"), 0.32, 0.14)
	if fidelity >= Game.FIDELITY_MEDIUM:
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


## Ultra's depth of field: a backdrop layer blurred by halving it `n` times
## and scaling it back up (alpha edges bled first so outlines don't darken).
static func _soft(tex: Texture2D, n: int) -> Texture2D:
	if tex == null:
		return null
	var key := [tex.get_rid(), n]
	if _dof.has(key):
		return _dof[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.fix_alpha_edges()
	var w := img.get_width()
	var h := img.get_height()
	for i in n:
		img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var out := ImageTexture.create_from_image(img)
	_dof[key] = out
	return out


const MOTE_COL := {
	0: Color(1.0, 0.85, 0.6), 1: Color(0.75, 0.85, 1.0), 2: Color(1.0, 0.7, 0.95), 3: Color(1.0, 0.8, 0.55),
	4: Color(0.95, 0.97, 1.0), 5: Color(0.7, 1.0, 1.0), 6: Color(0.55, 1.0, 0.9), 7: Color(1.0, 0.92, 0.85), 8: Color(1.0, 0.9, 0.8),
}
static var _mote_tex: Texture2D


## Ultra: a few large, faint, out-of-focus motes drifting in front of the
## room (parallax faster than the room), drawn by the level above its stage.
func draw_motes(ci: CanvasItem) -> void:
	if motes.is_empty():
		return
	if _mote_tex == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
				var v := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, floorf(sqrt(v) * 5.0) / 5.0))
		_mote_tex = ImageTexture.create_from_image(img)
	var col: Color = MOTE_COL.get(chapter, MOTE_COL[1])
	for m in motes:
		var p := Vector2(fposmod(m.p.x - cam_pos.x * 0.45, 400.0) - 40.0, fposmod(m.p.y - cam_pos.y * 0.25, 220.0) - 20.0)
		var r: float = m.r
		var a := 0.05 + 0.025 * sin(time * 0.8 + m.ph)
		ci.draw_texture_rect(_mote_tex, Rect2((p - Vector2(r, r)).round(), Vector2(r, r) * 2.0), false, Color(col, a))


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
## At Ultra every chapter gets them (moonlight, spotlights, the cave's glow),
## with a soft edge either side.
const ULTRA_SHAFTS := {1: Color(0.75, 0.85, 1, 0.04), 3: Color(1, 0.8, 0.6, 0.04), 6: Color(0.5, 1, 0.9, 0.035), 8: Color(1, 0.95, 0.8, 0.04)}


func _shafts() -> void:
	var ultra := fidelity >= Game.FIDELITY_ULTRA
	if not chapter in [0, 2, 4, 5, 7] and not (ultra and ULTRA_SHAFTS.has(chapter)):
		return
	var col := Color(1, 0.92, 0.75, 0.05)
	if chapter == 2:
		col = Color(1, 0.6, 0.9, 0.05)
	elif chapter == 5:
		col = Color(0.7, 0.95, 1, 0.05)
	elif ULTRA_SHAFTS.has(chapter):
		col = ULTRA_SHAFTS[chapter]
	for i in 4:
		var x := fposmod(i * 97.0 + time * 3.0 - cam_pos.x * 0.04, 420.0) - 50.0
		var wv := 14.0 + 6.0 * sin(time * 0.4 + i)
		var a := col.a * (0.6 + 0.4 * sin(time * 0.7 + i * 1.7))
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + wv, 0), Vector2(x + wv + 60, 180), Vector2(x + 60, 180)])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, a))
		if ultra:   # a soft edge: two wider, fainter copies
			for k in [3.0, 6.0]:
				var e := PackedVector2Array([Vector2(x - k, 0), Vector2(x + wv + k, 0), Vector2(x + wv + 60 + k, 180), Vector2(x + 60 - k, 180)])
				draw_colored_polygon(e, Color(col.r, col.g, col.b, a * 0.35))


func _layer(tex: Texture2D, fx: float, fy: float) -> void:
	if tex == null:
		return
	var w := tex.get_width()
	var ox := -fposmod(cam_pos.x * fx, w)
	var oy := clampf(-cam_pos.y * fy * 0.3, -20.0, 10.0)
	draw_texture(tex, Vector2(roundf(ox), roundf(oy)), tint)
	draw_texture(tex, Vector2(roundf(ox + w), roundf(oy)), tint)
