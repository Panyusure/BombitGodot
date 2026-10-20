extends "res://scripts/char_fx/CharAura.gd"

## 小炎 · 力量之王（龙炎的幼年形态）—— 不灭龙魂 / 双龙虚影 / 扬起的火星。
##
## 基类只管建层、推进时间、共享纹理；这里只回答两件事：
## 「小炎长什么样」和「小炎怎么动」。三层全部 additive：
##   aura  (z=-4) 灼热地气 + 盘绕的龙魂脊椎。压在立绘之后，只从轮廓外沿“漏”出来，
##                所以它是“魂在人身后的暗火”，不是一圈把人包住的发光特效。
##   front (z=1)  身体两侧的双龙虚影（点题「驭乘双龙」），随呼吸开合。
##   spark (z=2)  脚下升起的余烬火星（熔金 → 橙红 → 暗红），每颗带一小段拖尾。
##
## 视觉语汇：全部是矢量硬边（13 点折线 / 三角背鳍 / 楔形龙首 / 菱形火星 / 细环），
## 柔光只借用基类一次性生成的径向渐变纹理（soft_dot）做地气。没有 blur、没有后处理、
## 没有 SubViewport、没有 spritesheet —— 小炎的“魂”是画出来的。
##
## 配色只走暖区：橙红 #ffb278 / 熔金 #ffd45e / 暗红余烬 #c0392b。
## 不用绿、不用蓝光：那会把“浴龙血而生”的火魂稀释成通用的元素光效。
##
## 坐标系：pivot 已按 facing 做过 x 轴 -1 翻转，所以本文件里局部 +x 恒等于角色正面。
## 所有前后偏移一律写死正号，绝不再乘 facing / 侧向系数 —— 否则左走时整条龙影会被
## 甩到背后。这是本文件唯一刻意不碰 facing 的地方，也是唯一需要记住的契约。

const FLAME := Color("#ffb278")      # 主色：橙红
const GOLD := Color("#ffd45e")       # 点缀：熔金（只给火星头、龙角、地气细环）
const EMBER := Color("#c0392b")      # 暗红余烬（龙下颌、尾鳍、地气裂纹）
const SOUL_CORE := Color("#ffe9bd")  # 龙眼的一丝芯白：整条龙魂唯一的高光点

const SPARK_COUNT := 7               # 火星 5~9 颗：宁少勿多，铺满就成通用粒子了
const DRAGON_STEPS := 12             # 龙魂脊椎采样段数（13 个折点）
const WAVE_PERIOD := 3.0             # 待机蓄力周期（秒）

# ---------------------------------------------------------------- 覆写点

## 小炎是「爆发的少年」：全队最高的弹跳、最快的步频、最大的前倾与压扁。
## 八个值全部顶在各自区间的上沿，和沉稳型（未来 / 阿瑞）刻意拉开距离。
## 注意 bounce / squash 的因果关系：弹得越高，落地时 squash 越明显，
## 两个值必须一起大，否则会出现“弹得高但落地发飘”的假感。
func motion() -> Dictionary:
	return {
		"bounce": 5.4,      # 1.5~5.5：几乎弹离地面半个身位
		"wobble": 6.3,      # 1~7：落地时左右甩得最狠
		"stride": 13.6,     # 8~14：脚几乎不落地，步频快
		"sway": 2.3,        # 0~2.5：重心左右换得很凶，像在横冲
		"lean": 7.5,        # 0~8：明显前倾，随时要冲出去
		"breathe": 0.048,   # 0.012~0.05：待机也在大口喘，站不住
		"idle_rate": 3.15,  # 1.6~3.4：呼吸偏快，和 3 秒蓄力周期错开
		"squash": 0.285,    # 0.08~0.30：落地压得最扁
	}

## 三层：地气与龙魂在立绘后，双龙虚影与火星在前。
## 都走 add：魂火是加法，浅色地砖上只会提亮、不会糊掉立绘的墨线。
func layer_specs() -> Array:
	return [
		{"id": "aura", "z": -4, "blend": "add"},
		{"id": "front", "z": 1, "blend": "add"},
		{"id": "spark", "z": 2, "blend": "add"},
	]

## 菜单 / HUD 取色用：小炎的主色。
func accent_color() -> Color:
	return FLAME

func _ready() -> void:
	super()
	# 基类的 soft_dot() 是「首次调用才生成」的懒加载静态纹理。
	# 在这里提前触发一次，保证 paint() 执行期间绝不会发生纹理 / 渐变 / 材质创建 ——
	# 这样“paint 内禁止生成资源”的约束不是靠自觉，而是结构上就不可能违反。
	soft_dot()

# ---------------------------------------------------------------- 绘制分发

func paint(ci: CanvasItem, layer: String) -> void:
	# display 由 configure() 在立绘尺寸确定后写入；y<=0 说明还没配好，
	# 此时任何按身高的比例计算都会退化成 0，画出来只是一堆原点上的碎点。
	if display.y <= 0.0:
		return
	# 基类约定的省算法：静止且能量几乎归零时整层跳过（死亡镜头 / 远景淡化时生效）。
	if energy <= 0.03 and not moving:
		return
	match layer:
		"aura":
			_paint_aura(ci)
		"front":
			_paint_front(ci)
		"spark":
			_paint_spark(ci)

# ================================================================
# aura 层：灼热地气 + 不灭龙魂（约 23 个绘制调用）
# ================================================================

func _paint_aura(ci: CanvasItem) -> void:
	var h := display.y
	var w := maxf(display.x, 8.0)   # display.x 为 0 时退化成一条细线，也绝不参与除零
	# 立绘占位不是 [0, h]：顶边 = -h*anchor.y，底边 = h*(1-anchor.y)
	# （小炎 anchor.y = 0.97，底边落在地面下约 2px，属美术留白）。
	# 龙首的抬头高度必须按顶边算，否则会固定比角色头顶高出一截，像飘在别处。
	var top := h * clampf(anchor.y, 0.60, 1.0)
	var e := clampf(energy, 0.0, 1.0)
	var c := clampf(cast, 0.0, 1.0)
	var land := _land()
	var wave := 0.0 if moving else _charge_wave()
	var press := clampf(-wave, 0.0, 1.0)   # 蓄力：身体沉下去
	var pop := clampf(wave, 0.0, 1.0)      # 回弹：蹭地弹起来
	var beat := 0.5 + 0.5 * sin(t * 5.2 + 0.6)   # 心跳：魂火跳得比呼吸快一倍多
	var amp := (0.55 + 0.45 * e) * (1.0 + 0.45 * c) * (1.0 if alive else 0.30)
	# 和 motion().idle_rate 同频：立绘的呼吸与脚下地气同步起伏，不会各喘各的
	var breath := 1.0 + 0.05 * sin(t * 3.15)

	# ---- 灼热地气（一）：脚下那圈极淡的橙红光池 --------------------------
	# 半径吃 land（落地摊开）与 press（蓄力时被压扁）。小炎的“重”必须先落在地上，
	# 否则 5.4px 的弹跳在画面上只是个上下平移，没有重量感。
	var pool_rx := w * (0.50 + 0.08 * land + 0.06 * c) * (1.0 - 0.10 * press)
	var pool_ry := (4.4 + 2.6 * land) * (1.0 - 0.20 * press) * breath
	var pool_a := (0.065 + 0.055 * land + 0.07 * c) * amp * (0.72 + 0.28 * beat)
	ci.draw_texture_rect(soft_dot(),
			Rect2(-pool_rx, -pool_ry - 0.6, pool_rx * 2.0, pool_ry * 2.0), false,
			Color(FLAME.r, FLAME.g * 0.90, FLAME.b * 0.78, pool_a))

	# ---- 灼热地气（二）：一圈硬边细环，压住光池边缘 -----------------------
	# 只靠渐变纹理会糊成一团暖色雾；一根 1px 的环把“地面”重新钉住。
	var ring_rx := pool_rx * 0.88
	var ring_ry := pool_ry * 0.86
	MapArt.ellipse_stroke(ci, 0.0, -0.6, ring_rx, ring_ry,
			Color(GOLD.r, GOLD.g * 0.92, GOLD.b * 0.70, (0.085 + 0.075 * land) * amp), 1.0)

	# ---- 灼热地气（三）：六段缓慢转动的断续裂纹 --------------------------
	# 相位只跟 t 走、不掺随机数：脚下极稳、身上极躁，这个反差就是小炎的性格。
	dashed_ellipse(ci, ring_rx * 1.16, ring_ry * 1.12, 6, t * 0.35,
			Color(EMBER.r, EMBER.g, EMBER.b, 0.085 * amp), 1.0, 0.30)

	# ---- 待机蓄力的“微弹”：一枚向外弹开的地气冲击环 ----------------------
	# 立绘位移归 EntityView 管，氛围层不抢它的活；但回弹必须被看见，
	# 所以用“地面被踩出一圈冲击”来表达，而不是让光效自己蹦一下。
	if pop > 0.03 and not moving:
		var rr := ring_rx * (0.92 + 0.42 * pop)
		MapArt.ellipse_stroke(ci, 0.0, -0.6, rr, ring_ry * (0.78 + 0.55 * pop),
				Color(GOLD.r, GOLD.g * 0.86, GOLD.b * 0.52, 0.12 * pop * amp), 1.0)

	# ---- 不灭龙魂：一条盘绕的脊椎 ----------------------------------------
	var pts := _coil_points(w, top, press, pop)
	var n := pts.size()
	if n < 3:
		return
	# 硬约束：整条龙魂透明度 ≤0.30。它画在立绘**之后**（z=-4），提亮不会吃到五官，
	# 但也不能做成一贴就糊的光雾——魂是“后面有东西”，不是“前面贴了张画”。
	var dragon_a := clampf((0.175 + 0.075 * c) * amp, 0.0, 0.30)

	var nrms := PackedVector2Array()
	for i in n:
		var tangent := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var nv := Vector2(0.0, 1.0)
		if tangent.length() > 0.001:
			tangent = tangent.normalized()
			nv = Vector2(-tangent.y, tangent.x)
		nrms.append(nv)

	# 龙身：一条粗细变化的实心多边形（中段是胸腹，两端收成颈与尾）。
	# 这是“不能画成光带”的关键——光带是等宽的，生物是鼓的。
	# 半宽上限 1.6px，小于折线的最小曲率半径，不会自交折出难看的尖角。
	var half_k := 1.0 + 0.15 * c
	var poly := PackedVector2Array()
	for i in n:
		var u := float(i) / float(n - 1)
		poly.append(pts[i] + nrms[i] * (0.45 + 0.95 * sin(PI * u)) * half_k)
	for i in range(n - 1, -1, -1):
		var ur := float(i) / float(n - 1)
		poly.append(pts[i] - nrms[i] * (0.45 + 0.95 * sin(PI * ur)) * half_k)
	ci.draw_colored_polygon(poly, Color(FLAME.r, FLAME.g * 0.72, FLAME.b * 0.50, dragon_a))

	# 脊椎：一根 1px 的亮芯从龙身正中穿过，给多边形一条“骨头”。
	ci.draw_polyline(pts, Color(GOLD.r, GOLD.g, GOLD.b * 0.82, dragon_a * 0.95), 1.0, true)

	# 六枚三角背鳍：交替朝两侧长。它们是“分段”的唯一来源——
	# 去掉这六笔，剩下的就是一条会游的线；有了它们，才是一条会呼吸的脊椎。
	for k in 6:
		var idx := int(round(lerpf(0.16, 0.90, float(k) / 5.0) * float(n - 1)))
		var p := pts[idx]
		var tv := pts[mini(idx + 1, n - 1)] - pts[maxi(idx - 1, 0)]
		if tv.length() <= 0.001:
			continue
		tv = tv.normalized()
		var tvn := Vector2(-tv.y, tv.x)
		if k % 2 == 1:
			tvn = -tvn   # 一左一右地翻出来，像鳞片在盘绕时被顶起
		var tip := p + tvn * (2.4 + 0.9 * sin(float(k) * 1.7 + t * 2.2)) - tv * 0.8
		ci.draw_colored_polygon(PackedVector2Array([p - tv * 2.0, p + tv * 2.0, tip]),
				Color(FLAME.r, FLAME.g * 0.80, FLAME.b * 0.55, dragon_a * 0.85))

	# ---- 龙首：三笔硬边（楔形颅骨 + 暗红下颌 + 后掠双角）+ 一枚 1px 龙眼 ----
	var head := pts[n - 1]
	var htan := pts[n - 1] - pts[n - 2]
	if htan.length() <= 0.001:
		htan = Vector2(1.0, -0.4)   # 退化时朝局部 +x（正面）探，与整体前倾一致
	htan = htan.normalized()
	var hnv := Vector2(-htan.y, htan.x)
	ci.draw_colored_polygon(PackedVector2Array([
		head + htan * 5.4,
		head + htan * 1.2 + hnv * 2.4,
		head - htan * 2.0 + hnv * 1.5,
		head - htan * 2.4 - hnv * 1.5,
		head + htan * 1.0 - hnv * 2.1,
	]), Color(FLAME.r, FLAME.g * 0.74, FLAME.b * 0.52, dragon_a))
	ci.draw_colored_polygon(PackedVector2Array([
		head + htan * 1.8 - hnv * 1.2,
		head + htan * 6.0 - hnv * 0.8,
		head + htan * 3.2 - hnv * 0.1,
	]), Color(EMBER.r, EMBER.g, EMBER.b, dragon_a * 0.90))
	ci.draw_polyline(PackedVector2Array([
		head - htan * 1.2 + hnv * 1.7,
		head - htan * 4.2 + hnv * 3.3,
		head - htan * 5.3 + hnv * 2.3,
	]), Color(GOLD.r, GOLD.g, GOLD.b * 0.62, dragon_a * 0.95), 1.0, true)
	ci.draw_circle(head + htan * 2.4 + hnv * 0.8, 0.9,
			Color(SOUL_CORE.r, SOUL_CORE.g, SOUL_CORE.b, minf(0.22, dragon_a * 1.5)),
			true, -1.0, true)

	# ---- 尾鳍：两片极窄的三角，t 驱动的甩尾（不用随机数，节奏可被记住）------
	var tail := pts[0]
	var tdir := pts[0] - pts[1]
	if tdir.length() <= 0.001:
		tdir = Vector2(0.0, 1.0)
	tdir = tdir.normalized()
	# 尾鳍只往上、往两侧张：龙尾收在脚边，任何一片都不能戳进地面（y>0）里，
	# 所以旋完再叠一个向上偏置，而不是让两片鳍跟着切线往地下甩。
	var flick := sin(t * 3.6) * 0.5
	for s in 2:
		var ang := (0.62 + flick) * (1.0 if s == 0 else -1.0)
		var d1 := (tdir.rotated(ang) + Vector2(0.0, -0.90)).normalized()
		var d2 := (tdir.rotated(ang * 0.32) + Vector2(0.0, -0.90)).normalized()
		ci.draw_colored_polygon(PackedVector2Array([tail, tail + d1 * 4.2, tail + d2 * 3.4]),
				Color(EMBER.r, EMBER.g, EMBER.b, dragon_a * 0.80))

# ================================================================
# front 层：双龙虚影（约 8 个绘制调用）
# ================================================================

func _paint_front(ci: CanvasItem) -> void:
	var h := display.y
	var w := maxf(display.x, 8.0)
	# 与 aura 层同一套占位换算：肩高按立绘顶边取，不按 display.y 硬算。
	var top := h * clampf(anchor.y, 0.60, 1.0)
	var e := clampf(energy, 0.0, 1.0)
	var c := clampf(cast, 0.0, 1.0)
	var wave := 0.0 if moving else _charge_wave()
	var press := clampf(-wave, 0.0, 1.0)
	var pop := clampf(wave, 0.0, 1.0)
	# 开合频率：静止时和 motion().idle_rate 同频（跟着呼吸一张一合），
	# 走动时切到更快的扑动 —— 双龙是被甩在身后的，不是装饰挂件。
	var rate := 4.4 if moving else 3.15
	var open := 0.5 + 0.5 * sin(t * rate + 0.4)
	var amp := (0.55 + 0.45 * e) * (1.0 + 0.35 * c) * (1.0 if alive else 0.30)
	# 压在立绘之上，所以位移、透明度都必须克制：脸与胸口永远留空。
	var base_y := -top * 0.62 + pop * 1.8 - press * 1.6
	var out := w * (0.40 + 0.045 * open + 0.055 * c)
	var fa := clampf((0.10 + 0.05 * open + 0.06 * c) * amp, 0.0, 0.22)

	for s in 2:
		var sgn := -1.0 if s == 0 else 1.0
		var bx := out * sgn
		# 两段折线的颈：从腋下斜着探出，蓄力下压时一起沉，回弹时甩起来。
		var neck := PackedVector2Array([
			Vector2(bx * 0.55, base_y + 3.4),
			Vector2(bx * 0.88, base_y - 1.4 - open * 1.2),
			Vector2(bx + 1.2 * sgn, base_y - 3.2 - open * 2.0),
		])
		ci.draw_polyline(neck, Color(FLAME.r, FLAME.g * 0.86, FLAME.b * 0.62, fa), 1.4, true)
		var tip: Vector2 = neck[2]
		var dir := Vector2(sgn, -0.35).normalized()   # 朝外、略朝上：扬着头的姿态
		var up := Vector2(-dir.y, dir.x)
		# 一块三角当吻部：极简到只剩“朝外的尖”，但轮廓是硬的。
		ci.draw_colored_polygon(PackedVector2Array([
			tip + dir * (3.4 + 1.3 * open),
			tip + up * 2.3,
			tip - up * 1.9,
		]), Color(GOLD.r, GOLD.g * 0.84, GOLD.b * 0.55, minf(0.18, fa * 1.05)))
		# 一根后掠的角线：把“三角”从箭头读成龙首。
		ci.draw_line(tip - up * 0.5, tip - dir * 3.2 + up * 2.5,
				Color(GOLD.r, GOLD.g, GOLD.b * 0.72, minf(0.16, fa * 0.85)), 1.0, true)
		if c > 0.12:
			# 「炎灭火舞」施放中：龙口张开一道短裂口，暗示它在吞爆炸。
			ci.draw_line(tip + dir * 0.8, tip + dir * (4.2 + 1.8 * c) - up * 0.5,
					Color(EMBER.r, EMBER.g, EMBER.b, 0.22 * c * amp), 1.0, true)

# ================================================================
# spark 层：扬起的火星（约 14 个绘制调用）
# ================================================================

func _paint_spark(ci: CanvasItem) -> void:
	if not alive:
		return   # 人倒下就不再扬火星：龙魂留着，余烬先散
	var e := clampf(energy, 0.0, 1.0)
	var c := clampf(cast, 0.0, 1.0)
	var amp := (0.45 + 0.55 * e) * (1.0 + 0.25 * c)
	var wave := 0.0 if moving else _charge_wave()
	var pop := clampf(wave, 0.0, 1.0)
	# 回弹那一下把火星甩得更高：蓄力与火星共用同一条曲线，因果才成立，
	# 否则“压一下”和“火星窜一下”只是两个凑巧同框的动画。
	var lift := 1.0 + 0.20 * pop + 0.28 * c

	for i in SPARK_COUNT:
		# 相位 = t × 每颗自己的速度 + 无理数错位：循环但不同步，绝不是一排在齐步走。
		var life := fposmod(t * (0.34 + 0.05 * float(i % 3)) + float(i) * 0.618, 1.0)
		var fade := sin(clampf(life, 0.0, 1.0) * PI)   # 出生与消亡都归零
		if fade <= 0.02:
			continue
		# 颜色沿“生命”走：刚溅起是熔金，中段橙红，尾端暗红 —— 一颗火星自带色阶。
		var hot := GOLD.lerp(FLAME, clampf(life * 1.5, 0.0, 1.0))
		var cold := FLAME.lerp(EMBER, clampf(0.25 + life * 1.1, 0.0, 1.0))

		# 拖尾：沿同一轨迹回采样 4 点，顶点色从熔金渐变到暗红。
		# 用 draw_polyline_colors 一次画完，而不是四根线 —— 省调用，也让颜色是连续的。
		var trail := PackedVector2Array()
		var cols := PackedColorArray()
		for k in 4:
			trail.append(_ember_pos(i, maxf(life - float(k) * 0.052, 0.0), lift))
			var col := hot.lerp(cold, float(k) / 3.0)
			col.a = 0.46 * fade * amp * (1.0 - float(k) / 4.6)
			cols.append(col)
		ci.draw_polyline_colors(trail, cols, 1.5, true)

		# 火星头：一枚小菱形。圆点会立刻把它拉回“通用粒子”，硬边才接得住小炎的矢量语言。
		var p := trail[0]
		var r := 1.2 + 0.5 * (1.0 - life)
		ci.draw_colored_polygon(PackedVector2Array([
			p + Vector2(0.0, -r), p + Vector2(r * 0.7, 0.0),
			p + Vector2(0.0, r), p + Vector2(-r * 0.7, 0.0),
		]), Color(hot.r, hot.g, hot.b, minf(0.75, 0.62 * fade * amp)))

# ================================================================
# 曲线与几何
# ================================================================

## 龙魂脊椎的 13 个折点：从脚边一路盘到头侧。
## 两个 sin 谐波叠加——低频是“整条龙在游”，高频是“脊椎在扭”。
## 叠加后没有任何一段是等距的，读起来才像活物；单一正弦会立刻暴露成弹簧。
func _coil_points(w: float, top: float, press: float, pop: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# 前倾剪切：局部 +x 就是正面，所以恒为正（与 motion().lean 的 7.5° 同向，这里取 ≈5.7°）。
	var shear := 0.10
	var squash := 1.0 - 0.06 * press + 0.04 * pop   # 下压时整条龙一起沉，回弹时抻开
	var span := maxf(top - 4.0, 6.0)   # 尾巴离地 4px 起、龙头正好停在立绘顶边
	for i in range(DRAGON_STEPS + 1):
		var u := float(i) / float(DRAGON_STEPS)
		# 三角包络：尾与头收在中轴附近，中段才鼓出立绘轮廓 → 读感是“绕着人盘”。
		# 若全程等幅，它会变成背后一条平行的波浪线，跟角色没有任何缠绕关系。
		var env := pow(1.0 - absf(u * 2.0 - 1.0), 0.85)
		var coil := sin(u * 6.6 - t * 1.05) * 0.42 + sin(u * 2.7 + t * 0.52 + 0.8) * 0.13
		var x := (coil * env + 0.06) * w
		# 龙头往侧前方探出去（驭乘双龙的“首”）：蓄力时缩回来，回弹时再探出去。
		x += 0.27 * pow(u, 3.4) * (1.0 - 0.30 * press + 0.18 * pop) * w
		# 脚边贴地 → 肩上一口气冲到顶：pow 让下半身慢、上半身快，尾巴才不会飘起来。
		# 起点留 4px 离地：尾巴正好泡在脚下的地气里，同时给尾鳍留下张开的余量，
		# 两片鳍无论怎么甩都不会戳进地面（y>0）去。
		var y := (-4.0 - pow(u, 1.20) * span) * squash
		x += (-y) * shear
		pts.append(Vector2(x, y))
	return pts

## 第 idx 颗火星在生命进度 life 时的位置。
## 纯函数、不留状态：paint 每帧重算，所以不需要任何每帧缓存 / 随机种子。
func _ember_pos(idx: int, life: float, lift: float) -> Vector2:
	var w := maxf(display.x, 8.0)
	var top := display.y * clampf(anchor.y, 0.60, 1.0)
	var f := float(idx)
	# 用无理数步长错开起点与上升高度代替 randf()：每帧可复现，拖尾才能沿轨迹回采样。
	var x0 := sin(f * 2.39 + 0.7) * w * 0.30
	var rise := top * (0.58 + 0.30 * fposmod(f * 0.618, 1.0)) * lift
	var drift := sin(life * 4.4 + f * 1.9) * 3.2
	# +2.4 是局部 +x（角色正面）：火星被前冲的势头拖着往前飘，绝不乘 facing。
	var p := Vector2(x0 + drift + life * 2.4, -2.0 - life * rise)
	# 施放「炎灭火舞」时火星被龙口吸回胸口：同一套粒子，“扬”与“吸”两种戏。
	var c := clampf(cast, 0.0, 1.0)
	if c > 0.01:
		p = p.lerp(Vector2(0.0, -top * 0.52), c * 0.45)
	return p

## 落地冲击 0..1。bob 是基类给的当前弹跳位移（负 = 向上）：
## 越接近 0 越是刚踩实地面。小炎“落得重”全靠这个值去撑开地气与火星。
func _land() -> float:
	var v := clampf(1.0 + bob / 6.0, 0.0, 1.0)
	return v if moving else v * 0.30

## 待机蓄力：周期 3 秒的「下压 → 微弹」。
## 基频 + 2/3 次谐波叠加，波形被掰成不对称：压得慢、弹得急，末尾还有一个很小的回弹。
## 全程不用随机数 —— 每次循环一模一样，玩家能记住这个节奏（记忆点 > 惊喜）。
func _charge_wave() -> float:
	var w := TAU / WAVE_PERIOD
	return sin(w * t) - 0.46 * sin(2.0 * w * t + 1.85) + 0.15 * sin(3.0 * w * t + 0.55)
