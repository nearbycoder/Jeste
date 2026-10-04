class_name Solver
extends RefCounted
## Automated route finder used by the test-suite to *prove* that rooms can be
## cleared and every collectible can be picked up.
##
## It performs a weighted A* search over short "macro actions" (run, jump,
## hold jump, dash in 8 directions, climb...) and simulates every candidate
## with the real World code. The result is a frame-by-frame input recording
## that the replay tests feed back through the game.

const W = preload("res://scripts/sim/world.gd")

var world: World
var room: RoomDef
var spawn_index := 0
var chapter_dashes := 1

# Goal
var goal_exit := ""          # target room id, "end", or "any"
var goal_berries := PackedInt32Array()   # indices into world.berry_* that must be collected
var goal_bells := PackedInt32Array()
var goal_keys := PackedInt32Array()
var goal_golden := false

# Search params
var frames_per_action := 4
var long_actions := true
var weight := 2.5
var max_expansions := 150000
var max_frames := 60 * 60 * 2
var qx := 2
var qy := 2
var qv := 20.0
var cell_cap := 16
var verbose := false

# Result
var solved := false
var solution := PackedByteArray()
var expansions := 0
var nodes := 0
var elapsed_ms := 0

# Targets (cells) for the heuristic
var _target_cells: Array[Vector2i] = []
var _target_kind: Array[String] = []   # berry / bell / key
var _target_idx := PackedInt32Array()
var _dist: Array[PackedInt32Array] = []
var _exit_dist := PackedInt32Array()
var _best := {}                         # (mask*16+t) -> int cost
var _full_mask := 0
const INF := 1 << 28

# Node storage
var _n_parent := PackedInt32Array()
var _n_g := PackedInt32Array()
var _n_inputs: Array[PackedByteArray] = []
var _n_state: Array = []
var _heap_f := PackedFloat64Array()
var _heap_n := PackedInt32Array()
var _actions: Array = []


func setup(def: RoomDef, spawn: int, dashes: int, exit_target: String, collect_ids: PackedStringArray) -> void:
	room = def
	spawn_index = spawn
	chapter_dashes = dashes
	world = World.new()
	world.load_room(def, spawn, dashes)
	goal_exit = exit_target
	goal_berries = PackedInt32Array()
	goal_bells = PackedInt32Array()
	goal_keys = PackedInt32Array()
	for cid in collect_ids:
		var bi := world.berry_cid.find(cid)
		if bi >= 0:
			goal_berries.append(bi)
		var hi := world.bell_cid.find(cid)
		if hi >= 0:
			goal_bells.append(hi)
	# Doors need keys: make every key a target when the room has doors.
	if not world.door_groups.is_empty():
		for k in world.key_x.size():
			goal_keys.append(k)


# ----------------------------------------------------------------------
# Heuristic
# ----------------------------------------------------------------------

func _passable(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= room.w or cy >= room.h:
		return false
	var t := room.cells[cy * room.w + cx]
	return t != RoomDef.SOLID and t != RoomDef.SOLID_ALT


var _support := PackedByteArray()


func _build_support() -> void:
	# A cell is "supported" when the player could plausibly gain height there:
	# ground (or a jump-through / spring / balloon) within 3 tiles below, or a
	# wall directly beside it.
	_support = PackedByteArray()
	_support.resize(room.w * room.h)
	var lift := {}
	for e in room.entities:
		if e.type in ["spring_up", "spring_left", "spring_right", "balloon", "bumper", "gem", "twin_gem"]:
			for dy in range(-6, 2):
				for dx in range(-2, 3):
					lift[Vector2i(e.cx + dx, e.cy + dy)] = true
	for z in room.zips:
		var r: Rect2i = z.rect
		for yy in range(r.position.y - 4, r.end.y + 1):
			for xx in range(r.position.x - 1, r.end.x + 1):
				lift[Vector2i(xx, yy)] = true
		var t: Vector2i = z.target
		for yy in range(t.y - 6, t.y + r.size.y + 1):
			for xx in range(t.x - 2, t.x + r.size.x + 2):
				lift[Vector2i(xx, yy)] = true
	for cy in room.h:
		for cx in room.w:
			if not _passable(cx, cy):
				continue
			var sup := lift.has(Vector2i(cx, cy))
			if not sup:
				for dx in [-1, 1]:
					var nx: int = cx + dx
					if nx < 0 or nx >= room.w or _solidish(nx, cy):
						sup = true
						break
			if not sup:
				for dy in range(1, 5):
					var ny := cy + dy
					if ny >= room.h:
						break
					var t := room.cells[ny * room.w + cx]
					if _solidish(cx, ny) or t == RoomDef.JUMPTHRU:
						sup = true
						break
			_support[cy * room.w + cx] = 1 if sup else 0


func _solidish(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= room.w or cy >= room.h:
		return true
	var t := room.cells[cy * room.w + cx]
	return t == RoomDef.SOLID or t == RoomDef.SOLID_ALT or t == RoomDef.CRUMBLE or t == RoomDef.MASK_A or t == RoomDef.MASK_B or t == RoomDef.DOOR or t == RoomDef.CRACKED


## Dijkstra from seeds. Costs are expressed "backwards": the field gives the
## cost of travelling *from* a cell *to* the seeds, so moving up into an
## unsupported cell is expensive.
func _bfs(seeds: Array[Vector2i]) -> PackedInt32Array:
	if _support.is_empty():
		_build_support()
	var d := PackedInt32Array()
	d.resize(room.w * room.h)
	d.fill(INF)
	var heap_f := PackedInt32Array()
	var heap_n := PackedInt32Array()
	var push := func(f: int, n: int) -> void:
		heap_f.append(f)
		heap_n.append(n)
		var i := heap_f.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if heap_f[p] <= heap_f[i]:
				break
			var tf := heap_f[p]; heap_f[p] = heap_f[i]; heap_f[i] = tf
			var tn := heap_n[p]; heap_n[p] = heap_n[i]; heap_n[i] = tn
			i = p
	for s in seeds:
		if s.x >= 0 and s.y >= 0 and s.x < room.w and s.y < room.h:
			var i := s.y * room.w + s.x
			if d[i] != 0:
				d[i] = 0
				push.call(0, i)
	while not heap_f.is_empty():
		var cd := heap_f[0]
		var i := heap_n[0]
		var last := heap_f.size() - 1
		heap_f[0] = heap_f[last]
		heap_n[0] = heap_n[last]
		heap_f.resize(last)
		heap_n.resize(last)
		var k := 0
		while true:
			var l := k * 2 + 1
			var r := l + 1
			var m := k
			if l < last and heap_f[l] < heap_f[m]:
				m = l
			if r < last and heap_f[r] < heap_f[m]:
				m = r
			if m == k:
				break
			var tf := heap_f[m]; heap_f[m] = heap_f[k]; heap_f[k] = tf
			var tn := heap_n[m]; heap_n[m] = heap_n[k]; heap_n[k] = tn
			k = m
		if cd > d[i]:
			continue
		var cx := i % room.w
		var cy := i / room.w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if not _passable(nx, ny):
					continue
				if dx != 0 and dy != 0 and (not _passable(cx + dx, cy) or not _passable(cx, cy + dy)):
					continue
				# Travel direction is from (nx,ny) to (cx,cy): rising when dy > 0.
				var cost := 2
				if dy > 0:
					cost = 2 if _support[i] == 1 else 7
				elif dy < 0:
					cost = 1
				var ni := ny * room.w + nx
				if d[ni] > cd + cost:
					d[ni] = cd + cost
					push.call(cd + cost, ni)
	# Fill solid cells with the min of their neighbours + 1 so positions that
	# overlap walls still get a sensible estimate.
	for i in d.size():
		if d[i] == INF:
			var cx := i % room.w
			var cy := i / room.w
			var best := INF
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := cx + dx
					var ny := cy + dy
					if nx >= 0 and ny >= 0 and nx < room.w and ny < room.h:
						best = mini(best, d[ny * room.w + nx])
			if best < INF:
				d[i] = best + 1
	return d


func _build_heuristic() -> void:
	_target_cells.clear()
	_target_kind.clear()
	_target_idx = PackedInt32Array()
	for b in goal_berries:
		_target_cells.append(Vector2i(world.berry_x[b] >> 3, world.berry_y[b] >> 3))
		_target_kind.append("berry")
		_target_idx.append(b)
	for b in goal_bells:
		_target_cells.append(Vector2i(world.bell_x[b] >> 3, world.bell_y[b] >> 3))
		_target_kind.append("bell")
		_target_idx.append(b)
	for k in goal_keys:
		_target_cells.append(Vector2i(world.key_x[k] >> 3, world.key_y[k] >> 3))
		_target_kind.append("key")
		_target_idx.append(k)
	if goal_golden:
		for k in world.golden_x.size():
			_target_cells.append(Vector2i(world.golden_x[k] >> 3, world.golden_y[k] >> 3))
			_target_kind.append("golden")
			_target_idx.append(k)
	_support = PackedByteArray()
	_dist.clear()
	for c in _target_cells:
		var seeds: Array[Vector2i] = [c]
		_dist.append(_bfs(seeds))
	var exit_seeds: Array[Vector2i] = []
	if goal_exit == "end":
		for e in room.entities:
			if e.type == "end":
				exit_seeds.append(Vector2i(e.cx, e.cy))
	else:
		for e in room.exits:
			if goal_exit != "any" and e.target != goal_exit:
				continue
			var lo: int = e.lo
			var hi: int = e.hi
			match e.side:
				"left", "right":
					if lo < 0:
						lo = 0; hi = room.h - 1
					var cx := 0 if e.side == "left" else room.w - 1
					for cy in range(lo, hi + 1):
						if _passable(cx, cy):
							exit_seeds.append(Vector2i(cx, cy))
				"top", "bottom":
					if lo < 0:
						lo = 0; hi = room.w - 1
					var cy := 0 if e.side == "top" else room.h - 1
					for cx in range(lo, hi + 1):
						if _passable(cx, cy):
							exit_seeds.append(Vector2i(cx, cy))
	_exit_dist = _bfs(exit_seeds)
	_full_mask = (1 << _target_cells.size()) - 1
	_best.clear()


func _best_from(mask: int, t: int) -> int:
	var key := mask * 32 + t
	if _best.has(key):
		return _best[key]
	var c := _target_cells[t]
	var res := INF
	if mask == _full_mask:
		res = _exit_dist[c.y * room.w + c.x]
	else:
		for u in _target_cells.size():
			if mask & (1 << u):
				continue
			var d := _dist[u][c.y * room.w + c.x]
			if d >= INF:
				continue
			var rest := _best_from(mask | (1 << u), u)
			res = mini(res, d + rest)
	_best[key] = res
	return res


func _mask() -> int:
	var m := 0
	for t in _target_cells.size():
		var i := _target_idx[t]
		match _target_kind[t]:
			"berry":
				if world.berry_s[i] == 1 or world.berry_s[i] == 2:
					m |= 1 << t
			"bell":
				if world.bell_s[i] == 1:
					m |= 1 << t
			"key":
				if world.key_s[i] != 0:
					m |= 1 << t
			"golden":
				if world.golden_s[i] != 0:
					m |= 1 << t
	return m


func _h() -> float:
	var cx := clampi((world.x + 4) >> 3, 0, room.w - 1)
	var cy := clampi((world.y + 5) >> 3, 0, room.h - 1)
	var ci := cy * room.w + cx
	var mask := _mask()
	var tiles := INF
	if mask == _full_mask:
		tiles = _exit_dist[ci]
	else:
		for u in _target_cells.size():
			if mask & (1 << u):
				continue
			var d := _dist[u][ci]
			if d >= INF:
				continue
			tiles = mini(tiles, d + _best_from(mask | (1 << u), u))
	if tiles >= INF:
		tiles = 400
	# cost units are ~half a tile; ~2.5 px per frame average
	return tiles * 4.0 / 2.5


# ----------------------------------------------------------------------
# Actions
# ----------------------------------------------------------------------

static func _dir_bits(dx: int, dy: int) -> int:
	var b := 0
	if dx < 0: b |= W.IN_LEFT
	elif dx > 0: b |= W.IN_RIGHT
	if dy < 0: b |= W.IN_UP
	elif dy > 0: b |= W.IN_DOWN
	return b


func _build_actions() -> void:
	# Each action: {kind, dx, dy, n}
	_actions.clear()
	var f := frames_per_action
	for dx in [-1, 0, 1]:
		_actions.append({"kind": "move", "dx": dx, "dy": 0, "n": f})
	if long_actions:
		for dx in [-1, 1]:
			_actions.append({"kind": "move", "dx": dx, "dy": 0, "n": f * 2})
	for dx in [-1, 0, 1]:
		_actions.append({"kind": "hold", "dx": dx, "dy": 0, "n": f})
	for dx in [-1, 0, 1]:
		_actions.append({"kind": "jump", "dx": dx, "dy": 0, "n": f})
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			_actions.append({"kind": "dash", "dx": dx, "dy": dy, "n": f})
	for dy in [-1, 0, 1]:
		_actions.append({"kind": "grab", "dx": 0, "dy": dy, "n": f})
	_actions.append({"kind": "grabjump", "dx": 0, "dy": 0, "n": f})
	_actions.append({"kind": "fall", "dx": 0, "dy": 1, "n": f})


## Returns the per-frame inputs for action `a` in the current world state,
## or an empty array if the action is pointless here.
func _action_inputs(a: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	var n: int = a.n
	var prev_jump := (world.prev_input & W.IN_JUMP) != 0
	match a.kind:
		"move":
			var b := _dir_bits(a.dx, 0)
			for i in n:
				out.append(b)
		"fall":
			if world.on_ground or world.state != W.ST_NORMAL:
				return out
			for i in n:
				out.append(W.IN_DOWN)
		"hold":
			if not prev_jump or world.on_ground:
				return out
			var b := _dir_bits(a.dx, 0) | W.IN_JUMP
			for i in n:
				out.append(b)
		"jump":
			var b := _dir_bits(a.dx, 0) | W.IN_JUMP
			if prev_jump:
				out.append(_dir_bits(a.dx, 0))
				for i in n - 1:
					out.append(b)
			else:
				for i in n:
					out.append(b)
		"dash":
			var can := world.state == W.ST_BOOST or (world.dashes > 0 and world.dash_cooldown <= 1)
			if not can:
				return out
			var b := _dir_bits(a.dx, a.dy)
			out.append(b | W.IN_DASH)
			for i in n - 1:
				out.append(b)
		"grab", "grabjump":
			var side := 0
			if world.state == W.ST_CLIMB:
				side = world.facing
			elif world.state == W.ST_NORMAL and not world._tired():
				if world._collide(world.x + world.facing * 2, world.y):
					side = world.facing
				elif world._collide(world.x - world.facing * 2, world.y):
					side = -world.facing
			if side == 0:
				return out
			if a.kind == "grab":
				var b := _dir_bits(side, a.dy) | W.IN_GRAB
				for i in n:
					out.append(b)
			else:
				if world.state != W.ST_CLIMB:
					return out
				var b := W.IN_GRAB | W.IN_JUMP | _dir_bits(0, -1)
				if prev_jump:
					out.append(W.IN_GRAB)
					for i in n - 1:
						out.append(b)
				else:
					for i in n:
						out.append(b)
	return out


# ----------------------------------------------------------------------
# Search
# ----------------------------------------------------------------------

func _state_key() -> int:
	var k := 1469598103934665603
	var vals := [
		world.x / qx, world.y / qy,
		int(floorf(world.vx / qv)), int(floorf(world.vy / qv)),
		world.state, world.dashes, world.prev_input & (W.IN_JUMP | W.IN_GRAB),
		world.dash_timer, mini(world.dash_cooldown, 1),
		int(world.stamina / 22.0), mini(world.var_jump_timer, 1) + (2 if world.auto_jump else 0),
		mini(world.force_move_timer, 1) * (world.force_move_x + 2), 1 if world.ducking else 0,
		mini(world.jump_grace, 1), world.facing if world.state == W.ST_CLIMB else 0,
		world.boost_timer, world.key_count, world.mask_active, world.mask_ghost.size(),
		mini(world.wall_slide_timer / 24, 3),
	]
	for v in vals:
		k = (k ^ int(v)) * 1099511628211
	for v in world.berry_s:
		k = (k ^ v) * 1099511628211
	for v in world.bell_s:
		k = (k ^ v) * 1099511628211
	for v in world.key_s:
		k = (k ^ v) * 1099511628211
	for v in world.golden_s:
		k = (k ^ (v + 7)) * 1099511628211
	for v in world.gem_t:
		k = (k ^ ((v + 29) / 30)) * 1099511628211
	for v in world.balloon_t:
		k = (k ^ ((v + 9) / 10)) * 1099511628211
	for v in world.bumper_t:
		k = (k ^ ((v + 11) / 12)) * 1099511628211
	for gi in world.group_s.size():
		k = (k ^ world.group_s[gi]) * 1099511628211
		k = (k ^ (world.group_t[gi] / 12)) * 1099511628211
	for i in world.zip_count:
		k = (k ^ world.zip_phase[i]) * 1099511628211
		k = (k ^ (world.zip_timer[i] / 4)) * 1099511628211
	if world.chase_delay > 0:
		k = (k ^ mini(world.frame / 30, 1000)) * 1099511628211
	return k


func _goal_reached() -> int:
	# 1 = success, -1 = failed terminal, 0 = continue
	if world.dead:
		return -1
	for b in goal_berries:
		if world.berry_s[b] == 3:
			return -1
	if world.exited or world.end_reached:
		var ok := false
		if goal_exit == "end":
			ok = world.end_reached
		elif goal_exit == "any":
			ok = world.exited
		else:
			ok = world.exited and world.exit_target == goal_exit
		if not ok:
			return -1
		for b in goal_berries:
			if world.berry_s[b] != 2:
				return -1
		for b in goal_bells:
			if world.bell_s[b] != 1:
				return -1
		if goal_golden:
			for g in world.golden_s:
				if g == 0:
					return -1
		return 1
	return 0


func _heap_push(f: float, n: int) -> void:
	_heap_f.append(f)
	_heap_n.append(n)
	var i := _heap_f.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _heap_f[p] <= _heap_f[i]:
			break
		var tf := _heap_f[p]; _heap_f[p] = _heap_f[i]; _heap_f[i] = tf
		var tn := _heap_n[p]; _heap_n[p] = _heap_n[i]; _heap_n[i] = tn
		i = p


func _heap_pop() -> int:
	var top := _heap_n[0]
	var last := _heap_f.size() - 1
	_heap_f[0] = _heap_f[last]
	_heap_n[0] = _heap_n[last]
	_heap_f.resize(last)
	_heap_n.resize(last)
	var i := 0
	var size := last
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < size and _heap_f[l] < _heap_f[m]:
			m = l
		if r < size and _heap_f[r] < _heap_f[m]:
			m = r
		if m == i:
			break
		var tf := _heap_f[m]; _heap_f[m] = _heap_f[i]; _heap_f[i] = tf
		var tn := _heap_n[m]; _heap_n[m] = _heap_n[i]; _heap_n[i] = tn
		i = m
	return top


func solve() -> bool:
	var t0 := Time.get_ticks_msec()
	_build_heuristic()
	_build_actions()
	solved = false
	solution = PackedByteArray()
	expansions = 0
	_n_parent = PackedInt32Array()
	_n_g = PackedInt32Array()
	_n_inputs = []
	_n_state = []
	_heap_f = PackedFloat64Array()
	_heap_n = PackedInt32Array()
	var seen := {}
	var cell_count := {}

	world.reset_room()
	_n_parent.append(-1)
	_n_g.append(0)
	_n_inputs.append(PackedByteArray())
	_n_state.append(world.save_state())
	seen[_state_key()] = true
	_heap_push(weight * _h(), 0)
	var goal_node := -1

	while not _heap_f.is_empty() and expansions < max_expansions:
		var node := _heap_pop()
		expansions += 1
		var base_state: Array = _n_state[node]
		var g := _n_g[node]
		if g > max_frames:
			continue
		for a in _actions:
			world.load_state(base_state)
			var inputs := _action_inputs(a)
			if inputs.is_empty():
				continue
			var used := PackedByteArray()
			var res := 0
			for inp in inputs:
				world.step(inp)
				used.append(inp)
				res = _goal_reached()
				if res != 0:
					break
			if res == -1:
				continue
			var key := _state_key()
			if res == 0 and seen.has(key):
				continue
			seen[key] = true
			if res == 0:
				var ck := (((world.x >> 3) * 64 + (world.y >> 3)) * 8 + world.dashes) * 4096 + _mask() * 4 + (1 if world.state == W.ST_CLIMB else 0) + (2 if world.on_ground else 0)
				var cc: int = cell_count.get(ck, 0)
				if cc >= cell_cap:
					continue
				cell_count[ck] = cc + 1
			var ni := _n_parent.size()
			_n_parent.append(node)
			_n_g.append(g + used.size())
			_n_inputs.append(used)
			if res == 1:
				goal_node = ni
				_n_state.append(null)
				break
			_n_state.append(world.save_state())
			_heap_push(g + used.size() + weight * _h(), ni)
		if goal_node >= 0:
			break
		if verbose and expansions % 5000 == 0:
			print("  exp %d nodes %d open %d" % [expansions, _n_parent.size(), _heap_f.size()])

	nodes = _n_parent.size()
	elapsed_ms = Time.get_ticks_msec() - t0
	if goal_node < 0:
		_n_state = []
		return false
	var chain: Array[PackedByteArray] = []
	var n := goal_node
	while n > 0:
		chain.append(_n_inputs[n])
		n = _n_parent[n]
	chain.reverse()
	for c in chain:
		solution.append_array(c)
	solved = true
	_n_state = []
	return true


## Solves with progressively finer settings until one succeeds.
func solve_adaptive(budget: int = 150000) -> bool:
	var configs := [
		{"f": 4, "qx": 2, "qy": 2, "qv": 20.0, "w": 2.5, "cap": 10, "exp": budget / 4},
		{"f": 4, "qx": 1, "qy": 1, "qv": 15.0, "w": 2.0, "cap": 40, "exp": budget / 3},
		{"f": 2, "qx": 1, "qy": 1, "qv": 10.0, "w": 1.6, "cap": 200, "exp": budget},
	]
	var total_exp := 0
	var total_ms := 0
	for c in configs:
		frames_per_action = c.f
		qx = c.qx
		qy = c.qy
		qv = c.qv
		weight = c.w
		cell_cap = c.cap
		max_expansions = c.exp
		var ok := solve()
		total_exp += expansions
		total_ms += elapsed_ms
		if ok:
			expansions = total_exp
			elapsed_ms = total_ms
			return true
	expansions = total_exp
	elapsed_ms = total_ms
	return false


# ----------------------------------------------------------------------
# Replay / encoding helpers
# ----------------------------------------------------------------------

static func encode(inputs: PackedByteArray) -> String:
	var parts := PackedStringArray()
	var i := 0
	while i < inputs.size():
		var v := inputs[i]
		var n := 1
		while i + n < inputs.size() and inputs[i + n] == v:
			n += 1
		parts.append("%d:%d" % [v, n])
		i += n
	return " ".join(parts)


static func decode(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for tok in s.split(" ", false):
		var p := tok.split(":")
		var v := int(p[0])
		var n := int(p[1])
		for i in n:
			out.append(v)
	return out


## Replays inputs in a fresh world; returns a summary dictionary.
static func replay(def: RoomDef, spawn: int, dashes: int, inputs: PackedByteArray) -> Dictionary:
	var wd := World.new()
	wd.load_room(def, spawn, dashes)
	var collected := PackedStringArray()
	var frames := 0
	for inp in inputs:
		wd.step(inp)
		frames += 1
		for e in wd.events:
			if e.begins_with("berry:") or e.begins_with("bell:"):
				collected.append(e.split(":", true, 1)[1])
		if wd.dead or wd.exited or wd.end_reached:
			break
	return {
		"dead": wd.dead, "exited": wd.exited, "exit_target": wd.exit_target,
		"end": wd.end_reached, "collected": collected, "frames": frames,
	}
