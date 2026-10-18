class_name Scenery
extends RefCounted

## 主题场景机制：古树落果、工厂传送带、游乐园木马环道（迁自 levelgen.js scenery）。

static func point(path: Array, progress: float) -> Vector2:
    if path.is_empty():
        return Vector2.ZERO
    var n = path.size()
    var i = fposmod(progress, float(n))
    var k = int(floor(i))
    var t = i - k
    var a: Vector2i = path[k % n]
    var b: Vector2i = path[(k + 1) % n]
    return Vector2(
        Grid.center_x(a.x) + (b.x - a.x) * Cfg.TILE * t,
        Grid.center_y(a.y) + (b.y - a.y) * Cfg.TILE * t
    )

static func nearest(path: Array, x: float, y: float) -> Dictionary:
    var best = {}
    for i in path.size():
        var a: Vector2i = path[i]
        var b: Vector2i = path[(i + 1) % path.size()]
        var ax = Grid.center_x(a.x)
        var ay = Grid.center_y(a.y)
        var dx = (b.x - a.x) * Cfg.TILE
        var dy = (b.y - a.y) * Cfg.TILE
        var t = clampf(((x - ax) * dx + (y - ay) * dy) / float(Cfg.TILE * Cfg.TILE), 0.0, 1.0)
        var px = ax + dx * t
        var py = ay + dy * t
        var distance = Vector2(x, y).distance_to(Vector2(px, py))
        if best.is_empty() or distance < float(best["distance"]) - 0.001 \
                or (abs(distance - float(best["distance"])) < 0.001 and t < 0.999 and float(best["t"]) >= 0.999):
            # dx / dy 是原作 nearest 一并返回的线段方向（以格为单位），
            # 传送带箭头靠它取 atan2(dy,dx) 旋转 —— 缺了这段方向，箭头会永远朝右。
            best = {"progress": i + t, "distance": distance, "x": px, "y": py,
                "dx": dx / float(Cfg.TILE), "dy": dy / float(Cfg.TILE), "t": t}
    return best

static func update(world, dt: float) -> void:
    var lm: Dictionary = world.landmark
    if lm.is_empty() or String(lm.get("theme", "")) != "forest" or world.match.over:
        return
    lm["fruit_timer"] = float(lm.get("fruit_timer", 8.0)) - dt
    if float(lm["fruit_timer"]) > 0.0:
        return
    lm["fruit_timer"] = 14.0
    var fruit_count = 0
    for it in world.items:
        if String(it["type"]) == "fruit":
            fruit_count += 1
    if fruit_count >= 2:
        return
    var cells: Array = []
    for cell in LevelGen.loop_path(5, 4, 9, 8):
        var c: int = cell.x
        var r: int = cell.y
        if Grid.at(world.map, c, r) != Cfg.T_EMPTY:
            continue
        if Rules.bomb_at(world, c, r) != null:
            continue
        if Rules.flame_at(world, c, r):
            continue
        var taken = false
        for it in world.items:
            if int(it["c"]) == c and int(it["r"]) == r:
                taken = true
                break
        if taken:
            continue
        for actor in world.players + world.enemies:
            if actor.alive and Grid.col(actor.x) == c and Grid.row(actor.y) == r:
                taken = true
                break
        if not taken:
            cells.append(cell)
    if cells.is_empty():
        return
    var cell: Vector2i = cells[world.rng.next_int() % cells.size()]
    world.items.append({"c": cell.x, "r": cell.y, "type": "fruit", "born": world.time})
    lm["last_fruit_at"] = world.time
    world.emit_event("scenery", {"sub": "fruit", "x": Grid.center_x(cell.x), "y": Grid.center_y(cell.y)})

static func bomb_forecast(world, b: Bomb, seconds: float) -> Array:
    var lm: Dictionary = world.landmark
    if lm.is_empty():
        return []
    var theme_id = String(lm.get("theme", ""))
    if theme_id != "factory" and theme_id != "park":
        return []
    if not b.slide.is_empty():
        return []
    var path: Array = lm.get("path", [])
    if path.is_empty():
        return []
    var pos = Grid.bomb_position(b)
    var at = nearest(path, pos.x, pos.y)
    if at.is_empty() or float(at["distance"]) > Cfg.TILE * 0.48:
        return []
    var on_path = false
    for cell in path:
        if cell.x == b.cx and cell.y == b.cy:
            on_path = true
            break
    if not on_path:
        return []
    var speed = 1.65 if theme_id == "factory" else 1.8
    var distance = speed * maxf(0.0, seconds)
    var steps = mini(path.size() * 2, int(ceil(distance * 2.0)))
    var cells: Array = []
    var seen = {}
    for i in range(1, steps + 1):
        var next = point(path, float(at["progress"]) + minf(i * 0.5, distance))
        var c = Grid.col(next.x)
        var r = Grid.row(next.y)
        var key = "%d,%d" % [c, r]
        if not seen.has(key):
            seen[key] = true
            cells.append(Vector2i(c, r))
    return cells

static func carry_bomb(world, b: Bomb, dt: float) -> bool:
    var lm: Dictionary = world.landmark
    if lm.is_empty():
        return false
    var theme_id = String(lm.get("theme", ""))
    if theme_id != "factory" and theme_id != "park":
        return false
    var path: Array = lm.get("path", [])
    if path.is_empty():
        return false
    var pos = Grid.bomb_position(b)
    var at = nearest(path, pos.x, pos.y)
    if at.is_empty() or float(at["distance"]) > Cfg.TILE * 0.48:
        return false
    var on_path = false
    for cell in path:
        if cell.x == b.cx and cell.y == b.cy:
            on_path = true
            break
    if not on_path:
        return false
    var speed = 1.65 if theme_id == "factory" else 1.8
    var distance = speed * Cfg.TILE * dt
    var parts = maxi(1, int(ceil(distance / 2.0)))
    var moved = false
    for i in parts:
        pos = Grid.bomb_position(b)
        at = nearest(path, pos.x, pos.y)
        var next = point(path, float(at["progress"]) + distance / parts / Cfg.TILE)
        var correction = minf(1.0, distance / parts / maxf(1.0, float(at["distance"])))
        var x = next.x + (pos.x - float(at["x"])) * (1.0 - correction)
        var y = next.y + (pos.y - float(at["y"])) * (1.0 - correction)
        if not Rules.move_bomb(world, b, x, y):
            break
        moved = true
    return moved

## Factory velocity at an actor's current lane; park riders can walk freely.
static func factory_flow(world, x: float, y: float) -> Vector2:
    if String(world.landmark.get("theme", "")) != "factory":
        return Vector2.ZERO
    var path: Array = world.landmark.get("path", [])
    if not path.has(Vector2i(Grid.col(x), Grid.row(y))):
        return Vector2.ZERO
    var at := nearest(path, x, y)
    if at.is_empty() or float(at["distance"]) > Cfg.TILE * 0.48:
        return Vector2.ZERO
    return Vector2(float(at["dx"]), float(at["dy"])) * 1.65 * Cfg.TILE

static func carry(world, p, dt: float, manual: bool) -> bool:
    var lm: Dictionary = world.landmark
    if lm.is_empty():
        p.carousel_travel = 0.0
        return false
    var path: Array = lm.get("path", [])
    if path.is_empty() or not p.alive:
        p.carousel_travel = 0.0
        return false
    var at = nearest(path, p.x, p.y)
    if at.is_empty():
        p.carousel_travel = 0.0
        return false
    var cell_c = Grid.col(p.x)
    var cell_r = Grid.row(p.y)
    var on_track = false
    for cell in path:
        if cell.x == cell_c and cell.y == cell_r:
            on_track = true
            break
    if not on_track or float(at["distance"]) > Cfg.TILE * 0.48:
        p.carousel_travel = 0.0
        return false
    var theme_id = String(lm.get("theme", ""))
    if theme_id == "park" and manual:
        p.carousel_travel = 0.0
        return false
    var speed = 1.65 if theme_id == "factory" else 1.8
    var distance = speed * Cfg.TILE * dt
    var steps = maxi(1, int(ceil(distance / 2.0)))
    var moved = 0.0
    for n in steps:
        at = nearest(path, p.x, p.y)
        var next = point(path, float(at["progress"]) + distance / steps / Cfg.TILE)
        var offset_x = p.x - float(at["x"])
        var offset_y = p.y - float(at["y"])
        var correction = 0.0 if manual else minf(1.0, distance / steps / maxf(1.0, float(at["distance"])))
        var tx = next.x + offset_x * (1.0 - correction)
        var ty = next.y + offset_y * (1.0 - correction)
        var ox = p.x
        var oy = p.y
        var can_move: bool
        if p.is_enemy:
            can_move = Grid.can_move_enemy(world, p, tx, ty)
        else:
            can_move = Grid.can_stand(world, tx, ty, Cfg.BOX, p.id)
        if can_move:
            p.x = tx
            p.y = ty
        else:
            break
        moved += Vector2(p.x - ox, p.y - oy).length()
    if theme_id == "park" and not p.is_enemy:
        p.carousel_travel += moved / Cfg.TILE
        if p.carousel_travel >= path.size() - 0.01 and not p.carousel_rewarded:
            p.carousel_rewarded = true
            p.shield = 1
            world.emit_event("scenery", {"sub": "carousel", "x": p.x, "y": p.y, "player": p.id})
    return moved > 0.0001
