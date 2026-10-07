extends SceneTree
## Checks data/hints.json (the Route Ghost routes shipped with the game):
## every entry must replay, with the basic moveset only, from its room and
## spawn to its exit, exactly as the in-game ghost runs it. Berries-mode
## entries ("room:spawn:collect") must also pick up every id they list.
## godot --headless --path . --script res://tests/hints_check.gd
## Prints "HINTS PASS <n>" or "HINTS FAIL: ..." lines.


func _init() -> void:
	var hints = JSON.parse_string(FileAccess.get_file_as_string("res://data/hints.json"))
	var n := 0
	var bad := 0
	for chs in hints:
		var ch := LevelDB.get_chapter(int(chs))
		for key in hints[chs]:
			var h: Dictionary = hints[chs][key]
			var p: PackedStringArray = str(key).split(":")
			var def: RoomDef = ch.room(p[0])
			n += 1
			if def == null:
				print("HINTS FAIL: %s: unknown room" % key)
				bad += 1
				continue
			var wd := World.new()
			wd.load_room(def, int(p[1]), ch.dashes)
			var tech := false
			var taken := {}
			for inp in Solver.decode(str(h.inputs)):
				wd.step(inp)
				tech = tech or Solver.uses_tech(wd.events)
				for e in wd.events:
					if e.begins_with("berry:") or e.begins_with("bell:"):
						taken[e.split(":", true, 1)[1]] = true
				if wd.dead or wd.exited or wd.end_reached:
					break
			var got := "end" if wd.end_reached else (wd.exit_target if wd.exited else "")
			var missed := []
			for cid in h.get("collect", []):
				if not taken.has(cid):
					missed.append(cid)
			if p.size() > 2 and p[2] == "collect" and Array(h.get("collect", [])).is_empty():
				missed.append("(lists nothing)")
			if wd.dead or got != str(h.exit) or tech or not missed.is_empty():
				print("HINTS FAIL: %s: %s" % [key, "died" if wd.dead else ("advanced tech" if tech else ("missed %s" % [missed] if not missed.is_empty() \
					else "ended at '%s', expected '%s'" % [got, h.exit]))])
				bad += 1
	print("HINTS %s %d" % ["PASS" if bad == 0 else "FAIL", n])
	quit(0 if bad == 0 else 1)
