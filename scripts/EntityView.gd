class_name EntityView
extends Node2D

## 角色 / 敌人立绘：脚底锚点、朝向翻转、弹跳摇摆、护盾、星星、受击与死亡。
## 动效参数与锚点对照原作 sprites.js drawCharacter / drawEnemy。

static var _tex_cache := {}

## 动效参数：原作 assets/characters.js 每个角色自带 motion，缺省见 assets.js:22 DEFAULT_MOTION。
## 键必须**齐全**：没有氛围层脚本的角色（未来 / 觉醒形态）只吃这一份默认值，
## 缺键会在 update_view 里直接报 "Invalid access to property or key"。
const MOTION_DEFAULT = {
	"bounce": 4.0,     # 行走弹跳高度 px
	"wobble": 4.0,     # 行走摇摆角度 deg
	"stride": 11.0,    # 步频 rad/s
	"sway": 1.4,       # 重心横移 px
	"lean": 2.5,       # 前进方向倾斜 deg
	"breathe": 0.04,   # 静止呼吸幅度
	"idle_rate": 2.4,  # 静止呼吸频率 rad/s
	"squash": 0.22,    # 落地压扁系数
}
const MOTION_BY_ID = {
	"weilai": {"bounce": 3.0, "wobble": 3.0, "stride": 10.8, "sway": 1.2, "lean": 1.8,
		"breathe": 0.025, "idle_rate": 2.2, "squash": 0.18},
	"weilai-awakened": {"bounce": 2.0, "wobble": 1.5, "stride": 9.0, "sway": 0.6, "lean": 0.8,
		"breathe": 0.012, "idle_rate": 1.6, "squash": 0.1},
}

## 每个角色自己的氛围层脚本（「未来」已有 SoulGlow 通灵柔光，不在此列）。
## 用 res:// 路径 load，而不是 class_name：新增文件不必等编辑器注册全局类，
## 也让 5 个角色可以各写一个文件、互不干扰。
const AURA_PATHS = {
	"xiaonuo": "res://scripts/char_fx/xiaonuo_aura.gd",
	"axiu": "res://scripts/char_fx/axiu_aura.gd",
	"arui": "res://scripts/char_fx/arui_aura.gd",
	"xiaoyan": "res://scripts/char_fx/xiaoyan_aura.gd",
	"xiaotian": "res://scripts/char_fx/xiaotian_aura.gd",
}

static var _aura_scripts := {}
const TAG_SIZE = 13
const TAG_HALF_W = 50.0
const PLAYER_ANCHOR_Y = 18.0   # CFG.BOX / 2：玩家脚底（sprites.js:816）
const ENEMY_ANCHOR_Y = 14.0    # 敌人脚底 = drawEnemy 的 translate y（sprites.js:1061）
const DEPTH_SHIFT = 18.0       # 原作按角色中心 y 排序（main.js:290），炸弹同为 +18

var actor: Actor = null
var is_enemy := false
var world_time := 0.0

var pivot: Node2D
var sprite: Sprite2D
var tag: Label
var _tex: Texture2D
var _cur_id := ""
var _using_back := false
var _scale := 1.0
var _display := Vector2(48, 48)
var _time := 0.0
var _alpha := 1.0
var _base_h := 48.0
var _anchor := Vector2(0.5, 1.0)
var _bob := 0.0
var _wob := 0.0
var _sx := 1.0
var _sy := 1.0
var _flip := 1.0
var _bloom := 1.0
var _sway := 0.0       # 行走时的重心横移（px），影子与立绘共用
var _lift := 0.0       # 步态抬脚高度 0..1（0 = 触地），影子收缩与扬尘靠它
var _energy := 0.0     # 氛围层强度，静止时衰减以省掉大部分绘制
var _motion: Dictionary = MOTION_DEFAULT.duplicate()

# 1P/2P 标签的缓存：Label 的主题覆盖 / 尺寸每帧重设会触发一次
# NOTIFICATION_THEME_CHANGED + 重新排版，两个玩家就是每帧两次无谓开销。
var _tag_font: Font = null
var _tag_half_line := 0.0
var _tag_color := Color(0, 0, 0, 0)
var _tag_text := ""
var _tag_cy := 0.0

## 通灵柔光（只给「未来」觉醒形态）。挂在 pivot 下，跟随弹跳/倾斜/翻转。
var show_tag := true
var soul_enabled := true
var _soul_glow: SoulGlow = null
## 角色氛围层（小诺 / 阿修 / 阿瑞 / 小炎 / 小天），「未来」用 SoulGlow。
var _aura: Node2D = null

## 当前显示的通灵形态（原作 assets.js:240 visualId）。
func _visual_id() -> String:
	if actor == null:
		return ""
	if not is_enemy and actor.asset_id == "weilai" and actor.soul_evolved:
		return "weilai-awakened"
	return actor.asset_id

func setup(a: Actor, _f: Font) -> void:
	actor = a
	is_enemy = a.is_enemy
	# 立绘保真：素材是 560px 原图、导入为无损（compress/mode=0）且不缩放（size_limit=0），
	# 这里刻意**不开 mipmap**。mip 链在三线性过渡处会把细节混掉，小尺寸显示时反而更糊；
	# 宁可保留一点行走时的采样闪烁，也要保住脸和轮廓的清晰度。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pivot = Node2D.new()
	add_child(pivot)
	sprite = Sprite2D.new()
	sprite.centered = false
	pivot.add_child(sprite)
	if not a.is_enemy and a.asset_id == "weilai":
		_soul_glow = SoulGlow.new()
		# 实机参数：浅色地砖 / 森林底色上，0.34 光强 + 0.60 墨晕 + 0.35 体积光
		# 比纯 additive 的展示版克制得多，人物立绘始终可读。
		_soul_glow.energy = 0.34
		_soul_glow.ink_strength = 0.60
		_soul_glow.bloom_strength = 0.35
		pivot.add_child(_soul_glow)
		_soul_glow.visible = false
	# 其余五位的氛围层：每人一个脚本，挂在同一 pivot 下，自动跟随弹跳/倾斜/翻转。
	_aura = _make_aura(a)
	if _aura != null:
		pivot.add_child(_aura)
	# 立绘改由 _draw() 里的 _draw_sprite() 画（见该函数注释）：
	# Node2D 自身的 _draw 恒在子节点之下，若继续让 Sprite2D 渲染，
	# 「白闪 / 光环 / 护盾 / 星星」会被整体压到立绘背后，而原作是画在其上。
	# 这里只是让 Sprite2D 退出渲染，节点本身保留。
	sprite.visible = false
	tag = Label.new()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_font = UIDraw.font("cn", 900)
	tag.add_theme_font_override("font", _tag_font)
	tag.add_theme_font_size_override("font_size", TAG_SIZE)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	tag.add_theme_constant_override("outline_size", 3)
	if _tag_font != null:
		_tag_half_line = (_tag_font.get_ascent(TAG_SIZE) + _tag_font.get_descent(TAG_SIZE)) * 0.5
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.z_index = 20
	tag.size = Vector2(TAG_HALF_W * 2.0, 20)
	add_child(tag)
	_refresh_texture(true)

## 取某角色的氛围层脚本（按需 load，结果缓存）。文件不存在时返回 null，
## 于是「没写氛围层的角色」自动退化成原来的纯立绘动效，不会报错。
static func _aura_script(id: String) -> Script:
	if _aura_scripts.has(id):
		return _aura_scripts[id]
	var path: String = String(AURA_PATHS.get(id, ""))
	var script: Script = null
	if path != "" and ResourceLoader.exists(path):
		script = load(path)
	_aura_scripts[id] = script
	return script

func _make_aura(a: Actor) -> Node2D:
	if a.is_enemy:
		return null
	var script: Script = _aura_script(a.asset_id)
	if script == null:
		return null
	var node = script.new()
	if node is Node2D:
		return node
	return null

## 氛围层是否已接管地面投影（水镜 / 长影），是则不再画默认椭圆落影。
func _owns_ground() -> bool:
	return _aura != null and _aura.has_method("owns_ground") and bool(_aura.owns_ground())

## 动效参数合成：通用默认 → 少数按 id 定制的常数 → 角色氛围层自带的 motion()。
## 只在立绘/形态变化时算一次，update_view 里直接用缓存，避免每帧做字典查找与字符串比较。
func _resolve_motion() -> Dictionary:
	var out: Dictionary = MOTION_DEFAULT.duplicate()
	var id := _visual_id()
	if MOTION_BY_ID.has(id):
		out.merge(MOTION_BY_ID[id], true)
	if _aura != null and _aura.has_method("motion"):
		out.merge(_aura.motion(), true)
	return out

func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex

func _player_texture(id: String, back: bool, evolved: bool) -> Texture2D:
	if evolved and id == "weilai":
		return _load_tex("res://assets/characters/weilai-awakened%s.png" % ("-back" if back else ""))
	return _load_tex("res://assets/characters/%s%s.png" % [id, "-back" if back else ""])

func _enemy_texture(type_id: String, rage: bool) -> Texture2D:
	if type_id == "boss":
		if rage:
			var t := _load_tex("res://assets/enemies/luludan-rage-v2.png")
			if t != null:
				return t
		return _load_tex("res://assets/enemies/luludan.png")
	return _load_tex("res://assets/enemies/%s.png" % type_id)

func _refresh_texture(force: bool = false) -> void:
	var tex: Texture2D = null
	if is_enemy:
		tex = _enemy_texture(actor.type, actor.phase >= 3)
		_using_back = false
	else:
		_using_back = actor.facing_dir == "up"
		tex = _player_texture(actor.asset_id, _using_back, actor.soul_evolved)
	if tex == null:
		sprite.texture = null
		return
	if not force and tex == _tex:
		return
	_tex = tex
	sprite.texture = tex
	var target_h := 0.0
	var anchor := Vector2(0.5, 1.0)
	if is_enemy:
		target_h = 96.0 if actor.type == "boss" else 48.0
	else:
		var cfg := Cfg.char_cfg(actor.asset_id)
		target_h = float(cfg["height"]) * Cfg.TILE
		anchor = cfg["anchor"]
		if actor.soul_evolved and actor.asset_id == "weilai":
			target_h = 3.05 * Cfg.TILE
			# 通灵形态是独立素材：正面锚点 0.53、背面 0.5（assets/characters.js:81 / :114）。
			anchor = Vector2(0.5 if _using_back else 0.53, 0.97)
		_base_h = target_h
	_anchor = anchor
	_scale = target_h / float(tex.get_height())
	_display = Vector2(tex.get_width() * _scale, tex.get_height() * _scale)
	sprite.scale = Vector2(_scale, _scale)
	sprite.position = Vector2(-tex.get_width() * _scale * anchor.x,
		-tex.get_height() * _scale * anchor.y + (0.0 if not is_enemy else (8.0 if actor.type == "boss" else 2.0)))
	if _soul_glow != null:
		if actor.soul_evolved and not is_enemy:
			_soul_glow.configure(_tex, _display, _anchor)
		else:
			_soul_glow.clear()
	if not is_enemy:
		_motion = _resolve_motion()
	if _aura != null:
		_aura.configure(_tex, _display, _anchor)

func update_view(alpha: float, time_now: float, delta: float) -> void:
	if actor == null:
		return
	_time += delta
	world_time = time_now
	var back_now := (not is_enemy) and actor.facing_dir == "up"
	var evolved_now: bool = actor.soul_evolved and actor.asset_id == "weilai"
	var rage_now: bool = is_enemy and actor.type == "boss" and actor.phase >= 3
	if back_now != _using_back or (rage_now != (_cur_id == "boss_rage")) \
			or (not is_enemy and evolved_now != (_cur_id == "awakened")):
		_refresh_texture(true)
	_cur_id = "boss_rage" if rage_now else ("awakened" if evolved_now else "")

	var px := lerpf(actor.px, actor.x, alpha)
	var py := lerpf(actor.py, actor.y, alpha)
	# 脚底锚点：玩家 = 碰撞盒中心 + BOX/2（sprites.js:816）；敌人 = drawEnemy 的 py + 14（sprites.js:1061）。
	var foot := PLAYER_ANCHOR_Y if not is_enemy else ENEMY_ANCHOR_Y
	position = Vector2(px, py + foot)
	# 深度键沿用原作的「按角色中心 y 排序」（main.js:290），与 BombView 的 +18 同源。
	z_index = int(py + DEPTH_SHIFT)

	var boss := is_enemy and actor.type == "boss"
	var bob := 0.0
	var wob := 0.0
	var sx := 1.0
	var sy := 1.0
	var sway := 0.0
	var lift := 0.0
	_alpha = 1.0
	if is_enemy:
		# sprites.js:1055-1057：弹跳与死亡（0.7s 淡出 + 纵向压扁 0.65）
		bob = (-absf(sin(_time * 8.0)) * 2.5) if actor.moving else (sin(_time * 2.2) * 1.1)
		if not actor.alive:
			var dead_t := clampf((world_time - actor.dead_at) / 0.7, 0.0, 1.0)
			_alpha = 1.0 - dead_t
			sy = 0.65
	else:
		# 播放角色：四相步态（触地 → 顶起 → 触地 → 顶起）。
		# 旧版只有 -abs(sin) 的上下位移 + 平摆，没有落地压扁、重心横移、发力前倾，
		# 六个角色读起来是同一张会抖的贴纸；这里补上「重量」和「朝哪边使劲」。
		var m: Dictionary = _motion
		var st := float(m["squash"])
		if actor.alive:
			if actor.moving:
				var ph := _time * float(m["stride"])
				var wave := sin(ph)
				# pow(0.82)：顶部更「悬」、触地更干脆，比纯 |sin| 更有弹性
				lift = pow(absf(wave), 0.82)
				bob = -lift * float(m["bounce"])
				wob = wave * deg_to_rad(float(m["wobble"]))
				sway = wave * float(m["sway"])
				# 触地压扁 / 顶点拉伸 —— Q 版步态的重量感几乎全靠这一项
				var contact := pow(1.0 - lift, 3.0)
				var apex := pow(lift, 4.0)
				var squeeze := st * (contact * 0.55 - apex * 0.18)
				sx = 1.0 + squeeze
				sy = 1.0 - squeeze
				# 前倾只给左右移动：上下移动时整张贴图倾斜会读成「摔倒」，
				# 背面素材一斜还会露出侧边，所以只按左右朝向压一点。
				if actor.facing_dir == "left" or actor.facing_dir == "right":
					wob += deg_to_rad(float(m["lean"])) * float(actor.facing) * (0.35 + 0.65 * lift)
			else:
				var br := sin(_time * float(m["idle_rate"])) * float(m["breathe"])
				sx = 1.0 + br
				sy = 1.0 - br * 0.6
				# 待机时重心极慢地漂一点，避免「立绘贴纸」的僵直感
				sway = sin(_time * float(m["idle_rate"]) * 0.5) * float(m["sway"]) * 0.35
			if actor.squash > 0.0:
				var s: float = actor.squash * st
				sx *= 1.0 + s
				sy *= 1.0 - s
		else:
			_alpha = 0.55
			wob = sin(_time * 6.0) * 0.25
	# 左右翻转：小怪立绘随朝向翻转（sprites.js:1084），BOSS 立绘不翻转（sprites.js:1088-1092）；
	# 玩家背面素材 flipForLeft = false（characters.js:118），也不翻转。
	var flip := 1.0
	if actor.facing < 0:
		if is_enemy:
			if not boss:
				flip = -1.0
		elif not _using_back:
			flip = -1.0
	# 通灵瞬间的膨胀（sprites.js:848-852）
	var bloom := 1.0
	if not is_enemy and actor.alive and actor.asset_id == "weilai" and actor.soul_awaken_time > 0.0:
		bloom = 1.0 + sin(PI * (1.0 - actor.soul_awaken_time / 1.6)) * 0.07
	_bob = bob
	_wob = wob
	_sway = sway
	_lift = lift
	_sx = sx
	_sy = sy
	_flip = flip
	_bloom = bloom
	pivot.position = Vector2(sway, bob)
	pivot.rotation = wob
	pivot.scale = Vector2(flip * sx * bloom, sy * bloom)
	sprite.modulate = Color(1, 1, 1, _alpha)
	if _soul_glow != null:
		var show_soul := soul_enabled and actor.alive and actor.soul_evolved and _tex != null
		_soul_glow.visible = show_soul
		if show_soul:
			_soul_glow.update_soul(_time, actor.soul_awaken_time, delta)
	if _aura != null:
		var show_aura: bool = actor.alive and _tex != null
		if _aura.visible != show_aura:
			_aura.set_visible_layers(show_aura)
		if show_aura:
			# 静止时把能量压到 0.62：氛围层仍成立，但各角色可以按 energy 省掉大部分绘制
			var target := 1.0 if actor.moving else 0.62
			_energy = lerpf(_energy, target, clampf(delta * 6.0, 0.0, 1.0))
			_aura.moving = actor.moving
			_aura.alive = actor.alive
			_aura.facing = actor.facing
			_aura.bob = bob
			_aura.energy = _energy
			_aura.cast = clampf(actor.cast_flash / 0.8, 0.0, 1.0)
			_aura.actor = actor
			_aura.advance(delta)
		else:
			_energy = 0.0
	# 1P / 2P 标签（sprites.js:1151-1160：文字中心在 p.y - (130 | 62) + sin(time*3)*1.5）
	if not is_enemy:
		tag.visible = actor.alive and show_tag
		var want := "1P" if actor.id == "p1" else "2P"
		if want != _tag_text:
			_tag_text = want
			tag.text = want
		# 主题覆盖只在颜色真的变了才设：每帧 add_theme_color_override 会触发
		# NOTIFICATION_THEME_CHANGED 并让 Label 重新排版，等于每帧白烧两次布局。
		if actor.color != _tag_color:
			_tag_color = actor.color
			tag.add_theme_color_override("font_color", _tag_color)
		# 觉醒形态的立绘高出近一倍，标签要跟着抬到头顶之上
		_tag_cy = (-130.0 if (actor.asset_id == "weilai" and actor.soul_evolved) else -62.0) - PLAYER_ANCHOR_Y
		# Label 顶对齐：文字中心 = 顶部 + (ascent + descent) / 2（该值已在 setup 里缓存）
		tag.position = Vector2(-TAG_HALF_W, _tag_cy + sin(_time * 3.0) * 1.5 - _tag_half_line)
	else:
		tag.visible = false
	queue_redraw()

func _draw() -> void:
	if actor == null:
		return
	var boss: bool = is_enemy and actor.type == "boss"
	# ---- 落地阴影（原作 sprites.js:838-841 玩家 / :1057 敌人，都画在变换之外）----
	if actor.alive:
		if is_enemy:
			MapArt.ground_shadow(self, 0, -1, 32.0 if boss else 15.0, 9.0 if boss else 5.0, 0.22)
		elif not _owns_ground():
			# 影子跟着重心横移 35%、随抬脚收缩。原来按 bob 像素估收缩，
			# 换个角色参数就失准；_lift 是归一化的抬脚高度，任何角色都贴合。
			# 外层柔、内层实：脚底才真的像压在地上，而不是贴了一张灰饼。
			var shrink := 1.0 - _lift * 0.40
			var shx := _sway * 0.35
			MapArt.ground_shadow(self, shx, 0.6, 17.0 * shrink, 6.2 * shrink, 0.20)
			MapArt.ground_shadow(self, shx, 0.0, 10.5 * shrink, 3.8 * shrink, 0.15)
		# ---- 脚步扬尘：从步态相位反推「离上次触地多久」，不需要额外的状态机 ----
		if actor.moving and not is_enemy:
			var stride := maxf(0.001, float(_motion["stride"]))
			var since := fposmod(_time * stride, PI) / stride
			if since < 0.17:
				var u := since / 0.17
				var rr := 8.0 + u * 15.0
				MapArt.ellipse_stroke(self, _sway * 0.5, 0.0, rr, rr * 0.33,
					Color(20 / 255.0, 26 / 255.0, 45 / 255.0, 0.20 * (1.0 - u)), 1.5)
	if is_enemy:
		# 原作敌人的光环 / 提示都画在 translate(px, py + 14 + bob) 之内（sprites.js:1061），随弹跳位移。
		var by := _bob
		# ---- BOSS 阶段光环（sprites.js:1063-1074，先于护盾/气泡）----
		var stage := Entities.boss_stage(actor)
		if actor.alive and not stage.is_empty() and int(stage["id"]) > 1:
			var ring_w := 3.0 if int(stage["id"]) == 3 else 2.0
			var c: Color = stage["color"]
			MapArt.ellipse_stroke(self, 0, -1 + by, 37, 10,
				Color(c.r, c.g, c.b, 0.65 + sin(_time * 6.0) * 0.15), ring_w)
			if actor.phase_flash > 0.0:
				MapArt.ellipse_stroke(self, 0, -1 + by, 38 + (1.4 - actor.phase_flash) * 36,
					11 + (1.4 - actor.phase_flash) * 10, Color(c.r, c.g, c.b, actor.phase_flash / 1.4), ring_w)
		# ---- 护盾 / 无敌星星气泡（sprites.js:1075-1079）----
		if actor.alive and (actor.shield > 0 or actor.star_time > 0.0):
			var bcy := (-39.0 if boss else -21.0) + by
			var brx := 53.0 if boss else 28.0
			var bry := 56.0 if boss else 30.0
			var b_fill := Color(255 / 255.0, 220 / 255.0, 101 / 255.0, 0.15) if actor.star_time > 0.0 \
				else Color(123 / 255.0, 207 / 255.0, 255 / 255.0, 0.16)
			var b_line := Color("#ffdc65") if actor.star_time > 0.0 else Color("#7bcfff")
			MapArt.ellipse(self, 0, bcy, brx, bry, b_fill)
			MapArt.ellipse_stroke(self, 0, bcy, brx, bry, b_line, 2.0)
		# ---- 立绘本体（原作画在阶段光环/护盾之后、白闪/前摇之前）----
		_draw_sprite()
		# ---- 受击白闪 / 投弹前摇（sprites.js:1139-1146，画在立绘之上）----
		if actor.hit_flash > 0.0:
			var flash_r := 33.0 if boss else 19.0
			CanvasArt.ellipse_rot_stroke(self, 0, (-65.0 if boss else -24.0) + by, flash_r, flash_r, 0.0,
				Color("#fff9c3"), 3.0)
		if actor.windup > 0.0:
			UIDraw.text(self, "!", 0, (-142.0 if boss else -54.0) + by, {"size": 23, "weight": 900, "family": "cn",
				"fill": Color("#ffca68"), "stroke": Color("#65503d"), "strokeWidth": 3, "align": "center"})
			MapArt.ellipse_stroke(self, 0, -1 + by, 35.0 if boss else 21.0, 8, Color("#f5c560"), 2.5)
	else:
		# 通灵柔光由 pivot 下的 SoulGlow 子层绘制（z=-4..+2），
		# 在 Node2D 自身 _draw 之前完成：墨晕 → 主光 → 法环 → 立绘 → 前景灵屑/觉醒爆发。
		# ---- 立绘本体（原作画在通灵轮廓之后、白闪/光环/护盾/星星之前）----
		_draw_sprite()
		# ---- 受击保护白闪（sprites.js:869-876）----
		if actor.alive and actor.invuln > 0.0 and sin(_time * 26.0) > 0.0:
			MapArt.ellipse(self, 0, -26, 18, 30, Color(1, 1, 1, 0.45))
		# ---- 吸火 / 洞察光环（sprites.js:878-884）----
		if actor.alive and (actor.flame_guard > 0.0 or actor.insight_time > 0.0):
			var aura := Color("#82d4ed") if actor.insight_time > 0.0 else Color("#ffc18a")
			MapArt.ellipse_stroke(self, 0, -4, 23 + sin(_time * 5.0), 8, aura, 2.5)
		# ---- 未来通灵：脚下法环与双翼守护灵（sprites.js:886-893）----
		if actor.alive and actor.asset_id == "weilai" and actor.soul_evolved:
			MapArt.ellipse_stroke(self, 0, -2, 23, 7, Color("#b5f0fa"), 1.8)
			for spirit in 3:
				var orbit := _time * 1.8 + spirit * TAU / 3.0
				var xx := cos(orbit) * 27.0
				var yy := -30.0 + sin(orbit) * 22.0
				MapArt.poly_fill(self, PackedVector2Array([
					Vector2(xx, yy - 4), Vector2(xx + 3, yy), Vector2(xx, yy + 4), Vector2(xx - 3, yy),
				]), Color("#f3b9ea") if spirit % 2 else Color("#d5fbff"))
		# ---- 护盾气泡（sprites.js:896-903，globalAlpha 与颜色 alpha 相乘）----
		if actor.alive and actor.shield > 0:
			var sh_a := 0.38 + sin(_time * 7.0) * 0.12
			CanvasArt.ellipse_rot_fill(self, 0, -26, 30, 30, 0.0,
				Color(120 / 255.0, 200 / 255.0, 255 / 255.0, 0.35 * sh_a))
			CanvasArt.ellipse_rot_stroke(self, 0, -26, 30, 30, 0.0,
				Color(143 / 255.0, 216 / 255.0, 255 / 255.0, sh_a), 3.0)
		# ---- 无敌星星光环（sprites.js:905-916，只有玩家有环绕的星星）----
		if actor.alive and actor.star_time > 0.0:
			CanvasArt.ellipse_rot_fill(self, 0, -26, 32, 32, 0.0,
				Color(255 / 255.0, 217 / 255.0, 91 / 255.0, 0.14))
			CanvasArt.ellipse_rot_stroke(self, 0, -26, 32, 32, 0.0, Color("#ffe382"), 3.0)
			for i in 3:
				var a := _time * 3.0 + i * TAU / 3.0
				ItemIcons.draw(self, "star", cos(a) * 32.0, -26.0 + sin(a) * 29.0, 12)

## 立绘本体。
##
## 原作 drawCharacter / drawEnemy 都把立绘画在「落影 + 通灵轮廓」之后、
## 「白闪 / 光环 / 护盾 / 星星」之前；而 Godot 里 Node2D 自身的 _draw 恒在子节点**之下**，
## 所以继续用 Sprite2D 渲染会让那些特效整体被压到立绘背后（玩家无敌白闪会被完全遮住）。
## 因此立绘在这里用 draw_texture_rect 画，Sprite2D 只保留节点、退出渲染（见 setup）。
##
## 变换链与 SoulGlow 所在的 pivot 一致，也与原先 pivot/sprite 的合成变换等价：
##   T(0,_bob) · R(_wob) · S(_flip*_sx*_bloom, _sy*_bloom) · T(sprite.position) · S(_scale)
## 其中 sprite.position = (-w*scale*anchor.x, -h*scale*anchor.y + eoff)，
## 而 _display = (w*scale, h*scale)，故偏移量直接用 _display 表达。
func _draw_sprite() -> void:
	var tex: Texture2D = sprite.texture if sprite != null else null
	if tex == null or _display.x <= 0.0 or _display.y <= 0.0:
		return
	draw_set_transform(Vector2(_sway, _bob), _wob, Vector2(_flip * _sx * _bloom, _sy * _bloom))
	# 敌人的立绘另有 +2 / +8 的脚底微调（sprites.js:1085-1092）。
	var eoff := 0.0 if not is_enemy else (8.0 if actor.type == "boss" else 2.0)
	var off := Vector2(-_display.x * _anchor.x, -_display.y * _anchor.y + eoff)
	draw_texture_rect(tex, Rect2(off.x, off.y, _display.x, _display.y), false, Color(1, 1, 1, _alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
