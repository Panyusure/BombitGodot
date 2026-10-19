class_name Hud
extends Control

## 顶部 HUD、玩家状态卡、技能卡、悬浮计时 / BOSS 血条 / 回合板。
## 版式、坐标、配色对照原作 src/render/hud.js。

const MODE_META := {
	"dig": {"no": "02", "title": "计时拆砖", "en": "TIME ATTACK", "color": UIDraw.CYAN, "tag": "TIME"},
	"versus": {"no": "03", "title": "同屏对战", "en": "LOCAL VERSUS", "color": UIDraw.PINK, "tag": "SCORE"},
	"adventure": {"no": "01", "title": "闯关打怪", "en": "ADVENTURE", "color": UIDraw.GREEN, "tag": "STAGE"},
}

# 原作 modeMeta() 的兜底项（hud.js:25）。
const MODE_META_FALLBACK := {"no": "00", "title": "对局", "en": "BATTLE",
	"color": UIDraw.YELLOW, "tag": "PLAY"}

var world: World = null
var font: Font = null
var muted := false
var hint_alpha := 1.0
var network_player := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if world == null:
		return
	_draw_top()
	# 场地边框（原作 hud.js:643-655 HUD.drawFieldFrame，main.js:308 调用）：
	# 画在角色/粒子之后、悬浮层与技能卡之前，所以放在这里而不是 Board 里
	# （Board 在 Actors 之前，边框会被贴边角色盖住）。原作的 ctx 此时仍被
	# translate(0, HUD_H) 包着，故这里同样偏移 HUD_H。
	draw_rect(Rect2(1, Cfg.HUD_H + 1, Cfg.FIELD_W - 2, Cfg.FIELD_H - 2),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.44), false, 2.0, true)
	draw_rect(Rect2(4, Cfg.HUD_H + 4, Cfg.FIELD_W - 8, Cfg.FIELD_H - 8),
		Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.22), false, 1.0, true)
	draw_set_transform(Vector2(0, Cfg.HUD_H), 0.0, Vector2.ONE)
	_draw_floating()
	_draw_skills()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _meta() -> Dictionary:
	if not network_player.is_empty():
		return {"no": "04", "title": "联机对战", "en": "LAN VERSUS", "color": UIDraw.YELLOW, "tag": "SCORE"}
	return MODE_META.get(world.mode, MODE_META_FALLBACK)

## 该玩家最近一次实际生效的输入来源是不是手柄（InputSettings 逐帧记录）。
func _pad(slot: String) -> bool:
	return InputSettings.last_source(slot) == "gamepad"

## 手柄放弹 / 技能按钮名跟着实际绑定走（改绑后提示同步）。
func _pad_label(group: String, func_name: String, fallback: String) -> String:
	var labs := InputSettings.pad_labels(InputSettings.action_for(group, func_name))
	return String(labs[0]) if labs.size() > 0 else fallback

func _dir_text() -> String:
	if _pad("p1"):
		return "D-pad / 左摇杆"
	return "方向键 / WASD" if world.input_mode != "versus" else "方向键"

## 顶部操作提示（绘制与取证共用同一份文本）：
## 返回 [{"text", "y", "size", "family"}, ...]，键盘文案与移植前逐字一致。
func hint_lines() -> Array:
	if world == null:
		return []
	if not network_player.is_empty():
		return [{"text": "本机 %s · %s 移动" % [network_player.to_upper(), _dir_text()], "y": 50.0, "size": 11, "family": "cn", "fill": UIDraw.CREAM},
			{"text": "Esc / Start 离开 · 每台电脑控制一人", "y": 62.0, "size": 11, "family": "cn", "fill": UIDraw.CREAM}]
	var dim := Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.7)
	var faint := Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.36)
	if world.input_mode == "versus":
		var l1 := "1P：方向键 移动 · Enter 放弹"
		if _pad("p1"):
			l1 = "1P 摇杆移动 · %s 放弹 · %s 技能" % [
				_pad_label("p1", "bomb", "A"), _pad_label("p1", "skill", "X")]
		var l2 := "2P：WASD 移动 · 空格 放弹"
		if _pad("p2"):
			l2 = "2P 摇杆移动 · %s 放弹 · %s 技能" % [
				_pad_label("p2", "bomb", "A"), _pad_label("p2", "skill", "X")]
		return [
			{"text": l1, "y": 50.0, "size": 11, "family": "cn", "fill": dim},
			{"text": l2, "y": 62.0, "size": 11, "family": "cn", "fill": dim},
		]
	if _pad("p1"):
		return [
			{"text": "摇杆移动 · %s 放弹 · %s 技能" % [
				_pad_label("p1", "bomb", "A"), _pad_label("p1", "skill", "X")],
				"y": 52.0, "size": 11, "family": "cn", "fill": dim},
			{"text": "Start 暂停 · 设置中可改键",
				"y": 64.0, "size": 11, "family": "mono", "fill": faint},
		]
	return [
		{"text": _dir_text() + " 移动　·　空格 放炸弹",
			"y": 52.0, "size": 11, "family": "cn", "fill": dim},
		{"text": "Esc 暂停　·　M 静音　·　Tab 备用键",
			"y": 64.0, "size": 11, "family": "mono", "fill": faint},
	]

func _draw_top() -> void:
	var m := _meta()
	draw_rect(Rect2(0, 0, Cfg.FIELD_W, Cfg.HUD_H), UIDraw.INK, true, -1.0, true)
	UIDraw.dots(self, 0, 0, Cfg.FIELD_W, Cfg.HUD_H, UIDraw.CREAM, 0.045, 14)
	draw_rect(Rect2(0, 0, 5, Cfg.HUD_H), m["color"], true, -1.0, true)
	draw_rect(Rect2(0, Cfg.HUD_H - 1, Cfg.FIELD_W, 1), UIDraw.CREAM, true, -1.0, true)
	draw_rect(Rect2(0, 0, Cfg.FIELD_W, 1), Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.14), true, -1.0, true)
	UIDraw.text(self, m["no"], 304, 59, {"size": 98, "weight": 900, "family": "impact",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.0),
		"stroke": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.055),
		"strokeWidth": 1.3, "align": "center"})
	UIDraw.text(self, "MODE " + String(m["no"]) + "  /  " + String(m["en"]), 16, 12,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CREAM, "alpha": 0.52})
	UIDraw.text(self, m["title"], 14, 31, {"size": 20, "weight": 900, "family": "cn", "fill": UIDraw.CREAM})
	draw_rect(Rect2(16, 42, 22, 2), m["color"], true, -1.0, true)
	# 提示文案跟着「该玩家最近一次真正用过的输入设备」切换：手柄→手柄文案，键盘→原文案
	for line in hint_lines():
		UIDraw.text(self, String(line["text"]), 16, float(line["y"]),
			{"size": float(line["size"]), "weight": 500, "family": String(line["family"]),
			"fill": line["fill"], "max_width": 326})
	var right := float(Cfg.FIELD_W - 12)
	for i in range(world.players.size() - 1, -1, -1):
		_draw_chip(world.players[i], right, Cfg.HUD_H)

func _draw_chip(p, right: float, _h: float) -> void:
	var versus: bool = world.mode == "versus"
	var w := 352.0 if versus else 350.0
	var h := 28.0 if versus else 54.0
	var x := right - w
	var y := (4.0 if p.id == "p1" else 37.0) if versus else 9.0
	var color: Color = p.color
	var cy := y + h * 0.5
	UIDraw.panel(self, x, y, w, h, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 4,
		"shadow": color, "shadowX": 3, "shadowY": 3})
	var tab_w := 32.0 if versus else 36.0
	UIDraw.fill_rr(self, x, y, tab_w + 6, h, 4, color)
	draw_rect(Rect2(x + tab_w, y, 6, h), color, true, -1.0, true)
	draw_line(Vector2(x + tab_w, y), Vector2(x + tab_w, y + h), UIDraw.INK, 1.5, true)
	UIDraw.text(self, String(p.id).to_upper(), x + tab_w * 0.5, cy,
		{"size": 11 if versus else 10, "weight": 900, "family": "impact",
		"fill": UIDraw.INK, "align": "center"})
	var name: String = p.char_name if not p.char_name.is_empty() else p.name
	var hearts := (1 if p.alive else 0) if versus else Rules.life_count(p)
	var dim := 1.0 if p.alive else 0.48
	if versus:
		UIDraw.text(self, name, x + 39, y + 14, {"size": 11, "weight": 900, "family": "cn",
			"fill": UIDraw.INK, "alpha": dim})
		var sy := y + 14
		_stat("fire", x + 106, sy, str(p.power), 14, 8.5, dim)
		_stat("bomb", x + 147, sy, str(p.max_bombs), 14, 8.5, dim)
		_stat("speed", x + 188, sy, "×%.1f" % (1.0 + p.speed_bonus), 14, 8.0, dim)
		var ix := x + 246
		if p.glove:
			ItemIcons.draw(self, "glove", ix, sy, 15, dim)
			ix += 22
		if p.shield > 0:
			ItemIcons.draw(self, "shield", ix, sy, 17, dim)
			ix += 24
		if p.star_time > 0.0:
			ItemIcons.draw(self, "star", ix, sy, 17, dim)
			ix += 22
		if p.alive:
			UIDraw.heart(self, x + w - 13, sy, 12, Color("FF839B"), UIDraw.INK)
		else:
			UIDraw.text(self, "重生中", x + w - 9, sy, {"size": 11, "weight": 700, "family": "cn",
				"fill": UIDraw.INK, "align": "right", "alpha": 0.55 * dim})
	else:
		UIDraw.text(self, name, x + 45, y + 17, {"size": 12, "weight": 900, "family": "cn",
			"fill": UIDraw.INK, "alpha": dim})
		var hy := y + 17
		for i in hearts:
			UIDraw.heart(self, x + w - 17 - i * 13, hy, 11,
				_fade(Color("FF839B"), dim), _fade(UIDraw.INK, dim))
		var ry := y + 40
		_stat("fire", x + 47, ry, str(p.power), 17, 10, dim)
		_stat("bomb", x + 107, ry, str(p.max_bombs), 17, 10, dim)
		_stat("speed", x + 167, ry, "×%.1f" % (1.0 + p.speed_bonus), 17, 9, dim)
		var sx := x + 238
		if p.glove:
			ItemIcons.draw(self, "glove", sx, ry, 17, dim)
			sx += 26
		if p.shield > 0:
			ItemIcons.draw(self, "shield", sx, ry, 18, dim)
			sx += 26
		if p.star_time > 0.0:
			ItemIcons.draw(self, "star", sx, ry, 18, dim)
			UIDraw.text(self, "%.1fs" % p.star_time, sx + 13, ry, {"size": 11, "weight": 700,
				"family": "mono", "fill": UIDraw.INK, "alpha": 0.65 * dim})

func _stat(kind: String, x: float, y: float, value: String, icon: float, fsize: float, dim: float) -> void:
	ItemIcons.draw(self, kind, x, y, icon, dim)
	UIDraw.text(self, value, x + icon * 0.58 + 3, y, {"size": fsize, "weight": 900,
		"family": "mono", "fill": UIDraw.INK, "alpha": dim})

## 原作状态卡 / 技能卡用 ctx.globalAlpha 把整块内容压暗；这里把系数折进颜色 alpha。
## 底色是不透明的奶油纸，source-over 下与 globalAlpha 完全等价。
func _fade(c: Color, k: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * k)

func _draw_skills() -> void:
	for p in world.players:
		var info := Cfg.skill_cfg(p.asset_id)
		var passive := bool(info.get("passive", false))
		var key := "被动" if passive else ("F" if p.id == "p2" else ("右Shift" if world.input_mode == "versus" else "Q"))
		if not passive and _pad(p.id):
			key = _pad_label(p.id, "skill", "X")
		if not network_player.is_empty() and not passive:
			key = "远端" if p.id != network_player else (_pad_label("p1", "skill", "X") if _pad("p1") else InputSettings.first_key_label("p1_skill"))
		var key_w := maxf(40, UIDraw.measure(key, 11, 700, "mono") + 12)
		var w := maxf(230, key_w + 180)
		var height := 40.0
		var x := (Cfg.FIELD_W - w - 10) if p.id == "p2" else 10.0
		var y := Cfg.FIELD_H - height - 4
		var ready: bool = p.alive and p.skill_cd <= 0.0
		var col: Color = info["color"]
		UIDraw.panel(self, x, y, w, height, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8,
			"r": 3, "shadow": col, "shadowX": 3, "shadowY": 3})
		UIDraw.dots(self, x, y, w, height, UIDraw.INK, 0.055, 10)
		UIDraw.keycap(self, key, x + 7, y + 7, key_w, 18, col if ready else UIDraw.MUTED, UIDraw.INK)
		UIDraw.text(self, info["name"], x + key_w + 16, y + 15, {"size": 12,
			"weight": 900, "family": "cn", "fill": UIDraw.INK, "max_width": w - key_w - 80})
		var state := ""
		if passive and p.alive:
			state = "已通灵" if p.soul_evolved else "通灵"
		else:
			state = "就绪" if ready else (("%ds" % ceili(p.skill_cd)) if p.alive else "等待")
		UIDraw.text(self, state, x + w - 10, y + 14, {"size": 11, "weight": 700, "family": "mono",
			"fill": UIDraw.INK if ready else UIDraw.ORANGE, "align": "right", "alpha": 0.7 if ready else 1.0})
		if passive:
			var bar_x := x + 8
			var bar_y := y + 30
			var bar_w := w - 16
			UIDraw.fill_rr(self, bar_x, bar_y, bar_w, 5, 2.5, Color("45586B"))
			var progress := minf(1.0, float(p.soul_bombs) / float(info["bombs_to_evolve"]))
			if progress > 0.0:
				UIDraw.fill_rr(self, bar_x, bar_y, bar_w * progress, 5, 2.5,
					UIDraw.YELLOW if p.soul_evolved else col)
			for seg in range(1, int(info["bombs_to_evolve"])):
				draw_rect(Rect2(bar_x + bar_w * seg / float(info["bombs_to_evolve"]) - 1, bar_y - 1, 2, 7), UIDraw.INK, true, -1.0, true)
		else:
			draw_rect(Rect2(x + 8, y + height - 6, w - 16, 3), Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.14), true, -1.0, true)
			if p.skill_cd > 0.0:
				draw_rect(Rect2(x + 8, y + height - 6, (w - 16) * maxf(0.0, 1.0 - p.skill_cd / float(info["cd"])), 3), col, true, -1.0, true)
			else:
				draw_rect(Rect2(x + 8, y + height - 6, w - 16, 3), col if ready else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.2), true, -1.0, true)
		if not p.alive:
			# 原作：ctx.globalAlpha = .42 之后整块 panel 重画（填充与描边一起变淡），
			# 不是"实心盖住原有内容、再刷一层半透明奶油"。
			UIDraw.panel(self, x, y, w, height, {"fill": _fade(UIDraw.PAPER, 0.42),
				"stroke": _fade(UIDraw.INK, 0.42), "lw": 1.5, "r": 3})

func _draw_floating() -> void:
	var m: MatchState = world.match
	if m == null:
		return
	if world.boss_battle:
		_draw_boss_bar()
		return
	var label := ""
	var sub := ""
	var warn := false
	var tag := "TIME"
	var color := UIDraw.CYAN
	if m.mode == "dig":
		label = mmss(m.remaining)
		warn = m.remaining <= 20.0 and not m.over
		sub = "剩余障碍 %d" % world.count_bricks()
		tag = "TIME"
		color = UIDraw.CYAN
	elif m.mode == "adventure":
		var left := world.alive_enemies()
		label = "第 %d / %d 关" % [m.level, Cfg.ADVENTURE_LEVELS]
		if m.level_clear_at > 0.0:
			sub = "关卡完成 · 即将进入下一关"
		else:
			sub = "剩余敌人 %d" % left
		warn = left > 0 and left <= 2
		tag = "STAGE"
		color = UIDraw.GREEN
	else:
		label = "%d : %d" % [int(m.scores["p1"]), int(m.scores["p2"])]
		if m.sudden:
			sub = "加速决胜"
			warn = true
		else:
			sub = "第 %d 回合　先得 %d 分" % [m.round, m.target_score]
		tag = "SCORE"
		color = UIDraw.PINK
	var number_size := 26 if m.mode == "dig" else (27 if m.mode == "versus" else 18)
	var number_family := "cn" if m.mode == "adventure" else "impact"
	var lw := UIDraw.measure(label, number_size, 900, number_family)
	var sw := UIDraw.measure(sub, 11, 500, "cn")
	var w := maxf(lw + 86, sw + 24)
	var h := 40.0
	var x := Cfg.FIELD_W * 0.5 - w * 0.5
	var y := 2.0
	UIDraw.panel(self, x, y, w, h, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": UIDraw.ORANGE if warn else color, "shadowX": 4, "shadowY": 4})
	UIDraw.dots(self, x, y, w, h, UIDraw.INK, 0.055, 11)
	UIDraw.tag(self, tag, x + 10, y + 13, {"size": 11, "family": "mono",
		"fill": UIDraw.ORANGE if warn else color, "fg": UIDraw.INK, "padX": 5, "h": 12,
		"align": "left", "stroke": UIDraw.INK, "lw": 1})
	var plate_w := lw + 16
	var plate_h := 23.0
	var plate_x := x + w - plate_w - 6
	var plate_y := y + 2
	UIDraw.panel(self, plate_x, plate_y, plate_w, plate_h, {"fill": UIDraw.INK, "r": 2})
	var label_color := Color("ff7a6b") if warn else Color.WHITE
	UIDraw.text(self, label, plate_x + plate_w * 0.5, y + 13,
		{"size": number_size, "weight": 900, "family": number_family,
		"fill": label_color, "align": "center"})
	if not sub.is_empty():
		UIDraw.text(self, sub, Cfg.FIELD_W * 0.5, y + 32,
			{"size": 11, "weight": 700 if warn else 500, "family": "cn",
			"fill": UIDraw.ORANGE if warn else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.62),
			"align": "center"})
	if m.mode == "versus" and m.round_ends_at > 0.0 and not m.over:
		_draw_round_board(m)

func _draw_boss_bar() -> void:
	var boss = null
	for e in world.enemies:
		if e.type == "boss":
			boss = e
			break
	var hp: int = boss.hp if boss != null and boss.alive else 0
	var max_hp: int = boss.max_hp if boss != null else 8
	var stage := Entities.boss_stage(boss) if boss != null else {}
	var color: Color = stage.get("color", UIDraw.PINK) if not stage.is_empty() else UIDraw.PINK
	var x := 208.0
	var y := 2.0
	var w := 304.0
	var h := 43.0
	UIDraw.panel(self, x, y, w, h, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": color, "shadowX": 4, "shadowY": 4})
	UIDraw.dots(self, x, y, w, h, UIDraw.INK, 0.06, 11)
	UIDraw.tag(self, "BOSS", x + 10, y + 14, {"size": 11, "family": "mono", "fill": color,
		"fg": UIDraw.INK, "padX": 5, "h": 12, "align": "left", "stroke": UIDraw.INK, "lw": 1})
	var phase_name := "已击败"
	if hp > 0 and not stage.is_empty():
		phase_name = ["", "一 · 试探", "二 · 认真", "三 · 暴走"][clampi(int(stage["id"]), 1, 3)]
	UIDraw.text(self, "鲁鲁旦 · " + phase_name + (" · 最终战" if world.match.level == Cfg.ADVENTURE_LEVELS else ""),
		x + 56, y + 13, {"size": 11, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	UIDraw.text(self, "%d / %d" % [hp, max_hp], x + w - 10, y + 13,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "align": "right"})
	var segs := mini(max_hp, 12)
	var seg_w := (w - 20.0) / segs
	for i in segs:
		var on := i < int(ceil(float(hp) / max_hp * segs))
		draw_rect(Rect2(x + 10 + i * seg_w, y + 29, seg_w - 2, 7),
			color if on else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.14), true, -1.0, true)

func _draw_round_board(m: MatchState) -> void:
	var left_time := maxf(0.0, m.round_ends_at - world.time)
	var cy := Cfg.FIELD_H * 0.5
	draw_rect(Rect2(0, cy - 58, Cfg.FIELD_W, 116), Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.88), true, -1.0, true)
	draw_rect(Rect2(0, cy - 58, Cfg.FIELD_W, 4), UIDraw.ORANGE, true, -1.0, true)
	draw_rect(Rect2(0, cy + 54, Cfg.FIELD_W, 4), UIDraw.CYAN, true, -1.0, true)
	UIDraw.dots(self, 0, cy - 54, Cfg.FIELD_W, 108, UIDraw.CREAM, 0.05, 14)
	var who := ""
	if int(m.scores["p1"]) > int(m.scores["p2"]):
		who = "1P"
	elif int(m.scores["p2"]) > int(m.scores["p1"]):
		who = "2P"
	UIDraw.tag(self, "ROUND " + str(m.round), Cfg.FIELD_W * 0.5, cy - 38, {"size": 11,
		"family": "mono", "fill": UIDraw.YELLOW if not who.is_empty() else UIDraw.CREAM,
		"fg": UIDraw.INK, "padX": 6, "h": 13, "align": "center", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.text(self, (who + " 得分！") if not who.is_empty() else "本回合结束",
		Cfg.FIELD_W * 0.5, cy - 8, {"size": 30, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM, "align": "center"})
	UIDraw.text(self, "%.1f 秒后进入下一回合" % left_time, Cfg.FIELD_W * 0.5, cy + 27,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.68), "align": "center"})

func mmss(sec: float) -> String:
	sec = maxf(0.0, sec)
	return "%d:%02d" % [int(sec / 60.0), int(fmod(sec, 60.0))]
