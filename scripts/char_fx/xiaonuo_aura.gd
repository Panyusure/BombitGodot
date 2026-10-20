extends "res://scripts/char_fx/CharAura.gd"

## 小诺 · 时光节拍（神光 / 心之力量，时间之王·诺亚的幼年形态）
##
## 为什么是表盘而不是法环：
## 小诺的力量是时间——「时光星域」直接把怪物和敌方炸弹冻住 3 秒，
## 最终进化是头戴王冠、手持权杖的「时间王者」。所以脚下不放常见的旋转符文环，
## 而放一块读得懂的表盘：12 根长刻 + 24 根短刻 + 一根匀速秒针，
## 秒针扫过的部分留一道冷光弧，一眼就知道「这一圈过去了多少」。
## 移动时表盘沿前进方向拉长 15%，像被脚步拖出的光痕；待机时秒针放慢，
## 指针压到 12 点会闪一记 sin 尖峰的金光——那是「整点」的彩蛋。
##
## 性格是节拍器：光尘 6 颗、相位严格等分（每 1/6 周期亮一颗），
## 上浮节奏均匀，不做随机迸发；残影只在真正跑起来（energy > 0.5）时出现，
## 且不缩放——时间里的自己大小不变，只是越来越淡、越来越滞后。
##
## 全部是矢量硬边 + 基类共享的 soft_dot / ring_tex（只生成一次）。
## 没有 SubViewport、没有模糊、没有后处理，paint 内不创建任何资源。

const CYAN := Color("8dd8ff")   # 神光主色
const ICE := Color("eafaff")    # 针尖 / 高光冷白
const GOLD := Color("ffe382")   # 王冠与 12 点的金光

const STEP := TAU / 12.0        # 整点间隔（30°）
const HAND_WALK := 3.4          # 行走时秒针角速度（rad/s，一圈约 1.8 秒）
const HAND_IDLE := 0.9          # 待机时缓慢走一圈（约 7 秒）
const RING_DECAY := 2.2         # 回溯环寿命衰减（约 0.45 秒）

var _hand := 0.0                # 秒针累积角：0 = 12 点，屏幕顺时针
var _cast_prev := 0.0
var _cast_ring := 0.0           # 回溯环剩余寿命：1 → 0

# ---------------------------------------------------------------- 覆写点

func motion() -> Dictionary:
	# 「节拍器」：步频快而稳、弹跳中等，摇摆 / 压扁都收着——轻快但不软。
	# idle_rate 比默认更快，待机呼吸也像钟摆一样规律，绝不能显得慵懒。
	return {
		"bounce": 3.6,
		"wobble": 2.4,
		"stride": 12.6,
		"sway": 1.4,
		"lean": 2.2,
		"breathe": 0.022,
		"idle_rate": 2.9,
		"squash": 0.14,
	}

func layer_specs() -> Array:
	return [
		{"id": "aura", "z": -3, "blend": "add"},      # 立绘之后：上浮光尘
		{"id": "sigil", "z": -2, "blend": "normal"},  # 立绘之后：脚下表盘（硬边）
		{"id": "front", "z": 1, "blend": "add"},      # 立绘之前：残影 / 回溯环
	]

func accent_color() -> Color:
	return CYAN

func on_configure() -> void:
	# 共享渐变纹理在这里预热一次：paint 里只读，绝不生成资源。
	soft_dot()
	ring_tex()

func advance(delta: float, speed: float = 1.0) -> void:
	# cast 的上升沿触发回溯环：不依赖 cast 的波形，蓄力或瞬发都吃得到。
	if cast > 0.05 and _cast_prev <= 0.05:
		_cast_ring = 1.0
	_cast_prev = cast
	# 秒针用累积角而不是 t × 角速度：moving 切换时速率变化，指针不会瞬移。
	# 施法时让它飞转，像把时间倒拨回去；倒下时停针——时间随之停住。
	if alive:
		var rate := HAND_WALK if moving else HAND_IDLE
		_hand = fposmod(_hand + delta * speed * (rate + 7.5 * _cast_ring), TAU)
	if _cast_ring > 0.0:
		_cast_ring = maxf(0.0, _cast_ring - delta * speed * RING_DECAY)
	super.advance(delta, speed)

func paint(ci: CanvasItem, layer: String) -> void:
	if display.y <= 0.0:
		return
	match layer:
		"aura":
			_paint_dust(ci)
		"sigil":
			_paint_dial(ci)
		"front":
			_paint_front(ci)

# ---------------------------------------------------------------- 表盘（sigil）

func _paint_dial(ci: CanvasItem) -> void:
	var lit := 0.68 + 0.32 * clampf(energy, 0.0, 1.0)
	# 盘面跟着待机呼吸极轻微地缩放：和 motion 的 idle_rate 同拍，但不抢秒针的节拍。
	var beat := 1.0 + 0.025 * sin(t * 2.9)
	var stretch := 1.15 if moving else 1.0
	var rx := clampf(display.x * 0.70, 17.0, 26.0) * stretch * beat
	var ry := rx * 0.36
	# 表盘属于地面：抵消掉大部分弹跳，人物腾空时盘子只轻轻抬一点。
	var gy := -bob * 0.78 + 1.2
	# 局部 -x 永远是背后（pivot 已经负责左右翻转），移动时把整块盘往身后让一点。
	var cx := (-display.x * 0.05) if moving else 0.0
	ci.draw_set_transform(Vector2(cx, gy), 0.0, Vector2.ONE)

	# 秒针扫过的轨迹：盘内的冷光弧，长度就是 _hand，像表圈上被点亮的弧。
	if _hand > 0.05:
		var arc := PackedVector2Array()
		var seg := clampi(int(_hand * 9.0), 4, 26)
		for j in seg + 1:
			var a_arc := -PI * 0.5 + _hand * float(j) / float(seg)
			arc.append(_dial_pt(a_arc, rx, ry, 0.72))
		ci.draw_polyline(arc, _tint(CYAN, 0.20 + 0.20 * lit), 1.2, true)

	MapArt.ellipse_stroke(ci, 0.0, 0.0, rx, ry, _tint(CYAN, 0.50 * lit), 1.5)

	# 24 根短刻 + 12 根长刻：两次 draw_multiline 画完，不逐根 draw_line。
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	for i in 24:
		var a_min := -PI * 0.5 + float(i) * (TAU / 24.0)
		minor.append(_dial_pt(a_min, rx, ry, 0.93))
		minor.append(_dial_pt(a_min, rx, ry, 1.0))
	for i in 12:
		var a_maj := -PI * 0.5 + float(i) * STEP
		major.append(_dial_pt(a_maj, rx, ry, 0.84))
		major.append(_dial_pt(a_maj, rx, ry, 1.0))
	ci.draw_multiline(minor, _tint(CYAN, 0.26 * lit), 1.0, true)
	ci.draw_multiline(major, _tint(CYAN, 0.62 * lit), 1.4, true)

	# 秒针当前压住的那一根刻度点亮成金色；near 在正对刻度时到 1，
	# 于是每转过 30° 都会「咔」地亮一下——节拍器的可见节拍。
	var k := int(floor(fposmod(_hand, TAU) / STEP)) % 12
	var a_act := -PI * 0.5 + float(k) * STEP
	# 到最近刻度的归一距离：压线时 1、两刻正中间时 0。
	var u := fposmod(_hand, STEP) / STEP
	var near := 1.0 - minf(u, 1.0 - u) * 2.0
	ci.draw_line(_dial_pt(a_act, rx, ry, 0.80), _dial_pt(a_act, rx, ry, 1.0),
		_tint(GOLD, 0.52 + 0.30 * near), 1.7 + 0.5 * near, true)
	var spark := _dial_pt(a_act, rx, ry, 1.03)
	star4(ci, spark.x, spark.y, 1.0 + 0.5 * lit + 0.9 * near, _tint(GOLD, 0.45 + 0.40 * near))

	# 秒针：0 = 12 点。_dial_pt 负责把屏幕角换算到被 pivot 镜像过的局部角，
	# 朝左站立时指针在屏幕上仍然是顺时针。
	var hs := -PI * 0.5 + _hand
	var tip := _dial_pt(hs, rx, ry, 0.70)
	var tail := _dial_pt(hs + PI, rx, ry, 0.16)
	ci.draw_line(Vector2.ZERO, tip, _tint(ICE, 0.20 * lit), 3.2, true)
	ci.draw_line(tail, tip, _tint(CYAN, 0.72), 1.0, true)
	ci.draw_line(Vector2.ZERO, tip, _tint(ICE, 0.88), 0.9, true)
	ci.draw_circle(Vector2.ZERO, 1.5, _tint(GOLD, 0.82), true, -1.0, true)

	# 待机彩蛋：秒针经过 12 点时闪一下（sin 尖峰，在 12 点处取 1）。
	# 只在静止时触发——移动中每 1.8 秒一次会太吵。
	var flash := pow(maxf(0.0, sin(_hand + PI * 0.5)), 32.0) if not moving else 0.0
	if flash > 0.03:
		MapArt.ellipse_stroke(ci, 0.0, 0.0, rx * 1.12, ry * 1.12, _tint(GOLD, 0.50 * flash), 1.3)
		var edge_l := _dial_pt(PI, rx, ry, 1.14)
		var edge_r := _dial_pt(0.0, rx, ry, 1.14)
		star4(ci, edge_l.x, edge_l.y, 1.4 + 2.8 * flash, _tint(GOLD, 0.85 * flash))
		star4(ci, edge_r.x, edge_r.y, 1.4 + 2.8 * flash, _tint(GOLD, 0.85 * flash))
	# 12 点的金色菱形常亮，闪的时候变大变亮。
	var mark := _dial_pt(-PI * 0.5, rx, ry, 1.16)
	var ms := 1.3 + 1.5 * flash
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(mark.x, mark.y - ms), Vector2(mark.x + ms * 0.6, mark.y),
		Vector2(mark.x, mark.y + ms), Vector2(mark.x - ms * 0.6, mark.y),
	]), _tint(GOLD, 0.55 + 0.45 * flash))

	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- 光尘（aura）

func _paint_dust(ci: CanvasItem) -> void:
	var e := clampf(energy, 0.0, 1.0)
	var lit := 0.55 + 0.45 * e
	var half := display.x * 0.5
	# 局部 -x 是背后：跑动时把光尘落点微微甩到身后，静止时回到身体两侧。
	var back := (-1.6) if moving else 0.0
	for i in 6:
		# 相位严格等分 1/6 周期：每颗都在固定节拍出现，不是随机粒子。
		var ph := fposmod(t * 0.32 + float(i) / 6.0, 1.0)
		var fade := sin(ph * PI)
		if fade <= 0.03:
			continue
		var side := -1.0 if (i % 2) == 0 else 1.0
		var x := side * half * 0.92 + sin(t * 1.05 + float(i) * 1.7) * 1.8 + back
		var y := -3.0 - ph * display.y * 0.78
		var gold := (i % 3) == 0
		var col := GOLD if gold else CYAN
		var sz := 1.15 + 0.3 * float(i % 3) + 0.35 * e
		# 柔光只是上浮尾迹（共享 soft_dot 拉长，不新建纹理）；核心仍是硬边十字星。
		ci.draw_texture_rect(soft_dot(), Rect2(x - 5.0, y - 7.0, 10.0, 17.0), false,
			_tint(col, 0.10 * fade * lit))
		star4(ci, x, y, sz, _tint(ICE, 0.78 * fade * lit))

# ---------------------------------------------------------------- 前景（front）

func _paint_front(ci: CanvasItem) -> void:
	_paint_afterimage(ci)
	_paint_rewind(ci)

## 时光残影：同一张立绘，只沿身后一个方向滞后，越远越淡，且不缩放。
## 两步 alpha 分别是 0.135 / 0.07，远低于 0.16 的上限。
func _paint_afterimage(ci: CanvasItem) -> void:
	if tex == null or not moving or energy <= 0.5:
		return
	# 局部 -x 永远是背后：pivot 已经把朝左的翻转算进变换里，这里再乘 facing 会转到身前。
	var base := Vector2(-display.x * anchor.x, -display.y * anchor.y)
	for i in 2:
		var lag := display.x * 0.12 * float(i + 1)
		var rect := Rect2(base + Vector2(-lag, 0.9 * float(i + 1)), display)
		ci.draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, 0.135 - 0.065 * float(i)))

## 施法瞬间的「回溯」环：从脚下向外炸开一圈，胸口再起一圈小环，
## 最后补一记光之十字。整套 0.45 秒内结束，不常驻。
## 残影有 0.16 的 alpha 上限；这里的峰值属于短时技能反馈，不在此列。
func _paint_rewind(ci: CanvasItem) -> void:
	if _cast_ring <= 0.0:
		return
	var life := clampf(_cast_ring, 0.0, 1.0)
	var grow := 1.0 - life
	var fade := life * life
	var r := 15.0 + grow * 46.0
	# ring_tex 是基类共享的预烘径向环，这里只做缩放 / 压扁，不生成任何东西。
	ci.draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.32))
	ci.draw_texture_rect(ring_tex(), Rect2(-r, -r, r * 2.0, r * 2.0), false, _tint(CYAN, 0.34 * fade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var r2 := r * 0.54
	# 身体中心按基类修正后的公式取（anchor.y 通常 0.78~0.97，直接用 0.5 会偏高）。
	var chest := Vector2(0.0, display.y * (0.5 - anchor.y))
	ci.draw_texture_rect(ring_tex(), Rect2(chest.x - r2, chest.y - r2, r2 * 2.0, r2 * 2.0),
		false, _tint(ICE, 0.20 * fade))
	# 光之十字：审判天芒的极简版，横冷白、竖金光。
	var arm := display.y * (0.14 + grow * 0.20)
	var ca := 0.58 * fade
	ci.draw_line(chest - Vector2(arm, 0.0), chest + Vector2(arm, 0.0), _tint(ICE, ca), 1.6, true)
	ci.draw_line(chest - Vector2(0.0, arm), chest + Vector2(0.0, arm), _tint(GOLD, ca * 0.85), 1.6, true)
	star4(ci, chest.x, chest.y, 2.4 + grow * 5.0, _tint(ICE, 0.85 * fade))

# ---------------------------------------------------------------- 小工具

## 统一改 alpha；顺手挡住浮点误差导致的非法颜色。
func _tint(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))

## 表盘专用：把「屏幕参数角」换算成当前镜像状态下的局部坐标。
## pivot.scale.x 在朝左时是 -1，秒针 / 高亮刻度若不补这一下，屏幕上会倒着转。
func _dial_pt(a: float, rx: float, ry: float, k: float = 1.0) -> Vector2:
	var f := -1.0 if facing < 0 else 1.0
	return Vector2(cos(a) * rx * k * f, sin(a) * ry * k)
