extends Control

const StateModel = preload("res://scripts/VersusLobbyState.gd")
signal start_requested(c1: String, c2: String)
signal back_requested
signal settings_requested

@onready var panels := [$Player1Panel, $Player2Panel]
var model = StateModel.new()
var _previous: Array = [{}, {}]
var _directions := ["", ""]
var _timers := [0.0, 0.0]
var _blocked := [false, false]
var _clock := 0.0
var _notice := ""
var _notice_timer := 0.0

func _ready() -> void:
	model.changed.connect(_refresh)
	for slot in 2:
		panels[slot].slot = slot
		panels[slot].cycle_requested.connect(_cycle)
		panels[slot].character_requested.connect(_select)
		panels[slot].ready_requested.connect(_ready_player)
		panels[slot].cancel_requested.connect(_cancel)

func open(selections: Array) -> void:
	InputSettings.active_players = 2
	model.open(selections)
	visible = true
	_notice = ""
	prime_inputs()

func close() -> void:
	model.close()
	visible = false
	prime_inputs()

func prime_inputs(slots: Array = [0, 1]) -> void:
	for slot in slots:
		_previous[slot] = InputSettings.poll_lobby_player("p1" if slot == 0 else "p2")
		_blocked[slot] = _previous[slot].values().has(true)
		_directions[slot] = ""
		_timers[slot] = 0.0

func _refresh() -> void:
	if not is_node_ready():
		return
	for slot in 2:
		if model.players.size() == 2:
			panels[slot].choice = model.players[slot]
			panels[slot].occupied_character = model.players[1 - slot].selected_character
		panels[slot].queue_redraw()
	queue_redraw()

func _process(delta: float) -> void:
	_clock += delta
	_notice_timer = maxf(0, _notice_timer - delta)
	if not model.active or not is_visible_in_tree() or model.game_starting:
		return
	if model.active and model.refresh_routes():
		prime_inputs(model.changed_slots)  # Reconnect invalidates only its owner.
	process_inputs(delta)
	for panel in panels:
		panel.clock = _clock
		panel.queue_redraw()
	queue_redraw()

func process_inputs(delta: float) -> void:
	if not model.active or model.game_starting or not is_visible_in_tree():
		return
	if model.refresh_routes():
		prime_inputs(model.changed_slots)
	var states := [InputSettings.poll_lobby_player("p1"), InputSettings.poll_lobby_player("p2")]
	for slot in 2:
		var nav: Dictionary = states[slot]
		if _blocked[slot]:
			_previous[slot] = nav
			if nav.values().has(true):
				continue
			_blocked[slot] = false
		if nav["up"] and not _previous[slot].get("up", false):
			settings_requested.emit()
			prime_inputs()
			return
		var direction := "left" if nav["left"] and not nav["right"] else ("right" if nav["right"] and not nav["left"] else "")
		if direction.is_empty():
			_directions[slot] = ""
			_timers[slot] = 0.0
		else:
			_timers[slot] -= delta
			if direction != _directions[slot] or _timers[slot] <= 0:
				_timers[slot] = 0.35 if direction != _directions[slot] else 0.12
				_directions[slot] = direction
				_cycle(slot, -1 if direction == "left" else 1)
		# Cancel wins over confirm on the same player and frame.
		if nav["cancel"] and not _previous[slot].get("cancel", false):
			if model.players[slot].is_ready:
				_cancel(slot)
			else:
				_request_back()
		elif nav["accept"] and not _previous[slot].get("accept", false):
			if model.players[slot].is_ready:
				request_start()
			else:
				_ready_player(slot)
		elif nav["start"] and not _previous[slot].get("start", false):
			request_start()
		_previous[slot] = nav

func _cycle(slot: int, direction: int) -> void:
	model.cycle_character(slot, direction)

func _select(slot: int, index: int) -> void:
	if not model.select_character(slot, index) and index == model.players[1 - slot].selected_character:
		_notice = "该精灵已被 %dP 选择，请选择其他精灵" % (2 - slot)
		_notice_timer = 2.0

func _ready_player(slot: int) -> void:
	model.ready_player(slot)

func _cancel(slot: int) -> void:
	model.cancel_player(slot)

func request_start() -> void:
	if not is_visible_in_tree():
		return
	var characters: Array = model.begin_game()
	if characters.size() == 2:
		start_requested.emit(characters[0], characters[1])

func _request_back() -> void:
	if model.players.any(func(choice): return choice.is_ready):
		_notice = "请各自取消准备后再返回模式选择"
		_notice_timer = 2.0
		return
	close()
	back_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not model.active or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if model.players[0].is_ready:
			_cancel(0)
		else:
			_request_back()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if Rect2(180, 566, 360, 56).has_point(event.position):
		request_start()
	elif Rect2(20, 566, 136, 56).has_point(event.position):
		_request_back()
	elif Rect2(670, 24, 32, 34).has_point(event.position):
		settings_requested.emit()
	accept_event()

func _draw() -> void:
	if model.players.size() != 2:
		return
	UIDraw.text(self, "LOCAL VERSUS / 双人准备室", 22, 31, {"size": 11, "family": "mono", "fill": UIDraw.INK})
	UIDraw.text(self, "各自选角，一起开战", 20, 65, {"size": 27, "weight": 900, "fill": UIDraw.INK,
		"shadow": UIDraw.ORANGE, "shadowX": 2, "shadowY": 2})
	for slot in 2:
		var choice = model.players[slot]
		var x := 20 if slot == 0 else 368
		var group := "p1vs" if slot == 0 else "p2"
		var hint := "摇杆 / 十字键切换 · A 准备 · B 取消" if choice.device_id >= 0 else "%s %s 切换 · %s 准备 · %s 取消" % [
			InputSettings.first_key_label(group + "_left"), InputSettings.first_key_label(group + "_right"),
			InputSettings.first_key_label(group + "_bomb"), InputSettings.first_key_label(group + "_skill")]
		UIDraw.text(self, hint, x, 102, {"size": 11, "weight": 500, "fill": UIDraw.INK, "max_width": 332})
	var ready := model.can_start_game()
	UIDraw.panel(self, 180, 566, 360, 56, {"fill": UIDraw.YELLOW if ready else UIDraw.PAPER,
		"stroke": UIDraw.INK, "lw": 2.5, "r": 4, "shadow": UIDraw.INK, "shadowX": 4, "shadowY": 4})
	var count := int(model.players[0].is_ready) + int(model.players[1].is_ready)
	UIDraw.text(self, "开始对战" if ready else "等待双方准备  %d / 2" % count, 360, 586,
		{"size": 20, "weight": 900, "fill": UIDraw.INK, "align": "center"})
	UIDraw.text(self, "Start / A / Enter / 点击开始" if ready else "两名玩家分别确认自己的角色", 360, 608,
		{"size": 11, "weight": 500, "fill": UIDraw.INK, "align": "center"})
	UIDraw.panel(self, 20, 566, 136, 56, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2, "r": 4})
	UIDraw.text(self, "← 返回模式", 88, 594, {"size": 13, "fill": UIDraw.INK, "align": "center"})
	UIDraw.panel(self, 670, 24, 32, 34, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2, "r": 3})
	UIDraw.gear(self, 686, 41, UIDraw.INK)
	var footer := "选择对方已占用的精灵时，仅跳过该角色；双方选择互不改动。"
	if _notice_timer > 0:
		footer = _notice
	elif count == 1:
		footer = "已准备的一方等待另一位玩家；修改角色会取消自己的准备。"
	UIDraw.text(self, footer, 360, 654, {"size": 11, "fill": UIDraw.INK, "align": "center", "max_width": 672})
	UIDraw.text(self, "↑ 打开设置 · Esc 返回 / 取消 1P 准备", 360, 680,
		{"size": 11, "weight": 500, "fill": UIDraw.INK, "align": "center"})
