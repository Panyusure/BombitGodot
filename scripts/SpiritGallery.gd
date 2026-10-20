class_name SpiritGallery
extends RefCounted

## Single-player character gallery. Geometry is also used by Menu's hit testing
## and keyboard/controller navigation, so rendered and interactive bounds agree.
const BACKGROUND := Color("10151F")
const SURFACE := Color("19212E")
const TEXT := Color("F3F1EA")
const MUTED := Color("A6B1C1")
const GOLD := Color("DDC49A")
const LINE := Color("303B4B")
const HERO := Rect2(24, 86, 672, 284)
const BACK := Rect2(24, 640, 124, 40)
const START := Rect2(468, 640, 228, 40)
const REPLAY := Rect2(540, 26, 112, 32)
const SETTINGS := Rect2(660, 26, 36, 32)
const PALETTES := [
	Color("FFE09A"), Color("C79AFF"), Color("73F2BF"),
	Color("FF9B70"), Color("71D8FF"), Color("FFA9DE"),
]
static var _glow_texture: GradientTexture2D
const EVOLUTIONS := ["诺亚", "修尔", "阿瑞斯", "龙炎", "帝释天", "未来"]
const FOCUS := [
	Vector2(0.48, 0.25), Vector2(0.31, 0.24), Vector2(0.42, 0.40),
	Vector2(0.31, 0.23), Vector2(0.325, 0.38), Vector2(0.43, 0.36),
]

static func card_rect(index: int) -> Rect2:
	return Rect2(24 + index * 114, 522, 102, 98)

static func _text(m: Control, value: String, x: float, y: float, size: int = 12,
		color: Color = TEXT, weight: int = 500, align: String = "left",
		family: String = "cn") -> void:
	UIDraw.text(m, value, x, y, {"size": size, "fill": color,
		"weight": weight, "align": align, "family": family})

static func _panel(m: Control, r: Rect2, fill: Color, border: Color, radius: float = 6.0) -> void:
	UIDraw.panel(m, r.position.x, r.position.y, r.size.x, r.size.y,
		{"fill": fill, "stroke": border, "lw": 1.0, "r": radius})

static func _gradient(m: Control, r: Rect2, top: Color, bottom: Color) -> void:
	m.draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0),
		r.end, r.position + Vector2(0, r.size.y)]), PackedColorArray([top, top, bottom, bottom]))

## One cached GPU gradient supplies all soft lights; no per-frame image baking.
static func _glow(m: Control, center: Vector2, radius: Vector2, color: Color) -> void:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0, 0.22, 0.55, 1])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.6),
			Color(1, 1, 1, 0.13), Color(1, 1, 1, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.width = 128
		_glow_texture.height = 128
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1, 0.5)
	m.draw_texture_rect(_glow_texture, Rect2(center - radius, radius * 2), false, color)

static func _beam(m: Control, a: Vector2, b: Vector2, color: Color, strength: float = 1) -> void:
	m.draw_line(a, b, Color(color, 0.045 * strength), 9, true)
	m.draw_line(a, b, Color(color, 0.16 * strength), 4, true)
	m.draw_line(a, b, Color(color, 0.9 * strength), 1.2, true)

static func _edge_point(r: Rect2, distance: float) -> Vector2:
	var d := fposmod(distance, 2 * (r.size.x + r.size.y))
	if d < r.size.x:
		return r.position + Vector2(d, 0)
	d -= r.size.x
	if d < r.size.y:
		return Vector2(r.end.x, r.position.y + d)
	d -= r.size.y
	if d < r.size.x:
		return r.end - Vector2(d, 0)
	return Vector2(r.position.x, r.end.y - (d - r.size.x))

static func _trace(m: Control, r: Rect2, time: float, color: Color, speed: float = 90) -> void:
	# Short segments follow all four sides, including corners, without diagonals.
	for i in 16:
		var d := time * speed - i * 3.0
		m.draw_line(_edge_point(r, d), _edge_point(r, d - 3),
			Color(color, (1.0 - i / 16.0) * 0.85), 2, true)
	_glow(m, _edge_point(r, time * speed), Vector2(12, 12), Color(color, 0.3))

static func _corners(m: Control, r: Rect2, color: Color, length: float = 16) -> void:
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p: Vector2 = r.get_center() + r.size * 0.5 * corner
		_beam(m, p, p - Vector2(corner.x * length, 0), color, 0.8)
		_beam(m, p, p - Vector2(0, corner.y * length), color, 0.8)

static func _sweep(m: Control, r: Rect2, time: float, color: Color, strength: float) -> void:
	var progress := fposmod(time, 5.5) / 5.5
	if progress > 0.42:
		return
	var x := lerpf(r.position.x - 120, r.end.x + 150, progress / 0.42)
	# Polygon clipping keeps the traveling light within its panel.
	var strip := PackedVector2Array([Vector2(x, r.position.y), Vector2(x + 35, r.position.y),
		Vector2(x - 55, r.end.y), Vector2(x - 90, r.end.y)])
	var clip := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
		r.end, Vector2(r.position.x, r.end.y)])
	for part in Geometry2D.intersect_polygons(strip, clip):
		if part.size() >= 3:
			m.draw_colored_polygon(part, Color(color, strength * sin(progress / 0.42 * PI)))

static func _draw_ambient(m: Control, accent: Color) -> void:
	var time: float = m.t
	_glow(m, Vector2(90 + sin(time * 0.3) * 45, 65), Vector2(310, 180), Color(accent, 0.17))
	_glow(m, Vector2(690, 545), Vector2(230, 260), Color(accent, 0.12))
	for x in range(24, 700, 28):
		for y in [76, 480, 630, 689]:
			m.draw_circle(Vector2(x, y), 0.6, Color(accent, 0.16), true, -1, true)
	for i in 5:
		var x := 390.0 + i * 21
		m.draw_line(Vector2(x, 24), Vector2(x + 13, 11), Color(accent, 0.12 + i * 0.025), 3, true)
	_beam(m, Vector2(24, 73), Vector2(170, 73), accent, 0.6)
	_beam(m, Vector2(550, 689), Vector2(696, 689), accent, 0.6)
	_text(m, "02", 510, 51, 27, Color(accent, 0.20), 700, "right", "mono")

static func _wrap(m: Control, value: String, pos: Vector2, width: float,
		size: int, color: Color, max_lines: int) -> void:
	var lines := UIDraw.wrap_lines(value, width, size, max_lines, 500, "cn")
	for i in lines.size():
		_text(m, lines[i], pos.x, pos.y + i * 19, size, color)

static func draw(m: Control) -> void:
	var idx: int = int(m.char_index[m.player])
	var cid: String = Cfg.CHAR_IDS[idx]
	var accent: Color = PALETTES[idx]
	m.draw_rect(Rect2(0, 0, 720, 696), BACKGROUND)
	_gradient(m, Rect2(0, 0, 720, 410), Color(accent, 0.055), Color(accent, 0))
	_draw_ambient(m, accent)
	_draw_header(m)
	_draw_hero(m, cid, idx, accent)
	_draw_details(m, cid, accent)
	_draw_roster(m, idx, accent)
	_draw_actions(m, cid, accent)

static func _draw_header(m: Control) -> void:
	_text(m, "BOMBIT  /  SPIRIT COLLECTION", 24, 20, 10, GOLD, 500, "left", "mono")
	var accent: Color = PALETTES[int(m.char_index[m.player])]
	UIDraw.text(m, "选择你的精灵", 24, 52, {"size": 26, "fill": Color.TRANSPARENT,
		"stroke": Color(accent, 0.14), "strokeWidth": 3, "weight": 700})
	_text(m, "选择你的精灵", 24, 52, 26, TEXT, 700)
	var mode: Dictionary = m._mode()
	m.draw_line(Vector2(231, 39), Vector2(231, 63), LINE, 1, true)
	_text(m, String(mode["label"]), 246, 45, 12, TEXT)
	_text(m, "单人冒险" if mode["id"] == "adventure" else "限时挑战",
		246, 63, 10, MUTED)
	var hovered: bool = m.hover.get("kind", "") == "replay"
	_panel(m, REPLAY, SURFACE if hovered else Color(SURFACE, 0.4), GOLD if hovered else LINE)
	_text(m, "对局回放  ↗", REPLAY.get_center().x, REPLAY.get_center().y, 11,
		TEXT if hovered else MUTED, 500, "center")
	hovered = m.hover.get("kind", "") == "settings"
	_panel(m, SETTINGS, SURFACE if hovered else Color(SURFACE, 0.4), GOLD if hovered else LINE)
	var center := SETTINGS.get_center()
	# Sliders remain legible at this size without a heavy gear silhouette.
	for i in 3:
		var y := center.y - 6 + i * 6
		m.draw_line(Vector2(center.x - 7, y), Vector2(center.x + 7, y), MUTED, 1, true)
		m.draw_circle(Vector2(center.x + (-3 if i % 2 == 0 else 3), y), 2,
			GOLD if hovered else TEXT, true, -1, true)

## Cover crop around each original illustration's focal point. Motion never
## changes the destination rectangle or stretches the art.
static func poster_uv(tex: Texture2D, index: int, push: float) -> Rect2:
	var aspect := tex.get_size().x / tex.get_size().y
	var view_aspect := HERO.size.x / HERO.size.y
	var crop := Vector2(minf(1.0, view_aspect / aspect), minf(1.0, aspect / view_aspect))
	crop /= 1.0 + push
	var focus: Vector2 = FOCUS[index]
	var origin := focus - crop * Vector2(0.46, 0.36)
	origin.x = clampf(origin.x, 0, 1.0 - crop.x)
	origin.y = clampf(origin.y, 0, 1.0 - crop.y)
	return Rect2(origin, crop)

static func _art(m: Control, cid: String, alpha: float, push: float) -> void:
	var tex: Texture2D = m.poster_tex.get(cid)
	if tex == null:
		# Keep selection usable if an optional poster has not been imported.
		var sprite: Texture2D = m.char_tex.get(cid)
		if sprite != null:
			var size := sprite.get_size() * (HERO.size.y - 28) / sprite.get_height()
			m.draw_texture_rect(sprite, Rect2(HERO.get_center() - size * 0.5, size),
				false, Color(1, 1, 1, alpha))
		return
	var uv := poster_uv(tex, Cfg.CHAR_IDS.find(cid), push)
	var pointer: Vector2 = m.gallery_pointer
	uv.position.x = clampf(uv.position.x + pointer.x * 0.008, 0, 1 - uv.size.x)
	uv.position.y = clampf(uv.position.y + pointer.y * 0.006, 0, 1 - uv.size.y)
	m.draw_texture_rect_region(tex, HERO,
		Rect2(uv.position * tex.get_size(), uv.size * tex.get_size()), Color(1, 1, 1, alpha))

static func _draw_hero(m: Control, cid: String, idx: int, accent: Color) -> void:
	var enter := 1.0 - pow(1.0 - minf(m.stage_t / 0.6, 1.0), 3)
	var mix_value := smoothstep(0, 1, m.poster_mix)
	var push := 0.018 + 0.04 * (1.0 - enter) + 0.025 * (1.0 - mix_value) + sin(m.t * 0.55) * 0.006
	m.draw_rect(HERO, SURFACE)
	if m.poster_prev != "" and m.poster_prev != cid and mix_value < 1:
		_art(m, m.poster_prev, 1, 0)
		_art(m, cid, mix_value, push)
	else:
		_art(m, cid, 1, push)
	_draw_hero_energy(m, idx, accent)
	# Preserve the painting's luminosity. Shade only the two text areas.
	_gradient(m, Rect2(24, 86, 672, 54), Color(BACKGROUND, 0.52), Color(BACKGROUND, 0))
	_gradient(m, Rect2(24, 263, 672, 107), Color(BACKGROUND, 0), Color(BACKGROUND, 0.96))
	m.draw_rect(HERO, Color(TEXT, 0.15), false, 1)
	m.draw_line(Vector2(24, 86), Vector2(90, 86), accent, 2, true)
	_corners(m, HERO.grow(3), accent, 22)
	_trace(m, HERO.grow(1), m.t, accent, 145)
	_panel(m, Rect2(38, 98, 76, 22), Color(BACKGROUND, 0.7), Color(TEXT, 0.1), 3)
	_text(m, "%02d  /  06" % (idx + 1), 76, 109, 10, TEXT, 500, "center", "mono")
	var caption: String = EVOLUTIONS[idx] + (" · 通灵形态" if cid == "weilai" else " · 进化形态")
	var caption_w := UIDraw.measure(caption, 10, 500) + 20
	_panel(m, Rect2(682 - caption_w, 98, caption_w, 22),
		Color(BACKGROUND, 0.7), Color(TEXT, 0.1), 3)
	_text(m, caption, 672, 109, 10, TEXT, 500, "right")
	var cfg := Cfg.char_cfg(cid)
	UIDraw.text(m, cfg["name"], 42, 319, {"size": 38, "weight": 700,
		"fill": Color.TRANSPARENT, "stroke": Color(accent, 0.22), "strokeWidth": 4})
	_text(m, cfg["name"], 42, 319, 38, TEXT, 700)
	_text(m, cfg["title"], 44, 351, 12, accent, 700)
	_beam(m, Vector2(44, 365), Vector2(116, 365), accent)
	var skill := Cfg.skill_cfg(cid)
	_text(m, skill["tag"], 676, 344, 12, TEXT, 500, "right")
	m.draw_circle(Vector2(676 - UIDraw.measure(skill["tag"], 12, 500) - 13, 344),
		2.5, accent, true, -1, true)

static func _draw_hero_energy(m: Control, index: int, accent: Color) -> void:
	var time: float = m.t
	var center := Vector2(572, 222)
	_glow(m, center, Vector2(112, 112), Color(accent, 0.17 + sin(time * 1.7) * 0.04))
	# Two counter-rotating, broken rune rings stay in the scenery beside the face.
	for ring in 2:
		var radius := 72.0 + ring * 20
		var rotation := time * (0.17 if ring == 0 else -0.11) + index * 0.6
		for segment in 6:
			var angle := rotation + segment * TAU / 6
			m.draw_arc(center, radius, angle, angle + 0.67, 18, Color(accent, 0.23), 1, true)
		for tick in 24:
			var angle := rotation + tick * TAU / 24
			var direction := Vector2(cos(angle), sin(angle))
			m.draw_line(center + direction * (radius - 3),
				center + direction * (radius + (3 if tick % 3 == 0 else 0)), Color(accent, 0.32), 1, true)
		var orbit := center + Vector2(cos(rotation), sin(rotation)) * radius
		_glow(m, orbit, Vector2(13, 13), Color(accent, 0.7))
		m.draw_circle(orbit, 1.7, TEXT, true, -1, true)
	# All particles have deterministic lifetimes and fade at both ends.
	for i in 27:
		var seed := fposmod(i * 0.6180339, 1.0)
		var life := fposmod(time * (0.10 + seed * 0.07) + i * 0.137, 1)
		var opacity := sin(life * PI) * (0.24 + seed * 0.45)
		var p := Vector2(44 + fposmod(i * 97.3, 630) + sin(time * 0.5 + i) * 9,
			352 - life * 210)
		_glow(m, p, Vector2(7, 7), Color(accent, opacity * 0.5))
		if index == 1 or index == 3:
			m.draw_line(p, p + Vector2(-2, 7 + seed * 6), Color(accent, opacity), 1.2, true)
		elif index == 0 or index == 4:
			m.draw_line(p - Vector2(3, 0), p + Vector2(3, 0), Color(accent, opacity), 1, true)
			m.draw_line(p - Vector2(0, 3), p + Vector2(0, 3), Color(accent, opacity), 1, true)
		else:
			m.draw_circle(p, 1 + seed, Color(accent, opacity), true, -1, true)
	_sweep(m, HERO, time, accent, 0.09)
	var reveal: float = clampf(m.switch_t, 0, 1)
	if reveal < 1:
		var radius := 22 + 83 * reveal
		m.draw_arc(center, radius, 0, TAU, 64, Color(accent, (1 - reveal) * 0.6), 2, true)
		_glow(m, center, Vector2(108, 108), Color(accent, (1 - reveal) * 0.28))
		_beam(m, Vector2(24, 370), Vector2(24 + 672 * reveal, 370), accent, 1 - reveal)

static func _draw_details(m: Control, cid: String, accent: Color) -> void:
	var cfg := Cfg.char_cfg(cid)
	var skill := Cfg.skill_cfg(cid)
	_gradient(m, Rect2(252, 380, 444, 99), Color(accent, 0.075), Color(accent, 0.005))
	m.draw_line(Vector2(252, 380), Vector2(320, 380), Color(accent, 0.45), 1, true)
	_text(m, "角色档案", 24, 394, 10, accent, 700)
	_wrap(m, cfg["intro"], Vector2(24, 419), 200, 12, MUTED, 3)
	m.draw_line(Vector2(242, 390), Vector2(242, 476), LINE, 1, true)
	var passive: bool = bool(skill.get("passive", false))
	var key_label := "被动"
	if not passive:
		key_label = InputSettings.first_key_label(InputSettings.action_for("p1", "skill"))
		if InputSettings.last_source("p1") == "gamepad":
			var labels := InputSettings.pad_labels(InputSettings.action_for("p1", "skill"))
			key_label = String(labels[0]) if not labels.is_empty() else "未绑定"
	# Reserve a bounded keycap so even long remapped keys cannot hit cooldown.
	key_label = UIDraw.fit(key_label, 66, 10, 500, "cn")
	var key_w := maxf(26, UIDraw.measure(key_label, 10, 500) + 16)
	_panel(m, Rect2(262, 385, key_w, 22), Color(accent, 0.09), Color(accent, 0.28), 4)
	_glow(m, Vector2(262 + key_w * 0.5, 396), Vector2(31, 24),
		Color(accent, 0.10 + sin(m.t * 2) * 0.04))
	_text(m, key_label, 262 + key_w * 0.5, 396, 10, accent, 500, "center")
	_text(m, skill["name"], 274 + key_w, 396, 16, TEXT, 700)
	_text(m, "放弹触发" if passive else "冷却 %d 秒" % int(skill["cd"]),
		696, 396, 11, MUTED, 500, "right")
	_wrap(m, skill["desc"], Vector2(262, 424), 434, 12, TEXT, 3)

static func _draw_roster(m: Control, selected: int, accent: Color) -> void:
	m.draw_line(Vector2(24, 488), Vector2(696, 488), LINE, 1, true)
	var energy_x := 24 + fposmod(m.t * 65, 600)
	_beam(m, Vector2(energy_x, 488), Vector2(energy_x + 55, 488), accent, 0.55)
	_text(m, "出战精灵", 24, 505, 12, TEXT, 700)
	_text(m, "06 位精灵  /  选择一位伙伴", 696, 505, 10, MUTED, 500, "right")
	for i in Cfg.CHAR_IDS.size():
		var r := card_rect(i)
		var active := selected == i
		var hover_amount: float = m.gallery_hover[i]
		var tint: Color = PALETTES[i]
		var fill := SURFACE.lerp(tint, 0.14 if active else 0.035 + hover_amount * 0.06)
		var breath: float = 0.5 + 0.5 * sin(m.t * 2.6)
		if active:
			_glow(m, r.get_center(), Vector2(72, 73), Color(accent, 0.20 + breath * 0.09))
		_panel(m, r, fill, accent if active else LINE.lerp(MUTED, hover_amount * 0.55), 6)
		var x := r.position.x
		var y := r.position.y
		if active or hover_amount > 0.01:
			_glow(m, Vector2(x + 51, y + 40), Vector2(49, 39),
				Color(tint, 0.28 if active else hover_amount * 0.20))
			for ring in 2:
				var angle: float = m.t * (0.7 if ring == 0 else -0.5)
				m.draw_arc(Vector2(x + 51, y + 38), 32 + ring * 5,
					angle, angle + PI * 1.3, 32, Color(tint, 0.36), 1, true)
		m.draw_arc(Vector2(x + 51, y + 39), 28, PI * 0.12, PI * 0.9, 32,
			Color(tint, 0.15), 1, true)
		var texture: Texture2D = m.char_tex.get(Cfg.CHAR_IDS[i])
		if texture != null:
			# Fit the upper body, keeping ears and hair intact for every spirit.
			var source := Rect2(0, 0, texture.get_width(), texture.get_height() * 0.68)
			var fit := minf(76 / source.size.x, 65 / source.size.y)
			var size := source.size * fit
			var bob: float = sin(m.t * 2.6) * 1.7 if active else 0
			var position := Vector2(x + (102 - size.x) * 0.5, y + 6 - hover_amount * 2 + bob)
			m.draw_texture_rect_region(texture, Rect2(position, size), source)
		_gradient(m, Rect2(x + 1, y + 60, 100, 15), Color(fill, 0), fill)
		_text(m, Cfg.char_cfg(Cfg.CHAR_IDS[i])["name"], x + 51, y + 83, 12,
			TEXT if active else MUTED, 700 if active else 500, "center")
		if active:
			_corners(m, r.grow(2), accent, 9)
			_trace(m, r.grow(1), m.t, accent, 64)
			m.draw_circle(Vector2(x + 88, y + 12), 6, accent, true, -1, true)
			m.draw_polyline(PackedVector2Array([Vector2(x + 85, y + 12),
				Vector2(x + 87, y + 14), Vector2(x + 91, y + 10)]), BACKGROUND, 1.5, true)
			m.draw_line(Vector2(x + 35, y + 97), Vector2(x + 67, y + 97), accent, 2, true)

static func _draw_actions(m: Control, cid: String, accent: Color) -> void:
	var hover_back: bool = m.hover.get("kind", "") == "back"
	_panel(m, BACK, SURFACE if hover_back else Color(SURFACE, 0), MUTED if hover_back else LINE)
	_text(m, "←  返回模式", BACK.get_center().x, 660, 12, TEXT if hover_back else MUTED, 500, "center")
	_text(m, "方向键选择  ·  ESC 返回", 168, 660, 10, MUTED)
	var hover_start: bool = m.hover.get("kind", "") == "cta"
	var fill := accent.lightened(0.12) if hover_start else accent
	_glow(m, START.get_center(), Vector2(151, 35), Color(accent, 0.28 + sin(m.t * 2) * 0.06))
	_panel(m, START, fill, fill, 6)
	_gradient(m, START.grow(-1), Color.WHITE * Color(1, 1, 1, 0.22), Color(accent.darkened(0.3), 0.22))
	_sweep(m, START.grow(-2), m.t * 1.5, Color.WHITE, 0.35)
	_trace(m, START.grow(2), m.t, accent.lightened(0.3), 110)
	_text(m, "携 " + String(Cfg.char_cfg(cid)["name"]) + " 出发", 488, 660, 16, BACKGROUND, 700)
	_text(m, "ENTER  →", 680, 660, 10, BACKGROUND, 500, "right", "mono")
