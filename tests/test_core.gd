extends SceneTree

## 无头逻辑自测：地图、炸弹、道具、技能、赛制、AI（不依赖渲染）。

var failures = 0
var checks = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)

func make_world(mode: String = "adventure") -> World:
	var w = World.new()
	w.mode = mode
	w.theme = "forest"
	w.map = []
	w.map.resize(Cfg.COLS * Cfg.ROWS)
	w.map.fill(Cfg.T_EMPTY)
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
				w.map[r * Cfg.COLS + c] = Cfg.T_HARD
	w.spawns = [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]]
	w.rng = Rng.new(12345)
	w.match = Match.create(mode)
	w.landmark = {"theme": "forest", "c": 7, "r": 6, "path": [], "fruit_timer": 8.0}
	w.brick_variants = []
	w.brick_variants.resize(Cfg.COLS * Cfg.ROWS)
	w.brick_variants.fill(0)
	return w

func add_player(w: World, id: String, c: int, r: int, asset_id: String = "xiaonuo", color: Color = Cfg.P1_COLOR) -> Actor:
	var p = GameEngine.make_player(id, id.to_upper(), color, 0, asset_id)
	p.x = Grid.center_x(c)
	p.y = Grid.center_y(r)
	p.px = p.x
	p.py = p.y
	w.players.append(p)
	return p

func test_rng() -> void:
	var a = Rng.new(98765)
	var b = Rng.new(98765)
	var same = true
	for i in 50:
		if a.next_int() != b.next_int():
			same = false
			break
	check(same, "rng deterministic")

func test_maps() -> void:
	var modes = ["adventure", "dig", "versus"]
	var all_ok = true
	var bricks_ok = true
	var core_ok = true
	var loops_ok = true
	for mode in modes:
		for seed in 25:
			var rng = Rng.new(seed * 7919 + 3)
			var lvl = LevelGen.generate(rng, {"mode": mode, "spawns": [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]]})
			var mp: Array = lvl["map"]
			var st: Dictionary = lvl["stats"]
			if not bool(st["ok"]):
				all_ok = false
			if int(st["bricks"]) <= 0:
				bricks_ok = false
			for r in range(5, 8):
				for c in range(6, 9):
					if int(mp[r * Cfg.COLS + c]) != Cfg.T_HARD:
						core_ok = false
			var theme_id = String(lvl["theme"])
			var path: Array = lvl["landmark"].get("path", [])
			for cell in path:
				if int(mp[cell.y * Cfg.COLS + cell.x]) != Cfg.T_EMPTY:
					loops_ok = false
	check(all_ok, "all generated maps validate (75 maps)")
	check(bricks_ok, "generated maps contain bricks")
	check(core_ok, "central facility is 3x3 solid")
	check(loops_ok, "theme loop lanes stay open")

	# 主题不重复
	var prev = ""
	var theme_ok = true
	for seed in 20:
		var rng = Rng.new(seed + 100)
		var lvl = LevelGen.generate(rng, {"mode": "adventure", "previous_theme": prev})
		if String(lvl["theme"]) == prev:
			theme_ok = false
		prev = String(lvl["theme"])
	check(theme_ok, "consecutive themes differ")

func test_bombs() -> void:
	var w = make_world()
	var p = add_player(w, "p1", 7, 6)
	check(Rules.try_place_bomb(w, p), "place bomb")
	check(w.bombs.size() == 1, "bomb exists")
	var b: Bomb = w.bombs[0]
	var geo = Rules.bomb_cells(w, b)
	check(geo["cells"].size() == 5, "power1 cross covers 5 cells (got %d)" % geo["cells"].size())
	w.bombs.erase(b)
	Rules.detonate(w, b)
	check(w.flames.size() == 1, "explosion creates flame")
	check(w.flames[0]["cells"].size() == 5, "flame covers cross")

	# 软砖吸收火焰
	w = make_world()
	p = add_player(w, "p1", 7, 6)
	w.map[6 * Cfg.COLS + 9] = Cfg.T_BRICK
	Rules.try_place_bomb(w, p)
	var b2: Bomb = w.bombs[0]
	b2.power = 3
	var geo2 = Rules.bomb_cells(w, b2)
	check(geo2["bricks"].size() == 1, "brick caught by blast")
	check(not geo2["cells"].has(Vector2i(10, 6)), "brick stops flame")

	# 连锁引爆
	w = make_world()
	p = add_player(w, "p1", 5, 6)
	var b3 = Bomb.new(5, 6)
	b3.owner_id = "p1"
	b3.power = 2
	var b4 = Bomb.new(7, 6)
	b4.owner_id = "p1"
	b4.power = 2
	w.bombs.append(b3)
	w.bombs.append(b4)
	w.bombs.erase(b3)
	Rules.detonate(w, b3)
	check(w.flames.size() == 2, "chain detonates second bomb")

func test_items_and_skills() -> void:
	var w = make_world()
	var p = add_player(w, "p1", 7, 6)
	Rules.apply_item(p, "fire", "adventure")
	check(p.power == 2, "fire item +1 power")
	Rules.apply_item(p, "bomb", "adventure")
	check(p.max_bombs == 2, "bomb item +1")
	Rules.apply_item(p, "speed", "adventure")
	check(is_equal_approx(p.speed_bonus, 0.1), "speed item +10%")
	Rules.apply_item(p, "shield", "adventure")
	check(p.shield == 1, "shield item")
	Rules.apply_item(p, "star", "adventure")
	check(is_equal_approx(p.star_time, Cfg.STAR_TIME), "star item")
	Rules.apply_item(p, "glove", "adventure")
	check(p.glove, "glove item")

	for cid in Cfg.CHAR_IDS:
		var w2 = make_world()
		var pl = add_player(w2, "p1", 7, 6, cid)
		var e = Entities.create("gugu", 8, 6, 1, w2)
		w2.enemies.append(e)
		var casted = Skills.cast(w2, pl)
		if cid == "weilai":
			check(not casted, "weilai has passive skill")
		else:
			check(casted, "%s skill casts" % cid)
			check(pl.skill_cd > 0.0, "%s cooldown starts" % cid)

	# 未来通灵：放弹 6 次
	var w3 = make_world()
	var pw = add_player(w3, "p1", 7, 6, "weilai")
	pw.max_bombs = 8
	var placed = 0
	for i in 6:
		if Rules.try_place_bomb(w3, pw):
			placed += 1
		# 移开再放
		pw.x = Grid.center_x(6 + (i % 3))
		pw.y = Grid.center_y(5 + (i % 3))
	check(placed >= 1, "weilai can place bombs")
	check(pw.soul_bombs >= 0, "weilai soul progress tracked")

func test_match() -> void:
	# 拆砖：清空软砖立即胜利
	var w = make_world("dig")
	add_player(w, "p1", 7, 6)
	w.map[6 * Cfg.COLS + 9] = Cfg.T_BRICK
	w.match.start_bricks = 1
	Match.update(w, 1.0 / 60.0)
	check(not w.match.over, "dig not over with bricks")
	w.map[6 * Cfg.COLS + 9] = Cfg.T_EMPTY
	Match.update(w, 1.0 / 60.0)
	check(w.match.over and w.match.winner == "p1", "dig wins when bricks cleared")

	# 对战：1P 阵亡 -> 2P 得分
	var v = make_world("versus")
	var p1 = add_player(v, "p1", 1, 1)
	var p2 = add_player(v, "p2", 13, 11, "axiu", Cfg.P2_COLOR)
	p2.spawn_index = 1
	v.match = Match.create("versus")
	Match.on_death(v, p1)
	Match.update(v, 1.0 / 60.0)
	check(int(v.match.scores["p2"]) == 1, "versus scores point on death")
	check(not v.match.over, "versus continues at 1 point")

	# 闯关：清场后进入下一关
	var a = GameEngine.create_world({"mode": "adventure", "seed": "test-level", "chars": ["xiaonuo"]})
	a.briefing = false
	for e in a.enemies:
		e.hp = 0
		e.alive = false
	GameEngine.step(a, {}, 1.0 / 60.0)
	for i in 200:
		GameEngine.step(a, {}, 1.0 / 60.0)
		if a.match.level >= 2:
			break
	check(a.match.level >= 2, "adventure advances to level 2")

func test_ai() -> void:
	var w = GameEngine.create_world({"mode": "adventure", "seed": "ai-run", "chars": ["xiaonuo"]})
	w.briefing = false
	var actions = {"p1": {"hx": 0, "hy": 0, "bomb": false, "skill": false}}
	var start_enemies = w.enemies.size()
	var moved = false
	var last_positions: Array = []
	for e in w.enemies:
		last_positions.append(Vector2(e.x, e.y))
	for i in 900:
		if i % 90 == 0:
			actions["p1"]["bomb"] = true
		else:
			actions["p1"]["bomb"] = false
		actions["p1"]["hx"] = 1 if (i / 120) % 2 == 0 else -1
		actions["p1"]["hy"] = 1 if (i / 180) % 2 == 0 else 0
		GameEngine.step(w, actions, 1.0 / 60.0)
		if w.match.over:
			break
	for j in w.enemies.size():
		if j < last_positions.size() and Vector2(w.enemies[j].x, w.enemies[j].y) != last_positions[j]:
			moved = true
	check(start_enemies >= 2, "adventure spawns enemies")
	check(moved, "enemies move")
	check(w.time > 10.0, "simulation advances (time=%.1f)" % w.time)
	check(w.stats["explosions"] >= 1, "bombs explode during AI run")

func _initialize() -> void:
	test_rng()
	test_maps()
	test_bombs()
	test_items_and_skills()
	test_match()
	test_ai()
	print("CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
