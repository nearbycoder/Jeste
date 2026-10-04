class_name Lighting
extends Node2D
## Additive glow pass drawn over the room: soft, pixel-stepped light pools for
## the player, collectibles and light-emitting decorations. Darker chapters
## get stronger lights.

var world: World
var room_view: RoomView
var player_view: PlayerView
var chapter := 0
var time := 0.0
var strength := 1.0
static var _light_tex: Texture2D


static func light_texture() -> Texture2D:
	if _light_tex:
		return _light_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var v := clampf(1.0 - d, 0.0, 1.0)
			v = v * v
			v = floorf(v * 6.0) / 6.0   # stepped falloff keeps the pixel-art look
			img.set_pixel(x, y, Color(1, 1, 1, v))
	_light_tex = ImageTexture.create_from_image(img)
	return _light_tex


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func setup(ch: int) -> void:
	chapter = ch
	strength = {0: 0.7, 1: 1.25, 2: 1.2, 3: 1.25, 4: 0.55, 5: 1.15, 6: 1.35, 7: 0.75, 8: 0.6}.get(ch, 1.0)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _light(pos: Vector2, radius: float, col: Color, a: float) -> void:
	var tex := light_texture()
	var r := radius
	draw_texture_rect(tex, Rect2(pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, Color(col.r, col.g, col.b, a * strength))


func _draw() -> void:
	if world == null or room_view == null or room_view.def == null or world.room != room_view.def:
		return
	var flick := 0.85 + 0.15 * sin(time * 11.0) * sin(time * 7.3)
	# player
	if player_view and player_view.visible_player:
		var pc := world.player_center() + player_view.position - position
		var dashing := world.state == World.ST_DASH or world.state == World.ST_DREAM
		_light(pc, 26.0 if dashing else 18.0, player_view.cap_col, 0.30 if dashing else 0.14)
		if player_view.flash > 0.1:
			_light(pc, 30.0, Color.WHITE, 0.25 * player_view.flash)
	# collectibles & objects
	for i in world.gem_x.size():
		if world.gem_t[i] == 0:
			var col := Color("ff7ab8") if world.gem_twin[i] == 1 else Color("7aff8a")
			_light(Vector2(world.gem_x[i], world.gem_y[i]), 14.0, col, 0.28)
	for i in world.berry_x.size():
		if world.berry_s[i] == 0:
			_light(Vector2(world.berry_x[i], world.berry_y[i]), 11.0, Color("ffb050"), 0.22)
	for i in world.bell_x.size():
		if world.bell_s[i] == 0:
			_light(Vector2(world.bell_x[i], world.bell_y[i]), 22.0, Color("ffd27a"), 0.32 + 0.08 * sin(time * 3.0))
	for i in world.golden_x.size():
		if world.golden_s[i] == 0:
			_light(Vector2(world.golden_x[i], world.golden_y[i]), 16.0, Color("ffe066"), 0.3)
	for i in world.balloon_x.size():
		if world.balloon_t[i] == 0:
			_light(Vector2(world.balloon_x[i], world.balloon_y[i]), 10.0, Color("ff6a7a"), 0.18)
	for i in world.bumper_x.size():
		_light(Vector2(world.bumper_x[i], world.bumper_y[i]), 14.0, Color("6aa0ff"), 0.15 + (0.3 if world.bumper_t[i] > 0 else 0.0))
	for e in room_view.def.entities:
		if e.type == "end" and str(room_view.def.meta.get("end_style", "flag")) == "fire":
			_light(Vector2(e.cx * 8 + 4, e.cy * 8), 40.0, Color("ff9a3c"), 0.35 * flick)
		elif e.type == "key" :
			pass
	# light-emitting decorations
	for d in room_view.decor:
		var p: Vector2 = Vector2(d[1]) * 8.0 + Vector2(4, 4)
		match d[0]:
			"l": _light(p, 22.0, Color("ffcf6a"), 0.26 * flick)
			"c": _light(p + Vector2(0, -2), 14.0, Color("ffb050"), 0.22 * flick)
			"a": _light(p + Vector2(0, -3), 22.0, Color("ff8a3a"), 0.30 * flick)
			"u": _light(p, 14.0, Color("3fe0c0"), 0.25 + 0.05 * sin(time * 2.0 + p.x))
			"q": _light(p, 12.0, Color("8ab4ff"), 0.10)
