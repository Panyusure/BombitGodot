class_name InputSettings
extends RefCounted

## 输入设置 + 输入层（PC 手柄适配 / 操作方式可选 / 键位重绑定 / user:// 持久化）。
##
## 为什么长这样：
## 1. 动作字典格式不能变（回放 ReplayUI 与 CLI 都按 {hx,hy,bomb,skill} 走），
##    所以本类只回答「某个玩家这一帧的 6 个功能是否按下」，由 Main 合成动作字典。
## 2. 绑定表的事实来源是 project.godot 的 InputMap 动作（p1_* / p1alt_* / p1vs_* / p2_*），
##    启动时快照成「默认值」；玩家的改动以覆盖形式写进 user://settings.cfg，
##    不写回 project.godot。「恢复默认」= 回到这份快照。
## 3. 键盘与手柄逐事件分开判定，才能按玩家选「自动 / 只用键盘 / 只用手柄」；
##    手柄一律查「该玩家选定的 device」，事件自带的 device 忽略。
## 4. 摇杆死区在软件层判定（Input.get_joy_axis 原值 vs 死区），漂移不会触发方向动作。

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_VERSION := 1

const SLOTS := ["p1", "p2"]

const FUNCS := ["left", "right", "up", "down", "bomb", "skill"]
const FUNC_LABELS := {
	"left": "左移", "right": "右移", "up": "上移",
	"down": "下移", "bomb": "放炸弹", "skill": "技能",
}

## 键位分组：p1=单人 1P 主键位（键盘+手柄）；p1alt=Tab 备用键盘位（仅键盘）；
## p1vs=对战 1P 键位（仅键盘，默认方向键 / 回车 / Shift）；p2=2P 键位（键盘+手柄）。
## 手柄只挂在 p1 / p2 上：方向键组按模式切换，手柄不需要跟着切。
const GROUPS := ["p1", "p1alt", "p1vs", "p2"]
const PAD_GROUPS := ["p1", "p2"]
const GROUP_LABELS := {
	"p1": "1P 主键位", "p1alt": "1P 备用键位", "p1vs": "1P 对战键位", "p2": "2P 键位",
}
const GROUP_SHORT := {"p1": "1P", "p1alt": "1P·备用", "p1vs": "1P·对战", "p2": "2P"}

const MODE_AUTO := "auto"
const MODE_KEYBOARD := "keyboard"
const MODE_GAMEPAD := "gamepad"
const MODES := [MODE_AUTO, MODE_KEYBOARD, MODE_GAMEPAD]
const MODE_LABELS := {MODE_AUTO: "自动", MODE_KEYBOARD: "键盘", MODE_GAMEPAD: "手柄"}
const MODE_HINTS := {
	MODE_AUTO: "键盘可用；有手柄时手柄同时可用",
	MODE_KEYBOARD: "只读键盘，忽略所有手柄",
	MODE_GAMEPAD: "只读手柄，忽略键盘",
}

const DEADZONE_MIN := 0.05
const DEADZONE_MAX := 0.80
const DEADZONE_DEFAULT := 0.35
## 重绑定摇杆时要推到的幅度，避免轻微漂移被当成一次绑定。
const CAPTURE_AXIS_ENGAGE := 0.6

const KEY_LABELS := {
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓",
	KEY_SPACE: "空格", KEY_ENTER: "回车", KEY_KP_ENTER: "小回车", KEY_SHIFT: "Shift",
	KEY_ESCAPE: "Esc", KEY_TAB: "Tab", KEY_BACKSPACE: "退格", KEY_DELETE: "Del",
}
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓",
	JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→",
}
const PAD_AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "左摇杆 横", JOY_AXIS_LEFT_Y: "左摇杆 纵",
	JOY_AXIS_RIGHT_X: "右摇杆 横", JOY_AXIS_RIGHT_Y: "右摇杆 纵",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}

static var _loaded := false
static var _defaults := {}          # action -> {"keys": Array[int], "pads": Array[Dictionary]}
static var _live := {}              # 同上，当前生效的绑定
static var _cfg := {}               # 见 _default_cfg()
static var _seen := {}              # device -> true（含未走 joy_connection_changed 的设备）


# ==================== 生命周期 ====================

static func _default_cfg() -> Dictionary:
	return {
		"deadzone": DEADZONE_DEFAULT,
		"rumble": true,
		"p1": {"mode": MODE_AUTO, "device": -1},
		"p2": {"mode": MODE_AUTO, "device": -1},
		"audio": {"sfx": 1.0, "music": 1.0},
	}

## 幂等初始化：Main / Menu 的 _ready 都会调用，先到先算。
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cfg = _default_cfg()
	_defaults = {}
	for g in GROUPS:
		for f in FUNCS:
			var a := action_for(g, f)
			if not InputMap.has_action(a):
				push_warning("InputSettings: project.godot 缺少 InputMap 动作 %s" % a)
				continue
			_defaults[a] = _read_action(a)
	_live = _clone_table(_defaults)
	_load_file()
	_apply_live()


static func action_for(group: String, func_name: String) -> String:
	return "%s_%s" % [group, func_name]


static func is_ready() -> bool:
	return _loaded


static func _read_action(action: String) -> Dictionary:
	var keys: Array = []
	var pads: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc := int(ev.keycode)
			if kc == 0:
				kc = int(ev.physical_keycode)
			if kc != 0 and not keys.has(kc):
				keys.append(kc)
		elif ev is InputEventJoypadButton:
			pads.append({"type": "button", "index": int(ev.button_index)})
		elif ev is InputEventJoypadMotion:
			pads.append({"type": "axis", "axis": int(ev.axis),
				"value": -1.0 if float(ev.axis_value) < 0.0 else 1.0})
	return {"keys": keys, "pads": pads}


static func _clone_table(src: Dictionary) -> Dictionary:
	var out := {}
	for a in src.keys():
		out[a] = {
			"keys": (src[a]["keys"] as Array).duplicate(),
			"pads": (src[a]["pads"] as Array).duplicate(true),
		}
	return out


static func _valid_mode(m: String) -> String:
	return m if MODES.has(m) else MODE_AUTO


static func _int_array(v) -> Array:
	var out: Array = []
	if v is Array:
		for item in v:
			var kc := int(item)
			if kc != 0 and not out.has(kc):
				out.append(kc)
	return out


static func _pad_array(v) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	for item in v:
		if not (item is Dictionary):
			continue
		var t := String(item.get("type", ""))
		if t == "button":
			out.append({"type": "button", "index": int(item.get("index", 0))})
		elif t == "axis":
			out.append({"type": "axis", "axis": int(item.get("axis", 0)),
				"value": -1.0 if float(item.get("value", 1.0)) < 0.0 else 1.0})
	return out


# ==================== 持久化 ====================

static func _load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(CONFIG_PATH) != OK:
		return
	_cfg["deadzone"] = clampf(float(cf.get_value("controller", "deadzone", DEADZONE_DEFAULT)),
		DEADZONE_MIN, DEADZONE_MAX)
	_cfg["rumble"] = bool(cf.get_value("controller", "rumble", true))
	for s in SLOTS:
		_cfg[s]["mode"] = _valid_mode(String(cf.get_value("controller", "%s_mode" % s, MODE_AUTO)))
		_cfg[s]["device"] = int(cf.get_value("controller", "%s_device" % s, -1))
	for kind in ["sfx", "music"]:
		_cfg["audio"][kind] = clampf(float(cf.get_value("audio", kind, 1.0)), 0.0, 1.0)
	for g in GROUPS:
		for f in FUNCS:
			var a := action_for(g, f)
			if not _live.has(a):
				continue
			if cf.has_section_key("keys", a):
				_live[a]["keys"] = _int_array(cf.get_value("keys", a, []))
			if cf.has_section_key("pads", a):
				_live[a]["pads"] = _pad_array(cf.get_value("pads", a, []))


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", CONFIG_VERSION)
	cf.set_value("controller", "deadzone", float(_cfg["deadzone"]))
	cf.set_value("controller", "rumble", bool(_cfg["rumble"]))
	for s in SLOTS:
		cf.set_value("controller", "%s_mode" % s, String(_cfg[s]["mode"]))
		cf.set_value("controller", "%s_device" % s, int(_cfg[s]["device"]))
	for kind in ["sfx", "music"]:
		cf.set_value("audio", kind, float(_cfg["audio"][kind]))
	var names := _live.keys()
	names.sort()
	for a in names:
		cf.set_value("keys", a, _live[a]["keys"])
		cf.set_value("pads", a, _live[a]["pads"])
	var err := cf.save(CONFIG_PATH)
	if err != OK:
		push_warning("InputSettings: 写入 %s 失败（%s）" % [CONFIG_PATH, error_string(err)])


# ==================== 应用到 InputMap ====================

static func _make_pad_event(pad: Dictionary) -> InputEvent:
	if String(pad.get("type", "")) == "button":
		var b := InputEventJoypadButton.new()
		b.button_index = int(pad.get("index", 0))
		b.device = -1
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = int(pad.get("axis", 0))
	m.axis_value = -1.0 if float(pad.get("value", 1.0)) < 0.0 else 1.0
	m.device = -1
	return m


## 把当前绑定写回 InputMap（别的消费者如 Input.is_action_pressed 也能用），
## 同时把摇杆死区同步到动作上。
static func _apply_live() -> void:
	var dz := float(_cfg["deadzone"])
	for a in _live.keys():
		if not InputMap.has_action(a):
			continue
		InputMap.action_erase_events(a)
		InputMap.action_set_deadzone(a, dz)
		for kc in _live[a]["keys"]:
			var k := InputEventKey.new()
			k.keycode = int(kc)
			k.device = -1
			InputMap.action_add_event(a, k)
		for pad in _live[a]["pads"]:
			InputMap.action_add_event(a, _make_pad_event(pad))


static func _sync_deadzone() -> void:
	var dz := float(_cfg["deadzone"])
	for g in GROUPS:
		for f in FUNCS:
			var a := action_for(g, f)
			if InputMap.has_action(a):
				InputMap.action_set_deadzone(a, dz)


# ==================== 手柄设备 ====================

## 已连接 + 见过的设备（MCP 注入 / 部分平台不上报的手柄也会出现在这里）。
static func available_devices() -> Array:
	ensure_loaded()
	var set := {}
	for d in Input.get_connected_joypads():
		set[int(d)] = true
	for d in _seen.keys():
		set[int(d)] = true
	var out := set.keys()
	out.sort()
	return out


## 记住一个设备号：Main._input 收到手柄事件时调用，补上平台没广播的接入。
static func note_device(device: int) -> void:
	if device < 0:
		return
	if _seen.has(device):
		return
	_seen[device] = true


static func notify_joy_connection(device: int, connected: bool) -> void:
	if connected:
		_seen[device] = true
	else:
		_seen.erase(device)


static func device_setting(slot: String) -> int:
	ensure_loaded()
	return int(_cfg[slot]["device"])


static func set_device(slot: String, device: int) -> void:
	ensure_loaded()
	_cfg[slot]["device"] = device
	_save()


## 该玩家这一帧实际要读的手柄号；-1 = 没有可用手柄。
static func slot_device(slot: String) -> int:
	ensure_loaded()
	var explicit := int(_cfg[slot]["device"])
	if explicit >= 0:
		return explicit
	var devs := available_devices()
	if slot == "p1":
		return int(devs[0]) if devs.size() > 0 else -1
	var idx := 1
	# 1P 被强制键盘时手柄让给 2P，否则 2P 只有第二个手柄才自动接手。
	if String(_cfg["p1"]["mode"]) == MODE_KEYBOARD:
		idx = 0
	return int(devs[idx]) if devs.size() > idx else -1


static func device_name(device: int) -> String:
	if device < 0:
		return "无"
	var n := Input.get_joy_name(device)
	if n.is_empty():
		n = "未知手柄"
	return "%d: %s" % [device, n]


static func device_supports_rumble(device: int) -> bool:
	return device >= 0 and Input.has_joy_vibration(device)


static func any_rumble_device() -> bool:
	for d in available_devices():
		if Input.has_joy_vibration(int(d)):
			return true
	return false


# ==================== 操作方式 / 死区 / 震动 ====================

static func device_mode(slot: String) -> String:
	ensure_loaded()
	return String(_cfg[slot]["mode"])


static func set_device_mode(slot: String, mode: String) -> void:
	ensure_loaded()
	_cfg[slot]["mode"] = _valid_mode(mode)
	_save()


static func deadzone() -> float:
	ensure_loaded()
	return float(_cfg["deadzone"])


## persist=false 用于滑块拖动：只改内存里的值，松手再落盘。
static func set_deadzone(value: float, persist: bool = true) -> void:
	ensure_loaded()
	_cfg["deadzone"] = clampf(value, DEADZONE_MIN, DEADZONE_MAX)
	_sync_deadzone()
	if persist:
		_save()


static func rumble_enabled() -> bool:
	ensure_loaded()
	return bool(_cfg["rumble"])


static func set_rumble(on: bool) -> void:
	ensure_loaded()
	_cfg["rumble"] = on
	_save()


static func audio_value(kind: String) -> float:
	ensure_loaded()
	return float(_cfg["audio"].get(kind, 1.0))


static func set_audio_value(kind: String, value: float) -> void:
	ensure_loaded()
	_cfg["audio"][kind] = clampf(value, 0.0, 1.0)
	_save()


## 输入反馈：放弹 / 技能按下时的一次短震动。没手柄或不支持震动时静默跳过。
static func pulse(slot: String, kind: String) -> void:
	ensure_loaded()
	if not bool(_cfg["rumble"]):
		return
	var dev := slot_device(slot)
	if dev < 0 or not Input.has_joy_vibration(dev):
		return
	if kind == "skill":
		Input.start_joy_vibration(dev, 0.45, 0.72, 0.18)
	else:
		Input.start_joy_vibration(dev, 0.32, 0.55, 0.12)


# ==================== 每帧轮询（输入层核心） ====================

## profile: "solo"（主键位）| "alt"（Tab 备用键位）| "versus"（对战 1P 键位）
static func poll_player(slot: String, profile: String) -> Dictionary:
	ensure_loaded()
	var kb_group := _kb_group(slot, profile)
	var pad_group := slot
	var mode := String(_cfg[slot]["mode"])
	var dev := slot_device(slot)
	var use_kb := mode != MODE_GAMEPAD
	var use_pad: bool = mode != MODE_KEYBOARD and dev >= 0
	var out := {}
	for f in FUNCS:
		var on := false
		if use_kb and _keys_pressed(kb_group, f):
			on = true
		elif use_pad and _pad_pressed(pad_group, f, dev):
			on = true
		out[f] = on
	return out


static func _kb_group(slot: String, profile: String) -> String:
	if slot == "p2":
		return "p2"
	if profile == "alt":
		return "p1alt"
	if profile == "versus":
		return "p1vs"
	return "p1"


static func _keys_pressed(group: String, func_name: String) -> bool:
	var entry = _live.get(action_for(group, func_name))
	if entry == null:
		return false
	for kc in entry["keys"]:
		if Input.is_key_pressed(int(kc)):
			return true
	return false


static func _pad_pressed(group: String, func_name: String, device: int) -> bool:
	var entry = _live.get(action_for(group, func_name))
	if entry == null:
		return false
	var dz := float(_cfg["deadzone"])
	for pad in entry["pads"]:
		if String(pad.get("type", "")) == "button":
			if Input.is_joy_button_pressed(device, int(pad.get("index", -1))):
				return true
		else:
			var v := Input.get_joy_axis(device, int(pad.get("axis", 0)))
			if float(pad.get("value", 1.0)) < 0.0:
				if v <= -dz:
					return true
			elif v >= dz:
				return true
	return false


# ==================== 绑定表 / 重绑定 ====================

static func live_bindings(action: String) -> Dictionary:
	ensure_loaded()
	var entry = _live.get(action)
	if entry == null:
		return {"keys": [], "pads": []}
	return entry


static func has_custom_bindings() -> bool:
	ensure_loaded()
	for a in _live.keys():
		if not _defaults.has(a):
			return true
		if _live[a]["keys"] != _defaults[a]["keys"]:
			return true
		if _live[a]["pads"] != _defaults[a]["pads"]:
			return true
	return false


static func key_labels(action: String) -> Array:
	var out: Array = []
	for kc in live_bindings(action)["keys"]:
		out.append(key_label(int(kc)))
	return out


static func pad_labels(action: String) -> Array:
	var out: Array = []
	for pad in live_bindings(action)["pads"]:
		out.append(pad_label(pad))
	return out


static func first_key_label(action: String) -> String:
	var labels := key_labels(action)
	return String(labels[0]) if labels.size() > 0 else "—"


static func key_label(keycode: int) -> String:
	if KEY_LABELS.has(keycode):
		return String(KEY_LABELS[keycode])
	var s := OS.get_keycode_string(keycode)
	return s if not s.is_empty() else ("#%d" % keycode)


static func pad_label(pad: Dictionary) -> String:
	if String(pad.get("type", "")) == "button":
		var idx := int(pad.get("index", -1))
		return String(PAD_BUTTON_NAMES.get(idx, "按键%d" % idx))
	var ax := int(pad.get("axis", 0))
	var name := String(PAD_AXIS_NAMES.get(ax, "轴%d" % ax))
	return name + ("−" if float(pad.get("value", 1.0)) < 0.0 else "+")


## 该分组重绑键盘时要一起改的分组（1P 主键位与对战键位共用同一套键）。
static func _mirror_groups(group: String) -> Array:
	if group == "p1" or group == "p1vs":
		return ["p1", "p1vs"]
	return [group]


## 冲突判定的身份：p1 / p1vs 视为同一套（同一功能），p1alt 是独立的一套。
static func _identity(group: String, func_name: String) -> String:
	if group == "p1alt":
		return "p1alt:" + func_name
	return ("p2:" if group == "p2" else "p1:") + func_name


static func _owner_label(group: String, func_name: String) -> String:
	return "%s · %s" % [String(GROUP_SHORT.get(group, group)), String(FUNC_LABELS.get(func_name, func_name))]


static func _pad_key(pad: Dictionary) -> String:
	if String(pad.get("type", "")) == "button":
		return "button:%d" % int(pad.get("index", -1))
	return "axis:%d:%s" % [int(pad.get("axis", 0)), "-" if float(pad.get("value", 1.0)) < 0.0 else "+"]


static func _conflict_owner(group: String, func_name: String, kind: String, token: String) -> String:
	var me := _identity(group, func_name)
	for g in GROUPS:
		for f in FUNCS:
			if _identity(g, f) == me:
				continue
			var entry = _live.get(action_for(g, f))
			if entry == null:
				continue
			if kind == "key":
				if (entry["keys"] as Array).has(int(token)):
					return _owner_label(g, f)
			else:
				for pad in entry["pads"]:
					if _pad_key(pad) == token:
						return _owner_label(g, f)
	return ""


## 重绑一个键盘按键。返回 {"ok": bool, "conflict": String}。
static func bind_key(group: String, func_name: String, keycode: int) -> Dictionary:
	ensure_loaded()
	if keycode == 0:
		return {"ok": false, "conflict": ""}
	var action := action_for(group, func_name)
	if not _live.has(action):
		return {"ok": false, "conflict": ""}
	var owner := _conflict_owner(group, func_name, "key", str(keycode))
	if owner != "":
		return {"ok": false, "conflict": owner}
	for g in _mirror_groups(group):
		var a := action_for(g, func_name)
		if _live.has(a):
			_live[a]["keys"] = [keycode]
	_save()
	_apply_live()
	return {"ok": true, "conflict": ""}


## 重绑一个手柄按钮 / 摇杆方向。pad = {"type":"button","index":n} 或
## {"type":"axis","axis":n,"value":±1}。返回 {"ok": bool, "conflict": String}。
static func bind_pad(group: String, func_name: String, pad: Dictionary) -> Dictionary:
	ensure_loaded()
	if not PAD_GROUPS.has(group):
		return {"ok": false, "conflict": "该键位组不支持手柄"}
	var action := action_for(group, func_name)
	if not _live.has(action):
		return {"ok": false, "conflict": ""}
	var clean := _pad_array([pad])
	if clean.is_empty():
		return {"ok": false, "conflict": ""}
	var owner := _conflict_owner(group, func_name, "pad", _pad_key(clean[0]))
	if owner != "":
		return {"ok": false, "conflict": owner}
	_live[action]["pads"] = clean
	_save()
	_apply_live()
	return {"ok": true, "conflict": ""}


## kind: "key" 或 "pad"；清空该功能的对应绑定（Del 键）。
static func clear_binding(group: String, func_name: String, kind: String) -> void:
	ensure_loaded()
	for g in (_mirror_groups(group) if kind == "key" else [group]):
		var a := action_for(g, func_name)
		if _live.has(a):
			_live[a]["keys" if kind == "key" else "pads"] = []
	_save()
	_apply_live()


static func reset_defaults() -> void:
	ensure_loaded()
	_live = _clone_table(_defaults)
	_save()
	_apply_live()


# ==================== 调试 / 取证 ====================

static func debug_snapshot() -> Dictionary:
	ensure_loaded()
	var binds := {}
	for g in GROUPS:
		for f in FUNCS:
			var a := action_for(g, f)
			var e = _live.get(a, {"keys": [], "pads": []})
			binds[a] = {"keys": key_labels(a), "pads": pad_labels(a), "raw_keys": e["keys"]}
	return {
		"config_path": CONFIG_PATH,
		"config_abs": ProjectSettings.globalize_path(CONFIG_PATH),
		"loaded": _loaded,
		"deadzone": float(_cfg["deadzone"]),
		"rumble": bool(_cfg["rumble"]),
		"p1": {"mode": String(_cfg["p1"]["mode"]), "device_setting": int(_cfg["p1"]["device"]),
			"device_resolved": slot_device("p1")},
		"p2": {"mode": String(_cfg["p2"]["mode"]), "device_setting": int(_cfg["p2"]["device"]),
			"device_resolved": slot_device("p2")},
		"connected": Input.get_connected_joypads(),
		"seen": _seen.keys(),
		"available": available_devices(),
		"custom": has_custom_bindings(),
		"bindings": binds,
	}
