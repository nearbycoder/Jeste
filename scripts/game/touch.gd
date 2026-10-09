class_name TouchControls
extends Node
## Autoload "Touch": the on-screen controls of the browser version on phones
## and tablets. The page (tools/web/shell.html) draws and tracks them; this
## turns what it reports into the game's actions, so gameplay polls them and
## menus get the same presses a key would send. Off the web it does nothing.
##
## The page shows the controls only on touch-first devices (or after a real
## touch) and hides them when a key, mouse or gamepad is used; it tells the
## game through `mode`, and prompts then name the on-screen buttons
## (Game.using_touch).

## On-screen button -> the actions it presses, as its keyboard key would:
## Jump also confirms in menus and Dash goes back, like C and X.
const BUTTONS := {
	"jump": ["jump", "confirm"], "dash": ["dash", "back"], "grab": ["grab"], "pause": ["pause"],
	"up": ["up"], "down": ["down"], "left": ["left"], "right": ["right"],
}
## A tap shorter than this many physics ticks is held until then, so the
## 60 Hz simulation always sees it.
const MIN_TICKS := 2

var _js = null                  # window.jesteTouch
var _cb = null                  # keeps the JavaScript callback alive
var _held := {}                 # button -> physics tick it went down
var _release := {}              # button -> true: let go, waiting out MIN_TICKS
var _ticks := 0
var _counts := {}               # button -> presses (mirrored to the page for the checks)
var _shown := ""                # last state mirrored to the page
var _grab_shown := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		return
	_js = JavaScriptBridge.get_interface("jesteTouch")
	if _js == null:
		return
	_cb = JavaScriptBridge.create_callback(_on_page)
	_js.attach(_cb)


## True on a phone or tablet before any touch: the page's guess from the
## pointer media queries (for defaults chosen before the controls show).
static func touch_first() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.jesteTouch && window.jesteTouch.touchFirst)", true))


## The page after a crash: it reloaded a tab the browser had closed while the
## game ran (most likely out of memory), so this session starts light.
static func recovering() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.jesteTouch && window.jesteTouch.recovering)", true))


## From the page: ["down"|"up", button], ["mode", "1"|"0"], ["blocked", "1"|"0"].
func _on_page(args: Array) -> void:
	if args.size() < 2:
		return
	var op := str(args[0])
	var arg := str(args[1])
	match op:
		"down":
			if BUTTONS.has(arg) and not _held.has(arg):
				_held[arg] = _ticks
				_release.erase(arg)
				_counts[arg] = int(_counts.get(arg, 0)) + 1
				_send(arg, true)
		"up":
			if _held.has(arg):
				if _ticks - int(_held[arg]) >= MIN_TICKS:
					_let_go(arg)
				else:
					_release[arg] = true
		"mode":
			Game.using_touch = arg == "1"
			if Game.using_touch:
				Game.using_pad = false
			else:
				release_all()
		"blocked":
			# the page asks to turn the phone: let go and pause the climb
			release_all()
			if arg == "1":
				var s := get_tree().current_scene if is_inside_tree() else null
				if s and s.has_method("auto_pause"):
					s.auto_pause()


func _send(button: String, pressed: bool) -> void:
	for a in BUTTONS[button]:
		var ev := InputEventAction.new()
		ev.action = a
		ev.pressed = pressed
		ev.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)


func _let_go(button: String) -> void:
	_held.erase(button)
	_release.erase(button)
	_send(button, false)


func release_all() -> void:
	for b in _held.keys():
		_let_go(b)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	for b in _release.keys():
		if _ticks - int(_held.get(b, 0)) >= MIN_TICKS:
			_let_go(b)


func _process(_delta: float) -> void:
	if _js == null:
		return
	# Grab Mode Toggle: the Grab button stays lit while the grab is latched.
	var g := "%s%s" % [Game.settings.get("grab_mode", "hold"), Game.grab_latched]
	if g != _grab_shown:
		_grab_shown = g
		_js.grabState(str(Game.settings.get("grab_mode", "hold")), Game.grab_latched)
	if not Game.using_touch and _shown == "":
		return
	# what the game holds from touch, for tools/check-mobile.mjs
	var held := []
	for a in ["left", "right", "up", "down", "jump", "dash", "grab", "pause"]:
		if Input.is_action_pressed(a):
			held.append(a)
	var s := "%s|%s" % [",".join(held), JSON.stringify(_counts)]
	if s != _shown:
		_shown = s
		Game.web_status({"touch_held": ",".join(held), "touch_count": JSON.stringify(_counts)})


## A gamepad takes over: the page hides the controls (keys and the mouse it
## sees itself).
func _input(ev: InputEvent) -> void:
	if not Game.using_touch or _js == null:
		return
	if (ev is InputEventJoypadButton and ev.pressed) or (ev is InputEventJoypadMotion and absf((ev as InputEventJoypadMotion).axis_value) > 0.5):
		_js.hide("gamepad")
