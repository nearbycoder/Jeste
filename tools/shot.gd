extends Node
## Screenshot helper (needs a display):
## godot --path . res://tools/shot.tscn -- <chapter> <room> <out.png> <frames> [rle inputs] [spawn]
var frames := 0
var target := 60
var out := ""
var level

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.headless_test = true
	Game.data = Game.default_save()
	Game.pending_chapter = int(a[0])
	Game.pending_room = a[1]
	out = a[2]
	target = int(a[3])
	level = load("res://scenes/level.tscn").instantiate()
	if a.size() > 4 and a[4] != "-":
		level.replay = Solver.decode(a[4])
	add_child(level)

var perf_t := 0.0
var perf_n := 0
var perf_max := 0.0

func _process(_d: float) -> void:
	if OS.get_environment("PERF") == "":
		RenderingServer.force_draw(false)
	frames += 1
	if OS.get_environment("PERF") != "" and frames > 60:
		var pt := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		perf_t += pt
		perf_n += 1
		perf_max = maxf(perf_max, pt)
		if frames == target - 1:
			print("PERF process avg %.2f ms, max %.2f ms, draw calls %d, objects %d" % [perf_t / perf_n, perf_max, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if level.mode == "dialogue" and frames % 20 == 0:
		var ev := InputEventAction.new()
		ev.action = "confirm"
		ev.pressed = true
		level.dialogue.handle_input(ev)
	# SHOT_CALL="frame:method[,frame:method]" calls level methods (debug captures)
	for c in OS.get_environment("SHOT_CALL").split(",", false):
		var p := c.split(":")
		if int(p[0]) == frames:
			if p[1] == "pause":
				level.paused = true
				level.hud.open_pause()
			elif p[1] == "berry":
				level.hud.show_berry(3, 12)
			elif p[1] == "down":
				var ev := InputEventAction.new()
				ev.action = "down"
				ev.pressed = true
				level.hud.handle_menu_input(ev)
			elif p[1] == "confirm":
				var ev := InputEventAction.new()
				ev.action = "confirm"
				ev.pressed = true
				level.hud.handle_menu_input(ev)
			else:
				level.call(p[1])
	if frames == target:
		var img := get_viewport().get_texture().get_image()
		if OS.get_cmdline_user_args().has("zoom"):
			var sp: Vector2 = get_viewport().get_canvas_transform() * (level.world.player_center() + level.player_view.position)
			var r := Rect2i(clampi(int(sp.x) - 40, 0, 240), clampi(int(sp.y) - 28, 0, 124), 80, 56)
			img = img.get_region(r)
			img.resize(640, 448, Image.INTERPOLATE_NEAREST)
		else:
			img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		img.save_png(out)
		get_tree().quit()
