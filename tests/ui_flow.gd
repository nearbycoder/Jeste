extends Node
## Drives the real menus with simulated input and checks each screen is
## reached: title -> options -> chapter select -> level -> pause / options /
## assist -> map -> title, plus resume prompt, results and credits.
## godot --headless --path . res://tests/ui_flow.tscn
## Prints "UI FLOW PASS" or "UI FLOW FAIL: <step>" and exits 0 / 1.

var steps: Array = []
var idx := 0
var wait := 0
var failed := ""
var music_before := 0.0
var scroll_before := 0.0
var skip_id := ""
var speed_from := 0
var frames_btn := 0
var btn_last := {}
var btn_seen := 0
var frame := 0
var wait_frames := 0
var input_log: Array = []      # the last inputs that reached the scene, printed on a failure
var moves := {}                # jump / dash events the world fired since "watch_moves"


func _ready() -> void:
	# keep this driver alive across scene changes: hand "current scene" to a dummy
	var dummy := Node.new()
	get_tree().root.add_child.call_deferred(dummy)
	(func(): get_tree().current_scene = dummy).call_deferred()
	var game: Node = get_node("/root/Game")
	game.headless_test = true
	game.data = game.default_save()
	game.data.unlocked = 8
	game.settings = game.default_settings()   # whatever the machine's settings file says
	game.setup_input()
	var t := Timer.new()
	t.wait_time = 240.0
	t.one_shot = true
	t.timeout.connect(func(): _fail("watchdog timeout"))
	add_child(t)
	t.start()
	# [kind, arg, frames to wait afterwards]
	steps = [
		["scene", "res://scenes/main.tscn", 90],
		["expect", "Title", 0],
		["check", "helpers", 0],
		["check", "layout_names", 0],
		["check", "pad_hints", 0],
		["check", "ghost_parts", 0],
		["check", "ghost_items", 0],
		["check", "ghost_pickups", 0],
		["check", "ghost_goal", 0],
		["check", "air_dash_sim", 0],
		["check", "invincible_sim", 0],
		["check", "aim_probe_pure", 0],
		["check", "assist_help", 0],
		["check", "stick_sectors", 0],
		["check", "deadzone_sweep", 0],
		["check", "option_help", 0],
		["stick", "down", 6],                                     # one stick push = one row
		["check", "title_sel_1", 0],
		["stick", "up", 6],
		["check", "title_sel_0", 0],
		["stick_hold", "down", 4],                                # gameplay still sees a held stick
		["check", "held_down", 0],
		["stick_hold", "", 4],
		["press", "up", 6],
		["check", "title_sel_0", 0],
		["key", "Down", 2], ["check", "cursor_hidden", 0],      # the cursor hides on a key...
		["mouse", "", 2], ["check", "cursor_shown", 0],          # ...shows when the mouse moves...
		["wait_n", "100", 0], ["check", "cursor_shown", 0],
		["wait_n", "30", 0], ["check", "cursor_hidden", 0],     # ...and hides again after 2 s still
		["key", "Up", 6], ["check", "title_sel_0", 0],
		["key", "F11", 4], ["check", "fs_on_title", 0],         # F11 toggles fullscreen...
		["alt_enter", "", 4], ["check", "fs_off_title", 0],     # ...so does Alt+Enter, without choosing Climb
		["mouse_at", "60,116", 2], ["check", "title_sel_1", 0],  # pointing at a row selects it
		["click", "200,40", 6], ["check", "title_sel_1", 0], ["check", "main", 0],   # a click off the rows does nothing
		["click", "60,116", 20], ["check", "options", 0],        # a click confirms (Options)
		["click", "109,19", 4], ["check", "volume_music_0", 0],  # a click on a volume slider sets it there
		["click", "129,19", 4], ["check", "volume_music_5", 0],
		["click", "109,31", 4], ["check", "volume_sfx_0", 0],
		["click", "141,31", 4], ["check", "volume_sfx_8", 0],
		["click", "137,19", 4], ["check", "volume_music_7", 0],
		["click", "46,19", 4], ["check", "volume_music_8", 0],  # a click on the label still steps it
		["click", "137,19", 4], ["check", "volume_music_7", 0],
		["wheel", "137,19,up", 4], ["check", "volume_music_8", 0],     # the wheel over a slider steps it
		["wheel", "137,19,down", 4], ["check", "volume_music_7", 0],
		["mouse_at", "76,40", 2], ["wheel", "76,40,down", 4], ["check", "opt_sel_3", 0],   # elsewhere it moves the selection
		["mark_save", "", 0],
		["click", "76,139", 10], ["check", "erase_asks", 0],    # Erase Save asks...
		["click", "160,84", 6], ["check", "erase_asks", 0],      # ...a click off its prompts does nothing...
		["click_hint", "1", 6], ["check", "save_kept", 0],       # ...Keep keeps it
		["click", "76,139", 10], ["check", "erase_asks", 0],
		["rclick", "160,84", 6], ["check", "save_kept", 0],      # a right click keeps it too
		["click", "76,139", 10], ["click_hint", "0", 6], ["check", "save_erased", 0],   # Erase erases
		["unlock", "8", 0],
		["mouse_at", "76,40", 2], ["check", "opt_sel_2", 0],
		["rclick", "76,40", 10], ["check", "main", 0],          # a right click goes back
		["mouse_at", "60,102", 2], ["check", "title_sel_0", 0],
		["wheel", "60,102,down", 4], ["check", "title_sel_1", 0],          # the wheel moves the selection
		["wheel", "60,102,down,0.4", 2], ["wheel", "60,102,down,0.4", 2], ["check", "title_sel_1", 0],   # a touchpad's small
		["wheel", "60,102,down,0.4", 4], ["check", "title_sel_2", 0],      # scroll steps add up to one notch
		["wheel", "60,102,up", 4], ["wheel", "60,102,up", 4], ["check", "title_sel_0", 0],
		["press", "down", 6], ["press", "confirm", 20],          # Options
		["check", "options", 0],
		["hold", "dpad_down", 40], ["release", "dpad_down", 4],  # holding repeats
		["check", "repeated", 0], ["set_opt0", "", 2],
		["hold", "key_down", 40], ["release", "key_down", 4],
		["check", "repeated", 0], ["set_opt0", "", 2],
		["hold", "stick_down", 40], ["release", "stick_down", 4],
		["check", "repeated", 0], ["set_opt0", "", 2],
		["hold", "key_down", 2], ["release", "key_down", 30],    # a tap is one step, no repeats after release
		["check", "one_step", 0], ["set_opt0", "", 2],
		["mark_music", "", 0],
		["stick", "right", 6],                                    # one stick push = one slider step
		["check", "music_one_step", 0],
		["stick", "left", 6],
		["press", "right", 4], ["press", "down", 4], ["press", "left", 4],
		["press", "down", 4], ["press", "down", 4],              # Window Size
		["check", "window_auto", 0],
		["press", "right", 4], ["check", "window_2x", 0],
		["press", "left", 4], ["check", "window_auto", 0],
		["press", "down", 4], ["check", "fid_2", 0],             # Graphics Fidelity: High by default
		["press", "right", 4], ["check", "fid_3", 0], ["press", "right", 4], ["check", "fid_3", 0],   # Right stops at Ultra
		["press", "confirm", 4], ["check", "fid_0", 0],          # Confirm wraps to Low
		["press", "left", 4], ["check", "fid_0", 0],             # Left stops at Low
		["padbtn", "DPAD_RIGHT", 4], ["check", "fid_1", 0],      # the pad's D-pad steps it
		["wheel", "60,62,up", 4], ["check", "fid_2", 0],         # so does the wheel over the row
		["click", "110,62", 4], ["check", "fid_1", 0],           # a click on a meter bar sets that step
		["click", "118,62", 4], ["check", "fid_3", 0],           # (an order Confirm's wrap can't give)
		["click", "106,62", 4], ["check", "fid_0", 0],
		["click", "40,62", 4], ["check", "fid_1", 0],            # a click on the name steps it like Confirm
		["press", "right", 4], ["check", "fid_2", 0],
		["press", "down", 4], ["check", "smooth_auto", 0],       # Smooth Motion: Auto -> On -> Off -> Auto
		["press", "right", 4], ["check", "smooth_on", 0],
		["press", "right", 4], ["check", "smooth_off", 0],
		["press", "right", 4], ["check", "smooth_auto", 0],
		["press", "down", 4], ["press", "confirm", 4],           # toggles Screen Shake
		["press", "down", 4], ["press", "confirm", 4],           # Reduce Flashing
		["check", "reduced_flashing", 0],
		["press", "confirm", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Controls
		["check", "controls", 0],
		["press", "confirm", 6],                                  # rebind Jump
		["key", "N", 6],
		["check", "jump_is_n", 0],
		["press", "confirm", 6], ["key", "F11", 6], ["check", "jump_is_f11", 0],   # while rebinding, F11 is the new key
		["key", "F11", 6], ["check", "f11_is_jump", 0],          # bound to Jump, it's Jump (Select), not fullscreen
		["key", "Escape", 6], ["check", "jump_is_f11", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["check", "on_deadzone", 0],
		["check", "deadzone_40", 0], ["press", "right", 4], ["check", "deadzone_45", 0],   # Stick Deadzone: Right / Left step 5%...
		["press", "left", 4], ["press", "left", 4], ["check", "deadzone_35", 0],
		["wheel", "160,117,up", 4], ["check", "deadzone_40", 0],   # ...so does the wheel over the row...
		["set_deadzone", "0.7", 0], ["press", "confirm", 4], ["check", "deadzone_10", 0],   # ...and Confirm wraps from 70%
		["set_deadzone", "0.55", 0], ["press", "right", 4], ["check", "deadzone_60", 0],
		# a stick drifting to 0.5 below a 60% deadzone: no direction, the menu stays put
		["stick_rest", "0.5", 40], ["check", "on_deadzone", 0], ["check", "drift_still", 0],
		["stick_flick", "0.5", 4], ["check", "ctl_sel_9", 0],   # a full push still moves one row...
		["stick_flick", "0.5", 4], ["check", "ctl_sel_10", 0],  # ...and back at the drift, another push moves again
		["stick_rest", "0", 4], ["press", "up", 4], ["press", "up", 4], ["check", "on_deadzone", 0],
		["key", "F1", 2],                                        # (an unbound key puts prompts back on the keyboard)
		["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "jump_default", 0], ["check", "deadzone_60", 0], ["set_deadzone", "0.4", 0],   # Reset keeps the deadzone
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 6],   # rebind Jump on the pad
		["padbtn", "DPAD_UP", 6], ["check", "still_waiting", 0],  # D-pad can't be bound
		["padbtn", "X", 6],
		["check", "pad_jump_x", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],  # Reset
		["check", "pad_default", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["check", "on_grab_mode", 0],    # Grab Mode
		["press", "confirm", 4], ["check", "grab_toggle", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 6],          # Reset Defaults keeps it
		["check", "grab_mode_kept", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "right", 4], ["check", "grab_hold", 0],
		["mouse_at", "160,33", 2], ["check", "ctl_sel_1", 0],    # the mouse in Controls
		["wheel", "160,33,down", 4], ["check", "ctl_sel_2", 0], ["wheel", "160,33,up", 4], ["check", "ctl_sel_1", 0],
		["click", "160,33", 4], ["check", "ctl_waiting", 0],     # a click starts a rebind...
		["wheel", "160,33,down", 4], ["check", "ctl_waiting", 0],   # ...the wheel can't be bound or move it...
		["click", "160,33", 4], ["check", "ctl_waiting", 0],     # ...a mouse button can't be bound...
		["rclick", "160,33", 4], ["check", "ctl_cancelled", 0],  # ...a right click cancels it
		["click", "160,57", 4], ["check", "grab_toggle", 0],     # Grab Mode
		["click", "160,57", 4], ["check", "grab_hold", 0],
		["click", "160,4", 4], ["check", "ctl_cancelled", 0],   # a click off the rows does nothing
		["mouse_at", "160,117", 2], ["check", "on_deadzone", 0],   # the wheel over Stick Deadzone steps it
		["wheel", "160,117,down", 4], ["check", "deadzone_35", 0], ["wheel", "160,117,up", 4], ["check", "deadzone_40", 0],
		["check", "deadzone_dial", 0],
		["rclick", "160,57", 10], ["check", "options", 0],       # a right click closes the panel
		["click", "76,127", 10], ["check", "controls", 0],      # and a click on Controls opens it again
		["press", "back", 10],
		["press", "back", 20],
		["check", "main", 0],
		["press", "up", 6],                                      # Climb
		["press", "confirm", 90],
		["expect", "ChapterSelect", 0],
		["key", "F11", 6], ["check", "fs_on_cs", 0],            # fullscreen keys in chapter select
		["alt_enter", "", 6], ["check", "fs_off_cs", 0],
		["press", "left", 10], ["press", "right", 10],
		["press", "left", 10], ["press", "left", 10], ["press", "left", 10],
		["press", "left", 10], ["press", "left", 10], ["press", "left", 10], ["press", "left", 10],
		["press", "confirm", 120],                               # Chapter 1
		["expect", "Level", 0],
		["wait_dialogue", "", 20],
		["mark_line", "", 0], ["click", "160,90", 4], ["check", "line_advanced", 0],   # a click reads the next line
		["hold", "pause_key", 10], ["check", "skip_not_yet", 0],  # holding Esc skips the scene
		["hold_wait", "", 40],
		["release", "pause_key", 10],
		["check", "skipped", 0],
		["skip_dialogue", "", 60],
		["alt_enter", "", 6], ["check", "fs_on_play", 0],       # in play: Alt+Enter doesn't pause
		["key", "F11", 6], ["check", "fs_off_play", 0],
		["pad_lost", "", 6], ["check", "pad_paused", 0],         # an unplugged pad pauses the game
		["press", "pause", 10], ["check", "unpaused", 0],
		["pad_found", "", 6], ["check", "unpaused", 0],          # plugging one in doesn't
		["die", "", 2], ["pad_lost", "", 2], ["check", "pause_waits", 0],   # mid-death: pauses once play resumes
		["wait_play", "", 4], ["check", "pad_paused", 0],
		["press", "pause", 10], ["check", "unpaused", 0],
		["press", "pause", 20],
		["check", "paused", 0],
		["stick", "down", 4],
		["check", "pause_sel_1", 0],
		["stick", "up", 4],
		["mouse_at", "160,74", 2], ["check", "pause_sel_2", 0],  # the mouse in the pause menu
		["click", "160,74", 10], ["check", "assist", 0],
		["mouse_at", "160,123", 2], ["check", "assist_sel_5", 0],
		["wheel", "160,123,up", 6], ["check", "ghost_on", 0],    # the wheel steps Route Ghost under the pointer
		["wheel", "160,123,down", 6], ["check", "ghost_off", 0],
		["mouse_at", "160,110", 2], ["wheel", "160,110,down", 4], ["check", "assist_sel_5_not_invincible", 0],   # and moves past a toggle
		["rclick", "160,123", 10], ["check", "assist_closed", 0],
		["mouse_at", "160,46", 2], ["check", "pause_sel_0", 0],
		["wheel", "160,46,down", 4], ["check", "pause_sel_1", 0], ["wheel", "160,46,up", 4], ["check", "pause_sel_0", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["check", "assist", 0],
		["press", "down", 4], ["press", "down", 4], ["check", "on_air_dashes", 0],
		["press", "right", 4], ["check", "air_two", 0],          # Air Dashes: Two
		["press", "right", 4], ["check", "air_infinite", 0],
		["press", "right", 4], ["check", "air_infinite", 0],     # Right stops at the end...
		["press", "confirm", 4], ["check", "air_default", 0],    # ...Confirm wraps around
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],   # Route Ghost on
		["check", "ghost_on", 0],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "confirm", 4], ["press", "confirm", 4], ["press", "back", 10],
		["press", "down", 4], ["press", "confirm", 10],          # Options
		["check", "options_open", 0], ["check", "opt_layout", 0], ["check", "opt_layout_sweep", 0],   # the panel opens on the side away from Mira
		["opt_side", "240", 0],                                   # (Mira on the right: the steps below use the left-hand panel)
		["press", "right", 4], ["press", "left", 4],
		["press", "up", 4], ["press", "up", 4], ["check", "on_pause_controls", 0],   # Options > Controls, mid-climb
		["press", "confirm", 6], ["check", "pause_controls", 0],
		["press", "confirm", 6], ["key", "F11", 6], ["check", "pause_jump_f11", 0], # F11 can be bound here too
		["press", "confirm", 6], ["key", "M", 6], ["check", "pause_jump_m", 0],     # rebind Jump to M
		["press", "confirm", 6], ["key", "Escape", 6], ["check", "pause_jump_m", 0], # Esc cancels, still paused
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4],   # Grab Mode
		["check", "grab_toggle_paused", 0],
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "confirm", 6], ["check", "pause_reset", 0],                       # Reset Defaults
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "up", 4],
		["press", "confirm", 4], ["check", "grab_hold_paused", 0],
		["mouse_at", "160,33", 2], ["check", "pause_ctl_sel_1", 0],
		["rclick", "160,33", 6], ["check", "pause_controls_closed", 0],   # a right click closes Controls
		["click", "104,37", 4], ["check", "volume_sfx_0", 0],    # the pause menu's sliders take a click too
		["click", "135,37", 4], ["check", "volume_sfx_8", 0],
		["wheel", "135,37,down", 4], ["check", "volume_sfx_7", 0], ["wheel", "135,37,up", 4], ["check", "volume_sfx_8", 0],
		["opt_side", "80", 0],                                    # Mira on the left: the panel and its sliders on the right
		["click", "256,37", 4], ["check", "volume_sfx_0", 0], ["click", "287,37", 4], ["check", "volume_sfx_8", 0],
		["wheel", "287,37,down", 4], ["check", "volume_sfx_7", 0], ["wheel", "287,37,up", 4], ["check", "volume_sfx_8", 0],
		["click", "104,37", 4], ["check", "volume_sfx_8", 0],    # (where the slider was does nothing now)
		["click", "256,68", 4], ["check", "pause_fid_1", 0],     # Graphics in the pause menu: a click on a meter bar...
		["click", "264,68", 4], ["check", "pause_fid_3", 0],
		["click", "252,68", 4], ["check", "pause_fid_0", 0],     # ...and the level's post pass, backdrop and particles follow
		["wheel", "200,68,up", 4], ["check", "pause_fid_1", 0],
		["press", "right", 4], ["check", "pause_fid_2", 0],
		["mouse_at", "200,25", 2], ["check", "pause_opt_sel_0", 0],
		["press", "back", 10],
		["press", "up", 4], ["press", "up", 4], ["press", "up", 4], ["press", "confirm", 20],   # Resume
		["check", "unpaused", 0],
		["check", "ghost_running", 0],
		["wheel", "160,90,down", 4], ["wheel", "160,90,up", 4], ["check", "unpaused", 0],   # play ignores the wheel
		["ghost_buttons", "", 0],                                 # the HUD strip follows the ghost's inputs
		["speed", "0.5", 40], ["check", "half_speed", 0],        # Game Speed 50% = half the simulation steps
		["speed", "1.0", 40], ["check", "full_speed", 0],
		# the press that closes the pause menu doesn't also jump or dash
		["key_down", "Escape", 2], ["key_up", "Escape", 10], ["check", "paused", 0], ["check", "pause_time", 0],
		["check", "soften_full", 0],                              # the world blurs behind the pause menu...
		["watch_moves", "", 0], ["key_down", "C", 20], ["check", "unpaused", 0], ["key_up", "C", 10], ["check", "no_moves", 0],
		["check", "soften_off", 0],                               # ...and is sharp again in play
		["key_down", "Escape", 2], ["key_up", "Escape", 10], ["check", "paused", 0],
		["watch_moves", "", 0], ["key_down", "X", 20], ["check", "unpaused", 0], ["key_up", "X", 10], ["check", "no_moves", 0],
		["key_down", "Escape", 2], ["key_up", "Escape", 10], ["check", "paused", 0],   # on a pad, X (Dash) is the hint's Resume
		["watch_moves", "", 0], ["pad_down", "X", 20], ["check", "unpaused", 0], ["pad_up", "X", 10], ["check", "no_moves", 0],
		["key_down", "Escape", 2], ["key_up", "Escape", 10], ["check", "paused", 0],   # and Y (Jump) selects Resume
		["watch_moves", "", 0], ["pad_down", "Y", 20], ["check", "unpaused", 0], ["pad_up", "Y", 10], ["check", "no_moves", 0],
		["watch_moves", "", 0], ["key_down", "C", 4], ["key_up", "C", 40], ["check", "jumped", 0],   # a fresh press still jumps
		["dialogue_held", "", 20], ["check", "no_moves", 0], ["action_up", "jump", 10],   # nor does the last line of a cutscene
		["press", "pause", 20], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "down", 4],
		["press", "right", 4], ["check", "ghost_berries", 0],    # Route Ghost: Berries
		["press", "right", 4], ["check", "ghost_berries", 0],    # Right stops at the end...
		["press", "left", 4], ["check", "ghost_on", 0],          # ...Left goes back to Exit
		["press", "right", 4], ["press", "confirm", 4],          # Confirm wraps Berries -> Off
		["check", "ghost_off", 0],
		["press", "up", 4], ["press", "up", 4], ["check", "on_dash_aim", 0],
		["press", "right", 4], ["check", "dash_aim_on", 0],      # Dash Aim on
		["press", "back", 10], ["press", "back", 20],
		["check", "unpaused", 0],
		["wait_ground", "", 2],
		# Dash Aim: holding Dash stops time; she dashes the last way aimed on release
		["watch_moves", "", 0], ["key_down", "X", 2], ["check", "aiming", 0], ["mark_frame", "", 0],
		["key_down", "Up", 0], ["key_down", "Right", 20], ["check", "aim_frozen", 0],
		["key_up", "Up", 2], ["key_up", "Right", 1], ["check", "aim_frozen", 0],   # a diagonal let go one key at a time
		["key_up", "X", 3], ["check", "aim_dashed", 0],
		["key_down", "X", 2], ["check", "not_aiming", 0], ["key_up", "X", 2],   # no dash left: no aim
		["wait_ground", "", 2],
		["key_down", "X", 2], ["key_down", "Up", 0], ["key_down", "Right", 4], ["key_up", "Right", 10],   # a stick rolled to straight up
		["check", "aim_up", 0], ["key_up", "X", 3], ["check", "aim_dashed_up", 0], ["key_up", "Up", 0],
		["wait_ground", "", 2],
		["key_down", "X", 2], ["stick_at", "30,0.55", 6], ["check", "aim_up_right", 0],   # a stick half-pushed up-right aims up-right
		["key_up", "X", 3], ["check", "aim_dashed", 0], ["stick_at", "0,0", 2],
		["wait_ground", "", 2],
		["watch_moves", "", 0], ["key_down", "X", 2], ["check", "aiming", 0],   # pausing drops the aim
		["key_down", "Escape", 2], ["key_up", "Escape", 4], ["check", "paused_not_aiming", 0],
		["key_up", "X", 2], ["key_down", "Escape", 2], ["key_up", "Escape", 10], ["check", "no_moves", 0],
		["press", "pause", 20], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 10],   # Assist
		["press", "down", 4], ["press", "down", 4], ["press", "down", 4], ["press", "confirm", 4], ["check", "dash_aim_off", 0],
		["press", "back", 10], ["press", "back", 20], ["check", "unpaused", 0],
		["press", "pause", 20],
		["press", "up", 4], ["press", "confirm", 40],           # Retry Room (wraps to last = Return to Map? no: up from Resume = Return to Map)
		["expect", "ChapterSelect", 0],
		["seed_resume", "", 0],
		["press", "back", 60],
		["expect", "Title", 0],
		["check", "has_continue", 0],
		["press", "confirm", 120],                               # Continue
		["expect", "Level", 0],
		["check", "resumed", 0],
		["resume_end", "", 10],                                  # finishing a resumed run keeps Best
		["scene", "res://scenes/level.tscn", 60],
		["best_rows", "", 0],
		["results", "", 120],
		["click", "160,90", 90],                                 # a click continues from the results
		["expect", "ChapterSelect", 0],
		["check", "backfill", 0],                                # checkpoint select
		["seed_checkpoints", "", 0],
		["scene", "res://scenes/chapter_select.tscn", 60],
		["padbtn", "X", 60], ["expect", "Title", 0],              # pad X (the hint's Back) leaves chapter select
		["scene", "res://scenes/chapter_select.tscn", 60],
		["rclick", "160,10", 60], ["expect", "Title", 0],         # the mouse in chapter select: right click goes back
		["scene", "res://scenes/chapter_select.tscn", 60],
		["unlock", "5", 0], ["click_marker", "7", 6], ["check", "cs_sel_8", 0],   # a locked chapter can't be clicked
		["click_marker", "5", 6], ["check", "cs_sel_5", 0], ["wheel", "160,10,down", 6], ["check", "cs_sel_5", 0],   # nor wheeled to
		["unlock", "8", 0], ["click_marker", "3", 6], ["check", "cs_sel_3", 0],
		["click", "6,80", 6], ["check", "cs_sel_2", 0],          # the side arrows
		["click", "314,80", 6], ["check", "cs_sel_3", 0],
		["click", "160,10", 6], ["check", "cs_sel_3", 0],        # a click on nothing does nothing
		["click_marker", "1", 6], ["check", "cs_sel_1", 0],
		["wheel", "160,10,down", 6], ["check", "cs_sel_2", 0], ["wheel", "160,10,up", 6], ["check", "cs_sel_1", 0],   # the wheel steps chapters
		["click", "240,60", 10], ["check", "picker_open", 0],    # a click on the card chooses it
		["click_pip", "2", 6], ["check", "cp_sel_2", 0],         # a reached room's pip
		["wheel", "160,10,down", 6], ["check", "cp_sel_3", 0], ["wheel", "160,10,up", 6], ["check", "cp_sel_2", 0],   # and checkpoints
		["click_pip", "5", 6], ["check", "cp_sel_2", 0],         # an unreached one does nothing
		["click", "177,81", 6], ["check", "cp_sel_3", 0],        # the postcard's arrows
		["click", "19,81", 6], ["check", "cp_sel_2", 0],
		["rclick", "160,10", 6], ["check", "picker_closed", 0],
		["press", "confirm", 10], ["check", "picker_open", 0],
		["press", "right", 6], ["press", "right", 6], ["press", "right", 6], ["press", "right", 6],
		["check", "picker_last", 0],
		["wheel", "160,10,down", 6], ["check", "picker_last", 0],   # the wheel stops at the last one
		["press", "back", 6], ["check", "picker_closed", 0],
		["press", "confirm", 10], ["press", "right", 6], ["press", "right", 6],
		["click", "240,60", 120],                                # a click on the card starts there
		["expect", "Level", 0],
		["check", "from_checkpoint", 0],
		["press", "pause", 20], ["press", "up", 4], ["press", "up", 4],   # Restart Chapter
		["press", "confirm", 6], ["check", "restart_asks", 0],
		["wheel", "250,60,down", 4], ["check", "restart_asks", 0],   # the wheel does nothing here
		["mouse_at", "160,105", 2], ["check", "restart_yes", 0],        # the mouse picks a choice...
		["click", "160,75", 4], ["check", "restart_yes", 0],            # ...a click off them does nothing...
		["mouse_at", "160,93", 2], ["check", "restart_asks", 0],
		["rclick", "250,93", 10], ["check", "restart_kept", 0],         # ...a right click backs out
		["press", "confirm", 6], ["check", "restart_asks", 0],
		["press", "confirm", 10], ["check", "restart_kept", 0],          # "Keep climbing" is the default
		["press", "confirm", 6], ["press", "down", 4], ["check", "restart_yes", 0],
		["click", "160,105", 120],                                       # a click on Restart restarts
		["expect", "Level", 0],
		["check", "restarted", 0],
		["seed_continue", "", 0],                                # Continue from a secret room
		["scene", "res://scenes/chapter_select.tscn", 60],
		["press", "confirm", 10], ["check", "picker_continue", 0],
		["press", "confirm", 120],
		["expect", "Level", 0],
		["check", "continued", 0],
		["scene", "res://scenes/credits.tscn", 240],
		["expect", "Credits", 0],
		["mark_scroll", "", 0], ["wheel", "160,90,down", 2], ["check", "credits_ahead_40", 0],   # the wheel scrolls the credits
		["wheel", "160,90,up", 2], ["check", "credits_ahead_0", 0],
		["click", "160,90", 2], ["check", "credits_ahead_40", 0],   # a click skips ahead, as Confirm does
		["rclick", "160,90", 90], ["expect", "Title", 0],          # a right click leaves
		["done", "", 0],
	]


func _fail(msg: String) -> void:
	if failed == "":
		failed = msg
		print("UI FLOW FAIL: ", msg)
		var g: Node = get_node("/root/Game")
		print("  at frame %d; settings: window_scale=%s music=%s sfx=%s fullscreen=%s; using_pad=%s" % [frame,
			g.settings.get("window_scale"), g.settings.get("music"), g.settings.get("sfx"), g.settings.get("fullscreen"), g.using_pad])
		print("  last inputs (frame, step, event):")
		for l in input_log:
			print("    ", l)
		get_tree().quit(1)


## Records what reaches the scene (scripted presses, menu repeats, stick
## motion), so a failed check shows the inputs that led to it.
func _input(ev: InputEvent) -> void:
	var t := ""
	if ev is InputEventAction:
		t = "action %s %s" % [ev.action, "down" if ev.pressed else "up"]
	elif ev is InputEventKey:
		t = "key %s %s%s" % [OS.get_keycode_string(ev.physical_keycode), "down" if ev.pressed else "up", " echo" if ev.echo else ""]
	elif ev is InputEventJoypadButton:
		t = "pad button %d %s" % [ev.button_index, "down" if ev.pressed else "up"]
	elif ev is InputEventJoypadMotion:
		t = "pad axis %d %.2f" % [ev.axis, ev.axis_value]
	else:
		return
	input_log.append("%d, %d, %s" % [frame, idx, t])
	if input_log.size() > 40:
		input_log.pop_front()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _has_key(action: String, key: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == key:
			return true
	return false


func _pad_buttons(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	return out


func _scene() -> Node:
	return get_tree().current_scene


const PAD_STEP_BUTTONS := {"A": JOY_BUTTON_A, "B": JOY_BUTTON_B, "X": JOY_BUTTON_X, "Y": JOY_BUTTON_Y, "DPAD_UP": JOY_BUTTON_DPAD_UP, "DPAD_RIGHT": JOY_BUTTON_DPAD_RIGHT}


func _process(_d: float) -> void:
	frame += 1
	var lv := _scene()
	if lv and lv.name == "Level" and lv.world:
		for e in lv.world.events:
			if e in ["jump", "dash"]:
				moves[e] = true
	if failed != "":
		return
	if wait > 0:
		wait -= 1
		return
	if idx >= steps.size():
		return
	var s: Array = steps[idx]
	idx += 1
	wait = int(s[2])
	var cur := _scene()
	match s[0]:
		"scene":
			var game: Node = get_node("/root/Game")
			game.pending_chapter = 0
			game.pending_room = ""
			get_tree().change_scene_to_file(s[1])
		"expect":
			if cur == null or cur.name != s[1]:
				_fail("step %d: expected scene %s, got %s" % [idx, s[1], cur.name if cur else "none"])
		"press":
			_press(s[1])
		"stick":
			# a realistic push: the axis ramps through the deadzone, wobbles at
			# the rim, then springs back to centre
			var axis := JOY_AXIS_LEFT_Y if s[1] in ["up", "down"] else JOY_AXIS_LEFT_X
			var sgn := -1.0 if s[1] in ["up", "left"] else 1.0
			for v in [0.2, 0.35, 0.45, 0.6, 0.75, 0.9, 1.0, 0.95, 1.0, 0.6, 0.2, 0.0]:
				var ev := InputEventJoypadMotion.new()
				ev.device = 0
				ev.axis = axis
				ev.axis_value = v * sgn
				Input.parse_input_event(ev)
		"stick_hold":
			for v in ([0.3, 0.6, 0.9] if s[1] == "down" else [0.4, 0.1, 0.0]):
				var ev := InputEventJoypadMotion.new()
				ev.device = 0
				ev.axis = JOY_AXIS_LEFT_Y
				ev.axis_value = v
				Input.parse_input_event(ev)
		"hold", "release":
			var down: bool = s[0] == "hold"
			var ev: InputEvent
			match s[1]:
				"dpad_down":
					ev = InputEventJoypadButton.new()
					ev.button_index = JOY_BUTTON_DPAD_DOWN
					ev.pressed = down
				"pause_key":
					ev = InputEventKey.new()
					ev.physical_keycode = KEY_ESCAPE
					ev.keycode = KEY_ESCAPE
					ev.pressed = down
				"key_down":
					ev = InputEventKey.new()
					ev.physical_keycode = KEY_DOWN
					ev.keycode = KEY_DOWN
					ev.pressed = down
				"stick_down":
					ev = InputEventJoypadMotion.new()
					ev.axis = JOY_AXIS_LEFT_Y
					ev.axis_value = 1.0 if down else 0.0
			Input.parse_input_event(ev)
		"padbtn":
			var ev := InputEventJoypadButton.new()
			ev.button_index = PAD_STEP_BUTTONS[s[1]]
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate()
			up.pressed = false
			Input.parse_input_event.call_deferred(up)
		"pad_down", "pad_up":
			var ev := InputEventJoypadButton.new()
			ev.button_index = PAD_STEP_BUTTONS[s[1]]
			ev.pressed = s[0] == "pad_down"
			Input.parse_input_event(ev)
		"wait_dialogue":
			if not cur.dialogue.active:
				idx -= 1
				wait = 2
		"hold_wait":
			pass
		"ghost_buttons":
			# every frame for 150 frames: each button the ghost holds is fully lit,
			# each one she hasn't held for a while is dark
			cur.hud._process(0.0)    # this driver runs before the HUD in a frame
			var gi: int = cur.ghost_input()
			for b in [World.IN_UP, World.IN_DOWN, World.IN_LEFT, World.IN_RIGHT, World.IN_JUMP, World.IN_DASH, World.IN_GRAB]:
				var g: float = cur.hud._glow(b)
				if ((gi & b) and g < 1.0) or (not (gi & b) and b in btn_last and frames_btn - int(btn_last[b]) > 30 and g > 0.0):
					_fail("step %d: ghost button %d glow %.2f, held %s" % [idx, b, g, gi & b != 0])
				if gi & b:
					btn_last[b] = frames_btn
					btn_seen |= b
			frames_btn += 1
			if frames_btn < 150:
				idx -= 1
			elif btn_seen == 0:
				_fail("step %d: the ghost pressed nothing in 150 frames" % idx)
		"speed":
			get_node("/root/Game").settings.game_speed = float(s[1])
			Engine.time_scale = float(s[1])
			speed_from = cur.world.frame
		"pad_lost":
			# the pad in use, holding Right, goes away
			var g: Node = get_node("/root/Game")
			g.using_pad = true
			g.pad_device = 0
			Input.action_press("right")
			Input.joy_connection_changed.emit(0, false)
		"pad_found":
			Input.joy_connection_changed.emit(0, true)
		"die":
			cur.world._die()
			cur._on_death()
		"key_down", "key_up":
			var ev := InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(s[1])
			ev.keycode = ev.physical_keycode
			ev.pressed = s[0] == "key_down"
			Input.parse_input_event(ev)
		"opt_side":
			# lay the pause Options out for Mira at x (screen px), mid-height
			cur.hud.layout_options(Vector2(float(s[1]), 90.0))
			var want_x := 164.0 if float(s[1]) < 160.0 else 12.0
			if cur.hud.opt_x != want_x:
				_fail("step %d: Options panel at x %d for Mira at %s" % [idx, cur.hud.opt_x, s[1]])
		"set_deadzone":
			var g: Node = get_node("/root/Game")
			g.settings.stick_deadzone = float(s[1])
			g.apply_stick_deadzone()
		"stick_rest":
			# the left stick resting pushed down this far (a drifting stick)
			var ev := InputEventJoypadMotion.new()
			ev.device = 0
			ev.axis = JOY_AXIS_LEFT_Y
			ev.axis_value = float(s[1])
			Input.parse_input_event(ev)
		"stick_flick":
			# a quick full push down from the drift and back to it
			for v in [0.8, 1.0, 0.8, float(s[1])]:
				var ev := InputEventJoypadMotion.new()
				ev.device = 0
				ev.axis = JOY_AXIS_LEFT_Y
				ev.axis_value = v
				Input.parse_input_event(ev)
		"stick_at":
			var pa: PackedStringArray = str(s[1]).split(",")
			_stick(deg_to_rad(float(pa[0])), float(pa[1]))
		"watch_moves":
			moves = {}
		"mark_frame":
			speed_from = cur.world.frame
			scroll_before = cur.chapter_time
		"wait_ground":
			if not (cur.mode == "play" and cur.world.on_ground and cur.world.state == World.ST_NORMAL \
					and cur.world.dashes > 0) and wait_frames < 600:
				wait_frames += 1
				idx -= 1
			else:
				wait_frames = 0
		"dialogue_held":
			# Jump still down as a cutscene's last line closes
			Input.action_press("jump")
			cur.mode = "dialogue"
			cur._on_dialogue_finished("")
			moves = {}
		"action_up":
			Input.action_release(s[1])
		"wait_play":
			if cur.mode != "play" and wait_frames < 600:
				wait_frames += 1
				idx -= 1
		"mouse":
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(300, 5)   # off every menu
			ev.relative = Vector2(3, 1)
			Input.parse_input_event(ev)
		"mouse_at", "click", "rclick", "click_marker", "click_pip", "click_hint":
			# in the 320x180 canvas: a move there, then a press and release
			var xy: PackedStringArray = str(s[1]).split(",")
			var pos := Vector2(float(xy[0]), float(xy[1])) if xy.size() == 2 else Vector2.ZERO
			if s[0] == "click_marker":     # a chapter's marker on chapter select's trail
				pos = cur._marker_pos(int(s[1]))
			elif s[0] == "click_pip":      # a room's pip in the checkpoint picker
				pos = cur._pip_pos(int(s[1]), get_node("/root/Game").checkpoint_rooms(cur.sel).size())
			elif s[0] == "click_hint":     # a prompt in Erase Save's box, as UIKit.hints() lays it out
				var pairs: Array = cur._erase_hints()
				pos = cur._erase_hints_at() + Vector2(0, 4)
				for j in int(s[1]):
					pos.x += maxf(PixelText.width(str(pairs[j][0])) + 6.0, 9.0) + 3.0 + PixelText.width(str(pairs[j][1])) + 9.0
				pos.x += 8.0
			var evs: Array = []
			var m := InputEventMouseMotion.new()
			m.position = pos
			m.relative = Vector2(1, 0)
			evs.append(m)
			if s[0] != "mouse_at":
				for down in [true, false]:
					var b := InputEventMouseButton.new()
					b.position = pos
					b.button_index = MOUSE_BUTTON_RIGHT if s[0] == "rclick" else MOUSE_BUTTON_LEFT
					b.pressed = down
					evs.append(b)
			for e in evs:
				input_log.append("%d step %d mouse %s" % [frame, idx, e.as_text()])
				get_viewport().push_input(e, true)
		"wait_n":
			wait = int(s[1])
		"set_opt0":
			cur.opt_sel = 0
		"mark_scroll":
			scroll_before = cur.scroll
		"wheel":
			# "x,y,up|down[,factor]": one wheel notch (or a touchpad's partial
			# one) there, without moving the pointer
			var w: PackedStringArray = str(s[1]).split(",")
			for down in [true, false]:
				var b := InputEventMouseButton.new()
				b.position = Vector2(float(w[0]), float(w[1]))
				b.button_index = MOUSE_BUTTON_WHEEL_UP if w[2] == "up" else MOUSE_BUTTON_WHEEL_DOWN
				b.factor = float(w[3]) if w.size() > 3 else 1.0
				b.pressed = down
				input_log.append("%d step %d mouse %s" % [frame, idx, b.as_text()])
				get_viewport().push_input(b, true)
		"mark_music":
			music_before = float(get_node("/root/Game").settings.music)
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(s[1])
			ev.keycode = ev.physical_keycode
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate()
			up.pressed = false
			Input.parse_input_event.call_deferred(up)
		"check":
			var ok := true
			match s[1]:
				"options": ok = cur.screen == "options"
				"title_sel_1": ok = cur.sel == 1
				"opt_sel_2": ok = cur.screen == "options" and cur.opt_sel == 2
				"pause_sel_2": ok = cur.paused and cur.hud.pause_sel == 2 and not cur.hud.assist_open
				"pause_sel_0": ok = cur.paused and cur.hud.pause_sel == 0
				"assist_sel_5": ok = cur.hud.assist_open and cur.hud.assist_sel == 5
				"assist_closed": ok = cur.paused and not cur.hud.assist_open
				"reduced_flashing": ok = bool(get_node("/root/Game").settings.reduce_flashing) and is_equal_approx(get_node("/root/Game").flash_scale(), 0.2)
				"fid_0", "fid_1", "fid_2", "fid_3":   # the Graphics Fidelity row, at that step, and the title's post pass with it
					var want := int(str(s[1]).get_slice("_", 1))
					var pf: PostFX = _find_post(cur)
					ok = cur.OPTIONS[cur.opt_sel] == "Graphics" and get_node("/root/Game").fidelity() == want \
						and int(get_node("/root/Game").settings.fidelity) == want and pf != null and pf.fidelity == want and pf.rect.visible == (want > 0)
				"window_auto": ok = cur.OPTIONS[cur.opt_sel] == "Window Size" and int(get_node("/root/Game").settings.window_scale) == 0
				"smooth_auto": ok = cur.OPTIONS[cur.opt_sel] == "Smooth Motion" and str(get_node("/root/Game").settings.smooth_motion) == "auto" \
					and get_node("/root/Game").smooth_motion_label().begins_with("Auto")
				"smooth_on": ok = get_node("/root/Game").smooth_motion() and get_node("/root/Game").smooth_motion_label() == "On" \
					and is_zero_approx(Engine.physics_jitter_fix)
				"smooth_off": ok = not get_node("/root/Game").smooth_motion() and get_node("/root/Game").smooth_motion_label() == "Off"
				"window_2x": ok = int(get_node("/root/Game").settings.window_scale) == 2 and get_node("/root/Game").window_scale_label() == "2x"
				"title_sel_0": ok = cur.sel == 0
				"title_sel_2": ok = cur.sel == 2 and cur.screen == "main"
				"opt_sel_3": ok = cur.screen == "options" and cur.opt_sel == 3 and not bool(get_node("/root/Game").settings.fullscreen)
				"ctl_sel_2": ok = cur.screen == "controls" and cur.controls.sel == 2 and not cur.controls.waiting_key
				"assist_sel_5_not_invincible": ok = cur.hud.assist_open and cur.hud.assist_sel == 5 and not bool(get_node("/root/Game").settings.invincible)
				"credits_ahead_0", "credits_ahead_40":
					var ahead: float = cur.scroll - scroll_before
					var want := float(str(s[1]).get_slice("_", 2))
					ok = ahead >= want and ahead < want + 3.0
				"repeated": ok = cur.opt_sel >= 4 and cur.opt_sel <= 6
				"one_step": ok = cur.opt_sel == 1
				"still_waiting": ok = cur.controls.waiting_key and cur.controls.ITEMS[cur.controls.sel] == "jump"
				"pad_jump_x": ok = not Input.is_action_pressed("dash") and not cur.controls.waiting_key and _pad_buttons("jump") == [JOY_BUTTON_X] and _pad_buttons("dash").has(JOY_BUTTON_A) \
					and not _pad_buttons("dash").has(JOY_BUTTON_X) and get_node("/root/Game").pad_label("jump") == "X"
				"on_grab_mode": ok = cur.controls.ITEMS[cur.controls.sel] == "Grab Mode" and str(get_node("/root/Game").settings.grab_mode) == "hold"
				"grab_toggle": ok = str(get_node("/root/Game").settings.grab_mode) == "toggle" and _grab_reads() == [true, true, true, false, false, true, true, false]
				"grab_mode_kept": ok = cur.controls.ITEMS[cur.controls.sel] == "Reset Defaults" and str(get_node("/root/Game").settings.grab_mode) == "toggle"
				"grab_hold": ok = str(get_node("/root/Game").settings.grab_mode) == "hold" and _grab_reads() == [true, false, false, true, false, true, false, false]
				"pad_default": ok = _pad_buttons("jump") == [JOY_BUTTON_A, JOY_BUTTON_Y] and _pad_buttons("dash") == [JOY_BUTTON_X, JOY_BUTTON_B]
				"ghost_on": ok = bool(get_node("/root/Game").settings.route_ghost) and cur.ghost_world != null and cur.ghost_goal == "exit" \
					and get_node("/root/Game").ghost_mode() == "exit"
				"ghost_berries": ok = get_node("/root/Game").ghost_mode() == "berries" and cur.ghost_world != null and cur.room_id == "1-01" \
					and cur.ghost_goal == "collect" and cur.ghost_inputs == Solver.decode(str(Level._hint("1-01", 0, "1", "collect").inputs))
				"ghost_goal": ok = _ghost_goal_ok()
				"ghost_running": ok = cur.ghost_world != null and cur.ghost_view.visible and cur.ghost_i >= 5 and cur.ghost_world != cur.world
				"ghost_off": ok = not bool(get_node("/root/Game").settings.route_ghost) and cur.ghost_world == null and not cur.ghost_grin.visible \
					and cur.ghost_input() == 0
				"ghost_parts": ok = _ghost_parts_ok()
				"skip_not_yet":
					ok = cur.dialogue.active and cur.mode == "dialogue"
					skip_id = cur.dialogue.script_id
				"skipped": ok = not cur.dialogue.active and cur.mode == "play" and skip_id != "" and get_node("/root/Game").has_seen(skip_id) and not cur.paused
				"held_down": ok = Input.is_action_pressed("down") and cur.sel == 1
				"half_speed": ok = absi(cur.world.frame - speed_from - 20) <= 1 and cur.mode == "play"
				"full_speed": ok = absi(cur.world.frame - speed_from - 40) <= 1 and cur.mode == "play"
				"pause_sel_1": ok = cur.hud.pause_sel == 1
				"music_one_step": ok = is_equal_approx(float(get_node("/root/Game").settings.music), minf(music_before + 0.1, 1.0))
				"helpers":
					var g: Node = get_node("/root/Game")
					ok = g.pad_family("Xbox Series Controller") == "xbox" and g.pad_family("PS5 Controller") == "playstation" \
						and g.pad_family("Sony DualSense") == "playstation" and g.pad_family("Nintendo Switch Pro Controller") == "nintendo" \
						and g.pad_family("") == "xbox" and g.pad_button_name(JOY_BUTTON_A, "nintendo") == "B" \
						and g.pad_button_name(JOY_BUTTON_X, "playstation") == "Square" and g.pad_label("grab") == "RB" \
						and g.fit_scales(Vector2i(3840, 2160)) == [11, 9] and g.fit_scales(Vector2i(1920, 1080)) == [5, 4] \
						and g.fit_scales(Vector2i(1366, 768)) == [4, 3] and g.fit_scales(Vector2i(2560, 1440)) == [7, 6] \
						and g.fit_scales(Vector2i(800, 600)) == [2, 2] and g.fit_scales(Vector2i(500, 300)) == [1, 1] \
						and g.smooth_wanted("auto", 144.0, 1.0) and g.smooth_wanted("auto", 165.0, 1.0) and g.smooth_wanted("auto", 75.0, 1.0) \
						and not g.smooth_wanted("auto", 60.0, 1.0) and not g.smooth_wanted("auto", 119.98, 1.0) and not g.smooth_wanted("auto", 59.94, 1.0) \
						and not g.smooth_wanted("auto", 240.0, 1.0) and not g.smooth_wanted("auto", -1.0, 1.0) and g.smooth_wanted("auto", 60.0, 0.5) \
						and g.smooth_wanted("on", 60.0, 1.0) and not g.smooth_wanted("off", 144.0, 0.5)
				"layout_names": ok = _layout_names_ok()
				"pad_hints": ok = _pad_hints_ok()
				"controls": ok = cur.screen == "controls"
				"jump_is_n": ok = get_node("/root/Game").key_label("jump") == "N"
				"jump_default": ok = get_node("/root/Game").key_label("jump") == "C"
				"main": ok = cur.screen == "main"
				"paused": ok = cur.paused and cur.hud.paused
				"air_dash_sim": ok = _air_dashes_ok()
				"invincible_sim": ok = _invincible_ok()
				"aim_probe_pure": ok = _aim_probe_pure_ok()
				"assist_help": ok = _assist_help_ok()
				"stick_sectors": ok = _stick_sectors_ok()
				"pause_time": ok = _pause_time_ok(cur)
				"option_help": ok = _option_help_ok()
				"on_air_dashes": ok = cur.hud.assist_open and cur.hud.assist_items[cur.hud.assist_sel] == "Air Dashes"
				"air_two": ok = str(get_node("/root/Game").settings.air_dashes) == "two" and cur.world.assist_air_dashes == World.AIR_DASHES_TWO \
					and cur.room_id == "1-01" and cur.world.max_dashes == 2
				"air_infinite": ok = str(get_node("/root/Game").settings.air_dashes) == "infinite" and cur.world.assist_air_dashes == World.AIR_DASHES_INFINITE
				"air_default": ok = str(get_node("/root/Game").settings.air_dashes) == "default" and cur.world.assist_air_dashes == World.AIR_DASHES_DEFAULT
				"on_pause_controls": ok = cur.hud.options_open and cur.hud.option_items[cur.hud.option_sel] == "Controls"
				"pause_controls": ok = cur.paused and cur.hud.controls_open and cur.hud.controls.sel == 0 and not cur.hud.controls.waiting_key
				"pause_jump_m": ok = cur.paused and cur.hud.controls_open and not cur.hud.controls.waiting_key \
					and get_node("/root/Game").kb_label("jump") == "M" and _has_key("jump", KEY_M) and not _has_key("jump", KEY_C)
				"grab_toggle_paused": ok = cur.hud.controls.ITEMS[cur.hud.controls.sel] == "Grab Mode" and str(get_node("/root/Game").settings.grab_mode) == "toggle"
				"pause_reset": ok = cur.hud.controls.ITEMS[cur.hud.controls.sel] == "Reset Defaults" and get_node("/root/Game").kb_label("jump") == "C" \
					and _has_key("jump", KEY_C) and str(get_node("/root/Game").settings.grab_mode) == "toggle"
				"grab_hold_paused": ok = str(get_node("/root/Game").settings.grab_mode) == "hold"
				"pause_controls_closed": ok = cur.paused and cur.hud.options_open and not cur.hud.controls_open
				"cursor_hidden": ok = get_node("/root/Game").cursor_hidden
				"cursor_shown": ok = not get_node("/root/Game").cursor_hidden
				"pad_paused": ok = cur.paused and cur.hud.paused and cur.mode == "play" and not get_node("/root/Game").using_pad \
					and not Input.is_action_pressed("right") and not cur.pause_pending
				"pause_waits": ok = not cur.paused and cur.pause_pending and cur.mode == "dead"
				"assist": ok = cur.hud.assist_open
				"options_open": ok = cur.hud.options_open
				"unpaused": ok = not cur.paused
				"no_moves": ok = moves.is_empty() and not cur.paused and cur.mode == "play"
				"on_dash_aim": ok = cur.hud.assist_open and cur.hud.assist_items[cur.hud.assist_sel] == "Dash Aim"
				"dash_aim_on": ok = bool(get_node("/root/Game").settings.dash_aim)
				"dash_aim_off": ok = not bool(get_node("/root/Game").settings.dash_aim) and cur.hud.assist_items[cur.hud.assist_sel] == "Dash Aim"
				"aiming": ok = cur.aiming and moves.is_empty() and cur.aim_view.visible
				"aim_frozen": ok = cur.aiming and cur.world.frame == speed_from and is_equal_approx(cur.chapter_time, scroll_before) \
					and cur.aim_bits == (World.IN_UP | World.IN_RIGHT) and moves.is_empty()
				"aim_dashed": ok = not cur.aiming and moves.has("dash") and cur.world.dash_dir_x == 1 and cur.world.dash_dir_y == -1
				"not_aiming": ok = not cur.aiming
				"aim_up": ok = cur.aiming and cur.aim_bits == World.IN_UP
				"aim_up_right": ok = cur.aiming and cur.aim_bits == (World.IN_UP | World.IN_RIGHT)
				"aim_dashed_up": ok = not cur.aiming and cur.world.dash_dir_x == 0 and cur.world.dash_dir_y == -1 and cur.world.state == World.ST_DASH
				"paused_not_aiming": ok = cur.paused and not cur.aiming
				"jumped": ok = moves.has("jump")
				"resumed": ok = cur.chapter_n == 1 and cur.room_id == "1-02" and cur.chapter_time >= 100.0 and cur.deaths_this_chapter == 7 and not cur.full_run
				"has_continue": ok = cur.items.size() > 0 and cur.items[0] == "Continue" and cur.sel == 0
				"backfill": ok = _backfill_ok()
				"restart_asks": ok = cur.paused and cur.hud.confirm_restart and cur.hud.restart_sel == 0
				"restart_kept": ok = cur.paused and not cur.hud.confirm_restart and cur.room_id == "1-03" and cur.hud.pause_items[cur.hud.pause_sel] == "Restart Chapter"
				"restart_yes": ok = cur.hud.confirm_restart and cur.hud.restart_sel == 1
				"restarted": ok = cur.chapter_n == 1 and cur.room_id == "1-01" and cur.full_run and cur.chapter_time < 5.0 and cur.deaths_this_chapter == 0 and not cur.paused
				"picker_open": ok = cur.sel == 1 and cur.picking and Array(cur.cp_rooms) == ["1-01", "1-02", "1-03", "1-04"] and cur.cp_sel == 0
				"picker_last": ok = cur.picking and cur.cp_sel == 3
				"picker_closed": ok = not cur.picking and cur.leaving < 0
				"from_checkpoint": ok = cur.chapter_n == 1 and cur.room_id == "1-03" and not cur.full_run and cur.chapter_time < 5.0 and cur.deaths_this_chapter == 0
				"picker_continue": ok = cur.sel == 1 and cur.picking and Array(cur.cp_rooms) == ["1-01", "1-02", "1-03", "1-04", "1-05", "1-05s"] and cur.cp_sel == 5
				"continued": ok = cur.room_id == "1-05s" and cur.chapter_time >= 50.0 and cur.deaths_this_chapter == 3 and not cur.full_run
			var gm: Node = get_node("/root/Game")
			match s[1]:
				"erase_asks": ok = cur.screen == "confirm_reset" and int(gm.data.total_deaths) == 7
				"save_kept": ok = cur.screen == "options" and int(gm.data.total_deaths) == 7
				"save_erased": ok = cur.screen == "options" and int(gm.data.total_deaths) == 0 and int(gm.data.unlocked) == 0
				"ctl_sel_1": ok = cur.screen == "controls" and cur.controls.sel == 1 and not cur.controls.waiting_key
				"ctl_sel_9", "ctl_sel_10": ok = cur.screen == "controls" and cur.controls.sel == int(str(s[1]).get_slice("_", 2))
				"on_deadzone": ok = cur.screen == "controls" and cur.controls.ITEMS[cur.controls.sel] == "Stick Deadzone"
				"deadzone_10", "deadzone_35", "deadzone_40", "deadzone_45", "deadzone_60":
					var pct := int(str(s[1]).get_slice("_", 1))
					ok = is_equal_approx(gm.stick_deadzone(), pct / 100.0) and cur.controls.value_label("Stick Deadzone") == "%d%%" % pct
				"drift_still": ok = gm.read_input() & (World.IN_LEFT | World.IN_RIGHT | World.IN_UP | World.IN_DOWN) == 0 \
					and not Input.is_action_pressed("down") and is_equal_approx(gm.stick_vector(0).y, 0.5)
				"deadzone_dial": ok = _deadzone_dial_ok(cur.controls)
				"deadzone_sweep": ok = _deadzone_sweep_ok()
				"opt_layout": ok = _opt_layout_ok(cur)
				"opt_layout_sweep": ok = _opt_layout_sweep_ok(cur)
				"pause_fid_0", "pause_fid_1", "pause_fid_2", "pause_fid_3":
					var want := int(str(s[1]).get_slice("_", 2))
					var dens: float = Effects.DENSITY[want]
					ok = cur.paused and cur.hud.options_open and cur.hud.option_items[cur.hud.option_sel] == "Graphics" \
						and get_node("/root/Game").fidelity() == want and cur.post.fidelity == want and cur.post.rect.visible == (want > 0) \
						and cur.backdrop.fidelity == want and cur.backdrop.ambient.size() == (120 if want == 3 else Backdrop.AMBIENT_N[want]) \
						and cur.backdrop.motes.is_empty() == (want < 3) and is_equal_approx(dens, [0.5, 0.75, 1.0, 1.5][want]) \
						and (cur.room_view.shadow_tex != null) == (want == 3) \
						and is_equal_approx(cur.post.soften, 0.4 if want > 0 else 0.0)   # less blur under Options, none at Low
				"soften_full": ok = cur.post.fidelity >= 1 and is_equal_approx(cur.post.soften, 1.0) and is_equal_approx(float(cur.post.mat.get_shader_parameter("soften")), 1.0)
				"soften_off": ok = cur.post.soften == 0.0 and float(cur.post.mat.get_shader_parameter("soften")) == 0.0
				"pause_opt_sel_0": ok = cur.paused and cur.hud.options_open and cur.hud.option_sel == 0
				"ctl_waiting": ok = cur.screen == "controls" and cur.controls.sel == 1 and cur.controls.waiting_key and gm.kb_label("dash") == "X"
				"ctl_cancelled": ok = cur.screen == "controls" and not cur.controls.waiting_key and gm.kb_label("dash") == "X"
				"pause_ctl_sel_1": ok = cur.hud.controls_open and cur.hud.controls.sel == 1
				"ghost_items": ok = _ghost_items_ok()
				"ghost_pickups": ok = _ghost_pickups_ok()
				"fs_on_title", "fs_off_title":
					ok = bool(gm.settings.fullscreen) == (s[1] == "fs_on_title") and cur.screen == "main" and cur.sel == 0 and cur.leaving == ""
				"fs_on_cs", "fs_off_cs":
					ok = bool(gm.settings.fullscreen) == (s[1] == "fs_on_cs") and cur.sel == 8 and cur.leaving < 0 and not cur.picking
				"fs_on_play", "fs_off_play":
					ok = bool(gm.settings.fullscreen) == (s[1] == "fs_on_play") and cur.mode == "play" and not cur.paused
				"jump_is_f11": ok = _has_key("jump", KEY_F11) and not gm.rebinding and not bool(gm.settings.fullscreen) and cur.screen == "controls"
				"f11_is_jump": ok = _has_key("jump", KEY_F11) and gm.rebinding and not bool(gm.settings.fullscreen) and cur.screen == "controls"
				"pause_jump_f11": ok = _has_key("jump", KEY_F11) and cur.paused and cur.hud.controls_open and not gm.rebinding and not bool(gm.settings.fullscreen)
				"line_advanced": ok = cur.dialogue.active and cur.dialogue.idx > int(skip_id)
			if str(s[1]).begins_with("volume_"):        # volume_<music|sfx>_<tenths>
				ok = is_equal_approx(float(gm.settings[str(s[1]).get_slice("_", 1)]), int(str(s[1]).get_slice("_", 2)) / 10.0)
			if str(s[1]).begins_with("cs_sel_"):        # chapter select's chosen chapter
				ok = cur.sel == int(str(s[1]).get_slice("_", 2)) and not cur.picking and cur.leaving < 0
			elif str(s[1]).begins_with("cp_sel_"):      # the picker's chosen checkpoint
				ok = cur.picking and cur.cp_sel == int(str(s[1]).get_slice("_", 2)) and cur.leaving < 0
			if not ok:
				_fail("step %d: check %s failed%s" % [idx, s[1], (" (opt_sel %d)" % cur.opt_sel) if "opt_sel" in cur else ""])
		"skip_dialogue":
			for i in 40:
				if cur.mode == "dialogue":
					var ev := InputEventAction.new()
					ev.action = "confirm"
					ev.pressed = true
					cur.dialogue.handle_input(ev)
		"results":
			cur._show_results()
		"best_rows":
			# what the results screen says about Best: a first full climb, a
			# faster and a slower one, and runs that can't set it
			var cd: Dictionary = get_node("/root/Game").chapter_data(1)
			var got := []
			for c in [[0.0, 90.0, true], [100.0, 90.0, true], [80.0, 90.0, true], [80.0, 60.0, false]]:
				cd.best_time = c[0]
				cur.chapter_time = c[1]
				cur.full_run = c[2]
				cur.best_info = cur.record_best(cd)
				cur._show_results()
				var row: Array = cur.hud._result_rows()[2 if cur.hud._result_rows()[0][0] == "" else 3]
				got.append([row[1], row[2], snappedf(float(cd.best_time), 0.01)])
			cur.full_run = true
			var want := [["New Best!", "", 90.0], ["New Best!", "was 1:40.00", 90.0], ["Best", "1:20.00", 80.0], ["Best", "full climbs only", 80.0]]
			if got != want:
				_fail("step %d: Best rows %s" % [idx, got])
		"resume_end":
			var cd: Dictionary = get_node("/root/Game").chapter_data(1)
			cd.best_time = 300.0
			cur._on_end()
			if not is_equal_approx(float(cd.best_time), 300.0):
				_fail("step %d: resumed run overwrote Best with %.2f" % [idx, float(cd.best_time)])
		"seed_resume":
			get_node("/root/Game").data.resume = {"chapter": 1, "room": "1-02", "time": 100.0, "deaths": 7}
		"seed_checkpoints":
			# reached 1-01..1-03 and the secret 1-05s; a berry from 1-04 backfills it
			var g: Node = get_node("/root/Game")
			g.data.chapters.erase("1")
			g.data.resume = {}
			g.data.reached = {"1-01": true, "1-02": true, "1-03": true, "1-05s": true}
			g.data.collected = {"1-04:berry0": true}
		"unlock":
			get_node("/root/Game").data.unlocked = int(s[1])
		"alt_enter":
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_ENTER
			ev.keycode = KEY_ENTER
			ev.alt_pressed = true
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := ev.duplicate()
			up.pressed = false
			Input.parse_input_event.call_deferred(up)
		"mark_save":
			get_node("/root/Game").data.total_deaths = 7   # something Erase Save would clear
		"mark_line":
			if cur.dialogue.cur.is_empty():   # the scene opens with a pause: wait for a line
				idx -= 1
				wait = 2
			else:
				cur.dialogue.shown = cur.dialogue._total_chars()   # the line has finished typing
				skip_id = str(cur.dialogue.idx)
		"seed_continue":
			get_node("/root/Game").data.resume = {"chapter": 1, "room": "1-05s", "time": 50.0, "deaths": 3}
		"done":
			print("UI FLOW PASS")
			get_tree().quit(0)


## Checkpoint rules on a scratch save: a completed chapter offers every
## main-path room, an old save without room records is backfilled up to its
## Continue room, and secret rooms are never offered.
func _backfill_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var keep: Dictionary = g.data
	g.data = g.default_save()
	g.data.erase("reached")   # a save from before rooms were recorded
	var ok := true
	ok = ok and Array(g.reached_checkpoints(1)) == ["1-01"]
	g.data.resume = {"chapter": 1, "room": "1-06", "time": 1.0, "deaths": 0}
	ok = ok and Array(g.reached_checkpoints(1)) == ["1-01", "1-02", "1-03", "1-04", "1-05", "1-06"]
	g.chapter_data(1).complete = true
	ok = ok and g.reached_checkpoints(1).size() == 10 and not g.reached_checkpoints(1).has("1-05s")
	ok = ok and Array(g.checkpoint_rooms(8)) == ["8-01", "8-02"]
	# every checkpoint starts at spawn 0, which must have a proven route out
	for n in LevelDB.chapter_count():
		for rid in g.checkpoint_rooms(n):
			if Level._hint(rid, 0, str(n)).is_empty():
				print("no proven route from checkpoint %s" % rid)
				ok = false
	g.data = keep
	return ok


## Route Ghost Berries mode picks her route from what's still missing: the
## room's berries, then a secret room off it, then the exit. Old settings
## files (just `route_ghost: true`) read as Exit.
func _ghost_goal_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var ch := LevelDB.get_chapter(1)
	var all := {}
	for cid in ch.collectible_ids():
		all[cid] = true
	var some := {"1-05:berry0": true, "1-05:berry1": true}
	var got := [Level.ghost_goal_for(ch, "1", "1-02", 0, {}), Level.ghost_goal_for(ch, "1", "1-02", 0, all),
		Level.ghost_goal_for(ch, "1", "1-05", 0, {"1-05:berry0": true}), Level.ghost_goal_for(ch, "1", "1-05", 1, some),
		Level.ghost_goal_for(ch, "1", "1-05", 0, all), Level.ghost_goal_for(ch, "1", "1-05s", 0, some),
		Level.ghost_goal_for(LevelDB.get_chapter(3), "3", "3-01", 0, {})]
	var want := ["collect", "exit", "collect", "secret", "exit", "collect", "exit"]
	var saved: Dictionary = g.settings.duplicate()
	var modes := []
	for st in [{"route_ghost": true}, {"route_ghost": false, "ghost_goal": "berries"}, {"route_ghost": true, "ghost_goal": "berries"}]:
		g.settings = g.default_settings()
		g.settings.erase("ghost_goal")
		g.settings.merge(st, true)
		modes.append(g.ghost_mode())
	g.settings = saved
	if got != want or modes != ["exit", "off", "berries"]:
		print("ghost goals: ", got, " modes: ", modes)
	return got == want and modes == ["exit", "off", "berries"]


## Key names follow the keyboard layout: the default bindings under stand-ins
## for French (W/A/Z print Z/Q/W) and German (Z prints Y) layouts, a letter the
## pixel font can't draw falls back to the US name, and no stub changes nothing.
func _layout_names_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var got := []
	for stub in [{KEY_W: KEY_Z, KEY_A: KEY_Q, KEY_Z: KEY_W, KEY_Q: KEY_A, KEY_SEMICOLON: KEY_M},
			{KEY_Z: KEY_Y, KEY_Y: KEY_Z}, {KEY_Z: 0x044F, KEY_C: 0x0441}, {}]:
		g.layout_stub = stub
		got.append([g.key_label("grab"), g.key_label("jump"), g.key_name(KEY_W), g.key_name(KEY_A), g.key_name(KEY_SEMICOLON), g.key_name(KEY_LEFT)])
	g.layout_stub = null
	var want := [["W", "C", "Z", "Q", "M", "Left"], ["Y", "C", "W", "A", "Semicolon", "Left"],
		["Z", "C", "W", "A", "Semicolon", "Left"], ["Z", "C", "W", "A", "Semicolon", "Left"]]
	if got != want:
		print("layout names: ", got)
	return got == want


## On a pad, the button each menu hint names does what the hint says: Jump's
## first button (the "Select" hint) confirms and Dash's (the "Back" and
## "Resume" hint) goes back, with the default pad and after rebinding, and the
## keyboard's keys still do.
func _pad_hints_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var ok := true
	var saved = g.settings.get("pad_bindings", {}).duplicate()
	for rebind in [[], ["jump", JOY_BUTTON_X], ["dash", JOY_BUTTON_A], ["jump", JOY_BUTTON_B], ["dash", JOY_BUTTON_Y]]:
		g.settings.pad_bindings = {}
		if rebind:
			g.rebind_pad(rebind[0], rebind[1])
		else:
			g.setup_input()
		for pad in [true, false]:
			g.using_pad = pad
			for pair in [["jump", "confirm", "back"], ["dash", "back", "confirm"]]:
				var lbl: String = g.key_label(pair[0])
				var ev: InputEvent
				if pad:
					for b in g.PAD_BUTTON_NAMES:
						if g.pad_button_name(b, "xbox") == lbl:
							ev = InputEventJoypadButton.new()
							ev.button_index = b
				else:
					ev = InputEventKey.new()
					ev.physical_keycode = g.keys_for(pair[0])[0]
				if ev == null:
					print("pad hints: no button named ", lbl)
					ok = false
					continue
				ev.pressed = true
				if not ev.is_action_pressed(pair[1]) or ev.is_action_pressed(pair[2]):
					print("pad hints: %s %s %s (%s) confirm %s back %s" % [rebind, "pad" if pad else "keys", pair[0], lbl,
						ev.is_action_pressed("confirm"), ev.is_action_pressed("back")])
					ok = false
	g.using_pad = false
	g.settings.pad_bindings = saved
	g.setup_input()
	return ok


## Route Ghost parts: once the player has broken 1-03's boards, the ghost's
## intact ones (and only boards) are the cells drawn for her; in 4-02 her
## gondola moves away from the player's idle one.
func _ghost_parts_ok() -> bool:
	var ch := LevelDB.get_chapter(1)
	var def := ch.room("1-03")
	var pw := World.new()
	pw.load_room(def, 0, ch.dashes)
	var gw := World.new()
	gw.load_room(def, 0, ch.dashes)
	if not RoomView.ghost_only_cells(pw, gw).is_empty():
		return false
	var seen := 0
	for inp in Solver.decode(str(Level._hint("1-03", 0, "1").inputs)):
		pw.step(inp)
		for i in RoomView.ghost_only_cells(pw, gw):
			if def.cells[i] != RoomDef.CRUMBLE:
				return false
			seen += 1
		if pw.exited or pw.dead:
			break
	var ch4 := LevelDB.get_chapter(4)
	var def4 := ch4.room("4-02")
	var p4 := World.new()
	p4.load_room(def4, 0, ch4.dashes)
	var g4 := World.new()
	g4.load_room(def4, 0, ch4.dashes)
	var apart := 0
	for inp in Solver.decode(str(Level._hint("4-02", 0, "4").inputs)):
		g4.step(inp)
		p4.step(0)
		if g4.zip_view_pos(0) != p4.zip_view_pos(0):
			apart += 1
	return seen > 0 and apart > 0 and pw.exited and g4.exited and _ghost_open_ok("1", "1-03", RoomDef.CRUMBLE, false) \
		and _ghost_open_ok("3", "3-02", -1, true)


## Route Ghost's own berries and keys, on her collect routes in 1-03 (two
## berries) and 3-05 (two berries, two keys): nothing extra is drawn while
## the player has touched nothing, except what she is carrying, which is
## everything in the room at some point; and each berry the player found on
## an earlier climb (drawn as an outline) is drawn in place for her until
## she takes it.
func _ghost_items_ok() -> bool:
	return _ghost_items_room("1", "1-03") and _ghost_items_room("3", "3-05") and _ghost_sheet_ok()


## Her items come from a pale copy of the objects sheet: every pixel of a
## berry is a light grey (so her tint decides its colour, unlike the player's
## orange berry and slate found-berry outline), with a dark rim around it.
func _ghost_sheet_ok() -> bool:
	var src := Art.image("res://assets/sprites/objects.png")
	var img := Art.objects_ghost().get_image()
	if img.get_size() != src.get_size():
		return false
	var r := Art.obj_rect("berry0")
	var body := 0
	var rim := 0
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			var c := img.get_pixel(x, y)
			if src.get_pixel(x, y).a > 0.0:
				if absf(c.r - c.g) > 0.02 or absf(c.g - c.b) > 0.02 or c.r < 0.39:
					return false
				body += 1
			elif c.a > 0.0:
				if c.get_luminance() > 0.2:
					return false
				rim += 1
	return body > 20 and rim > 10


func _ghost_items_room(ch_key: String, rid: String) -> bool:
	var ch := LevelDB.get_chapter(int(ch_key))
	var def := ch.room(rid)
	var pw := World.new()
	pw.load_room(def, 0, ch.dashes)
	var gw := World.new()
	gw.load_room(def, 0, ch.dashes)
	var found := {}
	for cid in def.collectible_ids():
		found[cid] = true
	var old := World.new()   # the player found everything on an earlier climb
	old.load_room(def, 0, ch.dashes, found)
	if not RoomView.ghost_items(pw, gw).is_empty() or RoomView.ghost_items(old, gw).size() != gw.berry_s.size() + gw.bell_s.size():
		print("ghost items at the start of %s: %s / %s" % [rid, RoomView.ghost_items(pw, gw), RoomView.ghost_items(old, gw)])
		return false
	var followed := {}
	for inp in Solver.decode(str(Level._hint(rid, 0, ch_key, "collect").inputs)):
		gw.step(inp)
		for it in RoomView.ghost_items(pw, gw):
			var carried: bool = it[2] == "follow" and ((it[0] == "berry" and gw.berry_s[it[1]] == 1) or (it[0] == "key" and gw.key_s[it[1]] == 1))
			if not carried:
				print("ghost item %s in %s while the player has touched nothing" % [it, rid])
				return false
			followed["%s%d" % [it[0], it[1]]] = true
		for it in RoomView.ghost_items(old, gw):
			if it[0] == "berry" and it[2] == "spot" and gw.berry_s[it[1]] != 0:
				return false
		if gw.exited or gw.dead:
			break
	if not gw.exited or followed.size() != gw.berry_s.size() + gw.key_s.size():
		print("ghost items in %s: exited %s, carried %s" % [rid, gw.exited, followed.keys()])
		return false
	return true


## Route Ghost's dash gems (1-04) and balloons (5-02): one of them runs the
## room's route while the other stands still. Each frame, exactly the gems and
## balloons whose state differs are reported: "used" (hers gone, the
## player's there), "ready" (the other way round) and "riding" (she's in it),
## and each state turns up at least once.
func _ghost_pickups_ok() -> bool:
	return _ghost_pickups_room("1", "1-04", "gem") and _ghost_pickups_room("5", "5-02", "balloon")


func _ghost_pickups_room(ch_key: String, rid: String, kind: String) -> bool:
	var seen := {}
	for she_runs in [true, false]:
		var ch := LevelDB.get_chapter(int(ch_key))
		var def := ch.room(rid)
		var pw := World.new()
		pw.load_room(def, 0, ch.dashes)
		var gw := World.new()
		gw.load_room(def, 0, ch.dashes)
		if not RoomView.ghost_pickups(pw, gw).is_empty():
			return false
		var runner := gw if she_runs else pw
		for inp in Solver.decode(str(Level._hint(rid, 0, ch_key).inputs)):
			runner.step(inp)
			var want := []
			var n := gw.gem_t.size() if kind == "gem" else gw.balloon_t.size()
			for i in n:
				var hers := gw.gem_t[i] == 0 if kind == "gem" else gw.balloon_t[i] == 0
				var mine := pw.gem_t[i] == 0 if kind == "gem" else pw.balloon_t[i] == 0
				if kind == "balloon" and gw.boost_idx == i:
					if pw.boost_idx != i:
						want.append([kind, i, "riding"])
				elif mine and not hers:
					want.append([kind, i, "used"])
				elif hers and not mine:
					want.append([kind, i, "ready"])
			var got := RoomView.ghost_pickups(pw, gw)
			if got != want:
				print("ghost pickups in %s (she runs: %s): %s, expected %s" % [rid, she_runs, got, want])
				return false
			for it in got:
				seen[it[2]] = true
				if it[2] == "used":
					var left := RoomView.ghost_pickup_left(gw, kind, it[1])
					if left <= 0.0 or left > 1.0:
						return false
			if runner.exited or runner.dead:
				break
		if not runner.exited:
			return false
	var need := ["used", "ready", "riding"] if kind == "balloon" else ["used", "ready"]
	for st in need:
		if not seen.has(st):
			print("ghost pickups in %s: never %s" % [rid, st])
			return false
	return true


## The other direction: the player stands still while the ghost runs her
## route. Cells open for her but solid for the player are only boards (1-03)
## or mask blocks (3-02), none at the start, and the near ones are a subset
## within the radius. Her boards fall after she has left them, so only the
## mask room must have some near her.
func _ghost_open_ok(ch_key: String, rid: String, kind: int, need_near: bool) -> bool:
	var ch := LevelDB.get_chapter(int(ch_key))
	var def := ch.room(rid)
	var pw := World.new()
	pw.load_room(def, 0, ch.dashes)
	var gw := World.new()
	gw.load_room(def, 0, ch.dashes)
	if not RoomView.ghost_open_cells(pw, gw).is_empty():
		return false
	var seen := 0
	var near := 0
	for inp in Solver.decode(str(Level._hint(rid, 0, ch_key).inputs)):
		gw.step(inp)
		var all := RoomView.ghost_open_cells(pw, gw)
		for i in all:
			var t := def.cells[i]
			if (kind >= 0 and t != kind) or (kind < 0 and t != RoomDef.MASK_A and t != RoomDef.MASK_B):
				print("ghost open cell %d in %s is %d" % [i, rid, t])
				return false
		seen += all.size()
		var c := Vector2(gw.x + World.PW / 2.0, gw.y + World.PH / 2.0)
		for i in RoomView.ghost_open_cells(pw, gw, RoomView.GHOST_OPEN_RADIUS):
			if not all.has(i) or c.distance_to(Vector2((i % def.w) * 8 + 4, (i / def.w) * 8 + 4)) > RoomView.GHOST_OPEN_RADIUS:
				return false
			near += 1
		if gw.exited or gw.dead:
			break
	if seen == 0 or (need_near and near == 0):
		print("ghost open cells in %s: %d seen, %d near" % [rid, seen, near])
	return seen > 0 and (near > 0 or not need_near) and gw.exited


## Air Dashes assist in the simulation: from a jump, Mira dashes up, then
## tries again twice in the air. Default allows one, Two two, Infinite all
## three; a room the story keeps dashless stays dashless; respawning keeps it.
func _air_dashes_ok() -> bool:
	var want := {World.AIR_DASHES_DEFAULT: [1, 0], World.AIR_DASHES_TWO: [2, 0], World.AIR_DASHES_INFINITE: [3, 1]}
	var ok := true
	for mode in want:
		var r := _air_dash_run("1", "1-01", mode)
		if r != want[mode]:
			print("air dashes %d: %s dashes fired, %s left (want %s)" % [mode, r[0], r[1], want[mode]])
			ok = false
	var r0 := _air_dash_run("0", "0-01", World.AIR_DASHES_TWO)
	var r7 := _air_dash_run("7", "7-01", World.AIR_DASHES_TWO)
	if r0 != [0, 0] or r7 != [2, 0]:
		print("air dashes: prologue %s, summit %s" % [r0, r7])
		ok = false
	return ok


func _air_dash_run(ch_key: String, rid: String, mode: int) -> Array:
	var ch := LevelDB.get_chapter(int(ch_key))
	var w := World.new()
	w.assist_air_dashes = mode
	w.load_room(ch.room(rid), 0, ch.dashes)
	w.reset_room()   # a respawn keeps the assist
	var fired := 0
	var seq := []
	for i in 30: seq.append(0)
	for i in 6: seq.append(World.IN_JUMP)
	for k in 3:
		seq.append(World.IN_DASH | World.IN_UP)
		for i in 13: seq.append(0)   # past the dash cooldown
	for inp in seq:
		w.step(inp)
		if w.events.has("dash"):
			fired += 1
	return [fired, w.dashes]


## Invincibility in the simulation, each case off and on: a fall into the
## prologue's first pit (0-02), a dash through 7-03's middle curtain into the
## wall behind it, and a gondola in 4-02 pushing Mira into the right-hand
## wall. Off, each one kills. On, she bounces up out of the pit, turns back
## out of the curtain, or is set down beside the gondola, never inside
## anything solid and never stuck in the curtain.
func _invincible_ok() -> bool:
	var ok := true
	for inv in [false, true]:
		var cases := {"pit": _inv_pit(inv), "curtain": _inv_curtain(inv), "gondola": _inv_gondola(inv)}
		for k in cases:
			var r: Dictionary = cases[k]
			var good: bool = r.dead if not inv else (not r.dead and r.bounced and r.free)
			if not good:
				print("invincibility %s, %s: %s" % ["on" if inv else "off", k, r])
				ok = false
	return ok


## Dash Aim asks the world whether a dash would start now by stepping it and
## putting it back. Replaying Route Ghost routes through crumbling boards,
## mask blocks, a gondola, balloons and bumpers, with that question asked
## every frame, must give exactly the same world as not asking.
func _aim_probe_pure_ok() -> bool:
	var asked := 0
	for r in [["1", "1-03"], ["3", "3-02"], ["4", "4-02"], ["5", "5-02"], ["6", "6-02"]]:
		var ch := LevelDB.get_chapter(int(r[0]))
		var a := World.new()
		var b := World.new()
		a.load_room(ch.room(r[1]), 0, ch.dashes)
		b.load_room(ch.room(r[1]), 0, ch.dashes)
		for inp in Solver.decode(str(Level._hint(r[1], 0, r[0]).inputs)):
			if b.dash_would_start(inp):
				asked += 1
			a.step(inp)
			b.step(inp)
			if a.events != b.events or str(a.save_state()) != str(b.save_state()) or a.solid != b.solid:
				print("aim probe changed the world in %s at frame %d" % [r[1], a.frame])
				return false
			if a.dead or a.exited or a.end_reached:
				break
	return asked > 0


## The PostFX layer under a scene (title, chapter select, level).
func _find_post(n: Node) -> PostFX:
	for c in n.get_children():
		if c is PostFX:
			return c
	return null


## Every Options row (title and pause) has its own help text, which fits its
## box; on the title the box stays above Mira's juggling (y 110). Smooth
## Motion's three values and Window Size's Auto read differently.
func _option_help_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var keep: Dictionary = g.settings.duplicate()
	var ok := true
	var hud := Hud.new()
	var rows: Array = hud.option_items.duplicate()
	hud.free()
	for r in load("res://scripts/ui/title.gd").OPTIONS:
		if not rows.has(r):
			rows.append(r)
	var seen := {}
	for sm in ["auto", "on", "off"]:
		for k in 8:   # Window Size Auto and 2x, at each Graphics Fidelity step
			g.settings.smooth_motion = sm
			g.settings.window_scale = [0, 2][k % 2]
			g.settings.fidelity = k / 2
			for r in rows:
				var t := UIKit.option_help(r)
				seen[t] = true
				var lines := PixelText.wrap(t, UIKit.HELP_TEXT_W)
				if t == "" or 14 + 26 + lines.size() * PixelText.LINE_H > 110:
					print("option help for %s: %d lines: %s" % [r, lines.size(), t])
					ok = false
				for l in lines:
					if PixelText.width(l) > UIKit.HELP_TEXT_W:
						print("option help line too wide: ", l)
						ok = false
	g.settings = keep
	# 13 rows, plus Smooth Motion's other two values, Window Size's fixed scale
	# and Graphics Fidelity's other three steps
	if seen.size() != 19:
		print("option help: %d different texts, want 19" % seen.size())
		ok = false
	return ok


## The pause screen shows the chapter's time (with the Speedrun Timer off),
## and the line fits for every chapter at 999 deaths and an hour's climb.
func _pause_time_ok(cur: Node) -> bool:
	var info: String = cur.hud.pause_info()
	if bool(get_node("/root/Game").settings.show_timer) or cur.chapter_time <= 0.0 or not info.ends_with("   " + Level.fmt_time(cur.chapter_time)):
		print("pause info: %s (time %.2f)" % [info, cur.chapter_time])
		return false
	for n in 9:
		var w := PixelText.width("%s   Deaths %d   %s" % [LevelDB.get_chapter(n).name, 999, Level.fmt_time(3599.99)])
		if w > 300:
			print("pause info too wide for chapter %d: %d px" % [n, w])
			return false
	return true


## The left stick at <angle> (radians, counter-clockwise from right) and <tilt>.
func _stick(angle: float, tilt: float) -> void:
	for ax in [[JOY_AXIS_LEFT_X, cos(angle) * tilt], [JOY_AXIS_LEFT_Y, -sin(angle) * tilt]]:
		var ev := InputEventJoypadMotion.new()
		ev.device = 0
		ev.axis = ax[0]
		ev.axis_value = ax[1]
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


## In play the stick points eight equal ways at any tilt past the deadzone
## (each axis alone made a diagonal need the stick near its rim), and gives
## nothing below it.
func _stick_sectors_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var dirs := World.IN_LEFT | World.IN_RIGHT | World.IN_UP | World.IN_DOWN
	var ok := true
	for tilt in [0.3, 0.45, 0.6, 1.0]:
		var counts := {}
		for deg in 360:
			_stick(deg_to_rad(deg + 0.25), tilt)   # off the 22.5-degree boundaries
			var b: int = g.read_input() & dirs
			counts[b] = int(counts.get(b, 0)) + 1
		if tilt < g.STICK_DEADZONE:
			if counts.keys() != [0]:
				print("stick at %.2f gives a direction: %s" % [tilt, counts])
				ok = false
			continue
		for d in [World.IN_RIGHT, World.IN_RIGHT | World.IN_UP, World.IN_UP, World.IN_UP | World.IN_LEFT,
				World.IN_LEFT, World.IN_LEFT | World.IN_DOWN, World.IN_DOWN, World.IN_DOWN | World.IN_RIGHT]:
			if int(counts.get(d, 0)) != 45:
				print("stick at %.2f: direction %d covers %d degrees, want 45 (%s)" % [tilt, d, int(counts.get(d, 0)), counts])
				ok = false
	_stick(0.0, 0.0)
	if g.read_input() & dirs:
		print("stick at rest still gives a direction")
		ok = false
	return ok


## The pause Options just opened: Mira's screen position is where the camera
## puts her, and the panel is on the other side of the screen.
func _opt_layout_ok(lv: Node) -> bool:
	var m: Vector2 = lv.mira_screen_pos()
	var by_cam: Vector2 = lv.world.player_center() - lv.camera.get_screen_center_position() + Vector2(160, 90)
	var ok: bool = m.distance_to(by_cam) < 1.5 and Rect2(0, 0, 320, 180).has_point(m) \
		and not lv.hud.options_rect().intersects(Hud.mira_rect(m)) and (lv.hud.opt_x > 100.0) == (m.x < 160.0)
	print("Options layout: opened with Mira at %s (camera says %s), panel %s" % [m, by_cam, lv.hud.options_rect()])
	return ok


## Mira anywhere on the screen (4 px steps): neither the panel nor the help
## box covers her, for every row at every Smooth Motion and Window Size value
## (each text fits 4 lines, so one end of her column always clears her).
## Restores the layout for Mira's real position and the settings.
func _opt_layout_sweep_ok(lv: Node) -> bool:
	var g: Node = get_node("/root/Game")
	var keep: Dictionary = g.settings.duplicate()
	var hud: Hud = lv.hud
	var covered := {}
	var sel := hud.option_sel
	for sm in ["auto", "on", "off"]:
		for ws in [0, 2]:
			g.settings.smooth_motion = sm
			g.settings.window_scale = ws
			for x in range(2, 320, 4):
				for y in range(2, 180, 4):
					var m := Vector2(x, y)
					hud.layout_options(m)
					var me := Hud.mira_rect(m)
					if hud.options_rect().intersects(me):
						covered["panel"] = int(covered.get("panel", 0)) + 1
					for i in hud.option_items.size():
						hud.option_sel = i
						if hud.help_rect().intersects(me):
							var k := "%s (%s, %d)" % [hud.option_items[i], sm, ws]
							covered[k] = int(covered.get(k, 0)) + 1
	g.settings = keep
	hud.option_sel = sel
	hud.layout_options(lv.mira_screen_pos())
	if not covered.is_empty():
		print("Options layout covers Mira: ", covered)
	return covered.is_empty()


## Stick Deadzone: at 20%, 60% and 70% the stick gives the eight 45-degree
## directions just past the deadzone and nothing just inside it, in play
## (read_input) and for the menus' direction actions alike.
func _deadzone_sweep_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var dirs := World.IN_LEFT | World.IN_RIGHT | World.IN_UP | World.IN_DOWN
	var ok := true
	for t in [[0.2, [0.15], [0.25, 0.45, 1.0]], [0.6, [0.4, 0.55], [0.65, 1.0]], [0.7, [0.65], [0.75, 1.0]]]:
		g.settings.stick_deadzone = t[0]
		g.apply_stick_deadzone()
		for tilt in t[1] + t[2]:
			var counts := {}
			var acted := false
			for deg in 360:
				_stick(deg_to_rad(deg + 0.25), tilt)
				counts[g.read_input() & dirs] = int(counts.get(g.read_input() & dirs, 0)) + 1
				for a in ["up", "down", "left", "right"]:
					acted = acted or Input.is_action_pressed(a)
			if tilt in t[1]:
				if counts.keys() != [0] or acted:
					print("deadzone %.2f: stick at %.2f gives a direction: %s, actions %s" % [t[0], tilt, counts, acted])
					ok = false
				continue
			for d in [World.IN_RIGHT, World.IN_RIGHT | World.IN_UP, World.IN_UP, World.IN_UP | World.IN_LEFT,
					World.IN_LEFT, World.IN_LEFT | World.IN_DOWN, World.IN_DOWN, World.IN_DOWN | World.IN_RIGHT]:
				if int(counts.get(d, 0)) != 45:
					print("deadzone %.2f: stick at %.2f: direction %d covers %d degrees (%s)" % [t[0], tilt, d, int(counts.get(d, 0)), counts])
					ok = false
	# a push held while the deadzone rises past it lets go of its direction
	g.settings.stick_deadzone = g.STICK_DEADZONE
	g.apply_stick_deadzone()
	_stick(0.0, 0.48)
	var held_before := Input.is_action_pressed("right")
	g.step_stick_deadzone(1)
	g.step_stick_deadzone(1)
	Input.flush_buffered_events()
	if not held_before or Input.is_action_pressed("right"):
		print("a 0.48 push held as the deadzone goes 40 -> 50%%: right held %s, then %s" % [held_before, Input.is_action_pressed("right")])
		ok = false
	g.settings.stick_deadzone = g.STICK_DEADZONE
	g.apply_stick_deadzone()
	_stick(0.0, 0.0)
	return ok


## The Stick Deadzone row's dial and footer fit: the dial and its readout left
## of the panel, the footer inside it, the panel above the hint line; and the
## dial reads the stick that moved (lit past the deadzone, not inside it).
func _deadzone_dial_ok(c: ControlsMenu) -> bool:
	var ok := true
	var ctr := c.dial_center()
	var box := Rect2(ctr - Vector2.ONE * (c.DIAL_R + 2.0), Vector2.ONE * (2.0 * c.DIAL_R + 4.0)).merge(
		Rect2(ctr.x - PixelText.width("100%") / 2.0, ctr.y + c.DIAL_R + 5.0, PixelText.width("100%"), PixelText.CELL_H))
	if box.position.x < 2.0 or box.end.x > c.PANEL.position.x - 2.0 or box.position.y < 0.0 or box.end.y > 164.0:
		print("dial box ", box)
		ok = false
	if PixelText.width(c.DEADZONE_FOOT) > c.PANEL.size.x - 20.0 or c.PANEL.end.y > 164.0:
		print("footer %d px, panel ends at %d" % [PixelText.width(c.DEADZONE_FOOT), c.PANEL.end.y])
		ok = false
	var g: Node = get_node("/root/Game")
	_stick(-PI / 2.0, 0.5)   # down, half way
	var lit_40: int = g.stick_dirs(g.stick_vector(g.stick_pad()))
	g.settings.stick_deadzone = 0.6
	var lit_60: int = g.stick_dirs(g.stick_vector(g.stick_pad()))
	g.settings.stick_deadzone = 0.4
	_stick(0.0, 0.0)
	if g.stick_pad() != 0 or lit_40 != World.IN_DOWN or lit_60 != 0:
		print("dial reads pad %d: %d at 40%%, %d at 60%%" % [g.stick_pad(), lit_40, lit_60])
		ok = false
	return ok


## Every Assist row, at every value of Air Dashes and Route Ghost, has its
## own help line under the panel, at most two lines that fit the screen.
func _assist_help_ok() -> bool:
	var g: Node = get_node("/root/Game")
	var keep: Dictionary = g.settings.duplicate()
	var seen := {}
	var ok := true
	var hud := Hud.new()
	var items: Array = hud.assist_items
	hud.free()
	for air in ["default", "two", "infinite"]:
		for ghost in [[false, "exit"], [true, "exit"], [true, "berries"]]:
			g.settings.air_dashes = air
			g.settings.route_ghost = ghost[0]
			g.settings.ghost_goal = ghost[1]
			for item in items:
				var t := Hud.assist_help(item)
				seen[t] = true
				var lines := PixelText.wrap(t, Hud.ASSIST_HELP_W)
				if t == "" or lines.size() > 2:
					print("assist help for %s: %d lines: %s" % [item, lines.size(), t])
					ok = false
				for l in lines:
					if PixelText.width(l) > Hud.ASSIST_HELP_W:
						print("assist help line too wide: ", l)
						ok = false
	g.settings = keep
	# 7 rows, plus 2 more Air Dashes values and 2 more Route Ghost values
	if seen.size() != 11:
		print("assist help: %d different texts, want 11" % seen.size())
		ok = false
	return ok


func _inv_world(ch_n: int, rid: String, inv: bool) -> World:
	var ch := LevelDB.get_chapter(ch_n)
	var w := World.new()
	w.load_room(ch.room(rid), 0, ch.dashes)
	w.assist_invincible = inv
	return w


func _inv_result(w: World, bounced: bool) -> Dictionary:
	return {"dead": w.dead, "bounced": bounced, "free": not w._collide(w.x, w.y) and w.state != World.ST_DREAM \
		and w.x >= 0 and w.x <= w.w * 8 - World.PW and w.y <= w.h * 8 - World.PH}


func _inv_pit(inv: bool) -> Dictionary:
	var w := _inv_world(0, "0-02", inv)
	w.x = 80
	w.y = 140
	var bounced := false
	for i in 180:
		w.step(0)
		bounced = bounced or w.events.has("bounce")
		if w.dead:
			break
	return _inv_result(w, bounced)


func _inv_curtain(inv: bool) -> Dictionary:
	var w := _inv_world(7, "7-03", inv)
	w.x = 150
	w.y = 88
	var bounced := false
	var dreamed := false
	for i in 150:
		w.step(World.IN_DASH | World.IN_RIGHT if i == 0 else 0)
		dreamed = dreamed or w.events.has("dream_in")
		bounced = bounced or w.events.has("bounce")
		if w.dead:
			break
	var r := _inv_result(w, bounced)
	r.dead = r.dead and dreamed   # the crash, not a later fall
	return r


func _inv_gondola(inv: bool) -> Dictionary:
	var w := _inv_world(4, "4-02", inv)
	w.zip_px[0] = 280 - w.zip_w[0] - World.PW   # parked a player's width from the wall
	w.zip_px[1] = 80
	w.x = 280 - World.PW
	w.y = 78
	var before := w._collide(w.x, w.y)
	w._move_solid(0, 1, 0)
	var r := _inv_result(w, true)
	if before:
		r.dead = false
		r.free = false
	return r


## Grab as the simulation sees it over press, release, idle, press, release,
## press, release, and then after a death's release_grab().
func _grab_reads() -> Array:
	var g: Node = get_node("/root/Game")
	var out := []
	for down in [true, false, false, true, false, true, false]:
		if down:
			Input.action_press("grab")
		else:
			Input.action_release("grab")
		out.append((g.read_input() & World.IN_GRAB) != 0)
	g.release_grab()
	out.append((g.read_input() & World.IN_GRAB) != 0)
	return out
