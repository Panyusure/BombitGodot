extends SceneTree

const Prediction = preload("res://scripts/net/NetPrediction.gd")
const Inputs = preload("res://scripts/net/NetInputs.gd")
const Codec = preload("res://scripts/net/NetSnapshot.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func _init() -> void:
	call_deferred("run")

func command(sequence: int, hx: int = 1, hy: int = 0, bomb: int = 0, skill: int = 0) -> PackedInt32Array:
	return PackedInt32Array([sequence, hx, hy, bomb, skill, 0])

func make_world() -> World:
	var w := GameEngine.create_world({"mode": "versus", "seed": "prediction"})
	for row in range(1, Cfg.ROWS - 1):
		for col in range(1, Cfg.COLS - 1):
			w.set_tile(col, row, Cfg.T_EMPTY)
	w.items.clear()
	w.landmark = {}
	var player = w.player_by_id("p2")
	player.x = Grid.center_x(3)
	player.y = Grid.center_y(3)
	player.px = player.x
	player.py = player.y
	return w

func input_checks() -> void:
	var buffer = Inputs.new()
	check(buffer.receive(command(1)), "accept valid first input")
	check(buffer.receive(command(3)), "future input is buffered rather than applied early")
	check(buffer.consume()["hx"] == 1 and buffer.acknowledged == 1, "server consumes one physics tick per command")
	check(buffer.consume().is_empty() and buffer.acknowledged == 1, "missing input does not repeat movement or advance the acknowledgment")
	var resend := command(2, 0, 1, 1)
	resend.append_array(command(3, -1, 0, 1))
	# The first version of sequence 3 remains immutable on duplicate reception.
	buffer = Inputs.new()
	buffer.receive(command(1))
	buffer.consume()
	buffer.receive(resend)
	check(buffer.consume()["bomb"], "resent command delivers a dropped bomb edge")
	check(not buffer.consume()["bomb"], "repeated bomb counter does not trigger twice")
	buffer.receive(resend)
	check(buffer.consume().is_empty() and buffer.acknowledged == 3, "old duplicated batches cannot replay actions")
	check(not buffer.receive(PackedInt32Array([4, 99, 0, 1, 0, 0])), "invalid direction rejected")
	check(not buffer.receive(command(10000)), "far future sequence rejected")
	check(not buffer.receive(PackedInt32Array([4, 0])), "malformed batch rejected atomically")
	check(not buffer.receive(PackedInt32Array([4, 0, 0, 1, 0, 2])), "invalid axis rejected")
	var full := PackedInt32Array()
	for i in Inputs.REDUNDANCY:
		full.append_array(command(i + 4, 0, 0, 1))
	check(full.to_byte_array().size() <= 1152, "redundant command payload stays below MTU")
	buffer.receive(full)
	buffer.consume()
	check(buffer.acknowledged == 4 and buffer.commands.size() == Inputs.REDUNDANCY - 1, "one burst cannot speed up server movement")

func prediction_checks() -> void:
	var w := make_world()
	var origin := Vector2(w.players[1].x, w.players[1].y)
	var prediction = Prediction.new()
	prediction.initialize(w, 1)
	prediction.enqueue(w, command(1))
	check(prediction.actor.x > origin.x and w.players[1].x == origin.x, "first local tick moves the preview without moving authority")
	check(prediction.actor != w.players[1], "predicted and authoritative actor are separate")
	for i in range(2, 31):
		prediction.enqueue(w, command(i))
	for i in 20:
		GameEngine.step(w, {"p2": {"hx": 1}}, 1.0 / 60)
	prediction.reconcile(w, 20, 1)
	check(prediction.pending.size() == 10 and prediction.pending[0][0] == 21, "acknowledged history is removed before replay")
	check(absf(prediction.actor.x - (origin.x + Cfg.SPEED_BASE * Cfg.TILE * 0.5)) < 0.001, "unacknowledged movement is replayed from server position")
	var old_x: float = prediction.actor.x
	prediction.reconcile(w, 19, 1)
	check(prediction.actor.x == old_x and prediction.pending.size() == 10, "stale acknowledgment cannot rewind prediction")
	w.players[1].x -= 6
	prediction.reconcile(w, 20, 1)
	var correction: float = prediction.visual_offset.length()
	prediction.draw_offset(w, 0.05)
	check(correction > 0 and prediction.visual_offset.length() < correction, "small authoritative correction is smoothed visually")
	w.players[1].x = Grid.center_x(9)
	prediction.reconcile(w, 0, 2)
	check(prediction.pending.is_empty() and prediction.actor.x == w.players[1].x and prediction.visual_offset == Vector2.ZERO, "new movement generation discards old inputs and snaps teleports/round changes")
	w.players[1].alive = false
	prediction.reconcile(w, 0, 3)
	old_x = prediction.actor.x
	prediction.enqueue(w, command(1))
	check(prediction.actor.x == old_x and not prediction.actor.moving, "dead player cannot continue predicted movement")
	prediction.reset()
	check(prediction.actor == null and prediction.pending.is_empty() and prediction.scratch.bombs.is_empty() and prediction.scratch.map.is_empty(), "exit clears the render actor, pending commands and retained collision world")
	w = make_world()
	w.set_tile(4, 3, Cfg.T_HARD)
	prediction.initialize(w, 1)
	for i in 30:
		prediction.enqueue(w, command(i + 1))
	check(Grid.can_stand_map(w.map, prediction.actor.x, prediction.actor.y, Cfg.BOX), "predicted movement respects walls")
	w = make_world()
	w.bombs.append(Bomb.new(4, 3))
	prediction.initialize(w, 1)
	for i in 30:
		prediction.enqueue(w, command(i + 1, 1, 0, 1, 1))
	check(Grid.can_stand(w, prediction.actor.x, prediction.actor.y, Cfg.BOX, "p2"), "predicted movement respects authoritative bombs")
	check(w.bombs.size() == 1 and w.events.is_empty() and w.players[1].skill_cd == 0, "prediction never places bombs, casts skills or emits authoritative effects")
	for i in range(31, 100):
		prediction.enqueue(w, command(i, -1))
	var bounded_x: float = prediction.actor.x
	prediction.enqueue(w, command(100, -1))
	check(prediction.actor.x == bounded_x, "long snapshot silence caps speculative travel")
	for i in range(101, 500):
		prediction.enqueue(w, command(i))
	check(prediction.pending.size() == Inputs.MAX_PENDING, "missing acknowledgments cannot grow client history indefinitely")
	w = make_world()
	prediction.initialize(w, 1)
	for i in 8:
		prediction.enqueue(w, command(i + 1))
	w.bombs.append(Bomb.new(4, 3))
	prediction.reconcile(w, 0, 1)
	check(Grid.can_stand(w, prediction.actor.x, prediction.actor.y, Cfg.BOX, "p2") and prediction.visual_offset == Vector2.ZERO, "new authoritative bomb corrects prediction without smoothing through its collision")
	w.bombs.clear()
	w.set_tile(4, 3, Cfg.T_HARD)
	prediction.reconcile(w, 0, 1)
	check(Grid.can_stand_map(w.map, prediction.actor.x, prediction.actor.y, Cfg.BOX), "geometry changes are used when replaying pending inputs")
	w = make_world()
	var owned_bomb := Bomb.new(3, 3)
	owned_bomb.owner_id = "p2"
	owned_bomb.pass_for = ["p2"]
	w.bombs.append(owned_bomb)
	prediction.initialize(w, 1)
	for i in 15:
		prediction.enqueue(w, command(i + 1))
	for i in range(15, 30):
		prediction.enqueue(w, command(i + 1, -1))
	prediction.visual_offset = Vector2(-20, 0)
	var collision_correction_cleared: bool = prediction.draw_offset(w, 0) == Vector2.ZERO
	check(prediction.actor.x >= Grid.center_x(3) + Cfg.PLAYER_BOMB_RADIUS + Cfg.BOMB_RADIUS \
		and owned_bomb.pass_for.has("p2") and collision_correction_cleared, "leaving an owned bomb revokes only the predicted pass permission and prevents moving or smoothing back through it")
	w = make_world()
	w.players[1].insight_time = 0.1
	w.players[1].soul_slow_time = 0.2
	w.players[1].soul_slow_rate = 0.55
	prediction.initialize(w, 1)
	for i in 24:
		prediction.enqueue(w, command(i + 1))
		GameEngine.step(w, {"p2": {"hx": 1}}, 1.0 / 60)
	check(absf(w.players[1].x - prediction.actor.x) < 0.001, "predicted speed follows buff and slow expiration")
	w = make_world()
	w.landmark = {"theme": "park", "path": LevelGen.loop_path(2, 2, 4, 4)}
	w.players[1].x = Grid.center_x(3)
	w.players[1].y = Grid.center_y(2)
	w.players[1].carousel_travel = w.landmark["path"].size() - 0.01
	prediction.initialize(w, 1)
	prediction.enqueue(w, command(1, 0))
	check(w.players[1].shield == 0 and prediction.actor.shield == 0 and w.events.is_empty(), "carousel prediction cannot grant shields or duplicate rewards")
	w.landmark["theme"] = "factory"
	var codec = Codec.new()
	var reference := World.new()
	codec.apply(reference, codec.pack(w))
	Motion.step(reference, reference.players[1], 0, 0, 1.0 / 60)
	prediction.initialize(w, 1)
	prediction.enqueue(w, command(1, 0))
	check(Vector2(prediction.actor.x, prediction.actor.y).distance_to(Vector2(reference.players[1].x, reference.players[1].y)) < 0.001, "conveyor movement uses the same geometry on client and authority")

func wait_until(condition: Callable, timeout: float = 3) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func delayed_network_checks() -> void:
	var server = preload("res://tests/latency_session.gd").new()
	var client = preload("res://tests/latency_session.gd").new()
	server.name = "DelayedHost"
	client.name = "DelayedClient"
	root.add_child(server)
	root.add_child(client)
	var room_port := 42000 + OS.get_process_id() % 10000
	check(server.create_room(room_port) == OK and client.join_room("127.0.0.1", room_port) == OK, "delayed ENet peers can connect")
	check(await wait_until(func(): return client.phase == "lobby"), "delayed peers finish handshake")
	server.game_started.connect(func():
		var fixture := make_world()
		server.world.map = fixture.map
		server.world.landmark = {}
		server.world.items.clear()
		server.world.players[1].x = Grid.center_x(3)
		server.world.players[1].y = Grid.center_y(3))
	server.ready_player(true)
	client.ready_player(true)
	check(await wait_until(func(): return server.can_start()), "delayed peers prepare independently")
	server.start_game()
	if not await wait_until(func(): return client.phase == "playing"):
		check(false, "delayed match starts")
		client.close()
		server.close()
		server.queue_free()
		client.queue_free()
		return
	var max_pending := 0
	var monotonic := true
	var previous_snapshot := -1
	var origin: float = server.world.players[1].x
	for frame in 240:
		await physics_frame
		var action := {}
		if frame < 36: action = {"hx": 1}
		elif frame < 56: action = {"hy": 1, "axis_pref": "y"}
		elif frame < 76: action = {"hx": -1}
		elif frame < 90: action = {"hy": -1, "axis_pref": "y"}
		elif frame == 110: action = {"skill": true}
		client.tick(action, 1.0 / 60)
		server.tick({}, 1.0 / 60)
		if frame == 0:
			check(client.prediction.actor.x > origin and server.world.players[1].x == origin, "150ms uplink: local movement responds before the host receives input")
		max_pending = maxi(max_pending, client.prediction.pending.size())
		monotonic = monotonic and client.snapshot_frame >= previous_snapshot
		previous_snapshot = client.snapshot_frame
	check(client.dropped_packets > 0 and max_pending >= 12, "test exercised input loss and at least 300ms round-trip history")
	check(monotonic, "reordered snapshots never rewind the authoritative frame")
	var authority_position := Vector2(server.world.players[1].x, server.world.players[1].y)
	print("PREDICTION_METRICS= pending_max=%d dropped=%d position_error=%.5f" % [max_pending, client.dropped_packets,
		authority_position.distance_to(Vector2(client.prediction.actor.x, client.prediction.actor.y))])
	check(authority_position.distance_to(Vector2(client.prediction.actor.x, client.prediction.actor.y)) < 0.01, "prediction converges to host after stopping under latency/loss/jitter")
	check(authority_position.distance_to(Vector2(client.world.players[1].x, client.world.players[1].y)) < 0.01, "authoritative worlds also converge under delayed snapshots")
	check(server.input_generation > 1 and client.prediction.generation == server.input_generation, "server-authorized dash discards pre-teleport input history")
	check(server.world.bombs.is_empty() and client.world.bombs.is_empty(), "delayed prediction does not invent bombs or damage")
	check(client.prediction.pending.size() <= Inputs.MAX_PENDING and server.input_buffer.commands.size() <= Inputs.MAX_PENDING, "loss and jitter keep both history buffers bounded")
	client.close()
	server.close()
	check(client.prediction.actor == null and client.prediction.pending.is_empty(), "disconnect clears prediction after a delayed match")
	client.queue_free()
	server.queue_free()
	await process_frame

func run() -> void:
	input_checks()
	prediction_checks()
	await delayed_network_checks()
	print("PREDICTION_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
