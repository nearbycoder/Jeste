class_name RoomDef
extends RefCounted
## Static, parsed description of one room. Built from the ASCII level files in
## res://data/levels. Never mutated at runtime; World copies what it needs.

# Cell types (stored in `cells`)
const EMPTY := 0
const SOLID := 1
const SOLID_ALT := 2
const JUMPTHRU := 3
const SPIKE_UP := 4
const SPIKE_DOWN := 5
const SPIKE_LEFT := 6
const SPIKE_RIGHT := 7
const CRUMBLE := 8
const DOOR := 9
const CURTAIN := 10
const CRACKED := 11
const MASK_A := 12
const MASK_B := 13
const BGWALL := 14
const FAKE := 15

const TILE := 8

var id: String = ""
var chapter: int = 0
var w: int = 0
var h: int = 0
var rows: PackedStringArray = PackedStringArray()
var cells: PackedByteArray = PackedByteArray()
var spawns: Array[Vector2i] = []
## Entities: Array of Dictionary {type:String, cx:int, cy:int, idx:int, ...}
var entities: Array[Dictionary] = []
## Tile groups: Array of Dictionary {kind:int, cells:PackedInt32Array, rect:Rect2i}
var groups: Array[Dictionary] = []
## Per cell group index (-1 for none)
var group_of: PackedInt32Array = PackedInt32Array()
## Zip movers: Array of Dictionary {rect:Rect2i (cells), target:Vector2i (cell)}
var zips: Array[Dictionary] = []
## Exits: Array of Dictionary {side:String, lo:int, hi:int, target:String}
var exits: Array[Dictionary] = []
## Trigger zones: digit -> Rect2i (cells)
var triggers: Dictionary = {}
## Free-form header values
var meta: Dictionary = {}
var wind: Vector2 = Vector2.ZERO
var max_dashes: int = -1   # -1 = use chapter default
var chase_delay: int = 0   # frames; 0 = no chaser
var title: String = ""


func idx(cx: int, cy: int) -> int:
	return cy * w + cx


func cell(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return EMPTY
	return cells[cy * w + cx]


func has_exit(side: String) -> bool:
	for e in exits:
		if e.side == side:
			return true
	return false


## Returns the exit target for leaving through `side` at cell coordinate `along`
## (row for left/right, column for top/bottom). Empty string if none.
func exit_target(side: String, along: int) -> String:
	var fallback := ""
	for e in exits:
		if e.side != side:
			continue
		if e.lo < 0:
			if fallback == "":
				fallback = e.target
		elif along >= e.lo and along <= e.hi:
			return e.target
	return fallback


func exit_open(side: String, along: int) -> bool:
	return exit_target(side, along) != ""


func entities_of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entities:
		if e.type == type:
			out.append(e)
	return out


## Collectible ids in this room (berries, winged berries, bells, golden).
func collectible_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entities:
		if e.type in ["berry", "winged", "bell"]:
			out.append(e.cid)
	return out


## Picks the spawn used when entering from `side` ("" = first spawn).
func spawn_for_side(side: String) -> int:
	if spawns.is_empty():
		return -1
	if meta.has("spawn_" + side):
		return int(meta["spawn_" + side])
	var best := 0
	var best_d := 1 << 30
	for i in spawns.size():
		var s := spawns[i]
		var d := 0
		match side:
			"left": d = s.x
			"right": d = w - 1 - s.x
			"top": d = s.y
			"bottom": d = h - 1 - s.y
			_: d = i
		if d < best_d:
			best_d = d
			best = i
	return best
