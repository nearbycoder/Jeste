extends Node
## End-to-end chapter playthrough through the real Level scene (fast mode).
## godot --headless --path . res://tests/e2e.tscn -- routes.json results.json
##
## routes.json: {"<chapter>": [{"room": id, "inputs": "rle"}, ...], ...}

func _ready() -> void:
	# Watchdog so a script error can never hang the test-suite.
	var t := Timer.new()
	t.wait_time = 900.0
	t.one_shot = true
	t.timeout.connect(func(): get_tree().quit(2))
	add_child(t)
	t.start()
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out := {}
	var game: Node = get_node("/root/Game")
	game.headless_test = true
	for chs in routes:
		out[chs] = _play(game, int(chs), routes[chs])
		print("chapter %s: %s" % [chs, "PASS" if out[chs].ok else "FAIL " + str(out[chs].get("error", ""))])
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	get_tree().quit()


func _play(game: Node, n: int, chunks: Array) -> Dictionary:
	game.data = game.default_save()
	game.pending_chapter = n
	game.pending_room = ""
	var level = load("res://scenes/level.tscn").instantiate()
	level.fast = true
	add_child(level)
	var res := {"ok": false, "rooms": [], "collected": [], "deaths": 0, "frames": 0}
	for i in chunks.size():
		var c: Dictionary = chunks[i]
		if level.room_id != c.room:
			res.error = "chunk %d expected room %s but in %s" % [i, c.room, level.room_id]
			break
		res.rooms.append(c.room)
		var inputs := Solver.decode(c.inputs)
		var start_room: String = level.room_id
		for inp in inputs:
			level.sim_tick(inp)
			res.frames += 1
			if level.finished or level.room_id != start_room or level.mode != "play":
				break
		if level.deaths_this_chapter > 0:
			res.error = "died in room %s" % c.room
			break
		if level.finished:
			break
		if level.room_id == start_room and i < chunks.size() - 1 and chunks[i + 1].room != start_room:
			res.error = "chunk %d did not leave room %s" % [i, c.room]
			break
	res.deaths = level.deaths_this_chapter
	for cid in game.data.collected:
		res.collected.append(cid)
	res.finished = level.finished
	res.golden = bool(game.chapter_data(n).get("golden", false))
	if not res.has("error"):
		if not level.finished:
			res.error = "chapter not finished (ended in %s)" % level.room_id
		elif float(game.chapter_data(n).get("best_time", 0.0)) <= 0.0:
			res.error = "full run did not record a best time"
		else:
			res.ok = true
	level.queue_free()
	return res
