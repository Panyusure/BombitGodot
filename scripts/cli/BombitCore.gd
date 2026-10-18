extends RefCounted

## BombIt headless core shared by CLI, MCP and the in-game replay player.
## Sessions keep the initial config plus the full action history; a saved
## session is reconstructed deterministically, so nothing depends on the UI.

const SESSION_FORMAT = "bombit-godot-session/1"
const REPLAY_FORMAT = "bombit-godot-replay/1"
const ENGINE_VERSION = "godot-1"
const FPS = 60.0
const DT = 1.0 / 60.0
const CHARS = ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian", "weilai"]
const MODES = ["dig", "adventure", "versus"]
const DIRS = {"none": Vector2i(0, 0), "up": Vector2i(0, -1), "down": Vector2i(0, 1),
	"left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
const STOP_EVENTS = ["death", "level_started", "round_started", "match_over"]

var base_dir = ""
var sessions_dir = ""
var replays_dir = ""
var memory: Dictionary = {}
var autosave = true

func _init(dir_override: String = "") -> void:
	_setup_dirs(dir_override)

func _setup_dirs(dir_override: String) -> void:
	var root = ""
	if dir_override != "":
		root = dir_override
	elif OS.has_feature("editor") or FileAccess.file_exists("res://project.godot"):
		sessions_dir = ProjectSettings.globalize_path("res://.bombit/sessions")
		replays_dir = ProjectSettings.globalize_path("res://data/replays")
		base_dir = ProjectSettings.globalize_path("res://.bombit")
	else:
		root = ProjectSettings.globalize_path("user://bombit")
	if root != "":
		sessions_dir = root.path_join("sessions")
		replays_dir = root.path_join("replays")
		base_dir = root
	DirAccess.make_dir_recursive_absolute(sessions_dir)
	DirAccess.make_dir_recursive_absolute(replays_dir)

# ---------------------------------------------------------------- errors

func fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}

# ---------------------------------------------------------------- rules

func rules() -> Dictionary:
	var chars = []
	for id in CHARS:
		var cfg = Cfg.CHARS.get(id, {})
		var skill = Cfg.SKILLS.get(id, {}).duplicate()
		if skill.has("color"):
			skill["color"] = Color(skill["color"]).to_html(false)
		chars.append({"id": id, "name": String(cfg.get("name", id)), "skill": skill})
	var items = {}
	for key in Cfg.ITEM_INFO:
		items[key] = Cfg.ITEM_INFO[key].duplicate()
	return {
		"protocol": "bombit/1",
		"engine": ENGINE_VERSION,
		"modes": MODES,
		"characters": chars,
		"timing": {
			"fps": 60, "defaultFrames": 12, "maxFrames": 60, "fuseSeconds": Cfg.FUSE,
			"fuseAppliesTo": "players, all enemies and bosses",
			"flameSeconds": Cfg.FLAME_TIME, "movementTilesPerSecond": Cfg.SPEED_BASE,
			"actionOrder": ["move", "skill", "bomb"],
			"pulse": "bomb and skill fire once on the first frame",
			"pause": "Only act, batch, path and goTo advance game time.",
		},
		"control": {
			"recommendedTransport": "MCP stdio or serve --memory",
			"operations": ["new", "state", "act", "batch", "path", "goTo", "checkpoint", "finish", "replay", "export", "rules"],
			"batch": {"steps": "1..1024 normal action objects; one final state"},
			"navigation": {"path": "1..256 adjacent [col,row] cells", "target": "goTo uses [col,row]",
				"maxFrames": "1..3600, default 3600",
				"safety": "Walls and current blocking bombs only; predicted hazards are not avoided"},
			"memory": "MCP and serve --memory keep the world in memory; one-shot commands rebuild from history.",
		},
		"coordinates": {"origin": "top-left", "col": "right, zero-based", "row": "down, zero-based", "tileSize": Cfg.TILE},
		"legend": {"#": "hard wall", "+": "breakable brick", ".": "floor", "1": "p1", "2": "p2",
			"E": "enemy", "X": "boss", "o": "bomb", "*": "flame", "!": "poison",
			"?": "poison warning", "i": "item", "=": "moving track"},
		"objectives": {
			"dig": "Destroy every brick within 180 seconds; start with 3 lives.",
			"adventure": "Clear all enemies across 10 levels; bosses at levels 5 and 10.",
			"versus": "Two externally controlled players. First to 2 points; submit both actions in one request.",
		},
		"tips": [
			"Read state freely: thinking does not consume game time.",
			"Place a bomb while standing still, then move away and turn a corner.",
			"12 frames moves about 0.92 tiles at base speed. Use fewer frames near a turn.",
			"Use assist for conservative danger windows.",
			"versus does not supply a built-in second player; omitted player actions mean wait.",
		],
		"scenery": {
			"factory": "Carries players, enemies, bosses and bombs clockwise at 1.65 tiles/second.",
			"park": "Carries idle players/enemies/bosses and bombs clockwise at 1.8 tiles/second; walking can leave the ride.",
			"timeStop": "Freezes enemy movement and enemy-bomb transport; stun does not stop environmental transport.",
		},
		"items": items,
	}

# ---------------------------------------------------------------- config

func normalize_config(req: Dictionary) -> Dictionary:
	var mode = String(req.get("mode", "adventure"))
	var character = String(req.get("character", req.get("character1", "xiaonuo")))
	var character2 = String(req.get("character2", "axiu"))
	if not MODES.has(mode):
		return {}
	if not CHARS.has(character) or not CHARS.has(character2):
		return {}
	var seed = String(req.get("seed", _random_hex(6)))
	if seed == "" or seed.length() > 128:
		return {}
	return {"mode": mode, "seed": seed, "chars": [character, character2],
		"inputMode": "versus" if mode == "versus" else "solo", "label": mode}

func _create_world(config: Dictionary) -> World:
	var w = GameEngine.create_world({
		"mode": String(config.get("mode", "adventure")),
		"seed": String(config.get("seed", "demo")),
		"chars": config.get("chars", ["xiaonuo", "axiu"]),
		"input_mode": String(config.get("inputMode", "solo")),
	})
	w.briefing = false
	return w

# ---------------------------------------------------------------- sessions

func _valid_id(id: String) -> bool:
	if id.length() < 1 or id.length() > 96:
		return false
	var re = RegEx.new()
	re.compile("^[A-Za-z0-9][A-Za-z0-9_-]*$")
	return re.search(id) != null

func _session_path(id: String) -> String:
	return sessions_dir.path_join(id + ".json")

func _replay_path(name: String) -> String:
	return replays_dir.path_join(name + ".replay.json")

func new_session(req: Dictionary) -> Dictionary:
	var agent = String(req.get("agent", "agent"))
	var agent_re = RegEx.new()
	agent_re.compile("^[a-z][a-z0-9-]{0,23}$")
	if agent_re.search(agent) == null:
		return fail("INVALID_AGENT", "agent must use 1-24 lowercase letters, digits or hyphens, starting with a letter")
	var config = normalize_config(req)
	if config.is_empty():
		return fail("INVALID_CONFIG", "mode or character is invalid")
	var id = String(req.get("session", ""))
	if id == "":
		id = "%s-%s-%s-%s-%s" % [_stamp(), agent, config["mode"], _chars_slug(config), _random_hex(3)]
	if not _valid_id(id):
		return fail("INVALID_SESSION", "session must use 1-96 letters, digits, underscores or hyphens")
	if FileAccess.file_exists(_session_path(id)) or not find_replay(id).is_empty():
		return fail("SESSION_EXISTS", "This session already exists; choose a different name")
	var w = _create_world(config)
	var meta = _recording_meta(agent, config)
	var parts = id.split("-")
	if parts.size() > 1:
		meta["id"] = parts[parts.size() - 1]
	var s = {
		"id": id, "config": config, "world": w, "revision": 0, "history": [],
		"requests": {}, "recording": meta, "archived": false,
		"replay_file": "", "created_at": _iso_utc(), "last_response": null,
	}
	memory[id] = s
	_save_session(s)
	return _response(s, {"advancedFrames": 0, "stopReason": "frames_complete", "events": []}, false)

func _load_session(id: String) -> Dictionary:
	if memory.has(id):
		return {"ok": true, "session": memory[id]}
	var path = _session_path(id)
	if not FileAccess.file_exists(path):
		var replay = find_replay(id)
		if not replay.is_empty():
			var data = _read_json(replay)
			if not data.is_empty():
				var config = normalize_config({"mode": data.get("config", {}).get("mode", ""),
					"seed": data.get("config", {}).get("seed", ""),
					"character": data.get("config", {}).get("chars", ["xiaonuo"])[0],
					"character2": data.get("config", {}).get("chars", ["xiaonuo", "axiu"])[1]})
				if not config.is_empty():
					var w = _replay_world(config, data.get("history", []), false)
					if w != null:
						var rs = {"id": id, "config": config, "world": w,
							"revision": int(data.get("history", []).size()), "history": data.get("history", []),
							"requests": {}, "recording": data.get("recording", {}), "archived": true,
							"replay_file": replay, "created_at": "", "last_response": data.get("receipt", null)}
						memory[id] = rs
						return {"ok": true, "session": rs}
		return fail("SESSION_NOT_FOUND", "Session does not exist; create it with new")
	var data = _read_json(path)
	if data.is_empty():
		return fail("SESSION_CORRUPT", "Session JSON could not be parsed")
	if String(data.get("format", "")) != SESSION_FORMAT or String(data.get("engineVersion", "")) != ENGINE_VERSION:
		return fail("INCOMPATIBLE_SESSION", "Rules changed or session format is unsupported; create a new session")
	var config = data.get("config", {})
	var history = data.get("history", [])
	var w = _replay_world(config, history, false)
	if w == null:
		return fail("SESSION_CORRUPT", "Session history could not be replayed")
	var s = {"id": id, "config": config, "world": w, "revision": int(data.get("revision", history.size())),
		"history": history, "requests": data.get("requests", {}), "recording": data.get("recording", {}),
		"archived": bool(data.get("archived", false)), "replay_file": String(data.get("replay_file", "")),
		"created_at": String(data.get("created_at", "")), "last_response": data.get("last_response", null)}
	memory[id] = s
	return {"ok": true, "session": s}

func _save_session(s: Dictionary, force: bool = false) -> void:
	if not autosave and not force:
		return
	var path = _session_path(String(s["id"]))
	var data = {
		"format": SESSION_FORMAT, "engineVersion": ENGINE_VERSION, "config": s["config"],
		"revision": s["revision"], "history": s["history"], "requests": s["requests"],
		"recording": s["recording"], "archived": s["archived"], "replay_file": s["replay_file"],
		"created_at": s["created_at"], "last_response": s["last_response"],
	}
	var tmp = path + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)

func _delete_session_file(id: String) -> void:
	var path = _session_path(id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _response(s: Dictionary, extra: Dictionary, assist: bool) -> Dictionary:
	var sid = String(s.get("recording", {}).get("name", ""))
	if sid == "":
		sid = String(s["id"])
	var out = {"ok": true, "session": sid, "revision": int(s["revision"])}
	if bool(s.get("archived", false)):
		out["archived"] = true
		out["replayFile"] = String(s.get("replay_file", ""))
	out.merge(extra, true)
	out["state"] = observe(s["world"], assist)
	return out

# ---------------------------------------------------------------- actions

func normalize_action(world: World, req: Dictionary) -> Dictionary:
	var frames = int(req.get("frames", 12))
	if frames < 1 or frames > 60:
		return {}
	var player = String(req.get("player", "p1"))
	if world.player_by_id(player) == null:
		return {}
	var raw = req.get("actions", null)
	if raw == null:
		raw = {player: {"move": req.get("move", "none"), "bomb": req.get("bomb", false),
			"skill": req.get("skill", false), "wait": req.get("wait", false)}}
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var actions = {}
	for id in raw.keys():
		if world.player_by_id(String(id)) == null:
			return {}
		var a = raw[id]
		if typeof(a) != TYPE_DICTIONARY:
			return {}
		for k in a.keys():
			if not ["move", "bomb", "skill", "wait"].has(String(k)):
				return {}
		var move = String(a.get("move", "none"))
		if not DIRS.has(move):
			return {}
		var bomb = bool(a.get("bomb", false))
		var skill = bool(a.get("skill", false))
		var wait = bool(a.get("wait", false))
		if wait and (move != "none" or bomb or skill):
			return {}
		actions[String(id)] = {"move": move, "bomb": bomb, "skill": skill}
	return {"frames": frames, "actions": actions}

func _advance(world: World, action: Dictionary, collect_events: bool = true) -> Dictionary:
	var frames = int(action.get("frames", 1))
	var acts = action.get("actions", {})
	var events: Array = []
	var start = world.frame
	var stop_reason = "frames_complete"
	if world.match.over:
		return {"advancedFrames": 0, "stopReason": "finished", "events": []}
	for i in frames:
		var inputs = {}
		for id in acts.keys():
			var a = acts[id]
			var d = DIRS[String(a.get("move", "none"))]
			inputs[String(id)] = {"hx": d.x, "hy": d.y,
				"bomb": i == 0 and bool(a.get("bomb", false)),
				"skill": i == 0 and bool(a.get("skill", false))}
			if i == 0 and (bool(a.get("bomb", false)) or bool(a.get("skill", false))):
				var dead_p = world.player_by_id(String(id))
				if dead_p != null and not dead_p.alive:
					events.append({"type": "action_rejected", "player": id, "reason": "dead", "frame": world.frame})
		var before: Array = []
		for p in world.players:
			before.append([p.x, p.y])
		GameEngine.step(world, inputs, DT)
		if world.briefing:
			world.briefing = false
		for idx in world.players.size():
			var p = world.players[idx]
			var a = acts.get(p.id, null)
			if a != null and i == 0 and String(a.get("move", "none")) != "none" and p.alive:
				if is_equal_approx(float(before[idx][0]), p.x) and is_equal_approx(float(before[idx][1]), p.y):
					events.append({"type": "blocked", "player": p.id, "frame": world.frame})
		# requested bomb / skill feedback
		if i == 0:
			for id in acts.keys():
				var a = acts[id]
				var p = world.player_by_id(String(id))
				if p == null:
					continue
				if bool(a.get("bomb", false)):
					var ok = _has_event(world, "bomb_place", "owner", id)
					events.append({"type": "bomb_action", "player": id, "success": ok,
						"reason": "" if ok else ("dead" if not p.alive else "unavailable"), "frame": world.frame})
				if bool(a.get("skill", false)):
					var ok_s = _has_event(world, "skill", "player", id)
					events.append({"type": "skill_action", "player": id, "success": ok_s,
						"reason": "" if ok_s else ("dead" if not p.alive else "unavailable"), "frame": world.frame})
		for e in world.events:
			events.append(_event_out(e, world.frame))
		for e in world.events:
			if STOP_EVENTS.has(String(e.get("kind", ""))):
				stop_reason = _stop_name(String(e.get("kind", "")))
				break
		if stop_reason != "frames_complete":
			break
	return {"advancedFrames": world.frame - start, "stopReason": stop_reason, "events": events}

func _has_event(world: World, kind: String, key: String, value: String) -> bool:
	for e in world.events:
		if String(e.get("kind", "")) == kind and String(e.get(key, "")) == value:
			return true
	return false

func _stop_name(kind: String) -> String:
	match kind:
		"death": return "onDeath"
		"level_started": return "level_started"
		"round_started": return "round_started"
		"match_over": return "match_over"
	return kind

func _event_out(e: Dictionary, frame: int) -> Dictionary:
	var kind = String(e.get("kind", "event"))
	var out = e.duplicate()
	out.erase("kind")
	match kind:
		"explode": out["type"] = "onExplode"
		"death": out["type"] = "onDeath"
		"enemy_death": out["type"] = "onEnemyDeath"
		"boss_phase": out["type"] = "onBossPhase"
		"pickup": out["type"] = "onPickup"
		"skill": out["type"] = "onSkill"
		"bomb_place": out["type"] = "onPlaceBomb"
		_: out["type"] = kind
	out["frame"] = frame
	return out

# ---------------------------------------------------------------- apply

func handle(req: Dictionary) -> Dictionary:
	if typeof(req) != TYPE_DICTIONARY:
		return fail("INVALID_REQUEST", "Request must be a JSON object")
	var op = String(req.get("op", ""))
	if op == "rules":
		return {"ok": true, "rules": rules()}
	if not ["new", "state", "act", "batch", "path", "goTo", "checkpoint", "replay", "export", "finish"].has(op):
		return fail("INVALID_OPERATION", "Unknown operation")
	if op == "new":
		return new_session(req)
	if op == "replay" and req.has("file"):
		return replay_file(String(req.get("file", "")), bool(req.get("assist", false)))
	var id = String(req.get("session", ""))
	if id == "":
		return fail("INVALID_SESSION", "session is required")
	var loaded = _load_session(id)
	if not bool(loaded.get("ok", false)):
		return loaded
	var s: Dictionary = loaded["session"]
	var world: World = s["world"]
	var assist = bool(req.get("assist", false))
	if op == "state":
		return _response(s, {}, assist)
	if op == "export":
		return {"ok": true, "session": id, "replay": _replay_data(s)}
	if op == "replay":
		var report = _verify_history(s["config"], s["history"])
		if not bool(report.get("ok", false)):
			return report
		return _response(s, {"verified": true, "actions": s["history"].size(),
			"hash": state_hash(s["world"])}, assist)
	if op == "checkpoint":
		_save_session(s, true)
		return _response(s, {"checkpointed": true}, assist)
	if op == "finish":
		if bool(s.get("archived", false)):
			return _response(s, {"archived": true, "verified": true,
				"replayFile": s.get("replay_file", "")}, assist)
		var verified = _verify_history(s["config"], s["history"])
		if not bool(verified.get("ok", false)):
			return verified
		var replay_file = _archive(s)
		if replay_file == "":
			return fail("ARCHIVE_FAILED", "Could not write replay archive")
		_delete_session_file(id)
		memory.erase(id)
		s["archived"] = true
		s["replay_file"] = replay_file
		return _response(s, {"archived": true, "verified": true, "replayFile": replay_file}, assist)

	var commands: Array = []
	var navigation = null
	if op == "batch":
		if typeof(req.get("steps", null)) != TYPE_ARRAY:
			return fail("INVALID_BATCH", "steps must be an array")
		var steps: Array = req.get("steps", [])
		if steps.size() < 1 or steps.size() > 1024:
			return fail("INVALID_BATCH", "steps must contain 1..1024 action objects")
		for step in steps:
			if typeof(step) != TYPE_DICTIONARY:
				return fail("INVALID_BATCH", "Each step must be an action object")
			for k in step.keys():
				if not ["move", "bomb", "skill", "wait", "frames", "player", "actions"].has(String(k)):
					return fail("INVALID_BATCH", "Each step must contain only action fields")
			var a = normalize_action(world, step)
			if a.is_empty():
				return fail("INVALID_ACTION", "Invalid action in batch")
			commands.append(a)
	elif op == "path" or op == "goTo":
		navigation = normalize_navigation(world, req)
		if navigation.is_empty():
			return fail("INVALID_NAVIGATION", "Invalid path or target")
	else:
		var a = normalize_action(world, req)
		if a.is_empty():
			return fail("INVALID_ACTION", "Invalid action")
		commands.append(a)

	var fingerprint = _sha(JSON.stringify({"op": op, "commands": commands, "navigation": navigation}))
	var request_id = String(req.get("requestId", ""))
	if request_id != "":
		if request_id.length() > 128:
			return fail("INVALID_REQUEST_ID", "requestId must contain 1-128 characters")
		if s["requests"].has(request_id):
			var prev = s["requests"][request_id]
			if String(prev.get("fingerprint", "")) != fingerprint:
				return fail("REQUEST_ID_CONFLICT", "This requestId was already used for a different action")
			if int(prev.get("revision", -1)) == int(s["revision"]):
				var dup = _response(s, {"advancedFrames": 0, "stopReason": "duplicate", "events": [], "duplicate": true}, assist)
				return dup
			return fail("ALREADY_APPLIED", "This request was applied at revision %d; read state to continue" % int(prev.get("revision", 0)))
	if req.has("expectRevision"):
		if int(req.get("expectRevision", -1)) != int(s["revision"]):
			return fail("REVISION_CONFLICT", "Current revision is %d; read state before acting" % int(s["revision"]))
	if bool(s.get("archived", false)):
		return _response(s, {"advancedFrames": 0, "stopReason": "archived", "events": []}, assist)

	var start_revision = int(s["revision"])
	var result = {"advancedFrames": 0, "stopReason": "frames_complete", "events": [], "completedActions": 0}
	if navigation != null:
		var nav = _navigate(world, s, navigation, op == "goTo", result)
		for k in nav.keys():
			result[k] = nav[k]
	else:
		for action in commands:
			var step = _advance(world, action)
			result["advancedFrames"] += int(step.get("advancedFrames", 0))
			result["events"].append_array(step.get("events", []))
			result["stopReason"] = String(step.get("stopReason", "frames_complete"))
			if int(step.get("advancedFrames", 0)) > 0:
				s["revision"] = int(s["revision"]) + 1
				result["completedActions"] += 1
				var h = state_hash(world)
				s["history"].append({"revision": s["revision"], "requestId": request_id,
					"fingerprint": fingerprint, "action": action,
					"advancedFrames": int(step.get("advancedFrames", 0)), "hash": h})
			if String(step.get("stopReason", "frames_complete")) != "frames_complete":
				break
	if int(s["revision"]) == start_revision:
		return _response(s, result, assist)
	if request_id != "":
		s["requests"][request_id] = {"fingerprint": fingerprint, "revision": int(s["revision"])}
		while s["requests"].size() > 256:
			s["requests"].erase(s["requests"].keys()[0])
	var out = _response(s, result, assist)
	s["last_response"] = {"revision": s["revision"], "advancedFrames": result["advancedFrames"],
		"stopReason": result["stopReason"], "events": result["events"]}
	_save_session(s)
	if world.match.over:
		var verified = _verify_history(s["config"], s["history"])
		if not bool(verified.get("ok", false)):
			return verified
		var replay_file = _archive(s)
		if replay_file != "":
			_delete_session_file(String(s["id"]))
			s["archived"] = true
			s["replay_file"] = replay_file
			out = _response(s, result, assist)
			out["archived"] = true
			out["replayFile"] = replay_file
			out["verified"] = true
	return out

# ---------------------------------------------------------------- navigation

func normalize_navigation(world: World, req: Dictionary) -> Dictionary:
	var max_frames = int(req.get("maxFrames", 3600))
	if max_frames < 1 or max_frames > 3600:
		return {}
	if req.has("path"):
		var cells = req.get("path", [])
		if typeof(cells) != TYPE_ARRAY or cells.size() < 1 or cells.size() > 256:
			return {}
		var path: Array = []
		for cell in cells:
			if typeof(cell) != TYPE_ARRAY or cell.size() < 2:
				return {}
			var c = int(cell[0])
			var r = int(cell[1])
			if not Grid.in_bounds(c, r):
				return {}
			if path.size() > 0:
				var prev: Vector2i = path[path.size() - 1]
				if absi(prev.x - c) + absi(prev.y - r) != 1:
					return {}
			path.append(Vector2i(c, r))
		return {"kind": "path", "path": path, "maxFrames": max_frames}
	if req.has("target"):
		var target = req.get("target", [])
		if typeof(target) != TYPE_ARRAY or target.size() < 2:
			return {}
		var c = int(target[0])
		var r = int(target[1])
		if not Grid.in_bounds(c, r):
			return {}
		return {"kind": "goTo", "target": Vector2i(c, r), "maxFrames": max_frames}
	return {}

func _walkable(world: World, c: int, r: int) -> bool:
	if not Grid.in_bounds(c, r):
		return false
	if Grid.at(world.map, c, r) != Cfg.T_EMPTY:
		return false
	for b in world.bombs:
		if b.cx == c and b.cy == r:
			return false
	return true

func _bfs(world: World, start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return [start]
	if not _walkable(world, goal.x, goal.y):
		return []
	var q: Array = [start]
	var prev: Dictionary = {start: start}
	var head = 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		if cur == goal:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + d
			if prev.has(nxt) or not _walkable(world, nxt.x, nxt.y):
				continue
			prev[nxt] = cur
			q.append(nxt)
	if not prev.has(goal):
		return []
	var path: Array = [goal]
	var cur = goal
	while cur != start:
		cur = prev[cur]
		path.push_front(cur)
	return path

func _navigate(world: World, s: Dictionary, nav: Dictionary, is_goto: bool, result: Dictionary) -> Dictionary:
	var p = world.player_by_id("p1")
	if p == null:
		return {"stopReason": "dead", "reached": false}
	var start_cell = Vector2i(Grid.col(p.x), Grid.row(p.y))
	var path: Array = []
	if is_goto:
		path = _bfs(world, start_cell, nav["target"])
	elif not nav["path"].is_empty():
		path = nav["path"].duplicate()
	if path.is_empty():
		return {"stopReason": "blocked", "reached": false, "plannedPath": [],
			"completedWaypoints": 0}
	var max_frames = int(nav.get("maxFrames", 3600))
	var used = 0
	var waypoint_index = 0
	var completed = 0
	var group_dir = "none"
	var group_actions = {}
	var group_frames = 0
	var start_revision = int(s["revision"])
	var stop = "path_complete"
	var blocked_frames = 0

	while used < max_frames:
		if world.match.over:
			stop = "match_over"
			break
		if not p.alive:
			stop = "dead"
			break
		var target: Vector2i = path[waypoint_index]
		var tx = Grid.center_x(target.x)
		var ty = Grid.center_y(target.y)
		if absf(tx - p.x) <= 2.5 and absf(ty - p.y) <= 2.5:
			completed += 1
			waypoint_index += 1
			if waypoint_index >= path.size():
				stop = "path_complete"
				break
			continue
		var dir = "none"
		if absf(tx - p.x) > 2.5:
			dir = "right" if tx > p.x else "left"
		elif absf(ty - p.y) > 2.5:
			dir = "down" if ty > p.y else "up"
		else:
			completed += 1
			waypoint_index += 1
			if waypoint_index >= path.size():
				stop = "path_complete"
				break
			continue
		# Flush the previous direction before stepping, so each recorded
		# entry's hash describes exactly the state after its own frames.
		if dir != group_dir:
			if group_frames > 0:
				_flush_nav_group(world, s, group_dir, group_actions, group_frames, result)
			group_dir = dir
			group_actions = {"p1": {"move": dir, "bomb": false, "skill": false}}
			group_frames = 0
		var d = DIRS[dir]
		var before_x = p.x
		var before_y = p.y
		GameEngine.step(world, {"p1": {"hx": d.x, "hy": d.y, "bomb": false, "skill": false}}, DT)
		if world.briefing:
			world.briefing = false
		used += 1
		group_frames += 1
		if is_equal_approx(before_x, p.x) and is_equal_approx(before_y, p.y):
			blocked_frames += 1
			if blocked_frames > 90:
				stop = "blocked"
				break
		else:
			blocked_frames = 0
		var stopped = false
		for e in world.events:
			if STOP_EVENTS.has(String(e.get("kind", ""))):
				stop = _stop_name(String(e.get("kind", "")))
				stopped = true
				break
		if stopped:
			break
		if group_frames >= 60:
			_flush_nav_group(world, s, group_dir, group_actions, group_frames, result)
			group_frames = 0
	if group_frames > 0:
		_flush_nav_group(world, s, group_dir, group_actions, group_frames, result)
	result["completedActions"] = int(s["revision"]) - start_revision
	result["plannedPath"] = _cells_out(path)
	result["completedWaypoints"] = completed
	result["reached"] = stop == "path_complete"
	result["stopReason"] = stop
	return result

func _flush_nav_group(world: World, s: Dictionary, dir: String, acts: Dictionary, frames: int, result: Dictionary) -> void:
	var action = {"frames": frames, "actions": acts}
	s["revision"] = int(s["revision"]) + 1
	s["history"].append({"revision": s["revision"], "requestId": "", "fingerprint": "",
		"action": action, "advancedFrames": frames, "hash": state_hash(world)})
	result["advancedFrames"] = int(result.get("advancedFrames", 0)) + frames

func _cells_out(cells: Array) -> Array:
	var out = []
	for c in cells:
		out.append([c.x, c.y])
	return out

# ---------------------------------------------------------------- hash + verify

func state_hash(world: World) -> String:
	return _sha(JSON.stringify(_state_blob(world)))

func _state_blob(world: World) -> Dictionary:
	var players = []
	for p in world.players:
		players.append(_actor_blob(p, false))
	var enemies = []
	for e in world.enemies:
		enemies.append(_actor_blob(e, true))
	var bombs = []
	for b in world.bombs:
		bombs.append({"cx": b.cx, "cy": b.cy, "x": b.x, "y": b.y, "power": b.power,
			"fuse": b.fuse, "fuse_total": b.fuse_total, "owner_id": b.owner_id,
			"pass_for": b.pass_for, "free_for": b.free_for, "slide": b.slide,
			"by_enemy": b.by_enemy, "break_hard": b.break_hard})
	var m = world.match
	return {
		"frame": world.frame, "time": world.time, "mode": world.mode, "theme": world.theme,
		"map": world.map, "spawns": world.spawns, "rng": world.rng.state,
		"players": players, "enemies": enemies, "bombs": bombs,
		"flames": world.flames, "poison": world.poison, "items": world.items,
		"match": {"level": m.level, "round": m.round, "remaining": m.remaining,
			"scores": m.scores, "target_score": m.target_score, "over": m.over,
			"winner": m.winner, "title": m.title, "subtitle": m.subtitle,
			"sudden": m.sudden, "round_ends_at": m.round_ends_at,
			"level_clear_at": m.level_clear_at, "elapsed": m.elapsed},
		"next_entity_id": world.next_entity_id, "boss_battle": world.boss_battle,
		"time_stop": world.time_stop, "stats": world.stats,
		"landmark": _landmark_blob(world.landmark), "brick_variants": world.brick_variants,
		"skill_effects": _effects_blob(world.skill_effects), "pending_deaths": _pending_blob(world.pending_deaths),
		"seen_enemies": world.seen_enemies, "map_revision": world.map_revision,
		"level_started": world.level_started, "result_shown": world.result_shown,
	}

func _actor_blob(a, enemy: bool) -> Dictionary:
	var out = {"id": a.id, "x": a.x, "y": a.y, "px": a.px, "py": a.py,
		"alive": a.alive, "power": a.power, "max_bombs": a.max_bombs,
		"speed_bonus": a.speed_bonus, "shield": a.shield, "star_time": a.star_time,
		"invuln": a.invuln, "glove": a.glove, "facing": a.facing, "facing_dir": a.facing_dir,
		"moving": a.moving, "axis_pref": a.axis_pref, "squash": a.squash,
		"dead_at": a.dead_at, "lives": a.lives, "skill_cd": a.skill_cd,
		"flame_guard": a.flame_guard, "insight_time": a.insight_time, "slow_time": a.slow_time,
		"cast_flash": a.cast_flash, "aim_x": a.aim_x, "aim_y": a.aim_y,
		"picked": a.picked, "soul_evolved": a.soul_evolved, "soul_bombs": a.soul_bombs,
		"soul_awaken_time": a.soul_awaken_time, "soul_slow_time": a.soul_slow_time,
		"soul_slow_rate": a.soul_slow_rate, "soul_slow_owner_id": a.soul_slow_owner_id,
		"soul_slow_assist_until": a.soul_slow_assist_until, "carousel_travel": a.carousel_travel,
		"carousel_rewarded": a.carousel_rewarded}
	if enemy:
		out.merge({"type": a.type, "hp": a.hp, "max_hp": a.max_hp, "phase": a.phase,
			"phase_flash": a.phase_flash, "bomb_gap": a.bomb_gap, "windup": a.windup,
			"ability_cd": a.ability_cd, "level": a.level, "speed": a.speed,
			"hit_flash": a.hit_flash, "stun": a.stun, "dir": a.dir,
			"tc": a.tc, "tr": a.tr, "from_c": a.from_c, "from_r": a.from_r,
			"bomb_cd": a.bomb_cd, "last_x": a.last_x, "last_y": a.last_y,
			"has_last": a.has_last, "returning": a.returning,
			"scenery_motion": a.scenery_motion, "escape_path": _path_blob(a.escape_path),
			"queued_bomb": a.queued_bomb}, true)
	return out

func _effects_blob(effects: Array) -> Array:
	var out = []
	for e in effects:
		out.append({"type": e.get("type", ""), "x": e.get("x", 0.0), "y": e.get("y", 0.0),
			"to_x": e.get("to_x", 0.0), "to_y": e.get("to_y", 0.0),
			"owner": e.get("owner", ""), "radius": e.get("radius", 0),
			"evolved": e.get("evolved", false), "t": e.get("t", 0.0), "total": e.get("total", 0.0)})
	return out

func _pending_blob(pending: Array) -> Array:
	var out = []
	for p in pending:
		if p != null:
			out.append(String(p.id))
	return out

func _path_blob(path: Array) -> Array:
	var out = []
	for c in path:
		if c is Vector2i:
			out.append([c.x, c.y])
		elif c is Vector2:
			out.append([c.x, c.y])
		else:
			out.append(c)
	return out

func _landmark_blob(l: Dictionary) -> Dictionary:
	if l.is_empty():
		return {}
	var path = []
	for c in l.get("path", []):
		path.append([c.x, c.y])
	return {"theme": l.get("theme", ""), "c": l.get("c", 0), "r": l.get("r", 0),
		"path": path, "fruitTimer": l.get("fruit_timer", 0.0),
		"lastFruitAt": l.get("last_fruit_at", 0.0), "pathLen": l.get("path_len", 0)}

func _replay_world(config: Dictionary, history: Array, check: bool) -> World:
	var cfg = normalize_config({"mode": config.get("mode", ""), "seed": config.get("seed", ""),
		"character": config.get("chars", ["xiaonuo"])[0],
		"character2": config.get("chars", ["xiaonuo", "axiu"])[1] if config.get("chars", []).size() > 1 else "axiu"})
	if cfg.is_empty():
		return null
	var w = _create_world(cfg)
	for entry in history:
		var step = _advance(w, entry.get("action", {}), false)
		if check:
			if int(step.get("advancedFrames", 0)) != int(entry.get("advancedFrames", -1)):
				return null
			if state_hash(w) != String(entry.get("hash", "")):
				return null
	return w

func _verify_history(config: Dictionary, history: Array) -> Dictionary:
	var w = _replay_world(config, history, true)
	if w == null:
		return fail("REPLAY_MISMATCH", "Replay diverged; the recorded engine state no longer matches")
	return {"ok": true, "world": w}

# ---------------------------------------------------------------- replay files

func _replay_data(s: Dictionary) -> Dictionary:
	return {"format": REPLAY_FORMAT, "engineVersion": ENGINE_VERSION,
		"config": s["config"], "history": s["history"], "finalHash": state_hash(s["world"]),
		"recording": s["recording"]}

func _archive(s: Dictionary) -> String:
	var outcome = "stopped"
	if bool(s["world"].match.over):
		if String(s["world"].match.winner) == "draw":
			outcome = "draw"
		elif String(s["world"].match.winner) == "p1":
			outcome = "win"
		else:
			outcome = "loss"
	var meta = s["recording"].duplicate()
	meta["sourceSession"] = s["id"]
	meta["endedAt"] = _iso_utc()
	meta["outcome"] = outcome
	meta["character"] = s["config"]["chars"][0]
	meta["characters"] = _used_chars(s["config"])
	var name = _replay_name(String(s["id"]), outcome)
	meta["name"] = name
	var data = _replay_data(s)
	data["recording"] = meta
	data["receipt"] = s.get("last_response", null)
	var path = _replay_path(name)
	var f = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return ""
	s["recording"] = meta
	return path

func _replay_name(id: String, outcome: String) -> String:
	var parts = id.split("-")
	if parts.size() >= 2:
		var rid = parts[parts.size() - 1]
		var stem = "-".join(parts.slice(0, parts.size() - 1))
		return "%s-%s-%s" % [stem, outcome, rid]
	return id + "-" + outcome

func find_replay(id: String) -> String:
	var dir = DirAccess.open(replays_dir)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var name = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".replay.json"):
			var data = _read_json(replays_dir.path_join(name))
			if not data.is_empty():
				var rec = data.get("recording", {})
				if String(rec.get("name", "")) == id or String(rec.get("sourceSession", "")) == id:
					dir.list_dir_end()
					return replays_dir.path_join(name)
		name = dir.get_next()
	dir.list_dir_end()
	return ""

func replay_file(path: String, assist: bool) -> Dictionary:
	var data = _read_json(path)
	if data.is_empty():
		return fail("INVALID_REPLAY", "Replay JSON could not be parsed")
	var fmt = String(data.get("format", ""))
	if fmt == REPLAY_FORMAT:
		var config = data.get("config", {})
		var history = data.get("history", [])
		var w = _replay_world(config, history, true)
		if w == null:
			return fail("REPLAY_MISMATCH", "Replay diverged or hashes do not match")
		return {"ok": true, "session": String(data.get("recording", {}).get("name", "replay")),
			"revision": history.size(), "verified": true, "actions": history.size(),
			"hash": state_hash(w), "state": observe(w, assist)}
	if fmt == "bombit-replay/1" or fmt == "bombit-session/1":
		var raw_config = data.get("config", {})
		var config = normalize_config({"mode": raw_config.get("mode", "adventure"),
			"seed": raw_config.get("seed", "demo"),
			"character": raw_config.get("chars", ["xiaonuo"])[0],
			"character2": raw_config.get("chars", ["xiaonuo", "axiu"])[1] if raw_config.get("chars", []).size() > 1 else "axiu"})
		if config.is_empty():
			return fail("INVALID_REPLAY", "Replay opening config is invalid")
		var w = _create_world(config)
		for entry in data.get("history", []):
			_advance(w, entry.get("action", {}), false)
		return {"ok": true, "session": "replay", "revision": data.get("history", []).size(),
			"verified": false, "compatibility": "original-unverified", "actions": data.get("history", []).size(),
			"hash": state_hash(w), "state": observe(w, assist),
			"note": "Original JavaScript replay: action playback is compatible, but cryptographic hashes were not verified."}
	return fail("INVALID_REPLAY", "Unsupported replay format")

func list_replays() -> Array:
	var out = []
	var seen = {}
	# Loose files in the writable replay directory (editor: data/replays).
	for dir_path in [replays_dir]:
		var dir = DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name = dir.get_next()
		while name != "":
			if not dir.current_is_dir() and name.ends_with(".replay.json"):
				_add_replay(dir_path.path_join(name), out, seen)
			name = dir.get_next()
		dir.list_dir_end()
	# Packed export: DirAccess cannot reliably enumerate PCK directories, so
	# data/replays/index.json is the manifest for bundled sample replays.
	var bundled = ProjectSettings.globalize_path("res://data/replays")
	var index = _read_json(bundled.path_join("index.json"))
	for fname in index.get("files", []):
		_add_replay(bundled.path_join(String(fname)), out, seen)
	# A few builds may still expose the directory directly.
	var dir2 = DirAccess.open(bundled)
	if dir2 != null:
		dir2.list_dir_begin()
		var n2 = dir2.get_next()
		while n2 != "":
			if not dir2.current_is_dir() and n2.ends_with(".replay.json"):
				_add_replay(bundled.path_join(n2), out, seen)
			n2 = dir2.get_next()
		dir2.list_dir_end()
	out.sort_custom(func(a, b): return String(a["file"]) > String(b["file"]))
	return out

func _add_replay(full: String, out: Array, seen: Dictionary) -> void:
	if seen.has(full) or not FileAccess.file_exists(full):
		return
	seen[full] = true
	var data = _read_json(full)
	if data.is_empty():
		return
	var rec = data.get("recording", {})
	var base = full.get_file()
	out.append({"file": full, "name": base.get_basename().replace(".replay", ""),
		"format": data.get("format", ""), "mode": data.get("config", {}).get("mode", ""),
		"agent": rec.get("agent", ""), "outcome": rec.get("outcome", ""),
		"characters": rec.get("characters", data.get("config", {}).get("chars", [])),
		"startedAt": rec.get("startedAt", ""), "actions": data.get("history", []).size()})


# ---------------------------------------------------------------- observation

func _r6(v) -> float:
	return round(float(v) * 1000000.0) / 1000000.0

func observe(world: World, assist: bool = false) -> Dictionary:
	var terrain = []
	for r in Cfg.ROWS:
		var line = ""
		for c in Cfg.COLS:
			var t = Grid.at(world.map, c, r)
			line += "#" if t == Cfg.T_HARD else ("+" if t == Cfg.T_BRICK else ".")
		terrain.append(line)
	var players = []
	for p in world.players:
		var a = _actor_obs(p)
		a["assetId"] = p.asset_id
		a["character"] = p.asset_id
		a["lives"] = p.lives
		a["skillCd"] = _r6(p.skill_cd)
		a["flameGuard"] = _r6(p.flame_guard)
		a["insightTime"] = _r6(p.insight_time)
		a["slowTime"] = _r6(p.slow_time)
		a["soulEvolved"] = p.soul_evolved
		a["soulBombs"] = p.soul_bombs
		a["carouselTravel"] = _r6(p.carousel_travel)
		a["carouselRewarded"] = p.carousel_rewarded
		a["bombsOut"] = _bombs_out(world, p.id)
		var speed = Cfg.SPEED_BASE * (1.0 + p.speed_bonus)
		if p.insight_time > 0.0:
			speed *= 1.3
		speed *= minf(0.5 if p.slow_time > 0.0 else 1.0, Skills.slow_factor(p))
		a["speedTilesPerSecond"] = _r6(speed)
		var skill = Cfg.SKILLS.get(p.asset_id, {}).duplicate()
		if skill.has("color"):
			skill["color"] = Color(skill["color"]).to_html(false)
		a["skill"] = skill
		a["skillReady"] = p.alive and not bool(skill.get("passive", false)) and p.skill_cd <= 0.0 and not world.briefing and not world.match.over
		a["respawnIn"] = null
		if not p.alive and Match.can_respawn(world, p):
			a["respawnIn"] = _r6(maxf(0.0, Cfg.RESPAWN_DELAY - (world.time - p.dead_at)))
		players.append(a)
	var enemies = []
	for e in world.enemies:
		var a = _actor_obs(e)
		a["type"] = e.type
		a["name"] = e.name
		a["hp"] = e.hp
		a["maxHp"] = e.max_hp
		a["phase"] = e.phase
		a["windup"] = _r6(e.windup)
		a["stun"] = _r6(e.stun)
		a["speedTilesPerSecond"] = _r6(EnemyAI.move_speed(e) * (1.0 + e.speed_bonus))
		enemies.append(a)
	var bombs = []
	for b in world.bombs:
		var pos = Grid.bomb_position(b)
		bombs.append({"ownerId": b.owner_id, "power": b.power, "fuse": _r6(b.fuse),
			"fuseTotal": _r6(b.fuse_total), "slide": b.slide, "freeFor": b.free_for,
			"passFor": b.pass_for, "byEnemy": b.by_enemy, "breakHard": b.break_hard,
			"col": b.cx, "row": b.cy, "x": _r6(pos.x), "y": _r6(pos.y)})
	var flames = []
	for f in world.flames:
		var cells = []
		for cell in f.get("cells", []):
			cells.append([int(cell[0]), int(cell[1])])
		flames.append({"cells": cells, "remaining": _r6(f.get("t", 0.0))})
	var poison = []
	for p in world.poison:
		poison.append({"c": p.get("c", 0), "r": p.get("r", 0),
			"warn": _r6(p.get("warn", 0.0)), "life": _r6(p.get("life", 0.0))})
	var items = []
	for it in world.items:
		items.append({"col": it.get("c", 0), "row": it.get("r", 0), "type": it.get("type", "")})
	var time_stop = null
	if world.time_stop != null:
		time_stop = {"remaining": _r6(world.time_stop.get("remaining", 0.0)),
			"ownerId": String(world.time_stop.get("owner_id", ""))}
	var m = world.match
	var out = {
		"protocol": "bombit/1", "engine": ENGINE_VERSION, "mode": world.mode,
		"seed": world.seed_root, "frame": world.frame, "time": _r6(world.time),
		"phase": "finished" if m.over else ("briefing" if world.briefing else
			("round_end" if m.round_ends_at > 0.0 else
			("level_clear" if m.level_clear_at > 0.0 else "playing"))),
		"map": {"cols": Cfg.COLS, "rows": Cfg.ROWS, "tileSize": Cfg.TILE,
			"theme": world.theme, "terrain": terrain,
			"landmark": _landmark_blob(world.landmark) if not world.landmark.is_empty() else null,
			"bossBattle": world.boss_battle},
		"match": {"level": m.level, "round": m.round, "remaining": _r6(m.remaining),
			"scores": m.scores.duplicate(), "targetScore": m.target_score,
			"over": m.over, "winner": m.winner, "title": m.title, "subtitle": m.subtitle,
			"sudden": m.sudden, "roundEndsAt": _r6(m.round_ends_at),
			"levelClearAt": _r6(m.level_clear_at), "elapsed": _r6(m.elapsed)},
		"players": players, "enemies": enemies, "bombs": bombs,
		"flames": flames, "poison": poison, "items": items,
		"timeStop": time_stop, "briefing": null,
		"bricksLeft": world.count_bricks(), "enemiesLeft": world.alive_enemies(),
		"stats": world.stats.duplicate(),
	}
	if assist:
		var tl = Danger.timeline(world)
		var windows = []
		var wins: Array = tl.get("windows", [])
		for i in wins.size():
			var arr = wins[i]
			if arr == null or arr.size() == 0:
				continue
			var ww = []
			for pair in arr:
				ww.append([_r6(pair[0]), _r6(pair[1])])
			windows.append({"col": i % Cfg.COLS, "row": i / Cfg.COLS, "windows": ww})
		out["assist"] = {"assumption": "Conservative forecast using current bombs; future placements and terrain changes can alter it.",
			"dangerWindows": windows}
	return out

func _actor_obs(a) -> Dictionary:
	var out = {"id": a.id, "alive": a.alive, "x": _r6(a.x), "y": _r6(a.y),
		"facingDir": a.facing_dir, "facing": a.facing, "power": a.power,
		"maxBombs": a.max_bombs, "speedBonus": _r6(a.speed_bonus), "shield": a.shield,
		"starTime": _r6(a.star_time), "invuln": _r6(a.invuln), "glove": a.glove,
		"soulSlowTime": _r6(a.soul_slow_time), "soulSlowRate": _r6(a.soul_slow_rate)}
	out["col"] = Grid.col(a.x)
	out["row"] = Grid.row(a.y)
	return out

func _bombs_out(world: World, id: String) -> int:
	var n = 0
	for b in world.bombs:
		if b.owner_id == id:
			n += 1
	return n

# ---------------------------------------------------------------- text

func render_text(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "ERROR %s: %s" % [result.get("error", {}).get("code", ""), result.get("error", {}).get("message", "")]
	var lines = []
	var state = result.get("state", null)
	if state != null:
		var map: Dictionary = state.get("map", {})
		var terrain: Array = map.get("terrain", [])
		var rows: Array = []
		for r in terrain.size():
			rows.append(terrain[r].split(""))
		var players: Array = state.get("players", [])
		for p in players:
			var c = int(p.get("col", 0))
			var r = int(p.get("row", 0))
			if r >= 0 and r < rows.size() and c >= 0 and c < rows[r].size():
				rows[r][c] = "1" if String(p.get("id", "")) == "p1" else "2"
		var enemies: Array = state.get("enemies", [])
		for e in enemies:
			var c = int(e.get("col", 0))
			var r = int(e.get("row", 0))
			if r >= 0 and r < rows.size() and c >= 0 and c < rows[r].size():
				rows[r][c] = "X" if String(e.get("type", "")) == "boss" else "E"
		for b in state.get("bombs", []):
			var c = int(b.get("col", 0))
			var r = int(b.get("row", 0))
			if r >= 0 and r < rows.size() and c >= 0 and c < rows[r].size():
				rows[r][c] = "o"
		for f in state.get("flames", []):
			for cell in f.get("cells", []):
				var c = int(cell[0])
				var r = int(cell[1])
				if r >= 0 and r < rows.size() and c >= 0 and c < rows[r].size():
					rows[r][c] = "*"
		for it in state.get("items", []):
			var c = int(it.get("col", 0))
			var r = int(it.get("row", 0))
			if r >= 0 and r < rows.size() and c >= 0 and c < rows[r].size() and rows[r][c] == ".":
				rows[r][c] = "i"
		lines.append("%s  %s  level=%s  frame=%s  time=%.2fs" % [String(state.get("mode", "")),
			String(state.get("theme", "")), state.get("match", {}).get("level", 1),
			state.get("frame", 0), float(state.get("time", 0.0))])
		for row in rows:
			lines.append("".join(row))
		for p in players:
			lines.append("%s %s (%d,%d) life=%s power=%s bombs=%s speed=%.2f" % [p.get("id", ""),
				p.get("character", ""), p.get("col", 0), p.get("row", 0), p.get("lives", 0),
				p.get("power", 0), p.get("maxBombs", 0), float(p.get("speedTilesPerSecond", 0.0))])
		lines.append("bricks=%s enemies=%s revision=%s" % [state.get("bricksLeft", 0),
			state.get("enemiesLeft", 0), result.get("revision", 0)])
	if result.has("events") and result["events"].size() > 0:
		var ev = []
		for e in result["events"]:
			ev.append(String(e.get("type", "")))
		lines.append("events: " + ", ".join(ev))
	if result.has("advancedFrames"):
		lines.append("advancedFrames=%s stopReason=%s" % [result.get("advancedFrames", 0), result.get("stopReason", "")])
	if result.has("replayFile"):
		lines.append("replayFile: " + String(result.get("replayFile", "")))
	return "\n".join(lines)

# ---------------------------------------------------------------- helpers

func _bombs_out_count(world: World, id: String) -> int:
	return _bombs_out(world, id)

func _chars_slug(config: Dictionary) -> String:
	var chars: Array = config.get("chars", [])
	if chars.is_empty():
		return "xiaonuo"
	if String(config.get("mode", "")) == "versus" and chars.size() > 1:
		return "%s-vs-%s" % [chars[0], chars[1]]
	return String(chars[0])

func _used_chars(config: Dictionary) -> Array:
	var chars: Array = config.get("chars", []).duplicate()
	if String(config.get("mode", "")) != "versus":
		return [chars[0]]
	return chars

func _recording_meta(agent: String, config: Dictionary) -> Dictionary:
	return {"id": _random_hex(3), "agent": agent, "startedAt": _iso_utc(),
		"character": config["chars"][0], "characters": _used_chars(config),
		"sourceSession": "", "endedAt": "", "outcome": "", "name": ""}

func _stamp() -> String:
	var unix = int(Time.get_unix_time_from_system()) + 8 * 3600
	var d = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d%02d%02d-%02d%02d%02d" % [int(d["year"]), int(d["month"]), int(d["day"]),
		int(d["hour"]), int(d["minute"]), int(d["second"])]

func _iso_utc() -> String:
	var d = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [int(d["year"]), int(d["month"]), int(d["day"]),
		int(d["hour"]), int(d["minute"]), int(d["second"])]

func _random_hex(n: int) -> String:
	var bytes = Crypto.new().generate_random_bytes(n)
	return bytes.hex_encode()

func _sha(text: String) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var j = JSON.new()
	if j.parse(text) != OK:
		return {}
	if typeof(j.data) != TYPE_DICTIONARY:
		return {}
	return j.data
