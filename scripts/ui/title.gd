extends Node2D
## Title screen: animated logo, campfire vignette and the options menu.

var time := 0.0
var sel := 0
var items: Array = []
var row_k: Array = []
var screen := "main"     # main | options | confirm_reset
var opt_sel := 0
var opt_k: Array = []
var backdrop: Backdrop
var juggle_t := 0.0
var wipe := 1.0
var leaving := ""
var panel_k := 0.0
var embers: Array = []
var ledge_tex: Texture2D
var glow: Node2D
var logo_node: Node2D
var logo_mat: ShaderMaterial
var jingled := false
var bell_swing := 0.0
var notice := ""          # a damaged save was set aside (see Game.read_json)

const OPTIONS := ["Music Volume", "Sound Volume", "Fullscreen", "Window Size", "Smooth Motion", "Screen Shake", "Reduce Flashing", "Rumble", "Speedrun Timer", "Controls", "Erase Save", "Back"]
var controls := ControlsMenu.new()
const LOGO_Y := 25.0
const MENU_X := 40.0
const MENU_Y := 102.0
const FIRE := Vector2(268, 150)
const MIRA := Vector2(246, 150)


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
	opt_k.resize(OPTIONS.size())
	opt_k.fill(0.0)
	ledge_tex = _make_ledge()
	# warm additive glow from the campfire
	glow = Node2D.new()
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	glow.z_index = 1
	glow.draw.connect(_draw_glow)
	add_child(glow)
	# logo with a gloss sweep shader
	logo_node = Node2D.new()
	logo_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float sweep = -100.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float d = FRAGCOORD.x + FRAGCOORD.y * 0.7 - sweep;
	float band = (1.0 - step(3.0, abs(d))) * step(0.55, lum);
	c.rgb = mix(c.rgb, vec3(1.0, 1.0, 0.95), band * 0.8);
	COLOR = c;
}
"""
	logo_mat.shader = sh
	logo_node.material = logo_mat
	logo_node.z_index = 2
	logo_node.draw.connect(_draw_logo)
	add_child(logo_node)
	Sfx.play_music("title")
	Sfx.play_ambience("amb_meadow")
	notice = Game.load_notice
	Game.load_notice = ""


func _make_ledge() -> Texture2D:
	var d := RoomDef.new()
	d.id = "title_ledge"
	d.w = 16
	d.h = 5
	var rows := PackedStringArray([
		"................",
		"...#############",
		"..##############",
		"..##############",
		"..##############",
	])
	d.rows = rows
	d.cells.resize(d.w * d.h)
	for y in d.h:
		for x in d.w:
			d.cells[y * d.w + x] = RoomDef.SOLID if rows[y][x] == "#" else RoomDef.EMPTY
	var art := TerrainArt.render(d, "meadow")
	var img: Image = art.fg
	img.blend_rect(art.deco, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	return ImageTexture.create_from_image(img)


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
	row_k.resize(items.size())
	row_k.fill(0.0)


func _process(delta: float) -> void:
	time += delta
	juggle_t += delta
	backdrop.cam_pos.x = time * 12.0
	if leaving != "":
		wipe = minf(wipe + delta * 2.2, 1.0)
		if wipe >= 1.0:
			_go(leaving)
	else:
		wipe = maxf(wipe - delta * 1.6, 0.0)
	for i in row_k.size():
		row_k[i] = move_toward(row_k[i], 1.0 if (i == sel and screen == "main") else 0.0, delta * 8.0)
	for i in opt_k.size():
		opt_k[i] = move_toward(opt_k[i], 1.0 if i == opt_sel else 0.0, delta * 8.0)
	controls.process(delta)
	panel_k = move_toward(panel_k, 1.0 if screen != "main" else 0.0, delta * 6.0)
	if not jingled and time > 1.05:
		jingled = true
		bell_swing = 1.0
		Sfx.play("bell", 1.2, -6.0)
	bell_swing = maxf(bell_swing - delta * 0.6, 0.0)
	# campfire embers
	if randf() < delta * 14.0:
		embers.append({"p": FIRE + Vector2(randf_range(-3, 3), -6), "v": Vector2(randf_range(-6, 6), randf_range(-26, -14)), "life": randf_range(0.8, 1.6)})
	for e in embers:
		e.life -= delta
		e.v.x += sin(time * 3.0 + e.p.y * 0.2) * 12.0 * delta
		e.p += e.v * delta
	embers = embers.filter(func(e): return e.life > 0.0)
	var period := 5.0
	var ph := fmod(time - 1.4, period)
	logo_mat.set_shader_parameter("sweep", -40.0 + ph * 260.0 if time > 1.4 else -100.0)
	queue_redraw()
	glow.queue_redraw()
	logo_node.modulate.a = 1.0 - panel_k * 0.9
	logo_node.queue_redraw()


func _go(what: String) -> void:
	match what:
		"Continue":
			var r: Dictionary = Game.data.resume
			Game.start_chapter(int(r.chapter), str(r.room))
		"Climb":
			Game.goto_chapter_select()
		"Credits":
			Game.goto_credits()


func _input(ev: InputEvent) -> void:
	# key capture for rebinding happens before actions are dispatched
	if controls.capture(ev):
		get_viewport().set_input_as_handled()


func _unhandled_input(ev: InputEvent) -> void:
	if leaving != "" or time < 0.8:
		return
	if ev is InputEventMouse:
		ev = _mouse_menu(ev)
		if ev == null:
			return
	if controls.waiting_key:
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
		"controls":
			if controls.navigate(ev):
				screen = "options"
		"confirm_reset":
			if ev.is_action_pressed("confirm"):
				Game.reset_save()
				_build_items()
				screen = "options"
				Sfx.play("death")
			elif ev.is_action_pressed("back"):
				screen = "options"


## Mouse on the main menu, Options and Controls: pointing at a row selects it,
## a left click confirms it and a right click goes back (see
## UIKit.click_action). Erase Save's box takes a click only on its prompts.
## Returns the action to handle, or null when the event is used up here.
func _mouse_menu(ev: InputEventMouse) -> InputEvent:
	if screen == "controls":
		return controls.mouse(ev)
	if screen == "confirm_reset":
		var a := UIKit.click_action(ev)
		if a and a.action == "confirm":
			var h := UIKit.hint_at(ev.position, _erase_hints_at(), _erase_hints())
			if h < 0:
				return null   # only a click on "Erase" erases
			a.action = "confirm" if h == 0 else "back"
		return a
	var i := -1
	if screen == "main":
		i = UIKit.row_at(ev.position, MENU_X, MENU_Y, 92, 14, items.size())
		if i >= 0 and i != sel:
			sel = i
			Sfx.play("menu_move")
	else:
		i = UIKit.row_at(ev.position, 96, 16, 140, 12, OPTIONS.size())
		if i >= 0 and i != opt_sel:
			opt_sel = i
			Sfx.play("menu_move")
	var a := UIKit.click_action(ev)
	if a and a.action == "confirm" and i >= 0 and screen == "options" and Game.set_volume_at(OPTIONS[i], ev.position.x, 186.0):
		Sfx.refresh_volume()
		Sfx.play("menu_select")
		return null   # a click on a volume slider sets it there
	if a and a.action == "confirm" and i < 0:
		return null   # a click outside the rows does nothing
	return a


func _change_option(d: int, confirm: bool) -> void:
	Sfx.play("menu_select")
	match OPTIONS[opt_sel]:
		"Music Volume":
			Game.settings.music = clampf(snappedf(float(Game.settings.music) + 0.1 * d, 0.1), 0.0, 1.0)
			Sfx.refresh_volume()
		"Sound Volume":
			Game.settings.sfx = clampf(snappedf(float(Game.settings.sfx) + 0.1 * d, 0.1), 0.0, 1.0)
			Sfx.refresh_volume()
		"Fullscreen":
			Game.toggle_fullscreen()
		"Window Size":
			Game.step_window_scale(d)
		"Smooth Motion":
			Game.step_smooth_motion(d)
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
		"Controls":
			if confirm:
				screen = "controls"
				controls.open()
		"Erase Save":
			if confirm:
				screen = "confirm_reset"
		"Back":
			if confirm:
				screen = "main"
	Game.save_settings()


# ---------------------------------------------------------------- drawing

func _intro(delay: float, dur: float = 0.35) -> float:
	return clampf((time - delay) / dur, 0.0, 1.0)


func _draw_logo() -> void:
	var letters := UIKit.logo_letters()
	var total := UIKit.logo_width()
	var x := roundf(160.0 - total / 2.0)
	var cap_pos := Vector2.ZERO
	for i in letters.size():
		var L: Dictionary = letters[i]
		var k := _intro(0.25 + i * 0.09, 0.45)
		if k <= 0.0:
			x += int(L.w) + 2
			continue
		# drop in with an overshoot, then a gentle idle bob
		var drop := (1.0 - ease(k, 0.35)) * -50.0 + sin(k * PI) * 3.0 * (1.0 - k)
		var bob := roundf(sin(time * 1.6 + i * 0.8) * 1.2) if time > 1.4 else 0.0
		var pos := Vector2(x - int(L.m), LOGO_Y + drop + bob - int(L.m))
		logo_node.draw_texture(L.tex, pos.round(), Color(1, 1, 1, minf(k * 2.0, 1.0)))
		if i == 0:
			cap_pos = pos + Vector2(int(L.m) - 9, int(L.m) - 23)
		x += int(L.w) + 2
	# jester cap on the J, popping on after the letters land
	var ck := _intro(0.95, 0.3)
	if ck > 0.0:
		var s := 1.0 + sin(ck * PI) * 0.35
		var tilt := sin(time * 1.6) * 0.04 + bell_swing * sin(time * 14.0) * 0.12
		var cap := UIKit.logo_cap()
		var pivot := cap_pos + Vector2(20, 24)
		logo_node.draw_set_transform(pivot.round(), tilt, Vector2(s, s))
		logo_node.draw_texture(cap, Vector2(-20, -24))
		logo_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var sw := sin(time * 3.0) * 0.25 + bell_swing * sin(time * 16.0) * 0.8
		var tip1 := pivot + Vector2(-18, -10).rotated(tilt) * s
		var tip2 := pivot + Vector2(18, -10).rotated(tilt) * s
		UIKit.bell(logo_node, tip1 + Vector2(sin(sw) * 2.0, 3), sw)
		UIKit.bell(logo_node, tip2 + Vector2(-sin(sw) * 2.0, 3), -sw)


func _draw_glow() -> void:
	var tex := Lighting.light_texture()
	var fl := 0.85 + 0.1 * sin(time * 11.0) * sin(time * 7.3)
	glow.draw_texture_rect(tex, Rect2(FIRE - Vector2(56, 60), Vector2(112, 112)), false, Color(1.0, 0.55, 0.2, 0.32 * fl))
	glow.draw_texture_rect(tex, Rect2(FIRE - Vector2(22, 28), Vector2(44, 44)), false, Color(1.0, 0.8, 0.4, 0.3 * fl))


func _draw() -> void:
	# ledge, fire and Mira juggling
	draw_texture(ledge_tex, Vector2(212, 142))
	UIKit.campfire(self, FIRE, time)
	for e in embers:
		var a := clampf(e.life, 0.0, 1.0)
		draw_rect(Rect2((e.p as Vector2).round(), Vector2.ONE), Color(1.0, 0.75, 0.3, a))
	var frame := Art.frame_index("talk%d" % (int(juggle_t * 4.4) % 2))
	draw_set_transform(MIRA, 0, Vector2(1, 1))
	draw_texture_rect_region(Art.player_menu(), Rect2(-12, -24, 24, 24), Rect2(frame * 24, 0, 24, 24), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for i in 3:
		var t := juggle_t * 2.2 + i * TAU / 3.0
		var p := MIRA + Vector2(cos(t) * 7.0, -18.0 - absf(sin(t)) * 14.0)
		var names := ["ball_r", "ball_y", "ball_u"]
		draw_texture_rect_region(Art.objects(), Rect2((p - Vector2(8, 8)).round(), Vector2(16, 16)), Art.obj_rect(names[i]))
	# tagline
	var tk := _intro(1.15, 0.5) * (1.0 - panel_k)
	if tk > 0.0:
		var tag := "a mountain that laughs back"
		var ty := LOGO_Y + 40.0
		var tw := PixelText.width(tag)
		draw_rect(Rect2(160 - tw / 2.0 - 18, ty + 4, 12 * tk, 1), Color(UIKit.GOLD, 0.7 * tk))
		draw_rect(Rect2(160 + tw / 2.0 + 18 - 12 * tk, ty + 4, 12 * tk, 1), Color(UIKit.GOLD, 0.7 * tk))
		PixelText.draw_centered_outlined(self, 160, ty, tag, Color(UIKit.CREAM, tk), Color(UIKit.INK, 0.9 * tk))
	# main menu
	var mk := 1.0 - panel_k
	for i in items.size():
		var k := _intro(1.25 + i * 0.07, 0.3)
		if k <= 0.0:
			continue
		var x := MENU_X - (1.0 - ease(k, 0.3)) * 50.0 - panel_k * 30.0
		UIKit.menu_row(self, x, MENU_Y + i * 14, 92, items[i], row_k[i], time, k * mk)
	# options / confirm panel
	if panel_k > 0.0:
		var e := ease(panel_k, 0.3)
		var r := Rect2(84, 6 + (1.0 - e) * 12.0, 152, 14 + OPTIONS.size() * 12)
		if screen == "controls":
			e = 0.0   # the controls panel replaces the options panel
		UIKit.panel(self, r, e)
		UIKit.panel_title(self, r, "OPTIONS", e)
		for i in OPTIONS.size():
			var y := r.position.y + 10 + i * 12
			UIKit.menu_row(self, r.position.x + 12, y, 128, OPTIONS[i], opt_k[i], time, e)
			_draw_opt_value(OPTIONS[i], Vector2(r.end.x - 10, y), e)
		if screen == "controls":
			controls.draw(self, time)
		if screen == "confirm_reset":
			draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.5))
			var cr := Rect2(60, 76, 200, 40)
			UIKit.panel(self, cr, 1.0, UIKit.CRIMSON)
			PixelText.draw_centered(self, 160, cr.position.y + 8, "Erase ALL progress?", Color.WHITE)
			UIKit.hints(self, _erase_hints_at(), _erase_hints())
	# control hints
	var hk := _intro(1.6, 0.5)
	if hk > 0.0:
		var pairs := [[Game.move_label(), "Move"], [Game.key_label("jump"), "Jump"], [Game.key_label("dash"), "Dash"], [Game.key_label("grab"), "Grab"]] if screen == "main" else [[Game.move_label(), "Change"], [Game.key_label("jump"), "Select"], [Game.key_label("dash"), "Back"]]
		if screen == "controls":
			pairs = controls.hints()
		UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 166), pairs, hk * 0.9)
	if notice != "" and time < 9.0:
		var na := clampf(minf(time - 1.0, 9.0 - time), 0.0, 1.0)
		var nw := PixelText.width(notice) + 12.0
		var nr := Rect2(roundf(160 - nw / 2.0), 81, nw, 13)   # between the tagline and the menu
		draw_rect(nr, Color(UIKit.INK, 0.85 * na))
		draw_rect(Rect2(nr.position.x, nr.end.y - 1, nr.size.x, 1), Color(UIKit.CRIMSON, na))
		PixelText.draw_centered(self, 160, nr.position.y + 3, notice, Color(UIKit.CREAM, na))
	UIKit.wipe(self, wipe, -1.0 if leaving == "" else 1.0)


## Erase Save's prompts, centred in its box (see _draw).
func _erase_hints() -> Array:
	return [[Game.key_label("jump"), "Erase"], [Game.key_label("dash"), "Keep"]]


func _erase_hints_at() -> Vector2:
	return Vector2(roundf(160 - UIKit.hints_width(_erase_hints()) / 2.0), 99)


func _draw_opt_value(name: String, right: Vector2, a: float) -> void:
	match name:
		"Music Volume":
			UIKit.slider(self, right - Vector2(40, -1), float(Game.settings.music), a)
		"Sound Volume":
			UIKit.slider(self, right - Vector2(40, -1), float(Game.settings.sfx), a)
		"Fullscreen":
			UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.fullscreen), a)
		"Window Size", "Smooth Motion":
			var v := Game.window_scale_label() if name == "Window Size" else Game.smooth_motion_label()
			PixelText.draw_outlined(self, Vector2(right.x - PixelText.width(v), right.y), v, Color(UIKit.GOLD, a), Color(UIKit.INK, a))
		"Screen Shake":
			UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.screen_shake), a)
		"Reduce Flashing":
			UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.get("reduce_flashing", false)), a)
		"Rumble":
			UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.get("rumble", true)), a)
		"Speedrun Timer":
			UIKit.toggle(self, right - Vector2(15, -1), bool(Game.settings.show_timer), a)
