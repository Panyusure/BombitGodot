extends Node

signal changed
signal game_started
signal game_events(events: Array)
signal game_ended
signal lobby_returned

const Snapshot = preload("res://scripts/net/NetSnapshot.gd")
const PROTOCOL := "bombit-lan-1"
const DEFAULT_PORT := 24566
var api: SceneMultiplayer
var peer: ENetMultiplayerPeer
var phase := "home"
var notice := "创建房间，或输入房主的局域网 IP 加入。"
var host := false
var slot := 0
var guest := 0
var players: Array = []
var address := ""
var port := DEFAULT_PORT
var world: World
var epoch := 0
var snapshot = Snapshot.new()
var input_seq := 0
var last_input_seq := -1
var bomb_serial := 0
var skill_serial := 0
var last_bomb := 0
var last_skill := 0
var remote_input := {}
var remote_input_at := 0
var snapshot_frame := -1
var snapshot_at := 0
var event_seq := 0
var received_event := 0
var heartbeat_at := 0
var last_seen := 0
var started_at := 0
var tick_count := 0
var pending_peer := 0
var pending_since := 0

func _ready() -> void:
	api = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, get_path())
	api.peer_disconnected.connect(_peer_left)
	api.peer_connected.connect(func(id):
		if host:
			pending_peer = id
			pending_since = Time.get_ticks_msec())
	api.connected_to_server.connect(_connected)
	api.connection_failed.connect(func(): close("连接失败，请检查 IP、端口及系统防火墙。"))
	api.server_disconnected.connect(func(): close("房间已关闭或与房主断开连接。"))

func _exit_tree() -> void:
	if peer != null:
		peer.close()

func close(message: String = "已离开房间。") -> void:
	if peer != null:
		peer.close()
	peer = null
	api.multiplayer_peer = OfflineMultiplayerPeer.new()
	phase = "home"
	world = null
	players.clear()
	guest = 0
	pending_peer = 0
	address = ""
	host = false
	slot = 0
	_reset_match()
	notice = message
	lobby_returned.emit()
	changed.emit()

func create_room(room_port: int = DEFAULT_PORT) -> Error:
	close("")
	if OS.has_feature("web"):
		notice = "局域网联机请使用桌面版游戏。"
		changed.emit()
		return ERR_UNAVAILABLE
	if room_port < 1024 or room_port > 65535:
		notice = "端口应在 1024～65535 之间。"
		changed.emit()
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(room_port, 1, 3)
	if error != OK:
		peer = null
		notice = "创建失败：端口可能已被占用。"
		changed.emit()
		return error
	api.multiplayer_peer = peer
	host = true
	slot = 0
	port = room_port
	phase = "lobby"
	players = [{"player_id": "p1", "peer": 1, "character": 0, "confirmed": false, "ready": false, "online": true},
		{"player_id": "p2", "peer": 0, "character": 1, "confirmed": false, "ready": false, "online": false}]
	notice = "房间已创建，等待另一台电脑加入。"
	last_seen = Time.get_ticks_msec()
	changed.emit()
	return OK

func join_room(ip: String, room_port: int = DEFAULT_PORT) -> Error:
	close("")
	if OS.has_feature("web"):
		notice = "局域网联机请使用桌面版游戏。"
		changed.emit()
		return ERR_UNAVAILABLE
	if not ip.is_valid_ip_address() or room_port < 1024 or room_port > 65535:
		notice = "请输入有效的房主 IP 和端口（1024～65535）。"
		changed.emit()
		return ERR_INVALID_PARAMETER
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, room_port, 3)
	if error != OK:
		peer = null
		notice = "无法发起连接，请检查网络。"
		changed.emit()
		return error
	api.multiplayer_peer = peer
	address = ip
	port = room_port
	slot = 1
	phase = "connecting"
	notice = "正在连接 %s:%d …" % [ip, port]
	started_at = Time.get_ticks_msec()
	last_seen = started_at
	changed.emit()
	return OK

func _connected() -> void:
	_hello.rpc_id(1, PROTOCOL)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(protocol: String) -> void:
	if not host or phase != "lobby":
		return
	var sender := api.get_remote_sender_id()
	if sender != pending_peer or protocol != PROTOCOL or (guest != 0 and guest != sender):
		_rejected.rpc_id(sender, "游戏版本不一致或房间已满，请使用相同版本重新加入。")
		return
	guest = sender
	pending_peer = 0
	players[1]["peer"] = sender
	players[1]["online"] = true
	last_seen = Time.get_ticks_msec()
	notice = "双方已连接，请各自选择角色并准备。"
	_publish_room()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(message: String) -> void:
	if not host:
		close(message)

func _publish_room() -> void:
	changed.emit()
	if guest > 0:
		_room.rpc_id(guest, players, notice, epoch)

@rpc("authority", "call_remote", "reliable", 0)
func _room(data: Array, message: String, match_epoch: int) -> void:
	if host or phase == "home":
		return
	players = data
	epoch = match_epoch
	notice = message
	if phase == "connecting":
		phase = "lobby"
	last_seen = Time.get_ticks_msec()
	changed.emit()

func choose(index: int) -> void:
	if host:
		_choice(0, index)
	elif phase == "lobby":
		_request_choice.rpc_id(1, index)

func _choice(owner: int, index: int) -> void:
	if phase != "lobby" or index < 0 or index >= Cfg.CHAR_IDS.size() or index == players[1 - owner]["character"]:
		return
	players[owner]["character"] = index
	players[owner]["confirmed"] = false
	players[owner]["ready"] = false
	_publish_room()

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_choice(index: int) -> void:
	if host and guest > 0 and api.get_remote_sender_id() == guest:
		_choice(1, index)

func ready_player(value: bool) -> void:
	if host:
		_ready_player(0, value)
	elif phase == "lobby":
		_request_ready.rpc_id(1, value)

func _ready_player(owner: int, value: bool) -> void:
	if phase != "lobby" or not players[owner]["online"]:
		return
	players[owner]["ready"] = value
	players[owner]["confirmed"] = value
	_publish_room()

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_ready(value: bool) -> void:
	if host and guest > 0 and api.get_remote_sender_id() == guest:
		_ready_player(1, value)

func can_start() -> bool:
	return host and phase == "lobby" and guest > 0 and players.size() == 2 \
		and api.get_peers().has(guest) and players[0]["peer"] == 1 and players[1]["peer"] == guest \
		and players.all(func(p): return p["online"] and p["confirmed"] and p["ready"] and int(p["character"]) >= 0 and int(p["character"]) < Cfg.CHAR_IDS.size()) \
		and players[0]["character"] != players[1]["character"]

func start_game() -> void:
	if not can_start():
		return
	phase = "loading" # Lock before signals/RPCs: two confirms cannot start twice.
	epoch += 1
	_reset_match()
	world = GameEngine.create_world({"mode": "versus", "input_mode": "lan",
		"seed": str(Time.get_ticks_usec()), "chars": players.map(func(p): return Cfg.CHAR_IDS[p["character"]])})
	started_at = Time.get_ticks_msec()
	_begin.rpc_id(guest, epoch, snapshot.pack(world))
	game_started.emit()
	changed.emit()

func _reset_match() -> void:
	snapshot = Snapshot.new()
	input_seq = 0
	last_input_seq = -1
	bomb_serial = 0
	skill_serial = 0
	last_bomb = 0
	last_skill = 0
	remote_input = {}
	snapshot_frame = -1
	event_seq = 0
	received_event = 0
	tick_count = 0

@rpc("authority", "call_remote", "reliable", 0)
func _begin(match_epoch: int, data: Dictionary) -> void:
	if host or phase != "lobby" or match_epoch <= epoch:
		return
	epoch = match_epoch
	phase = "loading"
	_reset_match()
	world = World.new()
	snapshot.apply(world, data)
	game_started.emit()
	_loaded.rpc_id(1, epoch)

@rpc("any_peer", "call_remote", "reliable", 0)
func _loaded(match_epoch: int) -> void:
	if host and phase == "loading" and match_epoch == epoch and api.get_remote_sender_id() == guest:
		phase = "playing"
		_play.rpc_id(guest, epoch)
		changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _play(match_epoch: int) -> void:
	if not host and phase == "loading" and match_epoch == epoch:
		phase = "playing"
		changed.emit()

func tick(action: Dictionary, dt: float) -> void:
	if phase != "playing" or world == null:
		return
	if not host:
		input_seq += 1
		bomb_serial += int(action.get("bomb", false))
		skill_serial += int(action.get("skill", false))
		_input_packet.rpc_id(1, epoch, input_seq, int(action.get("hx", 0)), int(action.get("hy", 0)), bomb_serial, skill_serial, String(action.get("axis_pref", "x")))
		return
	var other := remote_input.duplicate()
	if Time.get_ticks_msec() - remote_input_at > 300:
		other = {}
	remote_input["bomb"] = false
	remote_input["skill"] = false
	world.player_by_id("p2").axis_pref = String(other.get("axis_pref", "x"))
	GameEngine.step(world, {"p1": action, "p2": other}, dt)
	if not world.events.is_empty():
		event_seq += 1
		_events.rpc_id(guest, epoch, event_seq, world.events)
		game_events.emit(world.events.duplicate(true))
	tick_count += 1
	if world.match.over:
		phase = "result"
		_finish.rpc_id(guest, epoch, snapshot.pack(world))
		game_ended.emit()
	elif tick_count % 3 == 0:
		# Reliable compressed snapshots avoid ENet's unreliable MTU fragmentation;
		# a separate channel keeps room transitions and effects independent.
		_state.rpc_id(guest, epoch, var_to_bytes(snapshot.pack(world)).compress(FileAccess.COMPRESSION_DEFLATE))

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _input_packet(match_epoch: int, sequence: int, hx: int, hy: int, bombs: int, skills: int, axis: String = "x") -> void:
	if not host or guest <= 0 or api.get_remote_sender_id() != guest or phase != "playing" or match_epoch != epoch:
		return
	if sequence <= last_input_seq or abs(hx) > 1 or abs(hy) > 1 or bombs < last_bomb or skills < last_skill \
		or bombs > last_bomb + 16 or skills > last_skill + 16 or axis not in ["x", "y"]:
		return
	last_input_seq = sequence
	remote_input["hx"] = hx
	remote_input["hy"] = hy
	remote_input["axis_pref"] = axis
	remote_input["bomb"] = remote_input.get("bomb", false) or bombs > last_bomb
	remote_input["skill"] = remote_input.get("skill", false) or skills > last_skill
	last_bomb = bombs
	last_skill = skills
	remote_input_at = Time.get_ticks_msec()

@rpc("authority", "call_remote", "reliable", 1)
func _state(match_epoch: int, packet: PackedByteArray) -> void:
	if host or phase != "playing" or match_epoch != epoch or packet.size() > 65536:
		return
	var decoded = bytes_to_var(packet.decompress_dynamic(262144, FileAccess.COMPRESSION_DEFLATE))
	if not decoded is Dictionary:
		return
	var data: Dictionary = decoded
	if int(data["frame"]) <= snapshot_frame:
		return
	snapshot.apply(world, data)
	snapshot_frame = world.frame
	snapshot_at = Time.get_ticks_msec()

@rpc("authority", "call_remote", "reliable", 2)
func _events(match_epoch: int, sequence: int, events: Array) -> void:
	if not host and phase in ["playing", "result"] and match_epoch == epoch and sequence > received_event:
		received_event = sequence
		game_events.emit(events)

@rpc("authority", "call_remote", "reliable", 0)
func _finish(match_epoch: int, data: Dictionary) -> void:
	if not host and phase == "playing" and match_epoch == epoch:
		snapshot.apply(world, data)
		phase = "result"
		game_ended.emit()

func return_lobby() -> void:
	if phase != "result":
		return
	if not host:
		_request_lobby.rpc_id(1, epoch)
		return
	phase = "lobby"
	world = null
	for player in players:
		player["ready"] = false
		player["confirmed"] = false
	_back.rpc_id(guest, epoch)
	lobby_returned.emit()
	notice = "对局结束，请重新选择并准备。"
	_publish_room()

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_lobby(match_epoch: int) -> void:
	if host and api.get_remote_sender_id() == guest and match_epoch == epoch:
		return_lobby()

@rpc("authority", "call_remote", "reliable", 0)
func _back(match_epoch: int) -> void:
	if not host and phase == "result" and match_epoch == epoch:
		phase = "lobby"
		world = null
		lobby_returned.emit()
		changed.emit()

func _peer_left(id: int) -> void:
	if host and id == pending_peer:
		pending_peer = 0
	if not host or id != guest:
		return
	guest = 0
	world = null
	phase = "lobby"
	players[1]["online"] = false
	players[1]["peer"] = 0
	for player in players:
		player["ready"] = false
		player["confirmed"] = false
	notice = "对方已退出或断开连接，等待重新加入。"
	lobby_returned.emit()
	changed.emit()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if host and pending_peer > 0 and now - pending_since > 8000:
		peer.disconnect_peer(pending_peer)
		pending_peer = 0
	if phase == "connecting" and now - started_at > 8000:
		close("连接超时，请确认双方在同一局域网、IP/端口正确，并允许游戏通过防火墙。")
	elif phase == "loading" and now - started_at > 8000 and host:
		_disconnect_guest()
	if phase in ["lobby", "loading", "playing", "result"] and (guest > 0 or not host):
		if now - last_seen > 6000:
			if host:
				_disconnect_guest()
			else:
				close("连接中断，已返回联机大厅。")
		elif not host and now - heartbeat_at > 500:
			heartbeat_at = now
			_heartbeat.rpc_id(1)

func _disconnect_guest() -> void:
	var id := guest
	if id > 0:
		peer.disconnect_peer(id)
		_peer_left(id)

@rpc("any_peer", "call_remote", "reliable", 2)
func _heartbeat() -> void:
	if host and guest > 0 and api.get_remote_sender_id() == guest:
		last_seen = Time.get_ticks_msec()
		_heartbeat_ack.rpc_id(guest)

@rpc("authority", "call_remote", "reliable", 2)
func _heartbeat_ack() -> void:
	if not host:
		last_seen = Time.get_ticks_msec()

func render_alpha() -> float:
	return clampf((Time.get_ticks_msec() - snapshot_at) / 50.0, 0, 1)
