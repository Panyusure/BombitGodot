class_name Actor
extends RefCounted

## 玩家与敌人共用的角色状态（迁自 engine.js makePlayer / entities.js create）。

var id = ""
var is_enemy = false
var type = ""                  # 敌人种类；玩家为空
var asset_id = "xiaonuo"       # 玩家可选精灵
var name = ""
var char_name = ""
var color = Color.WHITE
var spawn_index = 0

var x = 0.0
var y = 0.0
var px = 0.0
var py = 0.0
var facing = 1
var facing_dir = "down"
var moving = false
var axis_pref = "x"

var power = 1
var max_bombs = 1
var speed_bonus = 0.0
var shield = 0
var star_time = 0.0
var glove = false
var invuln = 0.0
var squash = 0.0

var alive = true
var dead_at = 0.0
var lives = Cfg.START_LIVES

var skill_cd = 0.0
var flame_guard = 0.0
var insight_time = 0.0
var slow_time = 0.0
var cast_flash = 0.0
var aim_x = 1
var aim_y = 0
var picked: Dictionary = {}

var soul_evolved = false
var soul_bombs = 0
var soul_awaken_time = 0.0
var soul_slow_time = 0.0
var soul_slow_rate = 0.0
var soul_slow_owner_id = ""
var soul_slow_assist_until = 0.0

var carousel_travel = 0.0
var carousel_rewarded = false

# ---- 敌人专用 ----
var hp = 1
var max_hp = 1
var phase = 0
var phase_flash = 0.0
var bomb_gap = 6.0
var windup = 0.0
var ability_cd = 2.5
var level = 1
var speed = 1.0
var hit_flash = 0.0
var stun = 0.0
var dir: Dictionary = {}
var tc = 0
var tr = 0
var from_c = -1
var from_r = -1
var bomb_cd = 3.0
var last_x = 0
var last_y = 0
var has_last = false
var returning = false
var scenery_motion = false
var escape_path: Array = []
var queued_bomb = false

func skill_info() -> Dictionary:
    return Cfg.skill_cfg(asset_id)

func is_boss() -> bool:
    return is_enemy and type == "boss"

func center() -> Vector2:
    return Vector2(x, y)
