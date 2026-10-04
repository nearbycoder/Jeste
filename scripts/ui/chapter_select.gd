extends Node2D
## Chapter select: a framed card per chapter with a living postcard (parallax
## backdrop + the chapter's painted opening room), collectible stats and a
## trail of chapter markers along the bottom.

var sel := 0
var time := 0.0
var backdrop: Backdrop
var post: PostFX
var slide := 0.0
var confirm_resume := false
var resume_sel := 0
var resume_k: Array = [0.0, 0.0]
var wipe := 1.0
var leaving := -1
var leaving_room := ""
var marker_x := 0.0
var card_flash := 0.0
var pc_vp: SubViewport
var pc_view: RoomView
var pc_world: World
var pc_for := -1

static var _cards: Dictionary = {}

const CARD := Rect2(14, 26, 292, 108)
const PC := Rect2(22, 37, 150, 89)     # postcard
const POSTCARD_ROOM := {3: "3-02", 5: "5-02"}


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	backdrop = Backdrop.new()
	layer.add_child(backdrop)
	post = PostFX.new()
	add_child(post)
	var r: Dictionary = Game.data.get("resume", {})
	sel = int(r.chapter) if not r.is_empty() else mini(int(Game.data.unlocked), LevelDB.chapter_count() - 1)
	backdrop.setup(sel)
	post.setup(sel)
	marker_x = _marker_pos(sel).x
	pc_vp = SubViewport.new()
	pc_vp.size = Vector2i(int(PC.size.x), int(PC.size.y))
	pc_vp.transparent_bg = true
	pc_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pc_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(pc_vp)
	# paint the postcard rooms in the background, nearest chapters first
	var order := range(LevelDB.chapter_count())
	order.sort_custom(func(a, b): return absi(a - sel) < absi(b - sel))
	for n in order:
		if _unlocked(n):
			var info := _card(n)
			RoomView.prebake(LevelDB.get_chapter(n).rooms[info.rid], info.ts)
	Sfx.play_music("map")
	Sfx.play_ambience("")


func _exit_tree() -> void:
	RoomView.flush_bakes()


func _unlocked(n: int) -> bool:
	return n <= int(Game.data.unlocked)


func _process(delta: float) -> void:
	time += delta
	backdrop.cam_pos.x = time * 10.0
	slide = move_toward(slide, 0.0, delta * 5.0)
	card_flash = maxf(card_flash - delta * 3.0, 0.0)
	marker_x = lerpf(marker_x, _marker_pos(sel).x, minf(delta * 10.0, 1.0))
	for i in 2:
		resume_k[i] = move_toward(resume_k[i], 1.0 if i == resume_sel else 0.0, delta * 8.0)
	if leaving >= 0:
		wipe = minf(wipe + delta * 2.2, 1.0)
		if wipe >= 1.0:
			Game.start_chapter(leaving, leaving_room)
	else:
		wipe = maxf(wipe - delta * 1.8, 0.0)
	queue_redraw()


func _select(n: int, dir: float) -> void:
	sel = n
	slide = dir
	card_flash = 1.0
	backdrop.setup(sel)
	post.setup(sel)
	Sfx.play("menu_move")


func _unhandled_input(ev: InputEvent) -> void:
	if leaving >= 0:
		return
	if confirm_resume:
		if ev.is_action_pressed("up") or ev.is_action_pressed("down"):
			resume_sel = 1 - resume_sel
			Sfx.play("menu_move")
		elif ev.is_action_pressed("confirm"):
			Sfx.play("menu_select")
			var r: Dictionary = Game.data.resume
			leaving = sel
			leaving_room = str(r.room) if resume_sel == 0 else ""
		elif ev.is_action_pressed("back"):
			confirm_resume = false
		return
	var n := LevelDB.chapter_count()
	if ev.is_action_pressed("left") and sel > 0:
		_select(sel - 1, -1.0)
	elif ev.is_action_pressed("right") and sel < n - 1 and _unlocked(sel + 1):
		_select(sel + 1, 1.0)
	elif ev.is_action_pressed("confirm") and _unlocked(sel):
		Sfx.play("menu_select")
		var r: Dictionary = Game.data.get("resume", {})
		if not r.is_empty() and int(r.chapter) == sel and str(r.room) != LevelDB.get_chapter(sel).start:
			confirm_resume = true
			resume_sel = 0
		else:
			leaving = sel
			leaving_room = ""
	elif ev.is_action_pressed("back"):
		Game.goto_title()


# ---------------------------------------------------------------- postcard

## Composes the chapter's opening room (bg, terrain, hangers, Mira at the
## spawn) cropped to the postcard window. Cached per chapter.
static func _card(n: int) -> Dictionary:
	if _cards.has(n):
		return _cards[n]
	var ch := LevelDB.get_chapter(n)
	var rid: String = POSTCARD_ROOM.get(n, ch.start)
	if not ch.rooms.has(rid):
		rid = ch.start
	var def: RoomDef = ch.rooms[rid]
	var ts: String = str(def.meta.get("tileset", ch.tileset if ch.tileset != "" else Art.CHAPTER_TILESETS[n]))
	var W := def.w * 8
	var H := def.h * 8
	var sp := Vector2i(2, def.h - 3)
	if not def.spawns.is_empty():
		sp = def.spawns[0]
	var feet := Vector2i(sp.x * 8 + 4, sp.y * 8 + 8)
	# pick the most interesting window: terrain edges + entities, Mira preferred
	var cw := int(PC.size.x) / 8
	var chh := int(PC.size.y) / 8 + 1
	var edge := PackedFloat32Array()
	edge.resize(def.w * def.h)
	for cy in def.h:
		for cx in def.w:
			var t := def.cells[cy * def.w + cx]
			if t == RoomDef.EMPTY or t == RoomDef.BGWALL:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nt := def.cell(cx + d.x, cy + d.y)
					if nt != RoomDef.EMPTY and nt != RoomDef.BGWALL:
						edge[cy * def.w + cx] = 1
						break
			elif t == RoomDef.CURTAIN:
				edge[cy * def.w + cx] = 0.12
			elif t != RoomDef.SOLID and t != RoomDef.SOLID_ALT:
				edge[cy * def.w + cx] = 1.5
	var best := -1.0
	var x0 := 0
	var y0 := 0
	for oy in range(0, maxi(def.h - chh, 0) + 1):
		for ox in range(0, maxi(def.w - cw, 0) + 1):
			var sc := 0.0
			for cy in range(oy, mini(oy + chh, def.h)):
				for cx in range(ox, mini(ox + cw, def.w)):
					sc += edge[cy * def.w + cx]
			for e in def.entities:
				if e.cx >= ox and e.cx < ox + cw and e.cy >= oy and e.cy < oy + chh:
					sc += 8.0
			if sp.x >= ox + 1 and sp.x < ox + cw - 1 and sp.y >= oy + 2 and sp.y < oy + chh - 1:
				sc += 25.0
			if sc > best:
				best = sc
				x0 = ox * 8
				y0 = oy * 8
	x0 = clampi(x0, 0, maxi(W - int(PC.size.x), 0))
	y0 = clampi(y0, 0, maxi(H - int(PC.size.y), 0))
	var d := {"rid": rid, "ts": ts, "crop": Vector2(x0, y0), "feet": Vector2(feet)}
	_cards[n] = d
	return d


## Live postcard: the real RoomView of the chosen room in a transparent
## SubViewport, so curtains ripple, gems spin and NPCs breathe.
func _ensure_postcard(n: int) -> void:
	if pc_for == n:
		return
	pc_for = n
	if pc_view:
		pc_view.queue_free()
		pc_view = null
	if not _unlocked(n):
		return
	var info := _card(n)
	var ch := LevelDB.get_chapter(n)
	var def: RoomDef = ch.rooms[info.rid]
	if not RoomView.is_painted(def, info.ts):
		pc_for = -1   # try again next frame
		return
	pc_world = World.new()
	pc_world.load_room(def, 0, ch.dashes)
	pc_world.x = -100   # keep the (unused) player far away from triggers / NPC facing
	pc_view = RoomView.new()
	pc_vp.add_child(pc_view)
	pc_view.build(def, pc_world, info.ts, n)
	pc_view.position = -(info.crop as Vector2)


func _draw_postcard(r: Rect2, n: int, a: float) -> void:
	# living backdrop: sky + slowly panning parallax layers, clipped to the card
	var sky := Art.bg(n, "sky")
	if sky:
		draw_texture_rect_region(sky, r, Rect2(170 - r.size.x / 2.0, 40, r.size.x, r.size.y), Color(1, 1, 1, a))
	var pans := {"far": 3.0, "mid": 7.0, "near": 13.0}
	for k in ["far", "mid", "near"]:
		var tex := Art.bg(n, k)
		if tex == null:
			continue
		var w := tex.get_width()
		var ox := fposmod(time * pans[k], w)
		var oy := 40.0
		var first := minf(r.size.x, w - ox)
		draw_texture_rect_region(tex, Rect2(r.position, Vector2(first, r.size.y)), Rect2(ox, oy, first, r.size.y), Color(1, 1, 1, a))
		if first < r.size.x:
			draw_texture_rect_region(tex, Rect2(r.position + Vector2(first, 0), Vector2(r.size.x - first, r.size.y)), Rect2(0, oy, r.size.x - first, r.size.y), Color(1, 1, 1, a))
	if _unlocked(n):
		_ensure_postcard(n)
		if pc_for == n:
			draw_texture(pc_vp.get_texture(), r.position, Color(1, 1, 1, a))
		var info := _card(n)
		var mira := (info.feet as Vector2) - (info.crop as Vector2)
		var fi := Art.frame_index("idle%d" % [0, 0, 1, 2, 3, 3, 3, 2, 1, 0, 4, 0][int(time * 5.0) % 12])
		var dst := Rect2(r.position + mira - Vector2(12, 24), Vector2(24, 24))
		if r.encloses(dst.grow(-6)):
			draw_texture_rect_region(Art.player_menu(), dst, Rect2(fi * 24, 0, 24, 24), Color(1, 1, 1, a))
	else:
		draw_rect(r, Color(0.04, 0.03, 0.07, 0.82 * a))
		_draw_lock(r.get_center(), a)
	# inner frame + vignette corners
	UIKit.frame(self, r.grow(1), Color(UIKit.INK, a))
	UIKit.frame(self, r.grow(2), Color(UIKit.GOLD, a))
	UIKit.frame(self, r.grow(3), Color(UIKit.INK, a))
	if card_flash > 0.0:
		draw_rect(r, Color(1, 1, 1, card_flash * 0.25))


func _draw_lock(c: Vector2, a: float) -> void:
	var p := c.round()
	draw_arc(p + Vector2(0, -4), 5, PI, TAU, 12, Color(UIKit.MUTED, a), 2.0)
	draw_rect(Rect2(p.x - 7, p.y - 3, 14, 11), Color(UIKit.INK, a))
	draw_rect(Rect2(p.x - 6, p.y - 2, 12, 9), Color(UIKit.MUTED.darkened(0.2), a))
	draw_rect(Rect2(p.x - 1, p.y + 1, 2, 3), Color(UIKit.INK, a))


# ---------------------------------------------------------------- path markers

func _marker_pos(i: int) -> Vector2:
	var n := LevelDB.chapter_count()
	var span := 248.0
	var x := 160.0 - span / 2.0 + span * i / float(n - 1)
	return Vector2(roundf(x), 155.0 + roundf(sin(i * 1.3) * 1.5))


func _draw_path() -> void:
	var n := LevelDB.chapter_count()
	for i in n - 1:
		var p0 := _marker_pos(i)
		var p1 := _marker_pos(i + 1)
		var lit := _unlocked(i + 1)
		var steps := int(p0.distance_to(p1) / 3.0)
		for s in steps:
			if s % 2 == 0:
				var q := p0.lerp(p1, (s + 0.5) / steps).round()
				draw_rect(Rect2(q, Vector2(2, 1)), Color(UIKit.GOLD, 0.8) if lit else Color(UIKit.MUTED, 0.35))
	for i in n:
		var p := _marker_pos(i)
		var cd := Game.chapter_data(i)
		var col := UIKit.MUTED.darkened(0.45)
		if _unlocked(i):
			col = UIKit.CREAM
		if cd.get("complete", false):
			col = UIKit.GOLD
		var r := 3.0 if i == sel else 2.0
		UIKit.diamond(self, p, r + 1.0, UIKit.INK)
		UIKit.diamond(self, p, r, col)
		if cd.get("golden", false):
			draw_rect(Rect2(p + Vector2(-0.5, -6), Vector2(1, 1)), UIKit.GOLD)
	# Mira's marker hops between chapters
	var mp := Vector2(marker_x, _marker_pos(sel).y)
	var hop := absf(sin(time * 4.0)) * 2.0
	var ring := fmod(time, 1.2) / 1.2
	draw_arc(mp, 4.0 + ring * 6.0, 0, TAU, 16, Color(UIKit.GOLD, 0.6 * (1.0 - ring)), 1.0)
	var fi := Art.frame_index("idle0")
	draw_texture_rect_region(Art.player_menu(), Rect2((mp + Vector2(-12, -23 - hop)).round(), Vector2(24, 24)), Rect2(fi * 24, 0, 24, 24))


# ---------------------------------------------------------------- draw

func _draw() -> void:
	var ch := LevelDB.get_chapter(sel)
	var off := roundf(slide * 24.0)
	var a := 1.0 - absf(slide) * 0.6
	UIKit.panel(self, CARD)
	UIKit.panel_title(self, CARD, Game.CHAPTER_TITLES[sel])
	_draw_postcard(Rect2(PC.position + Vector2(off, 0), PC.size), sel, a)
	# text column
	var tx := 184.0 + off
	var ty := 40.0
	if not _unlocked(sel):
		PixelText.draw_outlined(self, Vector2(tx, ty), "???", Color(UIKit.MUTED, a), Color(UIKit.INK, a))
		PixelText.draw(self, Vector2(tx, ty + 14), "Climb on to reveal", Color(UIKit.MUTED, 0.7 * a))
	else:
		var lines := PixelText.wrap(ch.name, 112)
		for i in lines.size():
			PixelText.draw_outlined(self, Vector2(tx, ty + i * 10), lines[i], Color(UIKit.CREAM, a), Color(UIKit.INK, a))
		ty += lines.size() * 10 + 2
		var sub := PixelText.wrap(ch.subtitle, 112)
		for i in sub.size():
			PixelText.draw(self, Vector2(tx, ty + i * 9), sub[i], Color(UIKit.MUTED, 0.85 * a))
		draw_rect(Rect2(tx, 92, 110, 1), Color(UIKit.GOLD, 0.35 * a))
		var cd := Game.chapter_data(sel)
		var y := 97.0
		var total := ch.berry_count()
		if total > 0:
			var got := Game.berries_in_chapter(sel)
			var bob := roundf(sin(time * 3.0) * 1.0)
			draw_texture_rect_region(Art.objects(), Rect2(tx - 3, y - 4 + bob, 16, 16), Art.obj_rect("berry0"))
			PixelText.draw(self, Vector2(tx + 14, y), "%d / %d" % [got, total], Color(UIKit.GOLD if got == total else Color.WHITE, a))
		if ch.has_bell():
			var bgot := Game.bell_in_chapter(sel)
			draw_texture_rect_region(Art.objects(), Rect2(tx + 54, y - 4, 16, 16), Art.obj_rect("bell0" if bgot else "bell_ghost"), Color(1, 1, 1, a if bgot else 0.6 * a))
		if cd.get("golden", false):
			var gb := roundf(sin(time * 3.0 + 1.0) * 1.0)
			draw_texture_rect_region(Art.objects(), Rect2(tx + 74, y - 4 + gb, 16, 16), Art.obj_rect("gold0"))
		y += 14
		PixelText.draw(self, Vector2(tx, y), "Deaths", Color(UIKit.MUTED, a))
		var ds := str(int(cd.deaths))
		PixelText.draw(self, Vector2(tx + 110 - PixelText.width(ds), y), ds, Color(Color.WHITE, a))
		y += 10
		var bt := float(cd.best_time)
		var bts := "--:--" if bt <= 0.0 else "%d:%02d.%02d" % [int(bt / 60.0), int(bt) % 60, int(fmod(bt, 1.0) * 100)]
		PixelText.draw(self, Vector2(tx, y), "Best", Color(UIKit.MUTED, a))
		PixelText.draw(self, Vector2(tx + 110 - PixelText.width(bts), y), bts, Color(Color.WHITE, a))
		if cd.get("complete", false):
			_draw_stamp(Vector2(PC.end.x - 22 + off, PC.position.y + 14), a)
	# arrows
	var bounce := roundf(sin(time * 5.0) * 1.5)
	if sel > 0:
		_draw_arrow(Vector2(6 - bounce, CARD.get_center().y), -1.0)
	if sel < LevelDB.chapter_count() - 1 and _unlocked(sel + 1):
		_draw_arrow(Vector2(314 + bounce, CARD.get_center().y), 1.0)
	# totals, top left
	var tot_x := 6.0
	draw_texture_rect_region(Art.objects(), Rect2(tot_x - 3, 2, 16, 16), Art.obj_rect("berry0"))
	PixelText.draw_outlined(self, Vector2(tot_x + 13, 6), str(Game.total_berries()), UIKit.CREAM, UIKit.INK)
	draw_texture_rect_region(Art.objects(), Rect2(tot_x + 34, 2, 16, 16), Art.obj_rect("bell0"))
	PixelText.draw_outlined(self, Vector2(tot_x + 50, 6), str(Game.total_bells()), UIKit.CREAM, UIKit.INK)
	var dstr := "Deaths %d" % int(Game.data.total_deaths)
	PixelText.draw_outlined(self, Vector2(314 - PixelText.width(dstr), 6), dstr, UIKit.CREAM, UIKit.INK)
	_draw_path()
	var pairs := [["Arrows", "Choose"], [Game.key_label("jump"), "Climb"], [Game.key_label("dash"), "Back"]]
	UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 167), pairs, 0.9)
	if confirm_resume:
		draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.45))
		var r := Rect2(80, 66, 160, 46)
		UIKit.panel(self, r)
		UIKit.panel_title(self, r, "Welcome back")
		var opts := ["Continue from checkpoint", "Restart chapter"]
		for i in 2:
			UIKit.menu_row(self, r.position.x + 8, r.position.y + 12 + i * 14, 144, opts[i], resume_k[i], time, 1.0, true)
	UIKit.wipe(self, wipe, -1.0 if leaving < 0 else 1.0)


func _draw_arrow(c: Vector2, dir: float) -> void:
	var p := c.round()
	var pts := PackedVector2Array([p + Vector2(-3 * dir, -5), p + Vector2(3 * dir, 0), p + Vector2(-3 * dir, 5)])
	var o := PackedVector2Array([p + Vector2(-4 * dir, -7), p + Vector2(5 * dir, 0), p + Vector2(-4 * dir, 7)])
	draw_colored_polygon(o, UIKit.INK)
	draw_colored_polygon(pts, UIKit.GOLD)


func _draw_stamp(c: Vector2, a: float) -> void:
	# a little "cleared" wax seal
	var p := c.round()
	draw_circle(p, 10, Color(UIKit.INK, a))
	draw_circle(p, 9, Color(UIKit.CRIMSON, a))
	draw_circle(p + Vector2(-1, -1), 6, Color(UIKit.CRIMSON.lightened(0.15), a))
	draw_arc(p, 7, 0, TAU, 20, Color(UIKit.CRIMSON.darkened(0.3), a), 1.0)
	var pts := PackedVector2Array([p + Vector2(-4, 0), p + Vector2(-1, 3), p + Vector2(4, -3)])
	draw_polyline(pts, Color(UIKit.CREAM, a), 2.0)
