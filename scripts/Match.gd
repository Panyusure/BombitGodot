class_name Match
extends RefCounted

## 对局规则：计时、得分、胜负、关卡推进（迁自 src/game/match.js）。

static func create(mode: String) -> MatchState:
    var m = MatchState.new()
    m.mode = mode
    m.time_limit = Cfg.VERSUS_TIME if mode == "versus" else Cfg.DIG_TIME
    m.remaining = m.time_limit
    return m

static func count_bricks(world) -> int:
    return world.count_bricks()

static func count_enemies(world) -> int:
    return world.alive_enemies()

static func update(world, dt: float) -> bool:
    var m: MatchState = world.match
    if m == null:
        return false
    var ended = resolve_deaths(world, m)
    if m.over:
        return ended
    m.elapsed += dt
    var tick_ended = false
    if m.mode == "dig":
        tick_ended = step_dig(world, dt, m)
    elif m.mode == "versus":
        tick_ended = step_versus(world, dt, m)
    else:
        tick_ended = step_adventure(world, dt, m)
    return ended or tick_ended

static func on_death(world, p) -> void:
    world.pending_deaths.append(p)

static func resolve_deaths(world, m: MatchState) -> bool:
    if world.pending_deaths.is_empty():
        return false
    var dead: Array = world.pending_deaths.duplicate()
    world.pending_deaths.clear()
    if m.over:
        return false

    if m.mode != "versus":
        var me = world.players[0] if not world.players.is_empty() else null
        if me != null and me.lives <= 0:
            var why = ""
            if m.mode == "adventure":
                why = "闯到了第 %d 关" % m.level
            else:
                why = "撑过了 %.1f 秒" % m.elapsed
            return finish(world, "p2", "挑战结束", why)
        return false

    for p in dead:
        var other = "p2" if p.id == "p1" else "p1"
        m.scores[other] = int(m.scores[other]) + 1
        Skills.charge_soul(world, world.player_by_id(other), int(Cfg.skill_cfg("weilai")["bombs_to_evolve"]))

    var p1_done = int(m.scores["p1"]) >= m.target_score
    var p2_done = int(m.scores["p2"]) >= m.target_score
    if p1_done and p2_done:
        return settle(world, "draw")
    if p2_done:
        return settle(world, "p2")
    if p1_done:
        return settle(world, "p1")

    if m.round_ends_at == 0.0:
        m.round_ends_at = world.time + Cfg.ROUND_RESTART_DELAY
    return false

static func begin_round(world) -> void:
    var m: MatchState = world.match
    if m == null:
        return
    m.start_bricks = count_bricks(world)
    m.round_ends_at = 0.0

# ---------------- 计时拆砖 ----------------

static func step_dig(world, dt: float, m: MatchState) -> bool:
    m.remaining -= dt
    if count_bricks(world) == 0:
        var used: float = m.time_limit - maxf(0.0, m.remaining)
        return finish(world, "p1", "挑战完成",
            "用时 %.1f 秒　剩余 %.1f 秒" % [used, maxf(0.0, m.remaining)])
    if m.remaining <= 0.0:
        m.remaining = 0.0
        return finish(world, "p2", "时间结束", "剩余障碍 %d" % count_bricks(world))
    var p = world.players[0] if not world.players.is_empty() else null
    if p != null and p.lives <= 0:
        return finish(world, "p2", "挑战结束", "用时 %.1f 秒" % m.elapsed)
    return false

# ---------------- 同屏对战 ----------------

static func step_versus(world, dt: float, m: MatchState) -> bool:
    if m.round_ends_at > 0.0:
        if world.time >= m.round_ends_at:
            m.round_ends_at = 0.0
            if not m.over:
                GameEngine.new_round(world)
        return false

    m.remaining -= dt
    if m.remaining <= 0.0 and not m.sudden:
        m.sudden = true
        m.remaining = Cfg.VERSUS_SUDDEN_TIME
        for i in world.map.size():
            if int(world.map[i]) == Cfg.T_BRICK:
                world.map[i] = Cfg.T_EMPTY
        world.map_revision += 1
        world.emit_event("sudden_death", {})
    if m.sudden and m.remaining <= 0.0:
        m.scores["p1"] = int(m.scores["p1"]) + 1
        m.scores["p2"] = int(m.scores["p2"]) + 1
        return settle(world, "draw")
    return false

# ---------------- 闯关打怪 ----------------

static func step_adventure(world, dt: float, m: MatchState) -> bool:
    if count_enemies(world) > 0:
        return false
    if m.level >= Cfg.ADVENTURE_LEVELS:
        m.level_clear_at = 0.0
        return finish(world, "p1", "冒险通关", "已完成全部 %d 关" % Cfg.ADVENTURE_LEVELS)
    if m.level_clear_at == 0.0:
        m.level_clear_at = world.time + Cfg.LEVEL_CLEAR_DELAY
        world.emit_event("level_clear", {"level": m.level})
        return false
    if world.time >= m.level_clear_at:
        m.level_clear_at = 0.0
        m.level += 1
        GameEngine.next_level(world)
    return false

static func can_respawn(world, p) -> bool:
    var m: MatchState = world.match
    if m == null or m.over:
        return false
    if m.mode == "versus":
        return m.round_ends_at == 0.0
    return p.lives > 0

static func settle(world, winner: String) -> bool:
    var m: MatchState = world.match
    if m.over:
        return false
    m.over = true
    m.winner = winner
    m.round_ends_at = 0.0
    if m.mode == "versus":
        if winner == "draw":
            m.title = "平局"
            m.subtitle = "本场对战结束"
        else:
            m.title = ("1P" if winner == "p1" else "2P") + " 获胜"
            m.subtitle = "比分 %d : %d" % [int(m.scores["p1"]), int(m.scores["p2"])]
    world.emit_event("match_over", {"winner": winner, "title": m.title})
    return true

static func finish(world, winner: String, title: String, subtitle: String = "") -> bool:
    var m: MatchState = world.match
    if m.over:
        return false
    m.over = true
    m.winner = winner
    m.title = title
    m.subtitle = subtitle
    world.emit_event("match_over", {"winner": winner, "title": title})
    return true

static func summary(world) -> Dictionary:
    var m: MatchState = world.match
    var players: Array = []
    for p in world.players:
        players.append({
            "id": p.id, "name": p.name, "char_name": p.char_name, "color": p.color,
            "power": p.power, "max_bombs": p.max_bombs,
            "speed": 1.0 + p.speed_bonus, "lives": Rules.life_count(p), "picked": p.picked,
        })
    return {
        "mode": m.mode, "title": m.title, "subtitle": m.subtitle, "winner": m.winner,
        "elapsed": m.elapsed, "scores": m.scores.duplicate(), "round": m.round,
        "level": m.level, "total_levels": Cfg.ADVENTURE_LEVELS,
        "enemies_left": count_enemies(world), "bricks_left": count_bricks(world),
        "bricks_cleared": maxi(0, m.start_bricks - count_bricks(world)),
        "start_bricks": m.start_bricks, "explosions": world.stats["explosions"],
        "kills": world.stats["kills"], "max_chain": world.stats["max_chain"],
        "players": players,
    }
