extends SceneTree
## Emits the chapter graphs and solver tasks as JSON.
## godot --headless --path . --script res://tests/list_tasks.gd -- out.json [chapter...]

const OPP := {"left": "right", "right": "left", "top": "bottom", "bottom": "top"}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "user://tasks.json"
	var chapters: Array = []
	for i in range(1, args.size()):
		chapters.append(int(args[i]))
	if chapters.is_empty():
		for i in LevelDB.chapter_count():
			chapters.append(i)
	var physics := FileAccess.get_file_as_string("res://scripts/sim/world.gd")
	var result := {"chapters": {}, "tasks": [], "errors": []}
	for n in chapters:
		var ch := LevelDB.get_chapter(n)
		if ch == null:
			result.errors.append("chapter %d failed to parse" % n)
			continue
		var g := {"start": ch.start, "dashes": ch.dashes, "rooms": {}, "name": ch.name}
		var entries := {}   # room -> {spawn: true}
		entries[ch.start] = {0: true}
		for rid in ch.order:
			var r: RoomDef = ch.rooms[rid]
			var exits: Array = []
			var seen_t := {}
			for e in r.exits:
				var t: String = e.target
				if seen_t.has(t):
					continue
				seen_t[t] = true
				var tr: RoomDef = ch.rooms.get(t)
				if tr == null:
					result.errors.append("%s: exit to missing room %s" % [rid, t])
					continue
				var sp := tr.spawn_for_side(OPP[e.side])
				exits.append({"target": t, "spawn": sp, "side": e.side})
				if not entries.has(t):
					entries[t] = {}
				entries[t][sp] = true
			var has_end := false
			for e in r.entities:
				if e.type == "end":
					has_end = true
			var col := Array(r.collectible_ids())
			for e in r.entities:
				if e.type == "golden":
					col.append(e.cid)
			g.rooms[rid] = {"exits": exits, "end": has_end, "collectibles": col, "spawns": r.spawns.size()}
			# Sanity checks
			if r.spawns.is_empty():
				result.errors.append("%s: no spawn" % rid)
			for si in r.spawns.size():
				var wd := World.new()
				wd.load_room(r, si, ch.dashes)
				if wd._collide(wd.x, wd.y):
					result.errors.append("%s: spawn %d is inside a wall" % [rid, si])
			for e in r.exits:
				if not _edge_open(r, e):
					result.errors.append("%s: exit %s has no opening on the border" % [rid, e.side])
		# Every referenced cutscene must exist.
		var refs: Array = []
		if ch.meta.has("end_scene"):
			refs.append(str(ch.meta.end_scene))
		for rid in ch.order:
			var r: RoomDef = ch.rooms[rid]
			if r.meta.has("enter"):
				refs.append(str(r.meta.enter))
			for tok in str(r.meta.get("triggers", "")).split(" ", false):
				refs.append(tok.split(":")[1])
				if not r.triggers.has(tok.split(":")[0]):
					result.errors.append("%s: trigger %s has no zone in the map" % [rid, tok])
		for sid in refs:
			if not Story.has(sid):
				result.errors.append("chapter %d: missing cutscene '%s'" % [n, sid])
		result.chapters[str(n)] = g
		for rid in entries:
			var r: RoomDef = ch.rooms.get(rid)
			if r == null:
				continue
			var h := (physics + JSON.stringify(r.meta) + "\n".join(r.rows) + str(ch.dashes)).sha1_text()
			for sp in entries[rid]:
				var targets: Array = []
				for e in g.rooms[rid].exits:
					targets.append(e.target)
				if g.rooms[rid].end:
					targets.append("end")
				for t in targets:
					result.tasks.append({
						"id": "%d_%s_s%d_to_%s" % [n, rid, sp, t], "chapter": n, "room": rid,
						"spawn": sp, "exit": t, "collect": [], "kind": "path", "hash": h,
					})
				var col: Array = g.rooms[rid].collectibles
				if not col.is_empty():
					result.tasks.append({
						"id": "%d_%s_s%d_collect" % [n, rid, sp], "chapter": n, "room": rid,
						"spawn": sp, "exit": "any", "collect": col, "kind": "collect", "hash": h,
					})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("tasks: %d, errors: %d" % [result.tasks.size(), result.errors.size()])
	for e in result.errors:
		print("ERROR: ", e)
	quit()


func _edge_open(r: RoomDef, e: Dictionary) -> bool:
	var lo: int = e.lo
	var hi: int = e.hi
	match e.side:
		"left", "right":
			if lo < 0:
				lo = 0; hi = r.h - 1
			var cx := 0 if e.side == "left" else r.w - 1
			var run := 0
			for cy in range(lo, hi + 1):
				var t := r.cell(cx, cy)
				if t != RoomDef.SOLID and t != RoomDef.SOLID_ALT:
					run += 1
					if run >= 2:
						return true
				else:
					run = 0
		"top", "bottom":
			if lo < 0:
				lo = 0; hi = r.w - 1
			var cy := 0 if e.side == "top" else r.h - 1
			for cx in range(lo, hi + 1):
				var t := r.cell(cx, cy)
				if t != RoomDef.SOLID and t != RoomDef.SOLID_ALT:
					return true
	return false
