extends Node
## godot --path . --rendering-method mobile res://tools/scene_shot.tscn -- <scene> <out.png> <frames> [action@frame ...]
var f := 0
var target := 60
var out := ""
var presses := {}
var node: Node

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.headless_test = true
	out = a[1]
	target = int(a[2])
	for i in range(3, a.size()):
		var p := a[i].split("@")
		presses[int(p[1])] = p[0]
	node = load(a[0]).instantiate()
	add_child(node)

func _process(_d: float) -> void:
	f += 1
	if presses.has(f):
		var ev := InputEventAction.new()
		ev.action = presses[f]
		ev.pressed = true
		Input.parse_input_event(ev)
		var ev2 := InputEventAction.new()
		ev2.action = presses[f]
		ev2.pressed = false
		Input.parse_input_event.call_deferred(ev2)
	if f == target:
		var img := get_viewport().get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_NEAREST)
		img.save_png(out)
		get_tree().quit()
