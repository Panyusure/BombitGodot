class_name Cfg
extends RefCounted

## BombIt 数值与内容配置（1:1 迁自 src/core/config.js、assets/characters.js、entities.js）

# ---------- 网格与画布 ----------
const TILE = 48
const COLS = 15
const ROWS = 13
const HUD_H = 72
const FIELD_W = TILE * COLS          # 720
const FIELD_H = TILE * ROWS          # 624
const VIEW_W = FIELD_W               # 720
const VIEW_H = FIELD_H + HUD_H       # 696
const VERSION = "v2.3-godot"

# ---------- 玩家 ----------
const BOX = 36.0
const ASSIST = 12.0
const SPEED_BASE = 4.6
const SPEED_STEP = 0.10
const SPEED_MAX_BONUS = 0.50
const START_POWER = 1
const START_BOMBS = 1
const MAX_POWER = 8
const MAX_BOMBS = 8
const START_LIVES = 3
const MAX_LIVES = 5

# ---------- 炸弹 ----------
const BOMB_RADIUS = 17.0
const PLAYER_BOMB_RADIUS = 14.0
const FUSE = 2.40
const FUSE_BLINK = 0.60
const FLAME_TIME = 0.45
const PUSH_SPEED = 9.0
const BURN_ITEMS = true

# ---------- 地图生成 ----------
const BRICK_RATE = {"dig": 0.62, "versus": 0.56, "adventure": 0.60}
const WALL_RATE = 0.24
const MIN_EXITS = 1
const SAFE_RADIUS = 2
const CONNECT_TRIES = 20

# ---------- 道具 ----------
const ITEM_DROP_RATE = 0.30
const STAR_TIME = 6.0
const INVULN_TIME = 1.5
const SHIELD_INVULN_TIME = 1.5

# ---------- 对局 ----------
const DIG_TIME = 180.0
const VERSUS_TIME = 90.0
const VERSUS_TARGET = 2
const VERSUS_SUDDEN_TIME = 45.0
const ROUND_RESTART_DELAY = 1.6
const RESPAWN_DELAY = 1.4
const RESULT_DELAY = 1.1
const MAX_CHAIN = 8

# ---------- 闯关 ----------
const ENEMY_BOX = 30.0
const ENEMY_HIT_INVULN = 0.8
const DANGER_MARGIN = 0.45
const ENEMY_DROP_RATE = 0.45
const LEVEL_CLEAR_DELAY = 1.6
const BOSS_EVERY = 5
const ADVENTURE_LEVELS = 10
const BOSS_POISON_LIFE = 0.8
const BOSS_POISON_WARN = 1.5
const BOSS_POISON_GAP = 8.0
const BOSS_POISON_RAGE_FACTOR = 0.8
const BOSS_RAGE_HP = 3

# ---------- 瓦片 / 道具 ----------
const T_EMPTY = 0
const T_HARD = 1
const T_BRICK = 2

const ITEM_INFO = {
    "fire":   {"label": "火力", "short": "火", "color": "#ff8a5c"},
    "bomb":   {"label": "炸弹", "short": "弹", "color": "#6f7bd6"},
    "speed":  {"label": "速度", "short": "速", "color": "#4cc9a8"},
    "fruit":  {"label": "生命果实", "short": "♥", "color": "#f4bd83"},
    "star":   {"label": "无敌星星", "short": "★", "color": "#ffd45e"},
    "shield": {"label": "护盾", "short": "盾", "color": "#63b8ff"},
    "glove":  {"label": "推弹手套", "short": "推", "color": "#f3b277"},
}

# ---------- 主题 ----------
static var THEMES = {
    "forest": {
        "name": "晨露森林", "subtitle": "生命古树 · 林间果实",
        "mechanic": "古树定时落果，拾取恢复1点生命；满生命或对战时获得护盾。",
        "floor": Color("d1dfad"), "floor_alt": Color("c4d59c"), "edge": Color("596e54"),
        "wall": Color("6d9b76"), "wall_dark": Color("345c52"), "top": Color("a3c78b"),
        "accent": Color("f3d58e"), "sky": Color("243d42"),
    },
    "factory": {
        "name": "星汽工厂", "subtitle": "中央反应炉 · 闭环传送带",
        "mechanic": "传送带顺行加速、逆行减速，静止时随带移动；炸弹也会被运送。",
        "floor": Color("c4d5da"), "floor_alt": Color("b8cbd1"), "edge": Color("557180"),
        "wall": Color("648799"), "wall_dark": Color("345265"), "top": Color("a1bfcb"),
        "accent": Color("ffce7c"), "sky": Color("26344e"),
    },
    "park": {
        "name": "星糖游乐园", "subtitle": "旋转木马 · 环游护盾",
        "mechanic": "静止搭乘木马一圈可获得护盾，每关一次；环道也会运送炸弹。",
        "floor": Color("f3e8d5"), "floor_alt": Color("e9dccd"), "edge": Color("987e9e"),
        "wall": Color("c08fbe"), "wall_dark": Color("836383"), "top": Color("f1c8db"),
        "accent": Color("a8dfdd"), "sky": Color("463b61"),
    },
}
const THEME_IDS = ["forest", "factory", "park"]

# ---------- 角色 ----------
# crop / height / anchor 与 assets/characters.js 一致；素材已按 3 倍预裁切。
static var CHARS = {
    "xiaonuo": {"name": "小诺", "height": 1.55, "anchor": Vector2(0.5, 0.78),
        "title": "心之力量", "intro": "从难以掌控力量的小诺，成长为守护伙伴的诺亚。"},
    "axiu": {"name": "阿修", "height": 1.58, "anchor": Vector2(0.5, 0.88),
        "title": "是非之心", "intro": "阿修的修尔进化线：驾驭黑暗，守护小诺与是非城。"},
    "arui": {"name": "阿瑞", "height": 1.62, "anchor": Vector2(0.5, 0.97),
        "title": "生命之盾", "intro": "阿瑞斯的生命与机械之力，化作守护伙伴的坚盾。"},
    "xiaoyan": {"name": "小炎", "height": 1.58, "anchor": Vector2(0.5, 0.97),
        "title": "力量之王", "intro": "小炎将承受的伤害转为力量，成长为烈焰中的龙炎。"},
    "xiaotian": {"name": "小天", "height": 1.56, "anchor": Vector2(0.5, 0.88),
        "title": "智慧之眼", "intro": "小天领悟对手的力量，成长为洞察战局的帝释天。"},
    "weilai": {"name": "未来", "height": 1.62, "anchor": Vector2(0.5, 0.97),
        "title": "逆转因果", "intro": "五女仆合体为通灵师，回到七年前拯救即将崩塌的世界。"},
}
const CHAR_IDS = ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian", "weilai"]

static var SKILLS = {
    "weilai": {"name": "迁境奇点", "tag": "放弹被动", "color": Color("a9eafa"), "cd": 0.0, "passive": true,
        "desc": "放弹减速45%·2秒；放弹6次、击杀敌人或击倒对手通灵，通灵后减速75%·3秒、范围5×5。",
        "bombs_to_evolve": 6},
    "xiaonuo": {"name": "时光星域", "tag": "时空控制", "color": Color("8dd8ff"), "cd": 12.0, "passive": false,
        "desc": "冻结怪物和敌方炸弹3秒；对战中使对手减速。"},
    "axiu": {"name": "暗刃瞬袭", "tag": "暗影突进", "color": Color("c7a0ff"), "cd": 15.0, "passive": false,
        "desc": "向前突进最多三格，攻击沿途目标，短暂无敌。"},
    "arui": {"name": "森罗守护", "tag": "生命守护", "color": Color("9ae6b3"), "cd": 14.0, "passive": false,
        "desc": "获得护盾，使两格内可达的怪物停留2秒。"},
    "xiaoyan": {"name": "炎灭火舞", "tag": "吸伤蓄火", "color": Color("ffb278"), "cd": 12.0, "passive": false,
        "desc": "4秒内吸收一次爆炸，反弹给周围5×5内的敌人。"},
    "xiaotian": {"name": "潜能洞察", "tag": "智慧预判", "color": Color("a8dafa"), "cd": 12.0, "passive": false,
        "desc": "显示炸弹范围，移动速度+30%，持续6秒。"},
}

# ---------- 敌人 ----------
static var ENEMY_TYPES = {
    "gugu": {"name": "谷谷歌歌", "speed": 1.0, "power": 1, "bomb_gap": 6.0, "hp": 1,
        "color": Color("80baff"), "dark": Color("395983"),
        "desc": "蓝翼小恶魔 · 慢节奏巡游，投弹后撤",
        "story": "蓝翼小恶魔喜欢收集彩色石头，把圆滚滚的烟花也当成了收藏。",
        "mechanic": "投弹前提示0.7秒，放弹后撤退，也会炸开挡路障碍。",
        "damage": "炸弹产生一格十字火焰；仅吃到无敌星星后有碰撞伤害。"},
    "claude": {"name": "克劳德德", "speed": 1.1, "power": 1, "bomb_gap": 6.6, "hp": 1,
        "color": Color("c49bef"), "dark": Color("72508e"),
        "desc": "紫翼小恶魔 · 保持距离，谨慎布弹",
        "story": "紫翼小恶魔做事总要反复检查，连放烟花之前也要先想好退路。",
        "mechanic": "靠近后保持距离，投弹前提示0.7秒，放弹后撤退。",
        "damage": "炸弹产生一格十字火焰；仅吃到无敌星星后有碰撞伤害。"},
    "oupao": {"name": "偶喷诶艾", "speed": 1.15, "power": 2, "bomb_gap": 7.2, "hp": 1,
        "color": Color("f09caa"), "dark": Color("9d4a5e"),
        "desc": "红翼小恶魔 · 两格火力，较长间隔",
        "story": "来自泡泡工坊的红翼小恶魔，总想让自己的烟花再热闹一点。",
        "mechanic": "投弹前提示0.7秒，火力较强、间隔较长，放弹后撤退。",
        "damage": "炸弹产生两格十字火焰；仅吃到无敌星星后有碰撞伤害。"},
    "boss": {"name": "鲁鲁旦", "speed": 1.3, "power": 2, "bomb_gap": 4.0, "hp": 8,
        "color": Color("bd99f0"), "dark": Color("70519b"),
        "desc": "8点生命 · 试探 / 认真 / 暴走",
        "story": "总爱捣乱的鲁鲁旦坐着紫色悬浮舱来到了战场，这次又准备了新的坏点子。",
        "mechanic": "8血试探：追击投弹；6血认真：移速+25%，解锁毒刺；3血暴走：毒刺加快，炸弹可破坏场内硬墙。",
        "damage": "毒刺预警1.5秒、持续0.8秒，仅伤落点一格；炸弹为十字火焰。仅吃到无敌星星后有碰撞伤害。"},
}

static var BOSS_PHASES = [
    {},
    {"id": 1, "name": "试探", "color": Color("c99af2"), "speed": 1.0, "poison": false, "break_hard": false},
    {"id": 2, "name": "认真", "color": Color("eca45e"), "speed": 1.25, "poison": true, "break_hard": false},
    {"id": 3, "name": "暴走", "color": Color("f27869"), "speed": 1.25, "poison": true, "break_hard": true},
]

# ---------- 界面配色（沿用原作的奶油 / 墨黑 / 朱红） ----------
const UI_INK = Color("141019")
const UI_CREAM = Color("f5ebd8")
const UI_RED = Color("ff5533")
const UI_CYAN = Color("5ce1f2")
const UI_YELLOW = Color("ffd23f")
const UI_PINK = Color("ff5e9e")
const UI_GREEN = Color("62df88")
const P1_COLOR = Color("5ec8f0")
const P2_COLOR = Color("ff9eb5")

static func theme(id: String) -> Dictionary:
    return THEMES.get(id, THEMES["forest"])

static func char_cfg(id: String) -> Dictionary:
    return CHARS.get(id, CHARS["xiaonuo"])

static func skill_cfg(asset_id: String) -> Dictionary:
    return SKILLS.get(asset_id, SKILLS["xiaonuo"])

static func center_x(c: int) -> float:
    return c * TILE + TILE * 0.5

static func center_y(r: int) -> float:
    return r * TILE + TILE * 0.5
