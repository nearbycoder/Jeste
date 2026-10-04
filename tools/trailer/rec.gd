extends Node
## Trailer shot recorder. Plays one scripted shot, then quits after a fixed
## number of frames so Godot's Movie Maker captures exactly that shot:
##
##   godot --path . --rendering-method mobile --resolution 320x180 --fixed-fps 60 \
##         --write-movie <dir>/f.png res://tools/trailer/rec.tscn -- '<shot json>'
##
## Music and ambience are muted (the trailer lays its own music bed under the
## cut); sound effects and voices stay. Shot kinds:
##   route  - chapter play driven by the solver-proven routes in tests/routes.json
##            {"ch", "from", "to", "cut", "append": rle, "story": [ids], "calls": [[frame, what]]}
##   scene  - a menu scene with scripted presses {"scene", "presses": [[frame, action]], "save"}
##   card   - the trailer's title / end card or README poster {"mode": "title" | "end" | "poster"}
## Driven by tools/trailer/make_trailer.py.

var spec: Dictionary
var frames := 0
var total := 0
var node: Node
var level
var line_t := 0.0
var allowed: Array = []
var calls := {}          # frame -> [what, ...]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	spec = JSON.parse_string(a[0])
	total = int(spec.get("frames", 120))
	Game.headless_test = true
	Game.data = Game.default_save()
	Game.settings = Game.default_settings()
	for k in spec.get("settings", {}):
		Game.settings[k] = spec.settings[k]
	Engine.time_scale = 1.0
	var all: Array = spec.get("calls", []).duplicate()
	for c in spec.get("presses", []):
		all.append([c[0], "press:" + str(c[1])])
	for c in all:
		var f := int(c[0])
		if not calls.has(f):
			calls[f] = []
		calls[f].append(str(c[1]))
	match str(spec.get("kind", "route")):
		"route":
			_start_route()
		"scene":
			_prepare_save(str(spec.get("save", "")))
			node = load(str(spec.scene)).instantiate()
		"card":
			node = load("res://tools/trailer/card.gd").new()
			node.mode = str(spec.get("mode", "title"))
	add_child(node)
	if level:
		# no chapter title banner: the trailer captions the shot instead
		level.hud.title_t = 99.0
		level.script_delay = 0.0


## Save data for menu shots: "progress" fills the chapter select with a
## believable mid-game save.
func _prepare_save(kind: String) -> void:
	if kind != "progress":
		return
	Game.data.unlocked = 8
	Game.data.resume = {"chapter": 4, "room": "4-03"}
	Game.data.total_deaths = 297
	for i in 8:
		Game.data.chapters[str(i)] = {"complete": i < 7, "deaths": [0, 23, 41, 57, 66, 38, 72, 0][i],
			"best_time": [61.2, 402.5, 388.1, 455.0, 371.9, 329.4, 410.7, 0.0][i], "golden": i == 1 or i == 4}
	var routes = JSON.parse_string(FileAccess.get_file_as_string("res://tests/routes.json"))
	for ch in ["1", "2", "3", "4", "5", "6"]:
		for chunk in routes[ch]:
			if str(chunk.task).ends_with("_collect"):
				var sol = JSON.parse_string(FileAccess.get_file_as_string("res://tests/solutions/%s.json" % chunk.task))
				for cid in sol.get("collected", []):
					if int(ch) != 3 or not "bell" in str(cid):
						Game.data.collected[cid] = true


func _start_route() -> void:
	var routes = JSON.parse_string(FileAccess.get_file_as_string("res://tests/routes.json"))
	var chunks: Array = routes[str(int(spec.ch))]
	var a := int(spec.get("from", 0))
	var b: int = chunks.size() if int(spec.get("to", -1)) < 0 else int(spec.to)
	var first: Dictionary = chunks[a]
	# task id: "<ch>_<room>_s<spawn>_..."
	var parts: PackedStringArray = str(first.task).split("_")
	Game.pending_chapter = int(spec.ch)
	Game.pending_room = str(first.room)
	Game.pending_spawn = int(parts[2].substr(1))
	allowed = spec.get("story", [])
	var inputs := PackedByteArray()
	for i in range(a, b):
		inputs.append_array(Solver.decode(chunks[i].inputs))
	if spec.has("cut"):
		# stop following the proven route early (e.g. to stage a death)
		inputs = inputs.slice(0, int(spec.cut))
	if spec.has("append"):
		inputs.append_array(Solver.decode(str(spec.append)))
	level = load("res://scenes/level.tscn").instantiate()
	level.replay = inputs
	node = level


func _process(delta: float) -> void:
	# Keep rendering even if the compositor suspends a hidden window, so the
	# Movie Maker never captures stale frames.
	RenderingServer.force_draw(false)
	frames += 1
	for p in [Sfx._music_a, Sfx._music_b, Sfx._amb_a, Sfx._amb_b]:
		if p.playing:
			p.stop()
	for what in calls.get(frames, []):
		_call(what)
	if level:
		_drive_dialogue(delta)
		if spec.get("log", false):
			# frame log for picking trailer cut points: frame room mode input-index events
			var d = level.dialogue
			var line := "%s#%d:%d/%d" % [d.script_id, d.idx, int(d.shown), d._total_chars()] if d.active else "-"
			print("@@ %d %s %s %d %s %s" % [frames, level.room_id, level.mode, level.replay_pos, line, ",".join(PackedStringArray(level.world.events))])
	if frames >= total:
		get_tree().quit()


func _call(what: String) -> void:
	if what == "pause":
		level.paused = true
		level.hud.open_pause()
	elif what.begins_with("menu:"):
		var ev := InputEventAction.new()
		ev.action = what.substr(5)
		ev.pressed = true
		level.hud.handle_menu_input(ev)
	elif what.begins_with("press:"):
		var ev := InputEventAction.new()
		ev.action = what.substr(6)
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventAction.new()
		up.action = ev.action
		up.pressed = false
		Input.parse_input_event.call_deferred(up)
	elif what == "timer":
		level.hud.show_timer = true
	elif node.has_method(what):
		node.call(what)


## Cutscenes: allowed ones advance at reading pace, the rest are skipped.
func _drive_dialogue(delta: float) -> void:
	if level.mode != "dialogue" or not level.dialogue.active:
		return
	var d = level.dialogue
	if not (d.script_id in allowed):
		d.skip_all()
	elif not d.cur.is_empty() and d.shown >= d._total_chars():
		line_t += delta
		var hold := 0.7 + str(d.cur.text).length() / 32.0
		if line_t >= hold:
			line_t = 0.0
			Sfx.play("text_next")
			d._next()
