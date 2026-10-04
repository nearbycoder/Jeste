extends SceneTree

func _init() -> void:
	var ch := LevelDB.parse_file("res://tests/fixtures/solver_test.txt")
	for rid in ch.order:
		var r: RoomDef = ch.room(rid)
		for collect in [false, true]:
			var s := Solver.new()
			var target: String = r.exits[0].target
			s.setup(r, 0, 1, target, r.collectible_ids() if collect else PackedStringArray())
			s.verbose = true
			var ok := s.solve_adaptive(60000)
			print("%s collect=%s -> %s exp=%d nodes=%d %dms frames=%d" % [rid, collect, ok, s.expansions, s.nodes, s.elapsed_ms, s.solution.size()])
			if ok:
				var rep := Solver.replay(r, 0, 1, s.solution)
				print("   replay: ", rep)
				print("   ", Solver.encode(s.solution).substr(0, 300))
	quit()
