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
var replay := PackedByteArray()  # optional scripted input (demo / screenshots)
var replay_pos := 0


func _ready() -> void:
	chapter_n = Game.pending_chapter
	chapter = LevelDB.get_chapter(chapter_n)
	_build_nodes()
	var start_room := Game.pending_room if Game.pending_room != "" else chapter.start
	_load_room(start_room, 0)
	cam_center = _cam_target()
	if not fast:
		if start_room == chapter.start:
			hud.show_title(chapter.name, Game.CHAPTER_TITLES[chapter_n] if chapter_n < Game.CHAPTER_TITLES.size() else "")
		Sfx.play_music(chapter.music)
		hud.wipe = 1.0
		hud.wipe_target = 0.0
		hud.wipe_dir = -1.0
	_on_room_enter()


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
	player_view = PlayerView.new()
	player_view.world = world
	stage.add_child(player_view)
	effects = Effects.new()
	stage.add_child(effects)

	camera = Camera2D.new()
	camera.position = cam_center
	add_child(camera)
	camera.make_current()

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


func _tileset() -> String:
	if room and room.meta.has("tileset"):
		return str(room.meta.tileset)
	if chapter.tileset != "":
		return chapter.tileset
	return Art.CHAPTER_TILESETS[clampi(chapter_n, 0, Art.CHAPTER_TILESETS.size() - 1)]


func _apply_assists() -> void:
	world.assist_invincible = bool(Game.settings.get("invincible", false))
	world.assist_infinite_stamina = bool(Game.settings.get("infinite_stamina", false))


func _load_room(id: String, spawn: int, view: RoomView = null) -> void:
	room_id = id
	room = chapter.room(id)
	if room == null:
		push_error("Level: missing room " + id)
		return
	_apply_assists()
	world.load_room(room, spawn, chapter.dashes, Game.data.collected)
	# Triggers whose scripts were already seen are pre-fired.
	world.trigger_fired = 0
	for i in world.trigger_keys.size():
		var sid := _trigger_script(world.trigger_keys[i])
		if sid == "" or Game.has_seen(sid):
			world.trigger_fired |= 1 << i
	var v := view if view else room_view
	v.level = self
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
	if not fast and not Game.headless_test:
		Game.data.resume = {"chapter": chapter_n, "room": id}
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
	dialogue.play(id)


func _on_dialogue_finished(_id: String) -> void:
	player_view.override_frame = ""
	if mode == "dialogue":
		mode = "play"
	if after_dialogue == "results":
		after_dialogue = ""
		_show_results()


func cutscene_command(cmd: String, args: Array) -> float:
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
	if fast or paused:
		return
	if mode == "play":
		var inp := Game.read_input()
		if freeze > 0:
			freeze -= 1
			return
		if replay_pos < replay.size():
			inp = replay[replay_pos]
			replay_pos += 1
		sim_tick(inp)


## One fixed simulation step with the given input bits.
func sim_tick(inp: int) -> void:
	if mode != "play" or finished:
		return
	if freeze > 0 and not fast:
		freeze -= 1
		return
	world.step(inp)
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
			effects.dust(feet + Vector2(-world.facing * 4, -4), world.facing, 4)
		"super", "hyper":
			Sfx.play("jump", 0.85)
			effects.dust(feet, world.facing, 8)
		"land":
			Sfx.play("land", 1.0, -4.0)
			effects.dust(feet, 0.0, 5)
		"dash", "launch":
			Sfx.play("dash")
			freeze = 3
			_shake(0.12)
			effects.burst(_pc(), player_view.cap_col, 8, 50.0, 0.25)
		"refill":
			Sfx.play("refill", 1.0, -6.0)
		"gem":
			Sfx.play("gem")
			effects.sparkle(_pc(), Color("8aff6e"), 8)
		"spring":
			room_view.notify_spring()
			Sfx.play("spring")
		"crumble":
			Sfx.play("crumble", 1.0, -3.0)
		"crumble_back":
			pass
		"break":
			Sfx.play("break")
			_shake(0.2)
			effects.debris(Rect2(_pc() - Vector2(12, 12), Vector2(24, 24)), Color("8a7a6a"), 18)
		"key":
			Sfx.play("key")
		"door":
			Sfx.play("door")
			_shake(0.15)
		"mask":
			Sfx.play("mask", 1.0 if world.mask_active == 0 else 0.8)
		"balloon":
			Sfx.play("balloon")
		"bumper":
			Sfx.play("bumper")
			_shake(0.1)
		"zip_start":
			Sfx.play("zip_start")
		"zip_hit":
			Sfx.play("zip_hit")
			_shake(0.15)
		"dream_in":
			Sfx.play("curtain")
		"dream_out":
			Sfx.play("curtain", 1.3)
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
				effects.sparkle(_pc() + Vector2(0, -10), Color("ffd27a"), 10)
				effects.popup(_pc() + Vector2(0, -18), "Sunberry!" if fresh else "Again!")
				hud.show_berry(Game.berries_in_chapter(chapter_n), chapter.berry_count())
				Game.save()
			elif ev.begins_with("bell:"):
				var cid := ev.split(":", true, 1)[1]
				Game.collect(cid)
				Sfx.play("bell")
				hud.flash = 1.0
				_shake(0.3)
				hud.show_title("A Jester Bell", "Nana's lost bell rings out", 3.0)
				effects.burst(_pc(), Color("ffd27a"), 20, 90.0, 0.8)
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
	if not Game.headless_test:
		Game.data.total_deaths = int(Game.data.total_deaths) + 1
		var cd := Game.chapter_data(chapter_n)
		cd.deaths = int(cd.deaths) + 1
	events_log.append("death")
	if fast:
		_respawn()
		return
	Sfx.play("death")
	effects.death(_pc(), player_view.cap_col)
	player_view.visible_player = false
	_shake(0.3)


func _respawn() -> void:
	if world.golden_held:
		world.golden_held = false
		_load_room(chapter.start, 0)
		hud.show_room_title("The Golden Sunberry slipped away...")
	else:
		world.reset_room()
		_apply_assists()
	vis_hist = PackedInt32Array()
	grin_view.visible = false
	player_view.reset_tails()
	player_view.trail.clear()
	if fast:
		mode = "play"
		return
	mode = "respawn"
	timer = 0.0
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
	var best := float(cd.best_time)
	if best <= 0.0 or chapter_time < best:
		cd.best_time = chapter_time
	if world.golden_held:
		cd.golden = true
	Game.data.unlocked = maxi(int(Game.data.unlocked), chapter_n + 1)
	Game.data.resume = {}
	Game.save()
	if fast:
		return
	Sfx.play("complete")
	var end_scene := str(chapter.meta.get("end_scene", ""))
	if end_scene != "" and Story.has(end_scene):
		after_dialogue = "results"
		Game.mark_seen(end_scene)
		mode = "dialogue"
		dialogue.play(end_scene)
	else:
		_show_results()


func _show_results() -> void:
	mode = "complete"
	var t := chapter_time
	hud.show_results({
		"title": chapter.name,
		"subtitle": (Game.CHAPTER_TITLES[chapter_n] + " complete"),
		"berries": Game.berries_in_chapter(chapter_n),
		"berry_total": chapter.berry_count(),
		"deaths": deaths_this_chapter,
		"time": "%d:%02d.%02d" % [int(t / 60.0), int(t) % 60, int(fmod(t, 1.0) * 100)],
		"has_bell": chapter.has_bell(),
		"bell": Game.bell_in_chapter(chapter_n),
		"golden": world.golden_held,
	})


func _on_results_closed() -> void:
	if chapter_n == LevelDB.chapter_count() - 1:
		Game.goto_credits()
	else:
		Game.goto_chapter_select()


func _on_pause_choice(choice: String) -> void:
	match choice:
		"Resume":
			paused = false
			hud.close_pause()
		"Retry Room":
			paused = false
			hud.close_pause()
			if mode == "play":
				world._die()
				_on_death()
		"Return to Map":
			Game.save()
			Game.goto_chapter_select()
		"assist_changed":
			_apply_assists()
			Engine.time_scale = float(Game.settings.game_speed)


func _unhandled_input(ev: InputEvent) -> void:
	if fast:
		return
	if hud.handle_menu_input(ev):
		get_viewport().set_input_as_handled()
		return
	if mode == "dialogue" and dialogue.handle_input(ev):
		get_viewport().set_input_as_handled()
		return
	if ev.is_action_pressed("pause") and mode != "complete":
		paused = true
		hud.open_pause()
		Sfx.play("menu_select")
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- per-frame visuals

func _cam_target() -> Vector2:
	var pc := _pc()
	var w := room.w * 8.0
	var h := room.h * 8.0
	var tx := w / 2.0 if w <= 320.0 else clampf(pc.x, 160.0, w - 160.0)
	var ty := h / 2.0 if h <= 180.0 else clampf(pc.y, 90.0, h - 90.0)
	return Vector2(tx, ty)


func _process(delta: float) -> void:
	if fast:
		return
	if not paused:
		chapter_time += 0.0
		match mode:
			"dead":
				timer += delta
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
		cam_center = cam_center.lerp(_cam_target(), 1.0 - pow(0.0005, delta))
	var off := Vector2.ZERO
	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		off = Vector2(randf_range(-2, 2), randf_range(-2, 2)) * minf(shake * 10.0, 2.0)
	camera.position = (cam_center + off).round()
	backdrop.cam_pos = cam_center
	backdrop.wind = Vector2(world.wind_x, world.wind_y)
	hud.timer_value = chapter_time
	_update_grin()


func _update_grin() -> void:
	if room == null or room.chase_delay <= 0 or not world.chase_active or mode == "dead":
		grin_view.visible = false
		return
	var p := world.chaser_pos()
	var n := vis_hist.size()
	var i := n - 1 - room.chase_delay
	if i < 0:
		grin_view.visible = false
		return
	grin_view.visible = true
	grin_view.ghost_pos = Vector2(p)
	grin_view.ghost_frame = vis_hist[i] >> 1
	grin_view.ghost_flip = (vis_hist[i] & 1) == 1
	grin_view.position = player_view.position
