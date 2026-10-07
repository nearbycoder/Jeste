extends SceneTree
## Save files survive bad writes: damages save files in each way a crash or a
## full disk can leave them and checks Game.read_json() / write_json() recover
## the last good copy without overwriting the damaged one.
## godot --headless --path . --script res://tests/save_check.gd
## Works in user://save_check/ only. The full load_save()/save() path, which
## uses the real save file name, runs only when user:// is a sandbox inside
## the repo's build/ folder (run_tests.py sets that up).
## Prints "SAVES PASS <n>" or "SAVES FAIL: ..." lines.

const DIR := "user://save_check/"
var g: Node
var n := 0
var bad := 0


func _init() -> void:
	g = load("res://scripts/game/game_state.gd").new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var p := DIR + "save.json"
	_clean(p)

	# a normal save round-trips; the previous copy becomes the backup
	_ok(g.write_json(p, {"a": 1}), "first write")
	_ok(not FileAccess.file_exists(p + ".bak"), "no backup before a second write")
	_ok(g.write_json(p, {"a": 2, "s": "x"}), "second write")
	_eq(g.read_json(p), {"a": 2, "s": "x"}, "round trip")
	_eq(_parse(p + ".bak"), {"a": 1}, "backup holds the previous save")
	_ok(not FileAccess.file_exists(p + ".tmp"), "temp file renamed away")

	# damaged main files fall back to the backup and are set aside, not overwritten
	var good := FileAccess.get_file_as_string(p)
	for dmg in [["truncated", good.substr(0, good.length() / 2)], ["empty", ""], ["garbage", "}{ not json"], ["not an object", "[1, 2]"]]:
		_reset(p, {"a": 1}, {"a": 2})
		_put(p, str(dmg[1]))
		g.load_notice = ""
		_eq(g.read_json(p), {"a": 1}, "%s save loads the backup" % dmg[0])
		_ok(FileAccess.get_file_as_string(p + ".corrupt") == str(dmg[1]), "%s save kept as .corrupt" % dmg[0])
		_ok("Restored" in g.load_notice, "%s save tells the player" % dmg[0])
		_ok(g.write_json(p, {"a": 3}), "%s: next write" % dmg[0])
		_ok(FileAccess.get_file_as_string(p + ".corrupt") == str(dmg[1]), "%s: next write leaves .corrupt alone" % dmg[0])
		_eq(g.read_json(p), {"a": 3}, "%s: next write reads back" % dmg[0])

	# a crash between the two renames leaves only the backup: use it, quietly
	_reset(p, {"a": 1}, {"a": 2})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_put(p + ".tmp", "{\"a\": 9")   # a half-written temp file is ignored
	g.load_notice = ""
	_eq(g.read_json(p), {"a": 1}, "missing save loads the backup")
	_ok(g.load_notice == "", "missing save with a backup is silent")

	# both damaged: nothing usable, but nothing destroyed either
	_reset(p, {"a": 1}, {"a": 2})
	_put(p, "{\"a\":")
	_put(p + ".bak", "")
	g.load_notice = ""
	_eq(g.read_json(p), {}, "both damaged gives a fresh start")
	_ok(FileAccess.get_file_as_string(p + ".corrupt") == "{\"a\":", "both damaged keeps .corrupt")
	_ok("set aside" in g.load_notice, "both damaged tells the player")

	# no files at all: a first launch, silently
	_clean(p)
	g.load_notice = ""
	_eq(g.read_json(p), {}, "first launch")
	_ok(g.load_notice == "", "first launch is silent")
	_clean(p)

	_game_path()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	g.free()
	print("SAVES %s %d" % ["PASS" if bad == 0 else "FAIL", n])
	quit(0 if bad == 0 else 1)


## Game.save() / load_save() / reset_save() with the real file names, only in
## a sandboxed user:// so a developer's own save is never touched.
func _game_path() -> void:
	var ud := OS.get_user_data_dir()
	if not "/build/" in ud:
		print("SAVES NOTE: user:// is %s, not a sandbox; skipping the full load/save check" % ud)
		return
	var sp: String = g.SAVE_PATH
	_clean(sp)
	g.headless_test = false
	g.data = g.default_save()
	g.data.unlocked = 5
	g.save()
	g.data.unlocked = 6
	g.save()
	_put(sp, FileAccess.get_file_as_string(sp).substr(0, 40))   # crash mid-write (old code: truncate, then write)
	g.load_save()
	_ok(int(g.data.unlocked) == 5, "load_save() recovers the backup after a torn write (got %s)" % str(g.data.unlocked))
	g.save()
	_ok(FileAccess.file_exists(sp + ".corrupt"), "load_save() kept the torn file")
	g.reset_save()
	_ok(not FileAccess.file_exists(sp + ".bak"), "Erase Save leaves no backup of the erased progress")
	g.load_save()
	_ok(int(g.data.unlocked) == 0, "Erase Save sticks")
	_clean(sp)


func _ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		bad += 1
		print("SAVES FAIL: " + what)


func _eq(got: Dictionary, want: Dictionary, what: String) -> void:
	var w := JSON.stringify(JSON.parse_string(JSON.stringify(want)))   # JSON numbers read back as floats
	_ok(JSON.stringify(got) == w, "%s: got %s, want %s" % [what, JSON.stringify(got), w])


func _parse(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Leaves `path` holding `cur` with `prev` as its backup.
func _reset(path: String, prev: Dictionary, cur: Dictionary) -> void:
	_clean(path)
	g.write_json(path, prev)
	g.write_json(path, cur)


func _clean(path: String) -> void:
	for ext in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(path + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
