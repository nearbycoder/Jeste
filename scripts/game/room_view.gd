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
var deco_tex: ImageTexture
var shadow_tex: ImageTexture     # Ultra: the terrain's blurred silhouette, cast onto the backdrop
const SHADOW_OFFSET := Vector2(2, 3)
const SHADOW_COL := Color(0.02, 0.0, 0.06, 0.42)
static var _art_cache := {}
var fake_alpha := {}
var time := 0.0
var level: Node = null   # Level, for follower positions

# Visual-only state
var spring_anim := {}      # spring index -> frames left
var berry_follow := {}     # berry index -> Vector2 position
var berry_fly := {}        # berry index -> Vector2 position (flying away)
var key_follow := {}       # key index -> Vector2
var golden_follow := Vector2.ZERO
var ghost_follow := {}     # Route Ghost: "berry3" / "key0" / "golden" -> Vector2
var _ghost_follow_for: World = null
var decor: Array = []      # [char, Vector2i]
var grass: PackedVector2Array = PackedVector2Array()  # blade roots
var npc_hidden := {}
var mask_flash := 0.0
var _prev_group := PackedInt32Array()
var _prev_gem := PackedInt32Array()
var _prev_balloon := PackedInt32Array()
var _prev_mask := 0
var npc_face := {}


func build(p_def: RoomDef, p_world: World, p_tileset: String, p_chapter: int) -> void:
	def = p_def
	world = p_world
	tileset = p_tileset
	chapter = p_chapter
	tiles_img = Art.tileset_image(tileset)
	spring_anim.clear()
	_prev_group = PackedInt32Array()
	_prev_gem = PackedInt32Array()
	_prev_balloon = PackedInt32Array()
	berry_follow.clear()
	berry_fly.clear()
	key_follow.clear()
	_bake()
	decor.clear()
	grass = PackedVector2Array()
	if tileset in ["meadow", "ridge", "village"]:
		for gy in range(1, def.h):
			for gx in def.w:
				var t := def.cells[gy * def.w + gx]
				var above := def.cells[(gy - 1) * def.w + gx]
				if (t == RoomDef.SOLID) and (above == RoomDef.EMPTY or above == RoomDef.BGWALL):
					for k in 3:
						var h := (gx * 7 + gy * 3 + k * 5) % 7
						if h < 4:
							grass.append(Vector2(gx * T + 1 + k * 3 + (h % 2), gy * T))
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


static var _tasks := {}
static var _mutex := Mutex.new()


static func _art_key(def_: RoomDef, ts: String) -> String:
	return def_.id + "|" + ts + "|" + str(hash(def_.rows))


## Queue a room's terrain painting on the worker pool (no-op if cached/queued).
static func prebake(def_: RoomDef, ts: String) -> void:
	var key := _art_key(def_, ts)
	_mutex.lock()
	if not _art_cache.has(key) and not _tasks.has(key):
		_tasks[key] = WorkerThreadPool.add_task(_bake_task.bind(key, def_, ts), false, "terrain " + def_.id)
	_mutex.unlock()


static func _bake_task(key: String, def_: RoomDef, ts: String) -> void:
	var art := TerrainArt.render(def_, ts)
	_mutex.lock()
	_art_cache[key] = art
	_mutex.unlock()


static func is_painted(def_: RoomDef, ts: String) -> bool:
	var key := _art_key(def_, ts)
	_mutex.lock()
	var ok := _art_cache.has(key)
	_mutex.unlock()
	return ok


## Painted layers for a room: from the cache, by waiting on a queued
## background job, or rendered right here as a last resort.
static func painted(def_: RoomDef, ts: String) -> Dictionary:
	var key := _art_key(def_, ts)
	_mutex.lock()
	var tid: int = _tasks.get(key, -1)
	_mutex.unlock()
	if tid != -1:
		WorkerThreadPool.wait_for_task_completion(tid)
		_mutex.lock()
		_tasks.erase(key)
		_mutex.unlock()
	_mutex.lock()
	var art: Dictionary = _art_cache.get(key, {})
	_mutex.unlock()
	if art.is_empty():
		art = TerrainArt.render(def_, ts)
		_mutex.lock()
		_art_cache[key] = art
		_mutex.unlock()
	return art


## Drops the painted art of rooms outside `defs` (a chapter's rooms, as
## [RoomDef, tileset] pairs), so a session holds one chapter's worth (up to
## ~11 MB) rather than every chapter it has visited (~64 MB): it matters on
## a phone, where the browser closes a tab that grows too big.
static func forget_others(defs: Array) -> void:
	var keep := {}
	for p in defs:
		keep[_art_key(p[0], p[1])] = true
	_mutex.lock()
	for key in _art_cache.keys():
		if not keep.has(key) and not _tasks.has(key):
			_art_cache.erase(key)
	_mutex.unlock()


## Wait for every queued job (call before quitting / freeing scenes).
static func flush_bakes() -> void:
	_mutex.lock()
	var ids := _tasks.values()
	_tasks.clear()
	_mutex.unlock()
	for tid in ids:
		WorkerThreadPool.wait_for_task_completion(tid)


func _bake() -> void:
	var art := painted(def, tileset)
	var fg: Image = (art.fg as Image).duplicate()
	# spikes and jump-through planks keep their hand-drawn tiles
	for cy in def.h:
		for cx in def.w:
			var t := def.cells[cy * def.w + cx]
			match t:
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
	bg_tex = ImageTexture.create_from_image(art.bg)
	fg_tex = ImageTexture.create_from_image(fg)
	fake_tex = ImageTexture.create_from_image(art.fake)
	deco_tex = ImageTexture.create_from_image(art.deco)
	fake_alpha.clear()
	_bake_shadow(fg)


## Ultra (Options > Graphics): the room's terrain casts a soft shadow down and
## to the right onto the backdrop and background walls behind it.
func _bake_shadow(fg: Image) -> void:
	shadow_tex = null
	if Game.fidelity() < Game.FIDELITY_ULTRA:
		return
	var img: Image = fg.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	img.resize(maxi(w / 2, 1), maxi(h / 2, 1), Image.INTERPOLATE_BILINEAR)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	shadow_tex = ImageTexture.create_from_image(img)


func _ready() -> void:
	Game.fidelity_changed.connect(_on_fidelity_changed)


func _on_fidelity_changed() -> void:
	if def:
		_bake_shadow(fg_tex.get_image() if fg_tex else Image.create(1, 1, false, Image.FORMAT_RGBA8))
		queue_redraw()


func _process(delta: float) -> void:
	time += delta
	mask_flash = maxf(mask_flash - delta * 4.0, 0.0)
	_react_to_state()
	for k in spring_anim.keys():
		spring_anim[k] -= 1
		if spring_anim[k] <= 0:
			spring_anim.erase(k)
	_update_followers(delta)
	queue_redraw()


## Spawns particles when entity state changes (purely visual).
func _react_to_state() -> void:
	if world == null or def == null or world.room != def or level == null or level.effects == null:
		_prev_group = PackedInt32Array()
		return
	var fx: Effects = level.effects
	if _prev_group.size() == world.group_s.size():
		for gi in world.group_s.size():
			var g: Dictionary = def.groups[gi]
			var r: Rect2i = g.rect
			var px := Rect2(r.position * T, r.size * T)
			if g.kind == RoomDef.CRUMBLE:
				if _prev_group[gi] == 1 and world.group_s[gi] == 2:
					fx.debris(px, Color("a07850"), 10 * r.size.x)
				elif _prev_group[gi] == 2 and world.group_s[gi] == 0:
					for k in r.size.x:
						fx.puff(px.position + Vector2(k * 8 + 4, 4), Vector2(0, -8), Color(1, 1, 1, 0.6), 1)
			elif g.kind == RoomDef.CRACKED and _prev_group[gi] == 0 and world.group_s[gi] == 1:
				fx.debris(px, Color("8a7a6a"), 6 * r.size.x * r.size.y)
	if _prev_gem.size() == world.gem_t.size():
		for i in world.gem_t.size():
			var c := Vector2(world.gem_x[i], world.gem_y[i])
			var col := Color("ff7ab8") if world.gem_twin[i] == 1 else Color("8aff6e")
			if _prev_gem[i] == 0 and world.gem_t[i] > 0:
				fx.burst(c, col, 12, 70.0, 0.4)
			elif _prev_gem[i] > 0 and world.gem_t[i] == 0:
				fx.ring(c, col, 10.0, 0.3)
				fx.sparkle(c, col, 5)
	if _prev_balloon.size() == world.balloon_t.size():
		for i in world.balloon_t.size():
			if _prev_balloon[i] == 1 and world.balloon_t[i] > 1:
				var c := Vector2(world.balloon_x[i], world.balloon_y[i])
				fx.burst(c, Color("ff5a6e"), 10, 80.0, 0.3)
				fx.ring(c, Color("ffb0b8"), 14.0, 0.25)
			elif _prev_balloon[i] > 0 and world.balloon_t[i] == 0:
				fx.ring(Vector2(world.balloon_x[i], world.balloon_y[i]), Color("ff8a9a"), 8.0, 0.25)
	if world.has_mask and world.mask_active != _prev_mask:
		mask_flash = 1.0
	_prev_group = world.group_s.duplicate()
	_prev_gem = world.gem_t.duplicate()
	_prev_balloon = world.balloon_t.duplicate()
	_prev_mask = world.mask_active


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
	if world == null or world.room != def:
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
	_update_ghost_followers(delta)


## The Route Ghost's carried berries, keys and golden berry trail her the way
## the player's trail the player.
func _update_ghost_followers(delta: float) -> void:
	var gw: World = level.ghost_world if level and level.get("ghost_world") else null
	if gw != _ghost_follow_for:
		ghost_follow.clear()   # she started over
		_ghost_follow_for = gw
	if gw == null or gw.room != def:
		return
	var lead := gw.player_center() + Vector2(-gw.facing * 10, -8)
	for it in ghost_items(world, gw):
		if it[2] != "follow":
			continue
		var k := "%s%d" % [it[0], it[1]]
		var cur: Vector2 = ghost_follow.get(k, item_pos(gw, it[0], it[1]))
		cur = cur.lerp(lead, 1.0 - pow(0.001, delta))
		ghost_follow[k] = cur
		lead = cur + Vector2(-gw.facing * 8, 0)


# ---------------------------------------------------------------- drawing

func _obj(name: String, center: Vector2, mod: Color = Color.WHITE, flip := false, sheet: Texture2D = null) -> void:
	var r := Art.obj_rect(name)
	var dst := Rect2(roundf(center.x) - 8, roundf(center.y) - 8, 16, 16)
	if sheet == null:
		sheet = Art.objects()
	if flip:
		draw_set_transform(Vector2(roundf(center.x) * 2.0, 0), 0, Vector2(-1, 1))
		draw_texture_rect_region(sheet, dst, r, mod)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_texture_rect_region(sheet, dst, r, mod)


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
	if deco_tex:
		draw_texture(deco_tex, Vector2.ZERO)
	if shadow_tex:
		draw_texture(shadow_tex, SHADOW_OFFSET, SHADOW_COL)
	if world.room != def:
		# The world has moved on (room transition): static layers only.
		if fg_tex:
			draw_texture(fg_tex, Vector2.ZERO)
		if fake_tex:
			draw_texture(fake_tex, Vector2.ZERO)
		return
	_draw_decor_back()
	_draw_curtains()
	_draw_groups()
	_draw_masks()
	_draw_zips(world)
	_draw_ghost_parts()
	if fg_tex:
		draw_texture(fg_tex, Vector2.ZERO)
	_draw_fake()
	_draw_decor_front()
	_draw_entities()
	_draw_ghost_items()


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
		var mirror: bool = chapter == 5 or (chapter == 7 and str(def.meta.get("mirror", "")) == "1")
		if mirror:
			_draw_mirror(px, passable)
			continue
		_draw_velvet(px, passable)


## Mirror glass: cool gradient, Mira's live reflection (mirrored about the
## glass centre), two travelling sheens and an ornate silver frame.
func _draw_mirror(px: Rect2, passable: bool) -> void:
	var top := Color("8ab8cc") if not passable else Color("c8ecff")
	var bot := Color("2a4a62") if not passable else Color("4a7a96")
	draw_polygon(PackedVector2Array([px.position, Vector2(px.end.x, px.position.y), px.end, Vector2(px.position.x, px.end.y)]),
		PackedColorArray([top, top.lerp(bot, 0.4), bot, bot.lerp(top, 0.3)]))
	var pv: PlayerView = level.player_view if level and "player_view" in level else null
	if pv and pv.visible_player and world:
		var feet: Vector2 = pv._feet()
		var mx := px.get_center().x
		var dst := Rect2(Vector2(roundf(2.0 * mx - feet.x) - 12.0, roundf(feet.y) - 24.0), Vector2(24, 24))
		var clip := dst.intersection(px)
		if clip.has_area():
			var flip := pv._facing() > 0
			var sx0 := clip.position.x - dst.position.x
			if flip:
				sx0 = 24.0 - (sx0 + clip.size.x)
			var src := Rect2(pv.last_frame * 24 + sx0, clip.position.y - dst.position.y, clip.size.x, clip.size.y)
			var d := clip
			if flip:
				d = Rect2(clip.position.x + clip.size.x, clip.position.y, -clip.size.x, clip.size.y)
			draw_texture_rect_region(Art.player_menu(), d, src, Color(0.75, 0.92, 1.0, 0.55))
	# travelling sheens
	for k in 2:
		var span := px.size.x + px.size.y
		var sweep := fposmod(time * (26.0 + k * 11.0) + k * span * 0.5, span + 20.0) - 10.0
		var bw := 3 if k == 0 else 1
		for i in int(px.size.y):
			var sx := px.position.x + sweep - i
			if sx >= px.position.x and sx + bw <= px.end.x:
				draw_rect(Rect2(int(sx), px.position.y + i, bw, 1), Color(1, 1, 1, 0.35 if k == 0 else 0.5))
	# frame: dark outline, silver bevel, corner studs
	var r := Rect2(px.position.round(), px.size.round())
	UIKit.frame(self, r, Color("e8f4f8") if not passable else Color.WHITE)
	UIKit.frame(self, r.grow(1), Color("1a2a30"))
	draw_rect(Rect2(r.position.x + 1, r.end.y - 2, r.size.x - 2, 1), Color("6a8a96"))
	for c in [r.position, Vector2(r.end.x - 2, r.position.y), Vector2(r.position.x, r.end.y - 2), r.end - Vector2(2, 2)]:
		draw_rect(Rect2(c, Vector2(2, 2)), Color("ffffff"))


## Theatre curtain: animated velvet folds, scalloped valance, gold rope trim,
## fringe and drifting gold dust (brighter while Mira can dash through).
func _draw_velvet(px: Rect2, passable: bool) -> void:
	var ramp := [Color("2e0410"), Color("4e0a1e"), Color("761228"), Color("a01e36"), Color("cc3a50"), Color("ee7080")]
	var x0 := int(px.position.x)
	var y0 := int(px.position.y)
	var w := int(px.size.x)
	var h := int(px.size.y)
	var lift := 1 if passable else 0
	for x in w:
		var y := 0
		while y < h:
			var seg := mini(4, h - y)
			var ph := (x + sin(time * 1.6 + y * 0.09 + x * 0.05) * 2.2) * TAU / 11.0
			var f := sin(ph)
			var idx := 2 + int(round(f * 1.6)) + lift
			if f < -0.92:
				idx = 0 + lift
			# deeper toward the bottom, lit near the top
			if y < 6:
				idx += 1
			elif y > h - 8:
				idx -= 1
			draw_rect(Rect2(x0 + x, y0 + y, 1, seg), ramp[clampi(idx, 0, 5)])
			y += seg
	# drifting gold dust
	var n := int(w * h / 40.0)
	var dust_a := 1.0 if passable else 0.55
	for i in n:
		var sx := fposmod(i * 37.0 + sin(time * 0.7 + i) * 4.0, float(w))
		var sy := fposmod(i * 53.0 - time * (4.0 + i % 4), float(h))
		var tw := 0.5 + 0.5 * sin(time * 4.0 + i * 1.3)
		draw_rect(Rect2(x0 + int(sx), y0 + int(sy), 1, 1), Color(1.0, 0.86, 0.45, tw * dust_a))
	# scalloped valance across the top
	var gold := Color("f2c14e") if not passable else Color("fff2b8")
	var gold_dk := Color("9a6420")
	for x in w:
		var sc := int(round(2.0 + 2.0 * absf(sin((x + 0.5) * PI / 8.0))))
		draw_rect(Rect2(x0 + x, y0, 1, sc + 1), ramp[1])
		draw_rect(Rect2(x0 + x, y0 + sc + 1, 1, 1), gold if (x + int(time * 6.0)) % 4 != 0 else gold_dk)
	# side ropes and bottom fringe
	for y in h:
		var rc := gold if ((y + int(time * 4.0)) / 2) % 2 == 0 else gold_dk
		draw_rect(Rect2(x0, y0 + y, 1, 1), rc)
		draw_rect(Rect2(x0 + w - 1, y0 + y, 1, 1), rc)
	for x in w:
		draw_rect(Rect2(x0 + x, y0 + h - 1, 1, 1), gold_dk)
		if x % 2 == 0:
			draw_rect(Rect2(x0 + x, y0 + h - 2, 1, 1), gold)
	# tassels at the top corners
	for cx in [x0 + 1, x0 + w - 3]:
		draw_rect(Rect2(cx, y0 + 4, 2, 4), gold)
		draw_rect(Rect2(cx, y0 + 8, 2, 1), gold_dk)


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
			if mask_flash > 0.0:
				draw_rect(Rect2(cx * T, cy * T, T, T), Color(1, 1, 1, 0.6 * mask_flash * Game.flash_scale()))
		else:
			_tile(col + 1, 5, Vector2(cx * T, cy * T), Color(1, 1, 1, 0.8 if active else 0.55))


## Gondolas of `w`: the room's own world, or the Route Ghost's (tinted, and
## only where its gondola isn't exactly where the player's is).
func _draw_zips(w: World, tint := Color.WHITE) -> void:
	var ghost := w != world
	for i in w.zip_count:
		var zw := w.zip_w[i]
		var zh := w.zip_h[i]
		var zp := w.zip_view_pos(i).round()
		if ghost and zp == world.zip_view_pos(i).round():
			continue
		if not ghost:
			var a := Vector2(w.zip_sx[i] + zw / 2.0, w.zip_sy[i] + zh / 2.0)
			var b := Vector2(w.zip_tx[i] + zw / 2.0, w.zip_ty[i] + zh / 2.0)
			# cable
			draw_line(a + Vector2(0, -1), b + Vector2(0, -1), Color("1c1424"), 1.0)
			draw_line(a + Vector2(0, 1), b + Vector2(0, 1), Color("1c1424"), 1.0)
			draw_circle(a, 3, Color("3a3f52"))
			draw_circle(b, 3, Color("3a3f52"))
		var x := zp.x
		var y := zp.y
		var moving := w.zip_phase[i] != World.Z_IDLE
		var body := Rect2(x, y, zw, zh)
		draw_rect(body, Color("1c1424") * tint)
		draw_rect(body.grow(-1), Color("6b4a35") * tint)
		draw_rect(Rect2(x + 1, y + 1, zw - 2, 2), (Color("e8b84a") if moving else Color("a8782a")) * tint)
		# windows
		var wy := y + 4
		var wx := x + 3
		while wx + 4 <= x + zw - 2 and zh >= 10:
			draw_rect(Rect2(wx, wy, 4, mini(4, zh - 7)), (Color("ffd27a") if moving else Color("2a1a14")) * tint)
			wx += 7
		# gear
		var gc := Vector2(x + zw / 2.0, y + zh - 4)
		var ang := time * (6.0 if moving else 0.5)
		for k in 4:
			var d := Vector2.RIGHT.rotated(ang + k * PI / 2.0) * 2.5
			draw_rect(Rect2(gc + d - Vector2(0.5, 0.5), Vector2(1, 1)), Color("c9ced9") * tint)
		draw_rect(Rect2(x, y + zh - 1, zw, 1), Color("1c1424") * tint)


## Route Ghost: she runs in a simulation of her own, so draw (in her tint) the
## moving parts that differ from the player's: her gondolas, and boards,
## gates, cracked walls and mask blocks that are solid for her but not here.
## Cells that can change (boards, gates, cracked walls, mask blocks) and are
## solid in the ghost's world `gw` but not in the player's `w`.
static func ghost_only_cells(w: World, gw: World) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in gw.dyn_cells:
		if gw.solid[i] == 1 and w.solid[i] != 1:
			out.append(i)
	return out


## The other way round: cells solid for the player but open for the ghost
## (her boards have crumbled, her mask blocks have swapped), within `radius`
## pixels of her centre (any distance when radius < 0).
static func ghost_open_cells(w: World, gw: World, radius := -1.0) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := Vector2(gw.x + World.PW / 2.0, gw.y + World.PH / 2.0)
	for i in gw.dyn_cells:
		if w.solid[i] == 1 and gw.solid[i] != 1:
			if radius < 0.0 or c.distance_to(Vector2((i % gw.w) * T + T / 2.0, (i / gw.w) * T + T / 2.0)) <= radius:
				out.append(i)
	return out


## How near the ghost a block that's open only for her gets outlined.
const GHOST_OPEN_RADIUS := 28.0


func _draw_ghost_parts() -> void:
	var gw: World = level.ghost_world if level and level.get("ghost_world") else null
	if gw == null or gw.room != def or not level.ghost_view.visible:
		return
	var tint: Color = level.ghost_view.modulate
	_draw_zips(gw, tint)
	# The player's own blocks stay as they are; where she passes through them,
	# an outline in her tint (fading with distance) shows they're open for her.
	var open := ghost_open_cells(world, gw, GHOST_OPEN_RADIUS)
	var marked := {}
	for i in open:
		marked[i] = true
	var gc := Vector2(gw.x + World.PW / 2.0, gw.y + World.PH / 2.0)
	for i in open:
		var cx := i % def.w
		var cy := i / def.w
		var p := Vector2(cx * T, cy * T)
		var a := clampf(1.2 - gc.distance_to(p + Vector2(T, T) / 2.0) / GHOST_OPEN_RADIUS, 0.0, 1.0)
		var col := Color(tint, a)
		draw_rect(Rect2(p, Vector2(T, T)), Color(tint, 0.18 * a))
		if not marked.has(i - def.w) or cy == 0: draw_rect(Rect2(p, Vector2(T, 1)), col)
		if not marked.has(i + def.w): draw_rect(Rect2(p + Vector2(0, T - 1), Vector2(T, 1)), col)
		if cx == 0 or not marked.has(i - 1): draw_rect(Rect2(p, Vector2(1, T)), col)
		if cx == def.w - 1 or not marked.has(i + 1): draw_rect(Rect2(p + Vector2(T - 1, 0), Vector2(1, T)), col)
	for i in ghost_only_cells(world, gw):
		var cx := i % def.w
		var col := -1
		match def.cells[i]:
			RoomDef.CRUMBLE:
				var l := cx > 0 and def.cells[i - 1] == RoomDef.CRUMBLE
				var r := cx < def.w - 1 and def.cells[i + 1] == RoomDef.CRUMBLE
				col = 5 if l and r else (6 if l else (4 if r else 7))
			RoomDef.DOOR: col = 8
			RoomDef.CRACKED: col = 9
			RoomDef.MASK_A: col = 10
			RoomDef.MASK_B: col = 12
		if col >= 0:
			_tile(col, 5, Vector2(cx * T, (i / def.w) * T), tint)


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


func _draw_grass() -> void:
	if grass.is_empty():
		return
	var pc := world.player_center()
	var feet_y := world.y + World.PH
	var wind := world.wind_x * 0.02
	var col_a := Color("6fbf4a") if tileset != "ridge" else Color("8fcf55")
	var col_b := Color("a8e46c") if tileset != "ridge" else Color("c8f084")
	for i in grass.size():
		var g := grass[i]
		var h := 2.0 + float(int(g.x * 13.0 + g.y) % 3)
		var sway := sin(time * 2.2 + g.x * 0.35) * 0.7 + wind
		var dx := g.x - pc.x
		if absf(dx) < 7.0 and absf(feet_y - g.y) < 3.0:
			sway += signf(dx) * (7.0 - absf(dx)) * 0.4
		var root := g + Vector2(0, 1)
		var steps := int(h) + 1
		for k in steps:
			var u := float(k) / steps
			var p := root + Vector2(sway * u * u, -h * u - 1.0)
			draw_rect(Rect2(roundf(p.x), roundf(p.y), 1, 1), col_a if k < steps - 1 else col_b)


func _draw_decor_front() -> void:
	_draw_grass()
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
					UIKit.campfire(self, pos + Vector2(0, 8), time)
					if level and level.effects and randf() < 0.25:
						level.effects.embers(pos + Vector2(0, -4))
				elif style == "none":
					pass
				else:
					if chapter == 7 and def.exits.is_empty():
						_draw_prayer_flags(pos + Vector2(-2, -12))
					_draw_flag(pos + Vector2(-2, 8))
			"npc":
				_draw_npc(e)
	# springs
	for i in world.spring_x.size():
		var name := "spring1" if spring_anim.has(i) else "spring0"
		var sx := world.spring_x[i]
		var sy := world.spring_y[i]
		var k: float = spring_anim.get(i, 0) / 14.0
		var st := 1.0 + sin(k * PI * 2.0) * 0.25 * k
		match world.spring_dir[i]:
			0:
				draw_set_transform(Vector2(sx + 4, sy + 8), 0, Vector2(2.0 - st, st))
				draw_texture_rect_region(Art.objects(), Rect2(-8, -16, 16, 16), Art.obj_rect(name))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
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
			var nm := ("twin%d" if world.gem_twin[i] == 1 else "gem%d") % 0
			var spin := absf(cos(time * 2.2 + i))
			var sxs := maxf(spin, 0.35)
			draw_set_transform(c + Vector2(0, bob - 1), 0, Vector2(sxs, 1))
			draw_texture_rect_region(Art.objects(), Rect2(-8, -8, 16, 16), Art.obj_rect(nm), Color(1, 1, 1).lerp(Color(1.3, 1.3, 1.3), 1.0 - spin))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			if fmod(time + i * 0.7, 2.0) < 0.12:
				var gp := c + Vector2(-2, -4 + bob)
				draw_rect(Rect2(gp.x - 1, gp.y, 3, 1), Color(1, 1, 1, 0.9))
				draw_rect(Rect2(gp.x, gp.y - 1, 1, 3), Color(1, 1, 1, 0.9))
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
			var sw := sin(time * 1.7 + i) * 0.12
			draw_set_transform(c + Vector2(0, bob - 1 + 6), sw, Vector2.ONE)
			draw_texture_rect_region(Art.objects(), Rect2(-8, -14, 16, 16), Art.obj_rect("balloon0"))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		else:
			draw_arc(c + Vector2(0, -1), 5, 0, TAU, 12, Color(1, 0.4, 0.5, 0.35), 1.0)
	# bumpers
	for i in world.bumper_x.size():
		var c := Vector2(world.bumper_x[i], world.bumper_y[i])
		var hit := world.bumper_t[i] > 0
		var s := 1.0 + (0.25 * world.bumper_t[i] / World.F_BUMPER_COOLDOWN if hit else 0.04 * sin(time * 4.0))
		var pr := fmod(time * 0.8 + i * 0.3, 1.0)
		draw_arc(c, 8.0 + pr * 6.0, 0, TAU, 20, Color(0.6, 0.8, 1.0, 0.35 * (1.0 - pr)), 1.0)
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


## Route Ghost: which of her berries, bells, keys and golden berry to draw, as
## [kind, index, "spot" | "follow"]. "spot": hers is still in place where the
## player's isn't drawn as a whole one (taken, or found on an earlier climb
## and drawn as an outline). "follow": she is carrying it. Where both are
## untouched the player's own covers hers, and what she has collected is gone.
static func ghost_items(w: World, gw: World) -> Array:
	var out := []
	for i in gw.berry_s.size():
		if gw.berry_s[i] == 0 and (w.berry_s[i] != 0 or w.berry_ghost[i] == 1):
			out.append(["berry", i, "spot"])
		elif gw.berry_s[i] == 1:
			out.append(["berry", i, "follow"])
	for i in gw.bell_s.size():
		if gw.bell_s[i] == 0 and (w.bell_s[i] != 0 or w.bell_ghost[i] == 1):
			out.append(["bell", i, "spot"])
	for i in gw.key_s.size():
		if gw.key_s[i] == 0 and w.key_s[i] != 0:
			out.append(["key", i, "spot"])
		elif gw.key_s[i] == 1:
			out.append(["key", i, "follow"])
	for i in gw.golden_s.size():
		if gw.golden_s[i] == 0 and w.golden_s[i] != 0:
			out.append(["golden", i, "spot"])
	if gw.golden_held:
		out.append(["golden", 0, "follow"])
	return out


## Route Ghost: her dash gems and balloons that differ from the player's, as
## [kind, index, state]. "used": hers is spent (a gem, or a balloon she has
## left) while the player's is ready. "ready": hers is ready while the
## player's is spent. "riding": she is in that balloon and the player isn't.
static func ghost_pickups(w: World, gw: World) -> Array:
	var out := []
	for i in gw.gem_t.size():
		if gw.gem_t[i] != 0 and w.gem_t[i] == 0:
			out.append(["gem", i, "used"])
		elif gw.gem_t[i] == 0 and w.gem_t[i] != 0:
			out.append(["gem", i, "ready"])
	for i in gw.balloon_t.size():
		if gw.boost_idx == i:
			if w.boost_idx != i:
				out.append(["balloon", i, "riding"])
		elif gw.balloon_t[i] != 0 and w.balloon_t[i] == 0:
			out.append(["balloon", i, "used"])
		elif gw.balloon_t[i] == 0 and w.balloon_t[i] != 0:
			out.append(["balloon", i, "ready"])
	return out


## Her own berries, bells, keys, gems and balloons are pale shapes
## (Art.objects_ghost) in her tint at this opacity.
const GHOST_ITEM_ALPHA := 0.8


## How much of her respawn wait is left (1 = just used, 0 = back).
static func ghost_pickup_left(gw: World, kind: String, i: int) -> float:
	if kind == "gem":
		return clampf(float(gw.gem_t[i]) / World.F_GEM_RESPAWN, 0.0, 1.0)
	return clampf(float(gw.balloon_t[i]) / World.F_BALLOON_RESPAWN, 0.0, 1.0)


func _draw_ghost_pickups(gw: World, tint: Color) -> void:
	var bob := sin(time * 3.0) * 1.5
	var sheet := Art.objects_ghost()
	var shape := Color(tint, GHOST_ITEM_ALPHA)
	for it in ghost_pickups(world, gw):
		var kind: String = it[0]
		var i: int = it[1]
		var c := Vector2(gw.gem_x[i], gw.gem_y[i]) if kind == "gem" else Vector2(gw.balloon_x[i], gw.balloon_y[i])
		match it[2]:
			"used":
				# hers is gone: a ring in her tint drains until it's back for her
				var rc := c + Vector2(0, bob - 1) if kind == "gem" else c + Vector2(0, bob - 3)
				var left := ghost_pickup_left(gw, kind, i)
				draw_arc(rc, 8.5, 0, TAU, 24, Color(tint, 0.25), 1.0)
				draw_arc(rc, 8.5, -PI / 2.0, -PI / 2.0 + TAU * left, maxi(3, int(24 * left)), Color(tint, 0.9), 1.0)
			"ready":
				if kind == "gem":
					var nm := "twin0" if gw.gem_twin[i] == 1 else "gem0"
					draw_set_transform(c + Vector2(0, bob - 1), 0, Vector2(maxf(absf(cos(time * 2.2 + i)), 0.35), 1))
					draw_texture_rect_region(sheet, Rect2(-8, -8, 16, 16), Art.obj_rect(nm), shape)
				else:
					draw_set_transform(c + Vector2(0, bob - 1 + 6), sin(time * 1.7 + i) * 0.12, Vector2.ONE)
					draw_texture_rect_region(sheet, Rect2(-8, -14, 16, 16), Art.obj_rect("balloon0"), shape)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"riding":
				var sq := 1.0 + 0.15 * sin(time * 30.0)
				draw_set_transform(c, 0, Vector2(sq, 2.0 - sq))
				draw_texture_rect_region(sheet, Rect2(-8, -9, 16, 16), Art.obj_rect("balloon0"), shape)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Where item `i` of a kind sits in world `w` (before anyone takes it). A
## golden berry carried in from another room starts at her.
static func item_pos(w: World, kind: String, i: int) -> Vector2:
	match kind:
		"berry": return Vector2(w.berry_x[i], w.berry_y[i])
		"bell": return Vector2(w.bell_x[i], w.bell_y[i])
		"key": return Vector2(w.key_x[i], w.key_y[i])
	return Vector2(w.golden_x[i], w.golden_y[i]) if i < w.golden_x.size() else w.player_center()


func _draw_ghost_items() -> void:
	var gw: World = level.ghost_world if level and level.get("ghost_world") else null
	if gw == null or gw.room != def or not level.ghost_view.visible:
		return
	var tint: Color = level.ghost_view.modulate
	_draw_ghost_pickups(gw, tint)
	var bob := sin(time * 3.0) * 1.5
	var f2 := int(time * 4.0) % 2
	var sheet := Art.objects_ghost()
	var shape := Color(tint, GHOST_ITEM_ALPHA)
	for it in ghost_items(world, gw):
		var kind: String = it[0]
		var c := item_pos(gw, kind, it[1]) + Vector2(0, bob)
		if it[2] == "follow":
			c = ghost_follow.get("%s%d" % [kind, it[1]], c)
		match kind:
			"berry":
				if it[2] == "spot" and gw.berry_winged[it[1]] == 1:
					var wf := "wing%d" % (int(time * 10.0) % 2)
					_obj(wf, c + Vector2(4, -2), shape, false, sheet)
					_obj(wf, c + Vector2(-4, -2), shape, true, sheet)
				_obj("berry%d" % f2, c, shape, false, sheet)
			"bell": _obj("bell%d" % f2, c, shape, false, sheet)
			"key": _obj("key", c, shape, false, sheet)
			"golden": _obj("gold%d" % f2, c, shape, false, sheet)


## Procedural waving pennant on a pole (base at `base`).
## Strings of fluttering prayer flags from the summit pole down both slopes.
func _draw_prayer_flags(top: Vector2) -> void:
	var cols := [Color("d8344f"), Color("f2c14e"), Color("4fae5a"), Color("4f8ad8"), Color("f4efe6")]
	for side in [-1.0, 1.0]:
		var end := top + Vector2(side * 70.0, 36.0)
		var n := 28
		var prev := top
		for i in range(1, n + 1):
			var u := float(i) / n
			var p := top.lerp(end, u) + Vector2(0, sin(u * PI) * 9.0)
			draw_line(prev.round(), p.round(), Color("3a2a30"), 1.0)
			prev = p
			if i % 2 == 0 and i < n:
				var fc: Color = cols[(i / 2) % cols.size()]
				var flap := sin(time * 5.0 + u * 9.0 + side) * 1.2
				var fp := p.round()
				draw_colored_polygon(PackedVector2Array([fp, fp + Vector2(3, 0), fp + Vector2(3 + flap * 0.5, 4), fp + Vector2(flap * 0.5, 4)]), fc)
				draw_rect(Rect2(fp.x, fp.y + 3, 3, 1), fc.darkened(0.3))


func _draw_flag(base: Vector2) -> void:
	var top := base + Vector2(0, -20)
	draw_rect(Rect2(base.x - 1, top.y - 1, 2, 21), Color("1d1428"))
	draw_rect(Rect2(base.x, top.y, 1, 20), Color("9aa3b8"))
	draw_circle(top + Vector2(0.5, -1), 1.5, Color("f2c14e"))
	var pts := PackedVector2Array()
	var pts2 := PackedVector2Array()
	var n := 10
	for i in n + 1:
		var u := float(i) / n
		var wave := sin(time * 6.0 - u * 5.0) * 1.6 * u
		pts.append(top + Vector2(1 + u * 13.0, 1 + wave + u * 2.0))
	for i in range(n, -1, -1):
		var u := float(i) / n
		var wave := sin(time * 6.0 - u * 5.0) * 1.6 * u
		pts.append(top + Vector2(1 + u * 13.0, 8 - u * 3.0 + wave))
	draw_colored_polygon(pts, Color("d8344f"))
	# stripe + highlight
	for i in n:
		var u := float(i) / n
		var wave := sin(time * 6.0 - u * 5.0) * 1.6 * u
		var y0 := 1 + wave + u * 2.0
		var y1 := 8 - u * 3.0 + wave
		var x := top.x + 1 + u * 13.0
		draw_rect(Rect2(x, top.y + (y0 + y1) * 0.5 - 0.5, 1.4, 1), Color("f2c14e"))
		if sin(time * 6.0 - u * 5.0) > 0.6:
			draw_rect(Rect2(x, top.y + y0, 1.4, 1), Color(1, 1, 1, 0.35))


func _draw_npc(e: Dictionary) -> void:
	var name: String = e.get("name", "")
	if npc_hidden.has(name):
		return
	var feet := Vector2(e.cx * T + 4, e.cy * T + 8)
	var face_left := world.player_center().x < feet.x
	if npc_face.has(name):
		face_left = npc_face[name] < 0
	var talking: bool = level != null and level.has_method("speaker") and level.speaker() == name
	if name == "magpie":
		var tex := Art.tex("res://assets/sprites/magpie.png")
		var hop := absf(sin(time * 3.0)) * 2.0 if int(time) % 3 == 0 else 0.0
		var fi := int(time * 8.0) % 3 if (talking or hop > 0.0) else 0
		var dst := Rect2(feet.x - 4, feet.y - 8 - hop, 8, 8)
		if face_left:
			draw_set_transform(Vector2(feet.x * 2.0, 0), 0, Vector2(-1, 1))
		draw_texture_rect_region(tex, dst, Rect2(fi * 8, 0, 8, 8))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	var tex: Texture2D
	var frames: Array = Art.index().get("npc_frames", ["idle0"])
	var fname := "idle%d" % [0, 0, 1, 2, 3, 3, 3, 2, 1, 0, 4, 0][int((time + e.cx * 0.37) * 5.0) % 12]
	if talking:
		fname = "talk%d" % (int(time * 7.0) % 2)
	var fi := maxi(frames.find(fname), 0)
	var mod := Color.WHITE
	var off := Vector2.ZERO
	match name:
		"bellamy":
			tex = Art.tex("res://assets/sprites/npc_bellamy.png")
		"tobi":
			tex = Art.tex("res://assets/sprites/npc_tobi.png")
			if def.meta.get("end_style", "") == "fire":
				fi = maxi(frames.find("sit"), 0)
		"oddo":
			tex = Art.tex("res://assets/sprites/npc_oddo.png")
			mod = Color(1, 1, 1, 0.72 + 0.15 * sin(time * 2.0))
			off = Vector2(0, sin(time * 1.5) * 2.0 - 3.0)
		"grin":
			tex = Art.grin()
			var gframes: Array = Art.index().get("mira_frames", [])
			fi = maxi(gframes.find(fname if not talking else ("idle%d" % (int(time * 7.0) % 2))), 0)
			mod = Color(1, 1, 1, 0.92)
			off = Vector2(randi_range(-1, 1) if randf() < 0.04 else 0, 0)
		_:
			return
	# soft contact shadow
	draw_rect(Rect2(feet.x - 4, feet.y - 1, 8, 1), Color(0, 0, 0, 0.25))
	var dst := Rect2(feet.x - 12 + off.x, feet.y - 24 + off.y, 24, 24)
	if face_left:
		draw_set_transform(Vector2(feet.x * 2.0, 0), 0, Vector2(-1, 1))
	draw_texture_rect_region(tex, dst, Rect2(fi * 24, 0, 24, 24), mod)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if talking:
		# little speech marks above the head
		var bob := int(time * 6.0) % 2
		draw_rect(Rect2(feet.x + (-6 if face_left else 5), feet.y - 23 - bob, 1, 2), Color(1, 1, 1, 0.8))
		draw_rect(Rect2(feet.x + (-8 if face_left else 7), feet.y - 22 - bob, 1, 2), Color(1, 1, 1, 0.6))
