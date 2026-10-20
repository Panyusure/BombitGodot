extends "res://scripts/char_fx/CharAura.gd"

## 阿瑞（arui）专属氛围层 —— 生命之王·阿瑞斯的幼年形态。
##
## 造型考据（决定每一笔）：草属性、出生曙光森林；战死后被父亲装上「机械心脏」复活，
## 体内是机械构造，外面还是那副圆滚滚的小孩模样。
## 所以整套特效只讲一条母题：**生命 × 机械 的双重性**，全角色独一份：
##   * 生命侧：脚边草叶、贴地藤蔓、叶片刻度环 —— 全部矢量硬边 + normal，不发光；
##   * 机械侧：胸口齿轮心脏、两条直角回路、方形压力脉冲 —— additive，但形状是几何的；
##   * 两者在「心跳给叶环供能」处交汇：每跳一下，脉冲顺回路压进地面，叶环亮一拍。
##
## 刻意和其它角色拉开距离的地方：
##   * 不做火焰、不做柔光雾、不做上升光尘 / 星屑、不做旋转魔法符文（本文件不调用 star4）；
##   * 地上的草是实色多边形 —— 生命感来自形状和重量，不来自亮度；
##   * 动效性格 = 厚实的守护者：弹跳最低、摇摆最大、步频最慢、压扁最狠、呼吸最深。
##
## 图层与遮挡（关键）：
##   立绘由 EntityView 自身的 _draw 画在 z=0，子层 z<0 会被不透明立绘**整个盖住**。
##   机械心脏只有约 11px，放 z=-3 就彻底看不见 —— 而它是这个角色唯一的标识。
##   所以承载心脏的 additive 层（id 就叫 aura）放在 z=+1；z=-3 的 back 层只画
##   「从剪影边缘溢出来的那圈光」。两者是同一颗心脏的内外两面。
##
## 坐标：原点是脚底中心，向上为负；立绘大致占 y ∈ [-display.y, 0]。

# ============================================================
# 动效参数：厚实的守护者
# ============================================================

## 弹跳很低 —— 他体重，跳不起来；腾空时间短，落地就压。
const M_BOUNCE = 2.6
## 横摆接近上限 —— 胖乎乎的左右晃，是这套动作的辨识点。
const M_WOBBLE = 6.4
## 步频最慢档 —— 一步一顿，绝不轻盈。
const M_STRIDE = 8.6
## 重心横移大，和 wobble 叠成「一整块肉在移动」的感觉。
const M_SWAY = 2.2
## 前倾很小：守护者是站着扛，不是往前冲。
const M_LEAN = 3.4
## 呼吸幅度接近上限：待机时肚子一鼓一鼓。
const M_BREATHE = 0.046
## 呼吸频率很慢：深而缓。
const M_IDLE_RATE = 1.75
## 落地压扁最狠：体重感的主要来源。
const M_SQUASH = 0.28

# ============================================================
# 调色：叶绿为主，暖金齿轮 + 机械青做「机械侧」
# ============================================================

const C_LEAF = Color("9ae6b3")        # 主色叶绿（角色技能色）
const C_LEAF_MID = Color("60bd83")    # 叶片中间调，浅色地板上也读得出来
const C_LEAF_DEEP = Color("2f6b49")   # 草叶 / 藤蔓的暗部，实色不发光
const C_GOLD = Color("e8c27a")        # 暖金：齿轮、铆钉 —— 机械的「零件」色
const C_MECH = Color("7fe3d4")        # 机械青：心脏、回路 —— 机械的「能量」色
const C_CORE = Color("eafffb")        # 轴心的近白点，表示「还在跳」

## 草叶排布表：[横向位置(相对立绘宽), 高度(相对立绘高), 倒向(-1 左 / 1 右)]。
## 写死成表而不是每帧随机：随机数会让草叶抖成噪点；手摆的位置更像一丛真草。
const BLADES = [
	[-0.30, 0.115, -1.0],
	[-0.13, 0.088, 1.0],
	[0.12, 0.124, -1.0],
	[0.27, 0.096, 1.0],
	[0.38, 0.078, 1.0],
]

# 共享径向渐变纹理是否已预热。paint() 里绝不创建纹理，
# 所以只有 _ready() 成功预热后，带贴图的那几笔才允许画。
var _glow_ready := false

# ============================================================
# 生命周期 / 覆写点
# ============================================================

func _ready() -> void:
	super._ready()
	# soft_dot() / ring_tex() 是基类的「一次性生成」共享纹理。
	# 在这里预热，是为了兑现硬性约束：paint() 内不得创建任何纹理 / 渐变 / 材质。
	soft_dot()
	ring_tex()
	_glow_ready = true

## 动效参数。这些数值同时决定 paint() 里的节奏
## （M_BOUNCE 判断「脚是否落地」，M_STRIDE 让扬起的叶子和脚步同拍）。
func motion() -> Dictionary:
	return {
		"bounce": M_BOUNCE,
		"wobble": M_WOBBLE,
		"stride": M_STRIDE,
		"sway": M_SWAY,
		"lean": M_LEAN,
		"breathe": M_BREATHE,
		"idle_rate": M_IDLE_RATE,
		"squash": M_SQUASH,
	}

func layer_specs() -> Array:
	return [
		# 贴地层：草叶 / 藤蔓 / 叶环。normal 混合，硬边，不发光。
		{"id": "ground", "z": -4, "blend": "normal"},
		# 背后层：心脏透过剪影溢出的环境光 + 地面心跳环。它会被立绘挡住大半，
		# 这是故意的 —— 光该从身体里透出来，而不是罩在身体外面。
		{"id": "back", "z": -3, "blend": "add"},
		# 心脏本体。放 z=+1 而不是 -3：11px 的齿轮放在立绘背后等于不存在。
		{"id": "aura", "z": 1, "blend": "add"},
		# 前景层：被脚步踢起的叶子与碎草屑。必须 normal，否则立刻变成「通用光尘」。
		{"id": "front", "z": 2, "blend": "normal"},
		# 护盾壳：只在 cast > 0 时出现，叶甲 + 金铆钉，厚实的实物感。
		{"id": "shell", "z": 3, "blend": "normal"},
	]

func accent_color() -> Color:
	return C_LEAF

## 每帧每层调用。三层守卫：空指针 → 尺寸非法 → 分派。
## display.y <= 0 时所有比例都会算出 0 或负数，后面的除法也会炸，直接退出。
func paint(ci: CanvasItem, layer: String) -> void:
	if ci == null or display.y <= 0.0 or display.x <= 0.0:
		return
	match layer:
		"ground":
			_paint_ground(ci)
		"back":
			_paint_back(ci)
		"aura":
			_paint_heart(ci)
		"front":
			_paint_front(ci)
		"shell":
			_paint_shell(ci)

# ============================================================
# 共享读数
# ============================================================

## energy 只压 additive 层，不压地面草叶：
## 草叶是阿瑞的实体标识，能量再低也不该整圈消失。
func _e() -> float:
	return 0.45 + 0.55 * clampf(energy, 0.0, 1.0)

## 心跳周期。施放「森罗守护」时泵得更急一点，但仍然是沉重的慢心跳。
func _beat_period() -> float:
	return lerpf(1.18, 0.94, clampf(cast, 0.0, 1.0))

## 当前心跳在一个周期里的位置（0..1）。
func _beat_phase() -> float:
	var period := _beat_period()
	if period <= 0.001:
		return 0.0
	return fposmod(t, period) / period

## 心跳包络：两下快搏 + 一段长间歇（咚—咚……）。
## 用心跳而不是 sin 波，是因为「咚」的波形是骤然起、快速落：
## 用 pow 截断出来的尖顶像肌肉 / 活塞，正弦只会像呼吸。
func _beat() -> float:
	var u := _beat_phase()
	var first := pow(maxf(0.0, 1.0 - u * 7.5), 2.4)
	var second := 0.0
	var u2 := u - 0.19
	if u2 >= 0.0:
		second = pow(maxf(0.0, 1.0 - u2 * 8.5), 2.4) * 0.62
	return clampf(0.10 + (first + second) * 0.90, 0.0, 1.0)

## 心脏半径：约立绘高的 7%（≈5.6px）。要「很小」，但小到齿轮齿读不出来就失去意义了；
## 位置贴住原画胸口那枚金色圆徽 —— 心脏就藏在徽章里，这是最短的解释路径。
func _heart_r() -> float:
	return clampf(display.y * 0.072, 4.2, 6.4)

## 脚下叶环的半径。用立绘宽高推，换素材 / 换缩放都不用改数值。
func _ring_rx(grow: float = 1.0) -> float:
	return clampf(display.x * 0.40, 16.0, 40.0) * grow

## 叶环是一圈「躺在地上」的椭圆：y 方向压到 0.34，叶片也必须跟着压扁。
func _ring_ry(grow: float = 1.0) -> float:
	return _ring_rx(grow) * 0.34

## 叶环上的一点：单位圆取角，再按椭圆压扁。
func _ell(a: float, rx: float, ry: float, k: float) -> Vector2:
	return Vector2(cos(a) * rx * k, sin(a) * ry * k)

# ============================================================
# 地面层（z=-4，normal）
# ============================================================

func _paint_ground(ci: CanvasItem) -> void:
	var w := display.x
	var h := display.y
	var c := clampf(cast, 0.0, 1.0)
	var solid := c * c * (3.0 - 2.0 * c)   # smoothstep：起手快、收尾慢 = 「短暂变实」
	var dead := not alive

	# 地面层必须钉在世界地面：pivot 会带着 bob 上下位移，若不平移回来，
	# 草叶会跟着角色一起「飞」，踩地的重量感立刻消失。
	ci.draw_set_transform(Vector2(0.0, -bob), 0.0, Vector2.ONE)

	var rx := _ring_rx()
	var ry := _ring_ry()

	# 1) 被踩实的草地底座：两层压扁椭圆，让叶环有一个「长在土里」的根。
	#    这里是最暗的两笔，负责把亮色草叶从浅色地板上「托」起来。
	MapArt.ellipse(ci, 0.0, -1.0, rx * 0.94, ry * 0.94, Color(0.10, 0.22, 0.15, 0.16))
	MapArt.ellipse(ci, 0.0, -1.4, rx * 0.64, ry * 0.64, Color(0.20, 0.36, 0.24, 0.14))

	# 2) 贴地藤蔓
	_vine(ci, w, c, solid, dead)

	# 3) 草叶：行走被脚掌压弯，站立缓慢舒展
	var press := 0.0
	if moving and not dead:
		# bob 是当前弹跳位移（负 = 在空中）。越接近 0，说明脚刚踩到地。
		press = clampf(1.0 - absf(bob) / maxf(0.001, M_BOUNCE), 0.0, 1.0)
		press = press * press   # 平方：只有真正踩下去那一下才明显
		press *= 0.55 + 0.45 * (0.5 + 0.5 * sin(t * M_STRIDE))   # 左右脚交替
	var open := 0.0
	if not moving and not dead:
		# 待机时草叶极慢地「张—合」，频率只有呼吸的一半：草比人更慢。
		open = 0.5 + 0.5 * sin(t * M_IDLE_RATE * 0.55)
	for i in BLADES.size():
		var row: Array = BLADES[i]
		var side := float(row[2])
		var bx := float(row[0]) * w
		var bh := float(row[1]) * h
		var bw := 2.2 + 0.5 * float(i % 3)
		var sway := sin(t * (0.85 + 0.14 * float(i)) + float(i) * 1.63)
		var lean := side * (1.1 + bh * 0.14 * (0.35 + open)) + sway * 0.85
		# 往局部 -x 压弯。注意：不要乘 facing —— pivot 已经按 facing 镜像过整套子层，
		# 这里再乘一次就是「镜像的镜像」，草会朝反方向倒。
		lean -= press * bh * 0.62
		var height := bh * (1.0 - 0.26 * press)
		if dead:
			# 倒下时草叶外摊：不是枯萎特效，只是「没人踩了」的自然垂落
			lean += side * bh * 0.8
			height *= 0.58
		var col := C_LEAF_MID if i % 2 == 0 else C_LEAF_DEEP
		_blade(ci, Vector2(bx, 0.5), height, bw, lean, _a(col, 0.5 if dead else 0.82))

	# 4) 叶片刻度环：dashed_ellipse 打底 + 7 片朝外叶尖，一起缓慢旋转。
	#    7 是奇数 —— 转起来不会像刻度盘那样机械对称，更像一丛活的草。
	var grow := 0.86 if dead else 1.0 + 0.40 * c + 0.05 * press
	var spin := t * (0.22 + 0.20 * c)
	dashed_ellipse(ci, rx * grow, ry * grow, 7, spin,
		_a(C_LEAF_MID, (0.42 + 0.36 * solid) * (0.45 if dead else 1.0)), 2.0, 0.36)
	var leaf_alpha := (0.52 + 0.34 * solid) * (0.4 if dead else 1.0)
	for i in 7:
		var la := spin + (float(i) + 0.5) * TAU / 7.0
		var b := _ell(la - 0.12, rx * grow, ry * grow, 0.94)
		var s1 := _ell(la - 0.06, rx * grow, ry * grow, 1.02)
		var tp := _ell(la + 0.05, rx * grow, ry * grow, 1.18 + 0.07 * solid)
		var s2 := _ell(la + 0.09, rx * grow, ry * grow, 1.02)
		var col := C_LEAF if i % 2 == 0 else C_LEAF_MID
		ci.draw_colored_polygon(PackedVector2Array([b, s1, tp, s2]), _a(col, leaf_alpha))

	# 5) cast：叶片环向外扩一圈「护盾骨架」，并短暂变实（森罗守护）。
	#    外圈叶片更大、更实，说明护盾是一层有厚度的壳，不是贴图光圈。
	if c > 0.05 and not dead:
		var g2 := 1.0 + 0.62 * c
		MapArt.ellipse(ci, 0.0, -1.0, rx * g2, ry * g2,
			Color(0.42, 0.78, 0.55, 0.08 + 0.10 * solid))
		for i in 5:
			var a := spin * 1.35 + float(i) * TAU / 5.0 + 0.4
			var ob := _ell(a - 0.16, rx * g2, ry * g2, 0.97)
			var os1 := _ell(a - 0.07, rx * g2, ry * g2, 1.00)
			var otp := _ell(a + 0.06, rx * g2, ry * g2, 1.22)
			var os2 := _ell(a + 0.11, rx * g2, ry * g2, 1.00)
			ci.draw_colored_polygon(PackedVector2Array([ob, os1, otp, os2]),
				_a(C_LEAF, 0.26 + 0.34 * solid))
		# 两枚金铆钉：叶环不是魔法阵，是被机械「铆」在地上的
		for i in 2:
			var na := spin * 1.35 + float(i * 2) * TAU / 5.0 + 0.49
			var np := _ell(na, rx * g2, ry * g2, 1.06)
			ci.draw_rect(Rect2(np.x - 1.1, np.y - 1.1, 2.2, 2.2), _a(C_GOLD, 0.55 * c))

	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 贴地藤蔓：6 点折线 + 3 片小叶。cast 时向外多爬 8px，像根系扎出去。
## 只画一条 —— 阿瑞的「生命」是厚实的一丛，不是一整片藤海。
func _vine(ci: CanvasItem, w: float, c: float, solid: float, dead: bool) -> void:
	var reach := clampf(w * 0.20, 9.0, 16.0) + c * 8.0
	var root := Vector2(-w * 0.20, -0.6)
	var wave := 0.0 if dead else 0.55
	var pts := PackedVector2Array()
	for i in 6:
		var u := float(i) / 5.0
		var x := root.x - u * reach
		var y := root.y - sin(u * PI) * (2.2 + c * 1.3) + sin(u * 5.0 + t * 0.9) * wave
		pts.append(Vector2(x, y))
	ci.draw_polyline(pts, _a(C_LEAF_DEEP, (0.85 + 0.08 * solid) * (0.45 if dead else 1.0)), 1.5, true)
	for i in 3:
		var base := pts[1 + i]
		var ang := -2.25 + 0.5 * float(i)
		if not dead:
			ang += sin(t * 0.6 + float(i) * 1.7) * 0.10
		var dir := Vector2(cos(ang), sin(ang))
		var col := C_LEAF_MID if i % 2 == 0 else C_LEAF
		_leaf(ci, base, dir, 4.2 + 0.9 * float(i % 2), 2.4, -0.16, _a(col, 0.4 if dead else 0.72))

# ============================================================
# 背后层（z=-3，additive）
# ============================================================

## 只画「光」，不画光源。它的作用是让心脏看起来真的埋在身体里：
## 光从剪影边缘漏出来，而不是浮在身体表面。
func _paint_back(ci: CanvasItem) -> void:
	if not alive or not _glow_ready:
		return
	var e := _e()
	var beat := _beat()
	var u := _beat_phase()
	var h := display.y
	# 胸口 ≈ -0.38h（与 _paint_heart 同一位置）：再高就压到脸上，洗掉五官。
	var chest := Vector2(0.0, -h * 0.38)
	var r := _heart_r()

	# 地面：心跳每跳一下，一道压扁的软环从脚下扩出去。
	# 用 ring_tex（基类一次性生成的径向渐变）而不是 blur，边缘始终干净。
	var rr := _ring_rx() * 0.35 + r * (2.4 + u * 7.0)
	var ra := pow(maxf(0.0, 1.0 - u * 2.4), 2.0) * 0.20 * e
	ci.draw_set_transform(Vector2(0.0, -bob), 0.0, Vector2(1.0, 0.30))
	ci.draw_texture_rect(ring_tex(), Rect2(-rr, -rr - 6.0, rr * 2.0, rr * 2.0), false, _a(C_MECH, ra))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 脚下生命底光：叶绿，压得很低，只负责把脚和地「接」起来。
	var gr := _ring_rx() * 1.55
	ci.draw_set_transform(Vector2(0.0, -bob), 0.0, Vector2(1.0, 0.32))
	ci.draw_texture_rect(soft_dot(), Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false,
		_a(C_LEAF, (0.10 + 0.05 * beat) * e))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 胸口：心脏透过剪影溢出的青光。大半被立绘挡住，只剩轮廓外的一圈。
	var halo := r * (6.6 + 1.4 * beat)
	ci.draw_texture_rect(soft_dot(), Rect2(chest.x - halo, chest.y - halo, halo * 2.0, halo * 2.0),
		false, _a(C_MECH, (0.05 + 0.055 * beat) * e))

# ============================================================
# 心脏层（id: aura，z=+1，additive）
# ============================================================

## 阿瑞最独特的标识：一颗**机械**心脏，不是法核、不是灵光。
## 「机械」的读法只靠三样东西：齿、轴孔、直角导线 —— 换成黑白也仍然像齿轮。
func _paint_heart(ci: CanvasItem) -> void:
	if not alive:
		return
	var h := display.y
	var w := display.x
	var e := _e()
	var beat := _beat()
	var u := _beat_phase()
	var c := clampf(cast, 0.0, 1.0)
	# 胸口 ≈ -0.38h：阿瑞是「大头小身」的 Q 版比例，头部占了立绘上部将近一半，
	# -0.55h 会正好压在嘴和下巴上，把五官洗掉；-0.38h 才是原画那枚金色圆徽所在的胸腹之间。
	# 不用 body_center()：它是给通用锚点准备的估值，这里直接按立绘比例取更准。
	var chest := Vector2(0.0, -h * 0.38)
	var r := _heart_r()
	var pump := 1.0 + beat * 0.14 + c * 0.10   # 搏动时整颗心胀一点点
	var rr := r * pump

	# 1) 极小一团青光：让齿轮有「在发光」的体积，而不是一张贴纸。
	#    尺寸压在 5 倍半径内，不往外扩散成大光雾。
	if _glow_ready:
		var hr := rr * 5.0
		ci.draw_texture_rect(soft_dot(), Rect2(chest.x - hr, chest.y - hr, hr * 2.0, hr * 2.0),
			false, _a(C_MECH, (0.07 + 0.09 * beat) * e))

	# 2) 齿轮本体：8 齿。先低透明度填一层体积，再用亮线勾一圈齿廓 ——
	#    在 11px 这个尺寸上，勾边比纯色块更能让人一眼认出「这是齿轮」。
	#    每跳一下「咔」地进一格，像被活塞推着转。
	var period := _beat_period()
	var tick := 0.0
	if period > 0.001:
		tick = floor(t / period) * (TAU / 8.0) * 0.10
	_gear(ci, chest, rr, 8, t * 0.5 + tick,
		_a(C_GOLD, (0.20 + 0.28 * beat) * e), _a(C_GOLD, (0.58 + 0.34 * beat) * e))

	# 3) 同心圆：轴孔 + 外圈薄环（齿轮中心的「孔」是机械感的一半）
	_circle(ci, chest, rr * 0.50, _a(C_MECH, (0.34 + 0.44 * beat) * e), 1.1)
	_circle(ci, chest, rr * 1.32, _a(C_MECH, 0.14 + 0.12 * beat), 0.8)

	# 4) 轴心：两个同心实心圆，最里面那颗近白的芯表示「还在跳」。
	#    近白芯刻意压暗：它叠在立绘上，太亮会把胸口的线稿吃掉，整只角色就糊了。
	ci.draw_circle(chest, rr * 0.30, _a(C_MECH, (0.55 + 0.35 * beat) * e))
	ci.draw_circle(chest, rr * 0.12, _a(C_CORE, (0.34 + 0.26 * beat) * e))

	# 5) 方形压力脉冲：雷达 / 活塞的方形波，比圆环更像仪器。只有 1px 细边，
	#    半径只到 ~1.7r 就淡出 —— 它是心口的仪表读数，不是罩住全身的法阵。
	var pr := rr * (1.30 + u * 2.8)
	var pa := pow(maxf(0.0, 1.0 - u * 2.9), 2.2) * 0.26 * e
	if pa > 0.004:
		ci.draw_rect(Rect2(chest.x - pr, chest.y - pr, pr * 2.0, pr * 2.0), _a(C_MECH, pa), false, 1.0)

	# 6) 两条直角回路 + 焊盘 + 沿导线跑向地面的脉冲。
	#    回路全部走直角：机械的接线不会拐优雅的弧。
	var spread := w * 0.33
	var ground_x := _ring_rx() * 0.62
	for sf in [-1.0, 1.0]:
		var side := float(sf)
		var path := PackedVector2Array([
			chest + Vector2(side * rr * 1.10, 0.0),
			Vector2(side * spread * 0.55, chest.y),
			Vector2(side * spread * 0.55, chest.y + h * 0.12),
			Vector2(side * spread * 0.92, chest.y + h * 0.12),
			Vector2(side * spread * 0.92, -h * 0.055),
			Vector2(side * ground_x, -h * 0.055),
			Vector2(side * ground_x, -1.0),
		])
		ci.draw_polyline(path, _a(C_MECH, (0.15 + 0.15 * beat) * e), 1.0, true)
		var endp: Vector2 = path[path.size() - 1]
		# 末端焊盘：方点。机械的节点不长成星星 —— 这也是本文件不用 star4 的原因。
		ci.draw_rect(Rect2(endp.x - 1.3, endp.y - 1.3, 2.6, 2.6), _a(C_MECH, 0.26 + 0.28 * beat))
		# 心跳把一枚脉冲压到地下：机械心脏在给地面的叶环供能。
		# 这是本角色唯一的「设定动作」，也把生命侧和机械侧缝在一起。
		if u < 0.55:
			var shape := u / 0.55
			var pp := _path_point(path, shape)
			ci.draw_rect(Rect2(pp.x - 1.0, pp.y - 1.0, 2.0, 2.0), _a(C_GOLD, 0.60 * (1.0 - shape)))

# ============================================================
# 前景层（z=+2，normal）
# ============================================================

## 被脚步踢起的叶子与碎草屑。刻意用 normal 混合：
## 发光的小叶子会立刻变成「通用光尘」，而阿瑞扬起来的是实实在在的草。
func _paint_front(ci: CanvasItem) -> void:
	if not alive or not moving:
		return
	var h := display.y
	var w := display.x
	var e := _e()
	# 步相位：EntityView 的弹跳是 -|sin(t*stride)|，脚落地在相位 0 与 π。
	# 用同一频率换算「第几步」，叶子才会一步一扬，而不是自己乱飘。
	var step_t := t * M_STRIDE / PI
	var step_n := int(floor(step_t))
	var p := step_t - float(step_n)
	var side := -1.0 if step_n % 2 == 0 else 1.0

	# 两片叶子错开半个周期：脚边永远有 1~2 片在翻。
	for i in 2:
		var q := fposmod(step_t * 0.5 + float(i) * 0.5, 1.0)
		var s := side if i == 0 else -side
		var life := sin(q * PI)
		if life <= 0.02:
			continue
		var x := s * w * 0.20 - q * (8.0 + 4.0 * float(i))
		var y := -1.0 - life * (h * 0.13) + q * q * 3.0
		var dir := Vector2(-0.55 - 0.25 * q, -1.0).normalized()
		var length := 4.6 + 1.1 * float(i % 2)
		var col := C_LEAF if i == 0 else C_LEAF_MID
		_leaf(ci, Vector2(x, y), dir, length * (0.82 + 0.18 * life), 2.6, 0.22 * s,
			_a(col, 0.86 * life * e))
		# 叶脉：一根深色硬线。有脉才像叶子，否则只是一颗绿点。
		ci.draw_line(Vector2(x, y), Vector2(x, y) + dir * length * 0.70,
			_a(C_LEAF_DEEP, 0.5 * life * e), 1.0, true)

	# 落地那一下崩起来的碎草屑：三片极小的硬边三角，只存在于每步的前 22%。
	if p < 0.22:
		var burst := p / 0.22
		var fade := 1.0 - burst
		for k in 3:
			var ang := -0.35 - 0.42 * float(k)
			var dist := 3.0 + burst * (6.5 + float(k))
			var cx := side * (w * 0.12 + cos(ang) * dist)
			var cy := -1.0 - sin(ang) * dist * 0.55 - sin(burst * PI) * 1.4
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 1.0, cy + 1.2),
				Vector2(cx, cy - 1.8),
				Vector2(cx + 0.9, cy + 0.9),
			]), _a(C_LEAF_DEEP, fade * 0.62 * e))

# ============================================================
# 护盾壳（z=+3，normal）
# ============================================================

## 「森罗守护」的实物壳：7 片叶甲沿壳沿朝外，隔一片换色，再用 3 枚金铆钉铆住。
## 不用半透明光球 —— 他的技能就是护盾，护盾应该有厚度、有拼接、有零件。
## cast <= 0.04 时整层直接 return，待机零开销。
func _paint_shell(ci: CanvasItem) -> void:
	if not alive:
		return
	var c := clampf(cast, 0.0, 1.0)
	if c <= 0.04:
		return
	var h := display.y
	var w := display.x
	var solid := c * c * (3.0 - 2.0 * c)
	var cy := -h * 0.45
	var rx := w * 0.64 + 3.0 * c
	var ry := h * 0.54 + 3.0 * c
	if rx <= 1.0 or ry <= 1.0:
		return

	# 1) 极淡填色：只是让壳有体积，alpha 压在 0.12 以下，人物始终清楚。
	MapArt.ellipse(ci, 0.0, cy, rx, ry, Color(0.42, 0.78, 0.55, 0.045 + 0.075 * solid))

	# 2) 壳沿：18 段实体细线。它是「边」，不是柔光边缘。
	var rim := PackedVector2Array()
	for i in 19:
		var a := float(i) / 18.0 * TAU
		rim.append(Vector2(cos(a) * rx, cy + sin(a) * ry))
	ci.draw_polyline(rim, _a(C_LEAF, 0.30 + 0.40 * solid), 1.2, true)

	# 3) 7 片叶甲：沿壳沿朝外，像一圈拼起来的鳞甲。
	for i in 7:
		var a := -PI * 0.5 + float(i) * TAU / 7.0 + 0.12
		var p := Vector2(cos(a) * rx, cy + sin(a) * ry)
		var n := Vector2(cos(a) / maxf(rx, 1.0), sin(a) / maxf(ry, 1.0)).normalized()
		var tg := Vector2(-n.y, n.x)
		var base := p - n * 1.2
		var mid := p + n * 2.4
		var tip := p + n * (6.2 + 1.4 * solid)
		var col := _a(C_LEAF if i % 2 == 0 else C_LEAF_MID, 0.16 + 0.26 * solid)
		ci.draw_colored_polygon(PackedVector2Array([
			base,
			mid + tg * 2.0,
			tip + tg * 0.6,
			tip - tg * 0.6,
			mid - tg * 2.0,
		]), col)

	# 4) 3 枚金铆钉：护盾的接缝也是机械的，和心口的齿轮是同一套零件。
	for i in 3:
		var ba := -PI * 0.5 + float(i * 2) * TAU / 7.0 + 0.12
		var bp := Vector2(cos(ba) * rx, cy + sin(ba) * ry)
		ci.draw_rect(Rect2(bp.x - 1.2, bp.y - 1.2, 2.4, 2.4), _a(C_GOLD, 0.30 + 0.45 * solid))

# ============================================================
# 图元（全部是自带的矢量构造，paint 内不生成任何资源）
# ============================================================

## 给颜色换一个 alpha。显式拼 r/g/b：避免 Color(Color, float) 构造在不同版本里的歧义。
func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(alpha, 0.0, 1.0))

## 极坐标点。
func _pol(a: float, c: Vector2, r: float) -> Vector2:
	return Vector2(c.x + cos(a) * r, c.y + sin(a) * r)

## 齿轮剪影：每个齿 4 个点（齿根 → 齿顶 → 齿顶 → 齿根），整圈只占 1 个填充调用。
## 比「8 个矩形拼齿」省 7 次绘制，也避免小尺寸下矩形之间露缝。
## line_color 有 alpha 时再补一圈齿廓（+1 调用），尺寸很小时靠它读出「齿」。
func _gear(ci: CanvasItem, c: Vector2, r: float, teeth: int, rot: float,
		fill_color: Color, line_color: Color = Color.TRANSPARENT) -> void:
	if r <= 0.2 or (fill_color.a <= 0.004 and line_color.a <= 0.004) or teeth < 3:
		return
	var pts := PackedVector2Array()
	var step := TAU / float(teeth)
	for i in teeth:
		var a0 := rot + float(i) * step
		pts.append(_pol(a0 + step * 0.04, c, r * 0.70))
		pts.append(_pol(a0 + step * 0.15, c, r))
		pts.append(_pol(a0 + step * 0.33, c, r))
		pts.append(_pol(a0 + step * 0.44, c, r * 0.70))
	if fill_color.a > 0.004:
		ci.draw_colored_polygon(pts, fill_color)
	if line_color.a > 0.004:
		pts.append(pts[0])
		ci.draw_polyline(pts, line_color, 1.0, true)

## 细圆环（同心圆 / 轴孔）。段数按半径自适应，小圆不浪费顶点。
func _circle(ci: CanvasItem, c: Vector2, r: float, color: Color, width: float) -> void:
	if r <= 0.05 or color.a <= 0.004:
		return
	var seg := clampi(int(r * 2.2) + 8, 10, 22)
	var pts := PackedVector2Array()
	for i in seg + 1:
		var a := float(i) / float(seg) * TAU
		pts.append(Vector2(c.x + cos(a) * r, c.y + sin(a) * r))
	ci.draw_polyline(pts, color, width, true)

## 一片叶子：从 base 沿 dir 长 length，宽 width，bend 让叶尖弯出去。
## 4 点风筝形，硬边，一次 draw_colored_polygon —— 小尺寸也不会糊。
func _leaf(ci: CanvasItem, base: Vector2, dir: Vector2, length: float, width: float,
		bend: float, color: Color) -> void:
	if length <= 0.2 or color.a <= 0.004:
		return
	var d := dir
	if d.length_squared() < 0.0001:
		d = Vector2.UP
	else:
		d = d.normalized()
	var n := Vector2(-d.y, d.x)
	var hw := maxf(0.4, width * 0.5)
	var mid := base + d * (length * 0.44) + n * (bend * length * 0.55)
	var tip := base + d * length + n * (bend * length)
	ci.draw_colored_polygon(PackedVector2Array([
		base,
		mid + n * hw - d * (hw * 0.25),
		tip,
		mid - n * hw + d * (hw * 0.15),
	]), color)

## 草叶：5 点锥形多边形，根宽尖窄；lean 是叶尖的横向偏移（负 = 往左倒）。
func _blade(ci: CanvasItem, base: Vector2, height: float, width: float, lean: float,
		color: Color) -> void:
	if height <= 0.3 or color.a <= 0.004:
		return
	var hw := maxf(0.5, width * 0.5)
	var mid := base + Vector2(lean * 0.34, -height * 0.55)
	var tip := base + Vector2(lean, -height)
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-hw, 0.5),
		mid + Vector2(-hw * 0.70, 0.0),
		tip,
		mid + Vector2(hw * 0.58, 0.0),
		base + Vector2(hw, 0.5),
	]), color)

## 折线上按弧长取点（回路的脉冲沿导线走）。先累加总长，避免每段重复求和。
func _path_point(pts: PackedVector2Array, u: float) -> Vector2:
	if pts.size() == 0:
		return Vector2.ZERO
	if pts.size() == 1:
		return pts[0]
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	if total <= 0.001:
		return pts[0]
	var target := clampf(u, 0.0, 1.0) * total
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if seg <= 0.0001:
			continue
		if acc + seg >= target:
			return pts[i - 1].lerp(pts[i], (target - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]
