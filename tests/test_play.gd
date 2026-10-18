extends SceneTree

## 完整玩法自测：BOSS 阶段/毒刺/破墙、场景机制、技能、死亡重生、长局稳定性。

var failures := 0
var checks := 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func find_boss(world):
	for e in world.enemies:
		if e.alive and e.type == "boss":
			return e
	return null

func test_boss() -> void:
	var w = GameEngine.create_world({"mode": "adventure", "seed": "boss-test", "chars": ["xiaoyan"]})
	w.briefing = false
	w.match.level = 5
	GameEngine.next_level(w)
	w.briefing = false
	var boss = find_boss(w)
	check(boss != null, "boss spawned on level 5")
	check(w.enemies.size() == 3, "boss level has 2 escorts (got %d)" % w.enemies.size())
	if boss == null:
		return
	check(boss.hp == 8, "boss starts at 8 hp")
	check(int(Entities.boss_stage(boss)["id"]) == 1, "boss starts phase 1")

	boss.invuln = 0.0
	Rules.hurt_enemy(w, boss, "p1")
	check(boss.hp == 7, "boss hp 7")
	check(int(Entities.boss_stage(boss)["id"]) == 1, "phase 1 at 7 hp")
	boss.invuln = 0.0
	Rules.hurt_enemy(w, boss, "p1")
	check(boss.hp == 6, "boss hp 6")
	check(boss.phase == 2, "phase 2 at 6 hp")
	boss.invuln = 0.0
	# 让毒刺施放
	for i in 300:
		EnemyAI.boss_ability(w, boss, 1.0 / 60.0)
		Rules.update_poison(w, 1.0 / 60.0)
		if not w.poison.is_empty():
			break
	check(not w.poison.is_empty(), "boss casts poison spikes in phase 2")

	# 打到 3 血进入暴走
	while boss.hp > 3:
		boss.invuln = 0.0
		Rules.hurt_enemy(w, boss, "p1")
	check(boss.phase == 3, "phase 3 at 3 hp")
	var stage = Entities.boss_stage(boss)
	check(bool(stage["break_hard"]), "rage stage can break hard walls")

	# 暴走炸弹破墙
	var target = Vector2i(-1, -1)
	for r in range(1, Cfg.ROWS - 1):
		for c in range(1, Cfg.COLS - 1):
			if Grid.at(w.map, c, r) == Cfg.T_HARD and Grid.can_break_hard(w, c, r):
				target = Vector2i(c, r)
				break
		if target.x >= 0:
			break
	check(target.x >= 0, "interior hard wall exists")
	if target.x >= 0:
		var from_cell = Vector2i(target.x, target.y)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if Grid.at(w.map, target.x + d.x, target.y + d.y) == Cfg.T_EMPTY:
				from_cell = Vector2i(target.x + d.x, target.y + d.y)
				break
		var b = Bomb.new(from_cell.x, from_cell.y)
		b.owner_id = boss.id
		b.power = 3
		b.break_hard = true
		w.bombs.append(b)
		w.bombs.erase(b)
		Rules.detonate(w, b)
		check(Grid.at(w.map, target.x, target.y) == Cfg.T_EMPTY, "rage bomb breaks interior hard wall")

func test_scenery() -> void:
	# 工厂传送带运送玩家
	var w = GameEngine.create_world({"mode": "dig", "seed": "belt", "chars": ["xiaonuo"]})
	w.briefing = false
	var rng = Rng.new(99)
	var lvl = LevelGen.generate(rng, {"mode": "dig", "theme": "factory"})
	GameEngine.apply_level(w, lvl)
	var p = w.players[0]
	p.x = Grid.center_x(4)
	p.y = Grid.center_y(3)
	p.px = p.x
	p.py = p.y
	var start = Vector2(p.x, p.y)
	for i in 120:
		Scenery.carry(w, p, 1.0 / 60.0, false)
	check(Vector2(p.x, p.y).distance_to(start) > 10.0, "factory belt carries player")

	# 传送带运送炸弹
	p.x = Grid.center_x(1)
	p.y = Grid.center_y(1)
	p.px = p.x
	p.py = p.y
	var b = Bomb.new(7, 3)
	b.owner_id = "p1"
	w.bombs.append(b)
	var bx = b.x
	var by = b.y
	var bomb_start = Grid.bomb_position(b)
	for i in 120:
		Scenery.carry_bomb(w, b, 1.0 / 60.0)
	check(Grid.bomb_position(b).distance_to(bomb_start) > 4.0, "factory belt carries bomb")

	# 游乐园绕圈奖励护盾
	var w2 = GameEngine.create_world({"mode": "dig", "seed": "park", "chars": ["xiaonuo"]})
	w2.briefing = false
	var lvl2 = LevelGen.generate(Rng.new(77), {"mode": "dig", "theme": "park"})
	GameEngine.apply_level(w2, lvl2)
	var p2 = w2.players[0]
	p2.x = Grid.center_x(5)
	p2.y = Grid.center_y(4)
	p2.px = p2.x
	p2.py = p2.y
	for i in 900:
		Scenery.carry(w2, p2, 1.0 / 60.0, false)
	check(p2.carousel_travel >= 15.0, "park ring travel accumulates (%.1f)" % p2.carousel_travel)
	check(p2.shield == 1, "full carousel lap grants shield")

func test_player_lifecycle() -> void:
	var w = GameEngine.create_world({"mode": "dig", "seed": "life", "chars": ["xiaonuo"]})
	w.briefing = false
	var p = w.players[0]
	p.invuln = 0.0
	var lives = p.lives
	Rules.hurt_player(w, p, "flame")
	check(not p.alive, "player dies from flame")
	check(p.lives == lives - 1, "death costs one life")
	# 推进 2 秒等待重生
	for i in 150:
		GameEngine.step(w, {}, 1.0 / 60.0)
	check(p.alive, "player respawns after delay")
	check(p.invuln > 0.0, "respawn grants invulnerability")

func test_skills() -> void:
	for cid in ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian"]:
		var w = GameEngine.create_world({"mode": "adventure", "seed": "skill-" + cid, "chars": [cid]})
		w.briefing = false
		var p = w.players[0]
		var before = p.skill_cd
		var cast = Skills.cast(w, p)
		check(cast or cid == "weilai", "%s skill can cast" % cid)
		if cast:
			check(p.skill_cd > before, "%s skill consumes cooldown" % cid)
	# 小炎吸火
	var wx = GameEngine.create_world({"mode": "adventure", "seed": "xiaoyan", "chars": ["xiaoyan"]})
	wx.briefing = false
	var px = wx.players[0]
	px.invuln = 0.0
	Skills.cast(wx, px)
	check(px.flame_guard > 0.0, "xiaoyan flame guard active")
	Rules.hurt_player(wx, px, "flame")
	check(px.alive and px.flame_guard == 0.0, "xiaoyan absorbs one explosion")

func test_stability() -> void:
	var modes = ["adventure", "dig", "versus"]
	var chars = ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian", "weilai"]
	var ok = true
	var total_steps = 0
	for mode in modes:
		for cid in chars:
			var w = GameEngine.create_world({
				"mode": mode, "seed": "stress-%s-%s" % [mode, cid],
				"chars": [cid, "axiu"], "input_mode": "versus" if mode == "versus" else "solo",
			})
			w.briefing = false
			w.match.over = false
			for step in 1800:
				total_steps += 1
				var actions = {
					"p1": {"hx": 1 if (step / 45) % 3 == 0 else (-1 if (step / 45) % 3 == 2 else 0),
						"hy": 1 if (step / 90) % 2 == 0 else (-1 if (step / 90) % 3 == 2 else 0),
						"bomb": step % 75 == 0, "skill": step % 300 == 0},
				}
				if mode == "versus":
					actions["p2"] = {"hx": -1 if (step / 60) % 2 == 0 else 1,
						"hy": 0, "bomb": step % 110 == 0, "skill": step % 420 == 0}
				GameEngine.step(w, actions, 1.0 / 60.0)
				for p in w.players:
					if is_nan(p.x) or is_nan(p.y):
						ok = false
				if w.match.over:
					break
	check(ok, "no NaN positions in stress run")
	check(total_steps > 8000, "stress covered many steps (%d)" % total_steps)

func _initialize() -> void:
	test_boss()
	test_scenery()
	test_player_lifecycle()
	test_skills()
	test_stability()
	print("PLAY_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
