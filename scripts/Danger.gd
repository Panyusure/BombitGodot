class_name Danger
extends RefCounted

## 威胁时间线（迁自 src/game/danger.js）：每格记录「还有多少秒会挨炸」。
## 0 = 安全；>0 = 秒数；-1 = 正在燃烧。

static func timeline(world, extra_bomb = null) -> Dictionary:
    var bombs: Array = world.bombs.duplicate()
    if extra_bomb != null:
        bombs.append(extra_bomb)

    var geometry: Array = []
    for b in bombs:
        var geo = Rules.bomb_cells(world, b, bombs)
        var seen = {}
        for cell in geo["cells"]:
            seen["%d,%d" % [cell.x, cell.y]] = true
        var forecast: Array = []
        if not b.slide.is_empty():
            forecast = Rules.slide_forecast(world, b)
        else:
            forecast = Scenery.bomb_forecast(world, b, b.fuse)
        for cell in forecast:
            var projected = Bomb.new(cell.x, cell.y)
            projected.power = b.power
            projected.owner_id = b.owner_id
            projected.break_hard = b.break_hard
            var future: Array = []
            for other in bombs:
                if other != b:
                    future.append(other)
            var geo2 = Rules.bomb_cells(world, projected, future)
            for point in geo2["cells"]:
                var key = "%d,%d" % [point.x, point.y]
                if not seen.has(key):
                    seen[key] = true
                    geo["cells"].append(point)
            for other in geo2["chain"]:
                if not geo["chain"].has(other):
                    geo["chain"].append(other)
        geometry.append(geo)

    var times: Array = []
    for b in bombs:
        times.append(maxf(0.001, b.fuse))

    var windows: Array = []
    for i in Cfg.COLS * Cfg.ROWS:
        windows.append([])

    for f in world.flames:
        for cell in f["cells"]:
            windows[cell.y * Cfg.COLS + cell.x].append([0.0, maxf(0.001, float(f["t"]))])
            for i in bombs.size():
                if bombs[i].cx == cell.x and bombs[i].cy == cell.y:
                    times[i] = 0.001

    for pass_i in bombs.size():
        var changed = false
        for i in geometry.size():
            for chained in geometry[i]["chain"]:
                var j = bombs.find(chained)
                if j >= 0 and float(times[j]) > float(times[i]):
                    times[j] = times[i]
                    changed = true
        if not changed:
            break

    for i in geometry.size():
        for cell in geometry[i]["cells"]:
            windows[cell.y * Cfg.COLS + cell.x].append([float(times[i]), float(times[i]) + Cfg.FLAME_TIME])

    return {"windows": windows, "bombs": bombs, "times": times, "cols": Cfg.COLS}

static func compute(world) -> PackedFloat32Array:
    var size = Cfg.COLS * Cfg.ROWS
    var d = PackedFloat32Array()
    d.resize(size)
    d.fill(0.0)
    var tl = timeline(world)
    var windows: Array = tl["windows"]
    for i in size:
        for w in windows[i]:
            if float(w[0]) <= 0.0:
                d[i] = -1.0
            elif d[i] != -1.0 and (d[i] == 0.0 or float(w[0]) < d[i]):
                d[i] = float(w[0])
    world.danger = d
    return d

static func at(world, c: int, r: int) -> float:
    if world.danger.is_empty() or not Grid.in_bounds(c, r):
        return 0.0
    return world.danger[r * Cfg.COLS + c]

static func is_hot(world, c: int, r: int, margin: float = Cfg.DANGER_MARGIN) -> bool:
    var v = at(world, c, r)
    if v == 0.0:
        return false
    if v < 0.0:
        return true
    return v <= margin
