extends Node
## Gameplay demo / trailer director. Plays the title screen, then segments of
## the real game driven by the solver-proven routes (tests/routes.json), with
## cutscenes auto-advancing at reading pace.
##
## Record a video with Godot's Movie Maker:
##   godot --path . --rendering-method mobile --resolution 1280x720 \
##         --write-movie /tmp/jeste.avi --fixed-fps 60 res://tools/demo.tscn

# Each segment: chapter, first/last route chunk, cutscenes to show (others are skipped).
const PLAYLIST := [
	{"type": "title", "secs": 7.5},
	{"type": "select", "secs": 9.0},
	{"type": "play", "ch": 0, "from": 0, "to": -1, "story": ["pro_arrive", "pro_magpie"]},
	{"type": "play", "ch": 1, "from": 0, "to": -1, "story": ["ch1_tobi"]},
	{"type": "play", "ch": 2, "from": 0, "to": 3, "story": ["ch2_dream"]},
	{"type": "play", "ch": 2, "from": 6, "to": -1, "story": ["ch2_mirror"]},
	{"type": "play", "ch": 3, "from": 0, "to": 6, "story": ["ch3_arrive"]},
	{"type": "play", "ch": 4, "from": 0, "to": 4, "story": []},
	{"type": "play", "ch": 5, "from": 0, "to": 4, "story": ["ch5_arrive"]},
	{"type": "play", "ch": 6, "from": 0, "to": 3, "story": []},
	{"type": "play", "ch": 6, "from": 7, "to": -1, "story": ["ch6_together"]},
	{"type": "play", "ch": 7, "from": 0, "to": 4, "story": ["ch7_start"]},
	{"type": "play", "ch": 7, "from": 7, "to": -1, "story": ["ch7_end"]},
	{"type": "credits", "secs": 17.0},
]

var routes: Dictionary
var seg := -1
var node: Node
var level
var t := 0.0
var total_inputs := 0
var done_t := 0.0
var line_t := 0.0
var allowed: Array = []
var fade_layer: CanvasLayer
var fade: ColorRect
var fading := 0.0      # >0 fading out to next segment


func _ready() -> void:
	Game.headless_test = true
	Game.data = Game.default_save()
	Game.settings.screen_shake = true
	routes = JSON.parse_string(FileAccess.get_file_as_string("res://tests/routes.json"))
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		seg = int(a[0]) - 1
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0.03, 0.02, 0.05, 1.0)
	fade.size = Vector2(320, 180)
	fade_layer.add_child(fade)
	_next()


func _next() -> void:
	if node:
		node.queue_free()
		node = null
		level = null
	seg += 1
	if seg >= PLAYLIST.size():
		get_tree().quit()
		return
	t = 0.0
	done_t = 0.0
	line_t = 0.0
	var s: Dictionary = PLAYLIST[seg]
	match s.type:
		"title":
			node = load("res://scenes/main.tscn").instantiate()
		"credits":
			node = load("res://scenes/credits.tscn").instantiate()
		"select":
			Game.data = Game.default_save()
			Game.data.unlocked = 8
			Game.data.resume = {"chapter": 0, "room": "0-01"}
			for i in 8:
				Game.data.chapters[str(i)] = {"complete": true, "deaths": [0, 23, 41, 57, 66, 38, 72, 104][i], "best_time": [61.2, 402.5, 388.1, 455.0, 371.9, 329.4, 410.7, 512.3][i], "golden": i % 3 == 1}
			node = load("res://scenes/chapter_select.tscn").instantiate()
		"play":
			_start_play(s)
	add_child(node)
	move_child(fade_layer, -1)
	if s.type == "play" and int(s.from) > 0:
		var ch := LevelDB.get_chapter(int(s.ch))
		level.hud.show_title(ch.name, Game.CHAPTER_TITLES[int(s.ch)], 3.0)


func _start_play(s: Dictionary) -> void:
	var chunks: Array = routes[str(int(s.ch))]
	var a: int = s.from
	var b: int = chunks.size() if int(s.to) < 0 else int(s.to)
	var first: Dictionary = chunks[a]
	# task id: "<ch>_<room>_s<spawn>_..."
	var parts: PackedStringArray = str(first.task).split("_")
	Game.data = Game.default_save()
	Game.pending_chapter = int(s.ch)
	Game.pending_room = str(first.room) if a > 0 else ""
	Game.pending_spawn = int(parts[2].substr(1))
	allowed = s.story
	var inputs := PackedByteArray()
	for i in range(a, b):
		inputs.append_array(Solver.decode(chunks[i].inputs))
	level = load("res://scenes/level.tscn").instantiate()
	level.replay = inputs
	total_inputs = inputs.size()
	node = level


func _process(delta: float) -> void:
	# Keep rendering even if the compositor suspends a hidden window, so the
	# Movie Maker never captures stale frames.
	RenderingServer.force_draw(false)
	t += delta
	# fades
	if fading > 0.0:
		fading -= delta
		fade.color.a = clampf(1.0 - fading / 0.5, 0.0, 1.0)
		if fading <= 0.0:
			_next()
		return
	fade.color.a = maxf(fade.color.a - delta * 2.5, 0.0)
	var s: Dictionary = PLAYLIST[seg]
	match s.type:
		"title", "credits", "select":
			if s.type == "select" and node:
				# browse the postcards: start at the prologue and step right
				var step := int((t - 0.8) / 0.9)
				if t > 0.8 and step < 8 and node.sel != step + 1 and node.sel == step:
					var ev := InputEventAction.new()
					ev.action = "right"
					ev.pressed = true
					node._unhandled_input(ev)
			if s.type == "credits" and node and t > 7.0 and not node.ended and node.scroll < node._total() - 140.0:
				node.scroll = node._total() - 140.0
			if t >= float(s.secs):
				fading = 0.5
		"play":
			_drive_level(delta)


func _drive_level(delta: float) -> void:
	if level == null:
		return
	# Cutscenes: show allowed ones at reading pace, skip the rest.
	if level.mode == "dialogue" and level.dialogue.active:
		var d = level.dialogue
		if not (d.script_id in allowed):
			d.skip_all()
			if level.after_dialogue == "results":
				pass
		elif not d.cur.is_empty() and d.shown >= d._total_chars():
			line_t += delta
			var hold := 0.7 + str(d.cur.text).length() / 32.0
			if line_t >= hold:
				line_t = 0.0
				Sfx.play("text_next")
				d._next()
	# Chapter results: linger, then move on.
	if level.hud.results:
		done_t += delta
		if done_t > 3.0:
			fading = 0.5
		return
	# Partial segment: once the route is used up and the transition is over.
	if level.replay_pos >= total_inputs and level.mode == "play":
		done_t += delta
		if done_t > 0.6:
			fading = 0.5
	elif t > 600.0:
		fading = 0.5
