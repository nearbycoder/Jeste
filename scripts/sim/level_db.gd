class_name LevelDB
extends RefCounted
## Loads and parses chapter files from res://data/levels.
##
## File format:
##   @chapter <n>
##   key = value            (chapter header: name, subtitle, start, end, dashes, tileset, music)
##   === <room id>
##   key = value            (room header: exits, wind, triggers, dashes, chase, title, spawn_<side>)
##   ---
##   <ascii map rows>       (until the next === or end of file)
## Lines starting with ';' outside maps are comments.

const CHAPTER_FILES := [
	"res://data/levels/ch0_prologue.txt",
	"res://data/levels/ch1_lantern_town.txt",
	"res://data/levels/ch2_hollow_stage.txt",
	"res://data/levels/ch3_carnival.txt",
	"res://data/levels/ch4_whistling_ridge.txt",
	"res://data/levels/ch5_mirror_cathedral.txt",
	"res://data/levels/ch6_undertow.txt",
	"res://data/levels/ch7_summit.txt",
	"res://data/levels/ch8_epilogue.txt",
]

static var _cache: Dictionary = {}


class ChapterDef:
	extends RefCounted
	var number: int = 0
	var name: String = ""
	var subtitle: String = ""
	var start: String = ""
	var tileset: String = "town"
	var music: String = ""
	var dashes: int = 1
	var meta: Dictionary = {}
	var rooms: Dictionary = {}          # id -> RoomDef
	var order: PackedStringArray = PackedStringArray()

	func room(id: String) -> RoomDef:
		return rooms.get(id)

	func collectible_ids() -> PackedStringArray:
		var out := PackedStringArray()
		for id in order:
			out.append_array(rooms[id].collectible_ids())
		return out

	func berry_count() -> int:
		var n := 0
		for id in order:
			for e in rooms[id].entities:
				if e.type == "berry" or e.type == "winged":
					n += 1
		return n

	func has_bell() -> bool:
		for id in order:
			for e in rooms[id].entities:
				if e.type == "bell":
					return true
		return false


static func chapter_count() -> int:
	return CHAPTER_FILES.size()


static func get_chapter(n: int) -> ChapterDef:
	if _cache.has(n):
		return _cache[n]
	var ch := parse_file(CHAPTER_FILES[n])
	_cache[n] = ch
	return ch


static func clear_cache() -> void:
	_cache.clear()


static func parse_file(path: String) -> ChapterDef:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LevelDB: cannot open " + path)
		return null
	var text := f.get_as_text()
	return parse_text(text, path)


static func parse_text(text: String, path: String = "<text>") -> ChapterDef:
	var ch := ChapterDef.new()
	var lines := text.split("\n")
	var mode := "chapter"   # chapter | header | map
	var room_id := ""
	var header := {}
	var map_rows: PackedStringArray = PackedStringArray()

	var blocks: Array = []   # [room_id, header, map_rows]

	for raw in lines:
		var line: String = raw.strip_edges(false, true)
		if line.begins_with("==="):
			room_id = line.substr(3).strip_edges()
			header = {}
			map_rows = PackedStringArray()
			blocks.append([room_id, header, map_rows])
			mode = "header"
			continue
		if mode == "map":
			if line.strip_edges() == "" or line.begins_with(";"):
				continue
			map_rows.append(line)
			blocks[blocks.size() - 1][2] = map_rows
			continue
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with(";"):
			continue
		if stripped.begins_with("@chapter"):
			ch.number = int(stripped.substr(8).strip_edges())
			continue
		if mode == "header" and stripped == "---":
			mode = "map"
			continue
		var eq := stripped.find("=")
		if eq < 0:
			push_error("%s: bad line '%s'" % [path, stripped])
			continue
		var key := stripped.substr(0, eq).strip_edges()
		var val := stripped.substr(eq + 1).strip_edges()
		if mode == "chapter":
			match key:
				"name": ch.name = val
				"subtitle": ch.subtitle = val
				"start": ch.start = val
				"tileset": ch.tileset = val
				"music": ch.music = val
				"dashes": ch.dashes = int(val)
				_: ch.meta[key] = val
		else:
			header[key] = val
	for b in blocks:
		var r := build_room(b[0], b[1], b[2], ch, path)
		if r != null:
			ch.rooms[b[0]] = r
			ch.order.append(b[0])
	if ch.start == "" and not ch.order.is_empty():
		ch.start = ch.order[0]
	return ch


static func build_room(id: String, header: Dictionary, map_rows: PackedStringArray, ch: ChapterDef, path: String) -> RoomDef:
	# Trim trailing empty rows
	while not map_rows.is_empty() and map_rows[map_rows.size() - 1].strip_edges() == "":
		map_rows.remove_at(map_rows.size() - 1)
	if map_rows.is_empty():
		push_error("%s: room %s has no map" % [path, id])
		return null
	var r := RoomDef.new()
	r.id = id
	r.chapter = ch.number
	r.meta = header.duplicate()
	r.h = map_rows.size()
	var w := 0
	for row in map_rows:
		w = maxi(w, row.length())
	r.w = w
	for row in map_rows:
		r.rows.append(row.rpad(w, "."))
	r.cells.resize(w * r.h)
	r.group_of.resize(w * r.h)
	r.group_of.fill(-1)

	var zip_cells: Dictionary = {}
	var zip_targets: Array[Vector2i] = []
	var counters := {}
	for cy in r.h:
		var row: String = r.rows[cy]
		for cx in w:
			var c := row[cx]
			var t := RoomDef.EMPTY
			match c:
				"#": t = RoomDef.SOLID
				"%": t = RoomDef.SOLID_ALT
				"=": t = RoomDef.JUMPTHRU
				"^": t = RoomDef.SPIKE_UP
				"v": t = RoomDef.SPIKE_DOWN
				"<": t = RoomDef.SPIKE_LEFT
				">": t = RoomDef.SPIKE_RIGHT
				"~": t = RoomDef.CRUMBLE
				"D": t = RoomDef.DOOR
				"C": t = RoomDef.CURTAIN
				"X": t = RoomDef.CRACKED
				"R": t = RoomDef.MASK_A
				"B": t = RoomDef.MASK_B
				",": t = RoomDef.BGWALL
				"&": t = RoomDef.FAKE
				"P": r.spawns.append(Vector2i(cx, cy))
				"Z": zip_cells[Vector2i(cx, cy)] = true
				"z": zip_targets.append(Vector2i(cx, cy))
				"S": _add_ent(r, counters, "spring_up", cx, cy)
				"[": _add_ent(r, counters, "spring_right", cx, cy)
				"]": _add_ent(r, counters, "spring_left", cx, cy)
				"*": _add_ent(r, counters, "gem", cx, cy)
				"+": _add_ent(r, counters, "twin_gem", cx, cy)
				"b": _add_ent(r, counters, "berry", cx, cy)
				"w": _add_ent(r, counters, "winged", cx, cy)
				"H": _add_ent(r, counters, "bell", cx, cy)
				"G": _add_ent(r, counters, "golden", cx, cy)
				"k": _add_ent(r, counters, "key", cx, cy)
				"O": _add_ent(r, counters, "balloon", cx, cy)
				"o": _add_ent(r, counters, "bumper", cx, cy)
				"E": _add_ent(r, counters, "end", cx, cy)
				"N": _add_ent(r, counters, "npc", cx, cy)
				"1", "2", "3", "4", "5", "6", "7", "8", "9":
					var rect: Rect2i = r.triggers.get(c, Rect2i(cx, cy, 0, 0))
					if rect.size == Vector2i.ZERO:
						rect = Rect2i(cx, cy, 1, 1)
					else:
						rect = rect.expand(Vector2i(cx, cy)).expand(Vector2i(cx + 1, cy + 1))
					r.triggers[c] = rect
				".", " ": pass
				_:
					# Decorations (lowercase letters not listed above) are visual only.
					pass
			r.cells[cy * w + cx] = t

	# Collectible ids
	for e in r.entities:
		if e.type in ["berry", "winged", "bell", "golden"]:
			e["cid"] = "%s:%s%d" % [id, e.type, e.idx]

	# NPC names from header "npc = bellamy,tobi"
	if header.has("npc"):
		var names: PackedStringArray = str(header.npc).split(",")
		var i := 0
		for e in r.entities:
			if e.type == "npc":
				e["name"] = names[mini(i, names.size() - 1)].strip_edges()
				i += 1

	_build_groups(r)
	_build_zips(r, zip_cells, zip_targets, path)
	_parse_exits(r, str(header.get("exits", "")), path)

	if header.has("wind"):
		var p: PackedStringArray = str(header.wind).split(",")
		r.wind = Vector2(float(p[0]), float(p[1]) if p.size() > 1 else 0.0)
	if header.has("dashes"):
		r.max_dashes = int(header.dashes)
	if header.has("chase"):
		r.chase_delay = int(header.chase)
	r.title = str(header.get("title", ""))
	if r.spawns.is_empty():
		push_error("%s: room %s has no spawn (P)" % [path, id])
	return r


static func _add_ent(r: RoomDef, counters: Dictionary, type: String, cx: int, cy: int) -> void:
	var n: int = counters.get(type, 0)
	counters[type] = n + 1
	r.entities.append({"type": type, "cx": cx, "cy": cy, "idx": n})


## Connected groups for crumble (horizontal runs), doors / curtains / cracked
## walls (4-connected regions). Mask blocks are not grouped.
static func _build_groups(r: RoomDef) -> void:
	for cy in r.h:
		for cx in r.w:
			var i := cy * r.w + cx
			var t := r.cells[i]
			if r.group_of[i] != -1:
				continue
			if t == RoomDef.CRUMBLE:
				var cells := PackedInt32Array()
				var x := cx
				while x < r.w and r.cells[cy * r.w + x] == RoomDef.CRUMBLE:
					cells.append(cy * r.w + x)
					x += 1
				_register_group(r, t, cells)
			elif t == RoomDef.DOOR or t == RoomDef.CURTAIN or t == RoomDef.CRACKED or t == RoomDef.FAKE:
				var cells := PackedInt32Array()
				var stack: Array[int] = [i]
				var seen := {i: true}
				while not stack.is_empty():
					var j: int = stack.pop_back()
					cells.append(j)
					var jx := j % r.w
					var jy := j / r.w
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = jx + d.x
						var ny: int = jy + d.y
						if nx < 0 or ny < 0 or nx >= r.w or ny >= r.h:
							continue
						var k := ny * r.w + nx
						if not seen.has(k) and r.cells[k] == t:
							seen[k] = true
							stack.append(k)
				cells.sort()
				_register_group(r, t, cells)


static func _register_group(r: RoomDef, kind: int, cells: PackedInt32Array) -> void:
	var gi := r.groups.size()
	var minx := 1 << 20
	var miny := 1 << 20
	var maxx := -1
	var maxy := -1
	for c in cells:
		r.group_of[c] = gi
		var x := c % r.w
		var y := c / r.w
		minx = mini(minx, x)
		miny = mini(miny, y)
		maxx = maxi(maxx, x)
		maxy = maxi(maxy, y)
	r.groups.append({"kind": kind, "cells": cells, "rect": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)})


static func _build_zips(r: RoomDef, zip_cells: Dictionary, targets: Array[Vector2i], path: String) -> void:
	var seen := {}
	var rects: Array[Rect2i] = []
	for cy in r.h:
		for cx in r.w:
			var p := Vector2i(cx, cy)
			if not zip_cells.has(p) or seen.has(p):
				continue
			var x1 := cx
			while zip_cells.has(Vector2i(x1 + 1, cy)):
				x1 += 1
			var y1 := cy
			while zip_cells.has(Vector2i(cx, y1 + 1)):
				y1 += 1
			for yy in range(cy, y1 + 1):
				for xx in range(cx, x1 + 1):
					seen[Vector2i(xx, yy)] = true
			rects.append(Rect2i(cx, cy, x1 - cx + 1, y1 - cy + 1))
	if rects.size() != targets.size():
		push_error("%s: room %s has %d zip movers but %d targets" % [path, r.id, rects.size(), targets.size()])
	for i in mini(rects.size(), targets.size()):
		r.zips.append({"rect": rects[i], "target": targets[i]})


## exits = right:1-02 top[3-8]:1-03b left:1-00
static func _parse_exits(r: RoomDef, spec: String, path: String) -> void:
	for tok in spec.split(" ", false):
		var colon := tok.find(":")
		if colon < 0:
			push_error("%s: room %s bad exit '%s'" % [path, r.id, tok])
			continue
		var side := tok.substr(0, colon)
		var target := tok.substr(colon + 1)
		var lo := -1
		var hi := -1
		var br := side.find("[")
		if br >= 0:
			var rng := side.substr(br + 1, side.length() - br - 2).split("-")
			lo = int(rng[0])
			hi = int(rng[1])
			side = side.substr(0, br)
		if not side in ["left", "right", "top", "bottom"]:
			push_error("%s: room %s bad exit side '%s'" % [path, r.id, side])
			continue
		r.exits.append({"side": side, "lo": lo, "hi": hi, "target": target})
