extends SceneTree
## Solver / verifier worker.
## godot --headless --path . --script res://tests/worker.gd -- jobs.json results.json [--verify-only] [--budget N]
##
## jobs.json: array of tasks (see list_tasks.gd), optionally with "solution"
## (RLE inputs). Cached solutions are replayed first; only failures are solved.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs_path := args[0]
	var out_path := args[1]
	var verify_only := args.has("--verify-only")
	var budget := 150000
	var bi := args.find("--budget")
	if bi >= 0:
		budget = int(args[bi + 1])
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(jobs_path))
	var results: Array = []
	for job in jobs:
		results.append(_run(job, verify_only, budget))
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(results))
		f.close()
	quit()


func _check(job: Dictionary, rep: Dictionary) -> bool:
	if rep.dead:
		return false
	var exit: String = job.exit
	if exit == "end":
		if not rep.end:
			return false
	elif exit == "any":
		if not rep.exited and not rep.end:
			return false
	else:
		if not rep.exited or rep.exit_target != exit:
			return false
	for c in job.collect:
		if not (c in rep.collected):
			return false
	return true


func _replay(def: RoomDef, spawn: int, dashes: int, inputs: PackedByteArray) -> Dictionary:
	var wd := World.new()
	wd.load_room(def, spawn, dashes)
	var collected: Array = []
	for inp in inputs:
		wd.step(inp)
		for e in wd.events:
			if e.begins_with("berry:") or e.begins_with("bell:"):
				collected.append(e.split(":", true, 1)[1])
			elif e == "golden_touch":
				for i in wd.golden_x.size():
					collected.append("%s:golden%d" % [def.id, i])
		if wd.dead or wd.exited or wd.end_reached:
			break
	return {"dead": wd.dead, "exited": wd.exited, "exit_target": wd.exit_target, "end": wd.end_reached, "collected": collected}


func _run(job: Dictionary, verify_only: bool, budget: int) -> Dictionary:
	var ch := LevelDB.get_chapter(int(job.chapter))
	var def: RoomDef = ch.room(job.room)
	var res := {"id": job.id, "ok": false, "cached": false, "frames": 0, "ms": 0, "expansions": 0}
	if def == null:
		res["error"] = "missing room"
		return res
	if job.has("solution") and str(job.solution) != "":
		var inputs := Solver.decode(job.solution)
		var rep := _replay(def, int(job.spawn), ch.dashes, inputs)
		if _check(job, rep):
			res.ok = true
			res.cached = true
			res.solution = job.solution
			res.frames = inputs.size()
			res.exit_target = "end" if rep.end else rep.exit_target
			res.collected = rep.collected
			return res
	if verify_only:
		res["error"] = "no valid cached solution"
		return res
	var s := Solver.new()
	var collect := PackedStringArray()
	for c in job.collect:
		if not str(c).contains(":golden"):
			collect.append(c)
	s.setup(def, int(job.spawn), ch.dashes, job.exit, collect)
	s.goal_golden = false
	for c in job.collect:
		if str(c).contains(":golden"):
			s.goal_golden = true
	var ok := s.solve_adaptive(budget)
	res.ms = s.elapsed_ms
	res.expansions = s.expansions
	if ok:
		var rep := _replay(def, int(job.spawn), ch.dashes, s.solution)
		if _check(job, rep):
			res.ok = true
			res.solution = Solver.encode(s.solution)
			res.frames = s.solution.size()
			res.exit_target = "end" if rep.end else rep.exit_target
			res.collected = rep.collected
		else:
			res["error"] = "solution failed replay: " + JSON.stringify(rep)
	else:
		res["error"] = "no route found"
	return res
