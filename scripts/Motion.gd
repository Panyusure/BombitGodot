class_name Motion
extends RefCounted

## 移动手感与推弹（迁自 src/game/motion.js）。

static func move_axis(world, p, dir: int, dist: float, axis: String) -> bool:
    var dx = dir * dist if axis == "x" else 0.0
    var dy = dir * dist if axis == "y" else 0.0
    if Grid.can_stand(world, p.x + dx, p.y + dy, Cfg.BOX, p.id):
        p.x += dx
        p.y += dy
        return true

    # 转角辅助：被挡住时，若与通道中线偏差在 ASSIST 内，先对齐再通过
    if axis == "x":
        var off_y = Grid.lane_y(p.y) - p.y
        if abs(off_y) > 0.0001 and abs(off_y) <= Cfg.ASSIST:
            var sy = clampf(off_y, -dist, dist)
            if Grid.can_stand(world, p.x + dx, p.y + sy, Cfg.BOX, p.id):
                p.x += dx
                p.y += sy
                return true
            if Grid.can_stand(world, p.x, p.y + sy, Cfg.BOX, p.id):
                p.y += sy
                return true
    else:
        var off_x = Grid.lane_x(p.x) - p.x
        if abs(off_x) > 0.0001 and abs(off_x) <= Cfg.ASSIST:
            var sx = clampf(off_x, -dist, dist)
            if Grid.can_stand(world, p.x + sx, p.y + dy, Cfg.BOX, p.id):
                p.x += sx
                p.y += dy
                return true
            if Grid.can_stand(world, p.x + sx, p.y, Cfg.BOX, p.id):
                p.x += sx
                return true
    return false

static func step(world, p, hx: int, hy: int, dt: float) -> bool:
    var skill_speed = (1.30 if p.insight_time > 0.0 else 1.0) \
        * minf(0.5 if p.slow_time > 0.0 else 1.0, Skills.slow_factor(p))
    var spd = Cfg.SPEED_BASE * (1.0 + p.speed_bonus) * skill_speed * Cfg.TILE
    var dist = spd * dt

    var use_x = hx != 0
    var use_y = hy != 0
    if use_x and use_y:
        if p.axis_pref == "y":
            use_x = false
        else:
            use_y = false

    if use_x:
        p.facing = hx
        p.facing_dir = "left" if hx < 0 else "right"
    elif use_y:
        p.facing_dir = "up" if hy < 0 else "down"

    var moved = false
    if use_x:
        moved = move_axis(world, p, hx, dist, "x")
    elif use_y:
        moved = move_axis(world, p, hy, dist, "y")

    if Scenery.carry(world, p, dt, use_x or use_y):
        moved = true
    return moved

static func push_check(world, p, hx: int, hy: int) -> bool:
    if hx == 0 and hy == 0:
        return false
    if hx != 0 and hy != 0:
        if p.axis_pref == "y":
            hx = 0
        else:
            hy = 0
    for b in world.bombs:
        var pos = Grid.bomb_position(b)
        var close = Vector2(p.x, p.y).distance_to(pos) <= Cfg.BOMB_RADIUS + Cfg.PLAYER_BOMB_RADIUS + 5.0
        var ahead = ((pos.x - p.x) * hx + (pos.y - p.y) * hy) > 0.0
        var side = abs((pos.y - p.y) * hx - (pos.x - p.x) * hy) < 21.0
        if ahead and side and close and b.slide.is_empty() and b.free_for.is_empty():
            b.slide = {"dc": hx, "dr": hy}
            return true
    return false
