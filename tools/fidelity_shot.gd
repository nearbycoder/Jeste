extends Node
## Same-frame captures and frame times for Options > Graphics (needs a display):
## godot --path . --fixed-fps 60 res://tools/fidelity_shot.tscn -- <chapter|title> <room> <solution.json|-> <frame> <fidelity 0-3> <out.png>
## godot --path . --disable-vsync res://tools/fidelity_shot.tscn -- <chapter|title> <room> <solution.json|-> <frames> <fidelity 0-3> bench [scale] [pause]
## The RNG is seeded and, with --fixed-fps, every frame advances the same
## amount, so two runs differ only by the setting. A solution file's inputs
## are replayed (looping) so Mira moves; the shot is taken at <frame>,
## scaled 3x. Bench mode renders <frames> frames as fast as it can in a
## window <scale> times the game's size (default 4) and prints the CPU frame
## time and the GPU's measured render time (mean, 95th and 99th percentile).
## "pause" opens the pause menu first (shot or bench).
var f := 0
var a: PackedStringArray
var node: Node
var level
var target := 150
var bench := false
var pause_at := -1
var inputs := PackedByteArray()
var deltas := PackedFloat64Array()
var gpu := PackedFloat64Array()
var last_us := 0


func _ready() -> void:
	seed(12345)
	a = OS.get_cmdline_user_args()
	Game.headless_test = true
	Game.data = Game.default_save()
	Game.data.unlocked = 8
	Game.settings = Game.default_settings()
	Game.settings["fidelity"] = int(a[4])
	Game.setup_input()
	target = int(a[3])
	bench = a.size() > 5 and a[5] == "bench"
	if a.has("pause"):
		pause_at = 90
	if a[2] != "-":
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[2]))
		inputs = Solver.decode(str(d.solution))
	if a[0] == "title":
		node = load("res://scenes/main.tscn").instantiate()
	else:
		Game.pending_chapter = int(a[0])
		Game.pending_room = a[1]
		level = load("res://scenes/level.tscn").instantiate()
		if not inputs.is_empty():
			level.replay = inputs
		node = level
	add_child(node)
	if bench:
		var k := int(a[6]) if a.size() > 6 and a[6].is_valid_int() else 4
		DisplayServer.window_set_size(Vector2i(320, 180) * k)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(_d: float) -> void:
	if not bench:
		RenderingServer.force_draw(false)
	f += 1
	if level and level.mode == "dialogue" and f % 20 == 0:
		level.dialogue.handle_input(UIKit.press("confirm"))
	if level and not inputs.is_empty() and level.replay_pos >= inputs.size():
		level.replay_pos = 0   # loop the route
	if f == pause_at and level:
		level.paused = true
		level.hud.open_pause()
	if bench:
		var now := Time.get_ticks_usec()
		if f > 120:   # warm-up: shaders, room bakes, the title's intro
			deltas.append((now - last_us) / 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		last_us = now
		if f == 120 + target:
			print("BENCH fidelity %s %s/%s: %s" % [a[4], a[0], a[1], _stats()])
			get_tree().quit()
		return
	if f == target:
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		img.save_png(a[5])
		print("SHOT ", a[5])
		get_tree().quit()


func _stats() -> String:
	var ft := Array(deltas)
	var gt := Array(gpu)
	ft.sort()
	gt.sort()
	var mean := func(arr: Array) -> float: return arr.reduce(func(s, x): return s + x, 0.0) / arr.size()
	var pct := func(arr: Array, p: float) -> float: return arr[mini(int(arr.size() * p), arr.size() - 1)]
	var win := DisplayServer.window_get_size()
	return "frame mean %.3f ms p95 %.3f p99 %.3f (%.0f fps); gpu mean %.3f ms p95 %.3f p99 %.3f; %d frames at %dx%d" % [
		mean.call(ft), pct.call(ft, 0.95), pct.call(ft, 0.99), 1000.0 / mean.call(ft),
		mean.call(gt), pct.call(gt, 0.95), pct.call(gt, 0.99), ft.size(), win.x, win.y]
