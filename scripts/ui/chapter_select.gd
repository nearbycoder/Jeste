extends Node2D
## Chapter select: browse unlocked chapters with their collectible stats.

var sel := 0
var time := 0.0
var backdrop: Backdrop
var slide := 0.0
var confirm_resume := false
var resume_sel := 0
var fade := 1.0
var leaving := -1
var leaving_room := ""


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	backdrop = Backdrop.new()
	layer.add_child(backdrop)
	var post := PostFX.new()
	add_child(post)
	post.setup(sel)
	var r: Dictionary = Game.data.get("resume", {})
	sel = int(r.chapter) if not r.is_empty() else mini(int(Game.data.unlocked), LevelDB.chapter_count() - 1)
	backdrop.setup(sel)
	Sfx.play_music("map")


func _unlocked(n: int) -> bool:
	return n <= int(Game.data.unlocked)


func _process(delta: float) -> void:
	time += delta
	backdrop.cam_pos.x = time * 10.0
	slide = move_toward(slide, 0.0, delta * 6.0)
	if leaving >= 0:
		fade = minf(fade + delta * 2.5, 1.0)
		if fade >= 1.0:
			Game.start_chapter(leaving, leaving_room)
	else:
		fade = maxf(fade - delta * 2.0, 0.0)
	queue_redraw()


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
		sel -= 1
		slide = -1.0
		backdrop.setup(sel)
		Sfx.play("menu_move")
	elif ev.is_action_pressed("right") and sel < n - 1 and _unlocked(sel + 1):
		sel += 1
		slide = 1.0
		backdrop.setup(sel)
		Sfx.play("menu_move")
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


func _draw() -> void:
	var ch := LevelDB.get_chapter(sel)
	var cx := 160.0 + slide * 40.0
	# Card
	var card := Rect2(cx - 110, 40, 220, 104)
	draw_rect(card, Color(0.05, 0.03, 0.09, 0.88))
	draw_rect(card, Color("f2c14e"), false, 1.0)
	var title: String = Game.CHAPTER_TITLES[sel]
	PixelText.draw_centered(self, cx, 48, title, Color("f2c14e"))
	if not _unlocked(sel):
		PixelText.draw_centered(self, cx, 80, "Locked", Color(0.6, 0.6, 0.7))
	else:
		PixelText.draw_centered(self, cx, 60, ch.name, Color.WHITE, Color(0, 0, 0, 0.8))
		PixelText.draw_centered(self, cx, 72, ch.subtitle, Color(0.8, 0.78, 0.9))
		var cd := Game.chapter_data(sel)
		var berries := Game.berries_in_chapter(sel)
		var total := ch.berry_count()
		draw_texture_rect_region(Art.objects(), Rect2(cx - 96, 88, 16, 16), Art.obj_rect("berry0"))
		PixelText.draw(self, Vector2(cx - 78, 92), "%d/%d" % [berries, total], Color.WHITE)
		if ch.has_bell():
			var got := Game.bell_in_chapter(sel)
			draw_texture_rect_region(Art.objects(), Rect2(cx - 36, 88, 16, 16), Art.obj_rect("bell0" if got else "bell_ghost"))
			PixelText.draw(self, Vector2(cx - 18, 92), "Found" if got else "???", Color.WHITE if got else Color(0.6, 0.6, 0.7))
		if cd.get("golden", false):
			draw_texture_rect_region(Art.objects(), Rect2(cx + 24, 88, 16, 16), Art.obj_rect("gold0"))
		PixelText.draw(self, Vector2(cx - 96, 110), "Deaths: %d" % int(cd.deaths), Color(0.85, 0.85, 0.9))
		var bt := float(cd.best_time)
		var bts := "--:--" if bt <= 0.0 else "%d:%02d.%02d" % [int(bt / 60.0), int(bt) % 60, int(fmod(bt, 1.0) * 100)]
		PixelText.draw(self, Vector2(cx + 4, 110), "Best: " + bts, Color(0.85, 0.85, 0.9))
		if cd.get("complete", false):
			PixelText.draw_centered(self, cx, 126, "Complete", Color("8aff6e"))
		else:
			var blink := 0.6 + 0.4 * sin(time * 4.0)
			PixelText.draw_centered(self, cx, 126, "Press Jump to climb", Color(1, 1, 1, blink))
	# arrows
	if sel > 0:
		PixelText.draw(self, Vector2(cx - 128, 86), "<", Color.WHITE)
	if sel < LevelDB.chapter_count() - 1 and _unlocked(sel + 1):
		PixelText.draw(self, Vector2(cx + 124, 86), ">", Color.WHITE)
	# totals
	PixelText.draw(self, Vector2(6, 6), "Sunberries: %d" % Game.total_berries(), Color.WHITE, Color(0, 0, 0, 0.8))
	PixelText.draw(self, Vector2(6, 16), "Jester Bells: %d" % Game.total_bells(), Color.WHITE, Color(0, 0, 0, 0.8))
	PixelText.draw(self, Vector2(6, 26), "Deaths: %d" % int(Game.data.total_deaths), Color.WHITE, Color(0, 0, 0, 0.8))
	# dots
	for i in LevelDB.chapter_count():
		var col := Color("f2c14e") if i == sel else (Color.WHITE if _unlocked(i) else Color(0.4, 0.4, 0.5))
		draw_rect(Rect2(160 - LevelDB.chapter_count() * 4 + i * 8, 156, 4, 4), col)
	PixelText.draw_centered(self, 160, 166, "Left/Right: choose   Jump: start   Dash: back", Color(1, 1, 1, 0.6), Color(0, 0, 0, 0.6))
	if confirm_resume:
		draw_rect(Rect2(80, 70, 160, 50), Color(0.05, 0.03, 0.09, 0.95))
		draw_rect(Rect2(80, 70, 160, 50), Color("f2c14e"), false, 1.0)
		var opts := ["Continue from checkpoint", "Restart chapter"]
		for i in 2:
			var s := i == resume_sel
			PixelText.draw_centered(self, 160, 80 + i * 14, ("> " if s else "") + opts[i] + (" <" if s else ""), Color.WHITE if s else Color(0.7, 0.7, 0.8))
	if fade > 0.0:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.05, 0.04, 0.08, fade))
