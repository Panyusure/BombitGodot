extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	await unit_checks()
	var prefix := "res://.godot/lan-test-%d" % OS.get_process_id()
	var room_port := 30000 + OS.get_process_id() % 10000
	var processes := []
	for role in ["host", "client"]:
		processes.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", ProjectSettings.globalize_path(prefix + "-" + role + ".log"), "--script", "res://tests/lan_peer.gd", "--",
			"--role=" + role, "--port=" + str(room_port), "--prefix=" + prefix]))
	var start := Time.get_ticks_msec()
	while processes.any(func(pid): return OS.is_process_running(pid)) and Time.get_ticks_msec() - start < 42000:
		await create_timer(0.2).timeout
	for pid in processes:
		if OS.is_process_running(pid):
			OS.kill(pid)
			check(false, "network test process timed out")
	var reports := []
	for role in ["host", "client"]:
		var path: String = prefix + "-" + role + ".json"
		if FileAccess.file_exists(path):
			var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			reports.append(report)
			print("LAN_PEER=%s %s" % [role, JSON.stringify(report)])
			checks += int(report["checks"])
			failures += int(report["failures"])
			DirAccess.remove_absolute(path)
		else:
			check(false, role + " did not produce a report")
		var log_text := FileAccess.get_file_as_string(prefix + "-" + role + ".log")
		check(not "SCRIPT ERROR:" in log_text and not "CHECK_FAIL=" in log_text, role + " runtime has no script errors or failed assertions")
		if "SCRIPT ERROR:" in log_text or "CHECK_FAIL=" in log_text:
			printerr(log_text)
	if reports.size() == 2:
		check(not reports[0]["digest"].is_empty() and reports[0]["digest"] == reports[1]["digest"], "authoritative final map, players, bombs, items, attributes and scores match on both processes")
	print("LAN_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func unit_checks() -> void:
	var codec = preload("res://scripts/net/NetSnapshot.gd").new()
	var w := GameEngine.create_world({"mode": "versus", "seed": "lan-codec"})
	var bomb := Bomb.new(1, 1)
	bomb.owner_id = "p1"
	w.bombs.append(bomb)
	var encoded: Dictionary = codec.pack(w)
	var received: Dictionary = bytes_to_var(var_to_bytes(encoded))
	var copy := World.new()
	var reader = preload("res://scripts/net/NetSnapshot.gd").new()
	reader.apply(copy, received)
	check(copy.map == w.map and copy.players.size() == 2, "snapshot round trip preserves map and independent players")
	check(copy.players[0] != copy.players[1] and copy.players[0] != w.players[0], "network actors are independent objects")
	var stable_bomb = copy.bombs[0]
	reader.apply(copy, codec.pack(w))
	check(copy.bombs[0] == stable_bomb, "repeated snapshots reuse stable bomb IDs instead of spawning duplicates")
	w.bombs.clear()
	w.bombs.append(Bomb.new(2, 1))
	var second: Dictionary = codec.pack(w)
	check(second["bombs"][0]["id"] != encoded["bombs"][0]["id"], "new bombs never reuse old IDs in the same match")
	var connection = preload("res://scripts/net/LanSession.gd").new()
	connection.name = "UnitLanSession"
	root.add_child(connection)
	check(connection.join_room("bad-host", 24566) == ERR_INVALID_PARAMETER and connection.peer == null, "invalid address cannot create a connection")
	check(connection.create_room(1) == ERR_INVALID_PARAMETER and connection.peer == null, "invalid port cannot bind a server")
	connection.host = true
	connection.phase = "playing"
	connection.guest = 999
	connection.epoch = 9
	connection._input_packet(9, 1, 1, 0, 0, 0)
	check(connection.remote_input.is_empty() and connection.last_input_seq == -1, "requests without an authenticated remote peer are rejected")
	connection.start_game()
	check(connection.world == null and connection.phase == "playing", "invalid phase cannot start another match")
	connection.close()
	check(connection.guest == 0 and connection.players.is_empty() and connection.world == null and connection.remote_input.is_empty(), "close clears peer identity, room, world and pending input")
	var protocol_client = preload("res://scripts/net/LanSession.gd").new()
	protocol_client.name = "ProtocolClient"
	root.add_child(protocol_client)
	var validation_port := 41000 + OS.get_process_id() % 10000
	check(connection.create_room(validation_port) == OK, "protocol validation room opens")
	connection.ready_player(true)
	check(not connection.can_start(), "host alone cannot start even after ready")
	protocol_client.api.connected_to_server.disconnect(protocol_client._connected)
	protocol_client.api.connected_to_server.connect(func(): protocol_client._hello.rpc_id(1, "incompatible-version"))
	protocol_client.join_room("127.0.0.1", validation_port)
	var deadline := Time.get_ticks_msec() + 2500
	while protocol_client.phase != "home" and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(protocol_client.phase == "home" and protocol_client.notice.contains("版本"), "incompatible client is rejected with a clear version message")
	check(connection.guest == 0 and not connection.players[1]["online"], "rejected connection never occupies a network player slot")
	protocol_client.queue_free()
	connection.close()
	connection.queue_free()
	await process_frame
