class_name Overlay
extends Control

## 关前敌情档案 / 暂停 / 结算 / 横幅。版式对照原作 hud.js、pause.js、result.js。

signal action(name: String)

enum Mode { NONE, BRIEF, PAUSE, RESULT }

const BRIEF_CARD = {"x": 56.0, "y": 72.0, "w": 608.0, "h": 552.0}
const BRIEF_HEADER = 74.0
const BRIEF_BTN = {"x": 230.0, "y": 530.0, "w": 260.0, "h": 46.0}
const PAUSE_CARD = {"w": 430.0, "h": 430.0}
const PAUSE_BTN = {"w": 300.0, "h": 52.0, "gap": 12.0}
const RESULT_CARD = {"w": 560.0, "h": 430.0}
const RESULT_BTN = {"w": 210.0, "h": 52.0, "gap": 20.0}
## 导航方向键首次重复延迟 / 之后每格间隔（与 Menu 一致）
const NAV_FIRST_DELAY := 0.35
const NAV_REPEAT_DELAY := 0.09

var world: World = null
var summary: Dictionary = {}
var mode = Mode.NONE
var appear = 0.0
var t = 0.0
var index = 0
var hover = -1
var confetti: Array = []
var _banner: Control = null
# 手柄 / 键盘导航：nav_mode=true 时高亮来自导航（鼠标悬停让位）
var nav_mode := false
var nav_dir := ""
var nav_timer := 0.0
var nav_accept_prev := false
var nav_cancel_prev := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)

func _process(delta: float) -> void:
	t += delta
	if mode == Mode.NONE:
		return
	# 原作入场速度：暂停 pause.js:59 为 dt*6，结算 result.js:67 为 dt*3.2。
	appear = minf(1.0, appear + delta * (3.2 if mode == Mode.RESULT else (6.0 if mode == Mode.PAUSE else 5.0)))
	if mode == Mode.RESULT:
		for c in confetti:
			c["y"] = float(c["y"]) + float(c["vy"]) * delta
			c["rot"] = float(c["rot"]) + delta * 3.0
			if float(c["y"]) > Cfg.VIEW_H + 20:
				c["y"] = -20.0
				c["x"] = fmod(float(c["x"]) + 91.0, Cfg.VIEW_W)
	if visible:
		_update_hover()
		_process_nav(delta)
	queue_redraw()

# ---------------- 手柄 / 键盘导航 ----------------
#
# 暂停的三个操作与设置齿轮 / 简报按钮 / 结算按钮接到导航状态机上，
# 高亮沿用原有的「选中项 = 墨色反白」，另加一圈呼吸焦点环。
# 方向与确认交给这里（限速重复），快捷键（R / M / Esc）仍走 _unhandled_input 与 Main。

func _process_nav(delta: float) -> void:
	var nav: Dictionary = InputSettings.poll_nav()
	var dir := ""
	if bool(nav["up"]):
		dir = "up"
	elif bool(nav["down"]):
		dir = "down"
	elif mode == Mode.RESULT and bool(nav["left"]):
		dir = "left"
	elif mode == Mode.RESULT and bool(nav["right"]):
		dir = "right"
	if dir.is_empty():
		nav_dir = ""
		nav_timer = 0.0
	elif dir != nav_dir:
		nav_dir = dir
		nav_timer = NAV_FIRST_DELAY
		_nav_step(-1 if dir in ["up", "left"] else 1)
	else:
		nav_timer -= delta
		if nav_timer <= 0.0:
			nav_timer = NAV_REPEAT_DELAY
			_nav_step(-1 if dir in ["up", "left"] else 1)
	var acc := bool(nav["accept"])
	if acc and not nav_accept_prev:
		nav_mode = true
		match mode:
			Mode.BRIEF:
				action.emit("start")
			Mode.PAUSE:
				_pause_action(index)
			Mode.RESULT:
				action.emit("restart" if index == 0 else "menu")
	nav_accept_prev = acc
	var can := bool(nav["cancel"])
	if can and not nav_cancel_prev:
		nav_mode = true
		match mode:
			Mode.BRIEF:
				action.emit("menu")
			Mode.PAUSE:
				action.emit("resume")
			Mode.RESULT:
				action.emit("menu")
	nav_cancel_prev = can

func _nav_step(step_dir: int) -> void:
	nav_mode = true
	if mode == Mode.PAUSE:
		index = (index + step_dir + 4) % 4
	elif mode == Mode.RESULT:
		index = (index + step_dir + 2) % 2

func _sync_nav() -> void:
	var nav := InputSettings.poll_nav()
	nav_accept_prev = bool(nav["accept"])
	nav_cancel_prev = bool(nav["cancel"])
	nav_dir = ""
	nav_timer = 0.0

func _nav_ring() -> void:
	if not nav_mode or mode == Mode.NONE:
		return
	var r := Rect2()
	match mode:
		Mode.BRIEF:
			r = Rect2(BRIEF_BTN["x"], BRIEF_BTN["y"], BRIEF_BTN["w"], BRIEF_BTN["h"])
		Mode.PAUSE:
			r = _pause_btn(index)
		Mode.RESULT:
			r = _result_btn(index)
		_:
			return
	if r.size.x <= 0.0:
		return
	var col := UIDraw.YELLOW
	col.a = 0.68 + 0.32 * (0.5 + 0.5 * sin(t * 7.0))
	UIDraw.stroke_rr(self, r.position.x - 3.0, r.position.y - 3.0,
		r.size.x + 6.0, r.size.y + 6.0, 6.0, UIDraw.INK, 3.0)
	UIDraw.stroke_rr(self, r.position.x - 6.0, r.position.y - 6.0,
		r.size.x + 12.0, r.size.y + 12.0, 8.0, col, 2.0)

func _update_hover() -> void:
	hover = -1
	if mode == Mode.NONE:
		return
	# 导航（手柄 / 方向键）刚操作过：鼠标悬停让位，避免两处同时高亮
	if nav_mode:
		return
	var p = get_local_mouse_position()
	if mode == Mode.BRIEF:
		if Rect2(BRIEF_BTN["x"], BRIEF_BTN["y"], BRIEF_BTN["w"], BRIEF_BTN["h"]).has_point(p):
			hover = 0
	elif mode == Mode.PAUSE:
		for i in 4:
			if _pause_btn(i).has_point(p):
				hover = i
				index = i
	elif mode == Mode.RESULT:
		for i in 2:
			if _result_btn(i).has_point(p):
				hover = i

# ---------------- 对外接口 ----------------

func show_briefing(w: World) -> void:
	world = w
	mode = Mode.BRIEF
	index = 0
	_sync_nav()
	appear = 0.0
	hover = -1
	_clear_banner()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func show_pause() -> void:
	mode = Mode.PAUSE
	appear = 0.0
	index = 0
	_sync_nav()
	hover = -1
	_clear_banner()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func show_result(sum: Dictionary) -> void:
	summary = sum
	mode = Mode.RESULT
	index = 0
	_sync_nav()
	appear = 0.0
	hover = -1
	_clear_banner()
	confetti = _make_confetti(sum)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func hide_overlay() -> void:
	mode = Mode.NONE
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover = -1
	queue_redraw()

func show_banner(text: String, sub: String = "", color: Color = UIDraw.ORANGE) -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	var holder = Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_banner = holder
	var box = VBoxContainer.new()
	box.position = Vector2(0, 132)
	box.size = Vector2(Cfg.VIEW_W, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.pivot_offset = Vector2(Cfg.VIEW_W * 0.5, 40)
	holder.add_child(box)
	var title = Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", color)
	title.add_theme_color_override("font_outline_color", UIDraw.INK)
	title.add_theme_constant_override("outline_size", 8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	if not sub.is_empty():
		var subtitle = Label.new()
		subtitle.text = sub
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.add_theme_font_size_override("font_size", 18)
		subtitle.add_theme_color_override("font_color", UIDraw.CREAM)
		subtitle.add_theme_color_override("font_outline_color", UIDraw.INK)
		subtitle.add_theme_constant_override("outline_size", 6)
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(subtitle)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, "modulate:a", 0.0, 0.5).set_delay(2.4)
	tween.tween_property(box, "scale", Vector2(1.06, 1.06), 0.28)
	tween.chain().tween_callback(holder.queue_free)

func _clear_banner() -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	_banner = null

# ---------------- 布局 ----------------

func _pause_card() -> Rect2:
	return Rect2((Cfg.VIEW_W - PAUSE_CARD["w"]) * 0.5, (Cfg.VIEW_H - PAUSE_CARD["h"]) * 0.5,
		PAUSE_CARD["w"], PAUSE_CARD["h"])

func _pause_btn(i: int) -> Rect2:
	var c = _pause_card()
	if i == 3:
		return Rect2(c.end.x - 66, c.position.y + 86, 40, 40)
	var total: float = 3 * PAUSE_BTN["h"] + 2 * PAUSE_BTN["gap"]
	var y0 = c.position.y + c.size.y - total - 24
	return Rect2(c.position.x + (c.size.x - PAUSE_BTN["w"]) * 0.5,
		y0 + i * (PAUSE_BTN["h"] + PAUSE_BTN["gap"]), PAUSE_BTN["w"], PAUSE_BTN["h"])

func _result_card() -> Rect2:
	return Rect2((Cfg.VIEW_W - RESULT_CARD["w"]) * 0.5, (Cfg.VIEW_H - RESULT_CARD["h"]) * 0.5,
		RESULT_CARD["w"], RESULT_CARD["h"])

func _result_btn(i: int) -> Rect2:
	var c = _result_card()
	var total: float = RESULT_BTN["w"] * 2 + RESULT_BTN["gap"]
	var x0 = c.position.x + (c.size.x - total) * 0.5
	return Rect2(x0 + i * (RESULT_BTN["w"] + RESULT_BTN["gap"]),
		c.position.y + c.size.y - RESULT_BTN["h"] - 22, RESULT_BTN["w"], RESULT_BTN["h"])

# ---------------- 输入 ----------------

func _gui_input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	if event is InputEventMouseMotion:
		nav_mode = false
		_update_hover()
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		nav_mode = false
		var p = event.position
		if mode == Mode.BRIEF:
			if Rect2(BRIEF_BTN["x"], BRIEF_BTN["y"], BRIEF_BTN["w"], BRIEF_BTN["h"]).has_point(p):
				action.emit("start")
		elif mode == Mode.PAUSE:
			for i in 4:
				if _pause_btn(i).has_point(p):
					_pause_action(i)
		elif mode == Mode.RESULT:
			for i in 2:
				if _result_btn(i).has_point(p):
					action.emit("restart" if i == 0 else "menu")
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.NONE or not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	# 方向与确认交给 _process_nav（键盘 / 手柄同一套 + 限速重复），这里只留快捷键。
	if mode == Mode.RESULT:
		if key == KEY_R:
			action.emit("restart")
		elif key == KEY_M:
			action.emit("menu")

func _pause_action(i: int) -> void:
	if i == 0:
		action.emit("resume")
	elif i == 1:
		action.emit("restart")
	elif i == 3:
		action.emit("settings")
	else:
		action.emit("menu")

# ---------------- 绘制 ----------------

func _draw() -> void:
	match mode:
		Mode.BRIEF:
			_draw_briefing()
		Mode.PAUSE:
			_draw_pause()
		Mode.RESULT:
			_draw_result()
	_nav_ring()

func _draw_pause() -> void:
	var e = appear
	draw_rect(Rect2(0, 0, Cfg.VIEW_W, Cfg.VIEW_H),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.84 * e), true, -1.0, true)
	UIDraw.dots(self, 0, 0, Cfg.VIEW_W, Cfg.VIEW_H, UIDraw.CREAM, 0.04 * e, 15)
	var c = _pause_card()
	var over = 1.0 - pow(1.0 - e, 3.0)
	var scale = 0.92 + over * 0.08
	# 原作 pause.js:119-122 的三段变换（translate → scale → translate）合成后
	# 等价于：以 (W/2, H/2) 为基准缩放 scale，并整体下移 (1-over)*30。
	var card_t = Vector2(Cfg.VIEW_W * 0.5, Cfg.VIEW_H * 0.5 + (1.0 - over) * 30.0) \
		- Vector2(Cfg.VIEW_W * 0.5, Cfg.VIEW_H * 0.5) * scale
	draw_set_transform(card_t, 0.0, Vector2(scale, scale))
	UIDraw.panel(self, c.position.x, c.position.y, c.size.x, c.size.y,
		{"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 3, "r": 5,
		"shadow": UIDraw.ORANGE, "shadowX": 8, "shadowY": 8})
	# 原作 pause.js:130-136：先 clip 到卡片圆角矩形（r=5），再填 58px 墨色刊头；
	# 不裁切会把卡片上方两个圆角糊成方角。网点层不重复裁切（圆角外溢出为亚像素级）。
	draw_colored_polygon(UIDraw.clip_polygon(
		UIDraw.rr_points(c.position.x, c.position.y, c.size.x, c.size.y, 5.0),
		Rect2(c.position.x, c.position.y, c.size.x, 58.0)), UIDraw.INK)
	UIDraw.dots(self, c.position.x, c.position.y, c.size.x, 58, UIDraw.CREAM, 0.06, 12)
	UIDraw.text(self, "PAUSED  /  TACTICAL BREAK", c.position.x + 22, c.position.y + 22,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CYAN})
	UIDraw.text(self, "BATTLE LOG  /  03", c.position.x + c.size.x - 22, c.position.y + 22,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.48), "align": "right"})
	UIDraw.text(self, "战场已冻结", c.position.x + 22, c.position.y + 43,
		{"size": 11, "weight": 700, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.7)})
	UIDraw.text(self, "已暂停", c.position.x + 24, c.position.y + 106,
		{"size": 38, "weight": 900, "family": "cn", "fill": UIDraw.INK,
		"shadow": UIDraw.ORANGE, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "PAUSE / 战术会议", c.position.x + 26, c.position.y + 134,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.42)})
	var info = _pause_info()
	if not info.is_empty():
		UIDraw.text(self, info, c.position.x + 24, c.position.y + 158,
			{"size": 11, "weight": 500, "family": "cn",
			"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.62)})
	draw_line(Vector2(c.position.x + 24, c.position.y + 174),
		Vector2(c.position.x + c.size.x - 24, c.position.y + 174),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16), 1.0, true)
	UIDraw.text(self, "选择下一步 / SELECT NEXT MOVE", c.position.x + 24, c.position.y + 187,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.42)})
	UIDraw.text(self, pad2(index + 1), c.position.x + c.size.x - 24, c.position.y + 244,
		{"size": 108, "weight": 900, "family": "impact", "fill": Color(0, 0, 0, 0),
		"stroke": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.065), "strokeWidth": 1.5, "align": "right"})
	UIDraw.star(self, c.position.x + c.size.x - 44, c.position.y + 204, 10, 4.5,
		UIDraw.YELLOW, 5, t * 0.3)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var items = [
		{"label": "继续游戏", "sub": "Esc / Enter", "primary": true, "en": "RESUME"},
		{"label": "重新开始", "sub": "R", "primary": false, "en": "RETRY"},
		{"label": "返回菜单", "sub": "M", "primary": false, "en": "MENU"},
	]
	for i in 3:
		_draw_pause_button(i, items[i])
	var gear := _pause_btn(3)
	UIDraw.panel(self, gear.position.x, gear.position.y, gear.size.x, gear.size.y,
		{"fill": UIDraw.YELLOW if index == 3 or hover == 3 else UIDraw.PAPER,
		"stroke": UIDraw.INK, "lw": 2, "r": 3, "shadow": UIDraw.CYAN, "shadowX": 3, "shadowY": 3})
	UIDraw.gear(self, gear.get_center().x, gear.get_center().y, UIDraw.INK)
	UIDraw.text(self, "设置", gear.get_center().x, gear.end.y + 14,
		{"size": 11, "fill": UIDraw.INK, "align": "center"})
	UIDraw.tag(self, "↑↓ 选择 · A / Enter 确认 · B / Esc 继续", Cfg.VIEW_W * 0.5, Cfg.VIEW_H - 25,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK,
		"fg": UIDraw.CREAM, "padX": 9, "h": 18, "align": "center", "stroke": UIDraw.CREAM, "lw": 1})

func _draw_pause_button(i: int, it: Dictionary) -> void:
	var r = _pause_btn(i)
	var hot = index == i or hover == i
	var primary: bool = it["primary"]
	var k = 1.012 if hot else 1.0
	var fill = UIDraw.INK if hot else (UIDraw.YELLOW if primary else UIDraw.CREAM)
	var fg = UIDraw.CREAM if hot else UIDraw.INK
	var accent = UIDraw.ORANGE if primary else (UIDraw.CYAN if i == 1 else UIDraw.PINK)
	draw_set_transform(r.position + r.size * 0.5, 0.0, Vector2(k, k))
	UIDraw.panel(self, -r.size.x * 0.5, -r.size.y * 0.5, r.size.x, r.size.y,
		{"fill": fill, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": accent if hot else (UIDraw.ORANGE if primary else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.18)),
		"shadowX": 4 if hot else 2, "shadowY": 4 if hot else 2})
	if hot:
		draw_rect(Rect2(-r.size.x * 0.5, -r.size.y * 0.5, 5, r.size.y), accent, true, -1.0, true)
	UIDraw.text(self, pad2(i + 1), -r.size.x * 0.5 + 18, 0,
		{"size": 11, "weight": 900, "family": "impact",
		"fill": UIDraw.YELLOW if hot else (UIDraw.INK if primary else accent), "alpha": 0.95})
	UIDraw.text(self, it["label"], -r.size.x * 0.5 + 42, 0,
		{"size": 17, "weight": 900, "family": "cn", "fill": fg})
	UIDraw.text(self, it["sub"], r.size.x * 0.5 - 42, 0,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55) if hot else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7), "align": "right"})
	UIDraw.text(self, it["en"], r.size.x * 0.5 - 12, 13,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": accent if hot else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.35), "align": "right"})
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _pause_info() -> String:
	if world == null:
		return ""
	# 文案对照原作 main.js:467-478 的 pauseInfo()（由 pause.js:155-160 画在卡片上）。
	if world.mode == "adventure":
		return "第 %d 关　·　剩余敌人 %d" % [world.match.level, world.alive_enemies()]
	if world.mode == "dig":
		return "剩余障碍 %d　·　剩余时间 %s" % [world.count_bricks(), _mmss(world.match.remaining)]
	return "%d : %d　·　第 %d 回合" % [int(world.match.scores["p1"]),
		int(world.match.scores["p2"]), world.match.round]

## hud.js:57-62 的 mmss：向下取整到秒，分钟不补零、秒补两位。
func _mmss(sec: float) -> String:
	sec = maxf(0.0, sec)
	return "%d:%02d" % [int(sec / 60.0), int(fmod(sec, 60.0))]

# ---------------- 结算 ----------------

func _make_confetti(sum: Dictionary) -> Array:
	var win = false
	if String(sum.get("mode", "")) == "versus":
		win = String(sum.get("winner", "")) in ["p1", "p2"]
	else:
		win = String(sum.get("winner", "")) == "p1"
	if not win:
		return []
	var out: Array = []
	var colors = [UIDraw.YELLOW, UIDraw.CYAN, UIDraw.PINK, UIDraw.GREEN, UIDraw.ORANGE, UIDraw.CREAM]
	for i in 48:
		out.append({
			"x": fmod(i * 149.5, Cfg.VIEW_W), "y": -fmod(i * 57.0, 430.0) - 20.0,
			"vy": 55.0 + (i % 7) * 24.0, "rot": (i % 11) * 0.42,
			"w": 4.0 + (i % 4) * 3.0, "h": 9.0 + (i % 3) * 5.0,
			"star": i % 7 == 0, "color": colors[i % colors.size()],
		})
	return out

func _draw_result() -> void:
	var s = summary
	var versus = String(s.get("mode", "")) == "versus"
	var player_win = String(s.get("winner", "")) == "p1"
	var any_win = String(s.get("winner", "")) in ["p1", "p2"]
	var draw = String(s.get("winner", "")) == "draw"
	var accent = UIDraw.PINK if draw else (UIDraw.YELLOW if (any_win if versus else player_win) else UIDraw.SKY)
	var stamp = "DRAW"
	if not draw:
		stamp = ("1P WIN" if String(s.get("winner", "")) == "p1" else "2P WIN") if versus else ("WIN" if player_win else "LOSE")

	draw_rect(Rect2(0, 0, Cfg.VIEW_W, Cfg.VIEW_H),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.84 * appear), true, -1.0, true)
	UIDraw.dots(self, 0, 0, Cfg.VIEW_W, Cfg.VIEW_H, UIDraw.CREAM, 0.04 * appear, 15)
	# 原作 result.js:125-140：每个彩带 save → translate → rotate → globalAlpha=.9*appear。
	for cf in confetti:
		var crot = float(cf["rot"])
		var calpha = 0.9 * appear
		draw_set_transform(Vector2(float(cf["x"]), float(cf["y"])), crot, Vector2.ONE)
		if bool(cf["star"]):
			# 原作在已 rotate(crot) 的坐标系里再调 U.star(..., rot=crot)，
			# 而 U.star 用 `rot || -PI/2`：0 时取 -PI/2，所以星形总旋转是 2*crot。
			_confetti_star(0.0, 0.0, float(cf["w"]) * 1.7, float(cf["w"]) * 0.7, cf["color"], 5,
				crot if crot != 0.0 else -PI * 0.5, calpha)
		else:
			draw_rect(Rect2(-float(cf["w"]) * 0.5, -float(cf["h"]) * 0.5, cf["w"], cf["h"]),
				Color(cf["color"].r, cf["color"].g, cf["color"].b, calpha), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var e = appear
	var over = 1.0 - pow(1.0 - e, 3.0)
	var scale = 0.88 + over * 0.12 + (sin(e * PI) * 0.02 if e < 1.0 else 0.0)
	var c = _result_card()
	# 原作 result.js:147-150 的三段变换（translate → scale → translate）合成后
	# 等价于：以 (W/2, H/2) 为基准缩放 scale，并整体上移 (1-over)*34。
	var card_t = Vector2(Cfg.VIEW_W * 0.5, Cfg.VIEW_H * 0.5) \
		+ Vector2(-Cfg.VIEW_W * 0.5, -Cfg.VIEW_H * 0.5 + (1.0 - over) * 34.0) * scale
	draw_set_transform(card_t, 0.0, Vector2(scale, scale))
	UIDraw.panel(self, c.position.x, c.position.y, c.size.x, c.size.y,
		{"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 3, "r": 5,
		"shadow": accent, "shadowX": 8, "shadowY": 8})
	# 原作 result.js:158-164：先 clip 到卡片圆角矩形（r=5），再填 64px 墨色刊头；
	# 不裁切会把卡片上方两个圆角糊成方角。网点层不重复裁切（圆角外溢出为亚像素级）。
	draw_colored_polygon(UIDraw.clip_polygon(
		UIDraw.rr_points(c.position.x, c.position.y, c.size.x, c.size.y, 5.0),
		Rect2(c.position.x, c.position.y, c.size.x, 64.0)), UIDraw.INK)
	UIDraw.dots(self, c.position.x, c.position.y, c.size.x, 64, UIDraw.CREAM, 0.055, 12)
	UIDraw.text(self, "MATCH REPORT  /  RESULT", c.position.x + 24, c.position.y + 22,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CYAN})
	UIDraw.text(self, "BOMBIT  /  BATTLE LOG", c.position.x + c.size.x - 24, c.position.y + 22,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.65), "align": "right"})
	UIDraw.text(self, "FINAL WHISTLE  /  " + String(s.get("title", "对局结束")),
		c.position.x + 24, c.position.y + 48, {"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55)})
	UIDraw.text(self, String(s.get("title", "对局结束")), c.position.x + 28, c.position.y + 112,
		{"size": 40, "weight": 900, "family": "cn", "fill": UIDraw.INK,
		"shadow": accent, "shadowX": 4, "shadowY": 4})
	var sub = String(s.get("subtitle", ""))
	if not sub.is_empty():
		UIDraw.text(self, sub, c.position.x + 30, c.position.y + 145,
			{"size": 11, "weight": 500, "family": "cn",
			"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.6)})
	# 原作 result.js:187-191：贴纸在卡片变换内 rotate(.04)，锚点是右对齐后的中心。
	# UIDraw.tag 的 rot 分支会把画布变换重置成绝对变换，吃不到卡片缩放，所以这里自行合成。
	_result_stamp_tag(stamp, c.position.x + c.size.x - 28, c.position.y + 102, card_t, scale, accent)
	draw_set_transform(card_t, 0.0, Vector2(scale, scale))
	UIDraw.star(self, c.position.x + c.size.x - 52, c.position.y + 144, 7, 3, accent, 5, t * 0.2)

	var sx = c.position.x + 28
	var sy = c.position.y + 184
	var sw = c.size.x - 56
	var sh = 148.0
	UIDraw.panel(self, sx, sy, sw, sh, {"fill": Color("FAF1E2"), "stroke": UIDraw.INK, "lw": 1.5,
		"r": 3, "shadow": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16), "shadowX": 3, "shadowY": 3})
	draw_rect(Rect2(sx, sy, sw, 25), UIDraw.INK, true, -1.0, true)
	UIDraw.text(self, "MATCH DATA  /  对局数据", sx + 12, sy + 13,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CREAM})
	UIDraw.text(self, "SNAPSHOT  " + pad2(int(s.get("round", 1))), sx + sw - 12, sy + 13,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CYAN, "align": "right"})
	_draw_result_stats(sx + 16, sy + 44, sw - 32)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_result_button(0, "返回联机大厅" if summary.get("network", false) else "再来一局", "Enter / R", UIDraw.YELLOW)
	_draw_result_button(1, "退出联机" if summary.get("network", false) else "返回菜单", "Esc / M", UIDraw.CREAM)
	UIDraw.tag(self, "← → 选择 · A / Enter 确认 · B / Esc 返回", Cfg.VIEW_W * 0.5, Cfg.VIEW_H - 25,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "fg": UIDraw.CREAM,
		"padX": 9, "h": 18, "align": "center", "stroke": UIDraw.CREAM, "lw": 1})

func _draw_result_button(i: int, label: String, sub: String, base: Color) -> void:
	var r = _result_btn(i)
	var hot = (nav_mode and index == i) or hover == i
	draw_set_transform(r.position + r.size * 0.5, 0.0, Vector2(1.018 if hot else 1.0, 1.018 if hot else 1.0))
	UIDraw.panel(self, -r.size.x * 0.5, -r.size.y * 0.5, r.size.x, r.size.y,
		{"fill": UIDraw.INK if hot else base, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": UIDraw.ORANGE if hot else (UIDraw.ORANGE if i == 0 else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.18)),
		"shadowX": 4 if hot else 2, "shadowY": 4 if hot else 2})
	if hot:
		draw_rect(Rect2(-r.size.x * 0.5, -r.size.y * 0.5, 5, r.size.y),
			UIDraw.YELLOW if i == 0 else UIDraw.CYAN, true, -1.0, true)
	UIDraw.play(self, -r.size.x * 0.5 + 22, 0, 10, UIDraw.YELLOW if hot else UIDraw.INK)
	UIDraw.text(self, label, -r.size.x * 0.5 + 40, -2, {"size": 15, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM if hot else UIDraw.INK})
	UIDraw.text(self, sub, -r.size.x * 0.5 + 40, 15, {"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.7) if hot else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.4)})
	UIDraw.keycap(self, "R" if i == 0 else "ESC", r.size.x * 0.5 - 44, -11, 30, 20,
		UIDraw.YELLOW if hot else UIDraw.INK, UIDraw.INK if hot else UIDraw.CREAM)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_result_stats(x: float, y: float, w: float) -> void:
	var s = summary
	var left: Array = []
	var right: Array = []
	var mode = String(s.get("mode", "adventure"))
	var players: Array = s.get("players", [])
	if mode == "dig":
		left.append(["用时", "%.1f 秒" % float(s.get("elapsed", 0.0))])
		left.append(["已清除障碍", "%d / %d" % [int(s.get("bricks_cleared", 0)), int(s.get("start_bricks", 0))]])
		left.append(["剩余障碍", str(int(s.get("bricks_left", 0)))])
		right.append(["爆炸次数", str(int(s.get("explosions", 0)))])
		right.append(["剩余生命", str(int(players[0]["lives"]) if players.size() > 0 else 0)])
		if players.size() > 0:
			right.append(["火力 / 炸弹", "%d格 / %d颗" % [int(players[0]["power"]), int(players[0]["max_bombs"])]])
	elif mode == "adventure":
		left.append(["完成关卡" if String(s.get("winner", "")) == "p1" else "到达关卡",
			"%d / %d关" % [int(s.get("level", 1)), int(s.get("total_levels", 10))]])
		left.append(["击败敌人", str(int(s.get("kills", 0)))])
		left.append(["用时", "%.1f秒" % float(s.get("elapsed", 0.0))])
		right.append(["爆炸次数", str(int(s.get("explosions", 0)))])
		right.append(["剩余生命", str(int(players[0]["lives"]) if players.size() > 0 else 0)])
		if players.size() > 0:
			right.append(["火力 / 炸弹", "%d格 / %d颗" % [int(players[0]["power"]), int(players[0]["max_bombs"])]])
	else:
		var scores: Dictionary = s.get("scores", {})
		left.append(["最终比分", "%d : %d" % [int(scores.get("p1", 0)), int(scores.get("p2", 0))]])
		left.append(["回合数", str(int(s.get("round", 1)))])
		left.append(["爆炸次数", str(int(s.get("explosions", 0)))])
		right.append(["1P 火力 / 炸弹", ("%d格 / %d颗" % [int(players[0]["power"]), int(players[0]["max_bombs"])]) if players.size() > 0 else "-"])
		right.append(["2P 火力 / 炸弹", ("%d格 / %d颗" % [int(players[1]["power"]), int(players[1]["max_bombs"])]) if players.size() > 1 else "-"])
	var col_w = w * 0.5
	_draw_stat_col(left, x, y, col_w - 12)
	draw_line(Vector2(x + col_w, y - 8), Vector2(x + col_w, y + 82),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.13), 1.0, true)
	_draw_stat_col(right, x + col_w + 12, y, col_w - 12)

func _draw_stat_col(rows: Array, x: float, y: float, w: float) -> void:
	for i in rows.size():
		var yy = y + i * 28.0
		if i > 0:
			draw_line(Vector2(x, yy - 12), Vector2(x + w, yy - 12),
				Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.09), 1.0, true)
		UIDraw.text(self, rows[i][0], x, yy, {"size": 11, "weight": 500, "family": "cn",
			"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.55)})
		UIDraw.text(self, rows[i][1], x + w, yy, {"size": 11.5, "weight": 900, "family": "mono",
			"fill": UIDraw.INK, "align": "right"})

## U.star + 原作 globalAlpha(.9*appear) 的等价物（result.js:131-133）：
## 彩带星形的填充与 1px 墨线描边都要跟着入场 alpha 一起淡入，不能只淡填充。
func _confetti_star(cx: float, cy: float, r1: float, r2: float, color: Color, points: int,
		rot: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a = rot + i * PI / points
		var rr = r2 if i % 2 == 1 else r1
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	draw_colored_polygon(pts, Color(color.r, color.g, color.b, color.a * alpha))
	pts.append(pts[0])
	draw_polyline(pts, Color(UIDraw.INK.r, UIDraw.INK.g, UIDraw.INK.b, alpha), 1.0, true)

## 原作 result.js:187-191 的赛果贴纸。U.tag 的 rot 分支等价于在当前矩阵上
## translate(left + w/2, y) → rotate(.04) → panel(-w/2, -h/2, w, h) → text(0, .5)，
## 其中 align:'right' 时 left = x - w。这里把卡片变换与该旋转合成成一次 draw_set_transform。
func _result_stamp_tag(label: String, x: float, y: float, card_t: Vector2, s: float, accent: Color) -> void:
	var size := 12
	var weight := 900
	var w := UIDraw.measure(label, size, weight, "impact") + 11.0 * 2.0
	var h := 26.0
	draw_set_transform(card_t + Vector2(x - w * 0.5, y) * s, 0.04, Vector2(s, s))
	UIDraw.panel(self, -w * 0.5, -h * 0.5, w, h, {"r": 3, "fill": accent, "stroke": UIDraw.INK,
		"lw": 1.5, "shadow": UIDraw.INK, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, label, 0, 0.5, {"size": size, "weight": weight, "family": "impact",
		"fill": UIDraw.INK, "align": "center"})

# ---------------- 关前档案 ----------------

func _draw_briefing() -> void:
	if world == null:
		return
	draw_rect(Rect2(0, 0, Cfg.VIEW_W, Cfg.VIEW_H),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.84), true, -1.0, true)
	UIDraw.dots(self, 0, 0, Cfg.VIEW_W, Cfg.VIEW_H, UIDraw.CREAM, 0.035, 16)
	var card = BRIEF_CARD
	UIDraw.panel(self, card["x"], card["y"], card["w"], card["h"],
		{"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 3, "r": 5,
		"shadow": UIDraw.ORANGE, "shadowX": 7, "shadowY": 7})
	# 原作 hud.js:451-458：先 clip 到卡片圆角矩形（r=5）再填刊头，方角不能盖掉圆角。
	# 网点层不重复裁切：step=13 的点阵在圆角外最多溢出约 0.2px，视觉等价。
	draw_colored_polygon(UIDraw.clip_polygon(
		UIDraw.rr_points(card["x"], card["y"], card["w"], card["h"], 5.0),
		Rect2(card["x"], card["y"], card["w"], BRIEF_HEADER)), UIDraw.INK)
	UIDraw.dots(self, card["x"], card["y"], card["w"], BRIEF_HEADER, UIDraw.CREAM, 0.055, 13)
	var th = Cfg.theme(world.theme)
	var level = world.match.level
	UIDraw.text(self, "STAGE %s / %d%s" % [pad2(level), Cfg.ADVENTURE_LEVELS,
		"  ·  FINAL" if level == Cfg.ADVENTURE_LEVELS else ""],
		card["x"] + 22, card["y"] + 18, {"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CYAN})
	UIDraw.text(self, String(th["name"]) + (" · BOSS 战" if world.boss_battle else ""),
		card["x"] + 22, card["y"] + 42, {"size": 26, "weight": 900, "family": "cn", "fill": UIDraw.CREAM})
	UIDraw.text(self, th["subtitle"], card["x"] + 22, card["y"] + 61,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.6)})
	var fresh = not world.briefing_fresh.is_empty()
	UIDraw.tag(self, "BOSS" if world.boss_battle else ("NEW ENEMY" if fresh else "REMINDER"),
		card["x"] + card["w"] - 22, card["y"] + 24, {"size": 11, "family": "mono",
		"fill": UIDraw.HOT if world.boss_battle else UIDraw.YELLOW, "fg": UIDraw.INK,
		"padX": 7, "h": 15, "align": "right", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.text(self, pad2(level), card["x"] + card["w"] - 22, card["y"] + 58,
		{"size": 50, "weight": 900, "family": "impact",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.0),
		"stroke": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.13), "strokeWidth": 1.2, "align": "right"})

	var ids: Array = world.briefing_fresh if fresh else world.briefing_types
	if ids.is_empty():
		ids = ["gugu"]
	var type_id = String(ids[0])
	var info: Dictionary = Cfg.ENEMY_TYPES.get(type_id, Cfg.ENEMY_TYPES["gugu"])
	var ax = card["x"] + 22
	var ay = card["y"] + 88
	var aw = 204.0
	var ah = 256.0
	UIDraw.panel(self, ax, ay, aw, ah, {"fill": th["sky"], "stroke": UIDraw.INK, "lw": 2, "r": 4,
		"shadow": UIDraw.INK, "shadowX": 4, "shadowY": 4})
	UIDraw.dots(self, ax, ay, aw, ah, UIDraw.CREAM, 0.075, 12)
	draw_circle(Vector2(ax + aw * 0.5, ay + 136), 82, UIDraw.CREAM, true, -1.0, true)
	# 原作 hud.js:493-500：arc(82) 描墨、arc(88) 描橙，都是 ctx.arc + stroke()（自适应细分 + 抗锯齿）。
	CanvasArt.arc_stroke(self, ax + aw * 0.5, ay + 136, 82.0, 0.0, TAU, UIDraw.INK, 2.0)
	CanvasArt.arc_stroke(self, ax + aw * 0.5, ay + 136, 88.0, 0.0, TAU, UIDraw.ORANGE, 2.0)
	# 原作 hud.js:485-503：网点 / 圆形舞台 / 底部黑条整块裁在 r=4 的档案卡内，
	# 黑条方角不能盖掉卡片下方圆角（圆舞台 r=88 全在卡内；网点溢出为亚像素级）。
	draw_colored_polygon(UIDraw.clip_polygon(
		UIDraw.rr_points(ax, ay, aw, ah, 4.0),
		Rect2(ax, ay + ah - 42, aw, 42)), UIDraw.INK)
	_draw_enemy_portrait(type_id, ax + aw * 0.5, ay + ah - 36, ax + aw * 0.5)
	UIDraw.tag(self, "初次登场" if fresh else "本关提醒", ax + 12, ay + 15, {"size": 11, "family": "cn",
		"fill": UIDraw.YELLOW, "fg": UIDraw.INK, "padX": 6, "h": 15, "align": "left",
		"stroke": UIDraw.INK, "lw": 1})
	UIDraw.text(self, info["name"], ax + 12, ay + ah - 15, {"size": 17.5, "weight": 900,
		"family": "cn", "fill": UIDraw.CREAM})
	UIDraw.text(self, "BOSS" if world.boss_battle else "NPC",
		ax + aw - 12, ay + ah - 16, {"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55), "align": "right"})

	var tx = ax + aw + 22
	var tw = card["x"] + card["w"] - 22 - tx
	UIDraw.text(self, "敌情档案 / THREAT PROFILE", tx, ay + 7, {"size": 11, "weight": 700,
		"family": "mono", "fill": UIDraw.INK, "alpha": 0.45})
	UIDraw.text(self, ("初次登场  " if fresh else "本关提醒  ") + String(info["name"]), tx, ay + 30,
		{"size": 21, "weight": 900, "family": "cn", "fill": UIDraw.INK,
		"shadow": UIDraw.YELLOW, "shadowX": 2, "shadowY": 2})
	UIDraw.wrap(self, String(info.get("story", "")), tx, ay + 54, tw, 12, 16,
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7), 3, 500, "cn")
	draw_line(Vector2(tx, ay + 102), Vector2(tx + tw, ay + 102),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16), 1.0, true)
	UIDraw.tag(self, "行动", tx, ay + 118, {"size": 11, "family": "cn", "fill": UIDraw.GREEN,
		"fg": UIDraw.INK, "padX": 6, "h": 15, "align": "left", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.wrap(self, String(info.get("mechanic", "")), tx + 42, ay + 118, tw - 42, 12, 16,
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.78), 2, 500, "cn")
	UIDraw.tag(self, "攻击", tx, ay + 172, {"size": 11, "family": "cn", "fill": UIDraw.ORANGE,
		"fg": UIDraw.INK, "padX": 6, "h": 15, "align": "left", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.wrap(self, String(info.get("damage", "")), tx + 42, ay + 172, tw - 42, 12, 16,
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.78), 2, 500, "cn")

	var hp = int(info["hp"])
	UIDraw.panel(self, tx, ay + 212, tw, 40, {"fill": UIDraw.INK, "stroke": UIDraw.INK, "lw": 1.5, "r": 2})
	UIDraw.text(self, "生命 / HP", tx + 12, ay + 224, {"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55)})
	UIDraw.text(self, str(hp), tx + tw - 12, ay + 224, {"size": 11, "weight": 900, "family": "mono",
		"fill": UIDraw.YELLOW, "align": "right"})
	var max_pips = mini(8, maxi(1, hp))
	for i in max_pips:
		draw_rect(Rect2(tx + 12 + i * ((tw - 24) / max_pips), ay + 235, (tw - 24) / max_pips - 3, 7),
			UIDraw.ORANGE, true, -1.0, true)

	var mx = card["x"] + 22
	var my = card["y"] + 358
	var mw = card["w"] - 44
	var mh = 84.0
	UIDraw.panel(self, mx, my, mw, mh, {"fill": UIDraw.INK, "stroke": UIDraw.INK, "lw": 1.5, "r": 3})
	draw_rect(Rect2(mx, my, mw, 3), UIDraw.ORANGE, true, -1.0, true)
	UIDraw.dots(self, mx, my, mw, mh, UIDraw.CREAM, 0.045, 12)
	var c1 = mx + 16
	var c2 = mx + 206
	var c3 = mx + 390
	draw_line(Vector2(c2 - 14, my + 12), Vector2(c2 - 14, my + mh - 12),
		Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.14), 1.0, true)
	draw_line(Vector2(c3 - 14, my + 12), Vector2(c3 - 14, my + mh - 12),
		Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.14), 1.0, true)
	UIDraw.text(self, "本关阵容 / SQUAD", c1, my + 16, {"size": 11, "weight": 700,
		"family": "mono", "fill": UIDraw.CYAN})
	var names: Array = []
	for id in world.briefing_types:
		names.append(Cfg.ENEMY_TYPES[id]["name"] if Cfg.ENEMY_TYPES.has(id) else String(id))
	UIDraw.wrap(self, " / ".join(names), c1, my + 35, 174, 11, 14, UIDraw.CREAM, 2, 700, "cn")
	UIDraw.text(self, "共 %d 只" % world.enemies.size(), c1, my + 70, {"size": 11,
		"weight": 700, "family": "mono", "fill": UIDraw.YELLOW})
	UIDraw.text(self, "场景机制 / STAGE RULE", c2, my + 16, {"size": 11, "weight": 700,
		"family": "mono", "fill": UIDraw.GREEN})
	UIDraw.text(self, th["subtitle"], c2, my + 34, {"size": 11, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM})
	UIDraw.wrap(self, th["mechanic"], c2, my + 52, 166, 11, 14,
		Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.6), 2, 500, "cn")
	UIDraw.text(self, "任务目标 / OBJECTIVE", c3, my + 16, {"size": 11, "weight": 700,
		"family": "mono", "fill": UIDraw.ORANGE})
	UIDraw.text(self, "击败全部敌人", c3, my + 38, {"size": 11, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM})
	UIDraw.text(self, "即可过关", c3, my + 56, {"size": 11, "weight": 500, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55)})

	var bx = float(BRIEF_BTN["x"])
	var by = float(BRIEF_BTN["y"])
	var bw = float(BRIEF_BTN["w"])
	var bh = float(BRIEF_BTN["h"])
	UIDraw.panel(self, bx, by, bw, bh, {"fill": UIDraw.ORANGE if hover == 0 else UIDraw.YELLOW,
		"stroke": UIDraw.INK, "lw": 2.5, "r": 4, "shadow": UIDraw.INK, "shadowX": 4, "shadowY": 4})
	UIDraw.play(self, bx + 28, by + bh * 0.5, 12, UIDraw.INK)
	UIDraw.text(self, "开始本关", bx + 49, by + bh * 0.5, {"size": 19, "weight": 900,
		"family": "cn", "fill": UIDraw.INK})
	UIDraw.keycap(self, "ENTER", bx + bw - 75, by + 14, 54, 19, UIDraw.INK, UIDraw.CREAM)
	UIDraw.text(self, "A / Enter / 空格 / 点击", card["x"] + card["w"] * 0.5, card["y"] + card["h"] - 20,
		{"size": 11, "weight": 500, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.65), "align": "center"})

## 关前档案的敌人立绘（原作 hud.js:512-517 调用 sprites.js 的 drawEnemy）。
##
## 原作写法是：把一个合成的敌人对象交给 drawEnemy，外面套一层变换：
##   ctx.translate(ax + aw/2, feetY - 16.5 * s); ctx.scale(s, s); drawEnemy(ctx, e, world.time, 1)
## drawEnemy 内部还会 translate(0, 14 + bob)（bob 是静止时的 idle 呼吸），并且：
##   · NPC 贴图按**固定 52×48**画在 (-w/2, -h + 2)（assets.js:31 的 enemySize，**非等比**）
##   · BOSS 贴图按 96 高、等比取宽，画在 (-w/2, -h + 8)
##   · e.alive 时先画一块落地阴影（局部 (0,13)，半径 32×9 / 15×5，alpha .22）
## 下面把这些变换合成回世界坐标逐项对齐——此前只做了「按高度等比缩放到 feet_y」，
## 于是 NPC 宽度差了最多 1.8px、BOSS 立绘整体高了约 10px，idle 呼吸与落地阴影也丢了。
func _draw_enemy_portrait(type_id: String, cx: float, feet_y: float, _panel_cx: float) -> void:
	var boss := type_id == "boss"
	var path = "res://assets/enemies/%s.png" % ("luludan" if boss else type_id)
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null or tex.get_height() <= 0:
		return
	var s := 1.85 if boss else 2.55
	# drawEnemy 里 e.moving 为假时的 idle bob（原作 sprites.js:1055）
	var bob := 0.0
	if world != null:
		bob = sin(world.time * 2.2) * 1.1
	# 敌人局部空间里的贴图尺寸与底边偏移
	var w0 := 96.0 if boss else 52.0
	var h0 := 96.0 if boss else 48.0
	var bottom_local := 8.0 if boss else 2.0
	# 合成：世界 y = (feetY - 16.5 * s) + s * (局部 y + 14 + bob)
	var origin_y := feet_y - 16.5 * s
	var bottom := origin_y + s * (bottom_local + 14.0 + bob)
	# NPC 宽度是固定的 52（非等比）；BOSS 按 96 高与贴图等比取宽。
	var w := (w0 * s) if not boss else (h0 * float(tex.get_width()) / float(tex.get_height()) * s)
	var h := h0 * s
	MapArt.ground_shadow(self, cx, origin_y + s * (13.0 + 14.0 + bob),
		32.0 * s if boss else 15.0 * s, 9.0 * s if boss else 5.0 * s, 0.22)
	draw_texture_rect(tex, Rect2(cx - w * 0.5, bottom - h, w, h), false)

func pad2(n: int) -> String:
	return ("0" + str(n)) if n < 10 else str(n)
