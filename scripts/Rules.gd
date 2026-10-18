class_name Rules
extends RefCounted

## 放弹 / 爆炸 / 连锁 / 道具 / 伤害（迁自 src/game/rules.js）。

static func life_count(p) -> int:
    return maxi(0, mini(Cfg.MAX_LIVES, int(p.lives)))

static func change_lives(p, amount: int) -> int:
    p.lives = maxi(0, mini(Cfg.MAX_LIVES, life_count(p) + amount))
    return p.lives

# ---------------- 放炸弹 ----------------

static func try_place_bomb(world, p) -> bool:
    if not p.alive:
        return false
    var c = Grid.col(p.x)
    var r = Grid.row(p.y)
    var mine = 0
    for b in world.bombs:
        var pos = Grid.bomb_position(b)
        if (b.cx == c and b.cy == r) \
                or Vector2(pos.x - Grid.center_x(c), pos.y - Grid.center_y(r)).length() < Cfg.BOMB_RADIUS * 2.0 + 1.0:
            return false
        if b.owner_id == p.id:
            mine += 1
    if mine >= p.max_bombs:
        return false

    var bomb = Bomb.new(c, r)
    bomb.power = mini(Cfg.MAX_POWER, p.power)
    bomb.fuse = Cfg.FUSE
    bomb.fuse_total = Cfg.FUSE
    bomb.owner_id = p.id
    bomb.color = p.color
    for other in world.players:
        if other.alive and Vector2(other.x, other.y).distance_to(Vector2(Grid.center_x(c), Grid.center_y(r))) \
                < Cfg.BOMB_RADIUS + Cfg.PLAYER_BOMB_RADIUS:
            bomb.pass_for.append(other.id)
    bomb.free_for = p.id
    world.bombs.append(bomb)
    p.squash = 1.0
    Skills.on_bomb_placed(world, p, c, r)
    world.emit_event("bomb_place", {"x": Grid.center_x(c), "y": Grid.center_y(r), "owner": p.id})
    return true

# ---------------- 每帧推进炸弹 ----------------

static func update_bombs(world, dt: float) -> void:
    var pending: Array = world.bombs.duplicate()
    for i in range(pending.size() - 1, -1, -1):
        var b: Bomb = pending[i]
        if not world.bombs.has(b):
            continue

        if not b.free_for.is_empty():
            var owner = world.player_by_id(b.free_for)
            if owner == null or not Grid.bomb_overlaps_player(b, owner):
                b.free_for = ""

        if not b.pass_for.is_empty():
            var keep: Array = []
            for pid in b.pass_for:
                var pl = world.player_by_id(pid)
                if pl != null and pl.alive and Grid.bomb_overlaps_player(b, pl):
                    keep.append(pid)
            b.pass_for = keep

        var frozen: bool = b.by_enemy and world.time_stop != null and world.time_stop["remaining"] > 0.0
        if not frozen:
            if not b.slide.is_empty():
                var distance = Cfg.PUSH_SPEED * Cfg.TILE * dt
                var parts = maxi(1, int(ceil(distance / 2.0)))
                for step in parts:
                    if b.slide.is_empty():
                        break
                    var pos = Grid.bomb_position(b)
                    var dx: int = b.slide["dc"]
                    var dy: int = b.slide["dr"]
                    if not move_bomb(world, b, pos.x + dx * distance / parts, pos.y + dy * distance / parts):
                        b.slide = {}
            else:
                Scenery.carry_bomb(world, b, dt)

        if not frozen:
            b.fuse -= dt
        if b.fuse <= 0.0:
            world.bombs.erase(b)
            detonate(world, b)

## 推弹滑行时按 2px 步进预测会经过哪些格（供 AI 逃生）。
static func slide_forecast(world, b: Bomb) -> Array:
    if b.slide.is_empty():
        return []
    var probe = Bomb.new(b.cx, b.cy)
    probe.has_pos = b.has_pos
    probe.x = b.x
    probe.y = b.y
    probe.power = b.power
    probe.owner_id = b.owner_id
    var cells: Array = []
    var seen = {}
    var limit = (Cfg.COLS + Cfg.ROWS) * Cfg.TILE / 2
    for i in limit:
        var pos = Grid.bomb_position(probe)
        if not move_bomb(world, probe, pos.x + int(b.slide["dc"]) * 2, pos.y + int(b.slide["dr"]) * 2):
            break
        var key = "%d,%d" % [probe.cx, probe.cy]
        if not seen.has(key):
            seen[key] = true
            cells.append(Vector2i(probe.cx, probe.cy))
    return cells

static func move_bomb(world, b: Bomb, x: float, y: float) -> bool:
    if not Grid.can_stand_map(world.map, x, y, Cfg.BOMB_RADIUS * 2.0):
        return false
    for other in world.bombs:
        if other == b:
            continue
        var pos = Grid.bomb_position(other)
        if Vector2(pos.x - x, pos.y - y).length() < Cfg.BOMB_RADIUS * 2.0 + 1.0:
            return false
    var old = Grid.bomb_position(b)
    for p in world.players + world.enemies:
        if not p.alive or Grid.bomb_allows(b, p.id):
            continue
        var radius = Cfg.BOMB_RADIUS + (Cfg.ENEMY_BOX * 0.5 if p.is_enemy else Cfg.PLAYER_BOMB_RADIUS)
        var before = Vector2(old.x - p.x, old.y - p.y).length()
        var after = Vector2(x - p.x, y - p.y).length()
        if after < radius and after <= before + 1e-6:
            return false
    b.x = x
    b.y = y
    b.has_pos = true
    b.cx = Grid.col(x)
    b.cy = Grid.row(y)
    return true

# ---------------- 爆炸与连锁 ----------------

static func bomb_cells(world, bomb: Bomb, bombs_override = null) -> Dictionary:
    var cells: Array = [Vector2i(bomb.cx, bomb.cy)]
    var bricks: Array = []
    var hard_walls: Array = []
    var chain: Array = []
    var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
    for d in dirs:
        for k in range(1, bomb.power + 1):
            var c: int = bomb.cx + d.x * k
            var r: int = bomb.cy + d.y * k
            if not Grid.in_bounds(c, r):
                break
            var t = Grid.at(world.map, c, r)
            if t == Cfg.T_HARD:
                if bomb.break_hard and Grid.can_break_hard(world, c, r):
                    cells.append(Vector2i(c, r))
                    hard_walls.append(Vector2i(c, r))
                break
            cells.append(Vector2i(c, r))
            if t == Cfg.T_BRICK:
                bricks.append(Vector2i(c, r))
                break
            var hit = bomb_at(world, c, r, bomb, bombs_override)
            if hit != null:
                chain.append(hit)
                break
    return {"cells": cells, "bricks": bricks, "hard_walls": hard_walls, "chain": chain}

static func detonate(world, bomb: Bomb) -> void:
    var geo = bomb_cells(world, bomb)
    var cells: Array = geo["cells"]

    # 先烧地上道具，再炸砖掉道具，避免新掉落被同一发火焰烧掉
    for cell in cells:
        burn_item(world, cell.x, cell.y)

    for cell in geo["bricks"]:
        world.set_tile(cell.x, cell.y, Cfg.T_EMPTY)
        maybe_drop_item(world, cell.x, cell.y)
    for cell in geo["hard_walls"]:
        world.set_tile(cell.x, cell.y, Cfg.T_EMPTY)

    world.flames.append({
        "cells": cells, "t": Cfg.FLAME_TIME, "total": Cfg.FLAME_TIME,
        "cx": bomb.cx, "cy": bomb.cy, "owner_id": bomb.owner_id,
    })
    world.stats["explosions"] += 1
    world.emit_event("explode", {
        "x": Grid.center_x(bomb.cx), "y": Grid.center_y(bomb.cy),
        "cells": cells.size(), "owner": bomb.owner_id,
    })

    for other in geo["chain"]:
        if world.bombs.has(other):
            world.bombs.erase(other)
            detonate(world, other)

static func bomb_at(world, c: int, r: int, except = null, bombs_override = null):
    var list: Array = world.bombs if bombs_override == null else bombs_override
    for b in list:
        if b == except:
            continue
        if b.cx == c and b.cy == r:
            return b
    return null

# ---------------- 道具 ----------------

static func maybe_drop_item(world, c: int, r: int) -> void:
    if not world.rng.chance(Cfg.ITEM_DROP_RATE):
        return
    var pool = item_pool()
    world.items.append({"c": c, "r": r, "type": pool[world.rng.next_int() % pool.size()], "born": world.time})

static func burn_item(world, c: int, r: int) -> bool:
    if not world.burn_items:
        return false
    for i in range(world.items.size() - 1, -1, -1):
        var it: Dictionary = world.items[i]
        if int(it["c"]) == c and int(it["r"]) == r:
            world.items.remove_at(i)
            world.emit_event("item_burn", {"c": c, "r": r, "type": it["type"]})
            return true
    return false

static func update_items(world, dt: float) -> void:
    var collectors: Array = world.players.duplicate()
    for e in world.enemies:
        if (world.time_stop == null or world.time_stop["remaining"] <= 0.0) and e.stun <= 0.0:
            collectors.append(e)
    for i in range(world.items.size() - 1, -1, -1):
        var it: Dictionary = world.items[i]
        for p in collectors:
            if not p.alive:
                continue
            if Grid.col(p.x) == int(it["c"]) and Grid.row(p.y) == int(it["r"]):
                apply_item(p, String(it["type"]), world.mode)
                world.items.remove_at(i)
                world.emit_event("pickup", {"actor": p.id, "type": it["type"],
                    "c": it["c"], "r": it["r"], "x": Grid.center_x(int(it["c"])), "y": Grid.center_y(int(it["r"]))})
                break

static func apply_item(p, type: String, mode: String) -> void:
    match type:
        "fire":
            p.power = mini(p.power + 1, Cfg.MAX_POWER)
        "bomb":
            p.max_bombs = mini(p.max_bombs + 1, 3 if p.is_enemy else Cfg.MAX_BOMBS)
        "speed":
            var before: float = p.speed_bonus
            p.speed_bonus = minf(before + Cfg.SPEED_STEP, Cfg.SPEED_MAX_BONUS)
            if p.is_enemy:
                p.speed *= (1.0 + p.speed_bonus) / (1.0 + before)
        "fruit":
            if not p.is_enemy and mode != "versus" and life_count(p) < Cfg.MAX_LIVES:
                change_lives(p, 1)
            else:
                p.shield = 1
        "shield":
            p.shield = 1
        "star":
            p.star_time = Cfg.STAR_TIME
        "glove":
            p.glove = true
    p.picked[type] = int(p.picked.get(type, 0)) + 1

static func item_pool() -> Array:
    return ["fire", "bomb", "speed", "star", "shield", "glove"]

# ---------------- 火焰与伤害 ----------------

static func update_flames(world, dt: float) -> void:
    for i in range(world.flames.size() - 1, -1, -1):
        var f: Dictionary = world.flames[i]
        f["t"] = float(f["t"]) - dt
        if float(f["t"]) <= 0.0:
            world.flames.remove_at(i)

static func flame_source_at(world, c: int, r: int) -> Dictionary:
    for f in world.flames:
        for cell in f["cells"]:
            if cell.x == c and cell.y == r:
                return f
    return {}

static func flame_at(world, c: int, r: int) -> bool:
    return not flame_source_at(world, c, r).is_empty()

static func player_burning(world, p) -> bool:
    return flame_at(world, Grid.col(p.x), Grid.row(p.y))

static func update_poison(world, dt: float) -> void:
    if world.time_stop != null and world.time_stop["remaining"] > 0.0:
        return
    for i in range(world.poison.size() - 1, -1, -1):
        var f: Dictionary = world.poison[i]
        if float(f["warn"]) > 0.0:
            var rest = maxf(0.0, dt - float(f["warn"]))
            f["warn"] = maxf(0.0, float(f["warn"]) - dt)
            f["life"] = float(f["life"]) - rest
        else:
            f["life"] = float(f["life"]) - dt
        if float(f["life"]) <= 0.0:
            world.poison.remove_at(i)

static func poison_at(world, c: int, r: int) -> bool:
    for f in world.poison:
        if float(f["warn"]) <= 0.0 and int(f["c"]) == c and int(f["r"]) == r:
            return true
    return false

static func hurt_player(world, p, cause: String) -> void:
    if not p.alive or p.invuln > 0.0 or p.star_time > 0.0:
        return
    if cause == "flame" and p.flame_guard > 0.0:
        p.flame_guard = 0.0
        p.invuln = 0.8
        var reflected: int = Skills.reflect_flame(world, p)
        var text = "吸收爆炸 · 反弹 %d 个目标" % reflected if reflected > 0 else "吸收爆炸 · 周围无敌人"
        world.emit_event("skill", {"player": p.id, "text": text})
        return
    if p.shield > 0:
        p.shield = 0
        p.invuln = Cfg.SHIELD_INVULN_TIME
        world.emit_event("shield_break", {"actor": p.id})
    else:
        p.alive = false
        p.star_time = 0.0
        p.dead_at = world.time
        if world.mode != "versus":
            change_lives(p, -1)
        Match.on_death(world, p)
        world.emit_event("death", {"player": p.id, "lives": p.lives})

static func kill_enemy(world, e, owner_id: String) -> void:
    if not e.alive:
        return
    if owner_id == e.id and not e.soul_slow_owner_id.is_empty() and world.time <= e.soul_slow_assist_until:
        owner_id = e.soul_slow_owner_id
    e.hp = 0
    e.alive = false
    e.dead_at = world.time
    if e.type == "boss":
        world.poison.clear()
    if not owner_id.is_empty():
        Skills.charge_soul(world, world.player_by_id(owner_id), int(Cfg.skill_cfg("weilai")["bombs_to_evolve"]))
    drop_from_enemy(world, e)
    world.stats["kills"] += 1
    world.emit_event("enemy_death", {"enemy": e.id, "type": e.type, "killed_by": owner_id,
        "x": e.x, "y": e.y})

static func update_damage(world, dt: float) -> void:
    for p in world.players:
        p.star_time = maxf(0.0, p.star_time - dt)
        if p.star_time < 1e-9:
            p.star_time = 0.0
        p.invuln = maxf(0.0, p.invuln - dt)

    for p in world.players:
        if not p.alive:
            continue
        if p.star_time > 0.0:
            var reach = (Cfg.BOX + Cfg.ENEMY_BOX) * 0.5 - 7.0
            for e in world.enemies:
                if e.alive and abs(e.x - p.x) < reach and abs(e.y - p.y) < reach:
                    hurt_enemy(world, e, p.id)
            for other in world.players:
                if other != p and abs(other.x - p.x) < Cfg.BOX - 7.0 \
                        and abs(other.y - p.y) < Cfg.BOX - 7.0:
                    hurt_player(world, other, "contact")
            continue
        if p.invuln > 0.0:
            continue

        var contact_reach = (Cfg.BOX + Cfg.ENEMY_BOX) * 0.5 - 7.0
        var contact = false
        for e in world.enemies:
            if e.alive and e.star_time > 0.0 and abs(e.x - p.x) < contact_reach \
                    and abs(e.y - p.y) < contact_reach:
                contact = true
                break
        if contact:
            hurt_player(world, p, "contact")
        if not p.alive or p.invuln > 0.0:
            continue

        var burning = player_burning(world, p)
        var poisoned = poison_at(world, Grid.col(p.x), Grid.row(p.y))
        if burning or poisoned:
            hurt_player(world, p, "flame" if burning else "poison")

static func drop_from_enemy(world, e) -> void:
    if not world.rng.chance(Cfg.ENEMY_DROP_RATE):
        return
    var pool = item_pool()
    world.items.append({
        "c": Grid.col(e.x), "r": Grid.row(e.y),
        "type": pool[world.rng.next_int() % pool.size()], "born": world.time,
    })

static func update_enemies(world, dt: float) -> void:
    for e in world.enemies:
        if not e.alive:
            continue
        e.star_time = maxf(0.0, e.star_time - dt)
        if e.invuln > 0.0:
            e.invuln = maxf(0.0, e.invuln - dt)
            continue
        var flame = flame_source_at(world, Grid.col(e.x), Grid.row(e.y))
        if not flame.is_empty():
            hurt_enemy(world, e, String(flame.get("owner_id", "")))

static func hurt_enemy(world, e, owner_id: String) -> void:
    if not e.alive or e.invuln > 0.0 or e.star_time > 0.0:
        return
    e.hit_flash = 1.0
    if e.shield > 0:
        e.shield = 0
        e.invuln = Cfg.SHIELD_INVULN_TIME
        world.emit_event("shield_break", {"actor": e.id})
        return
    e.invuln = Cfg.ENEMY_HIT_INVULN
    e.hp -= 1
    if e.hp <= 0:
        kill_enemy(world, e, owner_id)
    elif e.type == "boss":
        Entities.sync_boss_phase(world, e)

static func is_invulnerable(p) -> bool:
    return not p.alive or p.invuln > 0.0 or p.star_time > 0.0 or p.shield > 0
