extends RefCounted

## BombIt CLI / JSONL / MCP stdio entry point.
##
## Run one command:
##   Godot --headless --script res://scripts/cli/BombitCLI.gd -- new --agent deepseek --json
## Long-lived agent transport:
##   Godot --headless --script res://scripts/cli/BombitCLI.gd -- --mcp
##   Godot --headless --script res://scripts/cli/BombitCLI.gd -- serve --memory
##
## The process is request driven: thinking never advances the game.

const Core = preload("res://scripts/cli/BombitCore.gd")
const VERSION = "1.0.0"

const HELP = """BombIt CLI - deterministic, paused between actions

  bombit new --agent deepseek --mode adventure --seed demo --json
  bombit state --session SESSION_ID --json [--assist]
  bombit act --session SESSION_ID --bomb --frames 1 --json
  bombit act --session SESSION_ID --move down --frames 12 --json
  bombit act --session SESSION_ID --wait --frames 60 --json
  bombit batch --session SESSION_ID --steps '[{\"move\":\"right\",\"frames\":13}]' --json
  bombit path --session SESSION_ID --path '[[1,2],[1,3]]' --json
  bombit goTo --session SESSION_ID --target '[3,1]' --json
  bombit checkpoint --session SESSION_ID --json
  bombit replay --session SESSION_ID --json
  bombit replay --file data/replays/FILE.replay.json --json
  bombit export --session SESSION_ID --json
  bombit finish --session SESSION_ID --json
  bombit rules --json
  bombit play
  bombit serve --memory

Modes: dig, adventure (default), versus.
Characters: xiaonuo, axiu, arui, xiaoyan, xiaotian, weilai.
act: --move up|down|left|right|none, --bomb, --skill, --wait; --frames 1..60.
--player p1|p2 chooses one player. Simultaneous versus actions:
  --actions '{\"p1\":{\"move\":\"right\"},\"p2\":{\"bomb\":true}}'
Optional: --request-id ID, --expect-revision N, --session-dir PATH.
MCP stdio: --mcp (one JSON-RPC message per line).
"""

var core
var json_output = false

func run(args_in: Array) -> int:
	var args = args_in
	if args.is_empty():
		print(HELP)
		return 0
	if args[0] == "--mcp" or args[0] == "mcp":
		return _run_mcp(args)
	var parsed = _parse_args(args)
	if not bool(parsed.get("ok", false)):
		var out = {"ok": false, "error": {"code": String(parsed.get("code", "INVALID_ARGUMENT")),
			"message": String(parsed.get("message", "Invalid arguments"))}}
		print(_json_text(out))
		return 1
	var req: Dictionary = parsed["request"]
	var dir = String(parsed.get("directory", ""))
	if dir == "":
		dir = OS.get_environment("BOMBIT_SESSION_DIR")
	core = Core.new(dir)
	json_output = bool(parsed.get("json", false))
	if String(req.get("op", "")) == "help":
		print(HELP)
		return 0
	if String(req.get("op", "")) == "play":
		return _play(req)
	if String(req.get("op", "")) == "serve" or bool(req.get("jsonl", false)):
		if bool(req.get("memory", false)):
			core.autosave = false
		return _serve_jsonl()
	core.autosave = true
	var result = core.handle(req)
	print(_json_text(result) if json_output or String(req.get("op", "")) == "rules" else core.render_text(result))
	return 0 if bool(result.get("ok", false)) else 1

# ---------------------------------------------------------------- parsing

func _parse_args(argv: Array) -> Dictionary:
	var op = String(argv[0])
	var req = {"op": op}
	var json = false
	var memory = false
	var directory = ""
	var booleans = ["json", "assist", "bomb", "skill", "wait", "memory", "player-mode"]
	var names = {"session": "session", "mode": "mode", "seed": "seed", "character": "character",
		"character2": "character2", "move": "move", "frames": "frames", "player": "player",
		"actions": "actions", "request-id": "requestId", "expect-revision": "expectRevision",
		"session-dir": "directory", "file": "file", "agent": "agent", "steps": "steps",
		"path": "path", "target": "target", "max-frames": "maxFrames",
		"steps-file": "stepsFile", "actions-file": "actionsFile", "path-file": "pathFile"}
	var i = 1
	while i < argv.size():
		var flag = String(argv[i])
		if not flag.begins_with("--"):
			return {"ok": false, "code": "INVALID_ARGUMENT", "message": "Unexpected argument: " + flag}
		var key = flag.substr(2)
		if booleans.has(key):
			if key == "json":
				json = true
			elif key == "memory":
				memory = true
			else:
				req[key] = true
			i += 1
			continue
		if not names.has(key):
			return {"ok": false, "code": "INVALID_ARGUMENT", "message": "Unknown option: " + flag}
		if i + 1 >= argv.size() or String(argv[i + 1]).begins_with("--"):
			return {"ok": false, "code": "INVALID_ARGUMENT", "message": "Missing value for " + flag}
		var value = String(argv[i + 1])
		i += 2
		if key == "session-dir":
			directory = value
		elif key == "frames" or key == "expect-revision" or key == "max-frames":
			if not value.is_valid_int():
				return {"ok": false, "code": "INVALID_ARGUMENT", "message": flag + " must be an integer"}
			req[names[key]] = int(value)
		elif key == "actions" or key == "steps" or key == "path" or key == "target":
			var parsed = _parse_json_text(value)
			if parsed == null:
				if key == "target":
					var bits = value.split(",", false)
					if bits.size() == 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
						parsed = [int(bits[0]), int(bits[1])]
				elif key == "path":
					parsed = _parse_simple_path(value)
			if parsed == null:
				return {"ok": false, "code": "INVALID_JSON", "message": "Invalid JSON for " + flag}
			req[names[key]] = parsed
		elif key == "steps-file" or key == "actions-file" or key == "path-file":
			if not FileAccess.file_exists(value):
				return {"ok": false, "code": "FILE_NOT_FOUND", "message": "File not found: " + value}
			var f = FileAccess.open(value, FileAccess.READ)
			var parsed_file = _parse_json_text(f.get_as_text()) if f != null else null
			if f != null:
				f.close()
			if parsed_file == null:
				return {"ok": false, "code": "INVALID_JSON", "message": "Invalid JSON in " + value}
			req[names[key].replace("File", "")] = parsed_file
		else:
			req[names[key]] = value
	return {"ok": true, "request": req, "json": json, "memory": memory, "directory": directory}

# ---------------------------------------------------------------- stdin / stdout

func _parse_json_text(text: String):
	var j = JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data

func _parse_simple_path(text: String) -> Variant:
	var out = []
	for chunk in text.split(";", false):
		var bits = chunk.split(",", false)
		if bits.size() != 2 or not bits[0].is_valid_int() or not bits[1].is_valid_int():
			return null
		out.append([int(bits[0]), int(bits[1])])
	return out if out.size() > 0 else null

func _read_line() -> String:
	var buf = PackedByteArray()
	while true:
		var chunk = OS.read_buffer_from_stdin(1)
		if chunk.size() == 0:
			return ""
		var b = chunk[0]
		if b == 10:
			break
		if b != 13:
			buf.append(b)
	return buf.get_string_from_utf8()

func _write_line(value: Dictionary) -> void:
	print(_json_text(value))

## JSON over stdio must stay ASCII: Windows consoles and pipes may not be UTF-8.
func _json_text(value) -> String:
	var s = JSON.stringify(value)
	var out = ""
	for i in s.length():
		var c = s.unicode_at(i)
		if c < 128:
			out += String.chr(c)
		elif c <= 0xFFFF:
			out += "\\u%04x" % c
		else:
			var v = c - 0x10000
			out += "\\u%04x\\u%04x" % [0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)]
	return out

# ---------------------------------------------------------------- serve

func _serve_jsonl() -> int:
	while true:
		var line = _read_line()
		if line == "":
			break
		if line.strip_edges() == "":
			continue
		var parsed = JSON.parse_string(line)
		var result
		if typeof(parsed) != TYPE_DICTIONARY:
			result = core.fail("INVALID_JSON", "Request must be a JSON object")
		else:
			result = core.handle(parsed)
		_write_line(result)
	if not core.autosave:
		_finish_memory()
	return 0

func _finish_memory() -> void:
	for id in core.memory.keys():
		if core.memory.has(id):
			var res = core.handle({"op": "finish", "session": id})
			if not bool(res.get("ok", false)):
				printerr(_json_text({"event": "memory_session_close_failed", "session": id,
					"error": res.get("error", {})}))
			else:
				printerr(_json_text({"event": "memory_session_closed", "session": res.get("session", id),
					"replayFile": res.get("replayFile", "")}))

# ---------------------------------------------------------------- play

func _play(req: Dictionary) -> int:
	core.autosave = true
	var new_req = {"op": "new", "agent": "human",
		"mode": req.get("mode", "adventure"), "character": req.get("character", "xiaonuo"),
		"character2": req.get("character2", "axiu")}
	if req.has("seed") and String(req.get("seed", "")) != "":
		new_req["seed"] = String(req.get("seed"))
	var created = core.handle(new_req)
	print(core.render_text(created))
	if not bool(created.get("ok", false)):
		return 1
	var session = String(created["session"])
	print("Commands: w/a/s/d [frames], b [frames], q [frames], wait [frames], look, new [dig|adventure|versus], quit")
	while true:
		print("bombit> ")
		var line = _read_line().strip_edges()
		if line == "":
			continue
		var parts = line.split(" ", false)
		var command = String(parts[0]).to_lower()
		var count = int(parts[1]) if parts.size() > 1 and String(parts[1]).is_valid_int() else -1
		if command == "quit" or command == "exit":
			break
		if command == "new":
			var mode = String(parts[1]) if parts.size() > 1 else "adventure"
			created = core.handle({"op": "new", "agent": "human", "mode": mode,
				"character": "xiaonuo", "character2": "axiu"})
			if bool(created.get("ok", false)):
				session = String(created["session"])
			print(core.render_text(created))
			continue
		if command == "look":
			print(core.render_text(core.handle({"op": "state", "session": session})))
			continue
		var moves = {"w": "up", "a": "left", "s": "down", "d": "right"}
		var act = {"op": "act", "session": session,
			"frames": count if count > 0 else (1 if command == "b" or command == "q" else 12)}
		if moves.has(command):
			act["move"] = moves[command]
		elif command == "b":
			act["bomb"] = true
		elif command == "q":
			act["skill"] = true
		elif command == "wait" or command == ".":
			act["wait"] = true
		else:
			print("Use w/a/s/d, b, q, wait, look, new or quit.")
			continue
		print(core.render_text(core.handle(act)))
	var finished = core.handle({"op": "finish", "session": session})
	print(core.render_text(finished))
	return 0 if bool(finished.get("ok", false)) else 1

# ---------------------------------------------------------------- MCP

func _run_mcp(_args: Array) -> int:
	core = Core.new(OS.get_environment("BOMBIT_SESSION_DIR"))
	core.autosave = false
	while true:
		var line = _read_line()
		if line == "":
			break
		if line.strip_edges() == "":
			continue
		var msg = JSON.parse_string(line)
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		var response = _mcp_handle(msg)
		if response != null:
			_write_line(response)
	_finish_memory()
	return 0

func _mcp_handle(msg: Dictionary) -> Variant:
	var method = String(msg.get("method", ""))
	var id = msg.get("id", null)
	var is_notification = not msg.has("id")
	if method == "initialize":
		var params = msg.get("params", {})
		var protocol = String(params.get("protocolVersion", "2024-11-05"))
		return {"jsonrpc": "2.0", "id": id, "result": {
			"protocolVersion": protocol,
			"capabilities": {"tools": {"listChanged": false}},
			"serverInfo": {"name": "bombit-godot", "version": VERSION},
			"instructions": "BombIt deterministic game server. Create a session with bombit_new, read bombit_state, then call bombit_act/batch/path/goto. Finish with bombit_finish to verify and archive a replay. Thinking never advances time.",
		}}
	if method == "notifications/initialized" or method == "initialized":
		return null
	if method == "ping":
		return {"jsonrpc": "2.0", "id": id, "result": {}}
	if method == "tools/list":
		return {"jsonrpc": "2.0", "id": id, "result": {"tools": _mcp_tools()}}
	if method == "tools/call":
		var params = msg.get("params", {})
		var name = String(params.get("name", ""))
		var args = params.get("arguments", {})
		if typeof(args) != TYPE_DICTIONARY:
			return _rpc_error(id, -32602, "arguments must be an object")
		if name == "bombit_list_replays":
			var list = core.list_replays()
			return _tool_result(id, {"ok": true, "replays": list})
		var req = args.duplicate()
		match name:
			"bombit_new": req["op"] = "new"
			"bombit_state": req["op"] = "state"
			"bombit_act": req["op"] = "act"
			"bombit_batch": req["op"] = "batch"
			"bombit_path": req["op"] = "path"
			"bombit_goto": req["op"] = "goTo"
			"bombit_checkpoint": req["op"] = "checkpoint"
			"bombit_finish": req["op"] = "finish"
			"bombit_replay": req["op"] = "replay"
			"bombit_export": req["op"] = "export"
			"bombit_rules": req = {"op": "rules"}
			_: return _rpc_error(id, -32601, "Unknown tool: " + name)
		var result = core.handle(req)
		return _tool_result(id, result)
	if is_notification:
		return null
	return _rpc_error(id, -32601, "Unknown method: " + method)

func _rpc_error(id, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}

func _tool_result(id, result: Dictionary) -> Dictionary:
	var text = JSON.stringify(result)
	return {"jsonrpc": "2.0", "id": id, "result": {
		"content": [{"type": "text", "text": text}],
		"structuredContent": result,
		"isError": not bool(result.get("ok", false)),
	}}

func _mcp_tools() -> Array:
	var session = {"type": "string", "description": "Session id returned by bombit_new"}
	var move = {"type": "string", "enum": ["none", "up", "down", "left", "right"]}
	var chars = {"type": "string", "enum": ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian", "weilai"]}
	var player_action = {"type": "object", "properties": {
		"move": move, "bomb": {"type": "boolean"}, "skill": {"type": "boolean"},
		"wait": {"type": "boolean"}}, "additionalProperties": false}
	return [
		_tool("bombit_rules", "Read modes, characters, skills, timing, items and protocol details.",
			{"type": "object", "properties": {}, "additionalProperties": false}),
		_tool("bombit_new", "Create a deterministic session. Omit session to let the server name it.",
			{"type": "object", "properties": {
				"agent": {"type": "string"}, "mode": {"type": "string", "enum": ["dig", "adventure", "versus"]},
				"character": chars, "character2": chars, "seed": {"type": "string"},
				"session": {"type": "string"}}, "additionalProperties": false}),
		_tool("bombit_state", "Read the public state. Does not advance time.",
			{"type": "object", "properties": {"session": session, "assist": {"type": "boolean"}},
				"required": ["session"], "additionalProperties": false}),
		_tool("bombit_act", "Advance 1-60 frames with one action. Bomb/skill fire on frame 1.",
			{"type": "object", "properties": {
				"session": session, "frames": {"type": "integer", "minimum": 1, "maximum": 60},
				"move": move, "bomb": {"type": "boolean"}, "skill": {"type": "boolean"},
				"wait": {"type": "boolean"}, "player": {"type": "string", "enum": ["p1", "p2"]},
				"actions": {"type": "object", "additionalProperties": player_action},
				"requestId": {"type": "string"}, "expectRevision": {"type": "integer"}},
				"required": ["session"], "additionalProperties": false}),
		_tool("bombit_batch", "Run 1-1024 action steps; stops early on death, level, round or match end.",
			{"type": "object", "properties": {
				"session": session,
				"steps": {"type": "array", "minItems": 1, "maxItems": 1024,
					"items": {"type": "object", "properties": {
						"frames": {"type": "integer", "minimum": 1, "maximum": 60},
						"move": move, "bomb": {"type": "boolean"}, "skill": {"type": "boolean"},
						"wait": {"type": "boolean"}, "player": {"type": "string", "enum": ["p1", "p2"]},
						"actions": {"type": "object", "additionalProperties": player_action}},
						"additionalProperties": false}},
				"requestId": {"type": "string"}, "expectRevision": {"type": "integer"}},
				"required": ["session", "steps"], "additionalProperties": false}),
		_tool("bombit_path", "Walk 1-256 adjacent cells. Does not predict hazards.",
			{"type": "object", "properties": {
				"session": session,
				"path": {"type": "array", "minItems": 1, "maxItems": 256,
					"items": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2}},
				"maxFrames": {"type": "integer", "minimum": 1, "maximum": 3600},
				"requestId": {"type": "string"}, "expectRevision": {"type": "integer"}},
				"required": ["session", "path"], "additionalProperties": false}),
		_tool("bombit_goto", "Walk the shortest route to a cell. Does not predict hazards.",
			{"type": "object", "properties": {
				"session": session,
				"target": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2},
				"maxFrames": {"type": "integer", "minimum": 1, "maximum": 3600},
				"requestId": {"type": "string"}, "expectRevision": {"type": "integer"}},
				"required": ["session", "target"], "additionalProperties": false}),
		_tool("bombit_checkpoint", "Persist the current session so it can be resumed after a crash.",
			{"type": "object", "properties": {"session": session}, "required": ["session"],
				"additionalProperties": false}),
		_tool("bombit_finish", "Verify the full history and archive one replay; removes the working session.",
			{"type": "object", "properties": {"session": session}, "required": ["session"],
				"additionalProperties": false}),
		_tool("bombit_replay", "Replay and verify a session or a .replay.json file.",
			{"type": "object", "properties": {"session": session, "file": {"type": "string"},
				"assist": {"type": "boolean"}}, "additionalProperties": false}),
		_tool("bombit_export", "Return the replay JSON for a session without archiving.",
			{"type": "object", "properties": {"session": session}, "required": ["session"],
				"additionalProperties": false}),
		_tool("bombit_list_replays", "List archived replays in the local replay directory.",
			{"type": "object", "properties": {}, "additionalProperties": false}),
	]

func _tool(name: String, description: String, schema: Dictionary) -> Dictionary:
	return {"name": name, "description": description, "inputSchema": schema}
