class_name GameEngine
extends RefCounted

## 固定 60Hz 逻辑循环与对局装配（迁自 src/game/engine.js）。

static func make_player(id: String, label: String, color: Color, spawn_index: int, asset_id: String) -> Actor:
    var p = Actor.new()
    p.id = id
    p.name = label
    p.color = color
    p.spawn_index = spawn_index
    p.asset_id = asset_id
    p.char_name = Cfg.char_cfg(asset_id)["name"]
    p.power = Cfg.START_POWER
    p.max_bombs = Cfg.START_BOMBS
    p.lives = Cfg.START_LIVES
    return p

static func apply_level(world: World, lvl: Dictionary) -> void:
    world.map = lvl["map"]
    world.theme = String(lvl.get("theme", "forest"))
    world.landmark = lvl.get("landmark", {})
    world.brick_variants = lvl.get("variants", [])
    world.spawns = lvl.get("spawns", [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]])
    world.boss_battle = bool(lvl.get("boss_battle", false))
    world.degraded = bool(lvl.get("degraded", false))
    world.map_revision += 1
    # 整张地图被换掉 —— 地板/硬墙那一层也要重画（炸砖只动 map_revision）。
    world.map_identity += 1
    world.ai_field_cache = {}
    world.ai_break_field_cache = {}

static func create_world(cfg: Dictionary) -> World:
    var mode: String = cfg.get("mode", "adventure")
    var seed_text: String = cfg.get("seed", str(Time.get_ticks_msec()))
    var rng = Rng.new(Rng.hash_seed(seed_text))
    var spawns: Array = [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]]
    var map_mode = "versus" if mode == "versus" else mode
    var lvl = LevelGen.generate(rng, {"mode": map_mode, "spawns": spawns})

    var w = World.new()
    w.mode = mode
    w.input_mode = String(cfg.get("input_mode", "solo"))
    w.seed_text = seed_text
    w.seed_root = seed_text
    w.rng = rng
    apply_level(w, lvl)
    w.match = Match.create(mode)

    var chars: Array = cfg.get("chars", [])
    var a1: String = String(chars[0]) if chars.size() > 0 else "xiaonuo"
    var a2: String = String(chars[1]) if chars.size() > 1 else "axiu"
    w.players.append(make_player("p1", "1P", Cfg.P1_COLOR, 0, a1))
    if mode == "versus":
        w.players.append(make_player("p2", "2P", Cfg.P2_COLOR, 1, a2))

    for p in w.players:
        respawn(w, p)

    if mode == "adventure":
        Entities.spawn(w, Entities.count_for(1), 1, rng)
        Entities.prepare_briefing(w)
        w.briefing = true

    Match.begin_round(w)
    return w

static func respawn(world, p) -> void:
    var sp: Array = world.spawns[p.spawn_index] if p.spawn_index < world.spawns.size() else world.spawns[0]
    p.x = Grid.center_x(int(sp[0]))
    p.y = Grid.center_y(int(sp[1]))
    p.px = p.x
    p.py = p.y
    p.alive = true
    p.facing = 1
    p.facing_dir = "down"
    p.invuln = Cfg.INVULN_TIME
    p.star_time = 0.0
    p.carousel_travel = 0.0
    Skills.reset(p)
    p.moving = false
    p.squash = 0.0

static func clear_field(world) -> void:
    world.bombs.clear()
    world.flames.clear()
    world.poison.clear()
    world.items.clear()
    world.enemies.clear()
    world.time = 0.0
    world.time_stop = null
    world.skill_effects.clear()
    world.pending_deaths.clear()
    for p in world.players:
        p.carousel_travel = 0.0
        p.carousel_rewarded = false
    world.ai_field_cache = {}
    world.ai_break_field_cache = {}
    world.emit_event("field_reset", {})

static func next_level(world) -> void:
    var level: int = world.match.level
    var next_seed = "%s:level:%d" % [world.seed_root, level]
    var rng = Rng.new(Rng.hash_seed(next_seed))
    var lvl: Dictionary
    if level % Cfg.BOSS_EVERY == 0:
        lvl = LevelGen.generate_boss(rng, world.theme)
    else:
        lvl = LevelGen.generate(rng, {
            "mode": "adventure",
            "spawns": [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]],
            "previous_theme": world.theme,
        })
    apply_level(world, lvl)
    world.rng = rng
    world.seed_text = next_seed
    clear_field(world)

    for p in world.players:
        Skills.reset_level(p)
        Rules.change_lives(p, 1)
        respawn(world, p)

    Entities.spawn(world, Entities.count_for(level), level, rng)
    Match.begin_round(world)
    Entities.prepare_briefing(world)
    world.briefing = true
    world.emit_event("level_started", {"level": level})

static func new_round(world) -> void:
    var next_seed = "%s:round:%d" % [world.seed_root, int(world.match.round) + 1]
    var rng = Rng.new(Rng.hash_seed(next_seed))
    var lvl = LevelGen.generate(rng, {
        "mode": "versus", "spawns": world.spawns, "previous_theme": world.theme,
    })
    apply_level(world, lvl)
    world.rng = rng
    world.seed_text = next_seed
    clear_field(world)
    world.match.round += 1
    world.emit_event("round_started", {"round": world.match.round})

    for p in world.players:
        p.power = Cfg.START_POWER
        p.max_bombs = Cfg.START_BOMBS
        p.speed_bonus = 0.0
        p.shield = 0
        p.glove = false
        p.picked = {}
        p.skill_cd = 0.0
        respawn(world, p)
    Match.begin_round(world)

static func update_player(world, p, dt: float, a: Dictionary) -> void:
    if p.squash > 0.0:
        p.squash = maxf(0.0, p.squash - dt * 5.0)
    if not p.alive:
        p.moving = false
        if Match.can_respawn(world, p) and world.time - p.dead_at > Cfg.RESPAWN_DELAY:
            respawn(world, p)
            world.emit_event("respawn", {"player": p.id})
        return

    p.px = p.x
    p.py = p.y
    var hx = int(a.get("hx", 0))
    var hy = int(a.get("hy", 0))
    if hx != 0 or hy != 0:
        p.aim_x = hx if (hy == 0 or p.axis_pref != "y") else 0
        p.aim_y = 0 if p.aim_x != 0 else hy

    p.moving = Motion.step(world, p, hx, hy, dt)
    if bool(a.get("skill", false)):
        Skills.cast(world, p)
    if bool(a.get("bomb", false)):
        Rules.try_place_bomb(world, p)
    if p.glove:
        Motion.push_check(world, p, hx, hy)

static func step(world, actions: Dictionary, dt: float) -> void:
    world.events.clear()
    if world.match.over or world.briefing:
        return
    world.frame += 1
    world.time += dt
    Skills.update(world, dt)
    Scenery.update(world, dt)
    for p in world.players:
        update_player(world, p, dt, actions.get(p.id, {}))
    Danger.compute(world)
    for e in world.enemies:
        EnemyAI.update_enemy(world, e, dt)
    Rules.update_bombs(world, dt)
    Rules.update_flames(world, dt)
    Rules.update_poison(world, dt)
    Rules.update_items(world, dt)
    Rules.update_damage(world, dt)
    Rules.update_enemies(world, dt)
    Entities.sweep(world)
    Match.update(world, dt)
