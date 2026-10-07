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
var pause_items := ["Resume", "Retry Room", "Assist", "Options", "Restart Chapter", "Return to Map"]
var confirm_restart := false    # "Restart the chapter?" (a misclick shouldn't end a long climb)
var restart_sel := 0            # 0 = keep climbing, 1 = restart
var pause_sel := 0
var pause_k := 0.0
var row_k: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var assist_open := false
var assist_items := ["Game Speed", "Infinite Stamina", "Air Dashes", "Dash Aim", "Invincibility", "Route Ghost", "Back"]
var assist_sel := 0
var options_open := false
var option_items := ["Music Volume", "Sound Volume", "Fullscreen", "Window Size", "Smooth Motion", "Screen Shake", "Reduce Flashing", "Rumble", "Speedrun Timer", "Controls", "Back"]
var option_sel := 0
var controls_open := false      # Options > Controls: rebinding and Grab Mode mid-climb
var controls := ControlsMenu.new()
var results_ticks := 0

# Results
var results := false
var results_data: Dictionary = {}
var results_t := 0.0

var ghost_glow := {}            # Route Ghost button bit -> seconds of afterglow left
const GHOST_GLOW := 0.25         # a one-frame dash press stays visible this long
const GHOST_GOALS := {"collect": "Berries", "secret": "Secret room", "exit": "To the exit"}   # Berries mode tab
var show_timer := false
var timer_value := 0.0
var flash := 0.0


func _process(delta: float) -> void:
	time += delta
	berry_show = maxf(berry_show - delta, 0.0)
	bell_show = maxf(bell_show - delta, 0.0)
	title_t += delta
	var gi: int = level.ghost_input() if level and level.ghost_world else 0
	for b in [World.IN_UP, World.IN_DOWN, World.IN_LEFT, World.IN_RIGHT, World.IN_JUMP, World.IN_DASH, World.IN_GRAB]:
		ghost_glow[b] = GHOST_GLOW if gi & b else maxf(float(ghost_glow.get(b, 0.0)) - delta, 0.0)
	room_title_t += delta
	flash = maxf(flash - delta * 3.0, 0.0)
	wipe = move_toward(wipe, wipe_target, wipe_speed * delta)
	pause_k = move_toward(pause_k, 1.0 if paused else 0.0, delta * 7.0)
	var cur := pause_sel
	if confirm_restart:
		cur = 10 + restart_sel   # rows 10 and 11 animate the two choices
	elif assist_open:
		cur = assist_sel
	elif options_open:
		cur = option_sel
	for i in row_k.size():
		row_k[i] = move_toward(row_k[i], 1.0 if i == cur else 0.0, delta * 9.0)
	controls.process(delta)
	if results:
		results_t += delta
		# a soft tick as each stat row lands
		var n := int(clampf((results_t - 0.55) / 0.25, -1.0, 6.0)) + 1
		if n > results_ticks and n <= _result_rows().size():
			results_ticks = n
			Sfx.play("menu_move", 1.0 + n * 0.08)
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
	options_open = false
	controls_open = false
	controls.waiting_key = false
	confirm_restart = false


func close_pause() -> void:
	paused = false


func show_results(d: Dictionary) -> void:
	results = true
	results_data = d
	results_t = 0.0
	results_ticks = 0


func handle_menu_input(ev: InputEvent) -> bool:
	if results:
		if UIKit.click_action(ev):
			ev = UIKit.click_action(ev)   # a click continues too
		if results_t > 1.0 and ev.is_action_pressed("confirm"):
			results = false
			results_closed.emit()
		return true
	if not paused:
		return false
	if ev is InputEventMouse:
		ev = _mouse_menu(ev)
		if ev == null:
			return true
	if controls_open:
		if not controls.capture(ev) and controls.navigate(ev):
			controls_open = false
		return true
	if confirm_restart:
		if ev.is_action_pressed("up") or ev.is_action_pressed("down"):
			restart_sel = 1 - restart_sel
			Sfx.play("menu_move")
		elif ev.is_action_pressed("confirm"):
			Sfx.play("menu_select")
			confirm_restart = false
			if restart_sel == 1:
				pause_choice.emit("Restart Chapter")
		elif ev.is_action_pressed("back") or ev.is_action_pressed("pause"):
			confirm_restart = false
		return true
	if assist_open:
		if ev.is_action_pressed("up"):
			assist_sel = (assist_sel + assist_items.size() - 1) % assist_items.size()
			Sfx.play("menu_move")
		elif ev.is_action_pressed("down"):
			assist_sel = (assist_sel + 1) % assist_items.size()
			Sfx.play("menu_move")
		elif ev.is_action_pressed("confirm") or ev.is_action_pressed("left") or ev.is_action_pressed("right"):
			var dir := -1 if ev.is_action_pressed("left") else 1
			match assist_items[assist_sel]:
				"Game Speed":
					var speeds := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
					var i := speeds.find(float(Game.settings.game_speed))
					if i < 0: i = 5
					i = clampi(i + dir, 0, speeds.size() - 1) if not ev.is_action_pressed("confirm") else (i + 1) % speeds.size()
					Game.settings.game_speed = speeds[i]
				"Infinite Stamina":
					Game.settings.infinite_stamina = not Game.settings.infinite_stamina
				"Air Dashes":
					Game.step_air_dashes(dir, ev.is_action_pressed("confirm"))
				"Dash Aim":
					Game.settings.dash_aim = not bool(Game.settings.get("dash_aim", false))
				"Invincibility":
					Game.settings.invincible = not Game.settings.invincible
				"Route Ghost":
					Game.step_ghost_mode(dir, ev.is_action_pressed("confirm"))
				"Back":
					if ev.is_action_pressed("confirm"):
						assist_open = false
			Game.save_settings()
			pause_choice.emit("assist_changed")
			Sfx.play("menu_select")
		elif ev.is_action_pressed("back"):
			assist_open = false
		return true
	if options_open:
		if ev.is_action_pressed("up"):
			option_sel = (option_sel + option_items.size() - 1) % option_items.size()
			Sfx.play("menu_move")
		elif ev.is_action_pressed("down"):
			option_sel = (option_sel + 1) % option_items.size()
			Sfx.play("menu_move")
		elif ev.is_action_pressed("confirm") or ev.is_action_pressed("left") or ev.is_action_pressed("right"):
			var dir := -1 if ev.is_action_pressed("left") else 1
			match option_items[option_sel]:
				"Music Volume":
					Game.settings.music = clampf(snappedf(float(Game.settings.music) + 0.1 * dir, 0.1), 0.0, 1.0)
					Sfx.refresh_volume()
				"Sound Volume":
					Game.settings.sfx = clampf(snappedf(float(Game.settings.sfx) + 0.1 * dir, 0.1), 0.0, 1.0)
					Sfx.refresh_volume()
				"Fullscreen":
					Game.toggle_fullscreen()
				"Window Size":
					Game.step_window_scale(dir)
				"Smooth Motion":
					Game.step_smooth_motion(dir)
				"Screen Shake":
					Game.settings.screen_shake = not Game.settings.screen_shake
				"Reduce Flashing":
					Game.settings.reduce_flashing = not bool(Game.settings.get("reduce_flashing", false))
				"Rumble":
					Game.settings.rumble = not bool(Game.settings.get("rumble", true))
					if Game.settings.rumble:
						Game.rumble(0.6, 0.15)
				"Speedrun Timer":
					Game.settings.show_timer = not Game.settings.show_timer
					show_timer = Game.settings.show_timer
				"Controls":
					if ev.is_action_pressed("confirm"):
						controls_open = true
						controls.open()
				"Back":
					if ev.is_action_pressed("confirm"):
						options_open = false
			Game.save_settings()
			Sfx.play("menu_select")
		elif ev.is_action_pressed("back"):
			options_open = false
			Game.save_settings()
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
		elif item == "Options":
			options_open = true
			option_sel = 0
		elif item == "Restart Chapter":
			confirm_restart = true
			restart_sel = 0
		else:
			pause_choice.emit(item)
	elif ev.is_action_pressed("back") or ev.is_action_pressed("pause"):
		pause_choice.emit("Resume")
	return true


## Mouse in the pause, assist, options and Controls menus and the Restart
## Chapter box: pointing at a row selects it, a left click confirms it and a
## right click goes back (see UIKit.click_action). The wheel moves the
## selection, or steps a value row under the pointer (UIKit.wheel_menu); the
## Restart box ignores it (it isn't a click). Returns the action to handle,
## or null when the event is used up here.
func _mouse_menu(ev: InputEventMouse) -> InputEvent:
	if controls_open:
		return controls.mouse(ev)
	var a := UIKit.click_action(ev)
	var i := -1
	var wheel := UIKit.is_wheel(ev)
	if confirm_restart:
		i = UIKit.row_at(ev.position, 98, 90, 124, 12, 2)
		if i >= 0 and i != restart_sel:
			restart_sel = i
			Sfx.play("menu_move")
	elif assist_open:
		i = UIKit.row_at(ev.position, 90, 56, 140, 13, assist_items.size())
		if i >= 0 and i != assist_sel and (not wheel or UIKit.WHEEL_VALUE_ROWS.has(assist_items[i])):
			assist_sel = i
			Sfx.play("menu_move")
		if wheel:
			return UIKit.wheel_menu(ev, assist_items, i)
	elif options_open:
		i = UIKit.row_at(ev.position, 100, 22, 132, 12, option_items.size())
		if i >= 0 and i != option_sel and (not wheel or UIKit.WHEEL_VALUE_ROWS.has(option_items[i])):
			option_sel = i
			Sfx.play("menu_move")
		if wheel:
			return UIKit.wheel_menu(ev, option_items, i)
		if i >= 0 and a and a.action == "confirm" and Game.set_volume_at(option_items[i], ev.position.x, 182.0):
			Sfx.refresh_volume()
			Sfx.play("menu_select")
			return null   # a click on a volume slider sets it there
	else:
		if wheel:
			return UIKit.wheel_action(ev, "up", "down")
		i = UIKit.row_at(ev.position, 114, 44, 92, 14, pause_items.size())
		if i >= 0 and i != pause_sel:
			pause_sel = i
			Sfx.play("menu_move")
	if a and a.action == "confirm" and i < 0:
		return null   # a click outside the rows does nothing
	return a


func _panel(r: Rect2, col: Color = Color(0.06, 0.04, 0.1, 0.92)) -> void:
	draw_rect(r, col)
	draw_rect(r, Color("f2c14e"), false, 1.0)
	draw_rect(r.grow(-2), Color(1, 1, 1, 0.08), false, 1.0)


func _draw() -> void:
	# Berry counter
	if berry_show > 0.0:
		var slide := clampf(berry_show * 4.0, 0.0, 1.0)
		var x := roundf(-70.0 + 74.0 * ease(slide, 0.5))
		var pop := maxf(0.0, berry_show - 2.6) * 2.5
		var txt := "%d / %d" % [berry_count, berry_total] if berry_total > 0 else str(berry_count)
		var pw := PixelText.width(txt) + 26.0
		# dark pill with a gold underline
		draw_rect(Rect2(x - 2, 3, pw + 3, 15), Color(UIKit.INK, 0.75))
		draw_rect(Rect2(x - 1, 2, pw + 1, 1), Color(UIKit.INK, 0.75))
		draw_rect(Rect2(x - 1, 18, pw + 1, 1), Color(UIKit.INK, 0.75))
		draw_rect(Rect2(x, 17, pw - 1, 1), Color(UIKit.GOLD, 0.8))
		draw_set_transform(Vector2(x + 8, 10), 0, Vector2(1.0 + pop, 1.0 + pop))
		draw_texture_rect_region(Art.objects(), Rect2(-8, -8, 16, 16), Art.obj_rect("berry0"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var full := berry_total > 0 and berry_count >= berry_total
		PixelText.draw_outlined(self, Vector2(x + 18, 6), txt, UIKit.GOLD if full else UIKit.CREAM, UIKit.INK)
	# Timer
	if show_timer:
		var t := timer_value
		var s := "%d:%02d.%03d" % [int(t / 60.0), int(t) % 60, int(fmod(t, 1.0) * 1000)]
		PixelText.draw(self, Vector2(320 - PixelText.width(s) - 4, 4), s, Color.WHITE, Color(0, 0, 0, 0.8))
	if level and level.ghost_view.visible and level.mode == "play" and not (paused and assist_open):   # the Assist help sits there
		_draw_ghost_input()
	if Game.grab_latched and level and level.mode == "play":
		# Grab Mode: Toggle is holding grab for the player
		var pairs := [[Game.key_label("grab"), "Grab on"]]
		UIKit.hints(self, Vector2(roundf(316 - UIKit.hints_width(pairs)), 166), pairs, 0.85)
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
		draw_rect(Rect2(0, 0, 320, 180), Color(1, 1, 1, flash * 0.6 * Game.flash_scale()))
	# Wipe (diamond pattern like a curtain falling)
	if wipe > 0.0:
		_draw_wipe(wipe)
	# Pause menu
	if pause_k > 0.0:
		_draw_pause(ease(pause_k, 0.4))
	if results:
		_draw_results()


## Route Ghost buttons, bottom left: a D-pad and the Jump / Dash / Grab keys
## (named by the player's own bindings) light up while the ghost holds them.
func _draw_ghost_input() -> void:
	var tint := Color(0.7, 0.9, 1.0)
	var o := Vector2(5, 160)
	draw_rect(Rect2(o.x - 3, o.y - 3, 136, 19), Color(UIKit.INK, 0.6))
	draw_rect(Rect2(o.x - 3, o.y - 3, 136, 1), Color(tint, 0.5))
	if level.ghost_mode_shown == "berries":
		# Berries mode: a tab naming where she's headed
		var goal: String = GHOST_GOALS.get(level.ghost_goal, "")
		var gw := PixelText.width(goal) + 8.0
		draw_rect(Rect2(o.x - 3, o.y - 14, gw, 11), Color(UIKit.INK, 0.6))
		PixelText.draw_outlined(self, Vector2(o.x + 1, o.y - 12), goal, tint, Color(UIKit.INK, 0.8))
	for d in [[World.IN_UP, Vector2(5, 0)], [World.IN_LEFT, Vector2(0, 5)], [World.IN_RIGHT, Vector2(10, 5)], [World.IN_DOWN, Vector2(5, 10)]]:
		var g := _glow(int(d[0]))
		draw_rect(Rect2(o + (d[1] as Vector2), Vector2(4, 4)), Color(tint, lerpf(0.3, 1.0, g)))
	draw_rect(Rect2(o + Vector2(5, 5), Vector2(4, 4)), Color(tint, 0.15))
	var x := o.x + 19.0
	for a in [[World.IN_JUMP, "jump", "Jump"], [World.IN_DASH, "dash", "Dash"], [World.IN_GRAB, "grab", "Grab"]]:
		var g := _glow(int(a[0]))
		var k := lerpf(0.55, 1.0, g)
		x += UIKit.keycap(self, Vector2(x, o.y + 2), Game.key_label(str(a[1])), k) + 2.0
		PixelText.draw_outlined(self, Vector2(x, o.y + 3), str(a[2]), Color(UIKit.CREAM.lerp(tint, g), k), Color(UIKit.INK, 0.8 * k))
		x += PixelText.width(str(a[2])) + 6.0


## 1 while the ghost holds the button, fading to 0 over GHOST_GLOW after.
func _glow(bit: int) -> float:
	return clampf(float(ghost_glow.get(bit, 0.0)) / GHOST_GLOW, 0.0, 1.0)


func _draw_pause(e: float) -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0.02, 0.01, 0.04, 0.6 * e))
	if assist_open:
		_draw_assist(e)
		return
	if controls_open:   # replaces the options panel, as on the title screen
		controls.draw(self, time)
		var pairs := controls.hints()
		UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 166), pairs, e * 0.9)
		return
	if options_open:
		_draw_options(e)
		return
	var r := Rect2(108, 34 + (1.0 - e) * 10.0, 104, 14 + pause_items.size() * 14)
	UIKit.panel(self, r, e)
	UIKit.panel_title(self, r, "PAUSED", e)
	for i in pause_items.size():
		UIKit.menu_row(self, r.position.x + 6, r.position.y + 10 + i * 14, r.size.x - 12, pause_items[i], 0.0 if confirm_restart else row_k[i], time, e, true)
	if level:
		var info := "%s   Deaths %d" % [str(level.chapter.name), level.deaths_this_chapter]
		PixelText.draw_centered_outlined(self, 160, r.end.y + 6, info, Color(UIKit.CREAM, 0.85 * e), Color(UIKit.INK, e))
		_draw_pause_berries(r.end.y + 17, e)
	if confirm_restart:
		_draw_confirm_restart(e)
		return
	var pairs := [[Game.key_label("jump"), "Select"], [Game.key_label("dash"), "Resume"]]
	UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 166), pairs, e * 0.9)


## This chapter's berries (and its bell, found or not) under the pause menu.
func _draw_pause_berries(y: float, e: float) -> void:
	var ch: LevelDB.ChapterDef = level.chapter
	var total := ch.berry_count()
	if total == 0 and not ch.has_bell():
		return
	var txt := "%d / %d" % [Game.berries_in_chapter(level.chapter_n), total]
	var w := 14.0 + PixelText.width(txt) + (18.0 if ch.has_bell() else 0.0)
	var x := roundf(160 - w / 2.0)
	if total > 0:
		draw_texture_rect_region(Art.objects(), Rect2(x - 3, y - 4, 16, 16), Art.obj_rect("berry0"), Color(1, 1, 1, e))
		PixelText.draw_outlined(self, Vector2(x + 13, y), txt, Color(UIKit.CREAM, e), Color(UIKit.INK, e))
	if ch.has_bell():
		var got := Game.bell_in_chapter(level.chapter_n)
		draw_texture_rect_region(Art.objects(), Rect2(x + w - 13, y - 4, 16, 16), Art.obj_rect("bell0" if got else "bell_ghost"), Color(1, 1, 1, e if got else 0.6 * e))


func _draw_confirm_restart(e: float) -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.45 * e))
	var r := Rect2(90, 62, 140, 56)
	UIKit.panel(self, r, e, UIKit.CRIMSON)
	PixelText.draw_centered(self, 160, r.position.y + 7, "Restart the chapter?", Color(Color.WHITE, e))
	PixelText.draw_centered(self, 160, r.position.y + 17, "Time and deaths start over", Color(UIKit.MUTED, 0.9 * e))
	var opts := ["Keep climbing", "Restart"]
	for i in 2:
		UIKit.menu_row(self, r.position.x + 8, r.position.y + 28 + i * 12, r.size.x - 16, opts[i], row_k[10 + i], time, e, true)
	var pairs := [[Game.key_label("jump"), "Select"], [Game.key_label("dash"), "Back"]]
	UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 166), pairs, e * 0.9)


func _draw_options(e: float) -> void:
	var r := Rect2(88, 12, 144, 14 + option_items.size() * 12)
	UIKit.panel(self, r, e)
	UIKit.panel_title(self, r, "OPTIONS", e)
	for i in option_items.size():
		var y := r.position.y + 10 + i * 12
		UIKit.menu_row(self, r.position.x + 12, y, 120, option_items[i], row_k[i], time, e)
		var right := Vector2(r.end.x - 10, y)
		match option_items[i]:
			"Music Volume": UIKit.slider(self, right - Vector2(40, -1), float(Game.settings.music), e)
			"Sound Volume": UIKit.slider(self, right - Vector2(40, -1), float(Game.settings.sfx), e)
			"Fullscreen": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.fullscreen), e)
			"Window Size", "Smooth Motion":
				var v := Game.window_scale_label() if option_items[i] == "Window Size" else Game.smooth_motion_label()
				PixelText.draw_outlined(self, Vector2(right.x - PixelText.width(v), y), v, Color(UIKit.GOLD, e), Color(UIKit.INK, e))
			"Screen Shake": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.screen_shake), e)
			"Reduce Flashing": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.get("reduce_flashing", false)), e)
			"Rumble": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.get("rumble", true)), e)
			"Speedrun Timer": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.show_timer), e)
	var pairs := [[Game.move_label(), "Change"], [Game.key_label("dash"), "Back"]]
	UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 166), pairs, e * 0.9)


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


func _draw_assist(e: float = 1.0) -> void:
	var r := Rect2(78, 46, 164, 14 + assist_items.size() * 13)
	UIKit.panel(self, r, e)
	UIKit.panel_title(self, r, "ASSIST MODE", e)
	for i in assist_items.size():
		var y := r.position.y + 10 + i * 13
		UIKit.menu_row(self, r.position.x + 12, y, 140, assist_items[i], row_k[i], time, e)
		var right := Vector2(r.end.x - 10, y)
		match assist_items[i]:
			"Game Speed", "Air Dashes", "Route Ghost":
				var v := "%d%%" % int(float(Game.settings.game_speed) * 100.0) if assist_items[i] == "Game Speed" \
					else str(Game.settings.get("air_dashes", "default")).capitalize() if assist_items[i] == "Air Dashes" \
					else Game.ghost_mode().capitalize()
				PixelText.draw_outlined(self, Vector2(right.x - PixelText.width(v), y), v, Color(UIKit.GOLD, e), Color(UIKit.INK, e))
			"Infinite Stamina": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.infinite_stamina), e)
			"Dash Aim": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.get("dash_aim", false)), e)
			"Invincibility": UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.invincible), e)
	var lines := PixelText.wrap(assist_help(assist_items[assist_sel]), ASSIST_HELP_W)
	for i in lines.size():
		PixelText.draw_centered_outlined(self, 160, r.end.y + 5 + i * PixelText.LINE_H, lines[i], Color(UIKit.CREAM, 0.85 * e), Color(UIKit.INK, e))


const ASSIST_HELP_W := 300       # the Assist help text wraps to two lines this wide

## What the highlighted Assist row does, for its current value where that
## matters. Shown under the panel.
static func assist_help(item: String) -> String:
	match item:
		"Game Speed":
			return "Slows the whole game, controls included, so every jump and dash has more time."
		"Infinite Stamina":
			return "Climb and cling to walls for as long as you like without tiring."
		"Air Dashes":
			match str(Game.settings.get("air_dashes", "default")):
				"two": return "Two dashes in the air wherever a room gives one. Rooms before Mira learns to dash stay dashless."
				"infinite": return "Dash in the air as often as you like. Rooms before Mira learns to dash stay dashless."
			return "The dashes each room gives: none at first, then one, and two on the Summit."
		"Dash Aim":
			return "Pressing Dash stops time and shows an arrow. Hold a direction, then let go of Dash to dash that way."
		"Invincibility":
			return "Nothing can hurt Mira. Pits bounce her back up, and curtains turn her back from a wall."
		"Route Ghost":
			match Game.ghost_mode():
				"exit": return "A see-through Mira runs a proven way to this room's exit, using only moves the game teaches."
				"berries": return "She shows how to take the berries and bells you still lack here, then a secret room's way in, then the exit."
			return "Off. A see-through Mira can show a proven way through each room: to the exit, or to its berries."
	return "Play the way that feels right. Your progress counts the same."


func _result_rows() -> Array:
	var d := results_data
	var rows := []
	if int(d.get("berry_total", 0)) > 0:
		rows.append(["berry0", "Sunberries", "%d / %d" % [d.get("berries", 0), d.get("berry_total", 0)]])
	rows.append(["", "Deaths", str(d.get("deaths", 0))])
	rows.append(["", "Time", str(d.get("time", ""))])
	var b: Dictionary = d.get("best", {})
	if not b.is_empty():
		var prev := float(b.get("prev", 0.0))
		if not b.get("full_run", true):
			rows.append(["", "Best", "full climbs only"])   # from a checkpoint or Continue
		elif b.get("new", false):
			rows.append(["", "New Best!", "was " + Level.fmt_time(prev) if prev > 0.0 else "", UIKit.GOLD])
		else:
			rows.append(["", "Best", Level.fmt_time(prev)])
	if d.get("has_bell", false):
		rows.append(["bell0" if d.get("bell", false) else "bell_ghost", "Jester Bell", "Found!" if d.get("bell", false) else "---"])
	if d.get("golden", false):
		rows.append(["gold0", "Golden Sunberry", "Carried!"])
	return rows


func _draw_results() -> void:
	var a := clampf(results_t * 2.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 320, 180), Color(0.03, 0.02, 0.06, 0.8 * a))
	var d := results_data
	# header: ribbon + chapter name in large type
	var hk := ease(clampf(results_t * 2.5, 0.0, 1.0), 0.3)
	var name := str(d.get("title", ""))
	var sc := 2.0
	var nw := PixelText.width(name) * sc
	var hy := 22.0 + (1.0 - hk) * -20.0
	PixelText.draw_centered_outlined(self, 160, hy, str(d.get("subtitle", "")), Color(UIKit.GOLD, hk), Color(UIKit.INK, hk))
	draw_set_transform(Vector2(roundf(160 - nw / 2.0), hy + 12), 0, Vector2(sc, sc))
	PixelText.draw(self, Vector2(1, 1), name, Color(UIKit.INK, hk))
	PixelText.draw(self, Vector2.ZERO, name, Color(UIKit.CREAM, hk))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var lw := (nw + 30.0) * hk
	draw_rect(Rect2(160 - lw / 2.0, hy + 34, lw, 1), Color(UIKit.GOLD, 0.8 * hk))
	UIKit.diamond(self, Vector2(160 - lw / 2.0, hy + 34), 2.0, Color(UIKit.GOLD, hk))
	UIKit.diamond(self, Vector2(160 + lw / 2.0, hy + 34), 2.0, Color(UIKit.GOLD, hk))
	# stats panel
	var rows := _result_rows()
	var gap := 15.0 if rows.size() <= 5 else 13.0   # six rows still clear the prompt below
	var pr := Rect2(76, 70 if rows.size() <= 5 else 66, 168, 12 + rows.size() * gap)
	var pk := clampf((results_t - 0.3) * 3.0, 0.0, 1.0)
	if pk > 0.0:
		UIKit.panel(self, pr, pk)
	for i in rows.size():
		var reveal := clampf((results_t - 0.55 - i * 0.25) * 4.0, 0.0, 1.0)
		if reveal <= 0.0:
			continue
		var y := pr.position.y + 9 + i * gap
		var x := pr.position.x + 10 + (1.0 - ease(reveal, 0.3)) * 16.0
		var icon: String = rows[i][0]
		if icon != "":
			var pop := 1.0 + maxf(0.0, 1.0 - reveal * 1.5) * 0.6
			draw_set_transform(Vector2(x + 6, y + 3), 0, Vector2(pop, pop))
			draw_texture_rect_region(Art.objects(), Rect2(-8, -8, 16, 16), Art.obj_rect(icon), Color(1, 1, 1, reveal))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		else:
			UIKit.diamond(self, Vector2(x + 6, y + 3), 2.0, Color(UIKit.GOLD, reveal))
		var lc: Color = rows[i][3] if rows[i].size() > 3 else UIKit.MUTED
		PixelText.draw(self, Vector2(x + 18, y), rows[i][1], Color(lc, reveal))
		var v: String = rows[i][2]
		var vc := UIKit.GOLD if icon == "gold0" else Color.WHITE
		PixelText.draw_outlined(self, Vector2(pr.end.x - 10 - PixelText.width(v), y), v, Color(vc, reveal), Color(UIKit.INK, reveal))
	if results_t > 1.0 + rows.size() * 0.25:
		var blink := 0.65 + 0.35 * sin(time * 5.0)
		var pairs := [[Game.key_label("jump"), "Continue"]]
		UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 162), pairs, blink)
