extends SceneTree

## Headless checks for the Godot-native CLI/MCP core + replay archive.

const Core = preload("res://scripts/cli/BombitCore.gd")

var checks = 0
var failures = 0

func ok(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS " + label)
	else:
		failures += 1
		print("FAIL " + label)

func _initialize() -> void:
	var dir = ProjectSettings.globalize_path("user://bombit-test")
	_clean(dir)
	var core = Core.new(dir)
	var n = core.handle({"op": "new", "agent": "test", "mode": "dig", "seed": "cli-test",
		"character": "xiaonuo", "session": "cli-test-session"})
	ok(bool(n.get("ok", false)), "new session")
	ok(int(n.get("revision", -1)) == 0, "new revision 0")
	ok(String(n.get("session", "")) == "cli-test-session", "custom session name")
	ok(n.get("state", {}).get("protocol", "") == "bombit/1", "observation protocol")
	ok(n.get("state", {}).get("map", {}).get("terrain", []).size() == 13, "terrain rows")
	var sid = String(n.get("session", ""))

	var a = core.handle({"op": "act", "session": sid, "move": "down", "frames": 12, "requestId": "r1"})
	ok(bool(a.get("ok", false)), "act ok")
	ok(int(a.get("advancedFrames", 0)) == 12, "act advanced 12")
	ok(int(a.get("revision", 0)) == 1, "act revision 1")

	var dup = core.handle({"op": "act", "session": sid, "move": "down", "frames": 12, "requestId": "r1"})
	ok(bool(dup.get("ok", false)) and bool(dup.get("duplicate", false)), "requestId duplicate")

	var b = core.handle({"op": "batch", "session": sid, "steps": [
		{"move": "right", "frames": 3}, {"wait": true, "frames": 2}]})
	ok(bool(b.get("ok", false)), "batch ok")
	ok(int(b.get("completedActions", 0)) == 2, "batch completed 2")
	ok(int(b.get("revision", 0)) == 3, "batch revision 3")

	var st = core.handle({"op": "state", "session": sid})
	ok(bool(st.get("ok", false)) and int(st.get("revision", 0)) == 3, "state revision")

	var rep = core.handle({"op": "replay", "session": sid})
	ok(bool(rep.get("ok", false)) and bool(rep.get("verified", false)), "session replay verified")

	var fin = core.handle({"op": "finish", "session": sid})
	ok(bool(fin.get("ok", false)) and bool(fin.get("archived", false)), "finish archived")
	var file = String(fin.get("replayFile", ""))
	ok(FileAccess.file_exists(file), "replay file exists")
	ok(String(fin.get("session", "")).contains("-stopped-"), "archived name has outcome")

	var loaded = core.handle({"op": "state", "session": String(fin.get("session", ""))})
	ok(bool(loaded.get("ok", false)), "archived session can be read by replay name")

	var rf = core.handle({"op": "replay", "file": file})
	ok(bool(rf.get("ok", false)) and bool(rf.get("verified", false)), "replay file verified")

	var rules = core.handle({"op": "rules"})
	ok(bool(rules.get("ok", false)) and rules.get("rules", {}).get("characters", []).size() == 6, "rules characters")

	print("CLI_CHECKS=%d FAILURES=%d" % [checks, failures])
	_clean(dir)
	quit(0 if failures == 0 else 1)

func _clean(dir: String) -> void:
	for sub in ["sessions", "replays"]:
		var path = dir.path_join(sub)
		var d = DirAccess.open(path)
		if d == null:
			continue
		d.list_dir_begin()
		var name = d.get_next()
		while name != "":
			if not d.current_is_dir():
				DirAccess.remove_absolute(path.path_join(name))
			name = d.get_next()
		d.list_dir_end()
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)
