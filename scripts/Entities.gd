class_name Entities
extends RefCounted

## 敌人种类、出生与 BOSS 阶段（迁自 src/game/entities.js）。

static func boss_stage(e) -> Dictionary:
    if e == null or e.type != "boss":
        return {}
    var lost: int = e.max_hp - e.hp
    var index: int = maxi(int(e.phase), 3 if e.hp <= Cfg.BOSS_RAGE_HP else (2 if lost >= 2 else 1))
    index = clampi(index, 1, 3)
    return Cfg.BOSS_PHASES[index]

static func sync_boss_phase(world, e) -> void:
    var stage = boss_stage(e)
    if stage.is_empty() or not e.alive or int(stage["id"]) == e.phase:
        return
    e.phase = int(stage["id"])
    e.phase_flash = 1.4
    e.queued_bomb = false
    e.ability_cd = 0.9 if e.phase == 3 else 1.8
    if e.phase == 3:
        e.bomb_cd = minf(e.bomb_cd, 1.0)
    world.emit_event("boss_phase", {"enemy": e.id, "phase": e.phase,
        "name": stage["name"], "color": stage["color"], "x": e.x, "y": e.y})

static func difficulty_level(level: int) -> int:
    var n = clampi(level, 1, Cfg.ADVENTURE_LEVELS)
    return n if n <= 5 else 5 + (n - 5) * 2

static func count_for(level: int) -> int:
    var difficulty = difficulty_level(level)
    if level % Cfg.BOSS_EVERY == 0:
        return mini(2 + int(floor(difficulty / float(Cfg.BOSS_EVERY))), 5)
    return mini(2 + int(floor(difficulty / 2.0)), 5)

static func speed_scale(level: int) -> float:
    return minf(1.0 + 0.015 * (difficulty_level(level) - 1), 1.15)

static func pick_type(rng: Rng, level: int, index: int) -> String:
    if level % Cfg.BOSS_EVERY == 0 and index == 0:
        return "boss"
    var step = mini(3, level)
    if index == 0:
        return ["gugu", "claude", "oupao"][step - 1]
    var pool: Array = ["gugu", "claude", "oupao"].slice(0, step)
    return String(rng.pick(pool))

static func prepare_briefing(world) -> void:
    var types: Array = []
    for e in world.enemies:
        if not types.has(e.type):
            types.append(e.type)
    var fresh: Array = []
    for id in types:
        if not world.seen_enemies.has(id):
            fresh.append(id)
    world.briefing_types = types
    world.briefing_fresh = fresh
    for id in types:
        world.seen_enemies[id] = true

static func create(type_id: String, c: int, r: int, level: int, world) -> Actor:
    var t: Dictionary = Cfg.ENEMY_TYPES.get(type_id, Cfg.ENEMY_TYPES["gugu"])
    var scale = speed_scale(level)
    var e = Actor.new()
    e.id = "e%d" % world.next_entity_id
    world.next_entity_id += 1
    e.is_enemy = true
    e.type = type_id
    e.name = t["name"]
    e.phase = 1 if type_id == "boss" else 0
    e.phase_flash = 0.0
    e.color = t["color"]
    e.hp = int(t["hp"])
    e.max_hp = int(t["hp"])
    e.power = int(t["power"])
    e.bomb_gap = float(t["bomb_gap"])
    e.windup = 0.0
    e.ability_cd = 2.5
    e.level = level
    e.max_bombs = 1
    e.speed_bonus = 0.0
    e.shield = 0
    e.star_time = 0.0
    e.glove = false
    e.x = Grid.center_x(c)
    e.y = Grid.center_y(r)
    e.px = e.x
    e.py = e.y
    e.facing = 1
    e.moving = false
    e.speed = float(t["speed"]) * scale
    e.alive = true
    e.dead_at = 0.0
    e.hit_flash = 0.0
    e.invuln = 0.0
    e.tc = c
    e.tr = r
    e.bomb_cd = 3.0 + (c % 3) * 0.7
    return e

static func spawn(world, count: int, level: int, rng: Rng) -> int:
    if world.players.is_empty():
        return 0
    var pc = Grid.col(world.players[0].x)
    var pr = Grid.row(world.players[0].y)
    var track: Array = []
    if not world.landmark.is_empty():
        track = world.landmark.get("path", [])

    var cells: Array = []
    for r in range(1, Cfg.ROWS - 1):
        for c in range(1, Cfg.COLS - 1):
            if Grid.at(world.map, c, r) == Cfg.T_HARD:
                continue
            if LevelGen.open_exits(world.map, c, r) < 2:
                continue
            if abs(c - pc) + abs(r - pr) < 6:
                continue
            var taken = false
            for other in world.enemies:
                if other.alive and Grid.col(other.x) == c and Grid.row(other.y) == r:
                    taken = true
                    break
            if taken:
                continue
            var free = 0
            for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                if Grid.at(world.map, c + d.x, r + d.y) == Cfg.T_EMPTY:
                    free += 1
            var ready = false
            if Grid.at(world.map, c, r) == Cfg.T_EMPTY and free >= 2:
                var area = LevelGen.bfs(world.map, r * Cfg.COLS + c, "empty")
                var area_count = 0
                for v in area:
                    if int(v) == 1:
                        area_count += 1
                ready = area_count >= 10
            var gap = 99
            for cell in track:
                gap = mini(gap, abs(cell.x - c) + abs(cell.y - r))
            var rank = 0 if ready else (1 if Grid.at(world.map, c, r) == Cfg.T_EMPTY else 2)
            var tier = rank + (0 if gap >= 2 else (1 if gap == 1 else 2))
            cells.append({"c": c, "r": r, "tier": tier})

    rng.shuffle(cells)
    cells.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]))

    var picked: Array = []
    var made = 0
    var spacing = [4, 2, 0]
    for gap_pass in spacing:
        for cell in cells:
            if made >= count:
                break
            if bool(cell.get("used", false)):
                continue
            var spread = true
            for pcell in picked:
                if abs(int(pcell[0]) - int(cell["c"])) + abs(int(pcell[1]) - int(cell["r"])) < int(gap_pass):
                    spread = false
                    break
            if not spread:
                continue
            cell["used"] = true
            picked.append([cell["c"], cell["r"]])
            open_spawn_pocket(world, int(cell["c"]), int(cell["r"]))
            world.enemies.append(create(pick_type(rng, level, made), int(cell["c"]), int(cell["r"]), level, world))
            made += 1
        if made >= count:
            break
    return made

static func open_spawn_pocket(world, c: int, r: int) -> void:
    var empty: Array = [Vector2i(c, r)]
    var bricks: Array = []
    var seen = {"%d,%d" % [c, r]: true}
    var opened = 0
    var neighbours: Array = []
    for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
        var nc = c + d.x
        var nr = r + d.y
        if Grid.at(world.map, nc, nr) != Cfg.T_HARD:
            neighbours.append(Vector2i(nc, nr))
    neighbours.sort_custom(func(a, b): return Grid.at(world.map, a.x, a.y) < Grid.at(world.map, b.x, b.y))
    for cell in neighbours.slice(0, 2):
        world.set_tile(cell.x, cell.y, Cfg.T_EMPTY)
    while (not empty.is_empty() or not bricks.is_empty()) and opened < 10:
        var cell: Vector2i
        if not empty.is_empty():
            cell = empty.pop_back()
        else:
            cell = bricks.pop_front()
        world.set_tile(cell.x, cell.y, Cfg.T_EMPTY)
        opened += 1
        for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
            var nc = cell.x + d.x
            var nr = cell.y + d.y
            var key = "%d,%d" % [nc, nr]
            if seen.has(key) or not Grid.in_bounds(nc, nr) or Grid.at(world.map, nc, nr) == Cfg.T_HARD:
                continue
            seen[key] = true
            if Grid.at(world.map, nc, nr) == Cfg.T_EMPTY:
                empty.append(Vector2i(nc, nr))
            else:
                bricks.append(Vector2i(nc, nr))

static func sweep(world) -> void:
    for i in range(world.enemies.size() - 1, -1, -1):
        var e = world.enemies[i]
        if not e.alive and (world.time - e.dead_at) > 0.7:
            world.enemies.remove_at(i)

static func alive_count(world) -> int:
    return world.alive_enemies()

static func boss_alive(world) -> bool:
    return world.boss_alive()
