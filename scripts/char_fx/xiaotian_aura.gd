extends "res://scripts/char_fx/CharAura.gd"

## 小天（xiaotian）· 智慧之王的动效与氛围层。
##
## 设定 → 视觉的映射（不是通用粒子包）：
##   小天是《奥奇传说》帝释天的幼年形态，神水 / 光属性，称号「智慧之王」，
##   冷酷、爱耍帅，技能「潜能洞察」是「看穿并改写局势」。所以这套氛围只认四件事：
##     水镜     —— 脚下不是影子，是一面浅水（水体 + 三道涟漪 + 水平反光 + 倒影）
##     冰晶     —— 4 枚细长六角棱晶绕身缓慢公转，带自转与极短移动残迹
##     洞察之眼 —— 四象限准星 + 菱形瞳孔，缓慢自转，cast 时张开并扫视
##     冷冽符印 —— 脚下断续刻度环 + 四向分划，转速 0.10 rad/s（约 63 秒一圈）
##   配色只有三档：冰蓝 #a8dafa / 白金 #eaf6ff / 深靛 #3f5f8f。
##   没有暖色、没有绿、没有龙牙 / 叶片 / 齿轮，也没有「发光魔法阵」。
##
## 动画性格：「优雅的漂浮者」——轻、慢、几乎不落地。
##   bounce 2.2（冰面上只离地两像素）、stride 8.4（比通用值 11 慢一档）、
##   squash 0.10（落地不砸）、breathe 0.018 @ 1.7 rad/s（呼吸长而浅）。
##   「浮动感」刻意不靠弹跳，而靠本文件自己画的层：水面随 sin 呼吸、每枚冰晶
##   各带自己的漂移相位、准星独立悬浮在头侧 —— 身体是浮在水上的，不是蹦的。
##
## 技术纪律（对齐 SoulGlow 的做法）：
##   * 全部矢量硬边 + 基类一次性生成的径向渐变纹理；没有 blur、没有后处理、
##     没有 SubViewport、没有 shader、没有逐帧新建资源。
##   * paint() 内不创建纹理 / 渐变 / 材质、不 load()：soft_dot() 在 _ready() 与
##     on_configure() 里预热（见 _warm_textures 的注释）。
##   * 绘制调用预算（每帧每层，硬上限 40）：water ≤ 12 / aura ≤ 36 / front ≤ 12。
##
## 坐标系：原点 = 脚底中心，向上为 -y，地面在 y = 0；立绘约占 y ∈ [-display.y, 0]。
## 本素材 572×560，display ≈ 76.5×74.9，头在局部 +x 侧且整体是漂浮姿态（没有脚），
## 所以「脚下是水」比「脚下是影子」更贴设定。

# ---------------------------------------------------------------- 色彩与常量

const ICE := Color("a8dafa")       # 神水冰蓝：所有主线颜色
const PLATINUM := Color("eaf6ff")  # 白金：只给高光 / 刻度 / 棱线用
const INDIGO := Color("3f5f8f")    # 深靛：水面深度，用来替代「黑落影」
const STRIDE := 8.4                # 与 motion().stride 同源，尾波要对齐脚步

# ---------------------------------------------------------------- 基类覆写点

## 行走 / 待机动效。全部取「轻、慢、浅」的一端：
##   bounce 2.2 —— 只离地两像素，读作「水面上抬了一下」而不是跳；
##   wobble 2.6 / sway 1.6 —— 摆幅小但周期长，像水漂而不是走路的左右晃；
##   lean 4.5 —— 冷面角色也要有一点前倾的从容，完全直立会显得僵；
##   breathe 0.018 @ 1.7 —— 呼吸又长又浅，不会读成喘；
##   squash 0.10 —— 落地只压 10%，绝不砸地（其它 Q 版角色常在 0.18~0.22）。
func motion() -> Dictionary:
	return {
		"bounce": 2.2,
		"wobble": 2.6,
		"stride": STRIDE,
		"sway": 1.6,
		"lean": 4.5,
		"breathe": 0.018,
		"idle_rate": 1.7,
		"squash": 0.10,
	}

## 三层：水镜（normal）+ 冰晶/符印（add）+ 洞察之眼（add）。
## water 必须是 normal：水面是「实体」，塞进 additive 会变成一块发白的雾；
## 真正的「轻 additive」放在 aura 层（水面冷光、冰晶辉光、刻度环都加在它上面）。
func layer_specs() -> Array:
	return [
		{"id": "water", "z": -4, "blend": "normal"},
		{"id": "aura", "z": -3, "blend": "add"},
		{"id": "front", "z": 1, "blend": "add"},
	]

## 菜单 / HUD 取色用：冰蓝主色。
func accent_color() -> Color:
	return ICE

## 脚下是水镜而不是落影，通用椭圆影会把它压成一块脏灰。
func owns_ground() -> bool:
	return true

# ---------------------------------------------------------------- 生命周期

func _ready() -> void:
	# 基类 _ready 负责按 layer_specs() 建层，这里只额外预热共享纹理。
	super()
	_warm_textures()

func on_configure() -> void:
	# 要按立绘轮廓重建的缓存一个都没有（这里全是解析几何），
	# 但纹理预热必须在这个时机完成，见 _warm_textures。
	_warm_textures()

## paint() 里不允许创建纹理 / 渐变。基类的 soft_dot() 是「首次调用才生成」的
## 懒加载共享纹理，所以把它挪到建层 / 配置阶段预热：之后每帧的 paint() 只读取指针。
## 只预热实际用到的 soft_dot()，ring_tex / white_tex 本文件不用，不浪费一次烘焙。
func _warm_textures() -> void:
	soft_dot()

# ---------------------------------------------------------------- 尺寸推导

## 整体强度。energy 由调用方衰减；为 0 时一次绘制都不做（尊重「静止可 return」的约定），
## 但只要还在画，就保底 0.45，避免调用方把 energy 调得偏低时整层直接消失。
func _strength() -> float:
	if energy <= 0.001:
		return 0.0
	var k := 0.45 + 0.55 * clampf(energy, 0.0, 1.0)
	if not alive:
		k *= 0.45          # 倒地后只留一滩水光，不画准星与冰晶
	return k

## 立绘顶边的 y。
## 注意：基类 body_center() 用的是 (1.0 - anchor.y)，当 anchor.y = 0.88 时会把
## 「身体中心」算到脚底以下（+28.5），和画面对不上；这里按 EntityView 的贴图摆放
## （顶边 = -display.y * anchor.y，见 EntityView._draw_sprite）直接推。
func _top_y() -> float:
	return -display.y * anchor.y

## 头部高度（准星/洞察之眼挂在头侧）。
func _head_y() -> float:
	return _top_y() + display.y * 0.22

## 躯干中心（冰晶公转的圆心）。Q 版大头：脖子大致在立绘 52% 处。
func _torso_y() -> float:
	return _top_y() + display.y * 0.52

## 绕原点旋转一个局部点。冰晶不用 draw_set_transform，是为了避免和
## 准星那段 draw_set_transform 的状态互相污染。
func _rot(v: Vector2, ca: float, sa: float) -> Vector2:
	return Vector2(v.x * ca - v.y * sa, v.x * sa + v.y * ca)

# ---------------------------------------------------------------- 绘制分发

func paint(ci: CanvasItem, layer: String) -> void:
	if ci == null:
		return
	# 所有几何都由 display 推导；尺寸没就绪就直接返回，既避免除零也避免画一堆 0 尺寸图元。
	if display.x <= 0.0 or display.y <= 0.0:
		return
	var k := _strength()
	if k <= 0.02:
		return
	match layer:
		"water":
			_paint_water(ci, k)
		"aura":
			_paint_aura(ci, k)
		"front":
			_paint_eye(ci, k)

# ---------------------------------------------------------------- 水镜（z=-4）

## 水镜层。先铺偏靛的水体（在浅色地砖上也不会变成一块黑落影），再铺冰蓝水面，
## 然后把「涟漪 / 水平反光 / 倒影 / 水缘」压进去。全部矢量硬边，没有模糊。
## 调用数：本体 2 + 涟漪 3 + 反光 2 + 倒影 1 + 水缘 1 + 尾波 2 + 对焦环 1 = 12。
func _paint_water(ci: CanvasItem, k: float) -> void:
	var c := clampf(cast, 0.0, 1.0)
	# 移动时沿前进方向拉长 10%。局部 +x 就是角色正面（pivot 已按朝向翻转），
	# 所以这里不乘 facing —— 乘了会在向左走时把水面拖到身后去。
	var stretch := 1.0 + (0.10 if moving else 0.0)
	var breath := 1.0 + 0.035 * sin(t * 1.05)
	var rx := maxf(20.0, display.x * 0.44) * stretch * breath
	var ry := maxf(5.0, rx * 0.28)
	var cy := -0.6 + sin(t * 0.9) * 0.5
	# 弹跳越高水面越小（对应原作落影的收缩逻辑），幅度压得很小：他是浮着的，不是跳着的。
	var lift := clampf(absf(bob) / 26.0, 0.0, 0.35)
	rx *= 1.0 - lift * 0.55
	ry *= 1.0 - lift * 0.45
	# 退化保护：收缩 / 缩放之后仍要保证是能画的椭圆。
	if rx <= 1.0 or ry <= 0.4:
		return

	# 1) 水体：深靛打底 → 冰蓝覆面。深靛故意压到 0.13 —— 0.20 在浅色地砖上
	#    会读成「一个黑洞」，水的蓝反而没了；提亮冰蓝覆面才像一汪浅水。
	MapArt.ellipse(ci, 0.0, cy, rx, ry, Color(INDIGO.r, INDIGO.g, INDIGO.b, 0.13 * k))
	MapArt.ellipse(ci, 0.0, cy - ry * 0.18, rx * 0.84, ry * 0.66,
		Color(ICE.r, ICE.g, ICE.b, 0.22 * k))

	# 2) 涟漪：三道不同周期（3.2 / 4.0 / 4.8 秒）的椭圆环，从中心向外扩、边扩边淡。
	#    周期取三个互不成倍数的值，三道环就永远不会同相叠成「靶心」。
	for i in 3:
		var period := 3.2 + float(i) * 0.8
		var phase := fposmod(t / period + float(i) * 0.37, 1.0)
		var rr := 2.0 + phase * rx * 0.92
		var ra := pow(1.0 - phase, 1.8) * (0.32 + c * 0.16) * k
		if ra <= 0.012:
			continue
		# 移动时涟漪整体往身后拖：水是被「推」出去的，不是从脚底对称冒出来的。
		var back := -phase * (4.0 if moving else 1.1)
		MapArt.ellipse_stroke(ci, back, cy, rr, maxf(0.6, rr * 0.30),
			Color(ICE.r, ICE.g, ICE.b, ra), 1.0 + 0.6 * (1.0 - phase))

	# 3) 水平反光：宽而淡 + 细而亮两条压扁的横线。水之所以像水，靠的就是这条
	#    视平线；不描一圈实边，避免水面变成「盘子」。
	var bar := rx * 1.02
	ci.draw_line(Vector2(-bar * 0.5, cy - 0.5), Vector2(bar * 0.5, cy - 0.5),
		Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.10 * k), 2.2, true)
	ci.draw_line(Vector2(-bar * 0.30, cy - 1.1), Vector2(bar * 0.30, cy - 1.1),
		Color(1.0, 1.0, 1.0, 0.15 * k), 1.0, true)

	# 4) 倒影：脚下一团被水面吃掉一半的冷光。用基类共享的径向渐变纹理压扁，
	#    只加 0.13 —— 它是「倒影」，不是发光体，绝不能比角色亮。
	var refl_w := display.x * 0.44
	var refl_h := maxf(4.0, ry * 1.6)
	ci.draw_texture_rect(soft_dot(),
		Rect2(-refl_w * 0.5, cy - refl_h * 0.5, refl_w, refl_h), false,
		Color(ICE.r, ICE.g, ICE.b, 0.13 * k))

	# 5) 水缘：外圈一道极细的白金线，把「水面」从地砖上切下来（只切一圈，不做多层描边）。
	MapArt.ellipse_stroke(ci, 0.0, cy, rx * 1.01, ry * 1.06,
		Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.12 * k), 1.0)

	# 6) 移动尾波：身后两道短弧，频率与 motion().stride 对齐（一步推一次水）。
	if moving:
		var push := 0.55 + 0.45 * absf(sin(t * STRIDE))
		for i in 2:
			var edge := 0.55 + float(i) * 0.30
			var wy := cy + float(i) * 0.9
			ci.draw_line(Vector2(-rx * edge, wy), Vector2(-rx * (edge - 0.18), wy),
				Color(ICE.r, ICE.g, ICE.b, (0.15 - float(i) * 0.05) * k * push), 1.0, true)

	# 7) 洞察开启：水面多一圈极亮的细环 —— 水镜「对焦」，和准星的张开同拍。
	if c > 0.25:
		MapArt.ellipse_stroke(ci, 0.0, cy, rx * 1.16, ry * 1.20,
			Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.26 * c * k), 1.2)

# ---------------------------------------------------------------- 冰晶 / 符印（z=-3）

## 冰晶 + 冷冽符印层。
## 这一层负责「冷冽」：4 枚细长六角冰晶缓慢绕身公转（0.30 rad/s，约 21 秒一圈），
## 脚下 10 段断续刻度环（0.10 rad/s，约 63 秒一圈）。
## 冰晶靠「亮面 / 棱线」做出折面感：additive 下暗面不是压暗，而是少加一点光。
## 调用数：冷雾 1 + 符印 14 + 冰晶 16 + 残迹 2 + 水面冷光 3 = 36。
func _paint_aura(ci: CanvasItem, k: float) -> void:
	# 1) 极淡的冷雾：把冰晶和身体缝在一起，避免冰晶像贴纸浮在旁边。
	#    0.045 的 alpha 是「几乎看不见，但一去掉就觉得散」的量。
	var mist_w := display.x * 1.15
	var mist_h := display.y * 1.02
	ci.draw_texture_rect(soft_dot(),
		Rect2(-mist_w * 0.5, _torso_y() - mist_h * 0.5, mist_w, mist_h), false,
		Color(0.40, 0.72, 1.0, 0.045 * k))

	# 2) 冷冽符印：脚下一圈断续刻度。刻意只有一圈、不闭合、不发光脉动 ——
	#    魔法阵是「闭合 + 符文 + 呼吸光」，这里读起来是量角器 / 分划盘。
	var sigil_x := maxf(22.0, display.x * 0.46)
	var sigil_y := maxf(6.5, sigil_x * 0.30)
	dashed_ellipse(ci, sigil_x, sigil_y, 10, t * 0.10,
		Color(ICE.r, ICE.g, ICE.b, 0.28 * k), 1.0, 0.24)
	# 四个正方向各一根短刻度（10 段弧 + 4 根 = 14 次绘制）。
	# squash 用 maxf 兜底：sigil_x 恒 >= 22，这里只是形式上的除零保护。
	var squash := sigil_y / maxf(0.001, sigil_x)
	for i in 4:
		var ang := float(i) * PI * 0.5 + t * 0.10
		var dir := Vector2(cos(ang), sin(ang) * squash)
		ci.draw_line(dir * (sigil_x * 0.90), dir * (sigil_x * 1.07),
			Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.20 * k), 1.0, true)

	# 3) 冰晶：4 枚细长六角棱晶。公转 + 自转 + 各自的上下漂移。
	var spin := t * 0.30
	var orbit_x := maxf(16.0, display.x * 0.44)
	var orbit_y := maxf(11.0, display.y * 0.22)
	var torso := _torso_y()
	for i in 4:
		var ang_orbit := spin + float(i) * TAU * 0.25 + 0.55
		# 每枚带自己的 sin 相位上下漂 1.5px：四枚不同步，才像「各自浮着」，
		# 而不是被一个转盘带着走。
		var drift := sin(t * 1.05 + float(i) * 1.7)
		var x := cos(ang_orbit) * orbit_x * (1.0 + 0.05 * drift)
		var y := torso + sin(ang_orbit) * orbit_y + drift * 1.5
		var near := 0.5 + 0.5 * sin(ang_orbit)       # 0 = 身后, 1 = 身前
		var half_len := display.y * (0.085 + 0.035 * near)
		var half_wid := half_len * 0.40
		var alpha := (0.30 + 0.20 * near) * k
		# 辉光：additive 下一枚软光斑就够，不做「光晕套光晕」。
		var gl := half_len * 2.6
		ci.draw_texture_rect(soft_dot(), Rect2(x - gl, y - gl, gl * 2.0, gl * 2.0), false,
			Color(0.56, 0.86, 1.0, alpha * 0.20))
		_crystal(ci, x, y, t * 0.55 + float(i) * 1.1, half_len, half_wid, alpha)
		# 4) 移动残迹：只给最靠前的两枚拉一条 0.16 秒前的极短连线。
		#    不做粒子、不做残影副本 —— 冰晶是硬物，划过只该留一道痕。
		if moving and i < 2:
			var prev_a := ang_orbit - 0.16
			ci.draw_line(Vector2(cos(prev_a) * orbit_x, torso + sin(prev_a) * orbit_y),
				Vector2(x, y), Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.18 * k), 1.2, true)

	# 5) 水面冷光：三粒四芒星，相位错开地闪。放在 add 层的低处而不是 water 层，
	#    这样反光是「加」上去的，不会把水涂成一块白。
	for i in 3:
		var tw := pow(0.5 + 0.5 * sin(t * 1.35 + float(i) * 2.2), 3.0)
		if tw <= 0.08:
			continue
		var gx := (float(i) - 1.0) * maxf(12.0, display.x * 0.26)
		var gy := -1.2 + float(i % 2) * 1.6
		star4(ci, gx, gy, 1.1 + tw * 1.2,
			Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.42 * tw * k))

## 一枚冰晶：主体六边形 + 受光亮面 + 一条棱线（共 3 次绘制）。
## 形状刻意是「细长六角」而不是正六边形：正六边形像骰子 / 蜂巢，
## 上下拉长的尖棱才像冰。所有点绕自身中心旋转（自转），棱角保持硬边。
func _crystal(ci: CanvasItem, cx: float, cy: float, ang: float,
		half_len: float, half_wid: float, alpha: float) -> void:
	if half_len <= 0.5 or alpha <= 0.01:
		return
	var ca := cos(ang)
	var sa := sin(ang)
	var o := Vector2(cx, cy)
	var p_tip := Vector2(0.0, -half_len)
	var p_shoulder := Vector2(half_wid, -half_len * 0.42)
	var p_waist := Vector2(half_wid * 0.78, half_len * 0.40)
	var p_bottom := Vector2(0.0, half_len)
	var pts := PackedVector2Array([
		_rot(p_tip, ca, sa) + o,
		_rot(p_shoulder, ca, sa) + o,
		_rot(p_waist, ca, sa) + o,
		_rot(p_bottom, ca, sa) + o,
		_rot(Vector2(-p_waist.x, p_waist.y), ca, sa) + o,
		_rot(Vector2(-p_shoulder.x, p_shoulder.y), ca, sa) + o,
	])
	# 背面一半：只加一点点冰蓝，保留透明感（否则像不透明塑料片）。
	ci.draw_colored_polygon(pts, Color(ICE.r, ICE.g, ICE.b, alpha * 0.55))
	# 受光亮面（右半边）：additive 里「更亮的那一半」就是受光面，无需压暗背面。
	ci.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], pts[2], pts[3]]),
		Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, alpha * 0.42))
	# 棱线：上尖 → 下尖一根，硬边。多一根都会把冰晶画成玻璃碎片。
	ci.draw_line(pts[0], pts[3], Color(1.0, 1.0, 1.0, alpha * 0.65), 0.9, true)

# ---------------------------------------------------------------- 洞察之眼（z=+1）

## 洞察之眼：四象限准星 + 十字臂 + 菱形瞳孔，缓慢自转；cast 时张开并扫视。
## 关键差异：这里没有闭合圆、没有符文、没有内嵌星形 —— 那些是「魔法阵」。
## 准星的正确读法是「缺口 + 十字 + 瞳孔」：一把冷静的瞄具。
## 调用数：象限弧 4 + 十字臂 4 + 瞳孔 1 + 芯点 1 + 扫视 2 = 12。
func _paint_eye(ci: CanvasItem, k: float) -> void:
	# 死了就不「看」了：这一层是角色意识的外化，断气后必须整层消失。
	if not alive:
		return
	var c := clampf(cast, 0.0, 1.0)
	# 头在局部 +x 一侧（pivot 会按朝向整体镜像，所以 +x 永远是「正面」，
	# 这里再乘 facing 就会在左走时把准星甩到脑后）。
	var ex := clampf(display.x * 0.45 + 4.5, 20.0, 44.0)
	var ey := _head_y() + sin(t * 0.9) * 1.3
	var radius := maxf(4.5, display.x * 0.11) * (1.0 + c * 0.45)
	var a := (0.34 + 0.42 * c) * k
	if a <= 0.02:
		return

	# 准星外圈画在一个「随时间为轴旋转」的坐标系里（0.16 rad/s ≈ 39 秒一圈）：
	# 只转外圈，瞳孔留在不转的空间里 —— 读起来是「视线在缓慢校准」，
	# 而不是「整只眼睛在乱转」。
	ci.draw_set_transform(Vector2(ex, ey), t * 0.16, Vector2.ONE)
	var span := 1.14                       # 每段 65°，四个缺口正对十字轴
	for i in 4:
		var a0 := float(i) * PI * 0.5 + (PI * 0.5 - span) * 0.5
		ci.draw_arc(Vector2.ZERO, radius, a0, a0 + span, 7,
			Color(ICE.r, ICE.g, ICE.b, a * 0.90), 1.2, true)
	var arm_in := radius * 1.10
	var arm_out := radius * 1.52 + c * 2.6  # cast 时臂伸长 = 准星「张开」
	for i in 4:
		var dir := Vector2.RIGHT.rotated(float(i) * PI * 0.5)
		ci.draw_line(dir * arm_in, dir * arm_out,
			Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, a * 0.55), 1.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 瞳孔 = 立起来的菱形冰片 + 中心白金点。不做圆瞳：圆瞳太可爱，
	# 菱形才配「冷酷、爱耍帅」；而且菱形和冰晶是同一套几何语言。
	var pr := radius * 0.40
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(ex, ey - pr * 1.55), Vector2(ex + pr, ey),
		Vector2(ex, ey + pr * 1.55), Vector2(ex - pr, ey),
	]), Color(ICE.r, ICE.g, ICE.b, a * 0.75))
	ci.draw_circle(Vector2(ex, ey), maxf(0.7, pr * 0.30),
		Color(1.0, 1.0, 1.0, minf(1.0, a * 1.35)), true, -1.0, true)

	# cast：外圈一道细弧来回扫，sin 的驻点让它「扫到尽头停一下」。
	# 刻意没有扩散环 / 闪白 / 爆发粒子 —— 「潜能洞察」是看穿，不是放炮。
	if c > 0.02:
		var sweep := sin(t * 2.6) * 0.95
		var sr := radius * 2.30
		ci.draw_arc(Vector2(ex, ey), sr, sweep - 0.28, sweep + 0.28, 9,
			Color(PLATINUM.r, PLATINUM.g, PLATINUM.b, 0.26 * c * k), 1.4, true)
		ci.draw_circle(Vector2(ex, ey) + Vector2(cos(sweep), sin(sweep)) * sr,
			1.2 + c * 0.8, Color(1.0, 1.0, 1.0, 0.45 * c * k), true, -1.0, true)
