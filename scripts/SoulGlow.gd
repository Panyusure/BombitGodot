class_name SoulGlow
extends Node2D

## 通灵柔光 · 可复用节点
##
## 挂在 EntityView 的 pivot 下（跟随弹跳 / 倾斜 / 翻转 / 通灵膨胀），
## 用四层 CanvasItem 完成全部表现：
##   -4 ink   : SDF 墨晕（normal blend，浅色地面的对比）
##   -3 aura  : SDF 主光（additive，轮廓光 + 体积光 + 灵丝 + 色散）
##   -2 sigil : 法环 / 灵星（矢量硬边，和柔光形成“墨线 vs 灵光”的对照）
##   +1 front : 上升灵屑 / 呼吸环 / 灵丝
##   +2 burst : 1.6s 通灵觉醒爆发
##
## 没有任何 blur 图元、后处理、SubViewport。全部柔光来自 SoulSdf 的距离场
## 与解析衰减；法环 / 灵星 / 灵屑是矢量与径向渐变纹理（生成一次）。

class PaintLayer:
	extends Node2D
	var glow: SoulGlow
	var kind := ""

	func _draw() -> void:
		if glow != null:
			glow.paint_layer(self, kind)

var energy := 1.0
var ink_strength := 0.27
var bloom_strength := 1.0

var _time := 0.0
var _awaken_t := 0.0
var _seed := 0.0
var _char_tex: Texture2D = null
var _display := Vector2.ZERO
var _anchor := Vector2(0.5, 1.0)
var _sdf_info: Dictionary = {}
var _configured := false

var _bloom_layer: PaintLayer = null
var _burst_back_layer: PaintLayer = null
var _ink_layer: PaintLayer = null
var _aura_layer: PaintLayer = null
var _sigil_layer: PaintLayer = null
var _front_layer: PaintLayer = null
var _burst_front_layer: PaintLayer = null
var _aura_mat: ShaderMaterial = null
var _ink_mat: ShaderMaterial = null

var _quad_pts := PackedVector2Array()
var _quad_uvs := PackedVector2Array()
var _quad_cols := PackedColorArray()
var _char_min := Vector2.ZERO
var _body_center := Vector2.ZERO

# ---- 共享的“无 blur”光斑 / 光环 / 光柱纹理（只生成一次） ----
static var _soft_dot_tex: Texture2D = null
static var _ring_tex: Texture2D = null
static var _pillar_tex: Texture2D = null
static var _white_tex: Texture2D = null

func _ready() -> void:
	_seed = float(absi(get_instance_id()) % 997) * 0.013
	_ensure_layers()

func _ensure_layers() -> void:
	if _aura_layer != null:
		return
	_bloom_layer = _make_layer("bloom", -6)
	# 觉醒的大闪白 / 光柱 / 软环放在角色背后：人物始终留在最上层，不会被洗掉。
	_burst_back_layer = _make_layer("burst_back", -5)
	_ink_layer = _make_layer("ink", -4)
	_aura_layer = _make_layer("aura", -3)
	_sigil_layer = _make_layer("sigil", -2)
	_front_layer = _make_layer("front", 1)
	_burst_front_layer = _make_layer("burst_front", 2)

	var aura_shader: Shader = load("res://shaders/soul_aura.gdshader")
	var ink_shader: Shader = load("res://shaders/soul_ink.gdshader")
	if aura_shader != null:
		_aura_mat = ShaderMaterial.new()
		_aura_mat.shader = aura_shader
		_aura_layer.material = _aura_mat
	if ink_shader != null:
		_ink_mat = ShaderMaterial.new()
		_ink_mat.shader = ink_shader
		_ink_layer.material = _ink_mat

	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_bloom_layer.material = add_mat
	_burst_back_layer.material = add_mat
	_sigil_layer.material = add_mat
	_front_layer.material = add_mat
	_burst_front_layer.material = add_mat

func _make_layer(kind: String, layer_z: int) -> PaintLayer:
	var layer := PaintLayer.new()
	layer.glow = self
	layer.kind = kind
	layer.z_index = layer_z
	add_child(layer)
	return layer

## 由 EntityView 在贴图 / 尺寸 / 锚点变化时调用。SDF 会按纹理缓存，只烘一次。
func configure(tex: Texture2D, display: Vector2, anchor: Vector2) -> void:
	_ensure_layers()
	if tex == null or display.x <= 0.0 or display.y <= 0.0:
		clear()
		return
	if _configured and tex == _char_tex and display.is_equal_approx(_display) \
			and anchor.is_equal_approx(_anchor):
		return
	_char_tex = tex
	_display = display
	_anchor = anchor
	_sdf_info = SoulSdf.for_texture(tex)
	if _sdf_info.is_empty():
		clear()
		return

	_char_min = Vector2(-display.x * anchor.x, -display.y * anchor.y)
	var pad := maxf(44.0, display.y * 0.46)
	var quad_min := _char_min - Vector2(pad, pad)
	var quad_size := display + Vector2(pad, pad) * 2.0
	_body_center = _char_min + Vector2(display.x * 0.5, display.y * 0.56)

	_quad_pts = PackedVector2Array([
		quad_min,
		quad_min + Vector2(quad_size.x, 0.0),
		quad_min + quad_size,
		quad_min + Vector2(0.0, quad_size.y),
	])
	_quad_uvs = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	])
	_quad_cols = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 1),
	])

	var quad_rect := Vector4(quad_min.x, quad_min.y, quad_size.x, quad_size.y)
	# SDF 比立绘大一圈（四周各 PAD_SRC 原图像素），光才能在贴图边缘之外自然衰减；
	# 所以给 shader 的映射矩形是「SDF 覆盖的局部矩形」，不是立绘矩形。
	var pad_src := float(_sdf_info.get("pad_src", 0.0))
	var sdf_pad := Vector2(display.x * pad_src / float(_sdf_info["src_w"]),
		display.y * pad_src / float(_sdf_info["src_h"]))
	var sdf_min := _char_min - sdf_pad
	var sdf_size := display + sdf_pad * 2.0
	var sdf_rect := Vector4(sdf_min.x, sdf_min.y, sdf_size.x, sdf_size.y)
	if _aura_mat != null:
		_aura_mat.set_shader_parameter("sdf_tex", _sdf_info["tex"])
		_aura_mat.set_shader_parameter("quad_rect", quad_rect)
		_aura_mat.set_shader_parameter("sdf_rect", sdf_rect)
		_aura_mat.set_shader_parameter("body_center", _body_center)
		_aura_mat.set_shader_parameter("body_width", display.x)
		_aura_mat.set_shader_parameter("sdf_range", SoulSdf.RANGE_SRC)
		_aura_mat.set_shader_parameter("seed", _seed)
		_aura_mat.set_shader_parameter("glow", energy)
	if _ink_mat != null:
		_ink_mat.set_shader_parameter("sdf_tex", _sdf_info["tex"])
		_ink_mat.set_shader_parameter("quad_rect", quad_rect)
		_ink_mat.set_shader_parameter("sdf_rect", sdf_rect)
		_ink_mat.set_shader_parameter("sdf_range", SoulSdf.RANGE_SRC)
		_ink_mat.set_shader_parameter("seed", _seed)
		_ink_mat.set_shader_parameter("strength", ink_strength)
	_configured = true
	visible = true
	_redraw_all()

func clear() -> void:
	_configured = false
	_char_tex = null
	_sdf_info = {}
	visible = false
	_redraw_all()

func sdf_info() -> Dictionary:
	return _sdf_info

## 每帧：时间 / 觉醒进度 / 各层重绘。
func update_soul(time_now: float, awaken_left: float, _delta: float) -> void:
	_time = time_now
	_awaken_t = maxf(0.0, awaken_left)
	var progress := clampf(1.0 - _awaken_t / 1.6, 0.0, 1.0)
	var burst := 0.0
	if _awaken_t > 0.0:
		burst = pow(1.0 - progress, 2.4)
	if _aura_mat != null:
		_aura_mat.set_shader_parameter("time", _time)
		_aura_mat.set_shader_parameter("awaken", burst)
		_aura_mat.set_shader_parameter("glow", energy)
	if _ink_mat != null:
		_ink_mat.set_shader_parameter("time", _time)
		_ink_mat.set_shader_parameter("strength", ink_strength)
	_redraw_all()

func _redraw_all() -> void:
	if _bloom_layer != null:
		_bloom_layer.queue_redraw()
	if _burst_back_layer != null:
		_burst_back_layer.queue_redraw()
	if _ink_layer != null:
		_ink_layer.queue_redraw()
	if _aura_layer != null:
		_aura_layer.queue_redraw()
	if _sigil_layer != null:
		_sigil_layer.queue_redraw()
	if _front_layer != null:
		_front_layer.queue_redraw()
	if _burst_front_layer != null:
		_burst_front_layer.queue_redraw()

# ============================================================
# 绘制分发
# ============================================================

func paint_layer(ci: CanvasItem, kind: String) -> void:
	if not _configured:
		return
	match kind:
		"ink", "aura":
			if _quad_pts.size() == 4:
				ci.draw_polygon(_quad_pts, _quad_cols, _quad_uvs, _white())
		"bloom":
			_paint_bloom(ci)
		"sigil":
			_paint_sigil(ci)
		"front":
			_paint_front(ci)
		"burst_back":
			_paint_burst_back(ci)
		"burst_front":
			_paint_burst_front(ci)

func _white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

## 大范围柔光：径向渐变纹理，不是 SDF 的远场。
## SDF 负责“贴着轮廓的光”和“墨晕”，径向渐变负责“把角色包起来的环境光”。
## 两者的矩形边界都不可见：SDF 在范围外归零，渐变在边缘 alpha=0。
func _paint_bloom(ci: CanvasItem) -> void:
	var t := _time
	var pulse := 0.94 + 0.06 * sin(t * 1.6 + _seed)
	var burst := _burst_amount()
	var center := _body_center + Vector2(0.0, _display.y * 0.03)
	var boost := 1.0 + burst * 0.35
	var w := _display.x * 2.55 * pulse * boost
	var h := _display.y * 1.95 * pulse * boost
	ci.draw_texture_rect(_soft_dot(), Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h),
		false, Color(0.34, 0.88, 1.0, (0.105 + burst * 0.08) * bloom_strength))
	var w2 := _display.x * 1.75 * pulse * boost
	var h2 := _display.y * 1.45 * pulse * boost
	ci.draw_texture_rect(_soft_dot(), Rect2(center.x - w2 * 0.5, center.y - h2 * 0.5 + _display.y * 0.06,
		w2, h2), false, Color(1.0, 0.55, 0.88, (0.085 + burst * 0.08) * bloom_strength))
	# 胸口最亮的一小团，给角色一个“发光核心”
	var w3 := _display.x * 0.78 * pulse * boost
	var h3 := _display.y * 0.72 * pulse * boost
	var chest := Vector2(0.0, -_display.y * 0.50)
	ci.draw_texture_rect(_soft_dot(), Rect2(chest.x - w3 * 0.5, chest.y - h3 * 0.5, w3, h3),
		false, Color(0.72, 0.98, 1.0, (0.075 + burst * 0.10) * bloom_strength))

# ============================================================
# 法环 / 灵星 / 灵屑
# ============================================================

func _paint_sigil(ci: CanvasItem) -> void:
	var t := _time
	var burst := _burst_amount()
	var breathe := 1.0 + 0.08 * sin(t * 1.7) + burst * 0.45

	# 地面光池：径向渐变纹理（生成一次，不是 blur）
	ci.draw_texture_rect(_soft_dot(), Rect2(-52.0 * breathe, -15.0, 104.0 * breathe, 32.0),
		false, Color(0.38, 0.95, 1.0, 0.11 + burst * 0.20))

	# 法师环：两条压扁的椭圆 + 虚线外环
	CanvasArt.ellipse_rot_stroke(ci, 0.0, 0.0, 25.0 * breathe, 7.2 * breathe, 0.0,
		Color(0.66, 0.96, 1.0, 0.60), 1.3)
	CanvasArt.ellipse_rot_stroke(ci, 0.0, 0.0, 30.0 * breathe, 8.7 * breathe, 0.0,
		Color(1.0, 0.66, 0.92, 0.38), 1.0)
	_dashed_ellipse(ci, 35.0 * breathe, 10.2 * breathe, 18, t * 0.55,
		Color(0.72, 0.97, 1.0, 0.48), 1.0)

	# 8 枚符文：小菱形，硬边，和柔光对照
	for i in 8:
		var a := t * 0.5 + float(i) * TAU / 8.0
		var x := cos(a) * 35.0 * breathe
		var y := sin(a) * 10.2 * breathe
		var s := 1.7 + (0.5 if i % 2 == 0 else 0.0)
		var col := Color(0.82, 1.0, 1.0, 0.85) if i % 2 == 0 else Color(1.0, 0.68, 0.93, 0.8)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - s), Vector2(x + s * 0.6, y), Vector2(x, y + s), Vector2(x - s * 0.6, y),
		]), col)

func _paint_front(ci: CanvasItem) -> void:
	var t := _time
	var burst := _burst_amount()
	var pulse := 0.5 + 0.5 * sin(t * 2.1)

	# 三只守护灵：软光点 + 四芒星 + 三段拖尾
	# 放在前景层（z=+1），才不会被立绘挡住；地面法环仍留在身后。
	for i in 3:
		var a := t * 1.75 + float(i) * TAU / 3.0
		var orbit := 1.0 + burst * 0.35
		var x := cos(a) * 29.0 * orbit
		var y := -30.0 + sin(a) * 23.0 * orbit
		var col := Color(1.0, 0.68, 0.92) if i % 2 == 0 else Color(0.68, 0.98, 1.0)
		for trail in 3:
			var aa := a - float(trail + 1) * 0.16
			var tx := cos(aa) * 29.0 * orbit
			var ty := -30.0 + sin(aa) * 23.0 * orbit
			var ta := (0.22 - float(trail) * 0.06) * (0.7 + pulse * 0.6)
			ci.draw_texture_rect(_soft_dot(), Rect2(tx - 5.0, ty - 5.0, 10.0, 10.0), false,
				Color(col.r, col.g, col.b, ta))
		ci.draw_texture_rect(_soft_dot(), Rect2(x - 15.0, y - 15.0, 30.0, 30.0), false,
			Color(col.r, col.g, col.b, 0.34 + pulse * 0.18))
		_star4(ci, x, y, 4.2 + pulse * 1.4, Color(1.0, 1.0, 1.0, 0.9))
		_star4(ci, x, y, 6.6 + pulse * 1.8, Color(col.r, col.g, col.b, 0.28))

	# 呼吸环：每 3.4 秒从身体中段浮起一枚，仍然只用径向渐变纹理
	var cyc := fposmod(t + 0.4, 3.4) / 3.4
	var rr := 20.0 + cyc * _display.y * 0.55
	var ra := pow(1.0 - cyc, 2.2) * 0.26
	ci.draw_set_transform(Vector2(0.0, -_display.y * 0.45), 0.0, Vector2(1.0, 0.62))
	ci.draw_texture_rect(_ring(), Rect2(-rr, -rr, rr * 2.0, rr * 2.0), false,
		Color(0.66, 0.97, 1.0, ra))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 上升灵屑：确定性伪随机，前层亮、后层淡
	for i in 18:
		var phase := fposmod(t * (0.20 + 0.025 * float(i % 4)) + float(i) * 0.618, 1.0)
		var sway := sin(t * 0.9 + float(i) * 1.73) * (7.0 + _display.x * 0.06)
		var x := sin(float(i) * 2.17) * _display.x * 0.34 + sway
		var y := -6.0 - phase * _display.y * 0.95
		var fade := sin(phase * PI)
		var sz := 1.7 + float(i % 3) * 1.15
		var col := Color(1.0, 0.67, 0.92) if i % 3 == 0 else Color(0.66, 0.97, 1.0)
		ci.draw_texture_rect(_soft_dot(), Rect2(x - sz * 3.2, y - sz * 3.2, sz * 6.4, sz * 6.4),
			false, Color(col.r, col.g, col.b, fade * 0.36))
		if i % 4 == 0:
			_star4(ci, x, y, sz * 1.7, Color(1.0, 1.0, 1.0, fade * 0.72))

	# 两条绕身灵丝：先画宽而淡的底，再画细而亮的芯
	for k in 2:
		var pts := PackedVector2Array()
		var steps := 22
		for j in steps:
			var u := float(j) / float(steps - 1)
			var xx := sin(u * PI * 2.0 + t * 0.85 + float(k) * PI) * _display.x * (0.17 + 0.10 * u)
			var yy := -u * _display.y * 0.82 + sin(u * 6.0 + t * 1.1) * 2.0
			pts.append(Vector2(xx, yy))
		var col := Color(0.64, 0.97, 1.0, 0.10) if k == 0 else Color(1.0, 0.62, 0.90, 0.10)
		ci.draw_polyline(pts, col, 4.0, true)
		ci.draw_polyline(pts, Color(col.r, col.g, col.b, 0.26), 1.0, true)

	# 觉醒时，整圈向外抛出灵屑
	if burst > 0.0:
		var progress := 1.0 - _awaken_t / 1.6
		for i in 20:
			var a := float(i) * TAU / 20.0 + progress * 1.8
			var rad := _display.y * (0.12 + progress * 1.05)
			var x := cos(a) * rad
			var y := -_display.y * 0.48 + sin(a) * rad * 0.72
			_star4(ci, x, y, 2.0 + (1.0 - progress) * 2.4,
				Color(0.82, 1.0, 1.0, (1.0 - progress) * 0.5))

func _paint_burst_back(ci: CanvasItem) -> void:
	if _awaken_t <= 0.0:
		return
	var p := clampf(1.0 - _awaken_t / 1.6, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 2.6)
	var flash_fade := pow(1.0 - p, 3.0)
	var chest := Vector2(0.0, -_display.y * 0.50)

	# 1) 中心闪白：两枚不同尺度的径向渐变叠出“过曝”感。
	#    放在角色背后：人物剪影永远留在闪白之上，不会被洗掉。
	var flash_r := _display.y * (0.24 + eased * 1.15)
	ci.draw_texture_rect(_soft_dot(), Rect2(chest.x - flash_r, chest.y - flash_r,
		flash_r * 2.0, flash_r * 2.0), false, Color(0.58, 0.96, 1.0, 0.42 * flash_fade))
	var core_r := flash_r * 0.30
	ci.draw_texture_rect(_soft_dot(), Rect2(chest.x - core_r, chest.y - core_r,
		core_r * 2.0, core_r * 2.0), false, Color(1.0, 1.0, 1.0, 0.58 * flash_fade))

	# 2) 光柱：几何光柱纹理（横向高斯 + 纵向衰减），无 blur
	if p < 0.82:
		var pw := _display.x * (0.20 + 0.20 * sin(PI * p))
		var ph := _display.y * 1.55
		var pa := sin(PI * clampf(p * 1.15, 0.0, 1.0)) * (1.0 - p * 0.25)
		ci.draw_texture_rect(_pillar(), Rect2(-pw, -ph + _display.y * 0.12, pw * 2.0, ph),
			false, Color(0.58, 0.96, 1.0, 0.46 * pa))
		ci.draw_texture_rect(_pillar(), Rect2(-pw * 0.38, -ph * 0.88 + _display.y * 0.10,
			pw * 0.76, ph * 0.88), false, Color(1.0, 0.88, 1.0, 0.30 * pa))

	# 3) 两圈软光环：胸口 + 地面
	for i in 2:
		var rp := clampf(p * 1.22 - float(i) * 0.14, 0.0, 1.0)
		if rp <= 0.001 or rp >= 0.999:
			continue
		var rad := _display.y * (0.18 + rp * 1.05)
		var alpha := pow(1.0 - rp, 2.0) * (0.62 if i == 0 else 0.38)
		ci.draw_texture_rect(_ring(), Rect2(chest.x - rad, chest.y - rad, rad * 2.0, rad * 2.0),
			false, Color(0.64, 0.97, 1.0, alpha))
		var grad := _display.y * (0.22 + rp * 0.95)
		ci.draw_set_transform(Vector2(0.0, 0.0), 0.0, Vector2(1.0, 0.34))
		ci.draw_texture_rect(_ring(), Rect2(-grad, -grad, grad * 2.0, grad * 2.0),
			false, Color(1.0, 0.62, 0.90, alpha * 0.7))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _paint_burst_front(ci: CanvasItem) -> void:
	if _awaken_t <= 0.0:
		return
	var p := clampf(1.0 - _awaken_t / 1.6, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 2.6)
	var fade := pow(1.0 - p, 1.8)
	var chest := Vector2(0.0, -_display.y * 0.50)

	# 4) 12 道聚灵星屑 + 8 条放射线（硬边，像漫画集中线）
	for i in 12:
		var a := float(i) * TAU / 12.0 + p * 1.7
		var rad := _display.y * (0.92 * (1.0 - eased) + 0.10)
		var x := chest.x + cos(a) * rad
		var y := chest.y + sin(a) * rad * 0.80
		var col := Color(1.0, 0.70, 0.93) if i % 2 == 0 else Color(0.72, 0.99, 1.0)
		var sz := (2.0 + (1.0 - p) * 2.6) * (0.8 + 0.4 * sin(float(i) * 2.4))
		ci.draw_texture_rect(_soft_dot(), Rect2(x - 9.0, y - 9.0, 18.0, 18.0), false,
			Color(col.r, col.g, col.b, fade * 0.30))
		_star4(ci, x, y, sz, Color(col.r, col.g, col.b, fade * 0.85))

	for i in 8:
		var a := float(i) * TAU / 8.0 + 0.2
		var r0 := _display.y * 0.10
		var r1 := _display.y * (0.50 + eased * 0.62)
		ci.draw_line(chest + Vector2(cos(a), sin(a) * 0.8) * r0,
			chest + Vector2(cos(a), sin(a) * 0.8) * r1,
			Color(0.75, 0.99, 1.0, 0.22 * fade), 1.2, true)

	# 5) 墨点半调外圈：把“柔”拉回 Motion UI 的硬网点语言
	for i in 28:
		var a := float(i) * TAU / 28.0 + p * 0.9
		var rad := _display.y * (0.18 + eased * 0.88)
		var x := chest.x + cos(a) * rad
		var y := chest.y + sin(a) * rad * 0.68
		var sz := 1.4 + 1.2 * (1.0 - p)
		ci.draw_circle(Vector2(x, y), sz,
			Color(1.0, 0.70, 0.93, (1.0 - p) * 0.32))

func _burst_amount() -> float:
	if _awaken_t <= 0.0:
		return 0.0
	return pow(1.0 - clampf(1.0 - _awaken_t / 1.6, 0.0, 1.0), 1.5)

# ============================================================
# 小工具
# ============================================================

func _dashed_ellipse(ci: CanvasItem, rx: float, ry: float, count: int, phase: float,
		color: Color, width: float) -> void:
	var step := TAU / float(count)
	for i in count:
		var a0 := phase + float(i) * step
		var a1 := a0 + step * 0.46
		CanvasArt.stroke(ci, CanvasArt.arc_pts(0.0, 0.0, rx, ry, 0.0, a0, a1, 0.12), color, width, false)

func _star4(ci: CanvasItem, x: float, y: float, size: float, color: Color) -> void:
	if size <= 0.0 or color.a <= 0.0:
		return
	var s := size
	var k := 0.28
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x, y - s), Vector2(x + s * k, y - s * k), Vector2(x + s, y),
		Vector2(x + s * k, y + s * k), Vector2(x, y + s), Vector2(x - s * k, y + s * k),
		Vector2(x - s, y), Vector2(x - s * k, y - s * k),
	]), color)

func _soft_dot() -> Texture2D:
	if _soft_dot_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.34, 0.62, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.78), Color(1, 1, 1, 0.30),
			Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_soft_dot_tex = tex
	return _soft_dot_tex

func _ring() -> Texture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.50, 0.64, 0.72, 0.80, 0.90, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.18),
			Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12),
			Color(1, 1, 1, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.width = 160
		tex.height = 160
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_ring_tex = tex
	return _ring_tex

func _pillar() -> Texture2D:
	if _pillar_tex != null:
		return _pillar_tex
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / float(h - 1)          # 0 = 顶，1 = 底
		var vertical := pow(v, 1.45) * (1.0 - 0.45 * smoothstep(0.75, 1.0, v))
		for x in w:
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var wide := exp(-u * u * 4.6)
			var core := exp(-u * u * 34.0)
			var a := clampf(vertical * (wide * 0.58 + core * 0.62), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_pillar_tex = ImageTexture.create_from_image(img)
	return _pillar_tex
