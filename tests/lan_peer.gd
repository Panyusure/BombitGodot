extends SceneTree

## Two independent processes use real ENet and the real Main/lobby/results path.
var main: Node
var session: Node
var role := "host"
var room_port := 30001
var prefix := "res://.godot/lan-test"
var checks := 0
var failures := 0
var stage := 0
var stage_time := 0.0
var started := 0
var round_seen := 0
var starts := 0
var endings := 0
var events := {}
var placed_first := false
var placed_second := false
var ability := false
var moved := false
var picked := false
var skill_seen := false
var bomb_seen := false
var final_hash := ""
var original_guest := 0
var done := false
var bomb_step := 0
var settle_time := 0.0
var first_cell := 12
var lobby_input_checked := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + role + " " + message)

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): room_port = int(argument.trim_prefix("--port="))
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
	call_deferred("run")

func run() -> void:
	InputMap.load_from_project_settings()
	InputSettings.config_path = prefix + "-" + role + "-settings.cfg"
	DirAccess.remove_absolute(InputSettings.config_path)
	InputSettings.ensure_loaded()
	InputSettings.set_device_mode("p1", InputSettings.MODE_KEYBOARD)
	InputSettings.set_device_mode("p2", InputSettings.MODE_KEYBOARD)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main._open_lan()
	session = main.lan
	session.game_started.connect(func(): starts += 1)
	session.game_ended.connect(func(): endings += 1)
	session.game_events.connect(func(batch):
		for event in batch: events[event["kind"]] = events.get(event["kind"], 0) + 1)
	started = Time.get_ticks_msec()
	if role == "host":
		check(session.create_room(room_port) == OK, "creates ENet room")
	else:
		await create_timer(0.3).timeout
		check(session.join_room("127.0.0.1", room_port) == OK, "starts client connection")
	physics_frame.connect(step)

func fixture() -> void:
	var w: World = session.world
	for r in range(1, Cfg.ROWS - 1):
		for c in range(1, Cfg.COLS - 1):
			w.set_tile(c, r, Cfg.T_EMPTY)
	w.theme = "forest"
	w.landmark = {}
	w.set_tile(12, 10, Cfg.T_BRICK)
	w.items = [{"c": 13, "r": 11, "type": "bomb", "born": w.time}, {"c": 12, "r": 11, "type": "speed", "born": w.time}]

func step() -> void:
	if done:
		return
	if Time.get_ticks_msec() - started > 35000:
		check(false, "scenario timeout stage=%d phase=%s notice=%s" % [stage, session.phase, session.notice])
		finish()
		return
	stage_time += 1.0 / 60
	if stage in [0, 3] and session.phase == "lobby" and session.players.size() == 2 and session.players[1]["online"]:
		if not lobby_input_checked:
			main.lan_lobby.previous = {"accept": false}
			var press := InputEventKey.new()
			press.keycode = KEY_ENTER
			press.pressed = true
			Input.parse_input_event(press)
			Input.flush_buffered_events()
			session.changed.emit()
			check(not main.lan_lobby.previous.get("accept", false), "remote room refresh does not swallow this player's confirmation edge")
			var release := InputEventKey.new()
			release.keycode = KEY_ENTER
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			main.lan_lobby.previous = InputSettings.poll_nav()
			lobby_input_checked = true
		if stage == 0 and not session.players[session.slot]["ready"]:
			main.lan_lobby._select(1 - session.slot, 5) # Remote panel cannot send a request.
			main.lan_lobby._select(session.slot, 2 if role == "host" else 4)
			main.lan_lobby.panels[session.slot].ready_requested.emit(session.slot)
		elif stage == 3:
			session.ready_player(true)
		if role == "host" and session.can_start():
			if stage == 0:
				check(session.players[0]["character"] == 2 and session.players[1]["character"] == 4, "independent characters synchronize")
				original_guest = session.guest
				check(not main.multiplayer.has_multiplayer_peer() or main.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "network API is isolated from offline tree")
			session.start_game()
			session.start_game()
	if session.phase == "playing" and stage in [0, 3]:
		check(starts == (1 if stage == 0 else 2), "one start per match despite repeated request")
		if role == "client":
			# Valid connection, invalid requests: a stale epoch and impossible axis
			# must not poison sequencing or allow lobby changes during a match.
			session._input_packet.rpc_id(1, session.epoch - 1, 99999, 1, 0, 0, 0)
			session._input_packet.rpc_id(1, session.epoch, 99999, 999, 0, 0, 0)
			session._request_choice.rpc_id(1, 5)
			session.start_game()
		stage = 1 if stage == 0 else 4
		stage_time = 0
	if stage == 1 and session.phase == "playing":
		var w: World = session.world
		if role == "host" and round_seen != w.match.round:
			round_seen = w.match.round
			fixture()
		if role == "client" and round_seen != w.match.round:
			round_seen = w.match.round
			placed_first = false
			placed_second = false
			ability = false
			bomb_step = 0
			settle_time = 0
		var action := {}
		var player = w.player_by_id("p2")
		if player.alive and role == "client":
			settle_time += 1.0 / 60
			var owned: Array = w.bombs.filter(func(b): return b.owner_id == "p2")
			if bomb_step == 0:
				if player.x > Grid.center_x(12) + 1:
					action["hx"] = -1
				else:
					bomb_step = 1
					settle_time = 0
			elif bomb_step == 1 and settle_time > 0.2:
				if owned.size() > 0:
					first_cell = owned[0].cx
					placed_first = true
					bomb_step = 2
				else:
					action["bomb"] = true
					settle_time = 0
			elif bomb_step == 2:
				if player.x > Grid.center_x(first_cell - 1) + 1:
					action["hx"] = -1
				else:
					bomb_step = 3
					settle_time = 0
			elif bomb_step == 3 and settle_time > 0.2:
				if owned.size() > 1:
					placed_second = true
					bomb_step = 4
				else:
					action["bomb"] = true
					settle_time = 0
			if not ability and placed_first:
				action["skill"] = true
				ability = true
		if role == "host" and w.match.round == 1 and w.time < 0.2:
			action["hy"] = 1
		session.tick(action, 1.0 / 60)
		moved = moved or player.x < Grid.center_x(13) - 20
		picked = picked or (player.max_bombs >= 2 and player.speed_bonus > 0)
		skill_seen = skill_seen or player.insight_time > 0
		bomb_seen = bomb_seen or w.bombs.size() >= 2
	elif stage == 1 and session.phase == "result":
		stage = 8
		stage_time = 0
	elif stage == 8 and stage_time > 0.2:
		check(main.state == main.State.RESULT and endings == 1, "real Main shows exactly one synchronized result")
		check(session.world.match.winner == "p1" and session.world.match.scores["p1"] == 2, "authority awards two rounds and ends the match")
		check(moved and picked and skill_seen and bomb_seen, "remote movement, two bombs, pickups, attributes and skill are visible")
		check(events.get("explode", 0) >= 4 and events.get("pickup", 0) >= 2 and events.get("death", 0) >= 2, "explosions, chain and deaths arrive without local damage simulation: " + str(events))
		var data: Dictionary = session.snapshot.pack(session.world)
		for player in data["players"]:
			player.erase("px")
			player.erase("py")
		final_hash = str(hash(data))
		stage = 2
		stage_time = 0
	elif stage == 2 and stage_time > 0.4:
		if role == "client": session.return_lobby()
		if session.phase == "lobby":
			check(not session.players[0]["ready"] and not session.players[1]["ready"], "return resets both ready states")
			check(main.world == null and main.state == main.State.LAN, "return clears battle views and opens network lobby")
			stage = 3
			stage_time = 0
	elif stage == 4 and session.phase == "playing":
		session.tick({}, 1.0 / 60)
		if role == "client" and stage_time > 0.4:
			session.close("test client disconnect")
			check(main.world == null and main.state == main.State.LAN, "client disconnect cleans active match")
			stage = 5
			stage_time = 0
	elif stage == 4 and role == "host" and session.phase == "lobby" and session.guest == 0:
		check(main.world == null and not session.players[0]["ready"], "host detects departure during play and cleans match")
		stage = 5
		stage_time = 0
	elif stage == 5:
		if role == "client" and stage_time > 0.4 and session.phase == "home":
			session.join_room("127.0.0.1", room_port)
			stage = 6
		elif role == "host" and session.guest > 0:
			check(session.guest != original_guest, "reconnect maps new peer identity instead of local device index")
			session.close()
			stage = 7
			stage_time = 0
	elif stage == 6 and session.phase == "home":
		check(session.notice.contains("房间") or session.notice.contains("连接"), "host departure is reported clearly")
		stage = 7
		stage_time = 0
	elif stage == 7 and stage_time > 0.3:
		offline_checks()
		finish()

func offline_checks() -> void:
	main._to_menu()
	check(session.peer == null and session.players.is_empty() and main.menu.visible, "exit releases ENet and returns to original menu")
	check(main.menu.MODES.size() == 4, "four independent menu modes remain available")
	for mode in ["adventure", "dig", "versus"]:
		if mode == "versus":
			main.menu.mode_index = 2
			main.menu._open_character()
			main.menu.versus_lobby.model.ready_player(0)
			main.menu.versus_lobby.model.ready_player(1)
			main.menu.versus_lobby.request_start()
		else:
			main._on_menu_start(mode, "xiaonuo", "axiu")
			main._on_overlay_action("start")
		check(main.world != null and main.world.mode == mode and main.state == main.State.PLAY, "offline mode still starts: " + mode)
		var player = main.world.players[0]
		var before: float = player.x
		var key := InputEventKey.new()
		key.keycode = KEY_RIGHT
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		GameEngine.step(main.world, main._read_actions(), 1.0 / 60)
		check(player.x > before, "offline keyboard still moves player: " + mode)
		var release := key.duplicate()
		release.pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		main._to_menu()

func finish() -> void:
	done = true
	var file := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "digest": final_hash, "events": events}))
	file.close()
	main._to_menu()
	main.queue_free()
	DirAccess.remove_absolute(InputSettings.config_path)
	quit(0 if failures == 0 else 1)
