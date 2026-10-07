class_name ControlsMenu
extends RefCounted
## The Controls panel (rebinding and Grab Mode), shared by the title's
## options and the pause menu's. The owner forwards input and draws it.

const ITEMS := ["jump", "dash", "grab", "Grab Mode", "up", "down", "left", "right", "Reset Defaults", "Back"]
const NAMES := {"jump": "Jump", "dash": "Dash", "grab": "Grab / Climb", "up": "Up", "down": "Down", "left": "Left", "right": "Right"}

const PANEL := Rect2(78, 14, 164, 16 + 10 * 12 + 12)   # ITEMS.size() rows

var sel := 0
var waiting_key := false:
	set(v):
		waiting_key = v
		Game.rebinding = v   # Game leaves F11 / Alt+Enter to the new binding
var k: Array = []


func _init() -> void:
	k.resize(ITEMS.size())
	k.fill(0.0)


func open() -> void:
	sel = 0
	waiting_key = false


func process(delta: float) -> void:
	for i in k.size():
		k[i] = move_toward(k[i], 1.0 if i == sel else 0.0, delta * 8.0)


## While waiting for a key or button: takes the press, binds it (or cancels on
## Esc / Start) and returns true. Call before actions are matched, since the
## new key may already mean something else.
func capture(ev: InputEvent) -> bool:
	if not waiting_key:
		return false
	if ev is InputEventJoypadButton and ev.pressed:
		# pad buttons rebind Jump / Dash / Grab; Start cancels
		var btn: int = (ev as InputEventJoypadButton).button_index
		if btn == JOY_BUTTON_START:
			waiting_key = false
			Sfx.play("menu_move")
		elif Game.rebind_pad(ITEMS[sel], btn):
			waiting_key = false
			Game.save_settings()
			Sfx.play("menu_select")
		return true   # anything else can't be bound here: keep waiting
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return ev is InputEventKey or ev is InputEventJoypadButton   # releases while waiting
	var key: int = (ev as InputEventKey).physical_keycode
	waiting_key = false
	if key == KEY_ESCAPE:
		Sfx.play("menu_move")
		return true
	Game.rebind(ITEMS[sel], key)
	Game.save_settings()
	Sfx.play("menu_select")
	return true


## Menu navigation. Returns true when the panel should close.
func navigate(ev: InputEvent) -> bool:
	if waiting_key:
		return false
	if ev.is_action_pressed("up"):
		sel = (sel + ITEMS.size() - 1) % ITEMS.size()
		Sfx.play("menu_move")
	elif ev.is_action_pressed("down"):
		sel = (sel + 1) % ITEMS.size()
		Sfx.play("menu_move")
	elif ITEMS[sel] == "Grab Mode" and (ev.is_action_pressed("confirm") or ev.is_action_pressed("left") or ev.is_action_pressed("right")):
		Sfx.play("menu_select")
		Game.toggle_grab_mode()
		Game.save_settings()
	elif ev.is_action_pressed("confirm"):
		Sfx.play("menu_select")
		match ITEMS[sel]:
			"Reset Defaults":
				Game.reset_bindings()
				Game.save_settings()
			"Back":
				return true
			_:
				waiting_key = true
	elif ev.is_action_pressed("back"):
		return true
	return false


## Mouse: pointing at a row selects it, a left click confirms it (starting a
## rebind) and a right click goes back, or cancels a rebind (mouse buttons
## can't be bound). Returns the action for navigate(), or null when the event
## is used up here.
func mouse(ev: InputEventMouse) -> InputEvent:
	var a := UIKit.click_action(ev)
	if waiting_key:
		if a and a.action == "back":
			waiting_key = false
			Sfx.play("menu_move")
		return null
	var i := UIKit.row_at(ev.position, PANEL.position.x + 12, PANEL.position.y + 10, 140, 12, ITEMS.size())
	if i >= 0 and i != sel:
		sel = i
		Sfx.play("menu_move")
	if a and a.action == "confirm" and i < 0:
		return null   # a click outside the rows does nothing
	return a


## Prompt pairs for the bottom of the screen.
func hints() -> Array:
	if waiting_key:
		return [["Start" if Game.using_pad else "Esc", "Cancel"]]
	return [[Game.move_label(), "Change"], [Game.key_label("jump"), "Select"], [Game.key_label("dash"), "Back"]]


func draw(ci: CanvasItem, time: float) -> void:
	ci.draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.45))
	var r := PANEL
	UIKit.panel(ci, r)
	UIKit.panel_title(ci, r, "CONTROLS")
	for i in ITEMS.size():
		var y := r.position.y + 10 + i * 12
		var id: String = ITEMS[i]
		UIKit.menu_row(ci, r.position.x + 12, y, 140, NAMES.get(id, id), k[i], time)
		if id == "Grab Mode":
			var v := "Toggle" if str(Game.settings.get("grab_mode", "hold")) == "toggle" else "Hold"
			PixelText.draw_outlined(ci, Vector2(r.end.x - 10 - PixelText.width(v), y), v, UIKit.GOLD, UIKit.INK)
		elif NAMES.has(id):
			var lbl := "..." if (waiting_key and i == sel) else Game.kb_label(id)
			var w := maxf(PixelText.width(lbl) + 6.0, 9.0)
			if waiting_key and i == sel:
				var prompt := "key or button" if Game.PAD_REBINDABLE.has(id) else "press a key"
				PixelText.draw_outlined(ci, Vector2(r.end.x - 10 - PixelText.width(prompt), y), prompt, Color(UIKit.GOLD, 0.6 + 0.4 * sin(time * 8.0)), UIKit.INK)
			else:
				var kx := r.end.x - 10 - w
				UIKit.keycap(ci, Vector2(kx, y), lbl)
				if Game.PAD_REBINDABLE.has(id):
					var pl := Game.pad_label(id)
					PixelText.draw_outlined(ci, Vector2(kx - 6 - PixelText.width(pl), y), pl, UIKit.GOLD, UIKit.INK)
	var foot := "Gold: pad button"
	PixelText.draw_outlined(ci, Vector2(160 - PixelText.width(foot) / 2.0, r.end.y - 11), foot, Color(UIKit.GOLD, 0.8), UIKit.INK)
