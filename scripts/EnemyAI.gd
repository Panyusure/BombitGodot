class_name EnemyAI
extends RefCounted

## 敌人行为：格子锁定移动、投弹前撤离检查、BOSS 毒刺（迁自 src/game/ai.js）。

const DIRS = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

static func planning_speed(e) -> float:
    var stage = Entities.boss_stage(e)
    return e.speed * (float(stage["speed"]) if not stage.is_empty() else 1.0)

static func move_speed(e) -> float:
    return planning_speed(e) * Skills.slow_factor(e)

static func bomb_quota(e) -> int:
    var stage = Entities.boss_stage(e)
    return maxi(e.max_bombs, 2 if (not stage.is_empty() and int(stage["id"]) == 3) else 1)

static func target(world, e):
    var best = null
    var distance = INF
    for p in world.players:
        if not p.alive:
            continue
        var d: float = abs(p.x - e.x) + abs(p.y - e.y)
        if d < distance:
            distance = d
            best = p
    return best

static func aggression(e) -> Dictionary:
    var level = Entities.difficulty_level(e.level)
    var profile = {
        "range": mini(9, 4 + int(floor((level - 1) / 2.0))),
        "cooldown": maxf(0.55, 1.0 - (level - 1) * 0.035),
        "hunt": minf(1.0, 0.65 + (level - 1) * 0.04),
        "ability_gap": maxf(4.8, Cfg.BOSS_POISON_GAP - maxf(0.0, level - 5) * 0.08),
    }
    var stage = Entities.boss_stage(e)
    if not stage.is_empty() and int(stage["id"]) == 2:
        profile["hunt"] = maxf(0.9, float(profile["hunt"]))
    if not stage.is_empty() and int(stage["id"]) == 3:
        profile["hunt"] = 1.0
        profile["range"] = 9
        profile["cooldown"] = float(profile["cooldown"]) * 0.55
        profile["ability_gap"] = float(profile["ability_gap"]) * Cfg.BOSS_POISON_RAGE_FACTOR
    return profile

static func field(world, e) -> Array:
    var p = target(world, e) if e != null else _first_player(world)
    if p == null or not p.alive:
        return []
    var pc = Grid.col(p.x)
    var pr = Grid.row(p.y)
    var stage = Entities.boss_stage(e)
    var break_hard = not stage.is_empty() and bool(stage["break_hard"])
    var cache_key = "break" if break_hard else "normal"
    var cache: Dictionary = world.ai_break_field_cache if break_hard else world.ai_field_cache
    if not cache.is_empty() and int(cache["map_rev"]) == world.map_revision \
            and int(cache["c"]) == pc and int(cache["r"]) == pr \
            and (world.time - float(cache["t"])) < 0.25:
        return cache["data"]
    var data = build_field(world, pc, pr, true, break_hard)
    var entry = {"map_rev": world.map_revision, "c": pc, "r": pr, "t": world.time, "data": data}
    if cache_key == "break":
        world.ai_break_field_cache = entry
    else:
        world.ai_field_cache = entry
    return data

static func _first_player(world):
    for p in world.players:
        if p.alive:
            return p
    return null

static func build_field(world, tc: int, tr: int, breakable: bool = false, break_hard: bool = false) -> Array:
    var size = Cfg.COLS * Cfg.ROWS
    var d: Array = []
    d.resize(size)
    d.fill(-1)
    if not Grid.in_bounds(tc, tr):
        return d
    if Grid.is_wall(world.map, tc, tr):
        return d
    var start = tr * Cfg.COLS + tc
    d[start] = 0

    var buckets: Array = []
    buckets.resize(size * 7 + 8)
    for i in buckets.size():
        buckets[i] = []
    buckets[0].append(start)
    var cur_cost = 0
    while cur_cost < buckets.size():
        var bucket: Array = buckets[cur_cost]
        while not bucket.is_empty():
            var idx: int = bucket.pop_back()
            if int(d[idx]) != cur_cost:
                continue
            var c = idx % Cfg.COLS
            var r = int((idx - c) / Cfg.COLS)
            var base = int(d[idx])
            var here = Grid.at(world.map, c, r)
            var step_cost = base + (7 if here == Cfg.T_HARD else (4 if (breakable and here == Cfg.T_BRICK) else 1))
            for dir in DIRS:
                var nc: int = c + dir.x
                var nr: int = r + dir.y
                if not Grid.in_bounds(nc, nr):
                    continue
                var nt = Grid.at(world.map, nc, nr)
                if nt == Cfg.T_HARD and not (break_hard and Grid.can_break_hard(world, nc, nr)):
                    continue
                if not breakable and Grid.is_wall(world.map, nc, nr):
                    continue
                var ni = nr * Cfg.COLS + nc
                if int(d[ni]) != -1 and int(d[ni]) <= step_cost:
                    continue
                d[ni] = step_cost
                if step_cost < buckets.size():
                    (buckets[step_cost] as Array).append(ni)
        cur_cost += 1
    return d

# ---------------- 每帧推进 ----------------

static func update_enemy(world, e, dt: float) -> void:
    e.px = e.x
    e.py = e.y
    if not e.alive:
        e.moving = false
        return
    Entities.sync_boss_phase(world, e)
    if world.time_stop != null and world.time_stop["remaining"] > 0.0:
        e.moving = false
        return

    var manual = not e.dir.is_empty() and e.moving and e.stun <= 0.0 and e.windup <= 0.0
    var carried = Scenery.carry(world, e, dt, manual)
    if carried:
        e.scenery_motion = true
        if not e.dir.is_empty():
            var passed = (Grid.center_x(e.tc) - e.x) * int(e.dir["x"]) \
                + (Grid.center_y(e.tr) - e.y) * int(e.dir["y"]) < -0.001
            if passed:
                e.dir = {}
                e.returning = false

    if e.stun > 0.0:
        e.stun = maxf(0.0, e.stun - dt)
        e.moving = carried
        return

    e.phase_flash = maxf(0.0, e.phase_flash - dt)
    if e.hit_flash > 0.0:
        e.hit_flash = maxf(0.0, e.hit_flash - dt * 4.0)
    if e.bomb_cd > 0.0:
        e.bomb_cd -= dt

    if e.type == "boss":
        boss_ability(world, e, dt)

    if e.windup > 0.0:
        e.windup = maxf(0.0, e.windup - dt)
        e.moving = carried
        if e.windup > 0.0:
            return
        var bc = Grid.col(e.x)
        var br = Grid.row(e.y)
        if place_bomb(world, e, bc, br):
            var profile = aggression(e)
            e.bomb_cd = (e.bomb_gap + world.rng.next_float() * 1.2) * float(profile["cooldown"])
            e.queued_bomb = false
            if not e.escape_path.is_empty():
                apply(e, e.escape_path[0])
        else:
            e.bomb_cd = 2.0
            e.dir = {}

    if e.dir.is_empty():
        decide(world, e)
        if e.dir.is_empty():
            e.moving = carried
            return

    if not e.returning and Grid.bomb_blocks(world.bombs, e.tc, e.tr, ""):
        if e.glove:
            Motion.push_check(world, e, int(e.dir["x"]), int(e.dir["y"]))
        e.tc = e.from_c if e.from_c >= 0 else Grid.col(e.x)
        e.tr = e.from_r if e.from_r >= 0 else Grid.row(e.y)
        e.returning = true

    var tx = Grid.center_x(e.tc)
    var ty = Grid.center_y(e.tr)
    var step = move_speed(e) * Cfg.TILE * dt
    var dx = tx - e.x
    var dy = ty - e.y

    if e.scenery_motion:
        move_carried_enemy(world, e, tx, ty, step, carried)
        return

    if abs(dx) + abs(dy) <= step:
        e.x = tx
        e.y = ty
        e.moving = false
        decide(world, e)
    else:
        if dx != 0.0:
            e.x += signf(dx) * minf(step, abs(dx))
            e.facing = 1 if dx > 0.0 else -1
        if dy != 0.0:
            e.y += signf(dy) * minf(step, abs(dy))
        e.moving = true

static func move_carried_enemy(world, e, tx: float, ty: float, distance: float, carried: bool) -> void:
    var moved = false
    var axes: Array = ["x", "y"] if not e.dir.is_empty() and int(e.dir["x"]) != 0 else ["y", "x"]
    if not carried:
        axes.reverse()
    for axis in axes:
        if distance <= 1e-9:
            break
        var target = tx if axis == "x" else ty
        var delta = target - float(e.get(axis))
        var amount = minf(abs(delta), distance)
        var parts = maxi(1, int(ceil(amount / 2.0)))
        for n in parts:
            if amount <= 1e-9:
                break
            var x = e.x
            var y = e.y
            var d = signf(delta) * amount / parts
            if axis == "x":
                x += d
            else:
                y += d
            if not Grid.can_move_enemy(world, e, x, y):
                e.dir = {}
                e.moving = carried or moved
                return
            e.x = x
            e.y = y
            moved = true
            if axis == "x":
                e.facing = 1 if delta > 0.0 else -1
        distance -= amount
    e.moving = carried or moved
    if abs(tx - e.x) + abs(ty - e.y) < 1e-7:
        e.scenery_motion = false
        decide(world, e)

static func decide(world, e) -> void:
    var c = Grid.col(e.x)
    var r = Grid.row(e.y)
    var opts: Array = []
    for d in DIRS:
        var nc: int = c + d.x
        var nr: int = r + d.y
        if not Grid.in_bounds(nc, nr):
            continue
        if Grid.is_wall(world.map, nc, nr):
            continue
        if Grid.bomb_blocks(world.bombs, nc, nr, ""):
            continue
        opts.append({"x": d.x, "y": d.y, "c": nc, "r": nr})
    if opts.is_empty():
        e.dir = {}
        return

    var tl = Danger.timeline(world)
    var here_windows: Array = tl["windows"][r * Cfg.COLS + c]
    if not here_windows.is_empty():
        var escape = find_escape(world, e, null, tl)
        if not escape.is_empty():
            apply(e, escape[0])
            return

    var travel = 1.0 / planning_speed(e) + 0.18
    var safe: Array = []
    for o in opts:
        if safe_during(tl, int(o["c"]), int(o["r"]), 0.0, travel):
            safe.append(o)
    if here_windows.is_empty() and safe.is_empty():
        e.dir = {}
        return
    var pool: Array = safe if not safe.is_empty() else least_dangerous_pool(world, opts)

    if e.type != "boss" or true:
        if bomb_step(world, e, pool, c, r):
            return

    var pool2: Array = pool
    if e.has_last:
        var nostep: Array = []
        for opt in pool:
            if int(opt["x"]) == -e.last_x and int(opt["y"]) == -e.last_y:
                continue
            nostep.append(opt)
        if not nostep.is_empty():
            pool2 = nostep
    apply(e, pool2[world.rng.next_int() % pool2.size()])

static func apply(e, opt) -> void:
    if not e.dir.is_empty():
        e.last_x = int(e.dir["x"])
        e.last_y = int(e.dir["y"])
        e.has_last = true
    e.dir = {"x": int(opt["x"]), "y": int(opt["y"])}
    e.from_c = Grid.col(e.x)
    e.from_r = Grid.row(e.y)
    e.returning = false
    e.tc = int(opt["c"])
    e.tr = int(opt["r"])

static func step_toward(world, e, pool) -> bool:
    var f = field(world, e)
    if f.is_empty():
        return false
    var best = null
    var best_d = 1000000
    for o in pool:
        var d: int = int(f[int(o["r"]) * Cfg.COLS + int(o["c"])])
        if d < 0:
            continue
        if d < best_d:
            best_d = d
            best = o
    if best == null:
        return false
    apply(e, best)
    return true

static func farthest_from_player(world, pool, c: int, r: int):
    var p = target(world, {"x": Grid.center_x(c), "y": Grid.center_y(r)})
    if p == null:
        return pool[0]
    var pc = Grid.col(p.x)
    var pr = Grid.row(p.y)
    var best = pool[0]
    var best_d = -1
    for o in pool:
        var d: int = abs(int(o["c"]) - pc) + abs(int(o["r"]) - pr)
        if d > best_d:
            best_d = d
            best = o
    return best

static func least_dangerous_pool(world, pool) -> Array:
    var not_burning: Array = []
    for opt in pool:
        if Danger.at(world, int(opt["c"]), int(opt["r"])) >= 0.0:
            not_burning.append(opt)
    var use: Array = not_burning if not not_burning.is_empty() else pool
    var max_v = -1.0
    for opt in use:
        var v = Danger.at(world, int(opt["c"]), int(opt["r"]))
        if v > max_v:
            max_v = v
    var out: Array = []
    for opt in use:
        if Danger.at(world, int(opt["c"]), int(opt["r"])) >= max_v:
            out.append(opt)
    return out if not out.is_empty() else pool

static func bomb_step(world, e, pool, c: int, r: int) -> bool:
    var p = target(world, e)
    if p == null or not p.alive:
        return false
    var pc = Grid.col(p.x)
    var pr = Grid.row(p.y)
    var dist: int = abs(pc - c) + abs(pr - r)

    var own = 0
    var pressure = 0
    for b in world.bombs:
        if b.owner_id == e.id:
            own += 1
        if b.by_enemy:
            pressure += 1

    var ready: bool = e.bomb_cd <= 0.0
    var profile = aggression(e)
    var stage = Entities.boss_stage(e)
    var rage = not stage.is_empty() and bool(stage["break_hard"])
    var f = field(world, e)
    var here: int = int(f[r * Cfg.COLS + c]) if not f.is_empty() else -1
    var blocked_route = false
    if not f.is_empty() and here >= 0:
        for d in DIRS:
            var nc: int = c + d.x
            var nr: int = r + d.y
            var nt = Grid.at(world.map, nc, nr)
            if (nt == Cfg.T_BRICK or (rage and Grid.can_break_hard(world, nc, nr))) \
                    and int(f[nr * Cfg.COLS + nc]) >= 0 and int(f[nr * Cfg.COLS + nc]) < here:
                blocked_route = true
                break

    var in_range: bool = dist <= int(profile["range"])
    var attack: bool = in_range and dist <= e.power + 1 and can_threaten(world, e, pc, pr)
    var pressure_limit = 4 if world.boss_battle else 2
    if ready and own < bomb_quota(e) and pressure < pressure_limit and (attack or blocked_route) \
            and not Danger.is_hot(world, c, r) and not pool.is_empty():
        var trial = Bomb.new(c, r)
        trial.power = e.power
        trial.fuse = Cfg.FUSE
        trial.owner_id = e.id
        trial.break_hard = rage
        if not find_escape(world, e, trial).is_empty():
            e.windup = 0.7
            e.dir = {}
            e.moving = false
            return true

    if (own > 0 and not rage) or (e.type == "claude" and dist < 3):
        apply(e, farthest_from_player(world, pool, c, r))
        return true
    if not rage and seek_item(world, e, pool, c, r):
        return true
    if not world.rng.chance(float(profile["hunt"])):
        return false
    return step_toward(world, e, pool)

static func can_threaten(world, e, pc: int, pr: int) -> bool:
    var c = Grid.col(e.x)
    var r = Grid.row(e.y)
    if abs(pc - c) + abs(pr - r) <= 2:
        return true
    if pc != c and pr != r:
        return false
    var dc = signi(pc - c)
    var dr = signi(pr - r)
    for k in range(1, abs(pc - c) + abs(pr - r)):
        if Grid.is_wall(world.map, c + dc * k, r + dr * k):
            return false
    return true

static func seek_item(world, e, pool, c: int, r: int) -> bool:
    var best = null
    var length = 6
    for it in world.items:
        var ic = int(it["c"])
        var ir = int(it["r"])
        if abs(ic - c) + abs(ir - r) > 5:
            continue
        var type_id = String(it["type"])
        if (type_id == "glove" and e.glove) \
                or ((type_id == "shield" or type_id == "fruit") and e.shield > 0) \
                or (type_id == "star" and e.star_time > 1.0) \
                or (type_id == "speed" and e.speed_bonus >= Cfg.SPEED_MAX_BONUS) \
                or (type_id == "fire" and e.power >= Cfg.MAX_POWER) \
                or (type_id == "bomb" and e.max_bombs >= 3):
            continue
        var f = build_field(world, ic, ir)
        var distance: int = int(f[r * Cfg.COLS + c])
        if distance <= 0 or distance >= length:
            continue
        for opt in pool:
            if int(f[int(opt["r"]) * Cfg.COLS + int(opt["c"])]) == distance - 1:
                best = opt
                length = distance
    if best == null:
        return false
    apply(e, best)
    return true

static func boss_ability(world, e, dt: float) -> void:
    Entities.sync_boss_phase(world, e)
    var stage = Entities.boss_stage(e)
    if stage.is_empty() or not bool(stage["poison"]):
        return
    e.ability_cd -= dt
    if e.ability_cd > 0.0:
        return
    e.ability_cd = float(aggression(e)["ability_gap"]) + world.rng.next_float() * 0.8
    cast_forks(world, e)

static func cast_forks(world, e) -> void:
    var stage = Entities.boss_stage(e)
    if not e.alive or stage.is_empty() or not bool(stage["poison"]):
        return
    var used = {}
    for f in world.poison:
        used["%d,%d" % [int(f["c"]), int(f["r"])]] = true
    var p = target(world, e)
    var made = 0
    var count = 6 if world.boss_battle else 12
    for attempt in 150:
        if made >= count:
            break
        var near: bool = made < (2 if world.boss_battle else 4) and p != null
        var c: int
        var r: int
        if near:
            c = Grid.col(p.x) + world.rng.randi_range(-3, 3)
            r = Grid.row(p.y) + world.rng.randi_range(-3, 3)
        else:
            c = 1 + world.rng.next_int() % (Cfg.COLS - 2)
            r = 1 + world.rng.next_int() % (Cfg.ROWS - 2)
        var key = "%d,%d" % [c, r]
        if c < 1 or r < 1 or c >= Cfg.COLS - 1 or r >= Cfg.ROWS - 1:
            continue
        if used.has(key) or Grid.is_wall(world.map, c, r):
            continue
        used[key] = true
        world.poison.append({"c": c, "r": r, "warn": Cfg.BOSS_POISON_WARN,
            "life": Cfg.BOSS_POISON_LIFE, "owner_id": e.id})
        made += 1
    if made > 0:
        world.emit_event("poison", {"enemy": e.id, "count": made})

static func place_bomb(world, e, c: int, r: int) -> bool:
    var own = 0
    var pressure = 0
    for b in world.bombs:
        if b.owner_id == e.id:
            own += 1
        if b.by_enemy:
            pressure += 1
    if own >= bomb_quota(e) or pressure >= (4 if world.boss_battle else 2):
        return false
    for other in world.bombs:
        var pos = Grid.bomb_position(other)
        if (other.cx == c and other.cy == r) \
                or Vector2(pos.x - Grid.center_x(c), pos.y - Grid.center_y(r)).length() < Cfg.BOMB_RADIUS * 2.0 + 1.0:
            return false
    var stage = Entities.boss_stage(e)
    var bomb = Bomb.new(c, r)
    bomb.power = e.power
    bomb.fuse = Cfg.FUSE
    bomb.fuse_total = Cfg.FUSE
    bomb.owner_id = e.id
    bomb.color = stage["color"] if not stage.is_empty() else e.color
    bomb.by_enemy = true
    bomb.break_hard = not stage.is_empty() and bool(stage["break_hard"])
    for p in world.players:
        if p.alive and Vector2(p.x, p.y).distance_to(Vector2(Grid.center_x(c), Grid.center_y(r))) \
                < Cfg.BOMB_RADIUS + Cfg.PLAYER_BOMB_RADIUS:
            bomb.pass_for.append(p.id)

    var route = find_escape(world, e, bomb)
    if route.is_empty():
        return false
    world.bombs.append(bomb)
    e.escape_path = route
    Danger.compute(world)
    world.emit_event("enemy_bomb", {"enemy": e.id, "x": Grid.center_x(c), "y": Grid.center_y(r)})
    return true

static func safe_during(timeline: Dictionary, c: int, r: int, start: float, end: float) -> bool:
    for w in timeline["windows"][r * Cfg.COLS + c]:
        if not (end < float(w[0]) - 0.12 or start > float(w[1]) + 0.12):
            return false
    return true

static func find_escape(world, e, bomb = null, timeline = null) -> Array:
    var tl: Dictionary = timeline if timeline != null else Danger.timeline(world, bomb)
    var c = Grid.col(e.x)
    var r = Grid.row(e.y)
    var duration = 1.0 / planning_speed(e) + 1.0 / 60.0
    var track: Array = []
    if not world.landmark.is_empty():
        track = world.landmark.get("path", [])

    if bomb != null:
        for cell in track:
            if cell.x == c and cell.y == r:
                return []

    var p = target(world, e)
    var queue: Array = [{"c": c, "r": r, "t": 0.0, "path": []}]
    var head = 0
    var visited = {"%d,%d" % [c, r]: true}
    var dirs = DIRS.duplicate()
    if p != null:
        dirs.sort_custom(func(a, b):
            var da: int = abs(c + a.x - Grid.col(p.x)) + abs(r + a.y - Grid.row(p.y))
            var db: int = abs(c + b.x - Grid.col(p.x)) + abs(r + b.y - Grid.row(p.y))
            return da < db)

    var bombs: Array = tl["bombs"]
    var times: Array = tl["times"]
    while head < queue.size():
        var cur: Dictionary = queue[head]
        head += 1
        if not cur["path"].is_empty() and safe_during(tl, int(cur["c"]), int(cur["r"]), float(cur["t"]), 60.0):
            return cur["path"]
        for d in dirs:
            var nc: int = int(cur["c"]) + d.x
            var nr: int = int(cur["r"]) + d.y
            var key = "%d,%d" % [nc, nr]
            if not Grid.in_bounds(nc, nr) or visited.has(key) or Grid.is_wall(world.map, nc, nr):
                continue
            if bomb != null:
                var on_track = false
                for cell in track:
                    if cell.x == nc and cell.y == nr:
                        on_track = true
                        break
                if on_track:
                    continue
            var arrival = float(cur["t"]) + duration
            if not safe_during(tl, int(cur["c"]), int(cur["r"]), float(cur["t"]), arrival + 0.10) \
                    or not safe_during(tl, nc, nr, float(cur["t"]), arrival + 0.10):
                continue
            var blocked = false
            for j in bombs.size():
                var b: Bomb = bombs[j]
                if b.cx == nc and b.cy == nr and float(cur["t"]) < float(times[j]) + Cfg.FLAME_TIME:
                    blocked = true
                    break
            if blocked:
                continue
            visited[key] = true
            var path: Array = cur["path"].duplicate()
            path.append({"x": d.x, "y": d.y, "c": nc, "r": nr})
            queue.append({"c": nc, "r": nr, "t": arrival, "path": path})
    return []

static func wake(world, e) -> void:
    decide(world, e)
