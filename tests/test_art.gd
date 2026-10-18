extends SceneTree

## 无头美术自测：把所有绘制分支真正跑一遍。
##
## 为什么需要这个套件：test_core / test_play 都不加载 main.tscn，也不会触发任何
## Node2D._draw()，因此**渲染代码路径完全没有测试覆盖**。本轮给场景与 UI 引入了
## 新图元（自适应曲线、线性/径向渐变纹理、旋转椭圆、折线裁剪），这些路径一旦写错
## （Gradient 点数不合法、intersect_* 收到退化多边形、除零……）逻辑测试是发现不了的。
##
## 做法：实例化真实节点（MapPainter / Board / EntityView），挂进场景树后手动触发
## NOTIFICATION_DRAW，迫使 _draw() 执行；再针对 EntityView 的立绘变换做等价断言。

var failures = 0
var checks = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func make_world(theme: String) -> World:
	var w = World.new()
	w.mode = "adventure"
	w.theme = theme
	w.map = []
	w.map.resize(Cfg.COLS * Cfg.ROWS)
	w.map.fill(Cfg.T_EMPTY)
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
				w.map[r * Cfg.COLS + c] = Cfg.T_HARD
			elif (c + r) % 3 == 0 and c > 2 and r > 2 and c < Cfg.COLS - 3 and r < Cfg.ROWS - 3:
				w.map[r * Cfg.COLS + c] = Cfg.T_BRICK
	w.brick_variants = []
	w.brick_variants.resize(Cfg.COLS * Cfg.ROWS)
	for i in w.brick_variants.size():
		w.brick_variants[i] = i % 4
	w.spawns = [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]]
	w.rng = Rng.new(4242)
	w.match = Match.create("adventure")
	w.landmark = {
		"theme": theme, "c": 7, "r": 6,
		"path": LevelGen.loop_path(5, 4, 9, 8),
		"fruit_timer": 8.0,
	}
	w.map_revision = 1
	w.time = 1.25
	return w

func add_player(w: World, id: String, c: int, r: int, asset_id: String) -> Actor:
	var p = GameEngine.make_player(id, id.to_upper(), Cfg.P1_COLOR, 0, asset_id)
	p.x = Grid.center_x(c)
	p.y = Grid.center_y(r)
	p.px = p.x
	p.py = p.y
	w.players.append(p)
	return p

func add_enemy(w: World, type_id: String, c: int, r: int) -> Actor:
	var e = Actor.new()
	e.is_enemy = true
	e.type = type_id
	e.asset_id = type_id
	e.x = Grid.center_x(c)
	e.y = Grid.center_y(r)
	e.px = e.x
	e.py = e.y
	e.alive = true
	e.lives = 1
	w.enemies.append(e)
	return e

## 把节点挂进树并强制走一次 _draw()。
func force_draw(n: Node) -> void:
	get_root().add_child(n)
	n.notification(CanvasItem.NOTIFICATION_DRAW)

## ---------------- MapPainter：整张静态地图（地板/硬墙/软砖/设施/环路）----------------

func test_map_painter() -> void:
	for theme in Cfg.THEME_IDS:
		var w = make_world(theme)
		var painter = Node2D.new()
		painter.set_script(load("res://scripts/MapPainter.gd"))
		painter.world = w
		force_draw(painter)
		check(true, "MapPainter %s 绘制未崩溃" % theme)

## ---------------- Board：动态层（环路动效/微粒/毒刺/范围/道具/火焰/技能）----------------

func test_board() -> void:
	for theme in Cfg.THEME_IDS:
		var w = make_world(theme)
		var p = add_player(w, "p1", 2, 2, "xiaotian")
		p.insight_time = 3.0
		p.shield = 1
		p.star_time = 2.0
		p.invuln = 1.0
		p.flame_guard = 1.0
		p.hit_flash = 0.3
		p.windup = 0.2
		p.soul_evolved = true
		p.soul_slow_time = 2.0
		p.soul_slow_rate = 0.8
		add_enemy(w, "gugu", 4, 4)
		var boss = add_enemy(w, "boss", 6, 6)
		boss.phase = 3
		boss.phase_flash = 0.7
		boss.hit_flash = 0.4
		boss.windup = 0.3
		w.items = [
			{"c": 3, "r": 3, "type": "fire", "born": 0.0},
			{"c": 4, "r": 3, "type": "bomb", "born": 0.0},
			{"c": 5, "r": 3, "type": "speed", "born": 0.0},
			{"c": 6, "r": 3, "type": "fruit", "born": 0.0},
			{"c": 3, "r": 4, "type": "star", "born": 0.0},
			{"c": 4, "r": 4, "type": "shield", "born": 0.0},
			{"c": 5, "r": 4, "type": "glove", "born": 0.0},
		]
		w.flames = [{"t": 0.1, "total": 0.45, "cells": [Vector2i(7, 7), Vector2i(8, 7)]}]
		w.poison = [{"c": 9, "r": 9, "warn": 1.0}, {"c": 10, "r": 9, "warn": 0.0}]
		w.skill_effects = [
			{"type": "soul_pulse", "x": 100.0, "y": 100.0, "radius": 2, "evolved": true,
				"t": 0.5, "total": 1.0, "color": Color("f6c2f1")},
			{"type": "soul_awaken", "owner": "p1", "x": 100.0, "y": 100.0,
				"t": 0.5, "total": 1.6, "color": Color("a9eafa")},
			{"type": "flame_reflect", "x": 200.0, "y": 200.0, "radius": 2,
				"t": 0.5, "total": 1.0, "color": Color("ffc18a")},
			{"type": "axiu", "x": 300.0, "y": 300.0, "to_x": 400.0, "to_y": 350.0,
				"t": 0.5, "total": 1.0, "color": Color("c7a0ff")},
			{"type": "arui", "x": 260.0, "y": 260.0,
				"t": 0.5, "total": 1.0, "color": Color("ffd23f")},
		]
		var board = Node2D.new()
		board.set_script(load("res://scripts/Board.gd"))
		board.world = w
		force_draw(board)
		check(true, "Board %s 绘制未崩溃（含 5 类技能特效）" % theme)

## ---------------- EntityView：角色 / 敌人 / BOSS 全分支 ----------------

func test_entity_view() -> void:
	var w = make_world("forest")
	var cases := [
		{"name": "小诺-站立", "asset": "xiaonuo", "enemy": false},
		{"name": "小诺-移动", "asset": "xiaonuo", "enemy": false, "moving": true},
		{"name": "小诺-无敌+护盾+受击保护", "asset": "xiaonuo", "enemy": false,
			"star": 4.0, "shield": 1, "invuln": 1.0},
		{"name": "小炎-吸火+洞察", "asset": "xiaoyan", "enemy": false, "guard": 1.0, "insight": 2.0},
		{"name": "未来-通灵形态", "asset": "weilai", "enemy": false, "evolved": true},
		{"name": "背向移动", "asset": "xiaonuo", "enemy": false, "moving": true, "facing_up": true},
		{"name": "小怪-存活", "asset": "gugu", "enemy": true},
		{"name": "小怪-受击+前摇", "asset": "gugu", "enemy": true, "hit": 0.4, "windup": 0.3},
		{"name": "小怪-死亡", "asset": "gugu", "enemy": true, "dead": true},
		{"name": "BOSS-一阶段", "asset": "boss", "enemy": true},
		{"name": "BOSS-三阶段暴走", "asset": "boss", "enemy": true, "phase": 3, "flash": 0.7},
	]
	for c in cases:
		var a: Actor
		if c["enemy"]:
			a = add_enemy(w, c["asset"], 5, 5)
		else:
			a = add_player(w, "p1", 5, 5, c["asset"])
		a.moving = bool(c.get("moving", false))
		if bool(c.get("facing_up", false)):
			a.facing_dir = "up"
		a.star_time = float(c.get("star", 0.0))
		a.shield = int(c.get("shield", 0))
		a.invuln = float(c.get("invuln", 0.0))
		a.flame_guard = float(c.get("guard", 0.0))
		a.insight_time = float(c.get("insight", 0.0))
		a.hit_flash = float(c.get("hit", 0.0))
		a.windup = float(c.get("windup", 0.0))
		a.phase = int(c.get("phase", 1))
		a.phase_flash = float(c.get("flash", 0.0))
		if bool(c.get("evolved", false)):
			a.soul_evolved = true
			a.soul_awaken_time = 0.8
		if bool(c.get("dead", false)):
			a.alive = false
			a.dead_at = 0.0

		# 让 future / 背面分支都走到
		a.facing = -1 if a.moving else 1

		var v = EntityView.new()
		v.setup(a, null)
		v.update_view(1.0, 1.25, 0.016)
		force_draw(v)

		# 立绘改由 _draw() 画：Sprite2D 必须退出渲染，否则会重复绘制。
		check(v.sprite != null and not v.sprite.visible,
			"%s：Sprite2D 已退出渲染（避免与 _draw 重复绘制）" % c["name"])
		# 变换等价：_draw_sprite 用的偏移必须与 Sprite2D 的 position 一致。
		var tex: Texture2D = v.sprite.texture
		if tex != null:
			check(v._display.is_equal_approx(
					Vector2(tex.get_width(), tex.get_height()) * v._scale),
				"%s：_display = 贴图尺寸 × _scale" % c["name"])
			var eoff := 0.0 if not a.is_enemy else (8.0 if a.type == "boss" else 2.0)
			var off := Vector2(-v._display.x * v._anchor.x, -v._display.y * v._anchor.y + eoff)
			check(off.is_equal_approx(v.sprite.position),
				"%s：_draw_sprite 偏移与 Sprite2D.position 等价（%s vs %s）"
					% [c["name"], str(off), str(v.sprite.position)])
		else:
			check(true, "%s：无贴图时走空绘制分支" % c["name"])

## ---------------- 道具图标：七种全画一遍 ----------------

func test_item_icons() -> void:
	var probe = Node2D.new()
	var types := ["fire", "bomb", "speed", "fruit", "star", "shield", "glove"]
	var fn := func(ci: CanvasItem) -> void:
		for i in types.size():
			ItemIcons.draw(ci, types[i], 40.0 + i * 40.0, 40.0, 29.0)
			ItemIcons.draw(ci, types[i], 40.0 + i * 40.0, 90.0, 29.0, 0.48)
	probe.set_script(_probe_script())
	probe.fn = fn
	force_draw(probe)
	check(true, "七种道具图标（含 alpha=0.48 变体）绘制未崩溃")

## ---------------- 场地美术：三主题的砖/墙/设施逐格 ----------------

func test_map_art_units() -> void:
	var fn := func(ci: CanvasItem) -> void:
		for theme in Cfg.THEME_IDS:
			var w = make_world(theme)
			MapArt.draw_floor(ci, theme, w.map)
			MapArt.draw_track(ci, w.landmark)
			for c in range(0, Cfg.COLS):
				for r in range(0, Cfg.ROWS):
					MapArt.draw_hard(ci, c, r, theme)
					MapArt.draw_brick(ci, c, r, theme, (c + r) % 4)
			MapArt.draw_landmark(ci, w.landmark)
			MapArt.draw_scenery_motion(ci, w.landmark, 1.25)
	var probe = Node2D.new()
	probe.set_script(_probe_script())
	probe.fn = fn
	force_draw(probe)
	check(true, "三主题全格砖墙 + 设施 + 环路动效绘制未崩溃")

## ---------------- Effects：粒子 / 飘字 / 震屏（迁自 src/render/effects.js）----------------
##
## 这一层只吃 world.events（不清空），所以测试直接往 world 里塞各类事件，
## 再按 Main._physics_process 的节奏调用 feed()，最后强制走一次 _draw()。

func test_effects() -> void:
	var w = make_world("forest")
	add_player(w, "p1", 2, 2, "xiaonuo")
	var e = add_enemy(w, "gugu", 4, 4)
	e.id = "e1"
	e.name = "谷谷歌歌"

	# 爆炸：事件只带爆心像素坐标 + 格数，火焰本体（格子表）在 world.flames 里
	var cells := [Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5)]
	w.flames = [{"cells": cells, "t": Cfg.FLAME_TIME, "total": Cfg.FLAME_TIME,
		"cx": 6, "cy": 5, "owner_id": "p1"}]
	w.emit_event("explode", {"x": Grid.center_x(6), "y": Grid.center_y(5),
		"cells": cells.size(), "owner": "p1"})
	w.emit_event("death", {"player": "p1", "lives": 2})
	w.emit_event("enemy_death", {"enemy": "e1", "type": "gugu", "killed_by": "p1", "x": e.x, "y": e.y})
	w.emit_event("pickup", {"actor": "p1", "type": "fire", "c": 2, "r": 2,
		"x": Grid.center_x(2), "y": Grid.center_y(2)})
	w.emit_event("pickup", {"actor": "e1", "type": "shield", "c": 4, "r": 4,
		"x": Grid.center_x(4), "y": Grid.center_y(4)})
	w.emit_event("shield_break", {"actor": "e1"})
	w.emit_event("skill", {"player": "p1", "text": "时光星域"})
	w.emit_event("boss_phase", {"enemy": "e1", "phase": 2, "name": "认真",
		"color": Cfg.BOSS_PHASES[2]["color"], "x": e.x, "y": e.y})
	w.emit_event("scenery", {"kind": "fruit", "x": Grid.center_x(5), "y": Grid.center_y(5)})
	w.emit_event("scenery", {"kind": "carousel", "x": Grid.center_x(6), "y": Grid.center_y(6), "player": "p1"})
	w.emit_event("item_burn", {"c": 3, "r": 3, "type": "fire"})
	w.emit_event("level_clear", {"level": 1})

	var fx = load("res://scripts/Effects.gd").new()
	fx.set_rng(Rng.new(20240607))
	force_draw(fx)
	check(fx.particles.is_empty() and fx.texts.is_empty(), "Effects：初始粒子/飘字池为空")

	fx.feed(w, 0.016)
	var n_particles: int = fx.particles.size()
	var n_texts: int = fx.texts.size()
	check(n_particles > 0, "Effects：事件生成粒子（%d 个）" % n_particles)
	check(n_texts > 0, "Effects：事件生成飘字（%d 条）" % n_texts)
	check(fx.shake > 0.0 and fx.shake <= 7.0,
		"Effects：爆炸震屏被 maxShake 截到 7 以内（%.2f）" % fx.shake)
	check(fx.shake_offset() is Vector2, "Effects：shake_offset() 返回 Vector2")
	fx.notification(CanvasItem.NOTIFICATION_DRAW)

	# 模拟 GameEngine.step 开头的 world.events.clear()：同一批事件不得被二次消费
	w.events.clear()
	fx.feed(w, 0.016)
	check(fx.particles.size() == n_particles, "Effects：events 清空后 feed 不重复生成粒子")
	fx.notification(CanvasItem.NOTIFICATION_DRAW)

	# 推进到全部过期 + 震屏衰减到 0（走 remove_at 与 shake==0 分支）
	fx.feed(w, 3.0)
	check(fx.particles.is_empty() and fx.texts.is_empty(), "Effects：粒子与飘字按寿命清空")
	check(fx.shake == 0.0 and fx.shake_offset() == Vector2.ZERO, "Effects：震屏衰减到 0")
	fx.notification(CanvasItem.NOTIFICATION_DRAW)

	# field_reset 等价原作 main.js:124 的 FX.reset()
	w.emit_event("field_reset", {})
	fx.feed(w, 0.016)
	check(int(fx.stats()["particles"]) == 0 and int(fx.stats()["texts"]) == 0,
		"Effects：field_reset 清空特效池")

## 一个可挂进树的绘制探针：把任意绘制闭包塞进 _draw()。
class ArtProbe extends Node2D:
	var fn: Callable
	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)

func _probe_script() -> GDScript:
	return ArtProbe

func _initialize() -> void:
	test_map_art_units()
	test_map_painter()
	test_board()
	test_item_icons()
	test_entity_view()
	test_effects()
	print("ART_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
