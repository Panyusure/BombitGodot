extends Node2D

## 通灵柔光 · MOTION ID 预览台
##
## 独立场景（soul_preview.tscn），用来审阅 / 截图这套美术动画：
##   SPACE 手动通灵   A 开关光环   S 慢放   R 重置
## 角色仍然是游戏里的 EntityView，因此看到的就是实机效果，不是另一套实现。
##
## 背景 / 版式延续 BombIt 的 Motion UI：奶油纸、墨线、硬阴影、半调网点、编辑部标签。
## 深色舞台是为了让“无 blur 的柔光”有足够的对比；柔光本身全部来自 SoulGlow。

const CREAM := Color("F5EBD8")
const INK := Color("141019")
const CYAN := Color("9BEFFF")
const PINK := Color("FF8EC8")
const GOLD := Color("FFD23F")
const MUTED := Color("9A8C9F")
const PANEL := Color("1A1230")

var actor: Actor = null
var view: EntityView = null

var _ui: Node2D = null
var _time := 0.0
var _auto_clock := 3.0
var _auto := true
var _slow := false

func _ready() -> void:
	actor = Actor.new()
	actor.id = "p1"
	actor.asset_id = "weilai"
	actor.name = "未来"
	actor.char_name = "未来"
	actor.color = Color("FF5E9E")
	actor.x = 455.0
	actor.y = 542.0
	actor.px = actor.x
	actor.py = actor.y
	actor.facing = 1
	actor.facing_dir = "down"
	actor.alive = true
	actor.soul_evolved = true
	actor.soul_bombs = 6
	actor.lives = 3

	view = EntityView.new()
	view.show_tag = false
	view.scale = Vector2(1.95, 1.95)
	add_child(view)
	view.setup(actor, UIDraw.font("cn", 900))
	# 展示版：深色舞台允许更亮的柔光
	if view._soul_glow != null:
		view._soul_glow.energy = 1.0
		view._soul_glow.ink_strength = 0.27
		view._soul_glow.bloom_strength = 1.0
	view.update_view(0.0, 0.0, 0.0)

	_ui = Node2D.new()
	_ui.z_index = 1000
	add_child(_ui)
	_ui.draw.connect(_draw_ui.bind(_ui))
	_ui.queue_redraw()
	queue_redraw()
	trigger_awaken()
	_auto_clock = 4.6

func _process(delta: float) -> void:
	var dt := delta * (0.22 if _slow else 1.0)
	_time += dt
	if actor.soul_awaken_time > 0.0:
		actor.soul_awaken_time = maxf(0.0, actor.soul_awaken_time - dt)
	_auto_clock -= dt
	if _auto and _auto_clock <= 0.0:
		trigger_awaken()
		_auto_clock = 7.0
	view.update_view(0.0, _time, dt)
	_ui.queue_redraw()

func trigger_awaken() -> void:
	actor.soul_awaken_time = 1.6
	_auto_clock = 7.0

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			trigger_awaken()
		KEY_A:
			view.soul_enabled = not view.soul_enabled
		KEY_S:
			_slow = not _slow
		KEY_R:
			_time = 0.0
			trigger_awaken()
		KEY_ESCAPE:
			get_tree().quit()

# ============================================================
# 底层：奶油纸 + 墨色舞台（画在角色 / 柔光之后）
# ============================================================

func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 696), CREAM)

	# 舞台硬阴影：Motion UI 的招牌“贴纸”厚度
	UIDraw.fill_rr(self, 33, 29, 672, 656, 4, Color(0.36, 0.95, 1.0, 0.95))
	# 深色渐变舞台
	var panel := UIDraw.rr_points(24, 20, 672, 656, 4)
	CanvasArt.fill_linear_gradient(self, panel, Vector2(0, 20), Vector2(0, 676), [
		[0.0, Color("#241A3A")],
		[0.46, Color("#120F20")],
		[1.0, Color("#08070D")],
	])
	# 半调网点：只铺在舞台里，很淡
	UIDraw.dots(self, 24, 20, 672, 656, Color("#8FEFFF"), 0.030, 14)
	# 舞台内圈
	UIDraw.stroke_rr(self, 31, 27, 658, 642, 2, Color(1, 1, 1, 0.07), 1.0)
	# 角落十字规矩线
	for cp in [Vector2(14, 14), Vector2(706, 14), Vector2(14, 682), Vector2(706, 682)]:
		draw_line(cp - Vector2(5, 0), cp + Vector2(5, 0), INK, 1.0)
		draw_line(cp - Vector2(0, 5), cp + Vector2(0, 5), INK, 1.0)

# ============================================================
# 上层：版式 / 标签 / 技术注脚
# ============================================================

func _draw_ui(ci: CanvasItem) -> void:
	# 舞台描边压在最上，保证角色不会溢出圆角
	UIDraw.stroke_rr(ci, 24, 20, 672, 656, 4, INK, 3.0)
	UIDraw.stroke_rr(ci, 31, 27, 658, 642, 2, Color(1, 1, 1, 0.07), 1.0)

	_ui_header(ci)
	_ui_title(ci)
	_ui_notes(ci)
	_ui_sdf_card(ci)
	_ui_palette(ci)
	_ui_timeline(ci)
	_ui_controls(ci)
	_ui_footer(ci)

func _ui_header(ci: CanvasItem) -> void:
	UIDraw.tag(ci, "MOTION ID / 007", 44, 46, {
		"size": 8, "fill": CYAN, "fg": INK, "padX": 8, "h": 16, "align": "left",
	})
	UIDraw.text(ci, "BOMBIT / SOUL BLOOM", 676, 46, {
		"size": 9, "family": "mono", "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.58), "align": "right",
	})
	ci.draw_line(Vector2(44, 62), Vector2(676, 62), Color(CREAM.r, CREAM.g, CREAM.b, 0.14), 1.0)
	for i in 8:
		ci.draw_line(Vector2(44 + i * 18, 62), Vector2(44 + i * 18, 66),
			Color(CREAM.r, CREAM.g, CREAM.b, 0.20), 1.0)

func _ui_title(ci: CanvasItem) -> void:
	UIDraw.text(ci, "通灵柔光", 44, 96, {
		"size": 44, "weight": 900, "fill": CREAM,
		"shadow": PINK, "shadowX": 3, "shadowY": 3,
	})
	UIDraw.text(ci, "SOUL BLOOM / 无 blur 图元", 46, 137, {
		"size": 9, "family": "mono", "fill": CYAN,
	})
	UIDraw.text(ci, "未来 · 通灵觉醒 / 从轮廓距离场里长出来的柔光", 46, 156, {
		"size": 10, "weight": 500, "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.60),
	})
	# 标题右侧的小贴纸：把“技术”变成版式的一部分
	UIDraw.tag(ci, "4 SDF TAPS", 244, 137, {
		"size": 7, "fill": PINK, "fg": INK, "padX": 6, "h": 13, "align": "left",
	})
	UIDraw.tag(ci, "0 BLUR", 338, 137, {
		"size": 7, "fill": GOLD, "fg": INK, "padX": 6, "h": 13, "align": "left",
	})

func _ui_notes(ci: CanvasItem) -> void:
	var notes := [
		["01", "CONTOUR", "SDF 轮廓 / 4 次采样", "主光 3 次（含色散）+ 墨晕 1 次", CYAN],
		["02", "FALLOFF", "解析指数衰减", "没有高斯核，也没有后处理", PINK],
		["03", "CHROMA", "左右偏移 → 灵视重影", "青 / 粉两枚轮廓在呼吸", CYAN],
		["04", "INK", "紫墨晕压住浅色底", "柔光在奶油纸 / 地砖上也立得住", GOLD],
	]
	var y := 236.0
	for note in notes:
		var col: Color = note[4]
		ci.draw_circle(Vector2(50, y - 3), 2.0, col)
		UIDraw.text(ci, String(note[0]), 58, y, {
			"size": 8, "family": "mono", "fill": col,
		})
		UIDraw.text(ci, String(note[1]), 82, y, {
			"size": 8, "family": "mono", "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.82),
		})
		UIDraw.text(ci, String(note[2]), 48, y + 20, {
			"size": 10, "weight": 500, "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.90),
		})
		UIDraw.text(ci, String(note[3]), 48, y + 35, {
			"size": 8, "weight": 500, "fill": Color(MUTED.r, MUTED.g, MUTED.b, 0.95),
		})
		y += 58.0

	# 左侧竖线 + 刻度
	ci.draw_line(Vector2(232, 228), Vector2(232, 438), Color(CREAM.r, CREAM.g, CREAM.b, 0.18), 1.0)
	for i in 12:
		var yy := 232.0 + i * 18.0
		ci.draw_line(Vector2(228, yy), Vector2(232, yy), Color(CREAM.r, CREAM.g, CREAM.b, 0.30), 1.0)

func _ui_sdf_card(ci: CanvasItem) -> void:
	var x := 44.0
	var y := 468.0
	var w := 164.0
	var h := 122.0
	UIDraw.panel(ci, x, y, w, h, {
		"fill": Color("#0B0912"), "stroke": Color(CYAN.r, CYAN.g, CYAN.b, 0.72), "lw": 1.5,
		"r": 3, "shadow": Color(0, 0, 0, 0.45), "shadowX": 4, "shadowY": 4,
	})
	UIDraw.text(ci, "SDF / CONTOUR", x + 8, y + 13, {
		"size": 7, "family": "mono", "fill": CYAN,
	})
	var info: Dictionary = {}
	if view._soul_glow != null:
		info = view._soul_glow.sdf_info()
	if info.has("preview"):
		var tex: Texture2D = info["preview"]
		ci.draw_texture_rect(tex, Rect2(x + 8, y + 23, w - 16, 66), false,
			Color(0.52, 0.96, 1.0, 0.92))
	# 缩略图上的瞄准线
	ci.draw_line(Vector2(x + 8, y + 56), Vector2(x + w - 8, y + 56), Color(CYAN.r, CYAN.g, CYAN.b, 0.18), 1.0)
	ci.draw_line(Vector2(x + w * 0.5, y + 23), Vector2(x + w * 0.5, y + 89), Color(CYAN.r, CYAN.g, CYAN.b, 0.18), 1.0)
	var bake := float(info.get("bake_ms", 0.0))
	var dims := "%d×%d" % [int(info.get("w", 0)), int(info.get("h", 0))]
	UIDraw.text(ci, "0.5 = EDGE · %s" % dims, x + 8, y + 101, {
		"size": 6, "family": "mono", "fill": Color(MUTED.r, MUTED.g, MUTED.b, 0.95),
	})
	var bake_txt := "BAKED / 0 ms" if bool(info.get("baked", false)) else "BAKE %.1f ms" % bake
	UIDraw.text(ci, bake_txt, x + 8, y + 113, {
		"size": 6, "family": "mono", "fill": Color(CYAN.r, CYAN.g, CYAN.b, 0.75),
	})
	UIDraw.text(ci, "4 TAPS", x + w - 8, y + 113, {
		"size": 6, "family": "mono", "fill": Color(PINK.r, PINK.g, PINK.b, 0.85), "align": "right",
	})

func _ui_palette(ci: CanvasItem) -> void:
	UIDraw.text(ci, "PALETTE / 灵光", 44, 610, {
		"size": 7, "family": "mono", "fill": Color(MUTED.r, MUTED.g, MUTED.b, 0.95),
	})
	var cols := [CYAN, PINK, GOLD, Color("#3A2B52")]
	var names := ["灵青", "魂粉", "星金", "墨"]
	for i in 4:
		var x := 44.0 + i * 44.0
		ci.draw_rect(Rect2(x, 620, 18, 18), cols[i])
		ci.draw_rect(Rect2(x, 620, 18, 18), Color(1, 1, 1, 0.25), false, 1.0)
		UIDraw.text(ci, names[i], x + 22, 629, {
			"size": 8, "weight": 500, "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.72),
		})

func _ui_timeline(ci: CanvasItem) -> void:
	var x := 252.0
	var y := 610.0
	var w := 246.0
	var remain: float = actor.soul_awaken_time
	var p := clampf(1.0 - remain / 1.6, 0.0, 1.0)
	UIDraw.text(ci, "AWAKEN / 通灵", x, y, {
		"size": 7, "family": "mono", "fill": Color(CYAN.r, CYAN.g, CYAN.b, 0.85),
	})
	UIDraw.text(ci, "%.2fs" % remain, x + w, y, {
		"size": 7, "family": "mono", "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.65), "align": "right",
	})
	ci.draw_rect(Rect2(x, y + 10, w, 5), Color(1, 1, 1, 0.10))
	var fillc := CYAN.lerp(PINK, p)
	ci.draw_rect(Rect2(x, y + 10, w * p, 5), fillc)
	ci.draw_rect(Rect2(x, y + 10, w, 5), Color(0, 0, 0, 0.35), false, 1.0)
	for i in 9:
		var xx := x + i * w / 8.0
		ci.draw_line(Vector2(xx, y + 18), Vector2(xx, y + 22), Color(CREAM.r, CREAM.g, CREAM.b, 0.22), 1.0)
	UIDraw.text(ci, "0.0", x, y + 30, {
		"size": 6, "family": "mono", "fill": Color(MUTED.r, MUTED.g, MUTED.b, 0.9),
	})
	UIDraw.text(ci, "1.6", x + w, y + 30, {
		"size": 6, "family": "mono", "fill": Color(MUTED.r, MUTED.g, MUTED.b, 0.9), "align": "right",
	})

func _ui_controls(ci: CanvasItem) -> void:
	var y := 653.0
	var x := 252.0
	_key(ci, "SPACE", x, y)
	_label(ci, "通灵", x + 44, y)
	_key(ci, "A", x + 84, y)
	_label(ci, "光环", x + 102, y)
	_key(ci, "S", x + 140, y)
	_label(ci, "慢放", x + 158, y)
	_key(ci, "R", x + 196, y)
	_label(ci, "重置", x + 214, y)
	if not view.soul_enabled:
		UIDraw.tag(ci, "AURA OFF", x + 252, y, {
			"size": 6, "fill": PINK, "fg": INK, "padX": 5, "h": 11, "align": "left",
		})
	if _slow:
		UIDraw.tag(ci, "SLOW 0.22×", x + 252, y + 14, {
			"size": 6, "fill": GOLD, "fg": INK, "padX": 5, "h": 11, "align": "left",
		})

func _key(ci: CanvasItem, s: String, x: float, y: float) -> void:
	var w := maxf(18.0, UIDraw.measure(s, 6, 700, "mono") + 10.0)
	UIDraw.panel(ci, x, y - 7, w, 14, {
		"fill": CREAM, "stroke": INK, "lw": 1.0, "r": 2,
	})
	UIDraw.text(ci, s, x + w * 0.5, y, {
		"size": 6, "family": "mono", "fill": INK, "align": "center",
	})

func _label(ci: CanvasItem, s: String, x: float, y: float) -> void:
	UIDraw.text(ci, s, x, y, {
		"size": 8, "weight": 500, "fill": Color(CREAM.r, CREAM.g, CREAM.b, 0.68),
	})

func _ui_footer(ci: CanvasItem) -> void:
	# 右侧条码 + 年份
	var bx := 618.0
	for i in 26:
		var w := 1.0 if i % 3 else 2.0
		ci.draw_rect(Rect2(bx + i * 2.4, 620, w, 30), Color(CREAM.r, CREAM.g, CREAM.b, 0.55))
	UIDraw.text(ci, "2026 / MOTION UT", 676, 658, {
		"size": 6, "family": "mono", "fill": Color(MUTED.r, MUTED.g, MUTED.b, 0.95), "align": "right",
	})
	UIDraw.text(ci, "GODOT 4.7 / GL COMPATIBILITY", 676, 668, {
		"size": 6, "family": "mono", "fill": Color(CYAN.r, CYAN.g, CYAN.b, 0.60), "align": "right",
	})
