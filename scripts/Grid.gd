class_name Grid
extends RefCounted

## 网格工具：坐标换算与碰撞判定（迁自 src/game/grid.js）。

static func col(x: float) -> int:
    return floori(x / float(Cfg.TILE))

static func row(y: float) -> int:
    return floori(y / float(Cfg.TILE))

static func center_x(c: int) -> float:
    return c * Cfg.TILE + Cfg.TILE * 0.5

static func center_y(r: int) -> float:
    return r * Cfg.TILE + Cfg.TILE * 0.5

static func lane_x(x: float) -> float:
    return center_x(col(x))

static func lane_y(y: float) -> float:
    return center_y(row(y))

static func in_bounds(c: int, r: int) -> bool:
    return c >= 0 and r >= 0 and c < Cfg.COLS and r < Cfg.ROWS

static func at(map_data: Array, c: int, r: int) -> int:
    if not in_bounds(c, r):
        return Cfg.T_HARD
    return int(map_data[r * Cfg.COLS + c])

static func set_tile(map_data: Array, c: int, r: int, value: int) -> bool:
    if not in_bounds(c, r):
        return false
    var i = r * Cfg.COLS + c
    if int(map_data[i]) != value:
        map_data[i] = value
        return true
    return false

static func is_wall(map_data: Array, c: int, r: int) -> bool:
    var v = at(map_data, c, r)
    return v == Cfg.T_HARD or v == Cfg.T_BRICK

static func can_break_hard(world, c: int, r: int) -> bool:
    if c <= 0 or r <= 0 or c >= Cfg.COLS - 1 or r >= Cfg.ROWS - 1:
        return false
    if at(world.map, c, r) != Cfg.T_HARD:
        return false
    # 中央设施（3×3）不可破坏
    return not (abs(c - 7) <= 1 and abs(r - 6) <= 1)

static func bomb_position(b: Bomb) -> Vector2:
    if b.has_pos:
        return Vector2(b.x, b.y)
    return Vector2(center_x(b.cx), center_y(b.cy))

static func bomb_allows(b: Bomb, actor_id: String) -> bool:
    if actor_id.is_empty():
        return false
    if not b.free_for.is_empty() and b.free_for == actor_id:
        return true
    return b.pass_for.has(actor_id)

static func bomb_overlaps_player(b: Bomb, actor) -> bool:
    var pos = bomb_position(b)
    return Vector2(actor.x, actor.y).distance_to(pos) < Cfg.PLAYER_BOMB_RADIUS + Cfg.BOMB_RADIUS

## 只检查地形（不含炸弹）能否站住。
static func can_stand_map(map_data: Array, x: float, y: float, box: float) -> bool:
    var half = box * 0.5
    var c0 = floori((x - half) / Cfg.TILE)
    var c1 = floori((x + half - 1e-6) / Cfg.TILE)
    var r0 = floori((y - half) / Cfg.TILE)
    var r1 = floori((y + half - 1e-6) / Cfg.TILE)
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if is_wall(map_data, c, r):
                return false
    return true

## 以 (x,y) 为中心、边长 box 的方块能否站得住。
static func can_stand(world, x: float, y: float, box: float, actor_id: String) -> bool:
    var half = box * 0.5
    var c0 = floori((x - half) / Cfg.TILE)
    var c1 = floori((x + half - 1e-6) / Cfg.TILE)
    var r0 = floori((y - half) / Cfg.TILE)
    var r1 = floori((y + half - 1e-6) / Cfg.TILE)
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if is_wall(world.map, c, r):
                return false
    var radius = Cfg.PLAYER_BOMB_RADIUS if is_equal_approx(box, Cfg.BOX) else box * 0.5
    for b in world.bombs:
        if bomb_allows(b, actor_id):
            continue
        var pos = bomb_position(b)
        if Vector2(x, y).distance_to(pos) < radius + Cfg.BOMB_RADIUS - 1e-6:
            return false
    return true

## 怪物可以离开已经重叠的炸弹，但不能从外面挤进弹身。
static func can_move_enemy(world, enemy, x: float, y: float) -> bool:
    var box = Cfg.ENEMY_BOX
    var half = box * 0.5
    var c0 = floori((x - half) / Cfg.TILE)
    var c1 = floori((x + half - 1e-6) / Cfg.TILE)
    var r0 = floori((y - half) / Cfg.TILE)
    var r1 = floori((y + half - 1e-6) / Cfg.TILE)
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if is_wall(world.map, c, r):
                return false
    var radius = box * 0.5 + Cfg.BOMB_RADIUS
    for b in world.bombs:
        if bomb_allows(b, enemy.id):
            continue
        var pos = bomb_position(b)
        var before = Vector2(enemy.x, enemy.y).distance_to(pos)
        var after = Vector2(x, y).distance_to(pos)
        if before < radius and after > before + 1e-9:
            continue
        if after < radius - 1e-6:
            return false
    return true

static func bomb_blocks(bombs: Array, c: int, r: int, actor_id: String) -> bool:
    for b in bombs:
        if bomb_allows(b, actor_id):
            continue
        var pos = bomb_position(b)
        if Vector2(center_x(c), center_y(r)).distance_to(pos) >= Cfg.BOMB_RADIUS + Cfg.ENEMY_BOX * 0.5:
            continue
        return true
    return false

static func overlaps_tile(x: float, y: float, box: float, c: int, r: int) -> bool:
    var half = box * 0.5
    return (x + half > c * Cfg.TILE) and (x - half < (c + 1) * Cfg.TILE) \
        and (y + half > r * Cfg.TILE) and (y - half < (r + 1) * Cfg.TILE)
