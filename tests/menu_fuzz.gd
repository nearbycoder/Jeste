extends Node
## Random input through the menus and the level: keys, pad buttons, the
## stick, triggers, mouse moves, clicks and the wheel, from the title through
## Options, Controls, chapter select, the checkpoint picker, levels, pause,
## Assist, cutscenes, results and the credits, plus now and then the pad
## being unplugged (and plugged back in) and the window losing focus. Every
## input is let go at random intervals. Checked on every frame:
##   - a level is paused exactly when its pause menu shows;
##   - an unpaused level runs at the chosen Game Speed and keeps stepping
##     (unless a cutscene, a dash aim, a transition or the results hold it);
##   - a Controls panel waits for a key only while it is open;
##   - a level in play that loses focus or its pad is paused by the next frame;
## and, once everything is let go, that no action still reads as held.
## Script errors are caught by the runner (tests/run_tests.py) from the log.
## Quit is taken off the title menu so the run can't end itself.
##
##   godot --headless --path . --fixed-fps 60 res://tests/menu_fuzz.tscn -- <seed> <frames>
## Prints "MENU FUZZ PASS" or "MENU FUZZ FAIL: ...". Runs with saving on, so
## it refuses to start unless user:// is inside the repo's build/ folder.

const KEYS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S, KEY_C, KEY_SPACE, KEY_J,
	KEY_X, KEY_K, KEY_SHIFT, KEY_Z, KEY_V, KEY_L, KEY_ENTER, KEY_ESCAPE, KEY_P, KEY_BACKSPACE, KEY_Q]
const PAUSE_KEYS := [KEY_ESCAPE, KEY_P, KEY_ENTER]
const BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_START, JOY_BUTTON_BACK]
const CHECK_ACTIONS := ["jump", "dash", "grab", "up", "down", "left", "right", "pause", "confirm", "back"]

var rng := RandomNumberGenerator.new()
var seed_n := 1
var frames := 20000
var frame := 0
var held_keys := {}
var held_buttons := {}
var stick_moved := false
var trigger_on := false
var next_release := 0
var check_at := -1
var failed := false
var history: Array = []          # the last inputs, printed on a failure
var visits := {}                 # scene name -> frames spent there
var counts := {"releases": 0, "levels": 0}
var seen := {}                   # menus and states reached, for the report
var last_scene := ""
var last_world_frame := -1
var still_frames := 0
var expect_pause_at := -1        # a level in play lost focus or its pad on this frame


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: seed_n = int(a[0])
	if a.size() > 1: frames = int(a[1])
	if not OS.get_user_data_dir().contains("/build/"):
		print("MENU FUZZ REFUSED: user data is at ", OS.get_user_data_dir(), ", not in build/")
		get_tree().quit(2)
		return
	rng.seed = seed_n
	var dummy := Node.new()   # keep this driver alive across scene changes
	get_tree().root.add_child.call_deferred(dummy)
	(func(): get_tree().current_scene = dummy).call_deferred()
	var game: Node = get_node("/root/Game")
	game.data = game.default_save()
	game.data.unlocked = 8
	game.data.reached = {"1-01": true, "1-02": true, "1-03": true, "3-01": true, "3-02": true, "5-01": true, "5-02": true}
	game.settings = game.default_settings()
	game.setup_input()
	next_release = 200 + rng.randi_range(0, 400)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


func _scene() -> Node:
	return get_tree().current_scene


func _process(_d: float) -> void:
	if failed:
		return
	frame += 1
	var cur := _scene()
	var nm := str(cur.name) if cur else ""
	visits[nm] = int(visits.get(nm, 0)) + 1
	if nm != last_scene:
		history.append("%d scene %s" % [frame, nm])
		if nm == "Level":
			counts.levels += 1
		last_scene = nm
		last_world_frame = -1
		still_frames = 0
	if nm == "Title" and cur.items.has("Quit"):
		cur.items.erase("Quit")
		cur.sel = clampi(cur.sel, 0, cur.items.size() - 1)
	if history.size() > 400:
		history = history.slice(history.size() - 100)
	_check(cur, nm)
	if failed:
		return
	if frame >= frames:
		_release_all()
		print("MENU FUZZ PASS seed %d, %d frames, scenes %s, %s, reached %s" % [seed_n, frame, visits, counts, ", ".join(seen.keys())])
		get_tree().quit(0)
		return
	if frame == check_at:
		_check_released()
		check_at = -1
	if frame >= next_release:
		_release_all()
		counts.releases += 1
		check_at = frame + 4
		next_release = frame + 120 + rng.randi_range(0, 600)
		return
	if check_at > 0:
		return   # let the release settle before the check
	if rng.randf() < 0.45:
		_random_input(cur, nm)


func _random_input(cur: Node, nm: String) -> void:
	var playing: bool = nm == "Level" and not cur.paused and cur.mode == "play"
	var r := rng.randf()
	if r < 0.55:
		var k: int = KEYS[rng.randi_range(0, KEYS.size() - 1)]
		if playing and k in PAUSE_KEYS and rng.randf() < 0.9:
			k = KEY_RIGHT   # mostly play while playing
		_key(k, not held_keys.has(k))
	elif r < 0.75:
		var b: int = BUTTONS[rng.randi_range(0, BUTTONS.size() - 1)]
		if playing and b == JOY_BUTTON_START and rng.randf() < 0.9:
			b = JOY_BUTTON_A
		_button(b, not held_buttons.has(b))
	elif r < 0.85:
		var ang := rng.randf() * TAU
		var tilt := 0.0 if rng.randf() < 0.3 else rng.randf_range(0.1, 1.0)
		_axis(JOY_AXIS_LEFT_X, cos(ang) * tilt)
		_axis(JOY_AXIS_LEFT_Y, sin(ang) * tilt)
		stick_moved = tilt > 0.0
	elif r < 0.88:
		trigger_on = not trigger_on
		_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0 if trigger_on else 0.0)
	elif r < 0.885:
		_lose_pad(cur, nm)
	elif r < 0.89:
		_lose_focus(cur, nm)
	else:
		_mouse(nm)


## The pad goes away with its buttons, stick and trigger still held (no
## release events, as when a cable is pulled), then comes back. Whatever it
## held must stop reading as held.
func _lose_pad(cur: Node, nm: String) -> void:
	held_buttons.clear()
	stick_moved = false
	trigger_on = false
	history.append("%d pad unplugged" % frame)
	if nm == "Level" and cur.mode == "play" and not cur.paused:
		expect_pause_at = frame + 1
	Input.joy_connection_changed.emit(0, false)
	Input.joy_connection_changed.emit(0, true)
	seen["pad_lost"] = true


func _lose_focus(cur: Node, nm: String) -> void:
	history.append("%d focus out" % frame)
	if nm == "Level" and cur.mode == "play" and not cur.paused:
		expect_pause_at = frame + 1
	if cur:
		cur.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		cur.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	seen["focus_lost"] = true


func _key(k: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = down
	if down: held_keys[k] = true
	else: held_keys.erase(k)
	history.append("%d key %s %s" % [frame, OS.get_keycode_string(k), "down" if down else "up"])
	Input.parse_input_event(ev)


func _button(b: int, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = b
	ev.pressed = down
	if down: held_buttons[b] = true
	else: held_buttons.erase(b)
	history.append("%d pad %d %s" % [frame, b, "down" if down else "up"])
	Input.parse_input_event(ev)


func _axis(axis: int, v: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = v
	history.append("%d axis %d %.2f" % [frame, axis, v])
	Input.parse_input_event(ev)


func _mouse(nm: String) -> void:
	var pos := Vector2(rng.randf_range(0, 320), rng.randf_range(0, 180))
	var evs: Array = []
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.relative = Vector2(1, 0)
	evs.append(m)
	var r := rng.randf()
	if r < 0.5:
		var btn := MOUSE_BUTTON_LEFT if r < 0.4 else MOUSE_BUTTON_RIGHT
		if nm == "Level" and rng.randf() < 0.7:
			btn = MOUSE_BUTTON_LEFT
		for down in [true, false]:
			var b := InputEventMouseButton.new()
			b.position = pos
			b.button_index = btn
			b.pressed = down
			evs.append(b)
	elif r < 0.75:
		for down in [true, false]:
			var b := InputEventMouseButton.new()
			b.position = pos
			b.button_index = MOUSE_BUTTON_WHEEL_UP if rng.randf() < 0.5 else MOUSE_BUTTON_WHEEL_DOWN
			b.factor = 1.0 if rng.randf() < 0.7 else rng.randf_range(0.2, 0.9)
			b.pressed = down
			evs.append(b)
	for e in evs:
		history.append("%d mouse %s" % [frame, e.as_text()])
		get_viewport().push_input(e, true)


func _release_all() -> void:
	for k in held_keys.keys():
		_key(k, false)
	for b in held_buttons.keys():
		_button(b, false)
	if stick_moved:
		_axis(JOY_AXIS_LEFT_X, 0.0)
		_axis(JOY_AXIS_LEFT_Y, 0.0)
		stick_moved = false
	if trigger_on:
		_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		trigger_on = false


func _check_released() -> void:
	var g: Node = get_node("/root/Game")
	for a in CHECK_ACTIONS:
		if Input.is_action_pressed(a):
			_fail("%s still reads as held after every input was let go" % a)
			return
	if g.stick_input() != 0:
		_fail("the stick still gives a direction after it was let go")


func _check(cur: Node, nm: String) -> void:
	var g: Node = get_node("/root/Game")
	if g.rebinding:
		seen["rebind"] = true
	if frame == expect_pause_at:
		expect_pause_at = -1
		if nm == "Level" and not cur.paused and not cur.pause_pending:
			_fail("a level in play lost focus or its pad and didn't pause")
			return
	if nm == "Level":
		if not cur.world:
			return
		for k in ["paused", "aiming"]:
			if cur.get(k):
				seen[k] = true
		for k in ["assist_open", "options_open", "controls_open", "confirm_restart", "results"]:
			if cur.hud.get(k):
				seen[k] = true
		seen["level_" + str(cur.mode)] = true
		if cur.paused != cur.hud.paused:
			_fail("level paused=%s but its pause menu paused=%s" % [cur.paused, cur.hud.paused])
			return
		if g.rebinding and not (cur.hud.controls_open and cur.hud.controls.waiting_key):
			_fail("waiting for a key to bind with no Controls panel open")
			return
		if not cur.paused:
			if not is_equal_approx(Engine.time_scale, float(g.settings.game_speed)):
				_fail("unpaused at time scale %.2f, Game Speed %.2f" % [Engine.time_scale, float(g.settings.game_speed)])
				return
			var stepping: bool = cur.mode == "play" and not cur.aiming and not cur.hud.results and not cur.finished
			if stepping and cur.world.frame == last_world_frame:
				still_frames += 1
				if still_frames > 180:
					_fail("an unpaused level in play hasn't stepped for 3 s (mode %s)" % cur.mode)
					return
			else:
				still_frames = 0
			last_world_frame = cur.world.frame
	elif nm == "ChapterSelect" and cur.get("picking"):
		seen["picker"] = true
	elif nm == "Title":
		seen["title_" + str(cur.screen)] = true
		if g.rebinding and not (cur.screen == "controls" and cur.controls.waiting_key):
			_fail("waiting for a key to bind with no Controls panel open (title)")


func _fail(msg: String) -> void:
	failed = true
	print("MENU FUZZ FAIL: seed %d frame %d: %s" % [seed_n, frame, msg])
	var cur := _scene()
	if cur and cur.name == "Level":
		print("  level: room %s mode %s paused %s aiming %s menus: assist %s options %s controls %s results %s" % [cur.room_id, cur.mode,
			cur.paused, cur.aiming, cur.hud.assist_open, cur.hud.options_open, cur.hud.controls_open, cur.hud.results])
	print("  last inputs:")
	for l in history.slice(maxi(0, history.size() - 40)):
		print("    ", l)
	get_tree().quit(1)
