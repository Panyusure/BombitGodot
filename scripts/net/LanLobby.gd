extends Control

signal back_requested
const PlayerPanel = preload("res://scripts/LobbyPlayerPanel.gd")
const Choice = preload("res://scripts/VersusLobbyState.gd").PlayerChoice
var session: Node
var address: LineEdit
var port: LineEdit
var create_button: Button
var join_button: Button
var back_button: Button
var start_button: Button
var panels: Array = []
var previous := {}
var clock := 0.0
var direction := ""
var repeat_time := 0.0
var wallpaper: Texture2D
var last_phase := ""

func button(label: String, rect: Rect2, callback: Callable) -> Button:
	var control := Button.new()
	control.text = label
	control.position = rect.position
	control.size = rect.size
	control.add_theme_font_override("font", UIDraw.font())
	control.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = UIDraw.YELLOW if state in ["hover", "focus"] else UIDraw.CREAM
		style.border_color = UIDraw.INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		control.add_theme_stylebox_override(state, style)
	control.add_theme_color_override("font_color", UIDraw.INK)
	control.add_theme_color_override("font_hover_color", UIDraw.INK)
	control.add_theme_color_override("font_focus_color", UIDraw.INK)
	control.add_theme_color_override("font_pressed_color", UIDraw.INK)
	control.add_theme_color_override("font_disabled_color", UIDraw.MUTED)
	control.pressed.connect(callback)
	add_child(control)
	return control

func field(rect: Rect2, value: String, hint: String) -> LineEdit:
	var control := LineEdit.new()
	control.position = rect.position
	control.size = rect.size
	control.text = value
	control.placeholder_text = hint
	control.max_length = 45
	control.add_theme_font_override("font", UIDraw.font("mono"))
	control.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = UIDraw.WHITE
	style.border_color = UIDraw.INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	control.add_theme_stylebox_override("normal", style)
	control.add_theme_stylebox_override("focus", style)
	control.add_theme_color_override("font_color", UIDraw.INK)
	control.add_theme_color_override("font_placeholder_color", UIDraw.MUTED)
	add_child(control)
	return control

func _ready() -> void:
	visible = false
	wallpaper = load("res://assets/ui/menu-wallpaper.jpg")
	address = field(Rect2(72, 250, 428, 44), "", "Host IP / 192.168.1.8")
	port = field(Rect2(514, 250, 134, 44), "24566", "端口")
	create_button = button("创建房间", Rect2(72, 330, 270, 58), _host)
	join_button = button("加入房间", Rect2(378, 330, 270, 58), _join)
	back_button = button("← 返回主菜单", Rect2(20, 566, 160, 56), func(): back_requested.emit())
	start_button = button("等待双方准备", Rect2(220, 566, 480, 56), func(): session.start_game())
	for slot in 2:
		var panel = PlayerPanel.new()
		panel.slot = slot
		panel.position = Vector2(20 + slot * 348, 126)
		panel.size = Vector2(332, 420)
		panel.cycle_requested.connect(_cycle)
		panel.character_requested.connect(_select)
		panel.ready_requested.connect(func(owner):
			if owner == session.slot: session.ready_player(true))
		panel.cancel_requested.connect(func(owner):
			if owner == session.slot: session.ready_player(false))
		add_child(panel)
		panels.append(panel)
	address.text_submitted.connect(func(_value): _join())

func setup(connection: Node) -> void:
	session = connection
	session.changed.connect(refresh)
	refresh()

func open() -> void:
	InputSettings.active_players = 1
	visible = true
	previous = InputSettings.poll_nav()
	refresh()
	if session.phase == "home":
		create_button.grab_focus()

func _host() -> void:
	session.create_room(int(port.text))
	previous = InputSettings.poll_nav()

func _join() -> void:
	session.join_room(address.text.strip_edges(), int(port.text))
	previous = InputSettings.poll_nav()

func refresh() -> void:
	if session == null:
		return
	var home: bool = session.phase in ["home", "connecting"]
	for control in [address, port, create_button, join_button]:
		control.visible = home
	create_button.disabled = session.phase == "connecting"
	join_button.disabled = session.phase == "connecting"
	start_button.visible = not home
	start_button.disabled = not session.can_start()
	start_button.text = "开始联机对战" if session.can_start() else ("仅房主可开始 · 等待准备" if not session.host else "等待双方连接并准备")
	back_button.text = "← 返回主菜单" if home else "离开房间"
	back_button.focus_mode = Control.FOCUS_ALL if home else Control.FOCUS_NONE
	start_button.focus_mode = Control.FOCUS_NONE
	for slot in 2:
		var panel = panels[slot]
		panel.visible = not home and session.players.size() == 2
		if not panel.visible:
			continue
		var data: Dictionary = session.players[slot]
		var choice = Choice.new("p%d" % (slot + 1), data["character"])
		choice.is_ready = data["ready"]
		choice.is_character_confirmed = data["confirmed"]
		choice.has_control = data["online"]
		panel.choice = choice
		panel.occupied_character = session.players[1 - slot]["character"]
		panel.network_label = ("本机 · " if slot == session.slot else "远端 · ") + ("房主" if slot == 0 else "来宾") + (" · 已连接" if data["online"] else " · 等待加入")
		panel.network_readonly = slot != session.slot or not data["online"]
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE if panel.network_readonly else Control.MOUSE_FILTER_STOP
	if last_phase != session.phase:
		previous = InputSettings.poll_nav()
		direction = ""
		repeat_time = 0
		last_phase = session.phase
	queue_redraw()

func _select(owner: int, index: int) -> void:
	if owner == session.slot:
		session.choose(index)

func _cycle(owner: int, amount: int) -> void:
	if owner != session.slot or session.players.size() != 2:
		return
	var current: int = session.players[owner]["character"]
	for i in Cfg.CHAR_IDS.size():
		current = posmod(current + amount, Cfg.CHAR_IDS.size())
		if current != session.players[1 - owner]["character"]:
			session.choose(current)
			return

func _process(delta: float) -> void:
	if not visible or session == null:
		return
	clock += delta
	for panel in panels:
		panel.clock = clock
		if panel.visible:
			panel.animate(delta)
	if session.phase == "lobby" and session.players.size() == 2:
		var nav := InputSettings.poll_nav()
		var next := "left" if nav["left"] else ("right" if nav["right"] else "")
		repeat_time -= delta
		if next != "" and (next != direction or repeat_time <= 0):
			repeat_time = 0.35 if next != direction else 0.12
			_cycle(session.slot, -1 if next == "left" else 1)
		direction = next
		if nav["accept"] and not previous.get("accept", false):
			session.ready_player(not session.players[session.slot]["ready"])
		if nav["cancel"] and not previous.get("cancel", false):
			if session.players[session.slot]["ready"]:
				session.ready_player(false)
			else:
				back_requested.emit()
		previous = nav
	elif session.phase in ["home", "connecting"]:
		var nav := InputSettings.poll_nav()
		if nav["cancel"] and not previous.get("cancel", false):
			back_requested.emit()
		previous = nav
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if session.phase == "lobby" and session.players[session.slot]["ready"]:
			session.ready_player(false)
		else:
			back_requested.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		session.start_game()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		session.start_game()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if session == null:
		return
	draw_rect(Rect2(0, 0, 720, 696), UIDraw.PAPER)
	if wallpaper != null:
		draw_texture_rect(wallpaper, Rect2(0, 0, 720, 696), false, Color(1, 1, 1, 0.06))
	UIDraw.dots(self, 0, 0, 720, 696, UIDraw.INK, 0.07, 16)
	UIDraw.text(self, "MODE 04 / LAN VERSUS", 22, 27, {"size": 11, "family": "mono", "fill": UIDraw.INK})
	UIDraw.text(self, "局域网联机对战", 20, 62, {"size": 28, "fill": UIDraw.INK, "shadow": UIDraw.YELLOW})
	var home: bool = session.phase in ["home", "connecting"]
	if home:
		UIDraw.panel(self, 48, 138, 624, 356, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2.5, "r": 5, "shadow": UIDraw.YELLOW})
		UIDraw.text(self, "两台电脑，同一片战场", 72, 177, {"size": 23, "fill": UIDraw.INK})
		UIDraw.text(self, "加入时填写房主 IP；创建房间可直接使用下方端口。", 72, 211, {"size": 12, "fill": UIDraw.INK})
		UIDraw.text(self, "房主 IP", 72, 237, {"size": 11, "fill": UIDraw.INK})
		UIDraw.text(self, "UDP 端口", 514, 237, {"size": 11, "fill": UIDraw.INK})
		UIDraw.wrap(self, "同一局域网内连接。首次运行请允许游戏通过系统防火墙；两端使用相同版本。", 72, 426, 570, 12, 19, UIDraw.INK, 2)
	else:
		var ip: String = session.address
		if session.host:
			var addresses := Array(IP.get_local_addresses()).filter(func(value): return "." in value and not value.begins_with("127.") and not value.begins_with("169.254."))
			ip = " / ".join(addresses)
		UIDraw.text(self, "房主 %s : %d" % [ip, session.port], 20, 97,
			{"size": 12, "fill": UIDraw.INK, "max_width": 680})
	UIDraw.wrap(self, session.notice, 22, 642, 676, 12, 18, UIDraw.INK, 2)
	UIDraw.text(self, "← → 选角 · A / Enter 准备 · B 取消 · 房主 Start / F5 开战", 360, 682,
		{"size": 11, "fill": UIDraw.INK, "align": "center"})
