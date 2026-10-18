class_name LevelGen
extends RefCounted

## 地图生成、出生点保护与连通性校验（迁自 src/game/levelgen.js）。

const T_EMPTY = Cfg.T_EMPTY
const T_HARD = Cfg.T_HARD
const T_BRICK = Cfg.T_BRICK

static func open_exits(map_data: Array, c: int, r: int) -> int:
    var n = 0
    if c + 1 < Cfg.COLS and Grid.at(map_data, c + 1, r) != T_HARD:
        n += 1
    if c - 1 >= 0 and Grid.at(map_data, c - 1, r) != T_HARD:
        n += 1
    if r + 1 < Cfg.ROWS and Grid.at(map_data, c, r + 1) != T_HARD:
        n += 1
    if r - 1 >= 0 and Grid.at(map_data, c, r - 1) != T_HARD:
        n += 1
    return n

static func structure_ok(map_data: Array, min_exits: int) -> bool:
    var total = 0
    var start = -1
    for i in range(Cfg.COLS * Cfg.ROWS):
        if int(map_data[i]) == T_HARD:
            continue
        total += 1
        if start < 0:
            start = i
    if start < 0:
        return false

    if min_exits > 0:
        for r in Cfg.ROWS:
            for c in Cfg.COLS:
                if int(map_data[r * Cfg.COLS + c]) == T_HARD:
                    continue
                if open_exits(map_data, c, r) < min_exits:
                    return false

    var vis = []
    vis.resize(Cfg.COLS * Cfg.ROWS)
    vis.fill(0)
    var queue: Array = [start]
    var head = 0
    var seen = 1
    vis[start] = 1
    while head < queue.size():
        var cur: int = queue[head]
        head += 1
        var cc = cur % Cfg.COLS
        var rr = int((cur - cc) / Cfg.COLS)
        var neighbours = [[cc + 1, rr], [cc - 1, rr], [cc, rr + 1], [cc, rr - 1]]
        for nb in neighbours:
            var nc: int = nb[0]
            var nr: int = nb[1]
            if not Grid.in_bounds(nc, nr):
                continue
            var ni = nr * Cfg.COLS + nc
            if int(vis[ni]) == 1 or int(map_data[ni]) == T_HARD:
                continue
            vis[ni] = 1
            seen += 1
            queue.append(ni)
    return seen == total

static func scenic_lane(theme: String, c: int, r: int) -> bool:
    if theme == "factory":
        return c >= 4 and c <= 10 and r >= 3 and r <= 9
    if theme == "park":
        return c >= 4 and c <= 10 and r >= 3 and r <= 9
    if theme == "forest":
        return c >= 5 and c <= 9 and r >= 4 and r <= 8
    return false

static func reserved_track(theme: String, c: int, r: int) -> bool:
    if theme == "forest":
        return false
    var left = 4 if theme == "factory" else 5
    var right = 10 if theme == "factory" else 9
    var top = 3 if theme == "factory" else 4
    var bottom = 9 if theme == "factory" else 8
    return c >= left and c <= right and r >= top and r <= bottom \
        and (c == left or c == right or r == top or r == bottom)

static func loop_path(left: int, top: int, right: int, bottom: int) -> Array:
    var path: Array = []
    for c in range(left, right):
        path.append(Vector2i(c, top))
    for r in range(top, bottom):
        path.append(Vector2i(right, r))
    for c in range(right, left, -1):
        path.append(Vector2i(c, bottom))
    for r in range(bottom, top, -1):
        path.append(Vector2i(left, r))
    return path

static func decorate(map_data: Array, theme_id: String, rng: Rng) -> Dictionary:
    var path: Array = []
    if theme_id == "factory":
        path = loop_path(4, 3, 10, 9)
    elif theme_id == "park":
        path = loop_path(5, 4, 9, 8)
    var landmark = {
        "theme": theme_id, "c": 7, "r": 6, "path": path,
        "fruit_timer": 8.0, "last_fruit_at": 0.0, "path_len": path.size(),
    }
    var variants = []
    variants.resize(Cfg.COLS * Cfg.ROWS)
    variants.fill(0)
    var bricks: Array = []
    for i in range(Cfg.COLS * Cfg.ROWS):
        if int(map_data[i]) == T_BRICK:
            bricks.append(i)
    rng.shuffle(bricks)
    var variant_count = 4 if theme_id == "forest" else 3
    for index in bricks.size():
        variants[int(bricks[index])] = index % variant_count
    return {"map": map_data, "landmark": landmark, "variants": variants, "theme": theme_id}

static func place_walls(rng: Rng, map_data: Array, spawns: Array, target: int, min_exits: int, theme_id: String) -> int:
    var candidates: Array = []
    for r in range(1, Cfg.ROWS - 1):
        for c in range(1, Cfg.COLS - 1):
            var near = false
            for s in spawns:
                if abs(int(s[0]) - c) + abs(int(s[1]) - r) <= Cfg.SAFE_RADIUS:
                    near = true
                    break
            if not near and not scenic_lane(theme_id, c, r):
                candidates.append([c, r])

    for i in range(candidates.size() - 1, 0, -1):
        var j = rng.next_int() % (i + 1)
        var tmp = candidates[i]
        candidates[i] = candidates[j]
        candidates[j] = tmp

    var placed = 0
    for cand in candidates:
        if placed >= target:
            break
        var cc: int = cand[0]
        var rr: int = cand[1]
        var idx = rr * Cfg.COLS + cc
        map_data[idx] = T_HARD
        if structure_ok(map_data, min_exits):
            placed += 1
        else:
            map_data[idx] = T_EMPTY
    return placed

static func clear_area(map_data: Array, c0: int, r0: int, radius: int) -> void:
    for dr in range(-radius, radius + 1):
        for dc in range(-radius, radius + 1):
            if abs(dc) + abs(dr) > radius:
                continue
            var c = c0 + dc
            var r = r0 + dr
            if not Grid.in_bounds(c, r):
                continue
            if int(map_data[r * Cfg.COLS + c]) == T_BRICK:
                map_data[r * Cfg.COLS + c] = T_EMPTY

static func build_map(rng: Rng, rate: float, spawns: Array, theme_id: String) -> Dictionary:
    var map_data: Array = []
    map_data.resize(Cfg.COLS * Cfg.ROWS)
    map_data.fill(T_EMPTY)

    for r in Cfg.ROWS:
        for c in Cfg.COLS:
            if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
                map_data[r * Cfg.COLS + c] = T_HARD

    for r in range(5, 8):
        for c in range(6, 9):
            map_data[r * Cfg.COLS + c] = T_HARD

    var interior = (Cfg.COLS - 2) * (Cfg.ROWS - 2)
    var wall_target = maxi(0, int(round(interior * Cfg.WALL_RATE)) - 9)
    place_walls(rng, map_data, spawns, wall_target, Cfg.MIN_EXITS, theme_id)

    for i in range(Cfg.COLS * Cfg.ROWS):
        var rr = int((i - i % Cfg.COLS) / Cfg.COLS)
        var cc = i % Cfg.COLS
        var density = 0.0 if reserved_track(theme_id, cc, rr) else rate
        if int(map_data[i]) == T_EMPTY and rng.next_float() < density:
            map_data[i] = T_BRICK

    for s in spawns:
        clear_area(map_data, int(s[0]), int(s[1]), Cfg.SAFE_RADIUS)
    return decorate(map_data, theme_id, rng)

static func bfs(map_data: Array, start_index: int, mode: String) -> Array:
    var vis = []
    vis.resize(Cfg.COLS * Cfg.ROWS)
    vis.fill(0)
    var queue: Array = [start_index]
    var head = 0
    vis[start_index] = 1
    while head < queue.size():
        var cur: int = queue[head]
        head += 1
        var c = cur % Cfg.COLS
        var r = int((cur - c) / Cfg.COLS)
        var nb = [[c + 1, r], [c - 1, r], [c, r + 1], [c, r - 1]]
        for item in nb:
            var nc: int = item[0]
            var nr: int = item[1]
            if not Grid.in_bounds(nc, nr):
                continue
            var ni = nr * Cfg.COLS + nc
            if int(vis[ni]) == 1:
                continue
            var v = int(map_data[ni])
            if mode == "empty" and v != T_EMPTY:
                continue
            if mode == "not_hard" and v == T_HARD:
                continue
            vis[ni] = 1
            queue.append(ni)
    return vis

static func validate(map_data: Array, spawns: Array, _mode: String) -> Dictionary:
    var start = int(spawns[0][1]) * Cfg.COLS + int(spawns[0][0])
    var vis = bfs(map_data, start, "not_hard")

    var spawns_ok = true
    for s in spawns:
        if int(vis[int(s[1]) * Cfg.COLS + int(s[0])]) != 1:
            spawns_ok = false
            break

    var total = 0
    var bricks = 0
    var dead_bricks = 0
    var reachable_open = 0
    var reachable_bricks = 0
    for r in Cfg.ROWS:
        for c in Cfg.COLS:
            var i = r * Cfg.COLS + c
            var v = int(map_data[i])
            if v == T_HARD:
                continue
            total += 1
            if int(vis[i]) == 1:
                if v == T_BRICK:
                    reachable_bricks += 1
                else:
                    reachable_open += 1
            if v != T_BRICK:
                continue
            bricks += 1
            var touch = false
            for nb in [[c + 1, r], [c - 1, r], [c, r + 1], [c, r - 1]]:
                var nc: int = nb[0]
                var nr: int = nb[1]
                if not Grid.in_bounds(nc, nr):
                    continue
                if int(vis[nr * Cfg.COLS + nc]) == 1:
                    touch = true
                    break
            if not touch:
                dead_bricks += 1

    var vis_now = bfs(map_data, start, "empty")
    var open_now = 0
    for v in vis_now:
        if int(v) == 1:
            open_now += 1

    var dead_ends = 0
    if Cfg.MIN_EXITS > 0:
        for rr in Cfg.ROWS:
            for cc in Cfg.COLS:
                if int(map_data[rr * Cfg.COLS + cc]) == T_HARD:
                    continue
                if open_exits(map_data, cc, rr) < Cfg.MIN_EXITS:
                    dead_ends += 1

    return {
        "ok": spawns_ok and dead_bricks == 0 and dead_ends == 0,
        "spawns_ok": spawns_ok, "bricks": bricks, "dead_bricks": dead_bricks,
        "dead_ends": dead_ends, "reachable_open": reachable_open,
        "reachable_bricks": reachable_bricks, "open_now": open_now, "total": total,
    }

static func generate(rng: Rng, opts: Dictionary) -> Dictionary:
    var mode: String = opts.get("mode", "versus")
    var previous: String = opts.get("previous_theme", "")
    var themes: Array = []
    for t in Cfg.THEME_IDS:
        if t != previous:
            themes.append(t)
    var requested: String = opts.get("theme", "")
    var theme_id = requested
    if not Cfg.THEMES.has(theme_id) or theme_id == previous:
        theme_id = String(rng.pick(themes))
    var spawns: Array = opts.get("spawns", [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]])
    var rate: float = float(Cfg.BRICK_RATE.get(mode, 0.42))

    for attempt in range(1, Cfg.CONNECT_TRIES + 1):
        var built = build_map(rng, rate, spawns, theme_id)
        var map_data: Array = built["map"]
        var v = validate(map_data, spawns, mode)
        if bool(v["ok"]):
            built["spawns"] = spawns
            built["attempts"] = attempt
            built["stats"] = v
            built["degraded"] = false
            return built

    var sparse = build_map(rng, 0.12, spawns, theme_id)
    var sparse_map: Array = sparse["map"]
    var sv = validate(sparse_map, spawns, mode)
    if bool(sv["ok"]) and int(sv["bricks"]) > 0:
        sparse["spawns"] = spawns
        sparse["attempts"] = Cfg.CONNECT_TRIES
        sparse["stats"] = sv
        sparse["degraded"] = true
        return sparse

    var safe = build_map(rng, 0.0, spawns, theme_id)
    safe["spawns"] = spawns
    safe["attempts"] = Cfg.CONNECT_TRIES
    safe["stats"] = validate(safe["map"], spawns, mode)
    safe["degraded"] = true
    return safe

static func generate_boss(rng: Rng, previous_theme: String, requested_theme: String = "") -> Dictionary:
    var opts = {"mode": "adventure", "previous_theme": previous_theme}
    if not requested_theme.is_empty():
        opts["theme"] = requested_theme
    var level = generate(rng, opts)
    level["boss_battle"] = true
    return level

static func open_cells(map_data: Array) -> Array:
    var out: Array = []
    for r in Cfg.ROWS:
        for c in Cfg.COLS:
            if int(map_data[r * Cfg.COLS + c]) == T_EMPTY:
                out.append(Vector2i(c, r))
    return out
