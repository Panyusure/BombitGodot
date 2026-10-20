extends Node2D

## 角色氛围层基类 —— 5 个精灵共用的表现底座。
##
## 由 EntityView 挂在 pivot 之下，因此自动跟随「弹跳 / 摇摆 / 翻转 / 压扁 / 通灵膨胀」。
## 与 SoulGlow 的区别：SoulGlow 只服务「未来」的通灵形态（SDF 柔光 + 法环 + 觉醒爆发），
## 这里是给每个角色一条轻量、各有辨识度的氛围线（时间 / 暗影 / 生命 / 火焰 / 洞察）。
##
## 子类只做三件事：
##   1. motion()      —— 该角色的行走 / 静止动效参数（覆盖基类默认）
##   2. layer_specs() —— 声明要几层、各自的 z、混合模式
##   3. paint(ci,id)  —— 在指定层上画该角色的氛围
## 层创建、时间推进、共享光斑纹理、通用图元全部在这里，避免 5 份重复实现。
##
## 约束（性能）：
##   * paint() 每帧每层都会被调用，单层保持在 ~40 个绘制调用以内；
##   * paint() 内**不得**创建纹理 / 渐变 / 材质，也不得 load()；
##   * 静止时可用 energy 大幅衰减，甚至直接 return，避免无意义重绘。
##
## 坐标系：原点 = 脚底中心（脚底 y = 0，向上为负）。
## display 是立绘的显示尺寸，anchor 是立绘锚点（0..1），二者用于估算身体中心：
##   body_center = Vector2(0, -display.y * anchor.y + display.y * 0.5)
## 一般直接用负的经验值更稳（见各子类的实现）。

# ---------------------------------------------------------------- 子类覆写点

## 动效参数。键与含义：
##   bounce    行走弹跳高度（px，向上为正，内部取负）
##   wobble    行走摇摆角度（deg，左右各摆 ±该值）
##   stride    步频（rad/s；一个完整周期 = 左右各一步）
##   sway      横向重心摆动（px，左右各 ±该值）
##   lean      前进方向倾斜（deg，朝移动方向压一点）
##   breathe   静止呼吸幅度（比例，0.03 ≈ 上下 3%）
##   idle_rate 静止呼吸频率（rad/s）
##   squash    落地压扁系数（0..1，越大越 Q）
func motion() -> Dictionary:
	return {}

## 层声明。每项 {"id": String, "z": int, "blend": "add" | "normal"}。
## z 相对 pivot：负值在立绘之后，正值在立绘之前。
func layer_specs() -> Array:
	return [{"id": "aura", "z": -3, "blend": "add"}]

## 在某一层上绘制。ci 恒等于该层的 CanvasItem（自身即 Node2D）。
func paint(_ci: CanvasItem, _layer: String) -> void:
	pass

## 角色主色（菜单 / HUD 可以取用，用于统一色调）。
func accent_color() -> Color:
	return Color("#8dd8ff")

## 该角色的氛围层是否已经接管「地面投影」（例如小天脚下一面水镜、阿修贴地的长影）。
## 返回 true 时 EntityView 不再画默认的椭圆落影，避免两层地影叠在一起互相弄脏。
func owns_ground() -> bool:
	return false

# ---------------------------------------------------------------- 每帧上下文

var t := 0.0                  # 累计时间（秒，已按 speed 缩放）
var display := Vector2.ZERO   # 立绘显示尺寸
var anchor := Vector2(0.5, 1.0)
var tex: Texture2D = null
var moving := false
var alive := true
var facing := 1
var bob := 0.0                # 当前弹跳位移（负 = 向上）
var energy := 1.0             # 全局强度（0..1）：静止时衰减，省掉大部分绘制
var cast := 0.0               # 技能施放强度（0..1），角色放大招时拉满
var actor = null              # Actor 实例，可为 null —— 使用前必须判空

# ---------------------------------------------------------------- 内部状态

var _layers: Dictionary = {}  # id -> Node2D
var _built := false
var _last_display := Vector2.ZERO

## 画在立绘**之上**（z > 0）的层默认压低到这一档不透明度。
## 加色叠在脸上会把五官洗掉 —— 角色清晰度优先于特效浓度。
## 子类可以在 layer_specs() 里给某一层写 "gain" 覆盖它。
const FRONT_GAIN := 0.78

# 共享纹理（所有子类共用一份，只生成一次）
static var _soft_dot_tex: Texture2D = null
static var _ring_tex: Texture2D = null
static var _white_tex: Texture2D = null

# ---------------------------------------------------------------- 生命周期

func _ready() -> void:
	_ensure_layers()

func _ensure_layers() -> void:
	if _built:
		return
	_built = true
	var specs: Array = layer_specs()
	if specs.is_empty():
		specs = [{"id": "aura", "z": -3, "blend": "add"}]
	for spec in specs:
		var layer := Node2D.new()
		layer.name = String(spec.get("id", "aura"))
		layer.z_index = int(spec.get("z", 0))
		layer.z_as_relative = true
		if String(spec.get("blend", "normal")) == "add":
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			layer.material = mat
		# 盖在立绘上的层统一压暗一档：特效不能把角色的脸和轮廓吃掉。
		var gain := float(spec.get("gain", FRONT_GAIN if int(spec.get("z", 0)) > 0 else 1.0))
		if gain < 1.0:
			layer.modulate = Color(1, 1, 1, clampf(gain, 0.0, 1.0))
		var id := String(spec["id"])
		layer.draw.connect(func() -> void: paint(layer, id))
		add_child(layer)
		_layers[id] = layer

## 纹理 / 尺寸变化时调用（换朝向、通灵进化、切换角色）。子类一般无需覆写。
func configure(new_tex: Texture2D, new_display: Vector2, new_anchor: Vector2) -> void:
	# 可能早于 _ready（EntityView 先 setup 再入树），这里补一次建层。
	_ensure_layers()
	tex = new_tex
	display = new_display
	anchor = new_anchor
	_last_display = new_display
	on_configure()
	redraw()

## 子类可覆写：纹理变了之后要重建的缓存（如按立绘轮廓采样的点）。
func on_configure() -> void:
	pass

## 每帧由 EntityView 调用。ctx 由 EntityView 填好后再调用（见 EntityView.update_view）。
func advance(delta: float, speed: float = 1.0) -> void:
	t += delta * speed
	if not visible:
		return
	redraw()

func redraw() -> void:
	for node in _layers.values():
		if is_instance_valid(node):
			node.queue_redraw()

## 清空（角色死亡 / 离开视野）。
func clear() -> void:
	visible = false

func set_visible_layers(on: bool) -> void:
	visible = on
	redraw()

# ---------------------------------------------------------------- 通用图元

## 脚底在屏幕上的 y（auros 的局部坐标里脚底恒为 0，这个函数只为可读性）。
func foot_y() -> float:
	return 0.0

## 身体中心估计（向上为负）。
## 立绘顶边在 y = -display.y * anchor.y、底边在 y = display.y * (1 - anchor.y)，
## 所以中心 = 顶边 + display.y/2 = display.y * (0.5 - anchor.y)。
## 注意 anchor.y 常是 0.78~0.97，底边会落在地面之下的几像素，这是美术留白，不必较真。
func body_center() -> Vector2:
	if display.y <= 0.0:
		return Vector2(0, -28)
	return Vector2(0, display.y * (0.5 - anchor.y))

## 一到两像素的四角星（火花 / 光点 / 灵屑）。
func star4(ci: CanvasItem, x: float, y: float, size: float, color: Color) -> void:
	var s := size
	var k := s * 0.28
	var pts := PackedVector2Array([
		Vector2(x, y - s), Vector2(x + k, y - k), Vector2(x + s, y),
		Vector2(x + k, y + k), Vector2(x, y + s), Vector2(x - k, y + k),
		Vector2(x - s, y), Vector2(x - k, y - k),
	])
	ci.draw_colored_polygon(pts, color)

## 虚线椭圆环（法环 / 刻度 / 计时环）。
func dashed_ellipse(ci: CanvasItem, rx: float, ry: float, count: int, phase: float,
		color: Color, width: float = 1.6, dot: float = 0.30) -> void:
	if count <= 0:
		return
	var step := TAU / float(count)
	for i in count:
		var a0 := phase + float(i) * step
		var a1 := a0 + step * clampf(dot, 0.05, 1.0)
		var pts := PackedVector2Array()
		var seg := 4
		for j in seg + 1:
			var a := lerpf(a0, a1, float(j) / float(seg))
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		ci.draw_polyline(pts, color, width, true)

## 弧线发光（比 draw_arc 多了圆头，视觉更柔）。
func glow_arc(ci: CanvasItem, cx: float, cy: float, r: float, a0: float, a1: float,
		color: Color, width: float) -> void:
	if absf(a1 - a0) < 0.001:
		return
	var seg := clampi(int(absf(a1 - a0) * r * 0.5), 6, 64)
	var pts := PackedVector2Array()
	for i in seg + 1:
		var a := lerpf(a0, a1, float(i) / float(seg))
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	ci.draw_polyline(pts, color, width, true)
	var cap_r := width * 0.5
	ci.draw_circle(pts[0], cap_r, color, true, -1.0, true)
	ci.draw_circle(pts[pts.size() - 1], cap_r, color, true, -1.0, true)

# ---------------------------------------------------------------- 共享纹理

func soft_dot() -> Texture2D:
	if _soft_dot_tex != null:
		return _soft_dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.42))
	var grad := GradientTexture2D.new()
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	grad.width = 64
	grad.height = 64
	_soft_dot_tex = grad
	return _soft_dot_tex

func ring_tex() -> Texture2D:
	if _ring_tex != null:
		return _ring_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.62, Color(1, 1, 1, 0))
	g.add_point(0.80, Color(1, 1, 1, 0.55))
	g.add_point(0.92, Color(1, 1, 1, 1))
	g.add_point(1.00, Color(1, 1, 1, 0))
	var grad := GradientTexture2D.new()
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	grad.width = 96
	grad.height = 96
	_ring_tex = grad
	return _ring_tex

func white_tex() -> Texture2D:
	if _white_tex != null:
		return _white_tex
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	_white_tex = ImageTexture.create_from_image(img)
	return _white_tex
