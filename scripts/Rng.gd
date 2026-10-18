class_name Rng
extends RefCounted

## 可复现随机数（xorshift32），用于地图、掉落与敌人决策。

var state: int = 1

func _init(seed_value: int = 1) -> void:
    state = seed_value & 0x7fffffff
    if state == 0:
        state = 1
    # 预热，避免低种子开头过于规律
    for i in 3:
        next_int()

func next_int() -> int:
    var x = state
    x ^= (x << 13) & 0xffffffff
    x ^= x >> 17
    x ^= (x << 5) & 0xffffffff
    state = x & 0x7fffffff
    if state == 0:
        state = 1
    return state

func next_float() -> float:
    return float(next_int()) / 2147483648.0

func chance(p: float) -> bool:
    return next_float() < p

func rand_range_f(lo: float, hi: float) -> float:
    return lo + next_float() * (hi - lo)

func randi_range(lo: int, hi: int) -> int:
    if hi <= lo:
        return lo
    return lo + next_int() % (hi - lo + 1)

func pick(arr: Array):
    if arr.is_empty():
        return null
    return arr[next_int() % arr.size()]

func shuffle(arr: Array) -> void:
    for i in range(arr.size() - 1, 0, -1):
        var j = next_int() % (i + 1)
        var tmp = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp

static func hash_seed(text: String) -> int:
    var h = 2166136261
    for i in text.length():
        h ^= text.unicode_at(i)
        h = (h * 16777619) & 0x7fffffff
    return h if h != 0 else 1
