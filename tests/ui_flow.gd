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
var frame := 0
var wait_frames := 0
var input_log: Array = []      # the last inputs that reached the scene, printed on a failure


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
		["check", "layout_names", 0],
		["check", "ghost_parts", 0],
		["check", "ghost_goal", 0],
		["check", "air_dash_sim", 0],
		["stick", "down", 6],                                     # one stick push = one row
		["check", "title_sel_1", 0],
		["stick", "up", 6],
		["check", "title_sel_0", 0],
		["stick_hold", "down", 4],                                # gameplay still sees a held stick
		["check", "held_down", 0],
		["stick_hold", "", 4],
		["press", "up", 6],
		["check", "title_sel_0", 0],
		["key", "Down", 2], ["check", "cursor_hidden", 0],      # the cursor hides on a key...
		["mouse", "", 2], ["check", "cursor_shown", 0],          # ...shows when the mouse moves...
		["wait_n", "100", 0], ["check", "cursor_shown", 0],
		["wait_n", "30", 0], ["check", "cursor_hidden", 0],     # ...and hides again after 2 s still
		["key", "Up", 6], ["check", "title_sel_0", 0],
		["mouse_at", "60,116", 2], ["check", "title_sel_1", 0],  # pointing at a row selects it
		["click", "200,40", 6], ["check", "title_sel_1", 0], ["check", "main", 0],   # a click off the rows does nothing
		["click", "60,116", 20], ["check", "options", 0],        # a click confirms (Options)
		["click", "183,19", 4], ["check", "volume_music_0", 0],  # a click on a volume slider sets it there
		["click", "203,19", 4], ["check", "volume_music_5", 0],
		["click", "183,31", 4], ["check", "volume_sfx_0", 0],
		["click", "215,31", 4], ["check", "volume_sfx_8", 0],
		["click", "211,19", 4], ["check", "volume_music_7", 0],
		["click", "120,19", 4], ["check", "volume_music_8", 0],  # a click on the label still steps it
		["click", "211,19", 4], ["check", "volume_music_7", 0],
		["mark_save", "", 0],
		["click", "150,139", 10], ["check", "erase_asks", 0],    # Erase Save asks...
		["click", "160,84", 6], ["check", "erase_asks", 0],      # ...a click off its prompts does nothing...
		["click_hint", "1", 6], ["check", "save_kept", 0],       # ...Keep keeps it
		["click", "150,139", 10], ["check", "erase_asks", 0],
		["rclick", "160,84", 6], ["check", "save_kept", 0],      # a right click keeps it too
		["click", "150,139", 10], ["click_hint", "0", 6], ["check", "save_erased", 0],   # Erase erases
		["unlock", "8", 0],
		["mouse_at", "150,40", 2], ["check", "opt_sel_2", 0],
		["rclick", "150,40", 10], ["check", "main", 0],          # a right click goes back
		["mouse_at", "60,102", 2], ["check", "title_sel_0", 0],
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
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "jump_default", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 6],   # rebind Jump on the pad
		["padbtn", "DPAD_UP", 6], ["check", "still_waiting", 0],  # D-pad can't be bound
		["padbtn", "X", 6],
		["check", "pad_jump_x", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "pad_default", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["check", "on_grab_mode", 0],    # Grab Mode
		["press", "confirm", 4], ["check", "grab_toggle", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],          # Reset Defaults keeps it
		["check", "grab_mode_kept", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "right", 4], ["check", "grab_hold", 0],
		["mouse_at", "160,39", 2], ["check", "ctl_sel_1", 0],    # the mouse in Controls
		["click", "160,39", 4], ["check", "ctl_waiting", 0],     # a click starts a rebind...
		["click", "160,39", 4], ["check", "ctl_waiting", 0],     # ...a mouse button can't be bound...
		["rclick", "160,39", 4], ["check", "ctl_cancelled", 0],  # ...a right click cancels it
		["click", "160,63", 4], ["check", "grab_toggle", 0],     # Grab Mode
		["click", "160,63", 4], ["check", "grab_hold", 0],
		["click", "160,5", 4], ["check", "ctl_cancelled", 0],   # a click off the rows does nothing
		["rclick", "160,63", 10], ["check", "options", 0],       # a right click closes the panel
		["click", "150,127", 10], ["check", "controls", 0],      # and a click on Controls opens it again
		["press", "back", 10],
		["press", "back", 20],
		["check", "main", 0],
		["press", "up", 6],                                      # Climb
		["press", "confirm", 90],
		["expect", "ChapterSelect", 0],
		["press", "left", 10], ["press", "right", 10],
		["press", "left", 10], ["press", "left", 10], ["press", "left", 10],
		["press", "left", 10], ["press", "left", 10], ["press", "left", 10], ["press", "left", 10],
		["press", "confirm", 120],                               # Chapter 1
		["expect", "Level", 0],
		["wait_dialogue", "", 20],
		["mark_line", "", 0], ["click", "160,90", 4], ["check", "line_advanced", 0],   # a click reads the next line
		["hold", "pause_key", 10], ["check", "skip_not_yet", 0],  # holding Esc skips the scene
		["hold_wait", "", 40],
		["release", "pause_key", 10],
		["check", "skipped", 0],
		["skip_dialogue", "", 60],
		["pad_lost", "", 6], ["check", "pad_paused", 0],         # an unplugged pad pauses the game
		["press", "pause", 10], ["check", "unpaused", 0],
		["pad_found", "", 6], ["check", "unpaused", 0],          # plugging one in doesn't
		["die", "", 2], ["pad_lost", "", 2], ["check", "pause_waits", 0],   # mid-death: pauses once play resumes
		["wait_play", "", 4], ["check", "pad_paused", 0],
		["press", "pause", 10], ["check", "unpaused", 0],
		["press", "pause", 20],
		["check", "paused", 0],
		["stick", "down", 4],
		["check", "pause_sel_1", 0],
		["stick", "up", 4],
		["mouse_at", "160,74", 2], ["check", "pause_sel_2", 0],  # the mouse in the pause menu
		["click", "160,74", 10], ["check", "assist", 0],
		["mouse_at", "160,110", 2], ["check", "assist_sel_4", 0],
		["rclick", "160,110", 10], ["check", "assist_closed", 0],
		["mouse_at", "160,46", 2], ["check", "pause_sel_0", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["check", "assist", 0],
		["press", "down", 4], ["press", "down", 4], ["check", "on_air_dashes", 0],
		["press", "right", 4], ["check", "air_two", 0],          # Air Dashes: Two
		["press", "right", 4], ["check", "air_infinite", 0],
		["press", "right", 4], ["check", "air_infinite", 0],     # Right stops at the end...
		["press", "confirm", 4], ["check", "air_default", 0],    # ...Confirm wraps around
		["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],   # Route Ghost on
		["check", "ghost_on", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "confirm", 4], ["press", "confirm", 4], ["press", "back", 10],
		["press", "down", 4], ["press", "confirm", 10],          # Options
		["check", "options_open", 0],
		["press", "right", 4], ["press", "left", 4],
		["press", "up", 4], ["press", "up", 4], ["check", "on_pause_controls", 0],   # Options > Controls, mid-climb
		["press", "confirm", 6], ["check", "pause_controls", 0],
		["press", "confirm", 6], ["key", "M", 6], ["check", "pause_jump_m", 0],     # rebind Jump to M
		["press", "confirm", 6], ["key", "Escape", 6], ["check", "pause_jump_m", 0], # Esc cancels, still paused
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],   # Grab Mode
		["check", "grab_toggle_paused", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "confirm", 6], ["check", "pause_reset", 0],                       # Reset Defaults
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "confirm", 4], ["check", "grab_hold_paused", 0],
		["mouse_at", "160,39", 2], ["check", "pause_ctl_sel_1", 0],
		["rclick", "160,39", 6], ["check", "pause_controls_closed", 0],   # a right click closes Controls
		["click", "180,37", 4], ["check", "volume_sfx_0", 0],    # the pause menu's sliders take a click too
		["click", "211,37", 4], ["check", "volume_sfx_8", 0],
		["press", "back", 10],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 20],   # Resume
		["check", "unpaused", 0],
		["check", "ghost_running", 0],
		["ghost_buttons", "", 0],                                 # the HUD strip follows the ghost's inputs
		["speed", "0.5", 40], ["check", "half_speed", 0],        # Game Speed 50% = half the simulation steps
		["speed", "1.0", 40], ["check", "full_speed", 0],
		["press", "pause", 20], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "right", 4], ["check", "ghost_berries", 0],    # Route Ghost: Berries
		["press", "right", 4], ["check", "ghost_berries", 0],    # Right stops at the end...
		["press", "left", 4], ["check", "ghost_on", 0],          # ...Left goes back to Exit
		["press", "right", 4], ["press", "confirm", 4],          # Confirm wraps Berries -> Off
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
		["best_rows", "", 0],
		["results", "", 120],
		["click", "160,90", 90],                                 # a click continues from the results
		["expect", "ChapterSelect", 0],
		["check", "backfill", 0],                                # checkpoint select
		["seed_checkpoints", "", 0],
		["scene", "res://scenes/chapter_select.tscn", 60],
		["rclick", "160,10", 60], ["expect", "Title", 0],         # the mouse in chapter select: right click goes back
		["scene", "res://scenes/chapter_select.tscn", 60],
		["unlock", "5", 0], ["click_marker", "7", 6], ["check", "cs_sel_8", 0],   # a locked chapter can't be clicked
		["unlock", "8", 0], ["click_marker", "3", 6], ["check", "cs_sel_3", 0],
		["click", "6,80", 6], ["check", "cs_sel_2", 0],          # the side arrows
		["click", "314,80", 6], ["check", "cs_sel_3", 0],
		["click", "160,10", 6], ["check", "cs_sel_3", 0],        # a click on nothing does nothing
		["click_marker", "1", 6], ["check", "cs_sel_1", 0],
		["click", "240,60", 10], ["check", "picker_open", 0],    # a click on the card chooses it
		["click_pip", "2", 6], ["check", "cp_sel_2", 0],         # a reached room's pip
		["click_pip", "5", 6], ["check", "cp_sel_2", 0],         # an unreached one does nothing
		["click", "177,81", 6], ["check", "cp_sel_3", 0],        # the postcard's arrows
		["click", "19,81", 6], ["check", "cp_sel_2", 0],
		["rclick", "160,10", 6], ["check", "picker_closed", 0],
		["press", "confirm", 10], ["check", "picker_open", 0],
		["press", "right", 6], ["press", "right", 6], ["press", "right", 6], ["press", "right", 6],
		["check", "picker_last", 0],
		["press", "back", 6], ["check", "picker_closed", 0],
		["press", "confirm", 10], ["press", "right", 6], ["press", "right", 6],
		["click", "240,60", 120],                                # a click on the card starts there
		["expect", "Level", 0],
		["check", "from_checkpoint", 0],
		["press", "pause", 20], ["press", "up", 4], ["press", "up", 4],   # Restart Chapter
		["press", "confirm", 6], ["check", "restart_asks", 0],
		["mouse_at", "160,105", 2], ["check", "restart_yes", 0],        # the mouse picks a choice...
		["click", "160,75", 4], ["check", "restart_yes", 0],            # ...a click off them does nothing...
		["mouse_at", "160,93", 2], ["check", "restart_asks", 0],
		["rclick", "250,93", 10], ["check", "restart_kept", 0],         # ...a right click backs out
		["press", "confirm", 6], ["check", "restart_asks", 0],
		["press", "confirm", 10], ["check", "restart_kept", 0],          # "Keep climbing" is the default
		["press", "confirm", 6], ["press", "down", 4], ["check", "restart_yes", 0],
		["click", "160,105", 120],                                       # a click on Restart restarts
		["expect", "Level", 0],
		["check", "restarted", 0],
		["seed_continue", "", 0],                                # Continue from a secret room
		["scene", "res://scenes/chapter_select.tscn", 60],
		["press", "confirm", 10], ["check", "picker_continue", 0],
		["press", "confirm", 120],
		["expect", "Level", 0],
		["check", "continued", 0],
		["scene", "res://scenes/credits.tscn", 240],
		["expect", "Credits", 0],
		["done", "", 0],
	]


func _fail(msg: String) -> void:
	if failed == "":
		failed = msg
		print("UI FLOW FAIL: ", msg)
		var g: Node = get_node("/root/Game")
		print("  at frame %d; settings: window_scale=%s music=%s sfx=%s fullscreen=%s; using_pad=%s" % [frame,
			g.settings.get("window_scale"), g.settings.get("music"), g.settings.get("sfx"), g.settings.get("fullscreen"), g.using_pad])
		print("  last inputs (frame, step, event):")
		for l in input_log:
			print("    ", l)
		get_tree().quit(1)


## Records what reaches the scene (scripted presses, menu repeats, stick
## motion), so a failed check shows the inputs that led to it.
func _input(ev: InputEvent) -> void:
	var t := ""
	if ev is InputEventAction:
		t = "action %s %s" % [ev.action, "down" if ev.pressed else "up"]
	elif ev is InputEventKey:
		t = "key %s %s%s" % [OS.get_keycode_string(ev.physical_keycode), "down" if ev.pressed else "up", " echo" if ev.echo else ""]
	elif ev is InputEventJoypadButton:
		t = "pad button %d %s" % [ev.button_index, "down" if ev.pressed else "up"]
	elif ev is InputEventJoypadMotion:
		t = "pad axis %d %.2f" % [ev.axis, ev.axis_value]
	else:
		return
	input_log.append("%d, %d, %s" % [frame, idx, t])
	if input_log.size() > 40:
		input_log.pop_front()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _has_key(action: String, key: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == key:
			return true
	return false


func _pad_buttons(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	return out


func _scene() -> Node:
	return get_tree().current_scene


func _process(_d: float) -> void:
	frame += 1
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
		"pad_lost":
			# the pad in use, holding Right, goes away
			var g: Node = get_node("/root/Game")
			g.using_pad = true
			g.pad_device = 0
			Input.action_press("right")
			Input.joy_connection_changed.emit(0, false)
		"pad_found":
			Input.joy_connection_changed.emit(0, true)
		"die":
			cur.world._die()
			cur._on_death()
		"wait_play":
			if cur.mode != "play" and wait_frames < 600:
				wait_frames += 1
				idx -= 1
		"mouse":
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(300, 5)   # off every menu
			ev.relative = Vector2(3, 1)
			Input.parse_input_event(ev)
		"mouse_at", "click", "rclick", "click_marker", "click_pip", "click_hint":
			# in the 320x180 canvas: a move there, then a press and release
			var xy: PackedStringArray = str(s[1]).split(",")
			var pos := Vector2(float(xy[0]), float(xy[1])) if xy.size() == 2 else Vector2.ZERO
			if s[0] == "click_marker":     # a chapter's marker on chapter select's trail
				pos = cur._marker_pos(int(s[1]))
			elif s[0] == "click_pip":      # a room's pip in the checkpoint picker
				pos = cur._pip_pos(int(s[1]), get_node("/root/Game").checkpoint_rooms(cur.sel).size())
			elif s[0] == "click_hint":     # a prompt in Erase Save's box, as UIKit.hints() lays it out
				var pairs: Array = cur._erase_hints()
				pos = cur._erase_hints_at() + Vector2(0, 4)
				for j in int(s[1]):
					pos.x += maxf(PixelText.width(str(pairs[j][0])) + 6.0, 9.0) + 3.0 + PixelText.width(str(pairs[j][1])) + 9.0
				pos.x += 8.0
			var evs: Array = []
			var m := InputEventMouseMotion.new()
			m.position = pos
			m.relative = Vector2(1, 0)
			evs.append(m)
			if s[0] != "mouse_at":
				for down in [true, false]:
					var b := InputEventMouseButton.new()
					b.position = pos
					b.button_index = MOUSE_BUTTON_RIGHT if s[0] == "rclick" else MOUSE_BUTTON_LEFT
					b.pressed = down
					evs.append(b)
			for e in evs:
				input_log.append("%d step %d mouse %s" % [frame, idx, e.as_text()])
				get_viewport().push_input(e, true)
		"wait_n":
			wait = int(s[1])
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
				"opt_sel_2": ok = cur.screen == "options" and cur.opt_sel == 2
				"pause_sel_2": ok = cur.paused and cur.hud.pause_sel == 2 and not cur.hud.assist_open
				"pause_sel_0": ok = cur.paused and cur.hud.pause_sel == 0
				"assist_sel_4": ok = cur.hud.assist_open and cur.hud.assist_sel == 4
				"assist_closed": ok = cur.paused and not cur.hud.assist_open
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
				"still_waiting": ok = cur.controls.waiting_key and cur.controls.ITEMS[cur.controls.sel] == "jump"
				"pad_jump_x": ok = not Input.is_action_pressed("dash") and not cur.controls.waiting_key and _pad_buttons("jump") == [JOY_BUTTON_X] and _pad_buttons("dash").has(JOY_BUTTON_A) \
					and not _pad_buttons("dash").has(JOY_BUTTON_X) and get_node("/root/Game").pad_label("jump") == "X"
				"on_grab_mode": ok = cur.controls.ITEMS[cur.controls.sel] == "Grab Mode" and str(get_node("/root/Game").settings.grab_mode) == "hold"
				"grab_toggle": ok = str(get_node("/root/Game").settings.grab_mode) == "toggle" and _grab_reads() == [true, true, true, false, false, true, true, false]
				"grab_mode_kept": ok = cur.controls.ITEMS[cur.controls.sel] == "Reset Defaults" and str(get_node("/root/Game").settings.grab_mode) == "toggle"
				"grab_hold": ok = str(get_node("/root/Game").settings.grab_mode) == "hold" and _grab_reads() == [true, false, false, true, false, true, false, false]
				"pad_default": ok = _pad_buttons("jump") == [JOY_BUTTON_A, JOY_BUTTON_Y] and _pad_buttons("dash") == [JOY_BUTTON_X, JOY_BUTTON_B]
				"ghost_on": ok = bool(get_node("/root/Game").settings.route_ghost) and cur.ghost_world != null and cur.ghost_goal == "exit" \
					and get_node("/root/Game").ghost_mode() == "exit"
				"ghost_berries": ok = get_node("/root/Game").ghost_mode() == "berries" and cur.ghost_world != null and cur.room_id == "1-01" \
					and cur.ghost_goal == "collect" and cur.ghost_inputs == Solver.decode(str(Level._hint("1-01", 0, "1", "collect").inputs))
				"ghost_goal": ok = _ghost_goal_ok()
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
				"layout_names": ok = _layout_names_ok()
				"controls": ok = cur.screen == "controls"
				"jump_is_n": ok = get_node("/root/Game").key_label("jump") == "N"
				"jump_default": ok = get_node("/root/Game").key_label("jump") == "C"
				"main": ok = cur.screen == "main"
				"paused": ok = cur.paused and cur.hud.paused
				"air_dash_sim": ok = _air_dashes_ok()
				"on_air_dashes": ok = cur.hud.assist_open and cur.hud.assist_items[cur.hud.assist_sel] == "Air Dashes"
				"air_two": ok = str(get_node("/root/Game").settings.air_dashes) == "two" and cur.world.assist_air_dashes == World.AIR_DASHES_TWO \
					and cur.room_id == "1-01" and cur.world.max_dashes == 2
				"air_infinite": ok = str(get_node("/root/Game").settings.air_dashes) == "infinite" and cur.world.assist_air_dashes == World.AIR_DASHES_INFINITE
				"air_default": ok = str(get_node("/root/Game").settings.air_dashes) == "default" and cur.world.assist_air_dashes == World.AIR_DASHES_DEFAULT
				"on_pause_controls": ok = cur.hud.options_open and cur.hud.option_items[cur.hud.option_sel] == "Controls"
				"pause_controls": ok = cur.paused and cur.hud.controls_open and cur.hud.controls.sel == 0 and not cur.hud.controls.waiting_key
				"pause_jump_m": ok = cur.paused and cur.hud.controls_open and not cur.hud.controls.waiting_key \
					and get_node("/root/Game").kb_label("jump") == "M" and _has_key("jump", KEY_M) and not _has_key("jump", KEY_C)
				"grab_toggle_paused": ok = cur.hud.controls.ITEMS[cur.hud.controls.sel] == "Grab Mode" and str(get_node("/root/Game").settings.grab_mode) == "toggle"
				"pause_reset": ok = cur.hud.controls.ITEMS[cur.hud.controls.sel] == "Reset Defaults" and get_node("/root/Game").kb_label("jump") == "C" \
					and _has_key("jump", KEY_C) and str(get_node("/root/Game").settings.grab_mode) == "toggle"
				"grab_hold_paused": ok = str(get_node("/root/Game").settings.grab_mode) == "hold"
				"pause_controls_closed": ok = cur.paused and cur.hud.options_open and not cur.hud.controls_open
				"cursor_hidden": ok = get_node("/root/Game").cursor_hidden
				"cursor_shown": ok = not get_node("/root/Game").cursor_hidden
				"pad_paused": ok = cur.paused and cur.hud.paused and cur.mode == "play" and not get_node("/root/Game").using_pad \
					and not Input.is_action_pressed("right") and not cur.pause_pending
				"pause_waits": ok = not cur.paused and cur.pause_pending and cur.mode == "dead"
				"assist": ok = cur.hud.assist_open
				"options_open": ok = cur.hud.options_open
				"unpaused": ok = not cur.paused
				"resumed": ok = cur.chapter_n == 1 and cur.room_id == "1-02" and cur.chapter_time >= 100.0 and cur.deaths_this_chapter == 7 and not cur.full_run
				"has_continue": ok = cur.items.size() > 0 and cur.items[0] == "Continue" and cur.sel == 0
				"backfill": ok = _backfill_ok()
				"restart_asks": ok = cur.paused and cur.hud.confirm_restart and cur.hud.restart_sel == 0
				"restart_kept": ok = cur.paused and not cur.hud.confirm_restart and cur.room_id == "1-03" and cur.hud.pause_items[cur.hud.pause_sel] == "Restart Chapter"
				"restart_yes": ok = cur.hud.confirm_restart and cur.hud.restart_sel == 1
				"restarted": ok = cur.chapter_n == 1 and cur.room_id == "1-01" and cur.full_run and cur.chapter_time < 5.0 and cur.deaths_this_chapter == 0 and not cur.paused
				"picker_open": ok = cur.sel == 1 and cur.picking and Array(cur.cp_rooms) == ["1-01", "1-02", "1-03", "1-04"] and cur.cp_sel == 0
				"picker_last": ok = cur.picking and cur.cp_sel == 3
				"picker_closed": ok = not cur.picking and cur.leaving < 0
				"from_checkpoint": ok = cur.chapter_n == 1 and cur.room_id == "1-03" and not cur.full_run and cur.chapter_time < 5.0 and cur.deaths_this_chapter == 0
				"picker_continue": ok = cur.sel == 1 and cur.picking and Array(cur.cp_rooms) == ["1-01", "1-02", "1-03", "1-04", "1-05", "1-05s"] and cur.cp_sel == 5
				"continued": ok = cur.room_id == "1-05s" and cur.chapter_time >= 50.0 and cur.deaths_this_chapter == 3 and not cur.full_run
			var gm: Node = get_node("/root/Game")
			match s[1]:
				"erase_asks": ok = cur.screen == "confirm_reset" and int(gm.data.total_deaths) == 7
				"save_kept": ok = cur.screen == "options" and int(gm.data.total_deaths) == 7
				"save_erased": ok = cur.screen == "options" and int(gm.data.total_deaths) == 0 and int(gm.data.unlocked) == 0
				"ctl_sel_1": ok = cur.screen == "controls" and cur.controls.sel == 1 and not cur.controls.waiting_key
				"ctl_waiting": ok = cur.screen == "controls" and cur.controls.sel == 1 and cur.controls.waiting_key and gm.kb_label("dash") == "X"
				"ctl_cancelled": ok = cur.screen == "controls" and not cur.controls.waiting_key and gm.kb_label("dash") == "X"
				"pause_ctl_sel_1": ok = cur.hud.controls_open and cur.hud.controls.sel == 1
				"line_advanced": ok = cur.dialogue.active and cur.dialogue.idx > int(skip_id)
			if str(s[1]).begins_with("volume_"):        # volume_<music|sfx>_<tenths>
				ok = is_equal_approx(float(gm.settings[str(s[1]).get_slice("_", 1)]), int(str(s[1]).get_slice("_", 2)) / 10.0)
			if str(s[1]).begins_with("cs_sel_"):        # chapter select's chosen chapter
				ok = cur.sel == int(str(s[1]).get_slice("_", 2)) and not cur.picking and cur.leaving < 0
			elif str(s[1]).begins_with("cp_sel_"):      # the picker's chosen checkpoint
				ok = cur.picking and cur.cp_sel == int(str(s[1]).get_slice("_", 2)) and cur.leaving < 0
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
		"best_rows":
			# what the results screen says about Best: a first full climb, a
			# faster and a slower one, and runs that can't set it
			var cd: Dictionary = get_node("/root/Game").chapter_data(1)
			var got := []
			for c in [[0.0, 90.0, true], [100.0, 90.0, true], [80.0, 90.0, true], [80.0, 60.0, false]]:
				cd.best_time = c[0]
				cur.chapter_time = c[1]
				cur.full_run = c[2]
				cur.best_info = cur.record_best(cd)
				cur._show_results()
				var row: Array = cur.hud._result_rows()[2 if cur.hud._result_rows()[0][0] == "" else 3]
				got.append([row[1], row[2], snappedf(float(cd.best_time), 0.01)])
			cur.full_run = true
			var want := [["New Best!", "", 90.0], ["New Best!", "was 1:40.00", 90.0], ["Best", "1:20.00", 80.0], ["Best", "full climbs only", 80.0]]
			if got != want:
				_fail("step %d: Best rows %s" % [idx, got])
		"resume_end":
			var cd: Dictionary = get_node("/root/Game").chapter_data(1)
			cd.best_time = 300.0
			cur._on_end()
			if not is_equal_approx(float(cd.best_time), 300.0):
				_fail("step %d: resumed run overwrote Best with %.2f" % [idx, float(cd.best_time)])
		"seed_resume":
			get_node("/root/Game").data.resume = {"chapter": 1, "room": "1-02", "time": 100.0, "deaths": 7}
		"seed_checkpoints":
			# reached 1-01..1-03 and the secret 1-05s; a berry from 1-04 backfills it
			var g: Node = get_node("/root/Game")
			g.data.chapters.erase("1")
			g.data.resume = {}
			g.data.reached = {"1-01": true, "1-02": true, "1-03": true, "1-05s": true}
			g.data.collected = {"1-04:berry0": true}
		"unlock":
			get_node("/root/Game").data.unlocked = int(s[1])
		"mark_save":
			get_node("/root/Game").data.total_deaths = 7   # something Erase Save would clear
		"mark_line":
			if cur.dialogue.cur.is_empty():   # the scene opens with a pause: wait for a line
				idx -= 1
				wait = 2
			else:
				cur.dialogue.shown = cur.dialogue._total_chars()   # the line has finished typing
				skip_id = str(cur.dialogue.idx)
		"seed_continue":
			get_node("/root/Game").data.resume = {"chapter": 1, "room": "1-05s", "time": 50.0, "deaths": 3}
		"done":
			print("UI FLOW PASS")
			get_tree().quit(0)


## Checkpoint rules on a scratch save: a completed chapter offers every
## main-path room, an old save without room records is backfilled up to its
## Continue room, and secret rooms are never offered.
func _backfill_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var keep: Dictionary = g.data
	g.data = g.default_save()
	g.data.erase("reached")   # a save from before rooms were recorded
	var ok := true
	ok = ok and Array(g.reached_checkpoints(1)) == ["1-01"]
	g.data.resume = {"chapter": 1, "room": "1-06", "time": 1.0, "deaths": 0}
	ok = ok and Array(g.reached_checkpoints(1)) == ["1-01", "1-02", "1-03", "1-04", "1-05", "1-06"]
	g.chapter_data(1).complete = true
	ok = ok and g.reached_checkpoints(1).size() == 10 and not g.reached_checkpoints(1).has("1-05s")
	ok = ok and Array(g.checkpoint_rooms(8)) == ["8-01", "8-02"]
	# every checkpoint starts at spawn 0, which must have a proven route out
	for n in LevelDB.chapter_count():
		for rid in g.checkpoint_rooms(n):
			if Level._hint(rid, 0, str(n)).is_empty():
				print("no proven route from checkpoint %s" % rid)
				ok = false
	g.data = keep
	return ok


## Route Ghost Berries mode picks her route from what's still missing: the
## room's berries, then a secret room off it, then the exit. Old settings
## files (just `route_ghost: true`) read as Exit.
func _ghost_goal_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var ch := LevelDB.get_chapter(1)
	var all := {}
	for cid in ch.collectible_ids():
		all[cid] = true
	var some := {"1-05:berry0": true, "1-05:berry1": true}
	var got := [Level.ghost_goal_for(ch, "1", "1-02", 0, {}), Level.ghost_goal_for(ch, "1", "1-02", 0, all),
		Level.ghost_goal_for(ch, "1", "1-05", 0, {"1-05:berry0": true}), Level.ghost_goal_for(ch, "1", "1-05", 1, some),
		Level.ghost_goal_for(ch, "1", "1-05", 0, all), Level.ghost_goal_for(ch, "1", "1-05s", 0, some),
		Level.ghost_goal_for(LevelDB.get_chapter(3), "3", "3-01", 0, {})]
	var want := ["collect", "exit", "collect", "secret", "exit", "collect", "exit"]
	var saved: Dictionary = g.settings.duplicate()
	var modes := []
	for st in [{"route_ghost": true}, {"route_ghost": false, "ghost_goal": "berries"}, {"route_ghost": true, "ghost_goal": "berries"}]:
		g.settings = g.default_settings()
		g.settings.erase("ghost_goal")
		g.settings.merge(st, true)
		modes.append(g.ghost_mode())
	g.settings = saved
	if got != want or modes != ["exit", "off", "berries"]:
		print("ghost goals: ", got, " modes: ", modes)
	return got == want and modes == ["exit", "off", "berries"]


## Key names follow the keyboard layout: the default bindings under stand-ins
## for French (W/A/Z print Z/Q/W) and German (Z prints Y) layouts, a letter the
## pixel font can't draw falls back to the US name, and no stub changes nothing.
func _layout_names_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var got := []
	for stub in [{KEY_W: KEY_Z, KEY_A: KEY_Q, KEY_Z: KEY_W, KEY_Q: KEY_A, KEY_SEMICOLON: KEY_M},
			{KEY_Z: KEY_Y, KEY_Y: KEY_Z}, {KEY_Z: 0x044F, KEY_C: 0x0441}, {}]:
		g.layout_stub = stub
		got.append([g.key_label("grab"), g.key_label("jump"), g.key_name(KEY_W), g.key_name(KEY_A), g.key_name(KEY_SEMICOLON), g.key_name(KEY_LEFT)])
	g.layout_stub = null
	var want := [["W", "C", "Z", "Q", "M", "Left"], ["Y", "C", "W", "A", "Semicolon", "Left"],
		["Z", "C", "W", "A", "Semicolon", "Left"], ["Z", "C", "W", "A", "Semicolon", "Left"]]
	if got != want:
		print("layout names: ", got)
	return got == want


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
	return seen > 0 and apart > 0 and pw.exited and g4.exited and _ghost_open_ok("1", "1-03", RoomDef.CRUMBLE, false) \
		and _ghost_open_ok("3", "3-02", -1, true)


## The other direction: the player stands still while the ghost runs her
## route. Cells open for her but solid for the player are only boards (1-03)
## or mask blocks (3-02), none at the start, and the near ones are a subset
## within the radius. Her boards fall after she has left them, so only the
## mask room must have some near her.
func _ghost_open_ok(ch_key: String, rid: String, kind: int, need_near: bool) -> bool:
	var ch := LevelDB.get_chapter(int(ch_key))
	var def := ch.room(rid)
	var pw := World.new()
	pw.load_room(def, 0, ch.dashes)
	var gw := World.new()
	gw.load_room(def, 0, ch.dashes)
	if not RoomView.ghost_open_cells(pw, gw).is_empty():
		return false
	var seen := 0
	var near := 0
	for inp in Solver.decode(str(Level._hint(rid, 0, ch_key).inputs)):
		gw.step(inp)
		var all := RoomView.ghost_open_cells(pw, gw)
		for i in all:
			var t := def.cells[i]
			if (kind >= 0 and t != kind) or (kind < 0 and t != RoomDef.MASK_A and t != RoomDef.MASK_B):
				print("ghost open cell %d in %s is %d" % [i, rid, t])
				return false
		seen += all.size()
		var c := Vector2(gw.x + World.PW / 2.0, gw.y + World.PH / 2.0)
		for i in RoomView.ghost_open_cells(pw, gw, RoomView.GHOST_OPEN_RADIUS):
			if not all.has(i) or c.distance_to(Vector2((i % def.w) * 8 + 4, (i / def.w) * 8 + 4)) > RoomView.GHOST_OPEN_RADIUS:
				return false
			near += 1
		if gw.exited or gw.dead:
			break
	if seen == 0 or (need_near and near == 0):
		print("ghost open cells in %s: %d seen, %d near" % [rid, seen, near])
	return seen > 0 and (near > 0 or not need_near) and gw.exited


## Air Dashes assist in the simulation: from a jump, Mira dashes up, then
## tries again twice in the air. Default allows one, Two two, Infinite all
## three; a room the story keeps dashless stays dashless; respawning keeps it.
func _air_dashes_ok() -> bool:
	var want := {World.AIR_DASHES_DEFAULT: [1, 0], World.AIR_DASHES_TWO: [2, 0], World.AIR_DASHES_INFINITE: [3, 1]}
	var ok := true
	for mode in want:
		var r := _air_dash_run("1", "1-01", mode)
		if r != want[mode]:
			print("air dashes %d: %s dashes fired, %s left (want %s)" % [mode, r[0], r[1], want[mode]])
			ok = false
	var r0 := _air_dash_run("0", "0-01", World.AIR_DASHES_TWO)
	var r7 := _air_dash_run("7", "7-01", World.AIR_DASHES_TWO)
	if r0 != [0, 0] or r7 != [2, 0]:
		print("air dashes: prologue %s, summit %s" % [r0, r7])
		ok = false
	return ok


func _air_dash_run(ch_key: String, rid: String, mode: int) -> Array:
	var ch := LevelDB.get_chapter(int(ch_key))
	var w := World.new()
	w.assist_air_dashes = mode
	w.load_room(ch.room(rid), 0, ch.dashes)
	w.reset_room()   # a respawn keeps the assist
	var fired := 0
	var seq := []
	for i in 30: seq.append(0)
	for i in 6: seq.append(World.IN_JUMP)
	for k in 3:
		seq.append(World.IN_DASH | World.IN_UP)
		for i in 13: seq.append(0)   # past the dash cooldown
	for inp in seq:
		w.step(inp)
		if w.events.has("dash"):
			fired += 1
	return [fired, w.dashes]


## Grab as the simulation sees it over press, release, idle, press, release,
## press, release, and then after a death's release_grab().
func _grab_reads() -> Array:
	var g: Node = get_node("/root/Game")
	var out := []
	for down in [true, false, false, true, false, true, false]:
		if down:
			Input.action_press("grab")
		else:
			Input.action_release("grab")
		out.append((g.read_input() & World.IN_GRAB) != 0)
	g.release_grab()
	out.append((g.read_input() & World.IN_GRAB) != 0)
	return out
