extends "res://scripts/char_fx/CharAura.gd"

## 阿修（axiu）· 暗影氛围层 —— 只画「影、刃、瞳、雾」四件事。
##
## 考据：修尔的幼年形态，神暗 / 恶魔双系，黑发红瞳、冷酷疏离，坐骑阎罗，
## 能力是吸取气势 / 禁止敌方回血复活。因此这里的符号一律是「向下的、贴地的、锐的」：
##   shadow : 贴地长影 —— 朝背后拖成刀尖形，随步频轻微伸缩；
##   aura   : 暗刃残痕 + 脚下暗雾 —— 移动时才闪出短促刀锋弧，静止只剩一层压扁的雾；
##   front  : 红瞳 —— 头部两点血红，慢闪 + 偶发爆闪，cast 时骤然放大。
##
## 手法与 SoulGlow 对齐：矢量硬边 + 一次性共享的径向渐变纹理 + additive 图层；
## 没有 blur、没有后处理、没有 SubViewport；paint 里不创建任何纹理 / 渐变 / 材质，
## 也不 load()。所有随机感都用确定性的 sin 相位得到，避免每帧状态漂移。
##
## 坐标：原点 = 脚底中心，向上为负。EntityView 的 pivot 已经按 facing 做过 scale.x 翻转，
## 所以**局部 -x 恒为角色的背后**；这里不再乘 facing，否则等于翻两次。
## 唯一的例外是红瞳：背面朝向（actor.facing_dir == "up"）时没有眼睛可看，直接收起。

# 主色：神暗系的冷紫；点缀：血红。整套配色里没有任何暖色。
const PURPLE := Color("#c7a0ff")
const PALE := Color("#e8d8ff")
const DEEP := Color("#4a2168")
const ABYSS := Color("#1c0a2b")
const BLOOD := Color("#ff4d5e")
const FOG := Color("#7a4fb8")
# 影子不用纯黑：带一点紫的墨色压在浅色地砖上，才像「暗影」而不是一块脏斑。
const SHADE := Color("#0f0818")

## 一划残痕的周期（秒）。步频 13.2 rad/s ≈ 2.1 步/秒，0.60s 一划 ≈ 每 1.2 步一道，
## 比步频稍慢：残痕要「跟得上」而不是和脚步一起抖。
const SLASH_PERIOD := 0.60

var _m_params: Dictionary = {}

# ---------------------------------------------------------------- 动效参数

func motion() -> Dictionary:
	# 阿修是「影子」：低伏、快、几乎不弹跳。
	# bounce 2.2 / squash 0.10 是整套数值里最低的一档，落地没有任何回弹，
	# 所以读起来是「滑」而不是「蹦」；stride 13.2 比常规角色（≈11）更快，
	# 配 sway 0.9 的极小横摆，重心几乎不左右倒；lean 7.2 把身体压向前进方向，
	# 像随时会发动「暗刃瞬袭」。breathe 0.018 / idle_rate 1.75 让待机呼吸浅到几乎看不见。
	return {
		"bounce": 2.2,
		"wobble": 1.6,
		"stride": 13.2,
		"sway": 0.9,
		"lean": 7.2,
		"breathe": 0.018,
		"idle_rate": 1.75,
		"squash": 0.10,
	}

func layer_specs() -> Array:
	# shadow 必须用 normal：影子是真的把地面压暗，additive 只会把地面提亮、影就没了。
	# aura 放在立绘之后 —— 刀痕被身体挡掉一部分，才像从背后划出去；
	# front 只放红瞳，必须盖在脸上。
	return [
		{"id": "shadow", "z": -4, "blend": "normal"},
		{"id": "aura", "z": -3, "blend": "add"},
		{"id": "front", "z": 1, "blend": "add"},
	]

func accent_color() -> Color:
	return PURPLE

## 「贴地长影」就是阿修的地面投影，EntityView 不要再叠一层通用椭圆落影。
func owns_ground() -> bool:
	return true

# ---------------------------------------------------------------- 绘制分发

func paint(ci: CanvasItem, layer: String) -> void:
	# display 是立绘显示尺寸；没有尺寸就没有任何比例可依，直接不画（也避免后面除零）。
	if display.y <= 0.0 or display.x <= 0.0:
		return
	match layer:
		"shadow":
			_paint_shadow(ci)
		"aura":
			_paint_aura(ci)
		"front":
			_paint_front(ci)

## motion() 是常量表，但每帧每层都会进 paint；缓存一次，避免每帧新建 Dictionary。
func _params() -> Dictionary:
	if _m_params.is_empty():
		_m_params = motion()
	return _m_params

# ---------------------------------------------------------------- 贴地长影

func _paint_shadow(ci: CanvasItem) -> void:
	var h := display.y
	var w := display.x
	var m := _params()
	var step := t * float(m["stride"])
	var c := clampf(cast, 0.0, 1.0)

	# 离地越高影子越短：bob 由 EntityView 的行走弹跳驱动，负值 = 身体抬起。
	# 这一项让影子跟着脚走，而不是一张固定在脚下的贴纸。
	var lift := clampf(-bob / maxf(1.0, float(m["bounce"]) * 2.0), 0.0, 1.0)
	var shrink := 1.0 - 0.12 * lift
	# 死亡时立绘会淡出，影子跟着收一点，避免「影子比人还实」。
	var fade := 1.0
	if not alive:
		fade = 0.45
	# 整层是 pivot 的子节点，会跟着弹跳一起升起；影子必须留在地面，
	# 所以按 -bob 反向补偿，把它钉回世界坐标 y≈0（画面里也就是脚底那条线）。
	var gy := -bob

	# 一个完整左右步态里伸缩 ±8.5%：幅度刻意很小 —— 阿修是滑行的，影子不能被「颠」起来。
	# cast 时整条影子再拉长一点，作为突进的前置张力。
	var stretch := 1.0 + 0.085 * sin(step * 0.5) + 0.10 * c
	var tail := w * 0.92 * stretch * shrink
	var rx := w * 0.31 * shrink
	var ry := maxf(1.5, h * 0.038) * shrink

	# 主体：前缘压在脚下，尾端朝背后（局部 -x）收成刀尖。
	# 六边形轮廓 + 偏心的尖端，让它读起来是「被身体拖出去的一道暗痕」，不是普通圆影。
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(rx, 0.5 + gy),
		Vector2(rx * 0.35, -ry * 0.95 + gy),
		Vector2(-tail * 0.42, -ry * 1.05 + gy),
		Vector2(-tail, ry * 0.15 + gy),
		Vector2(-tail * 0.38, ry * 1.30 + gy),
		Vector2(rx * 0.40, ry * 1.00 + gy),
	]), Color(SHADE.r, SHADE.g, SHADE.b, 0.18 * fade))

	# 两缕更淡的拖尾：把「拉长」做出层次，同时保持矢量硬边（没有模糊、没有噪点）。
	for i in 2:
		var droop := 0.10 + 0.09 * float(i)     # 越远的尾丝越往画面下方（靠近观众）铺
		var far := tail * (1.24 - 0.17 * float(i))
		var base_y := gy - ry * (0.18 + 0.34 * float(i))
		var half_h := ry * (0.60 - 0.14 * float(i))
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(-tail * 0.34, base_y - half_h),
			Vector2(-far, base_y + far * droop),
			Vector2(-tail * 0.30, base_y + half_h),
		]), Color(SHADE.r, SHADE.g, SHADE.b, 0.08 * fade))

	# 接地暗核：最黑的一点，把角色「钉」在地面上。alpha 0.22，仍低于 0.25 的上限。
	# 用 MapArt.ellipse 是为了和场景里其它投影同一套椭圆细分，边缘不会出现折角。
	MapArt.ellipse(ci, 0.0, 0.3 + gy, rx * 0.82, ry * 0.92,
		Color(SHADE.r, SHADE.g, SHADE.b, 0.22 * fade))

# ---------------------------------------------------------------- 暗雾 + 暗刃

func _paint_aura(ci: CanvasItem) -> void:
	if not alive:
		return
	var h := display.y
	var w := display.x
	var e := clampf(energy, 0.0, 1.0)
	var c := clampf(cast, 0.0, 1.0)

	# ---- 1) 脚下暗雾：同一张共享径向渐变纹理压扁成薄饼 ----
	# 暗雾是「重量」而不是「光尘」：全部贴地、全部向下沉，绝不向上飘（上浮是小诺）。
	# 三团用不同相位和不同的紫，缓慢脉动，alpha 都压得很低，只负责让脚底「脏」一点。
	var fog_w := w * (1.30 + 0.055 * sin(t * 0.47))
	var fog_h := h * 0.112
	# 与贴地长影同理：雾是地面上的东西，按 -bob 抵消 pivot 的弹跳，不让它跟身体一起浮。
	var fog_y := -h * 0.030 - bob
	var fog_a := (0.072 + 0.016 * sin(t * 0.9)) * (0.55 + 0.45 * e) * (1.0 + 0.55 * c)
	ci.draw_texture_rect(soft_dot(), Rect2(-fog_w * 0.5, fog_y - fog_h * 0.5, fog_w, fog_h),
		false, Color(FOG.r, FOG.g, FOG.b, fog_a))
	# 后侧第二团：沿着背后拖出去，和贴地长影同向，把雾与影缝成一体。
	var drift := sin(t * 0.53 + 1.1) * w * 0.05
	ci.draw_texture_rect(soft_dot(), Rect2(-fog_w * 0.92 + drift, fog_y - fog_h * 0.32,
		fog_w * 0.86, fog_h * 0.84), false,
		Color(DEEP.r, DEEP.g, DEEP.b, fog_a * 0.85))
	# 前侧一小团：压得更低、更贴鞋底，像碾过地面的暗气。
	ci.draw_texture_rect(soft_dot(), Rect2(fog_w * 0.12, fog_y - fog_h * 0.24,
		fog_w * 0.52, fog_h * 0.60), false,
		Color(FOG.r, FOG.g, FOG.b, fog_a * 0.60))

	# ---- 2) 暗刃残痕：只有移动（或施放）时才出现 ----
	# 静止的刺客不该自带光效；残痕是「刚才那一刀留下的」，不是常驻光晕。
	var cyc := fposmod(t, SLASH_PERIOD) / SLASH_PERIOD
	var slash := 0.0
	if moving:
		# 前 42% 出现，其余时间留白：闪一下就没，短促、锐利。
		slash = pow(clampf(1.0 - cyc / 0.42, 0.0, 1.0), 1.35)
	slash = clampf(slash + c * 0.75, 0.0, 1.0)
	if slash > 0.02:
		# 每一划上下交替起手：上一划从肩前起，下一划从腰下起，像在「甩」刀，
		# 也补上步伐交换的节奏 —— 不增加任何绘制调用。
		var parity := 1.0
		if int(floor(t / SLASH_PERIOD)) % 2 == 1:
			parity = -1.0
		# 弧心放在身体前半侧、腰的高度：半径约 1/4 身高，弧的大半能露在剪影之外，
		# 剩下的部分被立绘挡住，读起来才是「从背后划出去的刀」，而不是贴在身上的光圈。
		var cx := w * 0.20
		var cy := -h * 0.50
		var rr := h * 0.285 * (1.0 + 0.12 * c)
		var a0 := -1.42 * parity
		var grow := 0.55 + 0.45 * clampf(cyc / 0.42, 0.0, 1.0)
		if not moving:
			grow = 1.0            # 施放时的残痕稳定成一道完整刀痕，不跟着周期抽动
		# 弧只扫 1.15~1.43 rad：够短，才像刀锋而不是光弧。
		var a1 := a0 + (1.15 + 0.28 * c) * grow * parity
		var mid := lerpf(a0, a1, 0.55)
		var lead := lerpf(a0, a1, 0.34)

		# 尾段两截：深紫 → 近黑。换的是颜色与 alpha，几何完全一致，
		# 于是得到一条沿弧「从刀尖的紫烧到弧尾的黑」的衰减，而不需要创建任何渐变纹理。
		ci.draw_arc(Vector2(cx, cy), rr, a0, mid, 10,
			Color(ABYSS.r, ABYSS.g, ABYSS.b, 0.17 * slash), maxf(1.0, h * 0.014), true)
		ci.draw_arc(Vector2(cx, cy), rr, mid, a1, 12,
			Color(DEEP.r, DEEP.g, DEEP.b, 0.24 * slash), maxf(1.0, h * 0.014), true)
		# 亮芯：只描靠刀尖的后半段，前端自然消失 —— 沿弧的 alpha 衰减（不是渐变纹理，也不是 blur）。
		glow_arc(ci, cx, cy, rr * 0.985, lead, a1,
			Color(PALE.r, PALE.g, PALE.b, 0.52 * slash), maxf(1.0, h * 0.020))
		# 刀尖的一点血光：除红瞳之外全角色唯一的红，落点只有一两像素。
		star4(ci, cx + cos(a1) * rr, cy + sin(a1) * rr, maxf(1.0, h * 0.028) * slash,
			Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.50 * slash))

	# ---- 3) 突进刀光：cast 只是通用强度，所以画「身后斜劈的暗色刀痕」 ----
	# 不假定 cast 一定是位移：即使原地放大招，这道刀光也只是「蓄势/收势」的暗色尾迹。
	if c > 0.02:
		var reach := w * (0.55 + 1.30 * c)
		var tip_y := -h * (0.40 + 0.18 * c)
		var root_top := Vector2(-w * 0.08, -h * 0.76)
		var root_bot := Vector2(-w * 0.02, -h * 0.47)
		var tip_top := Vector2(-reach, tip_y - h * 0.05)
		var tip_bot := Vector2(-reach * 0.92, tip_y + h * 0.05)
		# 刀身：极暗的深紫锥形。additive 下暗色只留一点点紫，压在角色背后不会洗掉立绘。
		ci.draw_colored_polygon(PackedVector2Array([root_top, tip_top, tip_bot, root_bot]),
			Color(DEEP.r, DEEP.g, DEEP.b, 0.28 * c))
		# 上缘一条硬亮线：速度感靠这条锐线，不靠光晕「糊」出来。
		ci.draw_polyline(PackedVector2Array([root_top, (root_top + tip_top) * 0.5, tip_top]),
			Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.40 * c), maxf(1.0, h * 0.016), true)

# ---------------------------------------------------------------- 红瞳

func _paint_front(ci: CanvasItem) -> void:
	if not alive:
		return
	# 背面朝向时没有眼睛可看：红瞳必须收起，否则两点红光会浮在后脑勺上。
	if actor != null and String(actor.facing_dir) == "up":
		return
	var h := display.y
	var w := display.x
	var c := clampf(cast, 0.0, 1.0)
	# 眼睛的纵向位置按锚点算（基类契约）：立绘顶边 = -display.y * anchor.y，
	# 头心再下移 0.18 个身位，眼线略高于头心 0.06 个身位。
	# 阿修 anchor.y = 0.88，合起来正好落在 -display.y * 0.76 —— 和立绘头部对得上，
	# 也不会因为将来换锚点而把红瞳顶到天灵盖或压到下巴。
	var anchor_y := anchor.y
	if anchor_y <= 0.0:
		anchor_y = 1.0            # 未 configure 时按「脚底在底边」处理，避免眼睛落到地面以下
	var head_y := -h * anchor_y + h * 0.18
	var eye_y := head_y - h * 0.06
	var eye_dx := maxf(2.0, w * 0.125)

	# 慢闪：很浅的呼吸式明暗；爆闪：sin 的 22 次方把「常亮」压成十几秒一次的短促红光。
	# 这两者叠在一起，才是「冷酷地瞥你一眼」，而不是一颗一直亮着的灯泡。
	var slow := 0.32 + 0.15 * sin(t * 1.15 + 0.7)
	var blink := pow(maxf(0.0, sin(t * 0.61 + 2.2)), 22.0)
	var glow := clampf(slow + blink * 0.55 + c * 0.95, 0.0, 1.25)
	var radius := maxf(1.1, h * 0.021) * (1.0 + 0.60 * c + 0.35 * blink)

	for i in 2:
		var ex := eye_dx
		if i == 1:
			ex = -eye_dx
		# 外层：几像素的红色溢散，只照亮眼窝附近，不扩散成光环。
		ci.draw_texture_rect(soft_dot(), Rect2(ex - radius * 2.2, eye_y - radius * 2.2,
			radius * 4.4, radius * 4.4), false,
			Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.16 * glow))
		# 内层：四角星硬核 = 一点竖长的红光。边缘是硬的，和脚下暗雾的软形成对照。
		star4(ci, ex, eye_y, radius * 1.15,
			Color(1.0, 0.56, 0.63, 0.82 * clampf(glow, 0.0, 1.0)))
		# 施放时才有的余光拖尾：红光被拉向身后（局部 -x），读作突进的反向拖尾。
		if c > 0.05:
			ci.draw_line(Vector2(ex, eye_y),
				Vector2(ex - w * (0.30 + 0.22 * c), eye_y + h * 0.018),
				Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.24 * c), 1.0, true)
