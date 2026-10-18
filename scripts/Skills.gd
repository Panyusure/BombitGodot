class_name Skills
extends RefCounted

## 六位精灵技能与「未来」通灵（迁自 rules.js BI.skills）。

static func info(p) -> Dictionary:
    return Cfg.skill_cfg(p.asset_id)

static func reset(p) -> void:
    p.flame_guard = 0.0
    p.insight_time = 0.0
    p.slow_time = 0.0
    p.cast_flash = 0.0
    p.aim_x = 1
    p.aim_y = 0
    p.soul_slow_time = 0.0
    p.soul_slow_rate = 0.0
    p.soul_awaken_time = 0.0

static func reset_level(p) -> void:
    p.soul_evolved = false
    p.soul_bombs = 0
    p.soul_awaken_time = 0.0

static func charge_soul(world, p, amount: int) -> int:
    if p == null or p.asset_id != "weilai" or p.soul_evolved:
        return 0
    var need = int(Cfg.skill_cfg("weilai")["bombs_to_evolve"])
    var before: int = p.soul_bombs
    p.soul_bombs = mini(need, before + maxi(0, amount))
    if p.soul_bombs >= need:
        awaken(world, p)
    return p.soul_bombs - before

static func slow_factor(actor) -> float:
    if actor.soul_slow_time > 0.0:
        return 1.0 - actor.soul_slow_rate
    return 1.0

static func on_bomb_placed(world, p, c: int, r: int) -> void:
    if p.asset_id != "weilai":
        return
    var info_weilai: Dictionary = Cfg.skill_cfg("weilai")
    charge_soul(world, p, 1)
    var effect: Dictionary = {
        "radius": 2 if p.soul_evolved else 1,
        "rate": 0.75 if p.soul_evolved else 0.45,
        "duration": 3.0 if p.soul_evolved else 2.0,
    }
    var targets: Array = world.enemies.duplicate()
    for other in world.players:
        if other != p:
            targets.append(other)
    for target in targets:
        if not target.alive:
            continue
        if abs(Grid.col(target.x) - c) > int(effect["radius"]) \
                or abs(Grid.row(target.y) - r) > int(effect["radius"]):
            continue
        if target.soul_slow_time > 0.0 and target.soul_slow_rate > float(effect["rate"]):
            continue
        target.soul_slow_rate = effect["rate"]
        target.soul_slow_time = effect["duration"]
        target.soul_slow_owner_id = p.id
        target.soul_slow_assist_until = world.time + maxf(effect["duration"], Cfg.FUSE + Cfg.FLAME_TIME)
    world.skill_effects.append({
        "type": "soul_pulse", "x": Grid.center_x(c), "y": Grid.center_y(r),
        "radius": effect["radius"], "evolved": p.soul_evolved,
        "t": 0.8, "total": 0.8,
        "color": Color("f6c2f1") if p.soul_evolved else info_weilai["color"],
    })

static func awaken(world, p) -> void:
    if p.soul_evolved or p.asset_id != "weilai":
        return
    p.soul_evolved = true
    p.soul_bombs = int(Cfg.skill_cfg("weilai")["bombs_to_evolve"])
    p.soul_awaken_time = 1.6
    world.skill_effects.append({
        "type": "soul_awaken", "owner": p.id, "x": p.x, "y": p.y,
        "t": 1.6, "total": 1.6, "color": Color("c3f4fa"),
    })
    world.emit_event("skill", {"player": p.id, "text": "通灵觉醒"})

static func reflect_flame(world, p) -> int:
    var radius = 2
    var c = Grid.col(p.x)
    var r = Grid.row(p.y)
    var hits = 0
    for e in world.enemies:
        if e.alive and abs(Grid.col(e.x) - c) <= radius and abs(Grid.row(e.y) - r) <= radius:
            Rules.hurt_enemy(world, e, p.id)
            hits += 1
    for other in world.players:
        if other != p and other.alive and abs(Grid.col(other.x) - c) <= radius \
                and abs(Grid.row(other.y) - r) <= radius:
            Rules.hurt_player(world, other, "skill")
            hits += 1
    world.skill_effects.append({
        "type": "flame_reflect", "x": Grid.center_x(c), "y": Grid.center_y(r),
        "radius": radius, "t": 0.7, "total": 0.7, "color": Cfg.skill_cfg("xiaoyan")["color"],
    })
    return hits

static func update(world, dt: float) -> void:
    for p in world.players:
        for key in ["skill_cd", "flame_guard", "insight_time", "slow_time", "cast_flash", "soul_awaken_time"]:
            p.set(key, maxf(0.0, float(p.get(key)) - dt))
    for actor in world.players + world.enemies:
        if actor.is_enemy and world.time_stop != null and world.time_stop["remaining"] > 0.0:
            continue
        actor.soul_slow_time = maxf(0.0, actor.soul_slow_time - dt)
        if actor.soul_slow_time <= 0.0:
            actor.soul_slow_rate = 0.0
    if world.time_stop != null:
        world.time_stop["remaining"] = float(world.time_stop["remaining"]) - dt
        var caster = world.player_by_id(String(world.time_stop["owner_id"]))
        if float(world.time_stop["remaining"]) <= 0.0 or caster == null or not caster.alive:
            world.time_stop = null
    for i in range(world.skill_effects.size() - 1, -1, -1):
        var f: Dictionary = world.skill_effects[i]
        f["t"] = float(f["t"]) - dt
        if float(f["t"]) <= 0.0:
            world.skill_effects.remove_at(i)

static func cast(world, p) -> bool:
    if not p.alive or p.skill_cd > 0.0 or world.match.over or world.briefing:
        return false
    var info = info(p)
    var id: String = p.asset_id
    if bool(info.get("passive", false)):
        return false

    var x0 = p.x
    var y0 = p.y
    if id == "xiaonuo":
        world.time_stop = {"owner_id": p.id, "remaining": 3.0}
        for other in world.players:
            if other != p and other.alive:
                other.slow_time = maxf(other.slow_time, 3.0)
    elif id == "axiu":
        var dc: int = p.aim_x
        var dr: int = p.aim_y
        if dc == 0 and dr == 0:
            dc = p.facing
        var c = Grid.col(p.x)
        var r = Grid.row(p.y)
        var path: Array = []
        for step in range(1, 4):
            var nc = c + dc * step
            var nr = r + dr * step
            if not Grid.can_stand(world, Grid.center_x(nc), Grid.center_y(nr), Cfg.BOX, p.id):
                break
            path.append(Vector2i(nc, nr))
        if path.is_empty():
            return false
        var visited = {}
        for cell in path:
            for e in world.enemies:
                if not e.alive or e.invuln > 0.0 or visited.has(e.id):
                    continue
                if abs(e.x - Grid.center_x(cell.x)) < Cfg.TILE * 0.7 \
                        and abs(e.y - Grid.center_y(cell.y)) < Cfg.TILE * 0.7:
                    visited[e.id] = true
                    Rules.hurt_enemy(world, e, p.id)
            for other in world.players:
                if other != p and not visited.has(other.id) \
                        and Grid.col(other.x) == cell.x and Grid.row(other.y) == cell.y:
                    visited[other.id] = true
                    Rules.hurt_player(world, other, "skill")
        var last: Vector2i = path[path.size() - 1]
        p.x = Grid.center_x(last.x)
        p.y = Grid.center_y(last.y)
        p.px = p.x
        p.py = p.y
        p.invuln = maxf(p.invuln, 0.5)
    elif id == "arui":
        p.shield = 1
        var start = Vector2i(Grid.col(p.x), Grid.row(p.y))
        var queue: Array = [{"c": start.x, "r": start.y, "d": 0}]
        var seen = {"%d,%d" % [start.x, start.y]: true}
        var head = 0
        while head < queue.size():
            var cur: Dictionary = queue[head]
            head += 1
            if int(cur["d"]) >= 2:
                continue
            for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                var nc: int = int(cur["c"]) + d.x
                var nr: int = int(cur["r"]) + d.y
                var key = "%d,%d" % [nc, nr]
                if seen.has(key) or not Grid.in_bounds(nc, nr) or Grid.is_wall(world.map, nc, nr):
                    continue
                seen[key] = true
                queue.append({"c": nc, "r": nr, "d": int(cur["d"]) + 1})
        for e in world.enemies:
            if e.alive and seen.has("%d,%d" % [Grid.col(e.x), Grid.row(e.y)]):
                e.stun = 2.0
        for other in world.players:
            if other != p and other.alive and seen.has("%d,%d" % [Grid.col(other.x), Grid.row(other.y)]):
                other.slow_time = 2.0
    elif id == "xiaoyan":
        if p.flame_guard > 0.0:
            return false
        p.flame_guard = 4.0
    elif id == "xiaotian":
        p.insight_time = 6.0
    else:
        return false

    p.skill_cd = float(info["cd"])
    p.cast_flash = 0.8
    world.skill_effects.append({
        "type": id, "x": x0, "y": y0, "to_x": p.x, "to_y": p.y,
        "t": 0.65, "total": 0.65, "color": info["color"],
    })
    world.emit_event("skill", {"player": p.id, "text": String(info["name"])})
    return true
