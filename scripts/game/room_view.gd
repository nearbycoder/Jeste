class_name RoomView
extends Node2D
## Renders one room: pre-baked static tile layers plus everything dynamic
## (crumble boards, doors, mask blocks, curtains, gondolas, collectibles...).
## All dynamic state is read from the World every frame.

const T := 8

var world: World
var def: RoomDef
var tileset := "town"
var chapter := 0
var tiles_img: Image
var bg_tex: ImageTexture
var fg_tex: ImageTexture
var fake_tex: ImageTexture
var fake_alpha := {}
var time := 0.0
var level: Node = null   # Level, for follower positions

# Visual-only state
var spring_anim := {}      # spring index -> frames left
var berry_follow := {}     # berry index -> Vector2 position
var berry_fly := {}        # berry index -> Vector2 position (flying away)
var key_follow := {}       # key index -> Vector2
var golden_follow := Vector2.ZERO
var decor: Array = []      # [char, Vector2i]
var npc_hidden := {}
var npc_face := {}


func build(p_def: RoomDef, p_world: World, p_tileset: String, p_chapter: int) -> void:
	def = p_def
	world = p_world
	tileset = p_tileset
	chapter = p_chapter
	tiles_img = Art.tileset_image(tileset)
	spring_anim.clear()
	berry_follow.clear()
	berry_fly.clear()
	key_follow.clear()
	_bake()
	decor.clear()
	for cy in def.h:
		var row: String = def.rows[cy]
		for cx in def.w:
			var c := row[cx]
			if c in ["f", "l", "c", "t", "s", "x", "m", "j", "a", "r", "u", "q"]:
				decor.append([c, Vector2i(cx, cy)])
	queue_redraw()


func _is_solid_cell(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= def.w or cy >= def.h:
		return true
	var t := def.cells[cy * def.w + cx]
	return t == RoomDef.SOLID or t == RoomDef.SOLID_ALT or t == RoomDef.FAKE


func _is_same(cx: int, cy: int, t: int) -> bool:
	if cx < 0 or cy < 0 or cx >= def.w or cy >= def.h:
		return t == RoomDef.SOLID or t == RoomDef.SOLID_ALT or t == RoomDef.BGWALL
	var c := def.cells[cy * def.w + cx]
	if t == RoomDef.BGWALL:
		return c == RoomDef.BGWALL or c == RoomDef.SOLID or c == RoomDef.SOLID_ALT
	return c == RoomDef.SOLID or c == RoomDef.SOLID_ALT


func _blit_tile(dst: Image, col: int, row: int, cx: int, cy: int) -> void:
	dst.blend_rect(tiles_img, Rect2i(col * T, row * T, T, T), Vector2i(cx * T, cy * T))


func _bake() -> void:
	var w := def.w * T
	var h := def.h * T
	var bg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fk := Image.create(w, h, false, Image.FORMAT_RGBA8)
	bg.fill(Color(0, 0, 0, 0))
	fg.fill(Color(0, 0, 0, 0))
	fk.fill(Color(0, 0, 0, 0))
	var outline := tiles_img.get_pixel(0, 7) if tiles_img else Color.BLACK
	for cy in def.h:
		for cx in def.w:
			var t := def.cells[cy * def.w + cx]
			match t:
				RoomDef.SOLID, RoomDef.SOLID_ALT, RoomDef.FAKE:
					var dst := fk if t == RoomDef.FAKE else fg
					var m := 0
					if _is_solid_cell(cx, cy - 1): m |= 1
					if _is_solid_cell(cx + 1, cy): m |= 2
					if _is_solid_cell(cx, cy + 1): m |= 4
					if _is_solid_cell(cx - 1, cy): m |= 8
					var variant := (cx * 7 + cy * 13) % 2
					var row := variant + (2 if t == RoomDef.SOLID_ALT else 0)
					_blit_tile(dst, m, row, cx, cy)
					# inner corners
					var ox := cx * T
					var oy := cy * T
					if m & 9 == 9 and not _is_solid_cell(cx - 1, cy - 1):
						dst.set_pixel(ox, oy, outline)
					if m & 3 == 3 and not _is_solid_cell(cx + 1, cy - 1):
						dst.set_pixel(ox + 7, oy, outline)
					if m & 12 == 12 and not _is_solid_cell(cx - 1, cy + 1):
						dst.set_pixel(ox, oy + 7, outline)
					if m & 6 == 6 and not _is_solid_cell(cx + 1, cy + 1):
						dst.set_pixel(ox + 7, oy + 7, outline)
				RoomDef.BGWALL:
					var m := 0
					if _is_same(cx, cy - 1, t): m |= 1
					if _is_same(cx + 1, cy, t): m |= 2
					if _is_same(cx, cy + 1, t): m |= 4
					if _is_same(cx - 1, cy, t): m |= 8
					_blit_tile(bg, m, 4, cx, cy)
				RoomDef.JUMPTHRU:
					var l := cx > 0 and def.cells[cy * def.w + cx - 1] == RoomDef.JUMPTHRU
					var r := cx < def.w - 1 and def.cells[cy * def.w + cx + 1] == RoomDef.JUMPTHRU
					var v := 3
					if l and r: v = 1
					elif r: v = 0
					elif l: v = 2
					_blit_tile(fg, v, 5, cx, cy)
				RoomDef.SPIKE_UP:
					_blit_tile(fg, 0, 6, cx, cy)
				RoomDef.SPIKE_DOWN:
					_blit_tile(fg, 1, 6, cx, cy)
				RoomDef.SPIKE_LEFT:
					_blit_tile(fg, 2, 6, cx, cy)
				RoomDef.SPIKE_RIGHT:
					_blit_tile(fg, 3, 6, cx, cy)
			# Background wall behind dynamic blocks and entities looks nicer
			if t in [RoomDef.CRUMBLE, RoomDef.DOOR, RoomDef.CRACKED]:
				pass
	bg_tex = ImageTexture.create_from_image(bg)
	fg_tex = ImageTexture.create_from_image(fg)
	fake_tex = ImageTexture.create_from_image(fk)
	fake_alpha.clear()


func _process(delta: float) -> void:
	time += delta
	for k in spring_anim.keys():
		spring_anim[k] -= 1
		if spring_anim[k] <= 0:
			spring_anim.erase(k)
	_update_followers(delta)
	queue_redraw()


func notify_spring() -> void:
	var best := -1
	var bd := 1e9
	var pc := world.player_center()
	for i in world.spring_x.size():
		var d := pc.distance_squared_to(Vector2(world.spring_x[i] + 4, world.spring_y[i] + 4))
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		spring_anim[best] = 14


func _update_followers(delta: float) -> void:
	if world == null:
		return
	var pc := world.player_center() + Vector2(-world.facing * 10, -8)
	var lead := pc
	for i in world.berry_s.size():
		var s := world.berry_s[i]
		if s == 1:
			var cur: Vector2 = berry_follow.get(i, Vector2(world.berry_x[i], world.berry_y[i]))
			cur = cur.lerp(lead, 1.0 - pow(0.001, delta))
			berry_follow[i] = cur
			lead = cur + Vector2(-world.facing * 8, 0)
		else:
			berry_follow.erase(i)
		if s == 3:
			var fp: Vector2 = berry_fly.get(i, Vector2(world.berry_x[i], world.berry_y[i]))
			fp.y -= 120.0 * delta
			berry_fly[i] = fp
	for i in world.key_s.size():
		if world.key_s[i] == 1:
			var cur: Vector2 = key_follow.get(i, Vector2(world.key_x[i], world.key_y[i]))
			cur = cur.lerp(lead, 1.0 - pow(0.001, delta))
			key_follow[i] = cur
			lead = cur + Vector2(-world.facing * 8, 0)
		else:
			key_follow.erase(i)
	if world.golden_held:
		if golden_follow == Vector2.ZERO:
			golden_follow = lead
		golden_follow = golden_follow.lerp(lead, 1.0 - pow(0.001, delta))


# ---------------------------------------------------------------- drawing

func _obj(name: String, center: Vector2, mod: Color = Color.WHITE, flip := false) -> void:
	var r := Art.obj_rect(name)
	var dst := Rect2(roundf(center.x) - 8, roundf(center.y) - 8, 16, 16)
	if flip:
		draw_set_transform(Vector2(roundf(center.x) * 2.0, 0), 0, Vector2(-1, 1))
		draw_texture_rect_region(Art.objects(), dst, r, mod)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_texture_rect_region(Art.objects(), dst, r, mod)


func _tile(col: int, row: int, pos: Vector2, mod: Color = Color.WHITE) -> void:
	var tex := _tiles_tex()
	draw_texture_rect_region(tex, Rect2(pos, Vector2(T, T)), Rect2(col * T, row * T, T, T), mod)


var _ttex: Texture2D
var _ttex_name := ""
func _tiles_tex() -> Texture2D:
	if _ttex == null or _ttex_name != tileset:
		_ttex = Art.tex("res://assets/tiles/%s.png" % tileset)
		_ttex_name = tileset
	return _ttex


func _draw() -> void:
	if def == null or world == null:
		return
	if bg_tex:
		draw_texture(bg_tex, Vector2.ZERO)
	_draw_decor_back()
	_draw_curtains()
	_draw_groups()
	_draw_masks()
	_draw_zips()
	if fg_tex:
		draw_texture(fg_tex, Vector2.ZERO)
	_draw_fake()
	_draw_decor_front()
	_draw_entities()


func _draw_fake() -> void:
	if fake_tex == null:
		return
	var a := 1.0
	var pc := world.player_center()
	for gi in def.groups.size():
		var g: Dictionary = def.groups[gi]
		if g.kind != RoomDef.FAKE:
			continue
		var r: Rect2i = g.rect
		var near := Rect2(r.position * T, r.size * T).grow(6).has_point(pc)
		var cur: float = fake_alpha.get(gi, 1.0)
		cur = move_toward(cur, 0.25 if near else 1.0, 0.08)
		fake_alpha[gi] = cur
		a = minf(a, cur)
	draw_texture(fake_tex, Vector2.ZERO, Color(1, 1, 1, a))


func _draw_curtains() -> void:
	if not world.has_curtain:
		return
	var passable := world.state == World.ST_DASH or world.state == World.ST_DREAM
	for g in def.groups:
		if g.kind != RoomDef.CURTAIN:
			continue
		var r: Rect2i = g.rect
		var px := Rect2(r.position * T, r.size * T)
		draw_rect(px, Color("4a0a1c"))
		for c in g.cells:
			var cx: int = c % def.w
			var cy: int = c / def.w
			var sway := int(round(sin(time * 2.0 + cx * 0.6) * 1.0))
			_tile(14, 5, Vector2(cx * T + sway, cy * T), Color(1, 1, 1, 1))
		# stars
		var n := int(r.size.x * r.size.y * 0.6)
		for i in n:
			var sx := px.position.x + fposmod(i * 37.0 + time * (6 + i % 5), px.size.x)
			var sy := px.position.y + fposmod(i * 53.0 + sin(time + i) * 3.0, px.size.y)
			var a := 0.5 + 0.5 * sin(time * 3.0 + i)
			draw_rect(Rect2(int(sx), int(sy), 1, 1), Color(1.0, 0.85, 0.4, a))
		# gold trim
		var trim := Color("e8b84a") if not passable else Color("fff0b0")
		draw_rect(px, trim, false, 1.0)


func _draw_groups() -> void:
	for gi in def.groups.size():
		var g: Dictionary = def.groups[gi]
		var st := world.group_s[gi]
		var r: Rect2i = g.rect
		match g.kind:
			RoomDef.CRUMBLE:
				var shake := Vector2.ZERO
				if st == 1:
					shake = Vector2(randi_range(-1, 1), 0)
				for c in g.cells:
					var cx: int = c % def.w
					var cy: int = c / def.w
					var v := 1
					var left := cx == r.position.x
					var right := cx == r.end.x - 1
					if left and right: v = 3
					elif left: v = 0
					elif right: v = 2
					if st == 2:
						var a := 0.18 if world.group_t[gi] > 20 else 0.18 + (20 - world.group_t[gi]) / 30.0
						_tile(4 + v, 5, Vector2(cx * T, cy * T), Color(1, 1, 1, a))
					else:
						_tile(4 + v, 5, Vector2(cx * T, cy * T) + shake)
			RoomDef.DOOR:
				if st == 0:
					for c in g.cells:
						_tile(8, 5, Vector2((c % def.w) * T, (c / def.w) * T))
			RoomDef.CRACKED:
				if st == 0:
					for c in g.cells:
						_tile(9, 5, Vector2((c % def.w) * T, (c / def.w) * T))


func _draw_masks() -> void:
	if not world.has_mask:
		return
	for i in world.dyn_cells:
		var t := def.cells[i]
		if t != RoomDef.MASK_A and t != RoomDef.MASK_B:
			continue
		var cx := i % def.w
		var cy := i / def.w
		var active := (t == RoomDef.MASK_A and world.mask_active == 0) or (t == RoomDef.MASK_B and world.mask_active == 1)
		var ghost := world.mask_ghost.has(i)
		var col := 10 if t == RoomDef.MASK_A else 12
		if active and not ghost:
			_tile(col, 5, Vector2(cx * T, cy * T))
		else:
			_tile(col + 1, 5, Vector2(cx * T, cy * T), Color(1, 1, 1, 0.8 if active else 0.55))


func _draw_zips() -> void:
	for i in world.zip_count:
		var zw := world.zip_w[i]
		var zh := world.zip_h[i]
		var a := Vector2(world.zip_sx[i] + zw / 2.0, world.zip_sy[i] + zh / 2.0)
		var b := Vector2(world.zip_tx[i] + zw / 2.0, world.zip_ty[i] + zh / 2.0)
		# cable
		draw_line(a + Vector2(0, -1), b + Vector2(0, -1), Color("1c1424"), 1.0)
		draw_line(a + Vector2(0, 1), b + Vector2(0, 1), Color("1c1424"), 1.0)
		draw_circle(a, 3, Color("3a3f52"))
		draw_circle(b, 3, Color("3a3f52"))
		var x := world.zip_px[i * 2]
		var y := world.zip_px[i * 2 + 1]
		var moving := world.zip_phase[i] != World.Z_IDLE
		var body := Rect2(x, y, zw, zh)
		draw_rect(body, Color("1c1424"))
		draw_rect(body.grow(-1), Color("6b4a35"))
		draw_rect(Rect2(x + 1, y + 1, zw - 2, 2), Color("e8b84a") if moving else Color("a8782a"))
		# windows
		var wy := y + 4
		var wx := x + 3
		while wx + 4 <= x + zw - 2 and zh >= 10:
			draw_rect(Rect2(wx, wy, 4, mini(4, zh - 7)), Color("ffd27a") if moving else Color("2a1a14"))
			wx += 7
		# gear
		var gc := Vector2(x + zw / 2.0, y + zh - 4)
		var ang := time * (6.0 if moving else 0.5)
		for k in 4:
			var d := Vector2.RIGHT.rotated(ang + k * PI / 2.0) * 2.5
			draw_rect(Rect2(gc + d - Vector2(0.5, 0.5), Vector2(1, 1)), Color("c9ced9"))
		draw_rect(Rect2(x, y + zh - 1, zw, 1), Color("1c1424"))


func _draw_decor_back() -> void:
	for d in decor:
		var c: String = d[0]
		var p: Vector2i = d[1] * T
		match c:
			"t":   # small pine / bush
				var col := Color("1f4a3a")
				for row in 10:
					var hw := row / 3 + 1
					draw_rect(Rect2(p.x + 4 - hw, p.y - 4 + row, hw * 2, 1), col)
				draw_rect(Rect2(p.x + 3, p.y + 6, 2, 2), Color("4a2a1a"))
			"r":   # bunting rope across the cell
				for i in 8:
					var yy := p.y + 2 + int(abs(sin((p.x + i) * 0.4)) * 2)
					draw_rect(Rect2(p.x + i, yy, 1, 1), Color("2a1a14"))
				draw_colored_polygon(PackedVector2Array([Vector2(p.x + 1, p.y + 3), Vector2(p.x + 4, p.y + 3), Vector2(p.x + 2.5, p.y + 7)]), Color("d8344f") if (p.x / 8) % 2 == 0 else Color("e8b84a"))
			"m":   # mirror shard on the wall
				var shine := 0.5 + 0.5 * sin(time * 2.0 + p.x)
				draw_rect(Rect2(p.x + 1, p.y, 6, 8), Color("1c1424"))
				draw_rect(Rect2(p.x + 2, p.y + 1, 4, 6), Color("8fd0e0").lerp(Color.WHITE, shine * 0.4))
			"q":   # stained glass
				draw_rect(Rect2(p.x, p.y, 8, 8), Color("1c1424"))
				var cols := [Color("2f6f8a"), Color("8a2f5a"), Color("c9a23a"), Color("3a8a5a")]
				for k in 4:
					draw_rect(Rect2(p.x + 1 + (k % 2) * 3, p.y + 1 + (k / 2) * 3, 3, 3), cols[(k + p.x / 8 + p.y / 8) % 4])


func _draw_decor_front() -> void:
	for d in decor:
		var c: String = d[0]
		var p: Vector2i = d[1] * T
		match c:
			"f":   # flowers / grass tuft
				var cols := [Color("ff7ab8"), Color("ffd25a"), Color("ffffff"), Color("8ab4ff")]
				for i in 3:
					var fx := p.x + 1 + i * 3
					var sway := int(round(sin(time * 1.5 + fx * 0.3)))
					draw_rect(Rect2(fx, p.y + 5, 1, 3), Color("3f8a3a"))
					draw_rect(Rect2(fx + sway, p.y + 4, 1, 1), cols[(p.x / 8 + i) % 4])
			"l":   # lantern
				var glow := 0.6 + 0.15 * sin(time * 3.0 + p.x)
				draw_circle(Vector2(p.x + 4, p.y + 4), 7, Color(1.0, 0.8, 0.4, 0.12 * glow))
				draw_circle(Vector2(p.x + 4, p.y + 4), 4, Color(1.0, 0.8, 0.4, 0.18 * glow))
				draw_rect(Rect2(p.x + 3, p.y, 2, 1), Color("1c1424"))
				draw_rect(Rect2(p.x + 2, p.y + 1, 4, 5), Color("1c1424"))
				draw_rect(Rect2(p.x + 3, p.y + 2, 2, 3), Color("ffd27a"))
			"c":   # candle
				var fl := int(round(sin(time * 9.0 + p.x)))
				draw_circle(Vector2(p.x + 4, p.y + 3), 4, Color(1.0, 0.7, 0.3, 0.12))
				draw_rect(Rect2(p.x + 3, p.y + 4, 2, 4), Color("f4efe6"))
				draw_rect(Rect2(p.x + 3 + fl * 0, p.y + 2, 2, 2), Color("ffb03a"))
			"s":   # sign post
				draw_rect(Rect2(p.x + 3, p.y + 3, 2, 5), Color("5a3a24"))
				draw_rect(Rect2(p.x, p.y, 8, 4), Color("1c1424"))
				draw_rect(Rect2(p.x + 1, p.y + 1, 6, 2), Color("a07850"))
			"x":   # crate (decoration)
				draw_rect(Rect2(p.x, p.y, 8, 8), Color("1c1424"))
				draw_rect(Rect2(p.x + 1, p.y + 1, 6, 6), Color("8a5a3a"))
				draw_line(Vector2(p.x + 1, p.y + 1), Vector2(p.x + 7, p.y + 7), Color("5a3a24"))
			"j":   # jar / pot
				draw_rect(Rect2(p.x + 2, p.y + 3, 4, 5), Color("1c1424"))
				draw_rect(Rect2(p.x + 3, p.y + 4, 2, 3), Color("c8644a"))
			"a":   # torch
				var fl := sin(time * 11.0 + p.y) * 0.5
				draw_circle(Vector2(p.x + 4, p.y + 2), 6, Color(1.0, 0.6, 0.2, 0.15))
				draw_rect(Rect2(p.x + 3, p.y + 3, 2, 5), Color("5a3a24"))
				draw_rect(Rect2(p.x + 3 + fl, p.y, 2, 3), Color("ffb03a"))
				draw_rect(Rect2(p.x + 3, p.y + 1, 2, 1), Color("fff0a0"))
			"u":   # glowing mushroom
				var g := 0.5 + 0.5 * sin(time * 2.0 + p.x * 0.1)
				draw_circle(Vector2(p.x + 4, p.y + 5), 5, Color(0.25, 0.9, 0.75, 0.1 + 0.08 * g))
				draw_rect(Rect2(p.x + 3, p.y + 5, 2, 3), Color("d0f0e8"))
				draw_rect(Rect2(p.x + 1, p.y + 3, 6, 2), Color("3fc9a8"))


func _draw_entities() -> void:
	var bob := sin(time * 3.0) * 1.5
	var f2 := int(time * 4.0) % 2
	# end flag / campfire
	for e in def.entities:
		match e.type:
			"end":
				var style: String = def.meta.get("end_style", "flag")
				var pos := Vector2(e.cx * T + 4, e.cy * T)
				if style == "fire":
					_obj("fire%d" % (int(time * 8.0) % 2), pos)
					draw_circle(pos, 14, Color(1.0, 0.6, 0.2, 0.08 + 0.03 * sin(time * 9.0)))
				elif style == "none":
					pass
				else:
					_obj("flag%d" % (int(time * 3.0) % 2), pos + Vector2(2, -4))
			"npc":
				_draw_npc(e)
	# springs
	for i in world.spring_x.size():
		var name := "spring1" if spring_anim.has(i) else "spring0"
		var sx := world.spring_x[i]
		var sy := world.spring_y[i]
		match world.spring_dir[i]:
			0:
				_obj(name, Vector2(sx + 4, sy))
			1:
				draw_set_transform(Vector2(sx, sy + 4), PI / 2.0, Vector2.ONE)
				draw_texture_rect_region(Art.objects(), Rect2(-8, -12, 16, 16), Art.obj_rect(name))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			-1:
				draw_set_transform(Vector2(sx + 8, sy + 4), -PI / 2.0, Vector2.ONE)
				draw_texture_rect_region(Art.objects(), Rect2(-8, -12, 16, 16), Art.obj_rect(name))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# gems
	for i in world.gem_x.size():
		var c := Vector2(world.gem_x[i], world.gem_y[i])
		if world.gem_t[i] == 0:
			var nm := ("twin%d" if world.gem_twin[i] == 1 else "gem%d") % f2
			draw_circle(c, 7, Color(0.6, 1.0, 0.6, 0.08) if world.gem_twin[i] == 0 else Color(1.0, 0.5, 0.8, 0.08))
			_obj(nm, c + Vector2(0, bob - 1))
		else:
			_obj("gem_empty", c, Color(1, 1, 1, 0.5))
	# balloons
	for i in world.balloon_x.size():
		var c := Vector2(world.balloon_x[i], world.balloon_y[i])
		if world.boost_idx == i:
			var sq := 1.0 + 0.15 * sin(time * 30.0)
			draw_set_transform(c, 0, Vector2(sq, 2.0 - sq))
			draw_texture_rect_region(Art.objects(), Rect2(-8, -9, 16, 16), Art.obj_rect("balloon0"))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		elif world.balloon_t[i] == 0:
			_obj("balloon%d" % f2, c + Vector2(0, bob - 1))
		else:
			draw_arc(c + Vector2(0, -1), 5, 0, TAU, 12, Color(1, 0.4, 0.5, 0.35), 1.0)
	# bumpers
	for i in world.bumper_x.size():
		var c := Vector2(world.bumper_x[i], world.bumper_y[i])
		var hit := world.bumper_t[i] > 0
		var s := 1.0 + (0.25 * world.bumper_t[i] / World.F_BUMPER_COOLDOWN if hit else 0.04 * sin(time * 4.0))
		draw_set_transform(c, 0, Vector2(s, s))
		draw_texture_rect_region(Art.objects(), Rect2(-8, -8, 16, 16), Art.obj_rect("bumper1" if hit else "bumper0"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# keys
	for i in world.key_x.size():
		match world.key_s[i]:
			0:
				_obj("key", Vector2(world.key_x[i], world.key_y[i] + bob))
			1:
				_obj("key", key_follow.get(i, Vector2(world.key_x[i], world.key_y[i])))
	# bells
	for i in world.bell_x.size():
		if world.bell_s[i] == 0:
			var c := Vector2(world.bell_x[i], world.bell_y[i] + bob)
			if world.bell_ghost[i] == 1:
				_obj("bell_ghost", c)
			else:
				draw_circle(c, 9, Color(1.0, 0.85, 0.3, 0.1 + 0.05 * sin(time * 4.0)))
				var sw := sin(time * 5.0) * 0.25
				draw_set_transform(c, sw, Vector2.ONE)
				draw_texture_rect_region(Art.objects(), Rect2(-8, -8, 16, 16), Art.obj_rect("bell%d" % f2))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# golden berry
	for i in world.golden_x.size():
		if world.golden_s[i] == 0:
			var c := Vector2(world.golden_x[i], world.golden_y[i] + bob)
			draw_circle(c, 8, Color(1.0, 0.9, 0.4, 0.12))
			_obj("gold%d" % f2, c)
	if world.golden_held:
		_obj("gold%d" % f2, golden_follow)
	# berries
	for i in world.berry_x.size():
		var s := world.berry_s[i]
		var base := Vector2(world.berry_x[i], world.berry_y[i])
		var ghost := world.berry_ghost[i] == 1
		var nm := ("ghost%d" if ghost else "berry%d") % f2
		match s:
			0:
				var c := base + Vector2(0, bob)
				if world.berry_winged[i] == 1:
					var wf := "wing%d" % (int(time * 10.0) % 2)
					_obj(wf, c + Vector2(4, -2))
					_obj(wf, c + Vector2(-4, -2), Color.WHITE, true)
				_obj(nm, c)
			1:
				_obj(nm, berry_follow.get(i, base))
			3:
				var fp: Vector2 = berry_fly.get(i, base)
				var wf := "wing%d" % (int(time * 14.0) % 2)
				_obj(wf, fp + Vector2(4, -2))
				_obj(wf, fp + Vector2(-4, -2), Color.WHITE, true)
				_obj(nm, fp)


func _draw_npc(e: Dictionary) -> void:
	var name: String = e.get("name", "")
	if npc_hidden.has(name):
		return
	var tex: Texture2D
	var fw := 16
	var fh := 16
	var frames := 2
	match name:
		"bellamy":
			tex = Art.tex("res://assets/sprites/npc_bellamy.png"); fh = 24
		"tobi":
			tex = Art.tex("res://assets/sprites/npc_tobi.png")
		"oddo":
			tex = Art.tex("res://assets/sprites/npc_oddo.png"); fh = 24; frames = 1
		"magpie":
			tex = Art.tex("res://assets/sprites/magpie.png"); fw = 8; fh = 8; frames = 3
		"grin":
			tex = Art.grin()
		_:
			return
	var fi := int(time * 2.0) % frames
	if name == "grin":
		fi = Art.frame_index("idle0") if int(time * 2.0) % 2 == 0 else Art.frame_index("idle1")
	var feet := Vector2(e.cx * T + 4, e.cy * T + 8)
	var face_left := world.player_center().x < feet.x
	if npc_face.has(name):
		face_left = npc_face[name] < 0
	var dst := Rect2(feet.x - fw / 2.0, feet.y - fh, fw, fh)
	var mod := Color(1, 1, 1, 0.75 + 0.15 * sin(time * 2.0)) if name == "oddo" else Color.WHITE
	if name == "oddo":
		dst.position.y += sin(time * 1.5) * 2.0 - 2.0
	if face_left:
		draw_set_transform(Vector2(feet.x * 2.0, 0), 0, Vector2(-1, 1))
	draw_texture_rect_region(tex, dst, Rect2(fi * fw, 0, fw, fh), mod)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
