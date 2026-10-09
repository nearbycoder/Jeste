class_name ControlsMenu
extends RefCounted
## The Controls panel (rebinding and Grab Mode), shared by the title's
## options and the pause menu's. The owner forwards input and draws it.

const ITEMS := ["jump", "dash", "grab", "Grab Mode", "up", "down", "left", "right", "Stick Deadzone", "Reset Defaults", "Back"]
const NAMES := {"jump": "Jump", "dash": "Dash", "grab": "Grab / Climb", "up": "Up", "down": "Down", "left": "Left", "right": "Right"}

const PANEL := Rect2(78, 8, 164, 10 + 11 * 12 + 13)   # ITEMS.size() rows and the footer
const DIAL_R := 18.0              # the stick dial left of the panel (Stick Deadzone)
const DEADZONE_FOOT := "Raise it if Mira drifts"

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
	if ev is InputEventAction:
		# the on-screen buttons (Touch) can't be bound; Dash / Pause cancels
		if ev.pressed and (ev.action == "back" or ev.action == "pause"):
			waiting_key = false
			Sfx.back()
		return true
	if ev is InputEventJoypadButton and ev.pressed:
		# pad buttons rebind Jump / Dash / Grab; Start cancels
		var btn: int = (ev as InputEventJoypadButton).button_index
		if btn == JOY_BUTTON_START:
			waiting_key = false
			Sfx.back()
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
		Sfx.back()
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
	elif ITEMS[sel] == "Stick Deadzone" and (ev.is_action_pressed("confirm") or ev.is_action_pressed("left") or ev.is_action_pressed("right")):
		Sfx.play("menu_move")
		Game.step_stick_deadzone(-1 if ev.is_action_pressed("left") else 1, ev.is_action_pressed("confirm"))
		Game.save_settings()
	elif ev.is_action_pressed("confirm"):
		if ITEMS[sel] == "Back":
			Sfx.back()
			return true
		Sfx.play("menu_select")
		match ITEMS[sel]:
			"Reset Defaults":
				Game.reset_bindings()
				Game.save_settings()
			_:
				waiting_key = true
	elif ev.is_action_pressed("back"):
		Sfx.back()
		return true
	return false


## Mouse: pointing at a row selects it, a left click confirms it (starting a
## rebind) and a right click goes back, or cancels a rebind (mouse buttons
## can't be bound). The wheel moves the selection, and does nothing while
## waiting for a key. Returns the action for navigate(), or null when the
## event is used up here.
func mouse(ev: InputEventMouse) -> InputEvent:
	var a := UIKit.click_action(ev)
	if waiting_key:
		if a and a.action == "back":
			waiting_key = false
			Sfx.back()
		return null
	var i := UIKit.row_at(ev.position, PANEL.position.x + 12, PANEL.position.y + 10, 140, 12, ITEMS.size())
	if UIKit.is_wheel(ev):
		if i >= 0 and UIKit.WHEEL_VALUE_ROWS.has(ITEMS[i]):
			if i != sel:
				sel = i
				Sfx.play("menu_move")
			return UIKit.wheel_action(ev, "right", "left")   # over the deadzone it steps the value
		return UIKit.wheel_action(ev, "up", "down")
	if i >= 0 and i != sel:
		sel = i
		Sfx.play("menu_move")
	if a and a.action == "confirm" and i < 0:
		return null   # a click outside the rows does nothing
	return a


## Prompt pairs for the bottom of the screen.
func hints() -> Array:
	if waiting_key:
		return [[Game.key_label("dash") if Game.using_touch else ("Start" if Game.using_pad else "Esc"), "Cancel"]]
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
		if id == "Grab Mode" or id == "Stick Deadzone":
			var v := value_label(id)
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
	var foot := footer()
	PixelText.draw_outlined(ci, Vector2(160 - PixelText.width(foot) / 2.0, r.end.y - 11), foot, Color(UIKit.GOLD, 0.8), UIKit.INK)
	if ITEMS[sel] == "Stick Deadzone":
		draw_dial(ci, dial_center())


func value_label(id: String) -> String:
	if id == "Grab Mode":
		return "Toggle" if str(Game.settings.get("grab_mode", "hold")) == "toggle" else "Hold"
	return "%d%%" % roundi(Game.stick_deadzone() * 100.0)


func footer() -> String:
	return DEADZONE_FOOT if ITEMS[sel] == "Stick Deadzone" else "Gold: pad button"


## Beside the Stick Deadzone row, left of the panel (clear of Mira and the
## campfire on the title screen).
func dial_center() -> Vector2:
	return Vector2(roundf(PANEL.position.x / 2.0), PANEL.position.y + 10 + ITEMS.find("Stick Deadzone") * 12 + 4)


## The stick dial: the stick's reach, the deadzone (darker, inside), the
## eight directions, and a dot where the stick is now, lit with the
## direction it gives once it's past the deadzone. So a stick that drifts
## shows where it rests, and how far to raise the deadzone.
func draw_dial(ci: CanvasItem, c: Vector2) -> void:
	var dz := Game.stick_deadzone()
	ci.draw_circle(c, DIAL_R + 2.0, UIKit.INK)
	ci.draw_circle(c, DIAL_R + 1.0, UIKit.GOLD_DK)
	ci.draw_circle(c, DIAL_R, Color(0.1, 0.07, 0.16))
	var pad := Game.stick_pad()
	var v := Game.stick_vector(pad) if pad >= 0 else Vector2.ZERO
	var dirs := Game.stick_dirs(v)
	for i in 8:
		var a := i * PI / 4.0
		var lit := dirs != 0 and posmod(roundi(v.angle() / (PI / 4.0)), 8) == i
		ci.draw_line(c + Vector2.from_angle(a) * (DIAL_R * dz + 1.0), c + Vector2.from_angle(a) * (DIAL_R - 1.0),
			Color(UIKit.GOLD, 0.9) if lit else Color(UIKit.MUTED, 0.25), 1.0)
	ci.draw_circle(c, DIAL_R * dz, Color(0.22, 0.17, 0.3))
	ci.draw_arc(c, DIAL_R * dz, 0.0, TAU, 24, Color(UIKit.MUTED, 0.6), 1.0)
	if pad < 0:
		PixelText.draw_centered_outlined(ci, c.x, c.y + DIAL_R + 5.0, "No pad", Color(UIKit.MUTED, 0.9), UIKit.INK)
		return
	var p := c + v.limit_length(1.1) * DIAL_R
	ci.draw_circle(p, 2.5, UIKit.INK)
	ci.draw_circle(p, 1.5, UIKit.GOLD if dirs != 0 else UIKit.CREAM)
	PixelText.draw_centered_outlined(ci, c.x, c.y + DIAL_R + 5.0, "%d%%" % roundi(v.length() * 100.0),
		Color(UIKit.GOLD if dirs != 0 else UIKit.MUTED, 0.9), UIKit.INK)
