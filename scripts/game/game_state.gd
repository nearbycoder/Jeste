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
## Button names per controller family [xbox, playstation, nintendo]. Godot
## maps face buttons by position (JOY_BUTTON_A is always the bottom one), so
## only the names differ. These are also the buttons a player may rebind.
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: ["A", "Cross", "B"], JOY_BUTTON_B: ["B", "Circle", "A"],
	JOY_BUTTON_X: ["X", "Square", "Y"], JOY_BUTTON_Y: ["Y", "Triangle", "X"],
	JOY_BUTTON_LEFT_SHOULDER: ["LB", "L1", "L"], JOY_BUTTON_RIGHT_SHOULDER: ["RB", "R1", "R"],
	JOY_BUTTON_LEFT_STICK: ["LS", "L3", "LS"], JOY_BUTTON_RIGHT_STICK: ["RS", "R3", "RS"],
}
const PAD_FAMILIES := ["xbox", "playstation", "nintendo"]
const PAD_REBINDABLE := ["jump", "dash", "grab"]
const DEFAULT_PAD := {
	"jump": [JOY_BUTTON_A, JOY_BUTTON_Y], "dash": [JOY_BUTTON_X, JOY_BUTTON_B],
	"grab": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER],
}
const PAD_DIRS := {"up": "Up", "down": "Down", "left": "Left", "right": "Right"}
## Stick hysteresis for menus: an axis counts as pushed past STICK_PRESS and
## released again below STICK_RELEASE.
const STICK_PRESS := 0.5
const STICK_RELEASE := 0.3
var _axis_dir := {}            # (device, axis) -> -1, 0 or 1
## Menu hold-to-repeat: a held direction re-sends its press after
## REPEAT_DELAY, then every REPEAT_RATE seconds (real time).
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.09
const REPEAT_ACTIONS := ["up", "down", "left", "right"]
var _held := {}                # action -> seconds held
## A gamepad was unplugged (or its battery died); a level pauses on it.
signal pad_disconnected


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	setup_input()
	load_save()
	apply_settings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Releases every action the pad was holding (so Mira doesn't keep running on
## a stale press), switches prompts back to the keyboard if it was the pad in
## use, and tells the level so it can pause.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	if device == pad_device or Input.get_connected_joypads().is_empty():
		using_pad = false
	for a in InputMap.get_actions():
		if not str(a).begins_with("ui_"):
			Input.action_release(a)
	for k in _axis_dir.keys():
		if int(k) / 64 == device:
			_axis_dir.erase(k)
	pad_disconnected.emit()


func _exit_tree() -> void:
	Art.clear_cache()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_menu_repeat(real)
	_mouse_still += real
	if not cursor_hidden and _mouse_still >= CURSOR_IDLE:
		set_cursor_hidden(true)


## The game has no mouse controls, so the cursor hides once a key or button is
## used or the mouse rests for CURSOR_IDLE seconds, and comes back when it moves.
const CURSOR_IDLE := 2.0
var cursor_hidden := false
var _mouse_still := 0.0


func set_cursor_hidden(h: bool) -> void:
	cursor_hidden = h
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if h else Input.MOUSE_MODE_VISIBLE


## Synthetic presses go straight to the viewport, not through Input, so the
## polled action state that gameplay reads is never touched.
func _menu_repeat(dt: float) -> void:
	for a in REPEAT_ACTIONS:
		if not Input.is_action_pressed(a):
			_held.erase(a)
			continue
		var t: float = _held.get(a, 0.0)
		var t2 := t + dt
		_held[a] = t2
		if t2 < REPEAT_DELAY:
			continue
		# number of repeat ticks crossed this frame (at most one per frame)
		if t < REPEAT_DELAY or floori((t2 - REPEAT_DELAY) / REPEAT_RATE) > floori((t - REPEAT_DELAY) / REPEAT_RATE):
			var ev := InputEventAction.new()
			ev.action = a
			ev.pressed = true
			if is_inside_tree():
				get_viewport().push_input(ev)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		_mouse_still = 0.0
		if cursor_hidden:
			set_cursor_hidden(false)
	elif not cursor_hidden and (ev is InputEventKey or ev is InputEventJoypadButton) and ev.pressed:
		set_cursor_hidden(true)
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
	var bs := pad_buttons_for(action)
	return "?" if bs.is_empty() else pad_button_name(int(bs[0]), pad_family(Input.get_joy_name(pad_device)))


static func pad_button_name(button: int, family: String) -> String:
	var names: Array = PAD_BUTTON_NAMES.get(button, [])
	return "?" if names.is_empty() else str(names[maxi(PAD_FAMILIES.find(family), 0)])


## Pad buttons per action: custom bindings override the defaults.
func pad_buttons_for(action: String) -> Array:
	var b: Dictionary = settings.get("pad_bindings", {}) if settings else {}
	if b.has(action):
		var out := []
		for k in b[action]:
			out.append(int(k))
		return out
	return DEFAULT_PAD.get(action, [])


## Bind a pad button to jump / dash / grab, swapping like rebind() does.
## Returns false for buttons that can't be bound (D-pad, Start, Back...).
func rebind_pad(action: String, button: int) -> bool:
	if not PAD_REBINDABLE.has(action) or not PAD_BUTTON_NAMES.has(button):
		return false
	var b: Dictionary = settings.get("pad_bindings", {})
	var old: Array = pad_buttons_for(action).duplicate()
	for other in PAD_REBINDABLE:
		if other == action:
			continue
		var bs: Array = pad_buttons_for(other).duplicate()
		if bs.has(button):
			bs.erase(button)
			if not old.is_empty() and not bs.has(old[0]):
				bs.insert(0, old[0])
			b[other] = bs
	b[action] = [button]
	settings.pad_bindings = b
	setup_input()
	return true


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


## Bindings are physical key positions (WASD stays WASD-shaped on AZERTY), so
## a key is named by what the player's layout prints on it: physical W reads
## "Z" on French keyboards, physical Z reads "Y" on German ones. Tests set
## `layout_stub` ({physical: printed keycode}) to stand in for a layout.
static var layout_stub = null


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
	var printed := k
	if layout_stub is Dictionary:
		printed = int(layout_stub.get(k, k))
	elif DisplayServer.get_name() != "headless":
		printed = DisplayServer.keyboard_get_keycode_from_physical(k)
	var s := OS.get_keycode_string(printed)
	# the pixel font is ASCII only; keyboards with other letters (Cyrillic,
	# Greek...) usually print the US name beside them
	if printed != k and (s == "" or not _ascii(s)):
		s = OS.get_keycode_string(k)
	return s


static func _ascii(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) < 32 or s.unicode_at(i) > 126:
			return false
	return true


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
	settings.pad_bindings = {}
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
	for a in PAD_REBINDABLE:
		_pad(a, pad_buttons_for(a))
	_pad("pause", [JOY_BUTTON_START])
	_pad("confirm", [JOY_BUTTON_A])
	_pad("back", [JOY_BUTTON_B])
	_pad("left", [JOY_BUTTON_DPAD_LEFT]); _pad("right", [JOY_BUTTON_DPAD_RIGHT])
	_pad("up", [JOY_BUTTON_DPAD_UP]); _pad("down", [JOY_BUTTON_DPAD_DOWN])
	_axis("left", JOY_AXIS_LEFT_X, -1.0); _axis("right", JOY_AXIS_LEFT_X, 1.0)
	_axis("up", JOY_AXIS_LEFT_Y, -1.0); _axis("down", JOY_AXIS_LEFT_Y, 1.0)
	_axis("grab", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis("grab", JOY_AXIS_TRIGGER_LEFT, 1.0)
	# A button held while it's rebound releases into its new action, so the
	# old one would stay "held" (a stuck dash fires on the next level start and
	# blocks every later dash). Start every action released.
	for a in defs:
		Input.action_release(a)


## Grab Mode "toggle": one press grabs until the next press (or a death or a
## new chapter, see release_grab()), instead of holding the button. Room
## changes keep it, so a climb can carry on into the room above.
var _grab_down := false
var grab_latched := false


func toggle_grab_mode() -> void:
	settings.grab_mode = "hold" if str(settings.get("grab_mode", "hold")) == "toggle" else "toggle"
	release_grab()


func release_grab() -> void:
	grab_latched = false


func read_input() -> int:
	var b := 0
	if Input.is_action_pressed("left"): b |= World.IN_LEFT
	if Input.is_action_pressed("right"): b |= World.IN_RIGHT
	if Input.is_action_pressed("up"): b |= World.IN_UP
	if Input.is_action_pressed("down"): b |= World.IN_DOWN
	if Input.is_action_pressed("jump"): b |= World.IN_JUMP
	if Input.is_action_pressed("dash"): b |= World.IN_DASH
	var grab := Input.is_action_pressed("grab")
	if str(settings.get("grab_mode", "hold")) == "toggle":
		if grab and not _grab_down:
			grab_latched = not grab_latched
		if grab_latched: b |= World.IN_GRAB
	elif grab:
		b |= World.IN_GRAB
	_grab_down = grab
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
		"reached": {},
	}


func load_save() -> void:
	data = default_save()
	if headless_test:
		return
	var parsed := read_json(SAVE_PATH)
	for k in parsed:
		data[k] = parsed[k]


func save() -> void:
	if headless_test:
		return
	write_json(SAVE_PATH, data)


func reset_save() -> void:
	data = default_save()
	if not headless_test:
		for ext in ["", ".bak"]:   # erased means erased: no backup of the old progress
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + ext))
	save()


# ---------------------------------------------------------------- safe files

## Set when a damaged save or settings file was set aside on load; the title
## screen shows it once.
var load_notice := ""


## Writes `d` so that a crash or a full disk mid-write can't destroy what was
## there: the new text goes to a temp file and is read back, the current file
## becomes `.bak`, then the temp file is renamed into place. Returns success.
static func write_json(path: String, d: Dictionary) -> bool:
	var text := JSON.stringify(d, "\t")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	if FileAccess.file_exists(path):
		# not every platform's rename replaces an existing file
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## Reads a JSON object written by write_json(). A missing main file (a crash
## between the two renames) falls back to `.bak`. A damaged one (empty,
## truncated, not an object) is renamed to `.corrupt`, never overwritten, and
## the backup is used. Returns {} when there is nothing usable.
func read_json(path: String) -> Dictionary:
	var main = _parse_file(path)
	if main is Dictionary:
		return main
	var damaged := FileAccess.file_exists(path)
	if damaged:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".corrupt"))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".corrupt"))
	var bak = _parse_file(path + ".bak")
	if damaged:
		var what := "save" if path == SAVE_PATH else "settings"
		load_notice = ("Your %s file was damaged. Restored the previous copy." % what) if bak is Dictionary \
			else ("Your %s file was damaged and set aside." % what)
		push_warning("%s was unreadable, moved to %s.corrupt" % [path, path])
	return bak if bak is Dictionary else {}


static func _parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


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


# ---------------------------------------------------------------- checkpoints

## A chapter's checkpoints: its main-path rooms in order. Secret rooms (ids
## ending in "s") are never offered, so the list gives nothing away.
static func checkpoint_rooms(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for rid in LevelDB.get_chapter(n).order:
		if not rid.ends_with("s"):
			out.append(rid)
	return out


func mark_reached(room_id: String) -> void:
	if not data.has("reached"):
		data.reached = {}
	data.reached[room_id] = true


## Checkpoints the player has reached. Saves from before rooms were recorded
## are backfilled: a completed chapter has them all; otherwise every room up
## to the Continue room, and any room where something was collected.
func reached_checkpoints(n: int) -> PackedStringArray:
	var rooms := checkpoint_rooms(n)
	if rooms.is_empty():
		return rooms
	var reached: Dictionary = data.get("reached", {})
	var all := bool(chapter_data(n).get("complete", false))
	var r: Dictionary = data.get("resume", {})
	var upto := -1
	if not r.is_empty() and int(r.get("chapter", -1)) == n:
		upto = Array(LevelDB.get_chapter(n).order).find(str(r.get("room", "")))
	var with_items := {}
	for cid in data.collected:
		with_items[str(cid).split(":")[0]] = true
	var out := PackedStringArray()
	var order := Array(LevelDB.get_chapter(n).order)
	for i in rooms.size():
		var rid := rooms[i]
		if i == 0 or all or reached.has(rid) or with_items.has(rid) or order.find(rid) <= upto:
			out.append(rid)
	return out


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
		"reduce_flashing": false, "route_ghost": false, "smooth_motion": "auto", "grab_mode": "hold",
		"air_dashes": "default", "ghost_goal": "exit",
	}


## Assist "Air Dashes" setting, in the order the menu steps through it.
const AIR_DASH_MODES := ["default", "two", "infinite"]


## World.AIR_DASHES_* for the current setting.
func air_dashes() -> int:
	match str(settings.get("air_dashes", "default")):
		"two": return World.AIR_DASHES_TWO
		"infinite": return World.AIR_DASHES_INFINITE
	return World.AIR_DASHES_DEFAULT


## Steps the setting by `d`, clamped, or wrapping when `wrap` (confirm cycles).
func step_air_dashes(d: int, wrap := false) -> void:
	var i := maxi(AIR_DASH_MODES.find(str(settings.get("air_dashes", "default"))), 0) + d
	settings.air_dashes = AIR_DASH_MODES[posmod(i, AIR_DASH_MODES.size()) if wrap else clampi(i, 0, AIR_DASH_MODES.size() - 1)]


## Assist "Route Ghost": off, or on with what she shows. "berries" runs the
## room's collectibles (and secret rooms) while any are missing. Stored as the
## old on/off flag plus a goal, so older settings files read as Exit.
const GHOST_MODES := ["off", "exit", "berries"]


func ghost_mode() -> String:
	if not bool(settings.get("route_ghost", false)):
		return "off"
	return "berries" if str(settings.get("ghost_goal", "exit")) == "berries" else "exit"


func step_ghost_mode(d: int, wrap := false) -> void:
	var i := GHOST_MODES.find(ghost_mode()) + d
	var m: String = GHOST_MODES[posmod(i, GHOST_MODES.size()) if wrap else clampi(i, 0, GHOST_MODES.size() - 1)]
	settings.route_ghost = m != "off"
	if m != "off":
		settings.ghost_goal = m


func load_settings() -> void:
	settings = default_settings()
	var parsed := read_json(SETTINGS_PATH)
	for k in parsed:
		settings[k] = parsed[k]


func save_settings() -> void:
	if headless_test:
		return
	write_json(SETTINGS_PATH, settings)


func apply_settings() -> void:
	if headless_test or DisplayServer.get_name() == "headless":
		return
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if not OS.has_feature("web"):
			_apply_window_size()
	Engine.time_scale = float(settings.game_speed)
	update_refresh_rate()
	apply_smooth_motion()
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
	if OS.has_feature("web"):
		return "Browser"   # the page sizes the canvas
	var s := int(settings.get("window_scale", 0))
	return "Auto %dx" % window_scale() if s <= 0 else "%dx" % window_scale()


## Steps through Auto, 2x .. the largest scale that fits (wrapping).
func step_window_scale(d: int) -> void:
	if OS.has_feature("web"):
		return
	var opts := [0]
	for k in range(2, max_window_scale() + 1):
		opts.append(k)
	var cur := int(settings.get("window_scale", 0))
	var i := opts.find(mini(cur, max_window_scale()) if cur > 0 else 0)
	settings.window_scale = opts[posmod(maxi(i, 0) + d, opts.size())]
	if settings.fullscreen:
		settings.fullscreen = false
	apply_settings()


## Mouse: a click at x on the Music or Sound Volume slider drawn at x0 sets
## that volume (see UIKit.slider_at; the caller refreshes the audio). False
## when it isn't one.
func set_volume_at(row: String, x: float, x0: float) -> bool:
	var key := "music" if row == "Music Volume" else ("sfx" if row == "Sound Volume" else "")
	var v := UIKit.slider_at(x, x0)
	if key == "" or v < 0.0:
		return false
	settings[key] = v
	save_settings()
	return true


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


# ---------------------------------------------------------------- smooth motion

const SMOOTH_MODES := ["auto", "on", "off"]
var refresh_rate := -1.0       # display refresh in Hz (-1 = unknown), see update_refresh_rate()


func update_refresh_rate() -> void:
	refresh_rate = -1.0
	if DisplayServer.get_name() != "headless":
		refresh_rate = DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())


## Whether to draw between the 60 Hz simulation steps. Auto does it only when
## steps can't land evenly on frames: a refresh rate that isn't a multiple of
## 60 Hz (144, 165, 75...) or a Game Speed below 100%. On 60/120/240 Hz screens
## at full speed every step already gets the same number of frames, so drawing
## the latest step as-is stays smooth and adds no latency.
static func smooth_wanted(mode: String, refresh: float, speed: float) -> bool:
	match mode:
		"on": return true
		"off": return false
	if speed < 0.999:
		return true
	if refresh <= 0.0:
		return false
	var k := refresh / 60.0
	return absf(k - roundf(k)) > 0.02 or k < 0.98


func smooth_motion() -> bool:
	return smooth_wanted(str(settings.get("smooth_motion", "auto")), refresh_rate, float(settings.get("game_speed", 1.0)))


func smooth_motion_label() -> String:
	var m := str(settings.get("smooth_motion", "auto"))
	if m == "auto":
		return "Auto (%s)" % ("On" if smooth_motion() else "Off")
	return m.capitalize()


func step_smooth_motion(d: int) -> void:
	var i := SMOOTH_MODES.find(str(settings.get("smooth_motion", "auto")))
	settings.smooth_motion = SMOOTH_MODES[posmod(maxi(i, 0) + d, SMOOTH_MODES.size())]
	apply_smooth_motion()


## Godot's jitter fix nudges ticks onto frame boundaries, which helps when the
## latest step is drawn as-is but fights interpolation, so it's only on then.
func apply_smooth_motion() -> void:
	Engine.physics_jitter_fix = 0.0 if smooth_motion() else 0.5


## Multiplier for full-screen flashes and the impact shimmer (accessibility).
func flash_scale() -> float:
	return 0.2 if bool(settings.get("reduce_flashing", false)) else 1.0


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
