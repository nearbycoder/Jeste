class_name World
extends RefCounted
## Deterministic fixed-step simulation of one room: the player plus every
## gameplay entity. Rendering nodes only *read* from this object, and the
## automated solver / replay tests drive exactly the same code, so a recorded
## input sequence that clears a room in a test clears it in the real game.
##
## Movement constants and timings follow a published, MIT-licensed platformer
## player controller (see THIRD_PARTY_NOTICES.md). Units: pixels and seconds,
## 60 steps per second.

# ---------------------------------------------------------------- input bits
const IN_LEFT := 1
const IN_RIGHT := 2
const IN_UP := 4
const IN_DOWN := 8
const IN_JUMP := 16
const IN_DASH := 32
const IN_GRAB := 64

# ---------------------------------------------------------------- states
const ST_NORMAL := 0
const ST_CLIMB := 1
const ST_DASH := 2
const ST_DREAM := 3
const ST_BOOST := 4

# ---------------------------------------------------------------- constants
const DT := 1.0 / 60.0
const PW := 8
const PH := 11
const GRAVITY := 900.0
const MAX_FALL := 160.0
const FAST_MAX_FALL := 240.0
const FAST_MAX_ACCEL := 300.0
const HALF_GRAV_THRESHOLD := 40.0
const MAX_RUN := 90.0
const RUN_ACCEL := 1000.0
const RUN_REDUCE := 400.0
const AIR_MULT := 0.65
const JUMP_SPEED := -105.0
const JUMP_H_BOOST := 40.0
const WALL_JUMP_H := 130.0
const WALL_SLIDE_START_MAX := 20.0
const DASH_SPEED := 240.0
const END_DASH_SPEED := 160.0
const END_DASH_UP_MULT := 0.75
const DODGE_SLIDE_MULT := 1.2
const SUPER_JUMP_H := 260.0
const DUCK_SUPER_X := 1.25
const DUCK_SUPER_Y := 0.5
const SUPER_WALL_JUMP_SPEED := -160.0
const SUPER_WALL_JUMP_H := 170.0
const CLIMB_MAX_STAMINA := 110.0
const CLIMB_UP_COST := 100.0 / 2.2
const CLIMB_STILL_COST := 100.0 / 10.0
const CLIMB_JUMP_COST := 110.0 / 4.0
const CLIMB_UP_SPEED := -45.0
const CLIMB_DOWN_SPEED := 80.0
const CLIMB_SLIP_SPEED := 30.0
const CLIMB_ACCEL := 900.0
const CLIMB_GRAB_Y_MULT := 0.2
const CLIMB_TIRED := 20.0
const CLIMB_HOP_Y := -120.0
const CLIMB_HOP_X := 100.0
const SPRING_SPEED := -185.0
const SIDE_SPRING_X := 240.0
const SIDE_SPRING_Y := -140.0
const BUMPER_SPEED := 280.0
const DREAM_SPEED := 240.0
const LIFT_X_CAP := 250.0
const LIFT_Y_CAP := -130.0
const DIAG := 0.70710678118

# Timers in frames
const F_JUMP_GRACE := 6
const F_JUMP_BUFFER := 5
const F_DASH_BUFFER := 5
const F_VAR_JUMP := 12
const F_WALL_JUMP_FORCE := 10
const F_DASH := 9
const F_DASH_COOLDOWN := 12
const F_DASH_REFILL := 6
const F_DASH_ATTACK := 18
const F_WALL_SLIDE := 72
const F_SUPER_WALL_VAR := 15
const F_CLIMB_HOP_FORCE := 12
const F_CLIMB_NO_MOVE := 6
const F_WALL_BOOST := 12
const F_CEILING_VAR_GRACE := 3
const F_LIFT_GRACE := 10
const F_BOOST := 15
const F_SIDE_SPRING_FORCE := 18
const F_GEM_RESPAWN := 150
const F_BALLOON_RESPAWN := 60
const F_BUMPER_COOLDOWN := 36
const F_CRUMBLE_SHAKE := 24
const F_CRUMBLE_GONE := 120
const F_ZIP_DELAY := 6
const F_ZIP_FORWARD := 30
const F_ZIP_HOLD := 30
const F_ZIP_RETURN := 120
const F_ZIP_COOLDOWN := 20

# Zip phases
const Z_IDLE := 0
const Z_DELAY := 1
const Z_FORWARD := 2
const Z_HOLD := 3
const Z_RETURN := 4
const Z_COOLDOWN := 5

# ---------------------------------------------------------------- room data
var room: RoomDef
var w: int = 0
var h: int = 0
var cells: PackedByteArray
var solid: PackedByteArray          # 0 none, 1 solid, 2 curtain (solid unless dashing)
var left_open: PackedByteArray
var right_open: PackedByteArray
var top_open: PackedByteArray
var dyn_cells: PackedInt32Array     # indices of cells whose solidity can change
var wind_x: float = 0.0
var wind_y: float = 0.0
var assist_invincible := false
var assist_infinite_stamina := false

# Static entity tables (pixel space)
var gem_x := PackedInt32Array()
var gem_y := PackedInt32Array()
var gem_twin := PackedByteArray()
var berry_x := PackedInt32Array()
var berry_y := PackedInt32Array()
var berry_winged := PackedByteArray()
var berry_ghost := PackedByteArray()
var berry_cid := PackedStringArray()
var key_x := PackedInt32Array()
var key_y := PackedInt32Array()
var bell_x := PackedInt32Array()
var bell_y := PackedInt32Array()
var bell_cid := PackedStringArray()
var bell_ghost := PackedByteArray()
var golden_x := PackedInt32Array()
var golden_y := PackedInt32Array()
var spring_x := PackedInt32Array()
var spring_y := PackedInt32Array()
var spring_dir := PackedInt32Array()  # 0 up, 1 right, -1 left
var balloon_x := PackedInt32Array()
var balloon_y := PackedInt32Array()
var bumper_x := PackedInt32Array()
var bumper_y := PackedInt32Array()
var end_rects: Array[Rect2i] = []
var trigger_keys := PackedStringArray()
var trigger_rects: Array[Rect2i] = []
var door_groups := PackedInt32Array()
var zip_w := PackedInt32Array()
var zip_h := PackedInt32Array()
var zip_sx := PackedInt32Array()
var zip_sy := PackedInt32Array()
var zip_tx := PackedInt32Array()
var zip_ty := PackedInt32Array()
var zip_count := 0
var has_mask := false
var has_curtain := false

# ---------------------------------------------------------------- dynamic entity state
var gem_t := PackedInt32Array()
var berry_s := PackedInt32Array()      # 0 idle, 1 held, 2 collected, 3 flown away
var key_s := PackedInt32Array()        # 0 idle, 1 held, 2 used
var bell_s := PackedInt32Array()
var golden_s := PackedInt32Array()     # 0 idle, 1 taken
var balloon_t := PackedInt32Array()
var bumper_t := PackedInt32Array()
var group_s := PackedInt32Array()      # per group: state
var group_t := PackedInt32Array()      # per group: timer
var zip_px := PackedInt32Array()       # x,y pairs
var zip_phase := PackedInt32Array()
var zip_timer := PackedInt32Array()
var zip_vx := PackedFloat64Array()
var zip_vy := PackedFloat64Array()
var mask_active: int = 0
var mask_ghost := PackedInt32Array()
var trigger_fired: int = 0
var key_count: int = 0
var golden_held := false

# ---------------------------------------------------------------- player state
var x: int = 0
var y: int = 0
var rx: float = 0.0
var ry: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var facing: int = 1
var state: int = ST_NORMAL
var dashes: int = 1
var max_dashes: int = 1
var stamina: float = CLIMB_MAX_STAMINA
var max_fall: float = MAX_FALL
var jump_grace: int = 0
var jump_buffer: int = 0
var dash_buffer: int = 0
var var_jump_timer: int = 0
var var_jump_speed: float = 0.0
var auto_jump := false
var force_move_x: int = 0
var force_move_timer: int = 0
var dash_timer: int = 0
var dash_cooldown: int = 0
var dash_refill_cd: int = 0
var dash_attack_timer: int = 0
var dash_dir_x: int = 0
var dash_dir_y: int = 0
var wall_slide_timer: int = F_WALL_SLIDE
var wall_slide_dir: int = 0
var wall_boost_timer: int = 0
var wall_boost_dir: int = 0
var climb_no_move: int = 0
var last_climb_move: int = 0
var ducking := false
var on_ground := false
var was_on_ground := false
var prev_input: int = 0
var lift_vx: float = 0.0
var lift_vy: float = 0.0
var lift_timer: int = 0
var boost_idx: int = -1
var boost_timer: int = 0
var dead := false
var frame: int = 0
var spawn_x: int = 0
var spawn_y: int = 0

# Transient per step
var move_x: int = 0
var move_y: int = 0
var in_x: int = 0
var in_y: int = 0
var jump_held := false
var grab_held := false
var curtain_pass := false
var zip_ignore: int = -1

# Results
var events := PackedStringArray()
var exited := false
var exit_side := ""
var exit_target := ""
var end_reached := false

# Chaser (the Grin): replays the player's path `chase_delay` frames later.
var chase_delay: int = 0
var chase_hist := PackedInt32Array()   # x,y pairs per frame since room start
var chase_active := false

# View only (never read by the simulation): positions as they were one physics
# tick ago, so the renderer can draw between steps (Smooth Motion). The level
# calls snap_prev() once per tick before stepping; view_alpha is how far the
# current frame is between that snapshot (0) and the latest step (1).
var prev_x: int = 0
var prev_y: int = 0
var prev_zip := PackedInt32Array()
var prev_chaser := Vector2i(-1000, -1000)
var view_alpha := 1.0


# ======================================================================
# Room loading
# ======================================================================

## collected: Dictionary of collectible ids already in the save (shown as ghosts).
func load_room(def: RoomDef, spawn_index: int, chapter_dashes: int, collected: Dictionary = {}) -> void:
	room = def
	w = def.w
	h = def.h
	cells = def.cells
	solid = PackedByteArray()
	solid.resize(w * h)
	dyn_cells = PackedInt32Array()
	for i in w * h:
		var t := cells[i]
		var s := 0
		match t:
			RoomDef.SOLID, RoomDef.SOLID_ALT, RoomDef.CRUMBLE, RoomDef.DOOR, RoomDef.CRACKED:
				s = 1
			RoomDef.CURTAIN:
				s = 2
			RoomDef.MASK_A:
				s = 1
		solid[i] = s
		if t == RoomDef.CRUMBLE or t == RoomDef.DOOR or t == RoomDef.CRACKED or t == RoomDef.MASK_A or t == RoomDef.MASK_B:
			dyn_cells.append(i)
	left_open = PackedByteArray()
	left_open.resize(h)
	right_open = PackedByteArray()
	right_open.resize(h)
	top_open = PackedByteArray()
	top_open.resize(w)
	for cy in h:
		left_open[cy] = 1 if def.exit_open("left", cy) else 0
		right_open[cy] = 1 if def.exit_open("right", cy) else 0
	for cx in w:
		top_open[cx] = 1 if def.exit_open("top", cx) else 0
	wind_x = def.wind.x
	wind_y = def.wind.y
	max_dashes = def.max_dashes if def.max_dashes >= 0 else chapter_dashes
	chase_delay = def.chase_delay

	# Entities
	gem_x = PackedInt32Array(); gem_y = PackedInt32Array(); gem_twin = PackedByteArray()
	berry_x = PackedInt32Array(); berry_y = PackedInt32Array(); berry_winged = PackedByteArray()
	berry_ghost = PackedByteArray(); berry_cid = PackedStringArray()
	key_x = PackedInt32Array(); key_y = PackedInt32Array()
	bell_x = PackedInt32Array(); bell_y = PackedInt32Array(); bell_cid = PackedStringArray(); bell_ghost = PackedByteArray()
	golden_x = PackedInt32Array(); golden_y = PackedInt32Array()
	spring_x = PackedInt32Array(); spring_y = PackedInt32Array(); spring_dir = PackedInt32Array()
	balloon_x = PackedInt32Array(); balloon_y = PackedInt32Array()
	bumper_x = PackedInt32Array(); bumper_y = PackedInt32Array()
	end_rects = []
	for e in def.entities:
		var px: int = e.cx * 8
		var py: int = e.cy * 8
		match e.type:
			"gem", "twin_gem":
				gem_x.append(px + 4); gem_y.append(py + 4); gem_twin.append(1 if e.type == "twin_gem" else 0)
			"berry", "winged":
				berry_x.append(px + 4); berry_y.append(py + 4)
				berry_winged.append(1 if e.type == "winged" else 0)
				berry_ghost.append(1 if collected.has(e.cid) else 0)
				berry_cid.append(e.cid)
			"key":
				key_x.append(px + 4); key_y.append(py + 4)
			"bell":
				bell_x.append(px + 4); bell_y.append(py + 4); bell_cid.append(e.cid)
				bell_ghost.append(1 if collected.has(e.cid) else 0)
			"golden":
				golden_x.append(px + 4); golden_y.append(py + 4)
			"spring_up":
				spring_x.append(px); spring_y.append(py); spring_dir.append(0)
			"spring_right":
				spring_x.append(px); spring_y.append(py); spring_dir.append(1)
			"spring_left":
				spring_x.append(px); spring_y.append(py); spring_dir.append(-1)
			"balloon":
				balloon_x.append(px + 4); balloon_y.append(py + 4)
			"bumper":
				bumper_x.append(px + 4); bumper_y.append(py + 4)
			"end":
				end_rects.append(Rect2i(px - 4, py - 16, 16, 24))
	trigger_keys = PackedStringArray()
	trigger_rects = []
	for k in def.triggers:
		trigger_keys.append(k)
		var r: Rect2i = def.triggers[k]
		trigger_rects.append(Rect2i(r.position * 8, r.size * 8))
	door_groups = PackedInt32Array()
	for gi in def.groups.size():
		if def.groups[gi].kind == RoomDef.DOOR:
			door_groups.append(gi)
	zip_count = def.zips.size()
	zip_w = PackedInt32Array(); zip_h = PackedInt32Array()
	zip_sx = PackedInt32Array(); zip_sy = PackedInt32Array()
	zip_tx = PackedInt32Array(); zip_ty = PackedInt32Array()
	for z in def.zips:
		var r: Rect2i = z.rect
		zip_w.append(r.size.x * 8); zip_h.append(r.size.y * 8)
		zip_sx.append(r.position.x * 8); zip_sy.append(r.position.y * 8)
		zip_tx.append(z.target.x * 8); zip_ty.append(z.target.y * 8)
	has_curtain = false
	for g in def.groups:
		if g.kind == RoomDef.CURTAIN:
			has_curtain = true
	has_mask = false
	for i in dyn_cells:
		if cells[i] == RoomDef.MASK_A or cells[i] == RoomDef.MASK_B:
			has_mask = true
			break

	var sp: Vector2i = def.spawns[clampi(spawn_index, 0, def.spawns.size() - 1)] if not def.spawns.is_empty() else Vector2i(1, 1)
	spawn_x = sp.x * 8
	spawn_y = sp.y * 8 + 8 - PH
	reset_room()


## Resets every entity and puts the player at the room's respawn point.
func reset_room() -> void:
	gem_t = PackedInt32Array(); gem_t.resize(gem_x.size())
	berry_s = PackedInt32Array(); berry_s.resize(berry_x.size())
	key_s = PackedInt32Array(); key_s.resize(key_x.size())
	bell_s = PackedInt32Array(); bell_s.resize(bell_x.size())
	golden_s = PackedInt32Array(); golden_s.resize(golden_x.size())
	if golden_held:
		golden_s.fill(1)
	balloon_t = PackedInt32Array(); balloon_t.resize(balloon_x.size())
	bumper_t = PackedInt32Array(); bumper_t.resize(bumper_x.size())
	group_s = PackedInt32Array(); group_s.resize(room.groups.size())
	group_t = PackedInt32Array(); group_t.resize(room.groups.size())
	zip_px = PackedInt32Array(); zip_px.resize(zip_count * 2)
	zip_phase = PackedInt32Array(); zip_phase.resize(zip_count)
	zip_timer = PackedInt32Array(); zip_timer.resize(zip_count)
	zip_vx = PackedFloat64Array(); zip_vx.resize(zip_count)
	zip_vy = PackedFloat64Array(); zip_vy.resize(zip_count)
	for i in zip_count:
		zip_px[i * 2] = zip_sx[i]
		zip_px[i * 2 + 1] = zip_sy[i]
	mask_active = 0
	mask_ghost = PackedInt32Array()
	key_count = 0
	_rebuild_dynamic_solids()

	x = spawn_x
	y = spawn_y
	rx = 0.0; ry = 0.0; vx = 0.0; vy = 0.0
	facing = 1 if spawn_x < w * 4 else -1
	state = ST_NORMAL
	dashes = max_dashes
	stamina = CLIMB_MAX_STAMINA
	max_fall = MAX_FALL
	jump_grace = 0; jump_buffer = 0; dash_buffer = 0
	var_jump_timer = 0; var_jump_speed = 0.0; auto_jump = false
	force_move_x = 0; force_move_timer = 0
	dash_timer = 0; dash_cooldown = 0; dash_refill_cd = 0; dash_attack_timer = 0
	dash_dir_x = 0; dash_dir_y = 0
	wall_slide_timer = F_WALL_SLIDE; wall_slide_dir = 0
	wall_boost_timer = 0; wall_boost_dir = 0
	climb_no_move = 0; last_climb_move = 0
	ducking = false
	on_ground = _check_ground()
	was_on_ground = on_ground
	prev_input = 0
	lift_vx = 0.0; lift_vy = 0.0; lift_timer = 0
	boost_idx = -1; boost_timer = 0
	dead = false
	frame = 0
	exited = false
	exit_side = ""
	exit_target = ""
	end_reached = false
	events = PackedStringArray()
	chase_hist = PackedInt32Array()
	chase_active = false
	snap_prev()


func _rebuild_dynamic_solids() -> void:
	for i in dyn_cells:
		var t := cells[i]
		var s := 0
		match t:
			RoomDef.CRUMBLE:
				s = 0 if group_s[room.group_of[i]] == 2 else 1
			RoomDef.DOOR:
				s = 0 if group_s[room.group_of[i]] == 1 else 1
			RoomDef.CRACKED:
				s = 0 if group_s[room.group_of[i]] == 1 else 1
			RoomDef.MASK_A:
				s = 1 if mask_active == 0 else 0
			RoomDef.MASK_B:
				s = 1 if mask_active == 1 else 0
		solid[i] = s
	for i in mask_ghost:
		solid[i] = 0


# ======================================================================
# Snapshot (used by the solver)
# ======================================================================

func save_state() -> Array:
	var p := PackedFloat64Array([
		x, y, rx, ry, vx, vy, facing, state, dashes, stamina, max_fall,
		jump_grace, jump_buffer, dash_buffer, var_jump_timer, var_jump_speed, 1 if auto_jump else 0,
		force_move_x, force_move_timer, dash_timer, dash_cooldown, dash_refill_cd, dash_attack_timer,
		dash_dir_x, dash_dir_y, wall_slide_timer, wall_slide_dir, wall_boost_timer, wall_boost_dir,
		climb_no_move, last_climb_move, 1 if ducking else 0, 1 if on_ground else 0, 1 if was_on_ground else 0,
		prev_input, lift_vx, lift_vy, lift_timer, boost_idx, boost_timer, 1 if dead else 0, frame,
		mask_active, trigger_fired, key_count, 1 if golden_held else 0,
		1 if exited else 0, 1 if end_reached else 0, 1 if chase_active else 0,
	])
	# Packed arrays are shared by reference in Godot 4, so snapshots must copy.
	return [p, gem_t.duplicate(), berry_s.duplicate(), key_s.duplicate(), bell_s.duplicate(),
		golden_s.duplicate(), balloon_t.duplicate(), bumper_t.duplicate(), group_s.duplicate(),
		group_t.duplicate(), zip_px.duplicate(), zip_phase.duplicate(), zip_timer.duplicate(),
		zip_vx.duplicate(), zip_vy.duplicate(), mask_ghost.duplicate(), exit_side, exit_target,
		chase_hist.duplicate()]


func load_state(s: Array) -> void:
	var p: PackedFloat64Array = s[0]
	x = int(p[0]); y = int(p[1]); rx = p[2]; ry = p[3]; vx = p[4]; vy = p[5]
	facing = int(p[6]); state = int(p[7]); dashes = int(p[8]); stamina = p[9]; max_fall = p[10]
	jump_grace = int(p[11]); jump_buffer = int(p[12]); dash_buffer = int(p[13])
	var_jump_timer = int(p[14]); var_jump_speed = p[15]; auto_jump = p[16] != 0.0
	force_move_x = int(p[17]); force_move_timer = int(p[18]); dash_timer = int(p[19])
	dash_cooldown = int(p[20]); dash_refill_cd = int(p[21]); dash_attack_timer = int(p[22])
	dash_dir_x = int(p[23]); dash_dir_y = int(p[24]); wall_slide_timer = int(p[25]); wall_slide_dir = int(p[26])
	wall_boost_timer = int(p[27]); wall_boost_dir = int(p[28]); climb_no_move = int(p[29]); last_climb_move = int(p[30])
	ducking = p[31] != 0.0; on_ground = p[32] != 0.0; was_on_ground = p[33] != 0.0
	prev_input = int(p[34]); lift_vx = p[35]; lift_vy = p[36]; lift_timer = int(p[37])
	boost_idx = int(p[38]); boost_timer = int(p[39]); dead = p[40] != 0.0; frame = int(p[41])
	var old_mask := mask_active
	mask_active = int(p[42]); trigger_fired = int(p[43]); key_count = int(p[44]); golden_held = p[45] != 0.0
	exited = p[46] != 0.0; end_reached = p[47] != 0.0; chase_active = p[48] != 0.0
	gem_t = (s[1] as PackedInt32Array).duplicate()
	berry_s = (s[2] as PackedInt32Array).duplicate()
	key_s = (s[3] as PackedInt32Array).duplicate()
	bell_s = (s[4] as PackedInt32Array).duplicate()
	golden_s = (s[5] as PackedInt32Array).duplicate()
	balloon_t = (s[6] as PackedInt32Array).duplicate()
	bumper_t = (s[7] as PackedInt32Array).duplicate()
	var gs: PackedInt32Array = s[8]
	var ghost: PackedInt32Array = s[15]
	var need_rebuild := (gs != group_s) or old_mask != mask_active or ghost != mask_ghost
	group_s = gs.duplicate()
	group_t = (s[9] as PackedInt32Array).duplicate()
	zip_px = (s[10] as PackedInt32Array).duplicate()
	zip_phase = (s[11] as PackedInt32Array).duplicate()
	zip_timer = (s[12] as PackedInt32Array).duplicate()
	zip_vx = (s[13] as PackedFloat64Array).duplicate()
	zip_vy = (s[14] as PackedFloat64Array).duplicate()
	mask_ghost = ghost.duplicate()
	exit_side = s[16]; exit_target = s[17]
	chase_hist = (s[18] as PackedInt32Array).duplicate()
	curtain_pass = state == ST_DASH or state == ST_DREAM
	if need_rebuild and not dyn_cells.is_empty():
		_rebuild_dynamic_solids()


# ======================================================================
# Collision helpers
# ======================================================================

func _oob_solid(cx: int, cy: int) -> bool:
	if cy >= h:
		return false
	if cx < 0:
		if cy < 0:
			return true
		return left_open[cy] == 0
	if cx >= w:
		if cy < 0:
			return true
		return right_open[cy] == 0
	if cy < 0:
		return top_open[cx] == 0
	return false


## Rectangle collision against the tile grid + zip movers.
func _collide_rect(px: int, py: int, rw: int, rh: int) -> bool:
	var cx0 := px >> 3
	var cx1 := (px + rw - 1) >> 3
	var cy0 := py >> 3
	var cy1 := (py + rh - 1) >> 3
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if cx < 0 or cx >= w or cy < 0 or cy >= h:
				if _oob_solid(cx, cy):
					return true
				continue
			var s := solid[cy * w + cx]
			if s == 1 or (s == 2 and not curtain_pass):
				return true
	if zip_count > 0:
		for i in zip_count:
			if i == zip_ignore:
				continue
			var zx := zip_px[i * 2]
			var zy := zip_px[i * 2 + 1]
			if px < zx + zip_w[i] and px + rw > zx and py < zy + zip_h[i] and py + rh > zy:
				return true
	return false


func _collide(px: int, py: int) -> bool:
	return _collide_rect(px, py, PW, PH)


## True if the cell under the player's feet row is the top of a jump-through.
func _jumpthru_below(px: int, py: int) -> bool:
	var feet := py + PH
	if feet & 7 != 0:
		return false
	var cy := feet >> 3
	if cy < 0 or cy >= h:
		return false
	var cx0 := px >> 3
	var cx1 := (px + PW - 1) >> 3
	for cx in range(cx0, cx1 + 1):
		if cx >= 0 and cx < w and cells[cy * w + cx] == RoomDef.JUMPTHRU:
			return true
	return false


func _check_ground() -> bool:
	return _collide(x, y + 1) or _jumpthru_below(x, y)


func _overlaps_curtain(px: int, py: int) -> bool:
	var cx0 := px >> 3
	var cx1 := (px + PW - 1) >> 3
	var cy0 := py >> 3
	var cy1 := (py + PH - 1) >> 3
	for cy in range(maxi(cy0, 0), mini(cy1, h - 1) + 1):
		for cx in range(maxi(cx0, 0), mini(cx1, w - 1) + 1):
			if solid[cy * w + cx] == 2:
				return true
	return false


## Breaks cracked walls overlapping the rect. Returns true if anything broke.
func _break_cracked(px: int, py: int) -> bool:
	var broke := false
	var cx0 := px >> 3
	var cx1 := (px + PW - 1) >> 3
	var cy0 := py >> 3
	var cy1 := (py + PH - 1) >> 3
	for cy in range(maxi(cy0, 0), mini(cy1, h - 1) + 1):
		for cx in range(maxi(cx0, 0), mini(cx1, w - 1) + 1):
			var i := cy * w + cx
			if cells[i] == RoomDef.CRACKED:
				var g := room.group_of[i]
				if group_s[g] == 0:
					group_s[g] = 1
					for c in room.groups[g].cells:
						solid[c] = 0
					broke = true
					events.append("break")
	return broke


func _blocked(px: int, py: int) -> bool:
	if not _collide(px, py):
		return false
	if state == ST_DASH and _break_cracked(px, py):
		return _collide(px, py)
	return true


# ======================================================================
# Movement
# ======================================================================

func _move_h(amount: float) -> void:
	rx += amount
	var m := int(roundf(rx))
	if m == 0:
		return
	rx -= m
	_move_h_exact(m)


func _move_v(amount: float) -> void:
	ry += amount
	var m := int(roundf(ry))
	if m == 0:
		return
	ry -= m
	_move_v_exact(m)


func _move_h_exact(m: int) -> void:
	var s := 1 if m > 0 else -1
	while m != 0:
		if _blocked(x + s, y):
			_on_collide_h(s)
			return
		x += s
		m -= s
		if state == ST_DASH and has_curtain and _overlaps_curtain(x, y):
			_enter_dream()


func _move_v_exact(m: int) -> void:
	var s := 1 if m > 0 else -1
	while m != 0:
		if _blocked(x, y + s) or (s > 0 and state != ST_DREAM and _jumpthru_below(x, y)):
			_on_collide_v(s)
			return
		y += s
		m -= s
		if state == ST_DASH and has_curtain and _overlaps_curtain(x, y):
			_enter_dream()


func _on_collide_h(s: int) -> void:
	if state == ST_DREAM:
		_die()
		return
	if state == ST_DASH and vy == 0.0 and vx != 0.0:
		for i in range(1, 5):
			for j in [1, -1]:
				if not _collide(x + s, y + i * j):
					y += i * j
					x += s
					return
	vx = 0.0
	rx = 0.0


func _on_collide_v(s: int) -> void:
	if state == ST_DREAM:
		_die()
		return
	if s < 0:
		if vx <= 0.01:
			for i in range(1, 5):
				if not _collide(x - i, y - 1):
					x -= i
					y -= 1
					return
		if vx >= -0.01:
			for i in range(1, 5):
				if not _collide(x + i, y - 1):
					x += i
					y -= 1
					return
		if var_jump_timer < F_VAR_JUMP - F_CEILING_VAR_GRACE:
			var_jump_timer = 0
	else:
		if state == ST_DASH and dash_dir_x != 0 and dash_dir_y > 0 and vy > 0.0:
			dash_dir_y = 0
			vy = 0.0
			ry = 0.0
			vx *= DODGE_SLIDE_MULT
			ducking = true
			return
		if vy > 60.0:
			events.append("land")
	vy = 0.0
	ry = 0.0


# ======================================================================
# Step
# ======================================================================

func step(inp: int) -> void:
	events = PackedStringArray()
	if dead or exited or end_reached:
		return
	frame += 1
	var prev := prev_input
	prev_input = inp
	if (inp & IN_JUMP) != 0 and (prev & IN_JUMP) == 0:
		jump_buffer = F_JUMP_BUFFER
	elif jump_buffer > 0:
		jump_buffer -= 1
	if (inp & IN_DASH) != 0 and (prev & IN_DASH) == 0:
		dash_buffer = F_DASH_BUFFER
	elif dash_buffer > 0:
		dash_buffer -= 1
	in_x = (1 if inp & IN_RIGHT else 0) - (1 if inp & IN_LEFT else 0)
	in_y = (1 if inp & IN_DOWN else 0) - (1 if inp & IN_UP else 0)
	jump_held = (inp & IN_JUMP) != 0
	grab_held = (inp & IN_GRAB) != 0
	curtain_pass = state == ST_DASH or state == ST_DREAM
	zip_ignore = -1

	if zip_count > 0:
		_update_zips()
		if dead:
			return
	_update_entity_timers()
	_player_update()
	if dead:
		return
	_check_entities()
	if dead or exited or end_reached:
		return
	_check_bounds()
	if chase_delay > 0 and not dead:
		_update_chaser()


func _player_update() -> void:
	if force_move_timer > 0:
		force_move_timer -= 1
		move_x = force_move_x
	else:
		move_x = in_x
	move_y = in_y

	if state == ST_DREAM or state == ST_BOOST:
		on_ground = false
	elif vy >= 0.0:
		on_ground = _check_ground()
	else:
		on_ground = false

	if wall_slide_dir != 0:
		wall_slide_timer = maxi(wall_slide_timer - 1, 0)
		wall_slide_dir = 0
	if wall_boost_timer > 0:
		wall_boost_timer -= 1
		if move_x == wall_boost_dir:
			vx = WALL_JUMP_H * move_x
			stamina += CLIMB_JUMP_COST
			wall_boost_timer = 0
	if on_ground and state != ST_CLIMB:
		auto_jump = false
		stamina = CLIMB_MAX_STAMINA
		wall_slide_timer = F_WALL_SLIDE
	if dash_attack_timer > 0:
		dash_attack_timer -= 1
	if on_ground:
		jump_grace = F_JUMP_GRACE
	elif jump_grace > 0:
		jump_grace -= 1
	if dash_cooldown > 0:
		dash_cooldown -= 1
	if dash_refill_cd > 0:
		dash_refill_cd -= 1
	elif on_ground and dashes < max_dashes:
		dashes = max_dashes
		events.append("refill")
	if var_jump_timer > 0:
		var_jump_timer -= 1
	if lift_timer > 0:
		lift_timer -= 1
		if lift_timer == 0:
			lift_vx = 0.0
			lift_vy = 0.0
	if assist_infinite_stamina:
		stamina = CLIMB_MAX_STAMINA
	if move_x != 0 and state != ST_CLIMB and state != ST_BOOST:
		facing = move_x

	curtain_pass = state == ST_DASH or state == ST_DREAM
	match state:
		ST_NORMAL:
			_normal_update()
		ST_CLIMB:
			_climb_update()
		ST_DASH:
			_dash_update()
		ST_DREAM:
			_dream_update()
		ST_BOOST:
			_boost_update()
	curtain_pass = state == ST_DASH or state == ST_DREAM

	if state == ST_BOOST:
		was_on_ground = false
		return
	# Wind (sheltered when a wall is right behind you on the upwind side)
	if state == ST_NORMAL and (wind_x != 0.0 or wind_y != 0.0):
		if wind_x != 0.0:
			var ws := 1 if wind_x > 0.0 else -1
			if not _collide(x - ws * 3, y):
				_move_h(wind_x * DT)
		if wind_y != 0.0 and (vy < 0.0 or not on_ground):
			_move_v(wind_y * DT)
	if vx != 0.0:
		_move_h(vx * DT)
	if dead:
		return
	if vy != 0.0:
		_move_v(vy * DT)
	if dead:
		return
	if state == ST_DREAM and not _overlaps_curtain(x, y):
		_exit_dream()
	if has_mask and not mask_ghost.is_empty():
		_update_mask_ghosts()
	was_on_ground = on_ground


func _aim() -> Vector2i:
	var ax := in_x
	var ay := in_y
	if ax == 0 and ay == 0:
		ax = facing
	return Vector2i(ax, ay)


func _tired() -> bool:
	return stamina < CLIMB_TIRED


func _lift_boost_x() -> float:
	return clampf(lift_vx, -LIFT_X_CAP, LIFT_X_CAP)


func _lift_boost_y() -> float:
	if lift_vy > 0.0:
		return 0.0
	return maxf(lift_vy, LIFT_Y_CAP)


func _climb_check(dir: int, yadd: int = 0) -> bool:
	return _collide(x + dir, y + yadd)


func _wall_jump_check(dir: int) -> bool:
	return _collide(x + dir * 3, y)


func _can_dash() -> bool:
	return dash_buffer > 0 and dash_cooldown <= 0 and dashes > 0


func _normal_update() -> void:
	if lift_vy < 0.0 and was_on_ground and not on_ground and vy >= 0.0:
		vy = _lift_boost_y()
	# Climb
	if grab_held and not _tired() and not ducking:
		if vy >= 0.0 and signf(vx) != -facing:
			if _climb_check(facing):
				_climb_begin()
				return
			if move_y < 1:
				for i in range(1, 3):
					if not _collide(x, y - i) and _climb_check(facing, -i):
						_move_v_exact(-i)
						_climb_begin()
						return
	# Dash
	if _can_dash():
		vx += _lift_boost_x()
		vy += _lift_boost_y()
		_start_dash()
		return
	# Running
	var mult := 1.0 if on_ground else AIR_MULT
	if absf(vx) > MAX_RUN and signf(vx) == move_x:
		vx = move_toward(vx, MAX_RUN * move_x, RUN_REDUCE * mult * DT)
	else:
		vx = move_toward(vx, MAX_RUN * move_x, RUN_ACCEL * mult * DT)
	# Gravity
	if move_y == 1 and vy >= MAX_FALL:
		max_fall = move_toward(max_fall, FAST_MAX_FALL, FAST_MAX_ACCEL * DT)
	else:
		max_fall = move_toward(max_fall, MAX_FALL, FAST_MAX_ACCEL * DT)
	if not on_ground:
		var mx := max_fall
		if (move_x == facing or (move_x == 0 and grab_held)) and move_y != 1:
			if vy >= 0.0 and wall_slide_timer > 0 and _collide(x + facing, y):
				wall_slide_dir = facing
			if wall_slide_dir != 0:
				mx = lerpf(MAX_FALL, WALL_SLIDE_START_MAX, float(wall_slide_timer) / F_WALL_SLIDE)
		var gm := 0.5 if (absf(vy) < HALF_GRAV_THRESHOLD and (jump_held or auto_jump)) else 1.0
		vy = move_toward(vy, mx, GRAVITY * gm * DT)
	# Variable jump
	if var_jump_timer > 0:
		if auto_jump or jump_held:
			vy = minf(vy, var_jump_speed)
		else:
			var_jump_timer = 0
	# Jump
	if jump_buffer > 0:
		if jump_grace > 0:
			_jump()
		elif _wall_jump_check(1):
			if facing == 1 and grab_held and stamina > 0.0 and not _tired():
				_climb_jump()
			elif dash_attack_timer > 0 and dash_dir_x == 0 and dash_dir_y == -1:
				_super_wall_jump(-1)
			else:
				_wall_jump(-1)
		elif _wall_jump_check(-1):
			if facing == -1 and grab_held and stamina > 0.0 and not _tired():
				_climb_jump()
			elif dash_attack_timer > 0 and dash_dir_x == 0 and dash_dir_y == -1:
				_super_wall_jump(1)
			else:
				_wall_jump(1)


func _jump() -> void:
	jump_buffer = 0
	jump_grace = 0
	var_jump_timer = F_VAR_JUMP
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = F_WALL_SLIDE
	wall_boost_timer = 0
	vx += JUMP_H_BOOST * move_x + _lift_boost_x()
	vy = JUMP_SPEED + _lift_boost_y()
	var_jump_speed = vy
	events.append("jump")


func _wall_jump(dir: int) -> void:
	jump_buffer = 0
	ducking = false
	jump_grace = 0
	var_jump_timer = F_VAR_JUMP
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = F_WALL_SLIDE
	wall_boost_timer = 0
	if move_x != 0:
		force_move_x = dir
		force_move_timer = F_WALL_JUMP_FORCE
	vx = WALL_JUMP_H * dir + _lift_boost_x()
	vy = JUMP_SPEED + _lift_boost_y()
	var_jump_speed = vy
	facing = dir
	events.append("walljump")


func _super_wall_jump(dir: int) -> void:
	jump_buffer = 0
	ducking = false
	jump_grace = 0
	var_jump_timer = F_SUPER_WALL_VAR
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = F_WALL_SLIDE
	wall_boost_timer = 0
	vx = SUPER_WALL_JUMP_H * dir + _lift_boost_x()
	vy = SUPER_WALL_JUMP_SPEED + _lift_boost_y()
	var_jump_speed = vy
	facing = dir
	events.append("wallbounce")


func _climb_jump() -> void:
	if not on_ground:
		stamina -= CLIMB_JUMP_COST
	_jump()
	if move_x == 0:
		wall_boost_dir = -facing
		wall_boost_timer = F_WALL_BOOST


func _super_jump() -> void:
	jump_buffer = 0
	jump_grace = 0
	var_jump_timer = F_VAR_JUMP
	auto_jump = false
	dash_attack_timer = 0
	wall_slide_timer = F_WALL_SLIDE
	wall_boost_timer = 0
	vx = SUPER_JUMP_H * facing + _lift_boost_x()
	vy = JUMP_SPEED + _lift_boost_y()
	if ducking:
		ducking = false
		vx *= DUCK_SUPER_X
		vy *= DUCK_SUPER_Y
		events.append("hyper")
	else:
		events.append("super")
	var_jump_speed = vy


func _start_dash() -> void:
	dashes -= 1
	dash_buffer = 0
	_dash_begin(true)


func _dash_begin(from_player: bool) -> void:
	dash_cooldown = F_DASH_COOLDOWN
	dash_refill_cd = F_DASH_REFILL
	wall_slide_timer = F_WALL_SLIDE
	dash_attack_timer = F_DASH_ATTACK
	var bvx := vx
	var a := _aim()
	var f := DIAG if (a.x != 0 and a.y != 0) else 1.0
	var nvx := a.x * DASH_SPEED * f
	var nvy := a.y * DASH_SPEED * f
	if signf(bvx) == signf(nvx) and absf(bvx) > absf(nvx):
		nvx = bvx
	vx = nvx
	vy = nvy
	dash_dir_x = a.x
	dash_dir_y = a.y
	if a.x != 0:
		facing = a.x
	if on_ground and a.x != 0 and a.y > 0:
		dash_dir_y = 0
		vy = 0.0
		vx *= DODGE_SLIDE_MULT
		ducking = true
	dash_timer = F_DASH
	state = ST_DASH
	curtain_pass = true
	var_jump_timer = 0
	if from_player:
		events.append("dash")
	else:
		events.append("launch")
	if has_mask:
		_toggle_mask()
	if berry_winged.size() > 0:
		for i in berry_x.size():
			if berry_winged[i] == 1 and berry_s[i] == 0:
				berry_s[i] = 3
				events.append("berry_flee")


func _dash_update() -> void:
	dash_timer -= 1
	if dash_dir_y == 0 and jump_buffer > 0 and jump_grace > 0:
		_super_jump()
		state = ST_NORMAL
		return
	if dash_dir_x == 0 and dash_dir_y == -1 and jump_buffer > 0:
		if _wall_jump_check(1):
			_super_wall_jump(-1)
			state = ST_NORMAL
			return
		elif _wall_jump_check(-1):
			_super_wall_jump(1)
			state = ST_NORMAL
			return
	if dash_timer <= 0:
		auto_jump = true
		if dash_dir_y <= 0:
			var f := DIAG if (dash_dir_x != 0 and dash_dir_y != 0) else 1.0
			vx = dash_dir_x * END_DASH_SPEED * f
			vy = dash_dir_y * END_DASH_SPEED * f
		if vy < 0.0:
			vy *= END_DASH_UP_MULT
		ducking = false
		state = ST_NORMAL


func _climb_begin() -> void:
	state = ST_CLIMB
	vx = 0.0
	vy *= CLIMB_GRAB_Y_MULT
	wall_slide_timer = F_WALL_SLIDE
	climb_no_move = F_CLIMB_NO_MOVE
	wall_boost_timer = 0
	last_climb_move = 0
	for i in 2:
		if not _collide(x + facing, y):
			x += facing
		else:
			break
	events.append("grab")


func _slip_check(addy: int = 0) -> bool:
	var px := (x + PW) if facing == 1 else (x - 1)
	var py := y + 4 + addy
	return not _point_solid(px, py) and not _point_solid(px, py - 4 + addy)


func _point_solid(px: int, py: int) -> bool:
	return _collide_rect(px, py, 1, 1)


func _climb_hop() -> void:
	vx = facing * CLIMB_HOP_X
	vy = minf(vy, CLIMB_HOP_Y)
	force_move_x = 0
	force_move_timer = F_CLIMB_HOP_FORCE
	events.append("climbhop")


func _climb_update() -> void:
	if climb_no_move > 0:
		climb_no_move -= 1
	if on_ground:
		stamina = CLIMB_MAX_STAMINA
	if jump_buffer > 0:
		if move_x == -facing:
			_wall_jump(-facing)
		else:
			_climb_jump()
		state = ST_NORMAL
		return
	if _can_dash():
		vx += _lift_boost_x()
		vy += _lift_boost_y()
		state = ST_NORMAL
		_start_dash()
		return
	if not grab_held:
		state = ST_NORMAL
		return
	if not _collide(x + facing, y):
		if vy < 0.0:
			_climb_hop()
		state = ST_NORMAL
		return
	var target := 0.0
	var try_slip := false
	if climb_no_move <= 0:
		if in_y == -1:
			target = CLIMB_UP_SPEED
			if _collide(x, y - 1):
				if vy < 0.0:
					vy = 0.0
				target = 0.0
				try_slip = true
			elif _slip_check():
				_climb_hop()
				state = ST_NORMAL
				return
		elif in_y == 1:
			target = CLIMB_DOWN_SPEED
			if on_ground:
				vy = 0.0
				target = 0.0
		else:
			try_slip = true
	else:
		try_slip = true
	last_climb_move = int(signf(target))
	if try_slip and _slip_check():
		target = CLIMB_SLIP_SPEED
	vy = move_toward(vy, target, CLIMB_ACCEL * DT)
	if in_y != 1 and vy > 0.0 and not _collide(x + facing, y + 1):
		vy = 0.0
	if climb_no_move <= 0:
		if last_climb_move == -1:
			stamina -= CLIMB_UP_COST * DT
		elif last_climb_move == 0:
			stamina -= CLIMB_STILL_COST * DT
	if assist_infinite_stamina:
		stamina = CLIMB_MAX_STAMINA
	if stamina <= 0.0:
		state = ST_NORMAL
		events.append("tired")


func _enter_dream() -> void:
	state = ST_DREAM
	var f := DIAG if (dash_dir_x != 0 and dash_dir_y != 0) else 1.0
	vx = dash_dir_x * DREAM_SPEED * f
	vy = dash_dir_y * DREAM_SPEED * f
	if dash_dir_x == 0 and dash_dir_y == 0:
		vx = facing * DREAM_SPEED
	curtain_pass = true
	events.append("dream_in")


func _dream_update() -> void:
	pass


func _exit_dream() -> void:
	state = ST_NORMAL
	curtain_pass = false
	if dashes < max_dashes:
		dashes = max_dashes
	jump_grace = F_JUMP_GRACE
	dash_attack_timer = 0
	auto_jump = true
	if vy < 0.0:
		vy *= END_DASH_UP_MULT
	events.append("dream_out")


func _boost_update() -> void:
	vx = 0.0
	vy = 0.0
	var bxp := balloon_x[boost_idx] - 4
	var byp := balloon_y[boost_idx] - 6
	x = bxp
	y = byp
	boost_timer -= 1
	if dash_buffer > 0 or boost_timer <= 0:
		dash_buffer = 0
		balloon_t[boost_idx] = F_BALLOON_RESPAWN
		boost_idx = -1
		state = ST_NORMAL
		dashes = maxi(dashes, max_dashes)
		_dash_begin(false)


func _toggle_mask() -> void:
	mask_active = 1 - mask_active
	var want := RoomDef.MASK_A if mask_active == 0 else RoomDef.MASK_B
	var other := RoomDef.MASK_B if mask_active == 0 else RoomDef.MASK_A
	mask_ghost = PackedInt32Array()
	for i in dyn_cells:
		var t := cells[i]
		if t == other:
			solid[i] = 0
		elif t == want:
			solid[i] = 1
	# Blocks appearing inside the player stay intangible until the player leaves them.
	var cx0 := x >> 3
	var cx1 := (x + PW - 1) >> 3
	var cy0 := y >> 3
	var cy1 := (y + PH - 1) >> 3
	for cy in range(maxi(cy0, 0), mini(cy1, h - 1) + 1):
		for cx in range(maxi(cx0, 0), mini(cx1, w - 1) + 1):
			var i := cy * w + cx
			if cells[i] == want:
				solid[i] = 0
				mask_ghost.append(i)
	events.append("mask")


func _update_mask_ghosts() -> void:
	var keep := PackedInt32Array()
	for i in mask_ghost:
		var cx := i % w
		var cy := i / w
		if x < cx * 8 + 8 and x + PW > cx * 8 and y < cy * 8 + 8 and y + PH > cy * 8:
			keep.append(i)
		else:
			solid[i] = 1
	mask_ghost = keep


# ======================================================================
# Entities
# ======================================================================

func _update_entity_timers() -> void:
	for i in gem_t.size():
		if gem_t[i] > 0:
			gem_t[i] -= 1
			if gem_t[i] == 0:
				events.append("gem_back")
	for i in balloon_t.size():
		if balloon_t[i] > 0 and boost_idx != i:
			balloon_t[i] -= 1
	for i in bumper_t.size():
		if bumper_t[i] > 0:
			bumper_t[i] -= 1
	# Crumble groups
	for gi in group_s.size():
		var g: Dictionary = room.groups[gi]
		if g.kind != RoomDef.CRUMBLE:
			continue
		var st := group_s[gi]
		if st == 0:
			var r: Rect2i = g.rect
			var gx := r.position.x * 8
			var gy := r.position.y * 8
			var gw := r.size.x * 8
			# standing on top, or climbing its side
			var on_top := (y + PH == gy) and x < gx + gw and x + PW > gx and on_ground
			var on_side := state == ST_CLIMB and y < gy + 8 and y + PH > gy and ((facing == 1 and x + PW == gx) or (facing == -1 and x == gx + gw))
			if on_top or on_side:
				group_s[gi] = 1
				group_t[gi] = F_CRUMBLE_SHAKE
				events.append("crumble")
		elif st == 1:
			group_t[gi] -= 1
			if group_t[gi] <= 0:
				group_s[gi] = 2
				group_t[gi] = F_CRUMBLE_GONE
				for c in g.cells:
					solid[c] = 0
		elif st == 2:
			group_t[gi] -= 1
			if group_t[gi] <= 0:
				var r: Rect2i = g.rect
				if _player_overlaps_px(r.position.x * 8, r.position.y * 8, r.size.x * 8, r.size.y * 8):
					group_t[gi] = 1
				else:
					group_s[gi] = 0
					for c in g.cells:
						solid[c] = 1
					events.append("crumble_back")


func _player_overlaps_px(ex: int, ey: int, ew: int, eh: int) -> bool:
	return x < ex + ew and x + PW > ex and y < ey + eh and y + PH > ey


func _check_entities() -> void:
	# Spikes
	if not assist_invincible and _touching_spikes():
		_die()
		return
	# Gems
	for i in gem_x.size():
		if gem_t[i] == 0 and _player_overlaps_px(gem_x[i] - 6, gem_y[i] - 6, 12, 12):
			var target := 2 if gem_twin[i] == 1 else max_dashes
			if dashes < target or stamina < CLIMB_TIRED:
				dashes = target
				stamina = CLIMB_MAX_STAMINA
				gem_t[i] = F_GEM_RESPAWN
				events.append("gem")
	# Springs
	for i in spring_x.size():
		var sx := spring_x[i]
		var sy := spring_y[i]
		match spring_dir[i]:
			0:
				if vy >= 0.0 and _player_overlaps_px(sx, sy + 3, 8, 5):
					_spring_up(sy + 3)
			1:
				if vx <= 60.0 and _player_overlaps_px(sx, sy, 5, 8):
					_spring_side(1)
			-1:
				if vx >= -60.0 and _player_overlaps_px(sx + 3, sy, 5, 8):
					_spring_side(-1)
	# Berries
	for i in berry_x.size():
		var bs := berry_s[i]
		if bs == 0 and _player_overlaps_px(berry_x[i] - 6, berry_y[i] - 6, 12, 12):
			berry_s[i] = 1
			events.append("berry_touch")
		elif bs == 1 and on_ground and state != ST_DASH:
			berry_s[i] = 2
			events.append("berry:" + berry_cid[i])
	# Golden
	for i in golden_x.size():
		if golden_s[i] == 0 and _player_overlaps_px(golden_x[i] - 6, golden_y[i] - 6, 12, 12):
			golden_s[i] = 1
			golden_held = true
			events.append("golden_touch")
	# Keys & doors
	for i in key_x.size():
		if key_s[i] == 0 and _player_overlaps_px(key_x[i] - 5, key_y[i] - 5, 10, 10):
			key_s[i] = 1
			key_count += 1
			events.append("key")
	if key_count > 0:
		for gi in door_groups:
			if group_s[gi] == 0:
				var r: Rect2i = room.groups[gi].rect
				if _player_overlaps_px(r.position.x * 8 - 2, r.position.y * 8 - 2, r.size.x * 8 + 4, r.size.y * 8 + 4):
					group_s[gi] = 1
					for c in room.groups[gi].cells:
						solid[c] = 0
					key_count -= 1
					for k in key_s.size():
						if key_s[k] == 1:
							key_s[k] = 2
							break
					events.append("door")
					if key_count == 0:
						break
	# Bells
	for i in bell_x.size():
		if bell_s[i] == 0 and _player_overlaps_px(bell_x[i] - 7, bell_y[i] - 7, 14, 14):
			bell_s[i] = 1
			events.append("bell:" + bell_cid[i])
	# Balloons
	if state != ST_BOOST:
		for i in balloon_x.size():
			if balloon_t[i] == 0 and _player_overlaps_px(balloon_x[i] - 6, balloon_y[i] - 6, 12, 12):
				state = ST_BOOST
				boost_idx = i
				boost_timer = F_BOOST
				balloon_t[i] = 1
				vx = 0.0
				vy = 0.0
				rx = 0.0
				ry = 0.0
				dashes = maxi(dashes, max_dashes)
				stamina = CLIMB_MAX_STAMINA
				x = balloon_x[i] - 4
				y = balloon_y[i] - 6
				events.append("balloon")
				break
	# Bumpers
	for i in bumper_x.size():
		if bumper_t[i] == 0:
			var pcx := x + 4.0
			var pcy := y + 5.5
			var dx := pcx - bumper_x[i]
			var dy := pcy - bumper_y[i]
			if dx * dx + dy * dy < 12.0 * 12.0:
				_bumper_launch(dx, dy)
				bumper_t[i] = F_BUMPER_COOLDOWN
	# Triggers
	for i in trigger_rects.size():
		var bit := 1 << i
		if trigger_fired & bit == 0:
			var r := trigger_rects[i]
			if _player_overlaps_px(r.position.x, r.position.y, r.size.x, r.size.y):
				trigger_fired |= bit
				events.append("trigger:" + trigger_keys[i])
	# End flag
	for r in end_rects:
		if _player_overlaps_px(r.position.x, r.position.y, r.size.x, r.size.y):
			end_reached = true
			_collect_held()
			events.append("end")
			return


func _touching_spikes() -> bool:
	var cx0 := maxi(x >> 3, 0)
	var cx1 := mini((x + PW - 1) >> 3, w - 1)
	var cy0 := maxi(y >> 3, 0)
	var cy1 := mini((y + PH - 1) >> 3, h - 1)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var t := cells[cy * w + cx]
			if t < RoomDef.SPIKE_UP or t > RoomDef.SPIKE_RIGHT:
				continue
			var ex := cx * 8
			var ey := cy * 8
			match t:
				RoomDef.SPIKE_UP:
					if vy >= 0.0 and _player_overlaps_px(ex, ey + 5, 8, 3):
						return true
				RoomDef.SPIKE_DOWN:
					if vy <= 0.0 and _player_overlaps_px(ex, ey, 8, 3):
						return true
				RoomDef.SPIKE_LEFT:
					if vx >= 0.0 and _player_overlaps_px(ex + 5, ey, 3, 8):
						return true
				RoomDef.SPIKE_RIGHT:
					if vx <= 0.0 and _player_overlaps_px(ex, ey, 3, 8):
						return true
	return false


func _refill_all() -> void:
	dashes = maxi(dashes, max_dashes)
	stamina = CLIMB_MAX_STAMINA


func _spring_up(top: int) -> void:
	y = top - PH
	ry = 0.0
	_refill_all()
	jump_grace = 0
	var_jump_timer = F_VAR_JUMP
	auto_jump = true
	dash_attack_timer = 0
	wall_slide_timer = F_WALL_SLIDE
	wall_boost_timer = 0
	ducking = false
	vx = 0.0 if state == ST_DASH else vx
	vy = SPRING_SPEED
	var_jump_speed = vy
	state = ST_NORMAL
	events.append("spring")


func _spring_side(dir: int) -> void:
	_refill_all()
	jump_grace = 0
	var_jump_timer = 0
	auto_jump = true
	dash_attack_timer = 0
	wall_slide_timer = F_WALL_SLIDE
	force_move_x = dir
	force_move_timer = F_SIDE_SPRING_FORCE
	wall_boost_timer = 0
	ducking = false
	vx = SIDE_SPRING_X * dir
	vy = minf(vy, SIDE_SPRING_Y)
	facing = dir
	state = ST_NORMAL
	events.append("spring")


func _bumper_launch(dx: float, dy: float) -> void:
	var l := sqrt(dx * dx + dy * dy)
	var nx := 0.0
	var ny := -1.0
	if l > 0.001:
		nx = dx / l
		ny = dy / l
	if ny <= 0.65 and ny >= -0.55:
		ny = 0.0
		nx = 1.0 if nx >= 0.0 else -1.0
	vx = BUMPER_SPEED * nx
	vy = BUMPER_SPEED * ny
	if vy <= 50.0:
		vy = minf(-150.0, vy)
		auto_jump = true
	if move_x != 0 and move_x == int(signf(vx)):
		vx *= 1.2
	_refill_all()
	state = ST_NORMAL
	var_jump_timer = 0
	dash_attack_timer = 0
	ducking = false
	events.append("bumper")


func _collect_held() -> void:
	for i in berry_s.size():
		if berry_s[i] == 1:
			berry_s[i] = 2
			events.append("berry:" + berry_cid[i])


func _check_bounds() -> void:
	var cxp := x + PW / 2
	var cyp := y + PH / 2
	var side := ""
	var along := 0
	if cxp < 0:
		side = "left"; along = clampi(cyp >> 3, 0, h - 1)
	elif cxp > w * 8:
		side = "right"; along = clampi(cyp >> 3, 0, h - 1)
	elif cyp < 0:
		side = "top"; along = clampi(cxp >> 3, 0, w - 1)
	elif y > h * 8:
		side = "bottom"; along = clampi(cxp >> 3, 0, w - 1)
	if side == "":
		return
	var t := room.exit_target(side, along)
	if t == "":
		if side == "bottom":
			_die()
		return
	exited = true
	exit_side = side
	exit_target = t
	_collect_held()
	events.append("exit")


func _update_chaser() -> void:
	chase_hist.append(x)
	chase_hist.append(y)
	var n := chase_hist.size() / 2
	if n <= chase_delay:
		return
	chase_active = true
	var i := (n - 1 - chase_delay) * 2
	var cxp := chase_hist[i]
	var cyp := chase_hist[i + 1]
	# Smaller hitbox than the player, so near misses feel fair.
	if not assist_invincible and absi(cxp - x) < 6 and absi(cyp - y) < 8:
		_die()


func chaser_pos() -> Vector2i:
	var n := chase_hist.size() / 2
	if n <= chase_delay:
		return Vector2i(-1000, -1000)
	var i := (n - 1 - chase_delay) * 2
	return Vector2i(chase_hist[i], chase_hist[i + 1])


func _die() -> void:
	if dead:
		return
	dead = true
	for i in berry_s.size():
		if berry_s[i] == 1:
			berry_s[i] = 0
	events.append("death")


# ======================================================================
# Zip movers (moving solids that carry and push the player)
# ======================================================================

func _riding_zip(i: int) -> bool:
	var zx := zip_px[i * 2]
	var zy := zip_px[i * 2 + 1]
	var zw := zip_w[i]
	var zh := zip_h[i]
	if state == ST_CLIMB:
		var fx := x + facing
		if fx < zx + zw and fx + PW > zx and y < zy + zh and y + PH > zy:
			return true
	if y + PH == zy and x < zx + zw and x + PW > zx and vy >= 0.0 and state != ST_DREAM:
		return true
	return false


static func _ease_sine_in(t: float) -> float:
	return -cos(t * PI * 0.5) + 1.0


func _update_zips() -> void:
	for i in zip_count:
		var ph := zip_phase[i]
		var nx := zip_px[i * 2]
		var ny := zip_px[i * 2 + 1]
		match ph:
			Z_IDLE:
				if _riding_zip(i):
					zip_phase[i] = Z_DELAY
					zip_timer[i] = F_ZIP_DELAY
					events.append("zip_start")
			Z_DELAY:
				zip_timer[i] -= 1
				if zip_timer[i] <= 0:
					zip_phase[i] = Z_FORWARD
					zip_timer[i] = 0
			Z_FORWARD:
				zip_timer[i] += 1
				var p := _ease_sine_in(float(zip_timer[i]) / F_ZIP_FORWARD)
				nx = int(roundf(lerpf(zip_sx[i], zip_tx[i], p)))
				ny = int(roundf(lerpf(zip_sy[i], zip_ty[i], p)))
				if zip_timer[i] >= F_ZIP_FORWARD:
					zip_phase[i] = Z_HOLD
					zip_timer[i] = F_ZIP_HOLD
					events.append("zip_hit")
			Z_HOLD:
				zip_timer[i] -= 1
				if zip_timer[i] <= 0:
					zip_phase[i] = Z_RETURN
					zip_timer[i] = 0
			Z_RETURN:
				zip_timer[i] += 1
				var p := _ease_sine_in(float(zip_timer[i]) / F_ZIP_RETURN)
				nx = int(roundf(lerpf(zip_tx[i], zip_sx[i], p)))
				ny = int(roundf(lerpf(zip_ty[i], zip_sy[i], p)))
				if zip_timer[i] >= F_ZIP_RETURN:
					zip_phase[i] = Z_COOLDOWN
					zip_timer[i] = F_ZIP_COOLDOWN
			Z_COOLDOWN:
				zip_timer[i] -= 1
				if zip_timer[i] <= 0:
					zip_phase[i] = Z_IDLE
		var dx := nx - zip_px[i * 2]
		var dy := ny - zip_px[i * 2 + 1]
		zip_vx[i] = dx * 60.0
		zip_vy[i] = dy * 60.0
		if dx != 0 or dy != 0:
			_move_solid(i, dx, dy)
			if dead:
				return


func _move_solid(i: int, dx: int, dy: int) -> void:
	var riding := _riding_zip(i)
	var zw := zip_w[i]
	var zh := zip_h[i]
	if dx != 0:
		zip_px[i * 2] += dx
		var zx := zip_px[i * 2]
		var zy := zip_px[i * 2 + 1]
		zip_ignore = i
		if x < zx + zw and x + PW > zx and y < zy + zh and y + PH > zy:
			# push
			var push := (zx + zw - x) if dx > 0 else (zx - (x + PW))
			if not _carry_x(push):
				zip_ignore = -1
				if not assist_invincible:
					_die()
					return
			_set_lift(i)
		elif riding:
			_carry_x(dx)
			_set_lift(i)
		zip_ignore = -1
	if dy != 0:
		zip_px[i * 2 + 1] += dy
		var zx := zip_px[i * 2]
		var zy := zip_px[i * 2 + 1]
		zip_ignore = i
		if x < zx + zw and x + PW > zx and y < zy + zh and y + PH > zy:
			var push := (zy + zh - y) if dy > 0 else (zy - (y + PH))
			if not _carry_y(push):
				zip_ignore = -1
				if not assist_invincible:
					_die()
					return
			_set_lift(i)
		elif riding:
			_carry_y(dy)
			_set_lift(i)
		zip_ignore = -1


func _set_lift(i: int) -> void:
	lift_vx = zip_vx[i]
	lift_vy = zip_vy[i]
	lift_timer = F_LIFT_GRACE


func _carry_x(m: int) -> bool:
	var s := 1 if m > 0 else -1
	while m != 0:
		if _collide(x + s, y):
			return false
		x += s
		m -= s
	return true


func _carry_y(m: int) -> bool:
	var s := 1 if m > 0 else -1
	while m != 0:
		if _collide(x, y + s):
			return false
		y += s
		m -= s
	return true


# ======================================================================
# Queries for rendering / tests
# ======================================================================

func snap_prev() -> void:
	prev_x = x
	prev_y = y
	prev_zip = zip_px.duplicate()
	prev_chaser = chaser_pos()


## Where to draw the player relative to the simulated position (zero when
## Smooth Motion is off, or when the frame lines up with a step).
func view_offset() -> Vector2:
	if view_alpha >= 1.0:
		return Vector2.ZERO
	return Vector2(prev_x - x, prev_y - y) * (1.0 - view_alpha)


func zip_view_pos(i: int) -> Vector2:
	var cur := Vector2(zip_px[i * 2], zip_px[i * 2 + 1])
	if view_alpha >= 1.0 or prev_zip.size() != zip_px.size():
		return cur
	return Vector2(prev_zip[i * 2], prev_zip[i * 2 + 1]).lerp(cur, view_alpha)


func chaser_view_pos() -> Vector2:
	var cur := Vector2(chaser_pos())
	if view_alpha >= 1.0 or prev_chaser.x <= -1000:
		return cur
	return Vector2(prev_chaser).lerp(cur, view_alpha)


func player_center() -> Vector2:
	return Vector2(x + PW * 0.5 + rx, y + PH * 0.5 + ry)


func is_climbing() -> bool:
	return state == ST_CLIMB


func berries_held() -> int:
	var n := 0
	for s in berry_s:
		if s == 1:
			n += 1
	return n
