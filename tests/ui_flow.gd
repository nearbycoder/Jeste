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
		["press", "down", 6], ["press", "confirm", 20],          # Options
		["check", "options", 0],
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
				"controls": ok = cur.screen == "controls"
				"jump_is_n": ok = get_node("/root/Game").key_label("jump") == "N"
				"jump_default": ok = get_node("/root/Game").key_label("jump") == "C"
				"main": ok = cur.screen == "main"
				"paused": ok = cur.paused and cur.hud.paused
				"assist": ok = cur.hud.assist_open
				"options_open": ok = cur.hud.options_open
				"unpaused": ok = not cur.paused
				"resumed": ok = cur.chapter_n == 1 and cur.room_id == "1-02"
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
		"seed_resume":
			get_node("/root/Game").data.resume = {"chapter": 1, "room": "1-02"}
		"done":
			print("UI FLOW PASS")
			get_tree().quit(0)
