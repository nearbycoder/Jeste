extends Node2D
## Title screen with options menu.

var time := 0.0
var sel := 0
var items: Array = []
var screen := "main"     # main | options | confirm_reset
var opt_sel := 0
var backdrop: Backdrop
var juggle_t := 0.0
var fade := 1.0
var leaving := ""

const OPTIONS := ["Music Volume", "Sound Volume", "Fullscreen", "Screen Shake", "Speedrun Timer", "Erase Save", "Back"]


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	backdrop = Backdrop.new()
	layer.add_child(backdrop)
	var post := PostFX.new()
	add_child(post)
	post.setup(0)
	backdrop.setup(0)
	_build_items()
	Sfx.play_music("title")


func _build_items() -> void:
	items = []
	if not Game.data.get("resume", {}).is_empty():
		items.append("Continue")
	items.append("Climb")
	items.append("Options")
	items.append("Credits")
	if OS.get_name() != "Web":
		items.append("Quit")
	sel = clampi(sel, 0, items.size() - 1)


func _process(delta: float) -> void:
	time += delta
	juggle_t += delta
	backdrop.cam_pos.x = time * 12.0
	if leaving != "":
		fade = minf(fade + delta * 2.5, 1.0)
		if fade >= 1.0:
			_go(leaving)
	else:
		fade = maxf(fade - delta * 1.5, 0.0)
	queue_redraw()


func _go(what: String) -> void:
	match what:
		"Continue":
			var r: Dictionary = Game.data.resume
			Game.start_chapter(int(r.chapter), str(r.room))
		"Climb":
			Game.goto_chapter_select()
		"Credits":
			Game.goto_credits()


func _unhandled_input(ev: InputEvent) -> void:
	if leaving != "":
		return
	match screen:
		"main":
			if ev.is_action_pressed("up"):
				sel = (sel + items.size() - 1) % items.size()
				Sfx.play("menu_move")
			elif ev.is_action_pressed("down"):
				sel = (sel + 1) % items.size()
				Sfx.play("menu_move")
			elif ev.is_action_pressed("confirm"):
				Sfx.play("menu_select")
				var it: String = items[sel]
				match it:
					"Options":
						screen = "options"
						opt_sel = 0
					"Quit":
						get_tree().quit()
					_:
						leaving = it
		"options":
			if ev.is_action_pressed("up"):
				opt_sel = (opt_sel + OPTIONS.size() - 1) % OPTIONS.size()
				Sfx.play("menu_move")
			elif ev.is_action_pressed("down"):
				opt_sel = (opt_sel + 1) % OPTIONS.size()
				Sfx.play("menu_move")
			elif ev.is_action_pressed("left") or ev.is_action_pressed("right") or ev.is_action_pressed("confirm"):
				var d := -1 if ev.is_action_pressed("left") else 1
				_change_option(d, ev.is_action_pressed("confirm"))
			elif ev.is_action_pressed("back"):
				screen = "main"
				Game.save_settings()
		"confirm_reset":
			if ev.is_action_pressed("confirm"):
				Game.reset_save()
				_build_items()
				screen = "options"
				Sfx.play("death")
			elif ev.is_action_pressed("back"):
				screen = "options"


func _change_option(d: int, confirm: bool) -> void:
	Sfx.play("menu_select")
	match OPTIONS[opt_sel]:
		"Music Volume":
			Game.settings.music = clampf(snappedf(float(Game.settings.music) + 0.1 * d, 0.1), 0.0, 1.0)
			Sfx.refresh_volume()
		"Sound Volume":
			Game.settings.sfx = clampf(snappedf(float(Game.settings.sfx) + 0.1 * d, 0.1), 0.0, 1.0)
		"Fullscreen":
			Game.settings.fullscreen = not Game.settings.fullscreen
			Game.apply_settings()
		"Screen Shake":
			Game.settings.screen_shake = not Game.settings.screen_shake
		"Speedrun Timer":
			Game.settings.show_timer = not Game.settings.show_timer
		"Erase Save":
			if confirm:
				screen = "confirm_reset"
		"Back":
			if confirm:
				screen = "main"
	Game.save_settings()


func _draw_logo(y: float) -> void:
	var text := "JESTE"
	var sc := 4.0
	var w := PixelText.width(text) * sc
	var x := 160.0 - w / 2.0
	for i in text.length():
		var c := text[i]
		var cw := PixelText.char_width(c) + 1
		var bob := sin(time * 2.0 + i * 0.7) * 2.0
		draw_set_transform(Vector2(x + 2, y + bob + 3), 0, Vector2(sc, sc))
		PixelText.draw(self, Vector2.ZERO, c, Color("1c1424"))
		var col := Color("e03a5a") if i % 2 == 0 else Color("f2c14e")
		draw_set_transform(Vector2(x, y + bob), 0, Vector2(sc, sc))
		PixelText.draw(self, Vector2.ZERO, c, col)
		x += cw * sc
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# jester cap on the J
	var jx := 160.0 - w / 2.0 + 6
	var pts := PackedVector2Array([Vector2(jx - 6, y - 2), Vector2(jx - 14, y - 12), Vector2(jx + 2, y - 6), Vector2(jx + 10, y - 16), Vector2(jx + 10, y - 2)])
	draw_colored_polygon(pts, Color("e03a5a"))
	draw_circle(Vector2(jx - 14, y - 12), 2, Color("f2c14e"))
	draw_circle(Vector2(jx + 10, y - 16), 2, Color("f2c14e"))


func _draw() -> void:
	_draw_logo(26)
	PixelText.draw_centered(self, 160, 64, "a mountain that laughs back", Color(1, 0.92, 0.8), Color(0, 0, 0, 0.7))
	# Mira juggling on a ledge
	var base := Vector2(250, 150)
	draw_rect(Rect2(226, 151, 60, 30), Color("1f1418"))
	draw_rect(Rect2(226, 151, 60, 2), Color("4f9a3a"))
	var frame := Art.frame_index("talk%d" % (int(juggle_t * 4.4) % 2))
	draw_set_transform(base, 0, Vector2(-1, 1))
	draw_texture_rect_region(Art.player_menu(), Rect2(-12, -24, 24, 24), Rect2(frame * 24, 0, 24, 24), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for i in 3:
		var t := juggle_t * 2.2 + i * TAU / 3.0
		var p := base + Vector2(cos(t) * 7.0, -18.0 - absf(sin(t)) * 14.0)
		var names := ["ball_r", "ball_y", "ball_u"]
		draw_texture_rect_region(Art.objects(), Rect2(p.x - 8, p.y - 8, 16, 16), Art.obj_rect(names[i]))
	match screen:
		"main":
			for i in items.size():
				var s := i == sel
				var txt: String = items[i]
				if s:
					txt = "> " + txt + " <"
				PixelText.draw_centered(self, 120, 92 + i * 13, txt, Color.WHITE if s else Color(0.75, 0.72, 0.85), Color(0, 0, 0, 0.8))
		"options":
			draw_rect(Rect2(40, 80, 170, 96), Color(0.05, 0.03, 0.09, 0.9))
			draw_rect(Rect2(40, 80, 170, 96), Color("f2c14e"), false, 1.0)
			for i in OPTIONS.size():
				var s := i == opt_sel
				var col := Color.WHITE if s else Color(0.75, 0.72, 0.85)
				PixelText.draw(self, Vector2(48, 85 + i * 12), ("> " if s else "  ") + OPTIONS[i], col)
				var v := _opt_value(OPTIONS[i])
				PixelText.draw(self, Vector2(202 - PixelText.width(v), 85 + i * 12), v, Color("8ab4ff"))
		"confirm_reset":
			draw_rect(Rect2(50, 90, 220, 50), Color(0.08, 0.02, 0.04, 0.95))
			draw_rect(Rect2(50, 90, 220, 50), Color("e03a5a"), false, 1.0)
			PixelText.draw_centered(self, 160, 98, "Erase ALL progress?", Color.WHITE)
			PixelText.draw_centered(self, 160, 116, "Jump: erase    Dash: keep", Color(0.9, 0.8, 0.8))
	PixelText.draw(self, Vector2(4, 170), "Move: Arrows  Jump: C  Dash: X  Grab: Z", Color(1, 1, 1, 0.6), Color(0, 0, 0, 0.6))
	if fade > 0.0:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.05, 0.04, 0.08, fade))


func _opt_value(name: String) -> String:
	match name:
		"Music Volume": return "%d%%" % int(round(float(Game.settings.music) * 100))
		"Sound Volume": return "%d%%" % int(round(float(Game.settings.sfx) * 100))
		"Fullscreen": return "On" if Game.settings.fullscreen else "Off"
		"Screen Shake": return "On" if Game.settings.screen_shake else "Off"
		"Speedrun Timer": return "On" if Game.settings.show_timer else "Off"
	return ""
