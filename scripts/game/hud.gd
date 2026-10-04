class_name Hud
extends Node2D
## Screen-space overlay: berry counter, title cards, timer, pause menu,
## chapter-complete screen and screen wipes. Lives inside a CanvasLayer.

signal pause_choice(choice: String)
signal results_closed

var level: Node
var time := 0.0

# Berry counter
var berry_show := 0.0
var berry_count := 0
var berry_total := 0
var bell_show := 0.0

# Title cards
var title_text := ""
var title_sub := ""
var title_t := 0.0
var title_dur := 0.0
var room_title := ""
var room_title_t := 0.0

# Wipe: 0 = clear, 1 = fully covered
var wipe := 0.0
var wipe_target := 0.0
var wipe_speed := 4.0
var wipe_dir := 1.0

# Pause menu
var paused := false
var pause_items := ["Resume", "Retry Room", "Assist", "Return to Map"]
var pause_sel := 0
var assist_open := false
var assist_items := ["Game Speed", "Infinite Stamina", "Invincibility", "Back"]
var assist_sel := 0

# Results
var results := false
var results_data: Dictionary = {}
var results_t := 0.0

var show_timer := false
var timer_value := 0.0
var flash := 0.0


func _process(delta: float) -> void:
	time += delta
	berry_show = maxf(berry_show - delta, 0.0)
	bell_show = maxf(bell_show - delta, 0.0)
	title_t += delta
	room_title_t += delta
	flash = maxf(flash - delta * 3.0, 0.0)
	wipe = move_toward(wipe, wipe_target, wipe_speed * delta)
	if results:
		results_t += delta
	queue_redraw()


func show_berry(count: int, total: int) -> void:
	berry_count = count
	berry_total = total
	berry_show = 3.0


func show_title(text: String, sub: String, dur: float = 3.5) -> void:
	title_text = text
	title_sub = sub
	title_t = 0.0
	title_dur = dur


func show_room_title(text: String) -> void:
	room_title = text
	room_title_t = 0.0


func open_pause() -> void:
	paused = true
	pause_sel = 0
	assist_open = false


func close_pause() -> void:
	paused = false


func show_results(d: Dictionary) -> void:
	results = true
	results_data = d
	results_t = 0.0


func handle_menu_input(ev: InputEvent) -> bool:
	if results:
		if results_t > 1.0 and ev.is_action_pressed("confirm"):
			results = false
			results_closed.emit()
		return true
	if not paused:
		return false
	if assist_open:
		if ev.is_action_pressed("up"):
			assist_sel = (assist_sel + assist_items.size() - 1) % assist_items.size()
			Sfx.play("menu_move")
		elif ev.is_action_pressed("down"):
			assist_sel = (assist_sel + 1) % assist_items.size()
			Sfx.play("menu_move")
		elif ev.is_action_pressed("confirm") or ev.is_action_pressed("left") or ev.is_action_pressed("right"):
			var dir := -1 if ev.is_action_pressed("left") else 1
			match assist_sel:
				0:
					var speeds := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
					var i := speeds.find(float(Game.settings.game_speed))
					if i < 0: i = 5
					i = clampi(i + dir, 0, speeds.size() - 1) if not ev.is_action_pressed("confirm") else (i + 1) % speeds.size()
					Game.settings.game_speed = speeds[i]
				1:
					Game.settings.infinite_stamina = not Game.settings.infinite_stamina
				2:
					Game.settings.invincible = not Game.settings.invincible
				3:
					if ev.is_action_pressed("confirm"):
						assist_open = false
			Game.save_settings()
			pause_choice.emit("assist_changed")
			Sfx.play("menu_select")
		elif ev.is_action_pressed("back"):
			assist_open = false
		return true
	if ev.is_action_pressed("up"):
		pause_sel = (pause_sel + pause_items.size() - 1) % pause_items.size()
		Sfx.play("menu_move")
	elif ev.is_action_pressed("down"):
		pause_sel = (pause_sel + 1) % pause_items.size()
		Sfx.play("menu_move")
	elif ev.is_action_pressed("confirm"):
		Sfx.play("menu_select")
		var item: String = pause_items[pause_sel]
		if item == "Assist":
			assist_open = true
			assist_sel = 0
		else:
			pause_choice.emit(item)
	elif ev.is_action_pressed("back") or ev.is_action_pressed("pause"):
		pause_choice.emit("Resume")
	return true


func _panel(r: Rect2, col: Color = Color(0.06, 0.04, 0.1, 0.92)) -> void:
	draw_rect(r, col)
	draw_rect(r, Color("f2c14e"), false, 1.0)
	draw_rect(r.grow(-2), Color(1, 1, 1, 0.08), false, 1.0)


func _draw() -> void:
	# Berry counter
	if berry_show > 0.0:
		var slide := clampf(berry_show * 4.0, 0.0, 1.0)
		var x := -60.0 + 66.0 * ease(slide, 0.5)
		var pop := maxf(0.0, berry_show - 2.6) * 2.5
		draw_set_transform(Vector2(x + 6, 10), 0, Vector2(1.0 + pop, 1.0 + pop))
		draw_texture_rect_region(Art.objects(), Rect2(-8, -8, 16, 16), Art.obj_rect("berry0"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		PixelText.draw(self, Vector2(x + 14, 6), "x %d" % berry_count, Color.WHITE, Color(0, 0, 0, 0.8))
	# Timer
	if show_timer:
		var t := timer_value
		var s := "%d:%02d.%03d" % [int(t / 60.0), int(t) % 60, int(fmod(t, 1.0) * 1000)]
		PixelText.draw(self, Vector2(320 - PixelText.width(s) - 4, 4), s, Color.WHITE, Color(0, 0, 0, 0.8))
	# Room title
	if room_title != "" and room_title_t < 3.0:
		var a := clampf(minf(room_title_t * 3.0, (3.0 - room_title_t) * 2.0), 0.0, 1.0)
		PixelText.draw_centered(self, 160, 150, room_title, Color(1, 1, 1, a), Color(0, 0, 0, a * 0.8))
	# Chapter title card
	if title_text != "" and title_t < title_dur:
		var a := clampf((title_dur - title_t) * 1.5, 0.0, 1.0)
		var open := ease(clampf(title_t * 2.5, 0.0, 1.0), 0.3)
		var y := 70.0
		var bh := 34.0 * open
		draw_rect(Rect2(0, y + 11 - bh / 2.0, 320, bh), Color(0.05, 0.03, 0.08, 0.75 * a))
		var lw := 320.0 * open
		draw_rect(Rect2(160 - lw / 2.0, y + 11 - bh / 2.0, lw, 1), Color(0.95, 0.76, 0.3, a))
		draw_rect(Rect2(160 - lw / 2.0, y + 10 + bh / 2.0, lw, 1), Color(0.95, 0.76, 0.3, a))
		var s1 := ease(clampf(title_t * 2.0 - 0.3, 0.0, 1.0), 0.25)
		var s2 := ease(clampf(title_t * 2.0 - 0.5, 0.0, 1.0), 0.25)
		PixelText.draw_centered(self, 160 - (1.0 - s1) * 60.0, y, title_sub, Color(0.95, 0.76, 0.3, a * s1))
		PixelText.draw_centered(self, 160 + (1.0 - s2) * 60.0, y + 12, title_text, Color(1, 1, 1, a * s2), Color(0, 0, 0, a * s2))
		# a little jester diamond on either side
		for sx in [-1, 1]:
			var dx: float = 160 + sx * (PixelText.width(title_text) / 2.0 + 10) + (1.0 - s2) * 60.0 * sx
			var d := PackedVector2Array([Vector2(dx, y + 12), Vector2(dx + 3, y + 15), Vector2(dx, y + 18), Vector2(dx - 3, y + 15)])
			draw_colored_polygon(d, Color(0.85, 0.2, 0.35, a * s2))
	# Flash
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 320, 180), Color(1, 1, 1, flash * 0.6))
	# Wipe (diamond pattern like a curtain falling)
	if wipe > 0.0:
		_draw_wipe(wipe)
	# Pause menu
	if paused:
		draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.55))
		if assist_open:
			_draw_assist()
		else:
			var r := Rect2(100, 50, 120, 22 + pause_items.size() * 14)
			_panel(r)
			PixelText.draw_centered(self, 160, r.position.y + 6, "PAUSED", Color("f2c14e"))
			for i in pause_items.size():
				var sel := i == pause_sel
				var col := Color.WHITE if sel else Color(0.7, 0.7, 0.8)
				var txt: String = pause_items[i]
				if sel:
					txt = "> " + txt + " <"
				PixelText.draw_centered(self, 160, r.position.y + 20 + i * 14, txt, col)
			if level:
				var info := "Deaths: %d" % level.deaths_this_chapter
				PixelText.draw_centered(self, 160, r.end.y + 6, info, Color(0.8, 0.8, 0.9), Color(0, 0, 0, 0.8))
	if results:
		_draw_results()


func _draw_wipe(k: float) -> void:
	var size := 20.0
	for gy in range(0, 10):
		for gx in range(0, 17):
			var cx := gx * size + (size / 2.0 if gy % 2 == 1 else 0.0)
			var cy := gy * size
			var order := (gx + gy) / 26.0 if wipe_dir > 0.0 else 1.0 - (gx + gy) / 26.0
			var s := clampf((k * 1.6 - order * 0.6), 0.0, 1.0) * size * 0.75
			if s < 0.75:
				continue
			var pts := PackedVector2Array([Vector2(cx, cy - s), Vector2(cx + s, cy), Vector2(cx, cy + s), Vector2(cx - s, cy)])
			draw_colored_polygon(pts, Color("0d0a14"))


func _draw_assist() -> void:
	var r := Rect2(70, 46, 180, 86)
	_panel(r)
	PixelText.draw_centered(self, 160, r.position.y + 6, "ASSIST MODE", Color("f2c14e"))
	var vals := [
		"%d%%" % int(float(Game.settings.game_speed) * 100.0),
		"On" if Game.settings.infinite_stamina else "Off",
		"On" if Game.settings.invincible else "Off",
		"",
	]
	for i in assist_items.size():
		var sel := i == assist_sel
		var col := Color.WHITE if sel else Color(0.7, 0.7, 0.8)
		var y := r.position.y + 22 + i * 14
		PixelText.draw(self, Vector2(r.position.x + 12, y), ("> " if sel else "  ") + assist_items[i], col)
		if vals[i] != "":
			PixelText.draw(self, Vector2(r.end.x - 12 - PixelText.width(vals[i]), y), vals[i], Color("8ab4ff"))
	PixelText.draw_centered(self, 160, r.end.y + 6, "Play the way that feels right.", Color(0.8, 0.8, 0.9), Color(0, 0, 0, 0.8))


func _draw_results() -> void:
	var a := clampf(results_t * 2.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 320, 180), Color(0.04, 0.03, 0.07, 0.85 * a))
	var d := results_data
	var y := 30.0
	PixelText.draw_centered(self, 160, y, str(d.get("subtitle", "")), Color(0.95, 0.76, 0.3, a))
	PixelText.draw_centered(self, 160, y + 12, str(d.get("title", "")), Color(1, 1, 1, a))
	y += 40
	var rows := []
	if int(d.get("berry_total", 0)) > 0:
		rows.append(["Sunberries", "%d / %d" % [d.get("berries", 0), d.get("berry_total", 0)]])
	rows.append(["Deaths", str(d.get("deaths", 0))])
	rows.append(["Time", str(d.get("time", ""))])
	if d.get("has_bell", false):
		rows.append(["Jester Bell", "Found!" if d.get("bell", false) else "---"])
	if d.get("golden", false):
		rows.append(["Golden Sunberry", "Carried to the end!"])
	for i in rows.size():
		var reveal := clampf((results_t - 0.4 - i * 0.25) * 4.0, 0.0, 1.0)
		PixelText.draw(self, Vector2(80, y + i * 14), rows[i][0], Color(0.8, 0.8, 0.9, reveal))
		PixelText.draw(self, Vector2(240 - PixelText.width(rows[i][1]), y + i * 14), rows[i][1], Color(1, 1, 1, reveal))
	if results_t > 1.0:
		var blink := 0.5 + 0.5 * sin(time * 5.0)
		PixelText.draw_centered(self, 160, 160, "Press Jump to continue", Color(1, 1, 1, blink))
