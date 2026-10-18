extends "res://tests/test_core.gd"

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func factory_world() -> World:
	var w := make_world()
	w.theme = "factory"
	w.landmark = {"theme": "factory", "path": LevelGen.loop_path(4, 3, 10, 9)}
	add_player(w, "p1", 1, 1)
	return w

func test_exit() -> void:
	var cases := [
		[Vector2i(6, 3), Vector2i(6, 2), Vector2i(1, 1)],
		[Vector2i(10, 5), Vector2i(11, 5), Vector2i(13, 1)],
		[Vector2i(8, 9), Vector2i(8, 10), Vector2i(13, 11)],
		[Vector2i(4, 7), Vector2i(3, 7), Vector2i(1, 11)],
	]
	for type_id in ["gugu", "claude", "oupao", "slowed"]:
		for setup in cases:
			var w := factory_world()
			var start: Vector2i = setup[0]
			var goal: Vector2i = setup[1]
			var player = w.players[0]
			player.x = Grid.center_x(setup[2].x)
			player.y = Grid.center_y(setup[2].y)
			if goal.y == 2 or goal.y == 10:
				for column in range(1, Cfg.COLS - 1):
					if column != goal.x:
						w.set_tile(column, goal.y, Cfg.T_HARD)
			else:
				for row in range(1, Cfg.ROWS - 1):
					if row != goal.y:
						w.set_tile(goal.x, row, Cfg.T_HARD)
			var enemy := Entities.create("gugu" if type_id == "slowed" else type_id, start.x, start.y, 1, w)
			if type_id == "slowed":
				enemy.soul_slow_time = 10
				enemy.soul_slow_rate = 0.55
			enemy.bomb_cd = 999
			w.enemies.append(enemy)
			EnemyAI.apply(enemy, {"x": goal.x - start.x, "y": goal.y - start.y, "c": goal.x, "r": goal.y})
			var exited := false
			var legal := true
			for frame in 240:
				w.time += 1.0 / 60.0
				EnemyAI.update_enemy(w, enemy, 1.0 / 60.0)
				legal = legal and Grid.can_stand_map(w.map, enemy.x, enemy.y, Cfg.ENEMY_BOX)
				if Vector2(enemy.x - Grid.center_x(goal.x), enemy.y - Grid.center_y(goal.y)).length() < 2:
					exited = true
					break
			check(exited, "%s exits %s toward %s with distant stationary player (%.2f, %.2f)" % [type_id, start, goal, enemy.x, enemy.y])
			check(legal, "%s belt exit %s never crosses walls" % [type_id, start])

func test_routing_and_collisions() -> void:
	var w := factory_world()
	var enemy := Entities.create("gugu", 6, 3, 1, w)
	check(not EnemyAI.can_walk_direction(w, enemy, Vector2i.LEFT), "slow actor cannot plan upstream against faster belt")
	check(EnemyAI.can_walk_direction(w, enemy, Vector2i.RIGHT), "downstream movement remains valid")
	check(EnemyAI.can_walk_direction(w, enemy, Vector2i.UP), "transverse exit remains valid")
	enemy.speed = 2
	check(EnemyAI.can_walk_direction(w, enemy, Vector2i.LEFT), "actor faster than belt can still walk upstream")
	w.landmark["theme"] = "park"
	enemy.speed = 1
	check(EnemyAI.can_walk_direction(w, enemy, Vector2i.LEFT), "manual carousel movement is unaffected")
	w.landmark["theme"] = "factory"
	enemy.x += 10
	var bomb := Bomb.new(6, 3)
	w.bombs.append(bomb)
	enemy.dir = {"x": 0, "y": -1}
	var before := Vector2(enemy.x, enemy.y).distance_to(Grid.bomb_position(bomb))
	EnemyAI.move_carried_enemy(w, enemy, Grid.center_x(6), Grid.center_y(2), 0.8, true)
	check(Vector2(enemy.x, enemy.y).distance_to(Grid.bomb_position(bomb)) >= before, "lane steering cannot pull an enemy through a bomb")

func test_patrol() -> void:
	var legal := true
	var moving := true
	for seed_value in 8:
		var w := factory_world()
		w.rng = Rng.new(seed_value + 1)
		var enemy := Entities.create("gugu", 6, 3, 1, w)
		enemy.bomb_cd = 999
		w.enemies.append(enemy)
		var visited := {}
		for frame in 1200:
			w.time += 1.0 / 60.0
			EnemyAI.update_enemy(w, enemy, 1.0 / 60.0)
			visited[Vector2i(Grid.col(enemy.x), Grid.row(enemy.y))] = true
			legal = legal and Grid.can_stand_map(w.map, enemy.x, enemy.y, Cfg.ENEMY_BOX) and not is_nan(enemy.x)
		moving = moving and visited.size() > 6
	check(legal, "long factory patrol remains collision-safe across eight seeds")
	check(moving, "enemy patrols without requiring player movement across eight seeds")

func _initialize() -> void:
	test_exit()
	test_routing_and_collisions()
	test_patrol()
	print("CONVEYOR_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
