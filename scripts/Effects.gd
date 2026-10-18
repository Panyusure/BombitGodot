class_name Effects
extends Node2D

## 粒子 / 震屏 / 飘字（逐点迁自原作 src/render/effects.js）。
##
## 三层结构与原作一致：
##   particles —— 爆炸、死亡、拾取…… 生成的小颗粒，带重力、寿命、自转；
##   texts     —— 飘字，匀速上浮 + 每帧 0.93 的阻尼，前 55% 寿命不透明、后段淡出；
##   shake     —— 震屏强度（像素），按 shakeDecay 线性衰减，shakeIt 取较大值不叠加。
##
## 事件消费：Main._physics_process() 在 GameEngine.step() 之后每个物理帧调用一次
## feed()。world.events 是追加式数组（GameEngine.step 开头 clear），这里只读取、
## **不清空** —— Main._drain_events() 与 ReplayUI 都还在用同一个数组。
##
## 坐标系：节点位置由 Main 设为 (0, Cfg.HUD_H)，与 Board / Actors 相同，
## 所以内部一律直接用场地坐标（0..FIELD_W, 0..FIELD_H），和原作一致。

# 原作 effects.js:16-17
const SHAKE_DECAY := 42.0
const MAX_SHAKE := 7.0

# 原作 main.js:107 的拾取文案表（effects.js 只负责画，文案在调用点）
const PICKUP_LABELS := {
    "fire": "火力+1",
    "bomb": "炸弹数量+1",
    "speed": "速度+10%",
    "fruit": "拾取生命果实",
    "star": "无敌6秒",
    "shield": "获得护盾",
    "glove": "获得推弹手套",
}

static var _color_cache: Dictionary = {}

var particles: Array = []       # {x,y,vx,vy,g,t,total,r,color,shape,rot,spin}
var texts: Array = []           # {x,y,str,color,t,total,vy,size}
var shake := 0.0                # 当前震屏强度
var ox := 0.0                   # 本帧震屏偏移（渲染时加到场地上）
var oy := 0.0

var _rng: Rng = null
var _world_ref: World = null

func _init() -> void:
    # 原作默认 Math.random；godot 侧用 Rng（xorshift32），set_rng() 可换确定性随机给测试用。
    _rng = Rng.new(int(Time.get_ticks_usec()) & 0x7fffffff)

## 让测试可以用确定性随机（对应原作 setRng）。
func set_rng(rng: Rng) -> void:
    if rng != null:
        _rng = rng

static func _col(hex: String) -> Color:
    if _color_cache.has(hex):
        return _color_cache[hex]
    var c := Color(hex)
    _color_cache[hex] = c
    return c

# ============================================================
# 生命周期
# ============================================================

## 对应原作 reset()（effects.js:21-27 / main.js:124 的 field_reset）。
func reset() -> void:
    particles.clear()
    texts.clear()
    shake = 0.0
    ox = 0.0
    oy = 0.0
    queue_redraw()

## 每个物理帧消费一次 world.events，然后推进一帧（原作 main.js:196/203 的 FX.update）。
func feed(world: World, dt: float) -> void:
    if world != _world_ref:
        # 新世界 = 新一局（对应原作 startGame 里的 FX.reset()）
        _world_ref = world
        reset()
    for e in world.events:
        _consume(world, e)
    update(dt)

## 推进一帧：原作 update()（effects.js:154-183）。
func update(dt: float) -> void:
    for i in range(particles.size() - 1, -1, -1):
        var p: Dictionary = particles[i]
        p["t"] = float(p["t"]) - dt
        if float(p["t"]) <= 0.0:
            particles.remove_at(i)
            continue
        p["vy"] = float(p["vy"]) + float(p["g"]) * dt
        p["x"] = float(p["x"]) + float(p["vx"]) * dt
        p["y"] = float(p["y"]) + float(p["vy"]) * dt
        p["rot"] = float(p["rot"]) + float(p["spin"]) * dt

    for j in range(texts.size() - 1, -1, -1):
        var t: Dictionary = texts[j]
        t["t"] = float(t["t"]) - dt
        if float(t["t"]) <= 0.0:
            texts.remove_at(j)
            continue
        t["y"] = float(t["y"]) + float(t["vy"]) * dt
        t["vy"] = float(t["vy"]) * 0.93      # 注意：原作是每帧一次的阻尼，不是每秒
    if shake > 0.0:
        shake = maxf(0.0, shake - dt * SHAKE_DECAY)
        var amp := shake
        ox = (_rng.next_float() - 0.5) * amp * 2.0
        oy = (_rng.next_float() - 0.5) * amp * 2.0
    else:
        ox = 0.0
        oy = 0.0
    queue_redraw()

## 本帧震屏偏移；Main 把它加在 Board / Actors / Effects 的位置上
## （等价原作 main.js:262 的 ctx.translate(FX.ox, CFG.HUD_H + FX.oy)）。
func shake_offset() -> Vector2:
    return Vector2(ox, oy)

## 调试 / 测试用（原作 stats()）。
func stats() -> Dictionary:
    return {"particles": particles.size(), "texts": texts.size(), "shake": snappedf(shake, 0.01)}

# ============================================================
# 粒子 / 飘字 生成（原作 effects.js:35-70）
# ============================================================

## 原作 burst()：环形喷射，n 个粒子均分圆周 + 随机抖动。
func burst(x: float, y: float, opt: Dictionary = {}) -> void:
    var n := int(opt.get("count", 10))
    var colors: Array = opt.get("colors", ["#ffd166"])
    var speed := float(opt.get("speed", 90.0))
    var life0 := float(opt.get("life", 0.5))
    var gravity := float(opt.get("gravity", 260.0))
    var size := float(opt.get("size", 4.0))
    var lift := float(opt.get("lift", 0.0))
    var shape := String(opt.get("shape", "circle"))
    for i in n:
        var a := float(i) / float(n) * TAU + _rng.next_float() * 0.6
        var sp := speed * (0.45 + _rng.next_float() * 0.9)
        var life := life0 * (0.65 + _rng.next_float() * 0.7)
        var rad := size * (0.55 + _rng.next_float() * 0.9)
        # 随机数消耗顺序必须与原作对象字面量的求值顺序一致：
        # a(1) sp(1) life(1) r(1) color(1) rot(1) spin(1)
        var color: Color = _col(String(colors[int(_rng.next_float() * float(colors.size()))]))
        var rot := _rng.next_float() * 6.283
        var spin := (_rng.next_float() - 0.5) * 14.0
        particles.append({
            "x": x, "y": y,
            "vx": cos(a) * sp,
            "vy": sin(a) * sp - lift,
            "g": gravity,
            "t": life, "total": life,
            "r": rad,
            "color": color,
            "shape": shape,
            "rot": rot,
            "spin": spin,
        })

## 原作 text()：飘字。
func text(x: float, y: float, s: String, color: Color = Color("ffffff"), opt: Dictionary = {}) -> void:
    var life := float(opt.get("life", 0.95))
    texts.append({
        "x": x, "y": y, "str": String(s),
        "color": color,
        "t": life, "total": life,
        "vy": float(opt.get("vy", -38.0)),
        "size": float(opt.get("size", 16.0)),
    })

## 原作 shakeIt()：取较大值，不叠加。
func shake_it(amount: float) -> void:
    var v := minf(MAX_SHAKE, amount)
    if v > shake:
        shake = v

# ============================================================
# 预设：游戏事件 -> 效果组合（原作 effects.js:81-149）
# ============================================================

## 原作 explosion(cx, cy, cells)：cx/cy 是格坐标，cells 是本次火焰的全部格子。
func explosion(cx: float, cy: float, cells: Array) -> void:
    var x := cx * Cfg.TILE + Cfg.TILE / 2.0
    var y := cy * Cfg.TILE + Cfg.TILE / 2.0
    burst(x, y, {
        "count": 14, "speed": 165.0, "size": 4.5, "life": 0.42, "gravity": 130.0, "lift": 30.0,
        "colors": ["#ffffff", "#ffd166", "#ff6b35", "#ff9e5c"],
    })
    # 火焰末端也甩几个火星，让爆炸看起来很"宽"
    if cells.size() > 1:
        var step := maxi(1, int(floor(float(cells.size()) / 3.0)))
        var i := step
        while i < cells.size():
            var cell: Vector2i = cells[i]
            burst(float(cell.x) * Cfg.TILE + Cfg.TILE / 2.0,
                float(cell.y) * Cfg.TILE + Cfg.TILE / 2.0,
                {"count": 3, "speed": 80.0, "size": 3.0, "life": 0.3, "gravity": 90.0,
                 "colors": ["#ffd166", "#ff6b35"]})
            i += step
    shake_it(9.0)      # 会被 maxShake 截到 7

## 原作 death(x, y)：星形粒子 + 震屏 7。
func death(x: float, y: float) -> void:
    burst(x, y, {
        "count": 16, "speed": 120.0, "size": 4.0, "life": 0.85, "gravity": 220.0, "lift": 120.0,
        "colors": ["#ffd166", "#ffffff", "#8fd8ff"], "shape": "star",
    })
    shake_it(7.0)

## 原作 enemyDeath(x, y, color)：不震屏。
func enemy_death(x: float, y: float, color: Color = Color("8fe3a1")) -> void:
    burst(x, y, {
        "count": 12, "speed": 130.0, "size": 4.0, "life": 0.6, "gravity": 240.0, "lift": 70.0,
        "colors": [color.to_html(false), "#ffffff"],
    })

## 原作 pickup(x, y, label)：向上飘的拾取粒子（重力为负）+ 可选飘字。
func pickup(x: float, y: float, label: String = "") -> void:
    burst(x, y, {
        "count": 8, "speed": 75.0, "size": 3.0, "life": 0.45, "gravity": -30.0,
        "colors": ["#ffffff", "#8fe3a1", "#ffd166"],
    })
    if not label.is_empty():
        text(x, y - 12.0, label, Color("ffffff"), {"size": 15.0})

## 原作 shieldBreak(x, y)：矩形碎片。
func shield_break(x: float, y: float) -> void:
    burst(x, y, {
        "count": 12, "speed": 140.0, "size": 3.5, "life": 0.5, "gravity": 160.0,
        "colors": ["#8fd8ff", "#ffffff", "#63b8ff"], "shape": "rect",
    })

## 原作 levelClear()：全屏彩带雨 + 「过关！」。
func level_clear() -> void:
    var colors := ["#ffd166", "#5ec8f0", "#ff9eb5", "#8fe3a1", "#c78bff"]
    for i in 70:
        # 随机数消耗顺序照抄原作字面量：x, y, vx, vy, r, color, rot, spin
        var x := _rng.next_float() * float(Cfg.FIELD_W)
        var y := -20.0 - _rng.next_float() * 120.0
        var vx := (_rng.next_float() - 0.5) * 40.0
        var vy := 90.0 + _rng.next_float() * 120.0
        var rad := 4.0 + _rng.next_float() * 4.0
        var color: Color = _col(colors[int(_rng.next_float() * 5.0)])
        var rot := _rng.next_float() * 6.283
        var spin := (_rng.next_float() - 0.5) * 10.0
        particles.append({
            "x": x, "y": y,
            "vx": vx, "vy": vy,
            "g": 30.0,
            "t": 2.2, "total": 2.2,
            "r": rad,
            "color": color,
            "shape": "rect",
            "rot": rot,
            "spin": spin,
        })
    text(float(Cfg.FIELD_W) / 2.0, float(Cfg.FIELD_H) / 2.0 - 40.0, "过关！", Color("ffd166"),
        {"size": 44.0, "life": 1.4, "vy": -14.0})

# ============================================================
# 事件 -> 预设（每个事件只在这里查一次参数，不改游戏逻辑）
# ============================================================

func _consume(world: World, e: Dictionary) -> void:
    match String(e.get("kind", "")):
        "explode":
            # Rules.gd:189 payload 只带爆心像素坐标与格数；火焰本体（含格子表）
            # 由 Rules.detonate 先写进 world.flames，这里按爆心取回同一份 cells。
            var cx := Grid.col(float(e.get("x", 0.0)))
            var cy := Grid.row(float(e.get("y", 0.0)))
            explosion(float(cx), float(cy), _flame_cells(world, cx, cy))
        "death":
            # Rules.gd:334 {player, lives}；原作 onDeath 用的是角色的当前坐标
            var p = _actor(world, String(e.get("player", "")))
            if p != null:
                death(p.x, p.y)
        "enemy_death":
            # Rules.gd:350 带 x/y；颜色照原作取 ENEMY_TYPES[type].color
            enemy_death(float(e.get("x", 0.0)), float(e.get("y", 0.0)), _enemy_color(e))
        "pickup":
            _on_pickup(world, e)
        "shield_break":
            # 原作 main.js:111 是在角色坐标上方 20px 起爆
            var a = _actor(world, String(e.get("actor", "")))
            if a != null:
                shield_break(a.x, a.y - 20.0)
        "level_clear":
            level_clear()
        "skill":
            _on_skill(world, e)
        # 以下三条不在任务清单里，但原作 main.js 的对应 hook 就是 FX 调用，
        # 一并按字面常量补齐（Godot 侧事件 payload 齐全，无需臆造）。
        "boss_phase":
            _on_boss_phase(e)
        "scenery":
            _on_scenery(e)
        "item_burn":
            var bx := float(e.get("c", 0)) * Cfg.TILE + Cfg.TILE / 2.0
            var by := float(e.get("r", 0)) * Cfg.TILE + Cfg.TILE / 2.0
            burst(bx, by, {"count": 8, "speed": 80.0, "size": 3.0, "life": 0.4, "gravity": 120.0,
                "colors": ["#ff9e5c", "#ffd166", "#ffffff"]})
        "field_reset":
            reset()
        _:
            pass

## 原作 main.js:98-108 的 onPickup：玩家走 FX.pickup + 文案，敌人只飘一行字。
func _on_pickup(world: World, e: Dictionary) -> void:
    var type_id := String(e.get("type", ""))
    var info: Dictionary = Cfg.ITEM_INFO.get(type_id, {})
    var actor = _actor(world, String(e.get("actor", "")))
    if actor != null and actor.is_enemy:
        text(actor.x, actor.y - 45.0,
            "%s · %s" % [actor.name, String(info.get("label", "道具"))],
            info.get("color", Color("ffffff")), {"size": 12.0})
        return
    var label := String(PICKUP_LABELS.get(type_id, String(info.get("label", ""))))
    pickup(float(e.get("x", 0.0)), float(e.get("y", 0.0)), label)

## 原作 main.js:91-96 的 onSkill：一圈技能色粒子 + 技能名飘字。
func _on_skill(world: World, e: Dictionary) -> void:
    var p = _actor(world, String(e.get("player", "")))
    if p == null:
        return
    var col: Color = Cfg.skill_cfg(String(p.asset_id))["color"]
    burst(p.x, p.y - 12.0, {"count": 16, "speed": 100.0, "life": 0.5,
        "colors": [col.to_html(false), "#fff9dd"], "gravity": -20.0})
    text(p.x, p.y - 54.0, String(e.get("text", "")), col, {"size": 14.0})

## 原作 main.js:79-85 的 onBossPhase。
func _on_boss_phase(e: Dictionary) -> void:
    var col: Color = e.get("color", Color("ffffff"))
    var x := float(e.get("x", 0.0))
    var y := float(e.get("y", 0.0))
    burst(x, y - 25.0, {"count": 24, "speed": 100.0, "life": 0.8,
        "colors": [col.to_html(false), "#fff3d1"], "gravity": -20.0})
    var prefix := "二 · " if int(e.get("phase", 0)) == 2 else "三 · "
    text(x, y - 104.0, prefix + String(e.get("name", "")), col, {"size": 21.0})

## 原作 main.js:86-90 的 onScenery。
func _on_scenery(e: Dictionary) -> void:
    var x := float(e.get("x", 0.0))
    var y := float(e.get("y", 0.0))
    burst(x, y - 8.0, {"count": 12, "speed": 65.0, "life": 0.7,
        "colors": ["#ffe3a5", "#c8e6a2", "#fff8e7"], "gravity": 25.0})
    # 子类型走 payload 的 "sub" 键：World.emit_event() 会把 data["kind"] 覆盖成事件名 "scenery"，
    # 原来的 "kind": "fruit" / "carousel" 会被冲掉。
    var label := "获得护盾" if String(e.get("sub", "")) == "carousel" else "生命果实"
    text(x, y - 34.0, label, Color("ffe3a5"), {"size": 14.0})

## 玩家 / 敌人共用的 id 查找（两个 id 空间不重叠）。
func _actor(world: World, id: String):
    if id.is_empty():
        return null
    for p in world.players:
        if p.id == id:
            return p
    for en in world.enemies:
        if en.id == id:
            return en
    return null

func _enemy_color(e: Dictionary) -> Color:
    var type_id := String(e.get("type", ""))
    if Cfg.ENEMY_TYPES.has(type_id):
        return Cfg.ENEMY_TYPES[type_id]["color"]
    return Color("8fe3a1")

## Rules.detonate 刚写进 world.flames 的那条火焰，就是本次爆炸的格子表。
func _flame_cells(world: World, cx: int, cy: int) -> Array:
    for i in range(world.flames.size() - 1, -1, -1):
        var f: Dictionary = world.flames[i]
        if int(f.get("cx", -1)) == cx and int(f.get("cy", -1)) == cy:
            return f.get("cells", [])
    return []

# ============================================================
# 渲染（原作 effects.js:188-234）：粒子在上，飘字在最上
# ============================================================

func _draw() -> void:
    _draw_particles()
    _draw_texts()

func _draw_particles() -> void:
    for p in particles:
        var a := float(p["t"]) / float(p["total"])
        if a <= 0.0:
            continue
        var col: Color = p["color"]
        col.a *= minf(1.0, a * 1.4)          # ctx.globalAlpha = min(1, a * 1.4)
        var rad := float(p["r"])
        var shape := String(p["shape"])
        if shape == "rect":
            # translate(p) + rotate(rot) + fillRect(-r, -r*0.55, r*2, r*1.1)
            draw_set_transform(Vector2(float(p["x"]), float(p["y"])), float(p["rot"]), Vector2.ONE)
            draw_rect(Rect2(-rad, -rad * 0.55, rad * 2.0, rad * 1.1), col, true, -1.0, true)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        elif shape == "star":
            draw_set_transform(Vector2(float(p["x"]), float(p["y"])), float(p["rot"]), Vector2.ONE)
            _fill_circle(Vector2.ZERO, rad * (0.5 + a * 0.5), col)
            var outer := col
            outer.a *= 0.5                   # ctx.globalAlpha *= 0.5（只作用于外圈）
            _fill_circle(Vector2.ZERO, rad * (1.1 + a * 0.6), outer)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        else:
            _fill_circle(Vector2(float(p["x"]), float(p["y"])), rad * (0.35 + a * 0.75), col)

func _draw_texts() -> void:
    for t in texts:
        var a := float(t["t"]) / float(t["total"])
        # 后段才开始淡出，前段保持清晰
        var alpha := 1.0 if a > 0.45 else a / 0.45
        UIDraw.text(self, String(t["str"]), float(t["x"]), float(t["y"]), {
            "size": int(t["size"]), "weight": 700, "family": "cn",
            "align": "center", "fill": t["color"], "alpha": alpha,
            "stroke": Color(0.0, 0.0, 0.0, 0.5), "strokeWidth": 4,
        })

## D.circle(ctx, x, y, r) + ctx.fill() 的等价物。
func _fill_circle(c: Vector2, r: float, col: Color) -> void:
    if r <= 0.0 or col.a <= 0.0:
        return
    var pts := CanvasArt.circle_pts(c.x, c.y, r)
    if pts.size() >= 3:
        draw_colored_polygon(pts, col)
