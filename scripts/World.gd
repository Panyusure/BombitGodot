class_name World
extends RefCounted

## 对局世界（迁自 engine.js createWorld）。

var mode = "adventure"          # adventure / dig / versus
var input_mode = "solo"         # solo / versus
var theme = "forest"
var map: Array = []              # 0 空地 / 1 硬墙 / 2 软砖
var spawns: Array = []
var rng: Rng
var time = 0.0
var frame = 0
var brief_text = ""

var bombs: Array = []
var flames: Array = []
var poison: Array = []
var items: Array = []
var players: Array = []
var enemies: Array = []

var danger = PackedFloat32Array()
var match: MatchState
var stats = {"explosions": 0, "kills": 0, "max_chain": 0}

var next_entity_id = 1
var landmark: Dictionary = {}
var brick_variants: Array = []
var boss_battle = false
var briefing = false
var time_stop = null            # {owner_id, remaining}
var skill_effects: Array = []
var pending_deaths: Array = []
var seen_enemies: Dictionary = {}
var seed_text = ""
var seed_root = ""
var degraded = false
var burn_items = Cfg.BURN_ITEMS
var ai_field_cache: Dictionary = {}
var ai_break_field_cache: Dictionary = {}
var level_started = false
var result_shown = false
var events: Array = []
var briefing_types: Array = []
var briefing_fresh: Array = []
var map_revision = 0
## 「关卡身份」：只有整张地图被换掉时才 +1（见 GameEngine.apply_level）。
## map_revision 炸一块砖就会 +1，无法用来判断地板/硬墙要不要重画；
## Board 的静态地图 base 层靠这个计数避免每次炸砖都整张重画。
var map_identity = 0
## Render-only revision: rage bombs can destroy interior hard walls.
var hard_revision = 0

func emit_event(kind: String, data: Dictionary = {}) -> void:
    var e = data.duplicate()
    e["kind"] = kind
    events.append(e)

func player_by_id(id: String):
    for p in players:
        if p.id == id:
            return p
    return null

func set_tile(c: int, r: int, value: int) -> bool:
    var previous := Grid.at(map, c, r)
    var changed = Grid.set_tile(map, c, r, value)
    if changed:
        map_revision += 1
        if previous == Cfg.T_HARD or value == Cfg.T_HARD:
            hard_revision += 1
    return changed

func count_bricks() -> int:
    var n = 0
    for v in map:
        if int(v) == Cfg.T_BRICK:
            n += 1
    return n

func alive_enemies() -> int:
    var n = 0
    for e in enemies:
        if e.alive:
            n += 1
    return n

func boss_alive() -> bool:
    for e in enemies:
        if e.alive and e.type == "boss":
            return true
    return false
