extends Control

## One panel owns one player's preview; it never writes another player's state.
signal cycle_requested(slot: int, direction: int)
signal character_requested(slot: int, character: int)
signal ready_requested(slot: int)
signal cancel_requested(slot: int)

var slot := 0
var choice = null
var occupied_character := -1
var textures := {}
var clock := 0.0
var _last_character := -1
var _last_ready := false
var _swap := 0.0
var _ready_burst := 0.0

func animate(delta: float) -> void:
	if choice == null:
		return
	if choice.selected_character != _last_character:
		_last_character = choice.selected_character
		_swap = 0.0
	if choice.is_ready and not _last_ready:
		_ready_burst = 1.0
	_last_ready = choice.is_ready
	_swap = minf(1, _swap + delta * 4.5)
	_ready_burst = maxf(0, _ready_burst - delta * 2.5)
	queue_redraw()

func _draw_stage(accent: Color, ready: bool) -> void:
	var center := Vector2(size.x * 0.5, 149)
	draw_rect(Rect2(8, 68, size.x - 16, 165), Color("211A2B"))
	UIDraw.dots(self, 8, 68, size.x - 16, 165, accent, 0.13, 12)
	var direction := 1.0 if slot == 0 else -1.0
	for ray in 16:
		var angle := ray * TAU / 16 + clock * 0.16 * direction
		var color := Color(accent, 0.1 if ray % 2 == 0 else 0.04)
		draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(angle) * 79,
			center + Vector2.from_angle(angle + 0.17) * 79]), color)
	draw_circle(center, 67, Color(accent, 0.12), true, -1, true)
	for ring in 3:
		var radius := 68.0 + ring * 5
		for segment in 4:
			var angle := segment * TAU / 4 + clock * (0.3 + ring * 0.12) * direction * (-1 if ring == 1 else 1)
			draw_arc(center, radius, angle, angle + 0.85, 16,
				Color(UIDraw.GREEN if ready else accent, 0.75 - ring * 0.15), 2 if ring == 0 else 1, true)
	for particle in 9:
		var angle := clock * direction * 0.35 + particle * TAU / 9
		var point := center + Vector2.from_angle(angle) * (72 + sin(clock * 1.8 + particle) * 5)
		draw_circle(point, 1.4, accent, true, -1, true)
	if _ready_burst > 0:
		draw_arc(center, 55 + (1 - _ready_burst) * 25, 0, TAU, 64, Color(UIDraw.GREEN, _ready_burst), 4 * _ready_burst, true)
	UIDraw.text(self, "SPIRIT %02d" % (choice.selected_character + 1), 18, 82,
		{"size": 11, "family": "mono", "fill": accent})

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for id in Cfg.CHAR_IDS:
		textures[id] = load("res://assets/characters/%s.png" % id)

func arrow_rect(direction: int) -> Rect2:
	return Rect2(10 if direction < 0 else size.x - 42, 124, 32, 44)

func tile_rect(index: int) -> Rect2:
	return Rect2(12 + index * 51, 326, 44, 42)

func ready_rect() -> Rect2:
	return Rect2(16, 382, size.x - 32, 30)

func _gui_input(event: InputEvent) -> void:
	if choice == null or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	for direction in [-1, 1]:
		if arrow_rect(direction).has_point(event.position):
			cycle_requested.emit(slot, direction)
	for index in Cfg.CHAR_IDS.size():
		if tile_rect(index).has_point(event.position):
			character_requested.emit(slot, index)
	if ready_rect().has_point(event.position):
		if choice.is_ready:
			cancel_requested.emit(slot)
		else:
			ready_requested.emit(slot)
	accept_event()

func _draw() -> void:
	if choice == null:
		return
	var accent := UIDraw.CYAN if slot == 0 else UIDraw.PINK
	var index: int = choice.selected_character
	var id: String = Cfg.CHAR_IDS[index]
	var info := Cfg.char_cfg(id)
	var skill := Cfg.skill_cfg(id)
	var ready: bool = choice.is_ready
	UIDraw.panel(self, 0, 0, size.x, size.y, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2.5,
		"r": 5, "shadow": accent, "shadowX": 5, "shadowY": 5})
	if ready:
		UIDraw.stroke_rr(self, 2, 2, size.x - 4, size.y - 4, 4, Color(UIDraw.GREEN, 0.55 + 0.2 * sin(clock * 3)), 2)
	UIDraw.fill_rr(self, 0, 0, size.x, 62, 5, UIDraw.INK)
	UIDraw.tag(self, "%dP" % (slot + 1), 14, 19, {"size": 16, "family": "impact", "fill": accent,
		"h": 24, "align": "left", "stroke": null})
	UIDraw.text(self, ("已准备 ✓" if ready else "选择中") if choice.has_control else "控制器离线", size.x - 14, 19,
		{"size": 13, "fill": (UIDraw.GREEN if ready else accent) if choice.has_control else UIDraw.ORANGE, "align": "right"})
	var device := "键盘"
	if choice.device_id >= 0:
		device = InputSettings.device_name(choice.device_id)
	elif not choice.has_control:
		device = "手柄未连接 · 请重连或修改设置"
	UIDraw.text(self, device, 14, 47, {"size": 11, "weight": 500, "fill": UIDraw.CREAM, "max_width": size.x - 28})
	_draw_stage(accent, ready)
	var texture: Texture2D = textures.get(id)
	if texture != null:
		var reveal := 1 - pow(1 - _swap, 3)
		var scale_factor := minf(182.0 / texture.get_width(), 154.0 / texture.get_height()) * (0.82 + 0.18 * reveal)
		var dimensions := texture.get_size() * scale_factor
		var slide := (1 - reveal) * (-18 if slot == 0 else 18)
		draw_texture_rect(texture, Rect2(Vector2((size.x - dimensions.x) * 0.5 + slide, 225 - dimensions.y + sin(clock * 2.0 + slot) * 2), dimensions), false,
			Color(1, 1, 1, 0.4 + 0.6 * reveal))
	for direction in [-1, 1]:
		var rect := arrow_rect(direction)
		UIDraw.panel(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			{"fill": UIDraw.INK, "r": 3, "shadow": accent, "shadowX": 2, "shadowY": 2})
		UIDraw.text(self, "‹" if direction < 0 else "›", rect.get_center().x, rect.get_center().y,
			{"size": 28, "fill": UIDraw.CREAM, "align": "center"})
	UIDraw.text(self, info["name"], size.x * 0.5, 246, {"size": 24, "weight": 900, "fill": UIDraw.INK, "align": "center"})
	UIDraw.text(self, skill["name"], size.x * 0.5, 272, {"size": 13, "fill": UIDraw.INK, "align": "center"})
	draw_line(Vector2(16, 281), Vector2(size.x - 16, 281), Color(accent, 0.65), 2, true)
	UIDraw.wrap(self, skill["desc"], 14, 292, size.x - 28, 11, 15, Color(0.12, 0.1, 0.15, 0.8), 2)
	for i in Cfg.CHAR_IDS.size():
		var rect := tile_rect(i)
		UIDraw.panel(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			{"fill": accent if i == index else (Color("D6CBB9") if i == occupied_character else UIDraw.PAPER), "stroke": UIDraw.INK, "lw": 2 if i == index else 1, "r": 3})
		UIDraw.text(self, Cfg.char_cfg(Cfg.CHAR_IDS[i])["name"], rect.get_center().x, rect.position.y + (13 if i == occupied_character else 21),
			{"size": 11, "fill": UIDraw.INK, "align": "center"})
		if i == occupied_character:
			UIDraw.text(self, "%dP" % (2 - slot), rect.get_center().x, rect.position.y + 31,
				{"size": 11, "family": "mono", "fill": UIDraw.INK, "align": "center"})
	var rect := ready_rect()
	UIDraw.panel(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y, {"fill": UIDraw.GREEN if ready else (accent if choice.has_control else UIDraw.MUTED),
		"stroke": UIDraw.INK, "lw": 2, "r": 3, "shadow": UIDraw.INK, "shadowX": 2, "shadowY": 2})
	UIDraw.text(self, "已准备 · 取消准备" if ready else ("确认角色 · 准备" if choice.has_control else "等待手柄连接"), rect.get_center().x, rect.get_center().y,
		{"size": 13, "weight": 900, "fill": UIDraw.INK, "align": "center"})
