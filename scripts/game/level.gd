class_name Level
extends Node2D
## Plays one chapter. Owns the World simulation and all the views, handles
## room transitions, death/respawn, cutscenes, collectibles and saving.
##
## `fast = true` (used by the end-to-end tests) skips every animation so the
## test can drive `sim_tick()` with recorded inputs as fast as possible.

const OPPOSITE := {"left": "right", "right": "left", "top": "bottom", "bottom": "top"}

var chapter_n := 0
var chapter: LevelDB.ChapterDef
var world := World.new()
var room: RoomDef
var room_id := ""

var stage: Node2D
var room_view: RoomView
var player_view: PlayerView
var grin_view: PlayerView
var effects: Effects
var backdrop: Backdrop
var hud: Hud
var dialogue: DialogueBox
var camera: Camera2D

var cam_center := Vector2(160, 90)
var look_ahead := Vector2.ZERO
var look_kick := Vector2.ZERO
var lighting: Lighting
var vignette: TextureRect
var post: PostFX
var shake := 0.0
var freeze := 0
var mode := "play"        # play | dead | respawn | transition | dialogue | complete
var paused := false
var timer := 0.0
var deaths_this_chapter := 0
var chapter_time := 0.0
var fast := false
var vis_hist := PackedInt32Array()
var trans: Dictionary = {}
var after_dialogue := ""
var events_log: Array = []      # test mode: collected ids, deaths, exits
var finished := false
var pending_script := ""
var death_burst_done := true
var script_delay := 0.0
var replay := PackedByteArray()  # optional scripted input (demo / screenshots)
var replay_pos := 0
var room_spawn := 0
# Route Ghost (assist): a silent, translucent Mira replaying the proven
# basic-moveset route for this room in a simulation of its own.
var ghost_world: World
var ghost_view: PlayerView
var ghost_grin: PlayerView      # the ghost's own chaser in chase rooms
var ghost_vis := PackedInt32Array()
var ghost_inputs := PackedByteArray()
var ghost_i := 0
var ghost_hold := 0
var ghost_mode_shown := "off"   # Game.ghost_mode() when she was last started
var ghost_goal := ""            # what she's running now: "exit", "collect" or "secret"
var room_deaths := 0
var nudged := {}
const GHOST_NUDGE_DEATHS := 10
static var _hints := {}
var full_run := true            # started at the chapter start in this session (may set Best)
var sim_acc := 0.0              # Game Speed: simulation steps owed (one per 1.0)
var tap_hold := 0               # jump / dash presses seen between two steps
var held_off := 0               # Jump / Dash still held from closing a menu or a cutscene: ignored until let go
var aiming := false             # Dash Aim: time is stopped while Dash is held
var aim_bits := 0               # direction bits she'll dash in (the last one held)
var aim_dash_down := false      # Dash held on the last tick, for the press edge
var aim_held := 0               # directions held on the last tick while aiming
var aim_drop := 0               # ticks a held direction has been let go (see AIM_GRACE)
const AIM_GRACE := 5            # a diagonal let go one key at a time stays diagonal this long
var aim_fire := -1              # input for the step that fires the aimed dash
var aim_view: Node2D
var best_info := {}             # record_best() at the chapter end, for the results screen


func _ready() -> void:
	chapter_n = Game.pending_chapter
	chapter = LevelDB.get_chapter(chapter_n)
	_build_nodes()
	Game.pad_disconnected.connect(_on_pad_disconnected)
	var start_room := Game.pending_room if Game.pending_room != "" else chapter.start
	_restore_resume(start_room)
	Game.release_grab()
	if not fast:
		# paint every room on worker threads; the first one is needed right away
		var first: RoomDef = chapter.rooms.get(start_room)
		if first:
			RoomView.prebake(first, str(first.meta.get("tileset", chapter.tileset)))
		for rid in chapter.order:
			var rd: RoomDef = chapter.rooms[rid]
			RoomView.prebake(rd, str(rd.meta.get("tileset", chapter.tileset)))
	_load_room(start_room, Game.pending_spawn if Game.pending_room != "" else 0)
	cam_center = _cam_target()
	if not fast:
		Game.update_refresh_rate()   # the window may have moved to another screen
		Game.apply_smooth_motion()
		if start_room == chapter.start:
			hud.show_title(chapter.name, Game.CHAPTER_TITLES[chapter_n] if chapter_n < Game.CHAPTER_TITLES.size() else "")
		Sfx.play_music(chapter.music)
		Sfx.play_ambience(AMBIENCE.get(chapter_n, ""))
		hud.wipe = 1.0
		hud.wipe_target = 0.0
		hud.wipe_dir = -1.0
	_on_room_enter()


## Continuing a chapter carries its time and deaths over from the save, so the
## results stay cumulative. Only runs started at the chapter start can set Best.
func _restore_resume(start_room: String) -> void:
	if start_room == chapter.start:
		return
	full_run = false
	var r: Dictionary = Game.data.get("resume", {})
	if int(r.get("chapter", -1)) == chapter_n and str(r.get("room", "")) == start_room:
		chapter_time = float(r.get("time", 0.0))
		deaths_this_chapter = int(r.get("deaths", 0))


const AMBIENCE := {
	0: "amb_meadow", 1: "amb_night", 2: "amb_dream", 3: "amb_carnival", 4: "amb_wind",
	5: "amb_hall", 6: "amb_cave", 7: "amb_wind", 8: "amb_meadow",
}


func _exit_tree() -> void:
	RoomView.flush_bakes()


func _notification(what: int) -> void:
	# auto-pause when the window loses focus mid-climb
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not fast and not Game.headless_test:
		auto_pause()


## Pause without a button press (focus lost, controller unplugged). Outside
## normal play (a death, a room transition, a cutscene) the pause waits until
## play resumes, so it can't be missed or land in the middle of a scene.
var pause_pending := false


func auto_pause() -> void:
	if fast or paused or (hud and hud.results) or mode == "complete":
		pause_pending = false   # already paused (or done): nothing left to catch up on
		return
	if mode != "play":
		pause_pending = true
		return
	pause_pending = false
	paused = true
	cancel_aim()
	hud.open_pause()


func _on_pad_disconnected() -> void:
	auto_pause()


func _build_nodes() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	backdrop = Backdrop.new()
	bg_layer.add_child(backdrop)
	backdrop.setup(chapter_n)

	stage = Node2D.new()
	add_child(stage)
	room_view = RoomView.new()
	stage.add_child(room_view)
	grin_view = PlayerView.new()
	grin_view.is_grin = true
	grin_view.world = world
	grin_view.visible = false
	stage.add_child(grin_view)
	var ghost_fx := Effects.new()
	ghost_fx.visible = false
	stage.add_child(ghost_fx)
	ghost_view = PlayerView.new()
	ghost_view.silent = true
	ghost_view.effects = ghost_fx
	ghost_view.visible = false
	ghost_view.modulate = Color(0.7, 0.9, 1.0, 0.5)
	stage.add_child(ghost_view)
	ghost_grin = PlayerView.new()
	ghost_grin.is_grin = true
	ghost_grin.world = world
	ghost_grin.visible = false
	ghost_grin.modulate = ghost_view.modulate
	stage.add_child(ghost_grin)
	player_view = PlayerView.new()
	player_view.world = world
	stage.add_child(player_view)
	effects = Effects.new()
	stage.add_child(effects)
	aim_view = Node2D.new()
	aim_view.draw.connect(_draw_aim)
	stage.add_child(aim_view)
	player_view.effects = effects
	lighting = Lighting.new()
	lighting.world = world
	lighting.player_view = player_view
	lighting.setup(chapter_n)
	stage.add_child(lighting)
	var motes_layer := CanvasLayer.new()   # Ultra's out-of-focus motes, in front of the room and under the post pass
	motes_layer.layer = 2
	add_child(motes_layer)
	var motes := Node2D.new()
	motes.draw.connect(func(): backdrop.draw_motes(motes))
	motes_layer.add_child(motes)
	backdrop.draw.connect(motes.queue_redraw)

	camera = Camera2D.new()
	camera.position = cam_center
	add_child(camera)
	camera.make_current()

	post = PostFX.new()
	add_child(post)
	post.setup(chapter_n)
	var vl := CanvasLayer.new()
	vl.layer = 4
	add_child(vl)
	vignette = TextureRect.new()
	vignette.texture = _vignette_texture()
	vignette.size = Vector2(320, 180)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate = Color(1, 1, 1, {0: 0.5, 1: 0.8, 2: 0.85, 3: 0.75, 4: 0.35, 5: 0.8, 6: 0.9, 7: 0.4, 8: 0.35}.get(chapter_n, 0.6))
	vl.add_child(vignette)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Hud.new()
	hud.level = self
	ui.add_child(hud)
	dialogue = DialogueBox.new()
	dialogue.level = self
	ui.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	hud.pause_choice.connect(_on_pause_choice)
	hud.results_closed.connect(_on_results_closed)
	hud.show_timer = bool(Game.settings.get("show_timer", false))


static func _vignette_texture() -> Texture2D:
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	for y in 180:
		for x in 320:
			var d := Vector2((x - 160.0) / 160.0, (y - 90.0) / 90.0).length()
			var a := clampf((d - 0.65) / 0.75, 0.0, 1.0)
			a = floorf(a * a * 8.0) / 8.0 * 0.55
			img.set_pixel(x, y, Color(0.03, 0.01, 0.06, a))
	return ImageTexture.create_from_image(img)


## Name of the character currently talking in a cutscene (for NPC animation).
func speaker() -> String:
	if mode == "dialogue" and dialogue.active and not dialogue.cur.is_empty():
		if dialogue.shown < dialogue._total_chars():
			return str(dialogue.cur.who)
	return ""


func _tileset() -> String:
	if room and room.meta.has("tileset"):
		return str(room.meta.tileset)
	if chapter.tileset != "":
		return chapter.tileset
	return Art.CHAPTER_TILESETS[clampi(chapter_n, 0, Art.CHAPTER_TILESETS.size() - 1)]


func _apply_assists() -> void:
	world.assist_invincible = bool(Game.settings.get("invincible", false))
	world.assist_infinite_stamina = bool(Game.settings.get("infinite_stamina", false))
	world.assist_air_dashes = Game.air_dashes()
	world.apply_dash_assist()


func _load_room(id: String, spawn: int, view: RoomView = null) -> void:
	room_id = id
	room = chapter.room(id)
	if room == null:
		push_error("Level: missing room " + id)
		return
	_apply_assists()
	world.load_room(room, spawn, chapter.dashes, Game.data.collected)
	room_spawn = spawn
	room_deaths = 0
	# Triggers whose scripts were already seen are pre-fired.
	world.trigger_fired = 0
	for i in world.trigger_keys.size():
		var sid := _trigger_script(world.trigger_keys[i])
		if sid == "" or Game.has_seen(sid):
			world.trigger_fired |= 1 << i
	var v := view if view else room_view
	v.level = self
	if lighting:
		lighting.room_view = v
	v.build(room, world, _tileset(), chapter_n)
	for n in str(room.meta.get("hidden", "")).split(",", false):
		if not Game.has_seen("show_" + room_id + "_" + n):
			v.npc_hidden[n.strip_edges()] = true
	player_view.reset_tails()
	player_view.trail.clear()
	player_view.visible_player = true
	player_view.override_frame = ""
	player_view.override_facing = 0
	vis_hist = PackedInt32Array()
	grin_view.visible = false
	_reset_ghost()
	Game.mark_reached(id)
	if not fast and not Game.headless_test:
		Game.data.resume = {"chapter": chapter_n, "room": id, "time": chapter_time, "deaths": deaths_this_chapter}
		Game.save()


func _trigger_script(key: String) -> String:
	for tok in str(room.meta.get("triggers", "")).split(" ", false):
		var p := tok.split(":")
		if p.size() == 2 and p[0] == key:
			return p[1]
	return ""


func _on_room_enter() -> void:
	if room == null:
		return
	if room.title != "" and not fast:
		hud.show_room_title(room.title)
	var enter := str(room.meta.get("enter", ""))
	if enter != "" and not Game.has_seen(enter):
		run_script(enter)
	if room.meta.has("music") and not fast:
		Sfx.play_music(str(room.meta.music))


# ---------------------------------------------------------------- cutscenes

func run_script(id: String) -> void:
	if not Story.has(id):
		push_warning("missing script " + id)
		Game.mark_seen(id)
		return
	Game.mark_seen(id)
	if fast:
		dialogue.play(id)
		dialogue.skip_all()
		return
	mode = "dialogue"
	if hud.title_text != "" and hud.title_t < hud.title_dur:
		# Let the chapter title card finish before the cutscene starts.
		pending_script = id
		script_delay = hud.title_dur - hud.title_t
		return
	dialogue.play(id)


func _on_dialogue_finished(_id: String) -> void:
	player_view.override_frame = ""
	if mode == "dialogue":
		mode = "play"
		_hold_off_buttons()
	if after_dialogue == "results":
		after_dialogue = ""
		_show_results()


func cutscene_command(cmd: String, args: Array) -> float:
	if dialogue.skipping and cmd in ["shake", "flash", "sfx"]:
		return 0.0   # a skipped scene shouldn't fire its effects all at once
	match cmd:
		"wait":
			return 0.0 if fast else float(args[0])
		"shake":
			shake = float(args[0]) if args.size() > 0 else 0.3
		"flash":
			hud.flash = 1.0
		"sfx":
			Sfx.play(str(args[0]))
		"music":
			Sfx.play_music(str(args[0]))
		"stop_music":
			Sfx.stop_music()
		"npc_hide":
			room_view.npc_hidden[str(args[0])] = true
		"npc_show":
			room_view.npc_hidden.erase(str(args[0]))
			Game.mark_seen("show_" + room_id + "_" + str(args[0]))
			if not fast:
				for e in room.entities:
					if e.type == "npc" and e.get("name", "") == str(args[0]):
						effects.burst(Vector2(e.cx * 8 + 4, e.cy * 8), Color("d8344f"), 12)
		"face":
			room_view.npc_face[str(args[0])] = int(args[1])
		"frame":
			player_view.override_frame = "" if str(args[0]) == "none" else str(args[0])
		"player_face":
			player_view.override_facing = int(args[0])
		"title":
			hud.show_room_title(" ".join(PackedStringArray(args)))
		"fade_out":
			hud.wipe_target = 1.0
			return 0.0 if fast else 0.6
		"fade_in":
			hud.wipe_target = 0.0
			return 0.0 if fast else 0.6
	return 0.0


# ---------------------------------------------------------------- main loop

func _physics_process(_delta: float) -> void:
	if fast:
		return
	if pause_pending and (paused or mode == "play"):
		auto_pause()
	if paused:
		_snap_views()
		sim_acc = 0.0
		return
	# Godot keeps ticking physics at 60 Hz whatever Engine.time_scale is (only
	# the delta shrinks), so Game Speed is applied here: at 50% the simulation
	# steps on every other tick. Presses that start and end between two steps
	# are carried to the next one so a quick tap isn't lost.
	var inp := Game.read_input()
	held_off &= inp
	inp &= ~held_off
	if _dash_aim(inp):
		return
	tap_hold |= inp & (World.IN_JUMP | World.IN_DASH)
	sim_acc += clampf(Engine.time_scale, 0.05, 1.0)
	if sim_acc < 1.0:
		return
	sim_acc -= 1.0
	_snap_views()
	inp |= tap_hold
	tap_hold = 0
	if mode == "play":
		if freeze > 0:
			freeze -= 1
			return
		if replay_pos < replay.size():
			inp = replay[replay_pos]
			replay_pos += 1
		elif aim_fire >= 0:
			inp = aim_fire
			aim_fire = -1
		sim_tick(inp)


## Assist > Dash Aim: a press of Dash that would start a dash stops time
## (no simulation steps, so no ghost, Grin or chapter timer either) and shows
## an arrow; held directions turn it, and letting go of Dash dashes the last
## way held (straight ahead if none). Keys of a diagonal are rarely let go on
## the same frame, so when a direction is let go the aim waits AIM_GRACE
## ticks before following what's still held. True while time is stopped.
func _dash_aim(inp: int) -> bool:
	var dash := (inp & World.IN_DASH) != 0
	var pressed := dash and not aim_dash_down
	aim_dash_down = dash
	var dirs := inp & (World.IN_LEFT | World.IN_RIGHT | World.IN_UP | World.IN_DOWN)
	if aiming:
		if dirs != 0 and ((dirs & ~aim_held) != 0 or dirs == aim_bits):
			aim_bits = dirs   # a new direction: follow it at once
			aim_drop = 0
		elif dirs != 0:
			aim_drop += 1     # one let go: follow after a moment
			if aim_drop > AIM_GRACE:
				aim_bits = dirs
		aim_held = dirs
		if dash and mode == "play":
			aim_view.queue_redraw()
			return true
		aiming = false
		aim_view.queue_redraw()
		if mode == "play":
			aim_fire = aim_bits | World.IN_DASH | (inp & (World.IN_JUMP | World.IN_GRAB))
		return false
	if pressed and bool(Game.settings.get("dash_aim", false)) and mode == "play" and not finished \
			and freeze == 0 and aim_fire < 0 and replay_pos >= replay.size() and world.dash_would_start(inp):
		aiming = true
		aim_bits = dirs
		aim_held = dirs
		aim_drop = 0
		sim_acc = 0.0
		_snap_views()
		Sfx.play("menu_move", 1.3, -6.0)
		aim_view.queue_redraw()
		return true
	return false


## Pausing (or a cutscene, death or room change) drops an aim without dashing.
func cancel_aim() -> void:
	aiming = false
	aim_fire = -1
	if aim_view:
		aim_view.queue_redraw()


## The Dash Aim arrow: eight ticks round Mira and a bright arrow for the
## way she'll dash.
func _draw_aim() -> void:
	if not aiming:
		return
	var c := _pc() + world.view_offset()
	var dx := (1 if aim_bits & World.IN_RIGHT else 0) - (1 if aim_bits & World.IN_LEFT else 0)
	var dy := (1 if aim_bits & World.IN_DOWN else 0) - (1 if aim_bits & World.IN_UP else 0)
	if dx == 0 and dy == 0:
		dx = world.facing
	var d := Vector2(dx, dy).normalized()
	var col := player_view.cap_col.lightened(0.55)
	var ink := Color(UIKit.INK, 0.9)
	for i in 8:
		var t := Vector2.RIGHT.rotated(i * PI / 4.0)
		if t.dot(d) < 0.99:
			aim_view.draw_line(c + t * 13.0, c + t * 16.0, Color(col, 0.45), 1.0)
	var pulse := 1.5 * sin(Time.get_ticks_msec() / 90.0)
	var tip := c + d * (24.0 + pulse)
	var side := Vector2(-d.y, d.x)
	var shaft_a := c + d * 11.0
	var shaft_b := tip - d * 6.0
	aim_view.draw_line(shaft_a, shaft_b, ink, 5.0)
	aim_view.draw_colored_polygon(PackedVector2Array([tip + d * 2.0, tip - d * 8.0 + side * 6.5, tip - d * 8.0 - side * 6.5]), ink)
	aim_view.draw_line(shaft_a, shaft_b, col, 3.0)
	aim_view.draw_colored_polygon(PackedVector2Array([tip, tip - d * 7.0 + side * 5.0, tip - d * 7.0 - side * 5.0]), col)


## Smooth Motion draws between this snapshot and the next step. Taken before
## every step (stepped or not), so anything that doesn't move holds still.
func _snap_views() -> void:
	world.snap_prev()
	if ghost_world:
		ghost_world.snap_prev()


## One fixed simulation step with the given input bits.
func sim_tick(inp: int) -> void:
	if mode != "play" or finished:
		return
	if freeze > 0 and not fast:
		freeze -= 1
		return
	world.step(inp)
	_ghost_tick()
	chapter_time += World.DT
	if room.chase_delay > 0:
		vis_hist.append(player_view.current_frame() * 2 + (1 if world.facing < 0 else 0))
	for ev in world.events:
		_handle_event(ev)
	if world.dead:
		_on_death()
	elif world.end_reached:
		_on_end()
	elif world.exited:
		_on_exit()


func _pc() -> Vector2:
	return world.player_center()


## Where Mira's centre is on the 320x180 screen (the pause Options panel
## opens on the other side).
func mira_screen_pos() -> Vector2:
	return player_view.get_global_transform_with_canvas() * world.player_center()


func _handle_event(ev: String) -> void:
	if fast:
		if ev.begins_with("berry:") or ev.begins_with("bell:"):
			var cid := ev.split(":", true, 1)[1]
			Game.collect(cid)
			events_log.append(ev)
		elif ev.begins_with("trigger:"):
			var sid := _trigger_script(ev.substr(8))
			if sid != "" and not Game.has_seen(sid):
				run_script(sid)
		return
	player_view.on_event(ev)
	var feet := Vector2(world.x + 4, world.y + 11)
	match ev:
		"jump":
			Sfx.play("jump")
			effects.dust(feet, 0.0, 4)
		"walljump", "wallbounce":
			Sfx.play("walljump")
			var wall := feet + Vector2(-world.facing * 5, -5)
			effects.dust(wall, world.facing, 5)
			effects.ring(wall, Color(1, 1, 1, 0.8), 8.0, 0.2)
			Game.rumble(0.15, 0.06)
		"super", "hyper":
			Sfx.play("jump", 0.85)
			effects.dust(feet, world.facing, 8)
			effects.ring(feet + Vector2(0, -3), player_view.cap_col.lightened(0.4), 14.0, 0.25)
			Game.rumble(0.3, 0.1)
		"land":
			Sfx.play("land", 1.0, -4.0)
			effects.land(feet, clampf(player_view.prev_vy / 200.0, 0.3, 1.2))
			if player_view.prev_vy > 180.0:
				Game.rumble(0.25, 0.07)
		"dash", "launch":
			Sfx.play("dash")
			freeze = 3
			_shake(0.12)
			effects.burst(_pc(), player_view.cap_col.lightened(0.2), 10, 60.0, 0.28)
			effects.ring(_pc(), player_view.cap_col.lightened(0.5), 18.0, 0.28)
			look_kick = Vector2(world.dash_dir_x, world.dash_dir_y) * 6.0
			post.pulse(0.6)
			Game.rumble(0.35, 0.12)
		"refill":
			Sfx.play("refill", 1.0, -6.0)
		"gem":
			Sfx.play("gem")
			effects.sparkle(_pc(), Color("8aff6e"), 10)
			effects.ring(_pc(), Color("aaffb0"), 16.0, 0.3)
			effects.burst(_pc(), Color("8aff6e"), 8, 50.0, 0.3)
			Game.rumble(0.2, 0.08)
		"spring":
			room_view.notify_spring()
			Sfx.play("spring")
			effects.ring(feet, Color("f2c14e"), 12.0, 0.25)
			effects.dust(feet, 0.0, 4)
			Game.rumble(0.4, 0.12)
		"bounce":   # Invincibility caught a fall or a curtain crash
			Sfx.play("spring", 1.2)
			effects.ring(_pc(), Color("b2e6ff"), 14.0, 0.3)
			effects.burst(_pc(), Color("b2e6ff"), 8, 50.0, 0.3)
			Game.rumble(0.3, 0.1)
		"crumble_back":
			pass
		"break":
			Sfx.play("break")
			_shake(0.2)
			effects.debris(Rect2(_pc() - Vector2(12, 12), Vector2(24, 24)), Color("8a7a6a"), 18)
			Game.rumble(0.6, 0.2)
		"mask":
			Sfx.play("mask", 1.0 if world.mask_active == 0 else 0.8)
		"balloon":
			Sfx.play("balloon")
			effects.ring(_pc(), Color("ff8a9a"), 12.0, 0.25)
		"bumper":
			Sfx.play("bumper")
			_shake(0.1)
			effects.ring(_pc(), Color("8ab4ff"), 20.0, 0.3)
			effects.burst(_pc(), Color("ffd27a"), 8, 70.0, 0.3)
			Game.rumble(0.45, 0.15)
		"zip_start":
			Sfx.play("zip_start")
		"zip_hit":
			Sfx.play("zip_hit")
			_shake(0.15)
			effects.burst(_pc() + Vector2(0, 8), Color("ffd27a"), 10, 80.0, 0.3)
			Game.rumble(0.5, 0.15)
		"dream_in":
			Sfx.play("curtain")
			effects.sparkle(_pc(), Color("ffd27a"), 8)
		"dream_out":
			Sfx.play("curtain", 1.3)
			effects.sparkle(_pc(), Color("fff0b0"), 10)
			effects.ring(_pc(), Color("fff0b0"), 14.0, 0.25)
		"key":
			Sfx.play("key")
			effects.sparkle(_pc(), Color("f2c14e"), 8)
		"door":
			Sfx.play("door")
			_shake(0.15)
			effects.debris(Rect2(_pc() - Vector2(8, 10), Vector2(16, 20)), Color("6b7390"), 10)
			Game.rumble(0.5, 0.2)
		"crumble":
			Sfx.play("crumble", 1.0, -3.0)
			effects.dust(feet + Vector2(0, 2), 0.0, 3, Color("c8a070"))
		"berry_touch":
			Sfx.play("berry_touch")
		"berry_flee":
			Sfx.play("flee")
		"golden_touch":
			Sfx.play("bell", 1.3)
		"grab":
			Sfx.play("grab", 1.0, -8.0)
		"climbhop":
			pass
		"tired":
			pass
		_:
			if ev.begins_with("berry:"):
				var cid := ev.split(":", true, 1)[1]
				var fresh := Game.collect(cid)
				Sfx.play("berry")
				effects.sparkle(_pc() + Vector2(0, -10), Color("ffd27a"), 14)
				effects.ring(_pc() + Vector2(0, -10), Color("ffd27a"), 18.0, 0.35)
				effects.popup(_pc() + Vector2(0, -18), "Sunberry!" if fresh else "Again!")
				hud.show_berry(Game.berries_in_chapter(chapter_n), chapter.berry_count())
				Game.rumble(0.3, 0.12)
				Game.save()
			elif ev.begins_with("bell:"):
				var cid := ev.split(":", true, 1)[1]
				Game.collect(cid)
				Sfx.play("bell")
				hud.flash = 1.0
				_shake(0.3)
				hud.show_title("A Jester Bell", "Nana's lost bell rings out", 3.0)
				effects.burst(_pc(), Color("ffd27a"), 20, 90.0, 0.8)
				Game.rumble(0.8, 0.4)
				Game.save()
			elif ev.begins_with("trigger:"):
				var sid := _trigger_script(ev.substr(8))
				if sid != "" and not Game.has_seen(sid):
					run_script(sid)


func _shake(amount: float) -> void:
	if bool(Game.settings.get("screen_shake", true)):
		shake = maxf(shake, amount)


func _on_death() -> void:
	mode = "dead"
	timer = 0.0
	deaths_this_chapter += 1
	Game.release_grab()
	Game.rumble(0.8, 0.3)
	if not Game.headless_test:
		Game.data.total_deaths = int(Game.data.total_deaths) + 1
		var cd := Game.chapter_data(chapter_n)
		cd.deaths = int(cd.deaths) + 1
	events_log.append("death")
	if fast:
		_respawn()
		return
	room_deaths += 1
	if room_deaths == GHOST_NUDGE_DEATHS and not bool(Game.settings.get("route_ghost", false)) and not nudged.has(room_id) and _hint(room_id, room_spawn).size() > 0:
		nudged[room_id] = true
		hud.show_room_title("Stuck? Pause > Assist > Route Ghost")
	Sfx.play("death")
	player_view.flash = 1.0
	player_view.flash_col = Color.WHITE
	player_view._kick(Vector2(0.5, -0.5))
	death_burst_done = false
	_shake(0.3)


func _respawn() -> void:
	if world.golden_held:
		world.golden_held = false
		_load_room(chapter.start, 0)
		hud.show_room_title("The Golden Sunberry slipped away...")
	else:
		world.reset_room()
		_apply_assists()
		_reset_ghost()
	vis_hist = PackedInt32Array()
	grin_view.visible = false
	player_view.reset_tails()
	player_view.trail.clear()
	if fast:
		mode = "play"
		return
	mode = "respawn"
	timer = 0.0
	Sfx.play("respawn", 1.0, -4.0)
	player_view.visible_player = false
	effects.respawn(_pc(), player_view.CAP_DASH)
	cam_center = _cam_target()


func _on_exit() -> void:
	var target := world.exit_target
	var side := world.exit_side
	var def2: RoomDef = chapter.room(target)
	events_log.append("exit:" + target)
	if def2 == null:
		push_error("Level: exit to unknown room " + target)
		mode = "complete"
		return
	var spawn := def2.spawn_for_side(OPPOSITE[side])
	if fast:
		_load_room(target, spawn)
		_on_room_enter()
		return
	var exit_feet := Vector2(world.x + 4, world.y + 11)
	var old_w := room.w * 8
	var old_h := room.h * 8
	var nv := RoomView.new()
	stage.add_child(nv)
	stage.move_child(nv, 0)
	var old_view := room_view
	_load_room(target, spawn, nv)
	room_view = nv
	var spawn_feet := Vector2(world.x + 4, world.y + 11)
	var origin := Vector2.ZERO
	match side:
		"right": origin = Vector2(old_w, exit_feet.y - spawn_feet.y)
		"left": origin = Vector2(-def2.w * 8, exit_feet.y - spawn_feet.y)
		"top": origin = Vector2(exit_feet.x - spawn_feet.x, -def2.h * 8)
		"bottom": origin = Vector2(exit_feet.x - spawn_feet.x, old_h)
	nv.position = origin
	var p0 := exit_feet - spawn_feet
	player_view.position = p0
	effects.clear_all()
	trans = {"t": 0.0, "dur": 0.45, "from": cam_center, "to": origin + _cam_target(), "origin": origin, "p0": p0, "old": old_view}
	mode = "transition"


func _finish_transition() -> void:
	var origin: Vector2 = trans.origin
	(trans.old as Node).queue_free()
	room_view.position = Vector2.ZERO
	player_view.position = Vector2.ZERO
	cam_center = trans.to - origin
	trans = {}
	mode = "play"
	_on_room_enter()


func _on_end() -> void:
	mode = "complete"
	finished = true
	events_log.append("end")
	var cd := Game.chapter_data(chapter_n)
	cd.complete = true
	best_info = record_best(cd)
	if world.golden_held:
		cd.golden = true
	Game.data.unlocked = maxi(int(Game.data.unlocked), chapter_n + 1)
	Game.data.resume = {}
	Game.save()
	if fast:
		return
	Sfx.play("complete")
	effects.confetti(_pc() + Vector2(0, -12), 70)
	hud.flash = 0.5
	_shake(0.15)
	Game.rumble(0.5, 0.3)
	var end_scene := str(chapter.meta.get("end_scene", ""))
	if end_scene != "" and Story.has(end_scene):
		after_dialogue = "results"
		Game.mark_seen(end_scene)
		mode = "dialogue"
		dialogue.play(end_scene)
	else:
		_show_results()


## Only runs from the chapter start set Best. Returns what the results screen
## says about it: whether this run counted, set a new Best, and the old Best.
func record_best(cd: Dictionary) -> Dictionary:
	var best := float(cd.best_time)
	var info := {"full_run": full_run, "new": false, "prev": best}
	if full_run and (best <= 0.0 or chapter_time < best):
		cd.best_time = chapter_time
		info.new = true
	return info


static func fmt_time(t: float) -> String:
	return "%d:%02d.%02d" % [int(t / 60.0), int(t) % 60, int(fmod(t, 1.0) * 100)]


func _show_results() -> void:
	mode = "complete"
	var t := chapter_time
	hud.show_results({
		"title": chapter.name,
		"subtitle": (Game.CHAPTER_TITLES[chapter_n] + " complete"),
		"berries": Game.berries_in_chapter(chapter_n),
		"berry_total": chapter.berry_count(),
		"deaths": deaths_this_chapter,
		"time": fmt_time(t),
		"best": best_info,
		"has_bell": chapter.has_bell(),
		"bell": Game.bell_in_chapter(chapter_n),
		"golden": world.golden_held,
	})


func _on_results_closed() -> void:
	if chapter_n == LevelDB.chapter_count() - 1:
		Game.goto_credits()
	else:
		Game.goto_chapter_select()


## Jump closes menus and reads cutscene lines, and Dash backs out of them
## (the pause screen offers it as Resume). The press that hands control back
## mustn't also make Mira jump or dash, so whatever is held now waits for a
## release before it counts.
func _hold_off_buttons() -> void:
	held_off = 0
	if Input.is_action_pressed("jump"):
		held_off |= World.IN_JUMP
	if Input.is_action_pressed("dash"):
		held_off |= World.IN_DASH


func _on_pause_choice(choice: String) -> void:
	match choice:
		"Resume":
			paused = false
			hud.close_pause()
			_hold_off_buttons()
		"Retry Room":
			paused = false
			hud.close_pause()
			_hold_off_buttons()
			if mode == "play":
				world._die()
				_on_death()
		"Restart Chapter":
			Game.save()
			Game.start_chapter(chapter_n)   # a fresh full run: Best and the golden berry count
		"Return to Map":
			Game.save()
			Game.goto_chapter_select()
		"assist_changed":
			_apply_assists()
			if Game.ghost_mode() != ghost_mode_shown:
				_reset_ghost()
			Engine.time_scale = float(Game.settings.game_speed)
			Game.apply_smooth_motion()


func _unhandled_input(ev: InputEvent) -> void:
	if fast:
		return
	if hud.handle_menu_input(ev):
		if is_inside_tree(): get_viewport().set_input_as_handled()
		return
	if mode == "dialogue" and dialogue.handle_input(ev):
		if is_inside_tree(): get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("pause") and mode != "complete":
		paused = true
		cancel_aim()
		hud.open_pause()
		Sfx.play("menu_select")
		if is_inside_tree(): get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- per-frame visuals

func _cam_target() -> Vector2:
	var pc := _pc() + world.view_offset() + look_ahead
	var w := room.w * 8.0
	var h := room.h * 8.0
	var tx := w / 2.0 if w <= 320.0 else clampf(pc.x, 160.0, w - 160.0)
	var ty := h / 2.0 if h <= 180.0 else clampf(pc.y, 90.0, h - 90.0)
	return Vector2(tx, ty)


func _process(delta: float) -> void:
	if fast:
		return
	# how far this frame is between the last two steps, in simulation steps
	var alpha := 1.0
	if Game.smooth_motion() and not paused:
		alpha = minf(sim_acc + Engine.get_physics_interpolation_fraction() * clampf(Engine.time_scale, 0.05, 1.0), 1.0)
	world.view_alpha = alpha
	if ghost_world:
		ghost_world.view_alpha = alpha
	if not paused:
		if pending_script != "":
			script_delay -= delta
			if script_delay <= 0.0:
				dialogue.play(pending_script)
				pending_script = ""
		match mode:
			"dead":
				timer += delta
				if not death_burst_done and timer > 0.1:
					death_burst_done = true
					var dp := _pc()
					dp.y = minf(dp.y, room.h * 8.0 - 10.0)
					effects.death(dp, player_view.cap_col)
					player_view.visible_player = false
					hud.flash = 0.35
				if timer > 0.5 and hud.wipe_target == 0.0:
					hud.wipe_dir = 1.0
					hud.wipe_speed = 4.0
					hud.wipe_target = 1.0
				if timer > 0.5 and hud.wipe >= 1.0:
					_respawn()
					hud.wipe_dir = -1.0
					hud.wipe_target = 0.0
			"respawn":
				timer += delta
				if timer > 0.35:
					player_view.visible_player = true
					player_view.reset_tails()
					player_view.flash = 1.0
					player_view._kick(Vector2(-0.4, 0.5))
					effects.ring(_pc(), Color.WHITE, 14.0, 0.25)
					mode = "play"
			"transition":
				trans.t += delta
				var k := clampf(trans.t / trans.dur, 0.0, 1.0)
				var e := ease(k, -2.0)
				cam_center = (trans.from as Vector2).lerp(trans.to, e)
				player_view.position = (trans.p0 as Vector2).lerp(trans.origin, e)
				if k >= 1.0:
					_finish_transition()
	if mode == "play" or mode == "dialogue" or mode == "respawn":
		var want := Vector2(clampf(world.vx * 0.12, -20.0, 20.0) + world.facing * 6.0, clampf(world.vy * 0.05, -8.0, 12.0)) + look_kick
		look_ahead = look_ahead.lerp(want, 1.0 - pow(0.02, delta))
		look_kick = look_kick.lerp(Vector2.ZERO, 1.0 - pow(0.001, delta))
		cam_center = cam_center.lerp(_cam_target(), 1.0 - pow(0.0005, delta))
	var off := Vector2.ZERO
	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		off = Vector2(randf_range(-2, 2), randf_range(-2, 2)) * minf(shake * 10.0, 2.0)
	camera.position = (cam_center + off).round()
	backdrop.cam_pos = cam_center
	lighting.position = room_view.position
	backdrop.wind = Vector2(world.wind_x, world.wind_y)
	hud.timer_value = chapter_time
	_update_grin()
	ghost_view.visible = ghost_world != null and mode in ["play", "dialogue"]
	_update_ghost_grin()
	_update_cutscene_pose(delta)


## Visual-only staging: Mira faces the NPC she talks to, animates while she
## speaks, and drops to the ground if the chapter ended mid-jump.
func _update_cutscene_pose(delta: float) -> void:
	player_view.talking = speaker() == "mira"
	var face := 0
	if mode == "dialogue" or (mode == "complete" and dialogue.active):
		var best := 1e9
		var pc := _pc()
		for e in room.entities:
			if e.type != "npc" or room_view.npc_hidden.has(e.get("name", "")):
				continue
			var nx: float = e.cx * 8 + 4
			var d := absf(nx - pc.x)
			if d < best and d < 120.0 and d > 2.0:
				best = d
				face = 1 if nx > pc.x else -1
	player_view.dialogue_facing = face
	if world.end_reached:
		# find the floor below the frozen player and fall onto it
		var floor_gap := 0
		while floor_gap < 96 and not world._collide(world.x, world.y + floor_gap + 1) and not world._jumpthru_below(world.x, world.y + floor_gap):
			floor_gap += 1
		if player_view.settle_y < floor_gap:
			player_view.settle_v = minf(player_view.settle_v + 600.0 * delta, 240.0)
			player_view.settle_y = minf(player_view.settle_y + player_view.settle_v * delta, floor_gap)
			if player_view.settle_y >= floor_gap and floor_gap > 0:
				player_view.settle_v = 0.0
				player_view._kick(Vector2(0.4, -0.35))
				effects.land(_pc() + Vector2(0, 5.5 + floor_gap), 0.6)
		else:
			player_view.settle_v = 0.0


# ---------------------------------------------------------------- route ghost

## A shipped route for a room and spawn: `goal` "exit" (the default), or for
## Berries mode "collect" (every berry and bell in the room) or "secret" (the
## way into a secret room off this one).
static func _hint(rid: String, spawn: int, chapter_key: String = "", goal: String = "exit") -> Dictionary:
	if _hints.is_empty() and FileAccess.file_exists("res://data/hints.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/hints.json"))
		if parsed is Dictionary:
			_hints = parsed
	var key := "%s:%d" % [rid, spawn] + ("" if goal == "exit" else ":" + goal)
	for ch in _hints:
		if chapter_key != "" and ch != chapter_key:
			continue
		var h: Dictionary = _hints[ch]
		if h.has(key):
			return h[key]
	return {}


## What the ghost runs in Berries mode: the room's collectibles while any is
## missing, then the way into a secret room that still holds something, then
## the exit. (Exit mode is always "exit".)
static func ghost_goal_for(ch: LevelDB.ChapterDef, chapter_key: String, rid: String, spawn: int, collected: Dictionary) -> String:
	var r: RoomDef = ch.room(rid)
	for cid in r.collectible_ids():
		if not collected.has(cid) and not _hint(rid, spawn, chapter_key, "collect").is_empty():
			return "collect"
	var sec := _hint(rid, spawn, chapter_key, "secret")
	if not sec.is_empty() and ch.room(str(sec.exit)) != null:
		for cid in ch.room(str(sec.exit)).collectible_ids():
			if not collected.has(cid):
				return "secret"
	return "exit"


## Restarts the ghost at the room's spawn (or removes it when the assist is off).
func _reset_ghost() -> void:
	ghost_world = null
	ghost_inputs = PackedByteArray()
	ghost_vis = PackedInt32Array()
	ghost_mode_shown = Game.ghost_mode()
	ghost_goal = ""
	if fast or ghost_view == null or room == null or ghost_mode_shown == "off":
		if ghost_view:
			ghost_view.visible = false
		return
	ghost_goal = "exit"
	if ghost_mode_shown == "berries":
		# chosen again every loop, so she moves on once the player has them
		ghost_goal = ghost_goal_for(chapter, str(chapter_n), room_id, room_spawn, Game.data.collected)
	var h := _hint(room_id, room_spawn, str(chapter_n), ghost_goal)
	if h.is_empty():
		ghost_view.visible = false
		return
	ghost_world = World.new()
	ghost_world.load_room(room, room_spawn, chapter.dashes)
	ghost_inputs = Solver.decode(str(h.inputs))
	ghost_i = 0
	ghost_hold = 0
	ghost_view.world = ghost_world
	ghost_view.reset_tails()
	ghost_view.trail.clear()
	ghost_view.visible = true


## Buttons the Route Ghost is holding this step (0 while she waits to loop).
func ghost_input() -> int:
	if ghost_world == null or ghost_hold > 0 or ghost_i <= 0:
		return 0
	return ghost_inputs[ghost_i - 1]


func _ghost_tick() -> void:
	if ghost_world == null:
		return
	if ghost_hold > 0:
		ghost_hold -= 1
		if ghost_hold == 0:
			_reset_ghost()
		return
	ghost_world.step(ghost_inputs[ghost_i])
	ghost_i += 1
	for ev in ghost_world.events:
		ghost_view.on_event(ev)
	if room.chase_delay > 0:
		ghost_vis.append(ghost_view.current_frame() * 2 + (1 if ghost_world.facing < 0 else 0))
	if ghost_world.dead or ghost_world.exited or ghost_world.end_reached or ghost_i >= ghost_inputs.size():
		ghost_hold = 45   # pause at the exit, then loop


func _update_grin() -> void:
	if room == null or room.chase_delay <= 0 or not world.chase_active or mode == "dead":
		grin_view.visible = false
		return
	var n := vis_hist.size()
	var i := n - 1 - room.chase_delay
	if i < 0:
		grin_view.visible = false
		return
	grin_view.visible = true
	grin_view.ghost_pos = world.chaser_view_pos()
	grin_view.ghost_frame = vis_hist[i] >> 1
	grin_view.ghost_flip = (vis_hist[i] & 1) == 1
	grin_view.position = player_view.position


## The Route Ghost's own Grin (chase rooms): replays her path, in her tint.
func _update_ghost_grin() -> void:
	var i := ghost_vis.size() - 1 - room.chase_delay if room else -1
	if not ghost_view.visible or room.chase_delay <= 0 or not ghost_world.chase_active or ghost_world.dead or i < 0:
		ghost_grin.visible = false
		return
	ghost_grin.visible = true
	ghost_grin.ghost_pos = ghost_world.chaser_view_pos()
	ghost_grin.ghost_frame = ghost_vis[i] >> 1
	ghost_grin.ghost_flip = (ghost_vis[i] & 1) == 1
	ghost_grin.position = player_view.position
