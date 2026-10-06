extends SceneTree
## Difficulty tuning aid: replays a room route with every possible 1-frame
## slip (a frame inserted or dropped) and reports how many slips kill and
## where Mira's feet were when she died, so the hazards that punish small
## timing errors stand out. Overrides test a change without editing the file.
##
## godot --headless --path . --script res://tools/slip_deaths.gd -- <chapter> <room> <spawn> <solution.json> [chase=N] [wind=x,y]
## e.g. ... -- 7 7-05 0 tests/solutions_basic/7_7-05_s0_to_7-06.json wind=-40,0
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var ch := LevelDB.get_chapter(int(a[0]))
	var def: RoomDef = ch.room(a[1])
	for i in range(4, a.size()):
		var kv := a[i].split("=")
		if kv[0] == "chase": def.chase_delay = int(kv[1])
		elif kv[0] == "wind": def.wind = Vector2(float(kv[1].split(",")[0]), float(kv[1].split(",")[1]))
		else: def.meta[kv[0]] = kv[1]
	var spawn := int(a[2])
	var inputs := Solver.decode(JSON.parse_string(FileAccess.get_file_as_string(a[3])).solution)
	var dead := 0; var n := 0; var cells := {}; var caught := 0
	for at in inputs.size():
		for drop in [false, true]:
			n += 1
			var mod := inputs.slice(0, at)
			if drop: mod.append_array(inputs.slice(at + 1))
			else: mod.append(inputs[at]); mod.append_array(inputs.slice(at))
			for k in 30: mod.append(inputs[inputs.size() - 1])
			var wd := World.new()
			wd.load_room(def, spawn, ch.dashes)
			for inp in mod:
				wd.step(inp)
				if wd.dead:
					dead += 1
					var c := "%d,%d" % [(wd.x + 4) / 8, (wd.y + 11) / 8]
					cells[c] = cells.get(c, 0) + 1
					break
				if wd.end_reached or wd.exited: break
	var ks := cells.keys()
	ks.sort_custom(func(x, y): return cells[x] > cells[y])
	var top := []
	for k in ks.slice(0, 8): top.append("%s:%d" % [k, cells[k]])
	print("DEATH %s lethal %d%% (%d/%d) cells(col,row of feet) %s" % [a[1], dead * 100 / n, dead, n, " ".join(top)])
	quit()
