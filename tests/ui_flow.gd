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


func _ready() -> void:
	# keep this driver alive across scene changes: hand "current scene" to a dummy
	var dummy := Node.new()
	get_tree().root.add_child.call_deferred(dummy)
	(func(): get_tree().current_scene = dummy).call_deferred()
	var game: Node = get_node("/root/Game")
	game.headless_test = true
	game.data = game.default_save()
	game.data.unlocked = 8
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
		["check", "pad_labels", 0],
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
		["mark_music", "", 0],
		["stick", "right", 6],                                    # one stick push = one slider step
		["check", "music_one_step", 0],
		["stick", "left", 6],
		["press", "right", 4], ["press", "down", 4], ["press", "left", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],  # toggles
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Controls
		["check", "controls", 0],
		["press", "confirm", 6],                                  # rebind Jump
		["key", "N", 6],
		["check", "jump_is_n", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "jump_default", 0],
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
		["skip_dialogue", "", 60],
		["press", "pause", 20],
		["check", "paused", 0],
		["stick", "down", 4],
		["check", "pause_sel_1", 0],
		["stick", "up", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["check", "assist", 0],
		["press", "down", 4], ["press", "confirm", 4], ["press", "confirm", 4], ["press", "back", 10],
		["press", "down", 4], ["press", "confirm", 10],          # Options
		["check", "options_open", 0],
		["press", "right", 4], ["press", "left", 4], ["press", "back", 10],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 20],   # Resume
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
				"title_sel_0": ok = cur.sel == 0
				"held_down": ok = Input.is_action_pressed("down") and cur.sel == 1
				"pause_sel_1": ok = cur.hud.pause_sel == 1
				"music_one_step": ok = is_equal_approx(float(get_node("/root/Game").settings.music), minf(music_before + 0.1, 1.0))
				"pad_labels":
					var g: Node = get_node("/root/Game")
					ok = g.pad_family("Xbox Series Controller") == "xbox" and g.pad_family("PS5 Controller") == "playstation" \
						and g.pad_family("Sony DualSense") == "playstation" and g.pad_family("Nintendo Switch Pro Controller") == "nintendo" \
						and g.pad_family("") == "xbox" and g.PAD_LABELS.nintendo.jump == "B"
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
				_fail("step %d: check %s failed" % [idx, s[1]])
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
