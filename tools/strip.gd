extends Node
## Plays a recorded solution in the real game and saves a contact sheet.
## godot --path . --rendering-method mobile res://tools/strip.tscn -- <chapter> <room> <solution.json> <out.png> [every=20] [cols=4]
var frames := 0
var level
var shots: Array[Image] = []
var every := 20
var cols := 4
var out := ""
var total := 0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.headless_test = true
	Game.data = Game.default_save()
	for k in Story.all_ids():
		Game.mark_seen(k)
	Game.pending_chapter = int(a[0])
	Game.pending_room = a[1]
	var sol: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[2]))
	out = a[3]
	if a.size() > 4: every = int(a[4])
	if a.size() > 5: cols = int(a[5])
	level = load("res://scenes/level.tscn").instantiate()
	level.replay = Solver.decode(sol.solution)
	total = level.replay.size()
	add_child(level)

func _process(_d: float) -> void:
	RenderingServer.force_draw(false)
	frames += 1
	if level.mode == "dialogue":
		level.dialogue.skip_all()
	if frames > 20 and frames % every == 0:
		var img := get_viewport().get_texture().get_image()
		shots.append(img)
	if level.replay_pos >= total + 10 or level.mode == "transition" or level.mode == "dead" or frames > 3000:
		_save()

func _save() -> void:
	set_process(false)
	var n := shots.size()
	var rows := int(ceil(n / float(cols)))
	var sheet := Image.create(320 * cols, 180 * rows, false, Image.FORMAT_RGBA8)
	for i in n:
		var im := shots[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, 320, 180), Vector2i((i % cols) * 320, (i / cols) * 180))
	sheet.save_png(out)
	get_tree().quit()
