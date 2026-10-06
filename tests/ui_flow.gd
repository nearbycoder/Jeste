extends Node
## Drives the real menus with simulated input and checks each screen is
## reached: title -> options -> chapter select -> level -> pause / options /
## assist -> map -> title, plus resume prompt, results and credits.
## godot --headless --path . res://tests/ui_flow.tscn
## Prints "UI FLOW PASS" or "UI FLOW FAIL: <step>" and exits 0 / 1.

var steps: Array = []
var idx := 0
var wait := 0
var failed := ""
var music_before := 0.0
var skip_id := ""
var speed_from := 0
var frames_btn := 0
var btn_last := {}
var btn_seen := 0


func _ready() -> void:
	# keep this driver alive across scene changes: hand "current scene" to a dummy
	var dummy := Node.new()
	get_tree().root.add_child.call_deferred(dummy)
	(func(): get_tree().current_scene = dummy).call_deferred()
	var game: Node = get_node("/root/Game")
	game.headless_test = true
	game.data = game.default_save()
	game.data.unlocked = 8
	game.settings = game.default_settings()   # whatever the machine's settings file says
	game.setup_input()
	var t := Timer.new()
	t.wait_time = 240.0
	t.one_shot = true
	t.timeout.connect(func(): _fail("watchdog timeout"))
	add_child(t)
	t.start()
	# [kind, arg, frames to wait afterwards]
	steps = [
		["scene", "res://scenes/main.tscn", 90],
		["expect", "Title", 0],
		["check", "helpers", 0],
		["check", "ghost_parts", 0],
		["stick", "down", 6],                                     # one stick push = one row
		["check", "title_sel_1", 0],
		["stick", "up", 6],
		["check", "title_sel_0", 0],
		["stick_hold", "down", 4],                                # gameplay still sees a held stick
		["check", "held_down", 0],
		["stick_hold", "", 4],
		["press", "up", 6],
		["check", "title_sel_0", 0],
		["press", "down", 6], ["press", "confirm", 20],          # Options
		["check", "options", 0],
		["hold", "dpad_down", 40], ["release", "dpad_down", 4],  # holding repeats
		["check", "repeated", 0], ["set_opt0", "", 2],
		["hold", "key_down", 40], ["release", "key_down", 4],
		["check", "repeated", 0], ["set_opt0", "", 2],
		["hold", "stick_down", 40], ["release", "stick_down", 4],
		["check", "repeated", 0], ["set_opt0", "", 2],
		["hold", "key_down", 2], ["release", "key_down", 30],    # a tap is one step, no repeats after release
		["check", "one_step", 0], ["set_opt0", "", 2],
		["mark_music", "", 0],
		["stick", "right", 6],                                    # one stick push = one slider step
		["check", "music_one_step", 0],
		["stick", "left", 6],
		["press", "right", 4], ["press", "down", 4], ["press", "left", 4],
		["press", "down", 4], ["press", "down", 4],              # Window Size
		["check", "window_auto", 0],
		["press", "right", 4], ["check", "window_2x", 0],
		["press", "left", 4], ["check", "window_auto", 0],
		["press", "down", 4], ["check", "smooth_auto", 0],       # Smooth Motion: Auto -> On -> Off -> Auto
		["press", "right", 4], ["check", "smooth_on", 0],
		["press", "right", 4], ["check", "smooth_off", 0],
		["press", "right", 4], ["check", "smooth_auto", 0],
		["press", "down", 4], ["press", "confirm", 4],           # toggles Screen Shake
		["press", "down", 4], ["press", "confirm", 4],           # Reduce Flashing
		["check", "reduced_flashing", 0],
		["press", "confirm", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Controls
		["check", "controls", 0],
		["press", "confirm", 6],                                  # rebind Jump
		["key", "N", 6],
		["check", "jump_is_n", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "jump_default", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 6],   # rebind Jump on the pad
		["padbtn", "DPAD_UP", 6], ["check", "still_waiting", 0],  # D-pad can't be bound
		["padbtn", "X", 6],
		["check", "pad_jump_x", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "pad_default", 0],
		["press", "back", 10],
		["press", "back", 20],
		["check", "main", 0],
		["press", "up", 6],                                      # Climb
		["press", "confirm", 90],
		["expect", "ChapterSelect", 0],
		["press", "left", 10], ["press", "right", 10],
		["press", "left", 10], ["press", "left", 10], ["press", "left", 10],
		["press", "left", 10], ["press", "left", 10], ["press", "left", 10], ["press", "left", 10],
		["press", "confirm", 120],                               # Prologue
		["expect", "Level", 0],
		["wait_dialogue", "", 20],
		["hold", "pause_key", 10], ["check", "skip_not_yet", 0],  # holding Esc skips the scene
		["hold_wait", "", 40],
		["release", "pause_key", 10],
		["check", "skipped", 0],
		["skip_dialogue", "", 60],
		["press", "pause", 20],
		["check", "paused", 0],
		["stick", "down", 4],
		["check", "pause_sel_1", 0],
		["stick", "up", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["check", "assist", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],   # Route Ghost on
		["check", "ghost_on", 0],
		["press", "up", 4], ["press", "up", 4],
		["press", "confirm", 4], ["press", "confirm", 4], ["press", "back", 10],
		["press", "down", 4], ["press", "confirm", 10],          # Options
		["check", "options_open", 0],
		["press", "right", 4], ["press", "left", 4], ["press", "back", 10],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 20],   # Resume
		["check", "unpaused", 0],
		["check", "ghost_running", 0],
		["ghost_buttons", "", 0],                                 # the HUD strip follows the ghost's inputs
		["speed", "0.5", 40], ["check", "half_speed", 0],        # Game Speed 50% = half the simulation steps
		["speed", "1.0", 40], ["check", "full_speed", 0],
		["press", "pause", 20], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],   # Route Ghost off
		["check", "ghost_off", 0],
		["press", "back", 10], ["press", "back", 20],
		["check", "unpaused", 0],
		["press", "pause", 20],
		["press", "up", 4], ["press", "confirm", 40],           # Retry Room (wraps to last = Return to Map? no: up from Resume = Return to Map)
		["expect", "ChapterSelect", 0],
		["seed_resume", "", 0],
		["press", "back", 60],
		["expect", "Title", 0],
		["check", "has_continue", 0],
		["press", "confirm", 120],                               # Continue
		["expect", "Level", 0],
		["check", "resumed", 0],
		["resume_end", "", 10],                                  # finishing a resumed run keeps Best
		["scene", "res://scenes/level.tscn", 60],
		["results", "", 120],
		["press", "confirm", 90],
		["expect", "ChapterSelect", 0],
		["scene", "res://scenes/credits.tscn", 240],
		["expect", "Credits", 0],
		["done", "", 0],
	]


func _fail(msg: String) -> void:
	if failed == "":
		failed = msg
		print("UI FLOW FAIL: ", msg)
		get_tree().quit(1)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _pad_buttons(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	return out


func _scene() -> Node:
	return get_tree().current_scene


func _process(_d: float) -> void:
	if failed != "":
		return
	if wait > 0:
		wait -= 1
		return
	if idx >= steps.size():
		return
	var s: Array = steps[idx]
	idx += 1
	wait = int(s[2])
	var cur := _scene()
	match s[0]:
		"scene":
			var game: Node = get_node("/root/Game")
			game.pending_chapter = 0
			game.pending_room = ""
			get_tree().change_scene_to_file(s[1])
		"expect":
			if cur == null or cur.name != s[1]:
				_fail("step %d: expected scene %s, got %s" % [idx, s[1], cur.name if cur else "none"])
		"press":
			_press(s[1])
		"stick":
			# a realistic push: the axis ramps through the deadzone, wobbles at
			# the rim, then springs back to centre
			var axis := JOY_AXIS_LEFT_Y if s[1] in ["up", "down"] else JOY_AXIS_LEFT_X
			var sgn := -1.0 if s[1] in ["up", "left"] else 1.0
			for v in [0.2, 0.35, 0.45, 0.6, 0.75, 0.9, 1.0, 0.95, 1.0, 0.6, 0.2, 0.0]:
				var ev := InputEventJoypadMotion.new()
				ev.device = 0
				ev.axis = axis
				ev.axis_value = v * sgn
				Input.parse_input_event(ev)
		"stick_hold":
			for v in ([0.3, 0.6, 0.9] if s[1] == "down" else [0.4, 0.1, 0.0]):
				var ev := InputEventJoypadMotion.new()
				ev.device = 0
				ev.axis = JOY_AXIS_LEFT_Y
				ev.axis_value = v
				Input.parse_input_event(ev)
		"hold", "release":
			var down: bool = s[0] == "hold"
			var ev: InputEvent
			match s[1]:
				"dpad_down":
					ev = InputEventJoypadButton.new()
					ev.button_index = JOY_BUTTON_DPAD_DOWN
					ev.pressed = down
				"pause_key":
					ev = InputEventKey.new()
					ev.physical_keycode = KEY_ESCAPE
					ev.keycode = KEY_ESCAPE
					ev.pressed = down
				"key_down":
					ev = InputEventKey.new()
					ev.physical_keycode = KEY_DOWN
					ev.keycode = KEY_DOWN
					ev.pressed = down
				"stick_down":
					ev = InputEventJoypadMotion.new()
					ev.axis = JOY_AXIS_LEFT_Y
					ev.axis_value = 1.0 if down else 0.0
			Input.parse_input_event(ev)
		"padbtn":
			var ev := InputEventJoypadButton.new()
			ev.button_index = JOY_BUTTON_X if s[1] == "X" else JOY_BUTTON_DPAD_UP
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate()
			up.pressed = false
			Input.parse_input_event.call_deferred(up)
		"wait_dialogue":
			if not cur.dialogue.active:
				idx -= 1
				wait = 2
		"hold_wait":
			pass
		"ghost_buttons":
			# every frame for 150 frames: each button the ghost holds is fully lit,
			# each one she hasn't held for a while is dark
			cur.hud._process(0.0)    # this driver runs before the HUD in a frame
			var gi: int = cur.ghost_input()
			for b in [World.IN_UP, World.IN_DOWN, World.IN_LEFT, World.IN_RIGHT, World.IN_JUMP, World.IN_DASH, World.IN_GRAB]:
				var g: float = cur.hud._glow(b)
				if ((gi & b) and g < 1.0) or (not (gi & b) and b in btn_last and frames_btn - int(btn_last[b]) > 30 and g > 0.0):
					_fail("step %d: ghost button %d glow %.2f, held %s" % [idx, b, g, gi & b != 0])
				if gi & b:
					btn_last[b] = frames_btn
					btn_seen |= b
			frames_btn += 1
			if frames_btn < 150:
				idx -= 1
			elif btn_seen == 0:
				_fail("step %d: the ghost pressed nothing in 150 frames" % idx)
		"speed":
			get_node("/root/Game").settings.game_speed = float(s[1])
			Engine.time_scale = float(s[1])
			speed_from = cur.world.frame
		"set_opt0":
			cur.opt_sel = 0
		"mark_music":
			music_before = float(get_node("/root/Game").settings.music)
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(s[1])
			ev.keycode = ev.physical_keycode
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate()
			up.pressed = false
			Input.parse_input_event.call_deferred(up)
		"check":
			var ok := true
			match s[1]:
				"options": ok = cur.screen == "options"
				"title_sel_1": ok = cur.sel == 1
				"reduced_flashing": ok = bool(get_node("/root/Game").settings.reduce_flashing) and is_equal_approx(get_node("/root/Game").flash_scale(), 0.2)
				"window_auto": ok = cur.OPTIONS[cur.opt_sel] == "Window Size" and int(get_node("/root/Game").settings.window_scale) == 0
				"smooth_auto": ok = cur.OPTIONS[cur.opt_sel] == "Smooth Motion" and str(get_node("/root/Game").settings.smooth_motion) == "auto" \
					and get_node("/root/Game").smooth_motion_label().begins_with("Auto")
				"smooth_on": ok = get_node("/root/Game").smooth_motion() and get_node("/root/Game").smooth_motion_label() == "On" \
					and is_zero_approx(Engine.physics_jitter_fix)
				"smooth_off": ok = not get_node("/root/Game").smooth_motion() and get_node("/root/Game").smooth_motion_label() == "Off"
				"window_2x": ok = int(get_node("/root/Game").settings.window_scale) == 2 and get_node("/root/Game").window_scale_label() == "2x"
				"title_sel_0": ok = cur.sel == 0
				"repeated": ok = cur.opt_sel >= 4 and cur.opt_sel <= 6
				"one_step": ok = cur.opt_sel == 1
				"still_waiting": ok = cur.waiting_key and cur.CONTROLS[cur.ctl_sel] == "jump"
				"pad_jump_x": ok = not cur.waiting_key and _pad_buttons("jump") == [JOY_BUTTON_X] and _pad_buttons("dash").has(JOY_BUTTON_A) \
					and not _pad_buttons("dash").has(JOY_BUTTON_X) and get_node("/root/Game").pad_label("jump") == "X"
				"pad_default": ok = _pad_buttons("jump") == [JOY_BUTTON_A, JOY_BUTTON_Y] and _pad_buttons("dash") == [JOY_BUTTON_X, JOY_BUTTON_B]
				"ghost_on": ok = bool(get_node("/root/Game").settings.route_ghost) and cur.ghost_world != null
				"ghost_running": ok = cur.ghost_world != null and cur.ghost_view.visible and cur.ghost_i >= 5 and cur.ghost_world != cur.world
				"ghost_off": ok = not bool(get_node("/root/Game").settings.route_ghost) and cur.ghost_world == null and not cur.ghost_grin.visible \
					and cur.ghost_input() == 0
				"ghost_parts": ok = _ghost_parts_ok()
				"skip_not_yet":
					ok = cur.dialogue.active and cur.mode == "dialogue"
					skip_id = cur.dialogue.script_id
				"skipped": ok = not cur.dialogue.active and cur.mode == "play" and skip_id != "" and get_node("/root/Game").has_seen(skip_id) and not cur.paused
				"held_down": ok = Input.is_action_pressed("down") and cur.sel == 1
				"half_speed": ok = absi(cur.world.frame - speed_from - 20) <= 1 and cur.mode == "play"
				"full_speed": ok = absi(cur.world.frame - speed_from - 40) <= 1 and cur.mode == "play"
				"pause_sel_1": ok = cur.hud.pause_sel == 1
				"music_one_step": ok = is_equal_approx(float(get_node("/root/Game").settings.music), minf(music_before + 0.1, 1.0))
				"helpers":
					var g: Node = get_node("/root/Game")
					ok = g.pad_family("Xbox Series Controller") == "xbox" and g.pad_family("PS5 Controller") == "playstation" \
						and g.pad_family("Sony DualSense") == "playstation" and g.pad_family("Nintendo Switch Pro Controller") == "nintendo" \
						and g.pad_family("") == "xbox" and g.pad_button_name(JOY_BUTTON_A, "nintendo") == "B" \
						and g.pad_button_name(JOY_BUTTON_X, "playstation") == "Square" and g.pad_label("grab") == "RB" \
						and g.fit_scales(Vector2i(3840, 2160)) == [11, 9] and g.fit_scales(Vector2i(1920, 1080)) == [5, 4] \
						and g.fit_scales(Vector2i(1366, 768)) == [4, 3] and g.fit_scales(Vector2i(2560, 1440)) == [7, 6] \
						and g.fit_scales(Vector2i(800, 600)) == [2, 2] and g.fit_scales(Vector2i(500, 300)) == [1, 1] \
						and g.smooth_wanted("auto", 144.0, 1.0) and g.smooth_wanted("auto", 165.0, 1.0) and g.smooth_wanted("auto", 75.0, 1.0) \
						and not g.smooth_wanted("auto", 60.0, 1.0) and not g.smooth_wanted("auto", 119.98, 1.0) and not g.smooth_wanted("auto", 59.94, 1.0) \
						and not g.smooth_wanted("auto", 240.0, 1.0) and not g.smooth_wanted("auto", -1.0, 1.0) and g.smooth_wanted("auto", 60.0, 0.5) \
						and g.smooth_wanted("on", 60.0, 1.0) and not g.smooth_wanted("off", 144.0, 0.5)
				"controls": ok = cur.screen == "controls"
				"jump_is_n": ok = get_node("/root/Game").key_label("jump") == "N"
				"jump_default": ok = get_node("/root/Game").key_label("jump") == "C"
				"main": ok = cur.screen == "main"
				"paused": ok = cur.paused and cur.hud.paused
				"assist": ok = cur.hud.assist_open
				"options_open": ok = cur.hud.options_open
				"unpaused": ok = not cur.paused
				"resumed": ok = cur.chapter_n == 1 and cur.room_id == "1-02" and cur.chapter_time >= 100.0 and cur.deaths_this_chapter == 7 and not cur.full_run
				"has_continue": ok = cur.items.size() > 0 and cur.items[0] == "Continue" and cur.sel == 0
			if not ok:
				_fail("step %d: check %s failed%s" % [idx, s[1], (" (opt_sel %d)" % cur.opt_sel) if "opt_sel" in cur else ""])
		"skip_dialogue":
			for i in 40:
				if cur.mode == "dialogue":
					var ev := InputEventAction.new()
					ev.action = "confirm"
					ev.pressed = true
					cur.dialogue.handle_input(ev)
		"results":
			cur._show_results()
		"resume_end":
			var cd: Dictionary = get_node("/root/Game").chapter_data(1)
			cd.best_time = 300.0
			cur._on_end()
			if not is_equal_approx(float(cd.best_time), 300.0):
				_fail("step %d: resumed run overwrote Best with %.2f" % [idx, float(cd.best_time)])
		"seed_resume":
			get_node("/root/Game").data.resume = {"chapter": 1, "room": "1-02", "time": 100.0, "deaths": 7}
		"done":
			print("UI FLOW PASS")
			get_tree().quit(0)


## Route Ghost parts: once the player has broken 1-03's boards, the ghost's
## intact ones (and only boards) are the cells drawn for her; in 4-02 her
## gondola moves away from the player's idle one.
func _ghost_parts_ok() -> bool:
	var ch := LevelDB.get_chapter(1)
	var def := ch.room("1-03")
	var pw := World.new()
	pw.load_room(def, 0, ch.dashes)
	var gw := World.new()
	gw.load_room(def, 0, ch.dashes)
	if not RoomView.ghost_only_cells(pw, gw).is_empty():
		return false
	var seen := 0
	for inp in Solver.decode(str(Level._hint("1-03", 0, "1").inputs)):
		pw.step(inp)
		for i in RoomView.ghost_only_cells(pw, gw):
			if def.cells[i] != RoomDef.CRUMBLE:
				return false
			seen += 1
		if pw.exited or pw.dead:
			break
	var ch4 := LevelDB.get_chapter(4)
	var def4 := ch4.room("4-02")
	var p4 := World.new()
	p4.load_room(def4, 0, ch4.dashes)
	var g4 := World.new()
	g4.load_room(def4, 0, ch4.dashes)
	var apart := 0
	for inp in Solver.decode(str(Level._hint("4-02", 0, "4").inputs)):
		g4.step(inp)
		p4.step(0)
		if g4.zip_view_pos(0) != p4.zip_view_pos(0):
			apart += 1
	return seen > 0 and apart > 0 and pw.exited and g4.exited
