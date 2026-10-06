extends Node
## Smooth Motion probe: replays a room's Route Ghost route through the real
## Level scene and logs, every rendered frame, where Mira is drawn and where
## the camera is. Run with --fixed-fps to stand in for a display's refresh rate:
## godot --headless --path . --fixed-fps 144 res://tools/motion_probe.tscn -- <chapter> <room> <speed> <on|off> <out.csv> [crop_dir]
## (crop_dir needs a display: saves a fixed 96x48 crop near Mira per frame,
## optionally only for frames CROP_FROM..CROP_TO)
var level
var out := ""
var rows: PackedStringArray = ["frame,ticks,steps,alpha,draw_x,draw_y,sim_x,sim_y,vx,vy,cam_x,cam_y"]
var frame := 0
var ticks := 0
var crop_dir := ""
var crop_rect := Rect2i()


func _ready() -> void:
	process_priority = 100        # after the level has placed everything this frame
	var a := OS.get_cmdline_user_args()
	Game.headless_test = true
	Game.data = Game.default_save()
	Game.settings.smooth_motion = a[3]
	Game.settings.game_speed = float(a[2])
	Engine.time_scale = float(a[2])
	Game.apply_smooth_motion()
	out = a[4]
	crop_dir = a[5] if a.size() > 5 else ""
	Game.pending_chapter = int(a[0])
	Game.pending_room = a[1]
	level = load("res://scenes/level.tscn").instantiate()
	var h: Dictionary = Level._hint(a[1], 0, a[0])
	level.replay = Solver.decode(str(h.inputs))
	add_child(level)


func _physics_process(_d: float) -> void:
	ticks += 1


func _process(_d: float) -> void:
	frame += 1
	if level.mode == "dialogue" and frame % 20 == 0:
		var ev := InputEventAction.new()
		ev.action = "confirm"
		ev.pressed = true
		level.dialogue.handle_input(ev)
	var w: World = level.world
	var f: Vector2 = level.player_view._feet()
	rows.append("%d,%d,%d,%.3f,%.3f,%.3f,%d,%d,%.1f,%.1f,%.0f,%.0f" % [frame, ticks, w.frame, w.view_alpha, f.x, f.y, w.x + 4, w.y + 11, w.vx, w.vy, level.camera.position.x, level.camera.position.y])
	var from := int(OS.get_environment("CROP_FROM")) if OS.has_environment("CROP_FROM") else 30
	var to := int(OS.get_environment("CROP_TO")) if OS.has_environment("CROP_TO") else 100000
	if crop_dir != "" and frame >= from and frame <= to:
		RenderingServer.force_draw(false)
		var img := get_viewport().get_texture().get_image()
		var sp: Vector2 = get_viewport().get_canvas_transform() * (f + level.player_view.position)
		if crop_rect.size == Vector2i.ZERO:   # fixed window, placed on the first captured frame
			crop_rect = Rect2i(clampi(int(sp.x) - 16, 0, img.get_width() - 96), clampi(int(sp.y) - 36, 0, img.get_height() - 48), 96, 48)
		img.get_region(crop_rect).save_png("%s/f%04d.png" % [crop_dir, frame])
	if level.replay_pos >= level.replay.size() or level.mode == "transition" or frame > 3000:
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string("\n".join(rows) + "\n")
		fa.close()
		get_tree().quit()
