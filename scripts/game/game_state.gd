extends Node
## Autoload "Game": save data, settings, input bindings and scene flow.

const SAVE_PATH := "user://jeste_save.json"
const SETTINGS_PATH := "user://jeste_settings.json"

const CHAPTER_TITLES := [
	"Prologue", "Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4",
	"Chapter 5", "Chapter 6", "Chapter 7", "Epilogue",
]

var data: Dictionary = {}
var settings: Dictionary = {}
var pending_chapter := 0
var pending_room := ""
var pending_spawn := 0
var headless_test := false     # set by test harness: no saving to disk
var using_pad := false         # last input came from a gamepad (prompts show pad buttons)
var pad_device := 0            # gamepad that sent the last pad input (for button names)
## Button names per controller family. Godot maps face buttons by position
## (JOY_BUTTON_A is always the bottom one), so only the names differ.
const PAD_LABELS := {
	"xbox": {"jump": "A", "dash": "X", "grab": "RB"},
	"playstation": {"jump": "Cross", "dash": "Square", "grab": "R1"},
	"nintendo": {"jump": "B", "dash": "Y", "grab": "R"},
}
const PAD_DIRS := {"up": "Up", "down": "Down", "left": "Left", "right": "Right"}
## Stick hysteresis for menus: an axis counts as pushed past STICK_PRESS and
## released again below STICK_RELEASE.
const STICK_PRESS := 0.5
const STICK_RELEASE := 0.3
var _axis_dir := {}            # (device, axis) -> -1, 0 or 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	setup_input()
	load_save()
	apply_settings()


func _exit_tree() -> void:
	Art.clear_cache()


func _input(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton or (ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.5):
		using_pad = true
		pad_device = ev.device
	elif ev is InputEventKey or ev is InputEventMouseButton:
		using_pad = false
	# A stick push sends a stream of motion events, and every one past the
	# deadzone reads as a fresh action press. Menus react to events, so pass on
	# only the event where the stick first crosses the threshold. Gameplay polls
	# Input state, which this doesn't touch.
	if ev is InputEventJoypadMotion and not stick_edge(ev) and is_inside_tree():
		get_viewport().set_input_as_handled()


## True when this motion event pushes its axis into a new direction.
func stick_edge(ev: InputEventJoypadMotion) -> bool:
	var key := ev.device * 64 + ev.axis
	var prev: int = _axis_dir.get(key, 0)
	var d := prev
	if absf(ev.axis_value) >= STICK_PRESS:
		d = 1 if ev.axis_value > 0.0 else -1
	elif absf(ev.axis_value) < STICK_RELEASE:
		d = 0
	_axis_dir[key] = d
	return d != 0 and d != prev


## Controller family from the device name reported by SDL.
static func pad_family(joy_name: String) -> String:
	var n := joy_name.to_lower()
	for k in ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony"]:
		if k in n:
			return "playstation"
	for k in ["nintendo", "switch", "joy-con", "joycon", "pro controller"]:
		if k in n:
			return "nintendo"
	return "xbox"


func pad_label(action: String) -> String:
	if PAD_DIRS.has(action):
		return PAD_DIRS[action]
	var fam := pad_family(Input.get_joy_name(pad_device))
	return PAD_LABELS[fam].get(action, "?")


## Label for the movement prompt ("Arrows" on keyboard, "Stick" on a pad).
func move_label() -> String:
	return "Stick" if using_pad else "Arrows"


# ---------------------------------------------------------------- input

func _key(action: String, keys: Array) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _pad(action: String, buttons: Array) -> void:
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)


func _axis(action: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


const REBINDABLE := ["jump", "dash", "grab", "up", "down", "left", "right"]
const DEFAULT_KEYS := {
	"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D],
	"up": [KEY_UP, KEY_W], "down": [KEY_DOWN, KEY_S],
	"jump": [KEY_C, KEY_SPACE, KEY_J], "dash": [KEY_X, KEY_K, KEY_SHIFT],
	"grab": [KEY_Z, KEY_V, KEY_L],
}


## Current keyboard keys per action: custom bindings override the defaults.
func keys_for(action: String) -> Array:
	var b: Dictionary = settings.get("bindings", {}) if settings else {}
	if b.has(action):
		var out := []
		for k in b[action]:
			out.append(int(k))   # JSON stores numbers as floats
		return out
	return DEFAULT_KEYS.get(action, [])


## Short label of an action's primary key for on-screen prompts.
func kb_label(action: String) -> String:
	var ks := keys_for(action)
	return "?" if ks.is_empty() else key_name(int(ks[0]))


func key_label(action: String) -> String:
	if using_pad:
		return pad_label(action)
	var ks := keys_for(action)
	if ks.is_empty():
		return "?"
	return key_name(int(ks[0]))


static func key_name(k: int) -> String:
	match k:
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_SPACE: return "Space"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
	return OS.get_keycode_string(k)


## Bind `key` to `action`; if another action used it, that action takes over
## this action's previous primary key (a swap, so nothing is left unbound).
func rebind(action: String, key: int) -> void:
	var b: Dictionary = settings.get("bindings", {})
	var old: Array = keys_for(action).duplicate()
	for other in REBINDABLE:
		if other == action:
			continue
		var ks: Array = keys_for(other).duplicate()
		if ks.has(key):
			ks.erase(key)
			if not old.is_empty() and not ks.has(old[0]):
				ks.insert(0, old[0])
			b[other] = ks
	b[action] = [key]
	settings.bindings = b
	setup_input()


func reset_bindings() -> void:
	settings.bindings = {}
	setup_input()


func setup_input() -> void:
	var defs := {}
	for a in REBINDABLE:
		defs[a] = keys_for(a)
	defs["pause"] = [KEY_ESCAPE, KEY_ENTER, KEY_P]
	defs["confirm"] = [KEY_SPACE, KEY_ENTER] + keys_for("jump")
	defs["back"] = [KEY_ESCAPE, KEY_BACKSPACE] + keys_for("dash")
	for a in defs:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a, 0.4)
		var seen := {}
		for k in defs[a]:
			if not seen.has(k):
				seen[k] = true
				_key(a, [k])
	_pad("jump", [JOY_BUTTON_A, JOY_BUTTON_Y])
	_pad("dash", [JOY_BUTTON_X, JOY_BUTTON_B])
	_pad("grab", [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER])
	_pad("pause", [JOY_BUTTON_START])
	_pad("confirm", [JOY_BUTTON_A])
	_pad("back", [JOY_BUTTON_B])
	_pad("left", [JOY_BUTTON_DPAD_LEFT]); _pad("right", [JOY_BUTTON_DPAD_RIGHT])
	_pad("up", [JOY_BUTTON_DPAD_UP]); _pad("down", [JOY_BUTTON_DPAD_DOWN])
	_axis("left", JOY_AXIS_LEFT_X, -1.0); _axis("right", JOY_AXIS_LEFT_X, 1.0)
	_axis("up", JOY_AXIS_LEFT_Y, -1.0); _axis("down", JOY_AXIS_LEFT_Y, 1.0)
	_axis("grab", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("grab", JOY_AXIS_TRIGGER_LEFT, 1.0)


func read_input() -> int:
	var b := 0
	if Input.is_action_pressed("left"): b |= World.IN_LEFT
	if Input.is_action_pressed("right"): b |= World.IN_RIGHT
	if Input.is_action_pressed("up"): b |= World.IN_UP
	if Input.is_action_pressed("down"): b |= World.IN_DOWN
	if Input.is_action_pressed("jump"): b |= World.IN_JUMP
	if Input.is_action_pressed("dash"): b |= World.IN_DASH
	if Input.is_action_pressed("grab"): b |= World.IN_GRAB
	if (b & World.IN_LEFT) and (b & World.IN_RIGHT):
		b &= ~(World.IN_LEFT | World.IN_RIGHT)
	if (b & World.IN_UP) and (b & World.IN_DOWN):
		b &= ~(World.IN_UP | World.IN_DOWN)
	return b


# ---------------------------------------------------------------- save data

func default_save() -> Dictionary:
	return {
		"version": 1,
		"collected": {},
		"chapters": {},
		"seen": {},
		"unlocked": 0,
		"total_deaths": 0,
		"playtime": 0.0,
		"resume": {},
	}


func load_save() -> void:
	data = default_save()
	if headless_test:
		return
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				data[k] = parsed[k]


func save() -> void:
	if headless_test:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func reset_save() -> void:
	data = default_save()
	save()


func chapter_data(n: int) -> Dictionary:
	var key := str(n)
	if not data.chapters.has(key):
		data.chapters[key] = {"complete": false, "deaths": 0, "best_time": 0.0, "golden": false}
	return data.chapters[key]


func is_collected(cid: String) -> bool:
	return data.collected.has(cid)


func collect(cid: String) -> bool:
	if data.collected.has(cid):
		return false
	data.collected[cid] = true
	return true


func berries_in_chapter(n: int) -> int:
	var c := 0
	var prefix_rooms := LevelDB.get_chapter(n).rooms
	for cid in data.collected:
		var room_id: String = str(cid).split(":")[0]
		if prefix_rooms.has(room_id) and ("berry" in str(cid) or "winged" in str(cid)):
			c += 1
	return c


func bell_in_chapter(n: int) -> bool:
	var rooms := LevelDB.get_chapter(n).rooms
	for cid in data.collected:
		var room_id: String = str(cid).split(":")[0]
		if rooms.has(room_id) and "bell" in str(cid):
			return true
	return false


func total_berries() -> int:
	var c := 0
	for cid in data.collected:
		if "berry" in str(cid) or "winged" in str(cid):
			c += 1
	return c


func total_bells() -> int:
	var c := 0
	for cid in data.collected:
		if "bell" in str(cid):
			c += 1
	return c


func mark_seen(id: String) -> void:
	data.seen[id] = true


func has_seen(id: String) -> bool:
	return data.seen.has(id)


# ---------------------------------------------------------------- settings

func default_settings() -> Dictionary:
	return {
		"music": 0.7, "sfx": 0.8, "fullscreen": false, "screen_shake": true,
		"show_timer": false, "game_speed": 1.0, "infinite_stamina": false,
		"invincible": false, "rumble": true, "window_scale": 0,
	}


func load_settings() -> void:
	settings = default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				settings[k] = parsed[k]


func save_settings() -> void:
	if headless_test:
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))


func apply_settings() -> void:
	if headless_test or DisplayServer.get_name() == "headless":
		return
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_window_size()
	Engine.time_scale = float(settings.game_speed)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, 0.0)


# ---------------------------------------------------------------- window size

const BASE := Vector2i(320, 180)


## Integer scales for a screen: [largest that fits, default]. The default is
## the largest scale that covers at most 75% of the screen in each direction.
static func fit_scales(screen: Vector2i) -> Array:
	var most := maxi(1, mini(screen.x / BASE.x, (screen.y - 48) / BASE.y))   # room for a title bar
	var auto := mini(int(screen.x * 0.75) / BASE.x, int(screen.y * 0.75) / BASE.y)
	return [most, clampi(auto, mini(2, most), most)]


func _screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size


func max_window_scale() -> int:
	return fit_scales(_screen_size())[0]


## Window scale in use: the saved choice (0 = automatic), capped to the screen.
func window_scale() -> int:
	var fit := fit_scales(_screen_size())
	var s := int(settings.get("window_scale", 0))
	return fit[1] if s <= 0 else mini(s, fit[0])


func window_scale_label() -> String:
	var s := int(settings.get("window_scale", 0))
	return "Auto %dx" % window_scale() if s <= 0 else "%dx" % window_scale()


## Steps through Auto, 2x .. the largest scale that fits (wrapping).
func step_window_scale(d: int) -> void:
	var opts := [0]
	for k in range(2, max_window_scale() + 1):
		opts.append(k)
	var cur := int(settings.get("window_scale", 0))
	var i := opts.find(mini(cur, max_window_scale()) if cur > 0 else 0)
	settings.window_scale = opts[posmod(maxi(i, 0) + d, opts.size())]
	if settings.fullscreen:
		settings.fullscreen = false
	apply_settings()


func toggle_fullscreen() -> void:
	settings.fullscreen = not settings.fullscreen
	apply_settings()


func _apply_window_size() -> void:
	var want := BASE * window_scale()
	if DisplayServer.window_get_size() == want:
		return
	DisplayServer.window_set_size(want)
	var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(scr.position + (scr.size - want) / 2)


## Gamepad vibration (weak/strong motors scaled together), if enabled.
func rumble(strength: float, duration: float) -> void:
	if headless_test or not bool(settings.get("rumble", true)):
		return
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, clampf(strength, 0.0, 1.0), clampf(strength * 0.7, 0.0, 1.0), duration)


# ---------------------------------------------------------------- flow

func goto_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func goto_chapter_select() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/chapter_select.tscn")


func start_chapter(n: int, room: String = "") -> void:
	pending_chapter = n
	pending_room = room
	pending_spawn = 0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func goto_credits() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/credits.tscn")
