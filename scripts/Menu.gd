class_name Menu
extends Control

## STEP 01 / STEP 02 菜单：按原作 menu.js 的 Motion UI 版式逐项复刻。
## 奶油纸 + 墨线 + 硬阴影 + 半调网点 + 角色动效海报。

signal start_requested(mode: String, p1: String, p2: String)
signal mute_toggled
signal replay_requested
signal settings_closed
signal lan_requested

const MODES := [
	{"id": "adventure", "input_mode": "solo", "label": "单人 · 闯关打怪",
		"desc": "共10关 · 第5、10关BOSS战", "players": 1,
		"color": Color("62DF88"), "soft": Color("C9F2B7"), "abbr": "ADV",
		"motif": "maze", "no": "01", "tagline": "十关清场 · 鲁鲁旦三阶段"},
	{"id": "dig", "input_mode": "solo", "label": "单人 · 计时拆砖",
		"desc": "限时清除全部障碍", "players": 1,
		"color": Color("5CE1F2"), "soft": Color("C9F3F9"), "abbr": "TIME",
		"motif": "clock", "no": "02", "tagline": "倒计时 · 全图障碍"},
	{"id": "versus", "input_mode": "versus", "label": "双人 · 同屏对战",
		"desc": "先得 2 分者获胜", "players": 2,
		"color": Color("FF5E9E"), "soft": Color("FFD0DE"), "abbr": "VS",
		"motif": "versus", "no": "03", "tagline": "同屏双打 · 先到 2 分"},
	{"id": "lan", "input_mode": "lan", "label": "联机对战",
		"desc": "两台电脑 · 局域网实时对战", "players": 2,
		"color": Color("FFD23F"), "soft": Color("FFF0B5"), "abbr": "LAN",
		"motif": "network", "no": "04", "tagline": "创建 / 加入房间 · 独立选角"},
]

const CHAR_UI := {
	"xiaonuo": {"color": Color("FFD23F"), "accent": Color("5CE1F2"), "role": "时间"},
	"axiu": {"color": Color("F5233C"), "accent": Color("FFD23F"), "role": "暗影"},
	"arui": {"color": Color("62DF88"), "accent": Color("FFD23F"), "role": "守护"},
	"xiaoyan": {"color": Color("FF5533"), "accent": Color("FFD23F"), "role": "烈焰"},
	"xiaotian": {"color": Color("66C8FF"), "accent": Color("FFFDF6"), "role": "洞察"},
	"weilai": {"color": Color("FF5E9E"), "accent": Color("5CE1F2"), "role": "通灵"},
}

const BTN := {"w": 360.0, "h": 56.0, "y": 566.0}
const REPLAY_BTN := {"x": 544.0, "y": 22.0, "w": 118.0, "h": 38.0}
const SETTINGS_BTN := {"x": 670.0, "y": 24.0, "w": 32.0, "h": 34.0}
const BACK_BTN := {"x": 20.0, "y": 566.0, "w": 136.0, "h": 56.0}
const MODE_CARD := {"x": 20.0, "y": 226.0, "w": 218.0, "h": 314.0, "gap": 13.0}
const GRID := {"x": 20.0, "y": 450.0, "w": 106.0, "h": 80.0, "gapX": 8.0, "cols": 6}
const POSTER := {"x": 20.0, "y": 128.0, "w": 680.0, "h": 310.0}
const SETTINGS_CARD := {"x": 60.0, "y": 38.0, "w": 600.0, "h": 620.0}
## 焦点方向键首次重复延迟 / 之后每格间隔（秒）
const NAV_FIRST_DELAY := 0.35
const NAV_REPEAT_DELAY := 0.09
const SETTINGS_TABS := [
	{"id": "audio", "label": "画面与声音", "en": "AV"},
	{"id": "pad", "label": "控制器", "en": "PAD"},
	{"id": "keys", "label": "键位", "en": "KEYS"},
]
const SETTINGS_TAB := {"x": 20.0, "y": 66.0, "w": 150.0, "h": 30.0, "gap": 12.0}
const SETTINGS_BODY := {"x": 26.0, "y": 112.0, "w": 548.0, "h": 440.0}
const SETTINGS_FOOT := 46.0
const SETTINGS_SLIDER := {"x": 8.0, "w": 532.0, "h": 8.0}
const AUDIO_ROW_Y := [68.0, 166.0]
const PAD_SEG := {"x": 150.0, "y": 40.0, "w": 86.0, "h": 26.0, "gap": 8.0}
const PAD_DEV := {"x": 150.0, "y": 76.0, "w": 214.0, "h": 26.0}
const PAD_BLOCK_H := 108.0
const PAD_DZ_Y := 280.0
const PAD_RUMBLE_Y := 330.0
const PAD_HINT_Y := 400.0
const KEYS_ROW := {"y": 80.0, "h": 40.0, "gap": 4.0}
const KEYS_ZONE := {"keyX": 100.0, "keyW": 200.0, "padX": 304.0, "padW": 216.0}

var step := "mode"
var mode_index := 0
var char_index: Array = [0, 1]
var player := 0
var t := 0.0
var pulse := 0.0
var step_t := 0.0
var switch_t := 1.0
var hover := {}
var settings_open := false
var settings_only := false
var drag_slider := ""
var sfx_level := 1.0
var music_level := 1.0
var toast_text := ""
var toast_time := 0.0
var settings_tab := "audio"
var keys_player := 0
var keys_profile := "main"
var capture_target := {}
var pad_notice := ""
var _started := false
var audio = null

# ---- 焦点 / 手柄导航状态机 ----
# nav_mode: true = 最近一次操作来自手柄或键盘方向键，画焦点环并让鼠标悬停让位；
#           false = 最近一次操作来自鼠标，画悬停高亮、不画焦点环。
var nav_mode := false
var nav_focus := {}            # domain -> 焦点项 key（每个域各记一份，跨页签/进入子页后可恢复）
var nav_dir := ""              # 当前按住的方向
var nav_timer := 0.0           # 方向键重复计时
var nav_accept_prev := false
var nav_cancel_prev := false
var nav_pending_slider := ""   # 方向键调过、等松手才落盘的滑块
var nav_release_required := false

var wallpaper: Texture2D = null
var char_tex := {}
var versus_lobby: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	audio = get_node_or_null("/root/GameAudio")
	# 输入层：读 user://settings.cfg（操作方式 / 手柄 / 死区 / 绑定表 / 音量），
	# 并订阅手柄热插拔，接入或拔出后设置面板与设备名会立刻刷新。
	InputSettings.ensure_loaded()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	versus_lobby = preload("res://versus_lobby.tscn").instantiate()
	add_child(versus_lobby)
	versus_lobby.visible = false
	versus_lobby.start_requested.connect(_on_lobby_start)
	versus_lobby.back_requested.connect(_back_to_mode)
	versus_lobby.settings_requested.connect(_open_settings)
	if audio != null:
		audio.call("set_sfx_level", InputSettings.audio_value("sfx"))
		audio.call("set_music_level", InputSettings.audio_value("music"))
		sfx_level = float(audio.get("sfx_level"))
		music_level = float(audio.get("music_level"))
	if ResourceLoader.exists("res://assets/ui/menu-wallpaper.jpg"):
		wallpaper = load("res://assets/ui/menu-wallpaper.jpg")
	for cid in Cfg.CHAR_IDS:
		var path := "res://assets/characters/%s.png" % cid
		if ResourceLoader.exists(path):
			char_tex[cid] = load(path)
	set_process(true)

func setup(_muted: bool) -> void:
	pass

func set_muted(_v: bool) -> void:
	pass

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	InputSettings.notify_joy_connection(device, connected)
	if _is_versus_lobby() and versus_lobby.model.active and versus_lobby.model.refresh_routes():
		versus_lobby.prime_inputs(versus_lobby.model.changed_slots)
	pad_notice = "手柄 %d %s" % [device, "已接入" if connected else "已拔出"]
	_show_toast(pad_notice)
	queue_redraw()

func reset() -> void:
	if versus_lobby != null:
		versus_lobby.close()
	_started = false
	step = "mode"
	settings_open = false
	settings_only = false
	capture_target = {}
	toast_text = ""
	step_t = 0.0
	player = 0
	switch_t = 1.0
	InputSettings.active_players = 2
	nav_focus.clear()
	_sync_nav()

func _process(delta: float) -> void:
	t += delta
	pulse += delta
	# 原作 menu.js:421-422 是 st.stepT = min(1, stepT + dt*5)、st.switchT = min(1, switchT + dt*4)：
	# 两者都要按 5×/4× 推进并夹在 1 以内，否则入场动画比原作慢 5 倍且 step_t 会无限增长。
	step_t = minf(1.0, step_t + delta * 5.0)
	switch_t = minf(1.0, switch_t + delta * 4.0)
	if toast_time > 0.0:
		toast_time -= delta
	versus_lobby.visible = visible and _is_versus_lobby() and not settings_open and not _started and not settings_only
	if visible:
		_update_hover()
		if not _started:
			_process_nav(delta)
	queue_redraw()

func _mode() -> Dictionary:
	return MODES[mode_index]

func _is_versus_lobby() -> bool:
	return step == "chars" and String(_mode()["id"]) == "versus"

func _on_lobby_start(c1: String, c2: String) -> void:
	if _started or not visible or not _is_versus_lobby() or settings_open:
		return
	if not versus_lobby.model.start_authorized(c1, c2):
		return
	_started = true
	start_requested.emit("versus", c1, c2)

func versus_start_authorized(c1: String, c2: String) -> bool:
	return _started and _is_versus_lobby() and versus_lobby.model.start_authorized(c1, c2)

func _char(i: int) -> String:
	return Cfg.CHAR_IDS[clampi(int(char_index[i]), 0, Cfg.CHAR_IDS.size() - 1)]

func _player_color() -> Color:
	return UIDraw.PINK if player == 1 else UIDraw.CYAN

func _char_visual(cid: String) -> Dictionary:
	return CHAR_UI.get(cid, {"color": UIDraw.CYAN, "accent": UIDraw.YELLOW, "role": "精灵"})

func _mode_rects() -> Array:
	var out: Array = []
	for i in MODES.size():
		out.append(Rect2(20 + (i % 2) * 348, 226 + (i / 2) * 166, 332, 148))
	return out

func _char_rects() -> Array:
	var out: Array = []
	for i in Cfg.CHAR_IDS.size():
		out.append(Rect2(GRID["x"] + i * (GRID["w"] + GRID["gapX"]), GRID["y"], GRID["w"], GRID["h"]))
	return out

func _tab_rects() -> Array:
	if int(_mode()["players"]) == 1:
		return [Rect2(20, 96, 220, 24)]
	return [Rect2(20, 96, 140, 24), Rect2(166, 96, 140, 24)]

func _cta_rect() -> Rect2:
	return Rect2((Cfg.VIEW_W - BTN["w"]) * 0.5, BTN["y"], BTN["w"], BTN["h"])

func _hit(rect: Rect2, p: Vector2) -> bool:
	return rect.has_point(p)

func _replay_rect() -> Rect2:
	return Rect2(REPLAY_BTN["x"], REPLAY_BTN["y"], REPLAY_BTN["w"], REPLAY_BTN["h"])

func _settings_rect() -> Rect2:
	return Rect2(SETTINGS_BTN["x"], SETTINGS_BTN["y"], SETTINGS_BTN["w"], SETTINGS_BTN["h"])

func _update_hover() -> void:
	hover = {}
	if not visible:
		return
	# 手柄 / 键盘方向键刚操作过：让鼠标悬停高亮让位，只显示焦点环，避免两处同时高亮
	if nav_mode:
		return
	if settings_open:
		_update_settings_hover()
		return
	var p := get_local_mouse_position()
	if _hit(_replay_rect(), p):
		hover = {"kind": "replay"}
	elif _hit(_settings_rect(), p):
		hover = {"kind": "settings"}
	elif step == "mode":
		var cards := _mode_rects()
		for i in cards.size():
			if _hit(cards[i], p):
				hover = {"kind": "mode", "index": i}
				return
		if _hit(_cta_rect(), p):
			hover = {"kind": "cta"}
	else:
		var tiles := _char_rects()
		for i in tiles.size():
			if _hit(tiles[i], p):
				hover = {"kind": "card", "index": i}
				return
		var tabs := _tab_rects()
		for i in tabs.size():
			if _hit(tabs[i], p):
				hover = {"kind": "tab", "index": i}
				return
		if _hit(Rect2(BACK_BTN["x"], BACK_BTN["y"], BACK_BTN["w"], BACK_BTN["h"]), p):
			hover = {"kind": "back"}
		elif _hit(_cta_rect(), p):
			hover = {"kind": "cta"}

# ---------------- 输入 ----------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 鼠标一动：焦点环让位给悬停高亮
		nav_mode = false
		_update_hover()
		if drag_slider != "" and settings_open:
			_set_slider_from_mouse(drag_slider, event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			nav_mode = false
			if settings_open:
				_handle_settings_click(event.position)
			else:
				_handle_click(event.position)
		else:
			if drag_slider != "":
				_commit_slider(drag_slider)
			drag_slider = ""
		accept_event()

func _handle_click(p: Vector2) -> void:
	if _is_versus_lobby():
		return
	if _hit(_replay_rect(), p):
		replay_requested.emit()
		return
	if _hit(_settings_rect(), p):
		_open_settings()
		return
	if step == "mode":
		var cards := _mode_rects()
		for i in cards.size():
			if _hit(cards[i], p):
				if mode_index != i:
					mode_index = i
					switch_t = 0.0
				return
		if _hit(_cta_rect(), p):
			_open_character()
		return
	var tiles := _char_rects()
	for i in tiles.size():
		if _hit(tiles[i], p):
			_select_char(i)
			return
	var tabs := _tab_rects()
	for i in tabs.size():
		if _hit(tabs[i], p):
			player = i
			switch_t = 0.0
			return
	if _hit(Rect2(BACK_BTN["x"], BACK_BTN["y"], BACK_BTN["w"], BACK_BTN["h"]), p):
		_back_to_mode()
	elif _hit(_cta_rect(), p):
		_confirm()

# ---------------- 设置面板：几何 ----------------

func _settings_body_x() -> float:
	return float(SETTINGS_CARD["x"]) + float(SETTINGS_BODY["x"])

func _settings_body_y() -> float:
	return float(SETTINGS_CARD["y"]) + float(SETTINGS_BODY["y"])

func _settings_close_rect() -> Rect2:
	return Rect2(float(SETTINGS_CARD["x"]) + float(SETTINGS_CARD["w"]) - 42,
		float(SETTINGS_CARD["y"]) + 16, 26, 26)

func _settings_done_rect() -> Rect2:
	return Rect2(float(SETTINGS_CARD["x"]) + float(SETTINGS_CARD["w"]) - 120,
		float(SETTINGS_CARD["y"]) + float(SETTINGS_CARD["h"]) - SETTINGS_FOOT, 96, 30)

func _fullscreen_rect() -> Rect2:
	return Rect2(_settings_body_x() + 8, _settings_body_y() + 284, 532, 48)

func _settings_tab_rect(i: int) -> Rect2:
	return Rect2(float(SETTINGS_CARD["x"]) + float(SETTINGS_TAB["x"])
		+ i * (float(SETTINGS_TAB["w"]) + float(SETTINGS_TAB["gap"])),
		float(SETTINGS_CARD["y"]) + float(SETTINGS_TAB["y"]),
		float(SETTINGS_TAB["w"]), float(SETTINGS_TAB["h"]))

func _settings_slider_rect(kind: String) -> Rect2:
	var y := _settings_body_y()
	match kind:
		"sfx":
			y += float(AUDIO_ROW_Y[0])
		"music":
			y += float(AUDIO_ROW_Y[1])
		"deadzone":
			y += PAD_DZ_Y
	return Rect2(_settings_body_x() + float(SETTINGS_SLIDER["x"]), y,
		float(SETTINGS_SLIDER["w"]), float(SETTINGS_SLIDER["h"]))

## 滑块的可点区域（轨道上下各留 8px 容错）。
func _settings_slider_hit(kind: String) -> Rect2:
	var r := _settings_slider_rect(kind)
	return Rect2(r.position.x, r.position.y - 8, r.size.x, 24)

func _slider_range(kind: String) -> Vector2:
	if kind == "deadzone":
		return Vector2(InputSettings.DEADZONE_MIN, InputSettings.DEADZONE_MAX)
	return Vector2(0.0, 1.0)

func _pad_seg_rect(s: int, i: int) -> Rect2:
	return Rect2(_settings_body_x() + float(PAD_SEG["x"])
		+ i * (float(PAD_SEG["w"]) + float(PAD_SEG["gap"])),
		_settings_body_y() + float(PAD_SEG["y"]) + s * PAD_BLOCK_H,
		float(PAD_SEG["w"]), float(PAD_SEG["h"]))

func _pad_dev_rect(s: int, part: String) -> Rect2:
	var x := _settings_body_x() + float(PAD_DEV["x"])
	var y := _settings_body_y() + float(PAD_DEV["y"]) + s * PAD_BLOCK_H
	var w := float(PAD_DEV["w"])
	var h := float(PAD_DEV["h"])
	match part:
		"prev":
			return Rect2(x, y, 26, h)
		"next":
			return Rect2(x + w - 26, y, 26, h)
		"box":
			return Rect2(x + 30, y, w - 60, h)
	return Rect2(x, y, w, h)

func _pad_rumble_rect() -> Rect2:
	return Rect2(_settings_body_x() + float(PAD_SEG["x"]), _settings_body_y() + PAD_RUMBLE_Y,
		float(PAD_SEG["w"]), float(PAD_SEG["h"]))

func _keys_player_rect(i: int) -> Rect2:
	return Rect2(_settings_body_x() + 4 + i * 78, _settings_body_y() + 4, 74, 26)

func _keys_profile_rect(i: int) -> Rect2:
	return Rect2(_settings_body_x() + 170 + i * 100, _settings_body_y() + 4, 96, 26)

func _keys_row_rect(i: int) -> Rect2:
	return Rect2(_settings_body_x() + 4,
		_settings_body_y() + float(KEYS_ROW["y"]) + i * (float(KEYS_ROW["h"]) + float(KEYS_ROW["gap"])),
		float(SETTINGS_BODY["w"]) - 8, float(KEYS_ROW["h"]))

func _keys_zone_rect(i: int, kind: String) -> Rect2:
	var r := _keys_row_rect(i)
	var zx := float(KEYS_ZONE["keyX"]) if kind == "key" else float(KEYS_ZONE["padX"])
	var zw := float(KEYS_ZONE["keyW"]) if kind == "key" else float(KEYS_ZONE["padW"])
	return Rect2(r.position.x + zx, r.position.y + 5, zw, r.size.y - 10)

func _keys_reset_rect() -> Rect2:
	return Rect2(_settings_body_x() + 4, _settings_body_y() + 352, 130, 28)

func _keys_group() -> String:
	if keys_player == 1:
		return "p2"
	return "p1alt" if keys_profile == "alt" else "p1"

func _h(kind: String, slot: int = -99, index: int = -99) -> bool:
	if String(hover.get("kind", "")) != kind:
		return false
	if slot != -99 and int(hover.get("slot", -99)) != slot:
		return false
	if index != -99 and int(hover.get("index", -99)) != index:
		return false
	return true

func _ui_click() -> void:
	if audio != null:
		audio.play_sfx("ui_click")

func _show_toast(text: String) -> void:
	toast_text = text
	toast_time = 2.4

# ---------------- 设置面板：悬停 ----------------

func _update_settings_hover() -> void:
	if not capture_target.is_empty():
		return
	var p := get_local_mouse_position()
	if _hit(_settings_close_rect(), p):
		hover = {"kind": "settings_close"}
		return
	if _hit(_settings_done_rect(), p):
		hover = {"kind": "settings_done"}
		return
	for i in SETTINGS_TABS.size():
		if _hit(_settings_tab_rect(i), p):
			hover = {"kind": "tab", "index": i}
			return
	match settings_tab:
		"audio":
			if _hit(_fullscreen_rect(), p):
				hover = {"kind": "fullscreen"}
				return
			for kind in ["sfx", "music"]:
				if _hit(_settings_slider_hit(kind), p):
					hover = {"kind": "slider", "id": kind}
					return
		"pad":
			for s in 2:
				for i in InputSettings.MODES.size():
					if _hit(_pad_seg_rect(s, i), p):
						hover = {"kind": "pad_seg", "slot": s, "index": i}
						return
				for part in ["prev", "box", "next"]:
					if _hit(_pad_dev_rect(s, part), p):
						hover = {"kind": "pad_dev", "slot": s, "part": part}
						return
			if _hit(_pad_rumble_rect(), p):
				hover = {"kind": "rumble"}
				return
			if _hit(_settings_slider_hit("deadzone"), p):
				hover = {"kind": "slider", "id": "deadzone"}
				return
		"keys":
			for i in 2:
				if _hit(_keys_player_rect(i), p):
					hover = {"kind": "keys_player", "index": i}
					return
			if keys_player == 0:
				for i in 2:
					if _hit(_keys_profile_rect(i), p):
						hover = {"kind": "keys_profile", "index": i}
						return
			if _hit(_keys_reset_rect(), p):
				hover = {"kind": "keys_reset"}
				return
			for i in InputSettings.FUNCS.size():
				if _hit(_keys_zone_rect(i, "key"), p):
					hover = {"kind": "key_zone", "index": i}
					return
				if _hit(_keys_zone_rect(i, "pad"), p):
					hover = {"kind": "pad_zone", "index": i}
					return

# ---------------- 设置面板：点击 ----------------

func _handle_settings_click(p: Vector2) -> void:
	if _hit(_settings_close_rect(), p) or _hit(_settings_done_rect(), p):
		_close_settings()
		return
	for i in SETTINGS_TABS.size():
		if _hit(_settings_tab_rect(i), p):
			settings_tab = String(SETTINGS_TABS[i]["id"])
			capture_target = {}
			_ui_click()
			return
	match settings_tab:
		"audio":
			if _hit(_fullscreen_rect(), p):
				_nav_accept_settings("fullscreen")
				return
			for kind in ["sfx", "music"]:
				if _hit(_settings_slider_hit(kind), p):
					drag_slider = kind
					_set_slider_from_mouse(kind, p)
					return
		"pad":
			_handle_pad_click(p)
		"keys":
			_handle_keys_click(p)

func _handle_pad_click(p: Vector2) -> void:
	for s in 2:
		var slot := "p1" if s == 0 else "p2"
		for i in InputSettings.MODES.size():
			if _hit(_pad_seg_rect(s, i), p):
				var m := String(InputSettings.MODES[i])
				InputSettings.set_device_mode(slot, m)
				_ui_click()
				_show_toast("%s 操作方式：%s" % [slot.to_upper(), String(InputSettings.MODE_LABELS[m])])
				return
		if _hit(_pad_dev_rect(s, "prev"), p):
			_cycle_device(slot, -1)
			return
		if _hit(_pad_dev_rect(s, "next"), p) or _hit(_pad_dev_rect(s, "box"), p):
			_cycle_device(slot, 1)
			return
	if _hit(_pad_rumble_rect(), p):
		var on := not InputSettings.rumble_enabled()
		InputSettings.set_rumble(on)
		_ui_click()
		_show_toast("震动反馈：%s" % ("开" if on else "关"))
		return
	if _hit(_settings_slider_hit("deadzone"), p):
		drag_slider = "deadzone"
		_set_slider_from_mouse("deadzone", p)

## 设备选择循环：自动(-1) → 每个可用手柄 → 自动。
func _cycle_device(slot: String, dir: int) -> void:
	var options: Array = [-1]
	for d in InputSettings.available_devices():
		options.append(int(d))
	var idx := options.find(InputSettings.device_setting(slot))
	if idx < 0:
		idx = 0
	idx = (idx + dir + options.size()) % options.size()
	var picked := int(options[idx])
	InputSettings.set_device(slot, picked)
	_ui_click()
	_show_toast("%s 手柄：%s" % [slot.to_upper(),
		"自动" if picked < 0 else InputSettings.device_name(picked)])

func _handle_keys_click(p: Vector2) -> void:
	for i in 2:
		if _hit(_keys_player_rect(i), p):
			keys_player = i
			if i == 1:
				keys_profile = "main"
			capture_target = {}
			_ui_click()
			return
	if keys_player == 0:
		for i in 2:
			if _hit(_keys_profile_rect(i), p):
				keys_profile = "main" if i == 0 else "alt"
				capture_target = {}
				_ui_click()
				return
	if _hit(_keys_reset_rect(), p):
		InputSettings.reset_defaults()
		capture_target = {}
		_ui_click()
		_show_toast("已恢复默认键位")
		return
	var group := _keys_group()
	for i in InputSettings.FUNCS.size():
		var f := String(InputSettings.FUNCS[i])
		if _hit(_keys_zone_rect(i, "key"), p):
			capture_target = {"group": group, "func": f, "kind": "key", "index": i}
			_ui_click()
			return
		if _hit(_keys_zone_rect(i, "pad"), p):
			if not InputSettings.PAD_GROUPS.has(group):
				_show_toast("备用键位只支持键盘")
				return
			capture_target = {"group": group, "func": f, "kind": "pad", "index": i}
			_ui_click()
			return

## 捕获「按一下你要的键 / 按钮」：Esc 取消，Del / Backspace 清除该格。
func _handle_capture_event(event: InputEvent) -> void:
	var want := String(capture_target.get("kind", "key"))
	var group := String(capture_target.get("group", "p1"))
	var f := String(capture_target.get("func", "bomb"))
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		var kc := int(event.keycode)
		if kc == 0:
			kc = int(event.physical_keycode)
		if kc == KEY_ESCAPE:
			capture_target = {}
			_sync_nav()
			_show_toast("已取消改绑")
		elif kc == KEY_DELETE or kc == KEY_BACKSPACE:
			_apply_clear(want)
		elif want != "key":
			_show_toast("这一格是手柄位，请按手柄按钮 / 摇杆")
		else:
			_apply_bind(InputSettings.bind_key(group, f, kc), InputSettings.key_label(kc))
	elif event is InputEventJoypadButton:
		if not event.pressed:
			return
		if event.button_index == JOY_BUTTON_BACK:
			capture_target = {}
			_sync_nav()
			_show_toast("已取消改绑")
		elif want != "pad":
			_show_toast("这一格是键盘位，请按键盘按键")
		else:
			var pad := {"type": "button", "index": int(event.button_index)}
			_apply_bind(InputSettings.bind_pad(group, f, pad), InputSettings.pad_label(pad))
	elif event is InputEventJoypadMotion:
		if want != "pad":
			_show_toast("这一格是键盘位，请按键盘按键")
		elif absf(event.axis_value) < InputSettings.CAPTURE_AXIS_ENGAGE:
			return
		else:
			var pad := {"type": "axis", "axis": int(event.axis),
				"value": -1.0 if float(event.axis_value) < 0.0 else 1.0}
			_apply_bind(InputSettings.bind_pad(group, f, pad), InputSettings.pad_label(pad))
	else:
		return
	get_viewport().set_input_as_handled()

func _apply_bind(res: Dictionary, label: String) -> void:
	if bool(res.get("ok", false)):
		capture_target = {}
		_sync_nav()
		_ui_click()
		_show_toast("已绑定 %s" % label)
		return
	var conflict := String(res.get("conflict", ""))
	if conflict.is_empty():
		_show_toast("改绑失败：%s" % label)
	else:
		# 冲突时保持捕获状态，可以直接再按一个键。
		_show_toast("%s 已被「%s」占用" % [label, conflict])

func _apply_clear(kind: String) -> void:
	InputSettings.clear_binding(String(capture_target.get("group", "p1")),
		String(capture_target.get("func", "bomb")), kind)
	capture_target = {}
	_sync_nav()
	_ui_click()
	_show_toast("已清除该格绑定")

func _set_slider_from_mouse(kind: String, p: Vector2) -> void:
	var r := _settings_slider_rect(kind)
	var range_v := _slider_range(kind)
	var frac := clampf((p.x - r.position.x) / r.size.x, 0.0, 1.0)
	var value := lerpf(range_v.x, range_v.y, frac)
	match kind:
		"deadzone":
			# 拖动期间只改内存值，松手才落盘（每帧写文件没必要）
			InputSettings.set_deadzone(value, false)
		"sfx":
			sfx_level = value
			if audio != null:
				audio.call("set_sfx_level", value)
		_:
			music_level = value
			if audio != null:
				audio.call("set_music_level", value)

func _commit_slider(kind: String) -> void:
	match kind:
		"deadzone":
			InputSettings.set_deadzone(InputSettings.deadzone())
		"sfx":
			InputSettings.set_audio_value("sfx", sfx_level)
		"music":
			InputSettings.set_audio_value("music", music_level)

# ---------------- 手柄 / 键盘导航：焦点状态机 ----------------
#
# 焦点域（domain）："menu_mode"（模式页）| "menu_chars"（角色页）| "settings:audio|pad|keys"。
# 每个域各自记住一个焦点项 key；跨页签、进出设置面板后回到原处。
# 焦点项 key 命名：replay / settings / mode:i / card:i / ptab:i / back / cta /
#                  tab:i / pad_seg:s:i / pad_dev:s:prev|box|next / slider:kind /
#                  rumble / ktab:i / kprof:i / cell:i:key|pad / keys_reset。
# 方向键在域内做「空间导航」（同向候选按 距离 + 1.6×横向偏移 打分），
# 没有同向候选时只在垂直/水平重叠的同一行/列里回绕。

func open_pause_settings() -> void:
	settings_only = true
	_started = false
	visible = true
	move_to_front()
	_open_settings()
	_sync_nav()

func _open_settings() -> void:
	settings_open = true
	if _is_versus_lobby():
		versus_lobby.visible = false
	capture_target = {}
	if audio != null:
		sfx_level = float(audio.get("sfx_level"))
		music_level = float(audio.get("music_level"))
	nav_mode = true
	# 关闭面板后焦点回到齿轮
	nav_focus["menu_mode"] = "settings"
	nav_focus["menu_chars"] = "settings"

func _focus_domain() -> String:
	if settings_open:
		return "settings:" + settings_tab
	return "menu_chars" if step == "chars" else "menu_mode"

func _focus_default_key(domain: String) -> String:
	if domain.begins_with("settings:"):
		for i in SETTINGS_TABS.size():
			if String(SETTINGS_TABS[i]["id"]) == settings_tab:
				return "tab:%d" % i
		return "tab:0"
	return "card:%d" % int(char_index[player]) if domain == "menu_chars" else "mode:%d" % mode_index

func _focus_key() -> String:
	var domain := _focus_domain()
	if not nav_focus.has(domain):
		nav_focus[domain] = _focus_default_key(domain)
	return String(nav_focus[domain])

## 当前域里全部可聚焦控件（key + 屏幕矩形）：导航与焦点环共用这一份。
func _focus_items() -> Array:
	var out: Array = []
	if settings_open:
		for i in SETTINGS_TABS.size():
			out.append({"key": "tab:%d" % i, "rect": _settings_tab_rect(i)})
		match settings_tab:
			"pad":
				for s in 2:
					for i in InputSettings.MODES.size():
						out.append({"key": "pad_seg:%d:%d" % [s, i], "rect": _pad_seg_rect(s, i)})
					out.append({"key": "pad_dev:%d:prev" % s, "rect": _pad_dev_rect(s, "prev")})
					out.append({"key": "pad_dev:%d:box" % s, "rect": _pad_dev_rect(s, "box")})
					out.append({"key": "pad_dev:%d:next" % s, "rect": _pad_dev_rect(s, "next")})
				out.append({"key": "slider:deadzone", "rect": _settings_slider_hit("deadzone")})
				out.append({"key": "rumble", "rect": _pad_rumble_rect()})
			"keys":
				for i in 2:
					out.append({"key": "ktab:%d" % i, "rect": _keys_player_rect(i)})
				if keys_player == 0:
					for i in 2:
						out.append({"key": "kprof:%d" % i, "rect": _keys_profile_rect(i)})
				for i in InputSettings.FUNCS.size():
					out.append({"key": "cell:%d:key" % i, "rect": _keys_zone_rect(i, "key")})
					if InputSettings.PAD_GROUPS.has(_keys_group()):
						out.append({"key": "cell:%d:pad" % i, "rect": _keys_zone_rect(i, "pad")})
				out.append({"key": "keys_reset", "rect": _keys_reset_rect()})
			_:
				out.append({"key": "slider:sfx", "rect": _settings_slider_hit("sfx")})
				out.append({"key": "slider:music", "rect": _settings_slider_hit("music")})
				out.append({"key": "fullscreen", "rect": _fullscreen_rect()})
		out.append({"key": "done", "rect": _settings_done_rect()})
		return out
	out.append({"key": "replay", "rect": _replay_rect()})
	out.append({"key": "settings", "rect": _settings_rect()})
	if step == "mode":
		var cards := _mode_rects()
		for i in cards.size():
			out.append({"key": "mode:%d" % i, "rect": cards[i]})
	else:
		var tabs := _tab_rects()
		for i in tabs.size():
			out.append({"key": "ptab:%d" % i, "rect": tabs[i]})
		var tiles := _char_rects()
		for i in tiles.size():
			out.append({"key": "card:%d" % i, "rect": tiles[i]})
		out.append({"key": "back",
			"rect": Rect2(BACK_BTN["x"], BACK_BTN["y"], BACK_BTN["w"], BACK_BTN["h"])})
	out.append({"key": "cta", "rect": _cta_rect()})
	return out

func _focus_index(items: Array) -> int:
	var key := _focus_key()
	for i in items.size():
		if String(items[i]["key"]) == key:
			return i
	return 0

## 只在测试/取证时用：当前焦点项的 key 与矩形。
func focus_state() -> Dictionary:
	var items := _focus_items()
	if items.is_empty():
		return {"domain": _focus_domain(), "key": "", "rect": Rect2()}
	var i := _focus_index(items)
	return {"domain": _focus_domain(), "key": String(items[i]["key"]),
		"rect": items[i]["rect"], "nav_mode": nav_mode, "count": items.size()}

func _sync_nav() -> void:
	var nav := InputSettings.poll_nav()
	nav_accept_prev = bool(nav["accept"])
	nav_cancel_prev = bool(nav["cancel"])
	nav_release_required = nav.values().has(true)
	nav_dir = ""
	nav_timer = 0.0

func _close_settings() -> void:
	if nav_pending_slider != "":
		_commit_slider(nav_pending_slider)
		nav_pending_slider = ""
	if drag_slider != "":
		_commit_slider(drag_slider)
		drag_slider = ""
	settings_open = false
	capture_target = {}
	_sync_nav()
	if settings_only:
		settings_only = false
		_started = true
		visible = false
		settings_closed.emit()
		return
	if _is_versus_lobby():
		versus_lobby.model.refresh_routes()
		versus_lobby.prime_inputs()

func _process_nav(delta: float) -> void:
	if _is_versus_lobby() and not settings_open:
		return  # This screen routes each player's input separately.
	if not capture_target.is_empty():
		# 捕获中：导航整体让位，否则「按一下你要的键」会被焦点移动吃掉
		_sync_nav()
		return
	var nav := InputSettings.poll_nav()
	if nav_release_required:
		if nav.values().has(true):
			return
		nav_release_required = false
		nav_accept_prev = false
		nav_cancel_prev = false
	var dir := ""
	if bool(nav["up"]):
		dir = "up"
	elif bool(nav["down"]):
		dir = "down"
	elif bool(nav["left"]):
		dir = "left"
	elif bool(nav["right"]):
		dir = "right"
	if dir.is_empty():
		nav_dir = ""
		nav_timer = 0.0
		if nav_pending_slider != "":
			_commit_slider(nav_pending_slider)
			nav_pending_slider = ""
	elif dir != nav_dir:
		# 刚按下（或换方向）：立刻走一格，然后进入首次重复延迟
		nav_dir = dir
		nav_timer = NAV_FIRST_DELAY
		_nav_move(dir)
	else:
		nav_timer -= delta
		if nav_timer <= 0.0:
			nav_timer = NAV_REPEAT_DELAY
			_nav_move(dir)
	var acc := bool(nav["accept"])
	if acc and not nav_accept_prev:
		_nav_accept()
	nav_accept_prev = acc
	var can := bool(nav["cancel"])
	if can and not nav_cancel_prev:
		_nav_cancel()
	nav_cancel_prev = can

func _nav_move(dir: String) -> void:
	nav_mode = true
	var items := _focus_items()
	if items.is_empty():
		return
	var key := _focus_key()
	if key.begins_with("slider:") and (dir == "left" or dir == "right"):
		_nav_adjust_slider(key.substr(7), -1.0 if dir == "left" else 1.0)
		return
	if nav_pending_slider != "":
		_commit_slider(nav_pending_slider)
		nav_pending_slider = ""
	var cur := _focus_index(items)
	var from: Rect2 = items[cur]["rect"]
	var fc := from.get_center()
	var best := -1
	var best_score := INF
	var wrap := -1
	var wrap_along := INF
	for i in items.size():
		if i == cur:
			continue
		var r: Rect2 = items[i]["rect"]
		var c := r.get_center() - fc
		var along := 0.0
		var across := 0.0
		var same_band := false
		match dir:
			"up":
				along = -c.y
				across = absf(c.x)
			"down":
				along = c.y
				across = absf(c.x)
			"left":
				along = -c.x
				across = absf(c.y)
			_:
				along = c.x
				across = absf(c.y)
		if dir == "left" or dir == "right":
			# 同一行：纵向有重叠
			same_band = r.position.y < from.position.y + from.size.y \
				and r.position.y + r.size.y > from.position.y
		else:
			# 同一列：横向有重叠
			same_band = r.position.x < from.position.x + from.size.x \
				and r.position.x + r.size.x > from.position.x
		if along > 8.0:
			var score := along + across * 1.6
			if score < best_score:
				best_score = score
				best = i
		elif same_band and along < wrap_along:
			# 同一行 / 同一列里的反方向项：作为回绕候选
			wrap_along = along
			wrap = i
	if best < 0:
		best = wrap
	if best < 0:
		return
	nav_focus[_focus_domain()] = String(items[best]["key"])
	_on_focus_changed(String(items[best]["key"]))
	if audio != null:
		audio.play_sfx("ui_move")

## 焦点落到某项时同步它代表的状态（方向键即选中，保持原键盘手感）。
func _on_focus_changed(key: String) -> void:
	if settings_open:
		return
	if key.begins_with("mode:"):
		var i := int(key.substr(5))
		if i >= 0 and i < MODES.size() and mode_index != i:
			mode_index = i
			switch_t = 0.0
	elif key.begins_with("card:"):
		var i := int(key.substr(5))
		if i >= 0 and i < Cfg.CHAR_IDS.size():
			_select_char(i)
	elif key.begins_with("ptab:"):
		var i := int(key.substr(5))
		if i >= 0 and i < _tab_rects().size():
			player = i
			switch_t = 0.0

func _nav_adjust_slider(kind: String, sign: float) -> void:
	match kind:
		"deadzone":
			InputSettings.set_deadzone(InputSettings.deadzone() + sign * 0.05, false)
			_show_toast("摇杆死区 %.2f" % InputSettings.deadzone())
		"sfx":
			sfx_level = clampf(sfx_level + sign * 0.05, 0.0, 1.0)
			if audio != null:
				audio.call("set_sfx_level", sfx_level)
		"music":
			music_level = clampf(music_level + sign * 0.05, 0.0, 1.0)
			if audio != null:
				audio.call("set_music_level", music_level)
	# 松手（方向键全部弹起）时才落盘，避免连按时每帧写文件
	nav_pending_slider = kind

func _nav_accept() -> void:
	nav_mode = true
	var key := _focus_key()
	if settings_open:
		_nav_accept_settings(key)
		return
	if key == "replay":
		replay_requested.emit()
	elif key == "settings":
		_ui_click()
		_open_settings()
	elif step == "mode":
		if key == "cta" or key.begins_with("mode:"):
			_ui_click()
			_open_character()
	elif key.begins_with("ptab:"):
		player = int(key.substr(5))
		switch_t = 0.0
		_ui_click()
	elif key == "back":
		_ui_click()
		_back_to_mode()
	elif key == "cta" or key.begins_with("card:"):
		_ui_click()
		_confirm()

func _nav_accept_settings(key: String) -> void:
	var parts := key.split(":")
	if key == "done":
		_close_settings()
	elif key == "fullscreen":
		InputSettings.set_fullscreen(not InputSettings.fullscreen_enabled())
		_ui_click()
	elif key.begins_with("tab:"):
		var i := int(parts[1])
		if i >= 0 and i < SETTINGS_TABS.size():
			settings_tab = String(SETTINGS_TABS[i]["id"])
			capture_target = {}
		_ui_click()
	elif key.begins_with("pad_seg:"):
		var s := int(parts[1])
		var i := int(parts[2])
		if i >= 0 and i < InputSettings.MODES.size():
			var slot := "p1" if s == 0 else "p2"
			var m := String(InputSettings.MODES[i])
			InputSettings.set_device_mode(slot, m)
			_ui_click()
			_show_toast("%s 操作方式：%s" % [slot.to_upper(), String(InputSettings.MODE_LABELS[m])])
	elif key.begins_with("pad_dev:"):
		var slot := "p1" if int(parts[1]) == 0 else "p2"
		_cycle_device(slot, -1 if String(parts[2]) == "prev" else 1)
	elif key == "rumble":
		var on := not InputSettings.rumble_enabled()
		InputSettings.set_rumble(on)
		_ui_click()
		_show_toast("震动反馈：%s" % ("开" if on else "关"))
	elif key == "keys_reset":
		InputSettings.reset_defaults()
		_ui_click()
		_show_toast("已恢复默认键位")
	elif key.begins_with("ktab:"):
		keys_player = int(parts[1])
		if keys_player == 1:
			keys_profile = "main"
		_ui_click()
	elif key.begins_with("kprof:"):
		keys_profile = "main" if int(parts[1]) == 0 else "alt"
		_ui_click()
	elif key.begins_with("cell:"):
		var i := int(parts[1])
		var kind := String(parts[2])
		var group := _keys_group()
		if kind == "pad" and not InputSettings.PAD_GROUPS.has(group):
			_show_toast("备用键位只支持键盘")
			return
		if i >= 0 and i < InputSettings.FUNCS.size():
			capture_target = {"group": group, "func": String(InputSettings.FUNCS[i]),
				"kind": kind, "index": i}
			_ui_click()

func _nav_cancel() -> void:
	nav_mode = true
	if settings_open:
		_close_settings()
		return
	if step == "chars":
		_back_to_mode()

## 焦点环：墨线内圈 + 呼吸色外圈（沿用 Motion UI 的硬边风格，不引入新风格）。
func _draw_focus_ring() -> void:
	if not nav_mode:
		return
	var items := _focus_items()
	if items.is_empty():
		return
	var r: Rect2 = items[_focus_index(items)]["rect"]
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var col := UIDraw.CYAN if settings_open else UIDraw.YELLOW
	col.a = 0.68 + 0.32 * (0.5 + 0.5 * sin(pulse * 7.0))
	UIDraw.stroke_rr(self, r.position.x - 3.0, r.position.y - 3.0,
		r.size.x + 6.0, r.size.y + 6.0, 6.0, UIDraw.INK, 3.0)
	UIDraw.stroke_rr(self, r.position.x - 6.0, r.position.y - 6.0,
		r.size.x + 12.0, r.size.y + 12.0, 8.0, col, 2.0)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_versus_lobby() and not settings_open:
		return
	if not capture_target.is_empty():
		_handle_capture_event(event)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	# 方向与确认交给 _process_nav 里的导航状态机（键盘 / 手柄同一套 + 限速重复），
	# 这里只保留「快捷键」：Esc 返回、M 静音、1/2 切玩家。
	if settings_open:
		if key == KEY_ESCAPE:
			_close_settings()
			nav_mode = true
			get_viewport().set_input_as_handled()
		return
	if key == KEY_ESCAPE:
		if step == "chars":
			_back_to_mode()
			nav_mode = true
		return
	if key == KEY_M:
		mute_toggled.emit()
		return
	if step == "chars":
		if key == KEY_1:
			player = 0
			switch_t = 0.0
		elif key == KEY_2 and int(_mode()["players"]) == 2:
			player = 1
			switch_t = 0.0

func _open_character() -> void:
	if _mode()["id"] == "lan":
		lan_requested.emit()
		return
	step = "chars"
	step_t = 0.0
	switch_t = 0.0
	player = 0
	nav_focus["menu_chars"] = "card:%d" % int(char_index[player])
	if _is_versus_lobby():
		versus_lobby.open(char_index.duplicate())

func _back_to_mode() -> void:
	versus_lobby.close()
	step = "mode"
	step_t = 0.0
	switch_t = 0.0
	_sync_nav()

func _select_char(idx: int) -> void:
	if _is_versus_lobby():
		versus_lobby.model.select_character(player, idx)
		return
	char_index[player] = idx
	switch_t = 0.0

func _confirm() -> void:
	if _started:
		return
	if step == "mode":
		_open_character()
		return
	if _is_versus_lobby():
		versus_lobby.request_start()
		return
	_started = true
	start_requested.emit(String(_mode()["id"]), _char(0), _char(1))

# ---------------- 绘制 ----------------

func _draw() -> void:
	if settings_only:
		_draw_settings()
		_draw_focus_ring()
		_draw_toast()
		return
	_draw_background()
	if _is_versus_lobby():
		if settings_open:
			_draw_settings()
			_draw_focus_ring()
		_draw_toast()
		return
	if step == "mode":
		_draw_header_mode()
		_draw_mode_section()
		_draw_mode_cards()
	else:
		_draw_char_header()
		_draw_player_tabs()
		_draw_poster()
		_draw_char_tiles()
		_draw_back()
	_draw_replay()
	_draw_settings_button()
	_draw_cta()
	_draw_footer()
	if settings_open:
		_draw_settings()
	_draw_focus_ring()
	_draw_toast()

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, Cfg.VIEW_W, Cfg.VIEW_H), UIDraw.PAPER, true, -1.0, true)
	if wallpaper != null:
		draw_texture_rect(wallpaper, Rect2(0, 0, Cfg.VIEW_W, Cfg.VIEW_H), false, Color(1, 1, 1, 0.07))
	UIDraw.dots(self, 0, 0, Cfg.VIEW_W, Cfg.VIEW_H, UIDraw.INK, 0.07, 16)
	var bars := [UIDraw.ORANGE, UIDraw.CYAN, UIDraw.YELLOW, UIDraw.PINK, UIDraw.GREEN, UIDraw.INK]
	var bh := Cfg.VIEW_H / bars.size()
	for i in bars.size():
		draw_rect(Rect2(0, i * bh, 4, bh), bars[i], true, -1.0, true)
		draw_rect(Rect2(Cfg.VIEW_W - 4, Cfg.VIEW_H - (i + 1) * bh, 4, bh), bars[i], true, -1.0, true)
	if step == "mode":
		UIDraw.text(self, "BOMBIT", Cfg.VIEW_W * 0.5, 438, {
			"size": 112, "weight": 900, "family": "impact",
			"fill": Color(0, 0, 0, 0), "stroke": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.055),
			"strokeWidth": 2, "align": "center",
		})
		UIDraw.sun(self, 606, 112, 89, UIDraw.ORANGE, t * 0.025)
		UIDraw.bomb(self, 610, 111, 31, -0.12)
	else:
		UIDraw.text(self, "SPIRIT", 492, 390, {
			"size": 128, "weight": 900, "family": "impact",
			"fill": Color(0, 0, 0, 0), "stroke": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.04),
			"strokeWidth": 2, "align": "center",
		})
	var stars := [
		[512.0, 48.0, 7.0, UIDraw.YELLOW, 0.2],
		[690.0, 172.0, 5.0, UIDraw.CREAM, 0.6],
		[490.0, 180.0, 4.0, UIDraw.PINK, 0.8],
		[268.0, 164.0, 3.0, UIDraw.CYAN, 1.2],
		[684.0, 620.0, 5.0, UIDraw.CYAN, 0.4],
	]
	for o in stars:
		var bob := sin(t * 2.2 + float(o[4]) * 4.0) * 4.0
		UIDraw.star(self, o[0], o[1] + bob, o[2], float(o[2]) * 0.45, o[3], 5, t * 0.4)
	for l in 5:
		draw_line(Vector2(440 + l * 64, 0), Vector2(300 + l * 64, 210),
			Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.12), 1.0, true)

func _draw_header_mode() -> void:
	draw_rect(Rect2(0, 0, Cfg.VIEW_W, 18), UIDraw.INK, true, -1.0, true)
	UIDraw.text(self, "BOMBIT®  /  Q-BAN BUBBLE HALL", 13, 9,
		{"size": 11, "family": "mono", "weight": 700, "fill": UIDraw.CREAM, "alpha": 0.82})
	UIDraw.text(self, "MOTION UI  /  2026", Cfg.VIEW_W - 13, 9,
		{"size": 11, "family": "mono", "weight": 700, "fill": UIDraw.CREAM, "alpha": 0.55, "align": "right"})
	draw_rect(Rect2(26, 35, 7, 7), UIDraw.ORANGE, true, -1.0, true)
	UIDraw.text(self, "GAME MOTION ID / 006", 40, 39,
		{"size": 11, "family": "mono", "weight": 700, "fill": UIDraw.INK, "alpha": 0.64})
	UIDraw.tag(self, "Q版", 26, 61, {"size": 11, "weight": 900, "family": "cn",
		"fill": UIDraw.INK, "fg": UIDraw.CREAM, "padX": 7, "h": 18, "align": "left",
		"rot": -0.035, "stroke": null, "shadow": UIDraw.ORANGE, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "泡泡堂", 24, 105, {"size": 56, "weight": 900, "family": "cn",
		"fill": UIDraw.INK, "shadow": UIDraw.ORANGE, "shadowX": 4, "shadowY": 4})
	UIDraw.text(self, "BOMBIT", 26, 151, {"size": 44, "weight": 900, "family": "impact",
		"fill": UIDraw.ORANGE, "stroke": UIDraw.INK, "strokeWidth": 1.7,
		"shadow": UIDraw.INK, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "精灵冒险  ×  同屏 / 局域网对战", 268, 85,
		{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.INK})
	UIDraw.text(self, "6 SPIRITS  /  4 MODES  /  1 FUSE", 268, 101,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.62})
	var scenes := [["晨露森林", UIDraw.GREEN], ["星汽工厂", UIDraw.CYAN], ["星糖游乐园", UIDraw.PINK]]
	var sx := 268.0
	for sc in scenes:
		draw_rect(Rect2(sx, 119, 4, 4), sc[1], true, -1.0, true)
		UIDraw.text(self, sc[0], sx + 8, 122,
			{"size": 11, "weight": 500, "family": "cn", "fill": UIDraw.INK, "alpha": 0.78})
		sx += UIDraw.measure(sc[0], 11, 500, "cn") + 20
	UIDraw.text(self, "SELECT MODE  /  选择模式", 268, 141,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.48})
	draw_line(Vector2(26, 175), Vector2(694, 175), Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.24), 1.0, true)

func _draw_mode_section() -> void:
	UIDraw.tag(self, "STEP 01", MODE_CARD["x"], 198, {"size": 11, "family": "mono",
		"fill": UIDraw.INK, "fg": UIDraw.CREAM, "padX": 7, "h": 17, "align": "left", "stroke": null})
	UIDraw.text(self, "选择模式", MODE_CARD["x"] + 72, 203,
		{"size": 16, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	UIDraw.text(self, "选好玩法后确认", MODE_CARD["x"] + 146, 202,
		{"size": 11, "weight": 500, "family": "cn", "fill": UIDraw.INK, "alpha": 0.52})
	UIDraw.text(self, "MODE SELECT  /  4", Cfg.VIEW_W - MODE_CARD["x"], 208,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.45, "align": "right"})
	draw_line(Vector2(MODE_CARD["x"], 216), Vector2(Cfg.VIEW_W - MODE_CARD["x"], 216),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16), 1.0, true)

func _draw_mode_cards() -> void:
	var rects := _mode_rects()
	for i in MODES.size():
		_draw_mode_card(i, rects[i])

func _draw_mode_card(idx: int, rect: Rect2) -> void:
	_draw_compact_mode(idx, rect)

func _draw_compact_mode(idx: int, rect: Rect2) -> void:
	var data: Dictionary = MODES[idx]
	var selected := idx == mode_index
	var hovered: bool = hover.get("kind", "") == "mode" and int(hover.get("index", -1)) == idx
	var x := rect.position.x
	var y: float = rect.position.y - (3 if hovered else 0) + (sin(pulse * 2.5) if selected else 0)
	var fg := UIDraw.CREAM if selected else UIDraw.INK
	UIDraw.panel(self, x, y, rect.size.x, rect.size.y, {"fill": UIDraw.INK if selected else data["soft"],
		"stroke": UIDraw.INK, "lw": 2.5, "r": 4, "shadow": data["color"] if selected else UIDraw.INK, "shadowX": 4, "shadowY": 4})
	draw_rect(Rect2(x, y, rect.size.x, 5), data["color"])
	UIDraw.text(self, data["no"], x + 14, y + 35, {"size": 38, "family": "impact", "fill": data["color"] if selected else UIDraw.INK})
	UIDraw.text(self, data["label"], x + 72, y + 34, {"size": 20, "fill": fg})
	UIDraw.text(self, data["tagline"], x + 15, y + 70, {"size": 11, "weight": 500, "fill": fg})
	UIDraw.wrap(self, data["desc"], x + 15, y + 94, 235, 12, 17, Color(fg, 0.75), 2)
	UIDraw.text(self, data["abbr"] + (" / SELECTED" if selected else " / ENTER"), x + 15, y + 132,
		{"size": 11, "family": "mono", "fill": data["color"] if selected else UIDraw.INK})
	var center := Vector2(x + 290, y + 105)
	_draw_mode_motif(data, center.x, center.y, 44, selected, 0.55)

func _draw_mode_motif(mode: Dictionary, cx: float, cy: float, r: float, selected: bool, scale_factor: float = 1) -> void:
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE * scale_factor)
	draw_circle(Vector2.ZERO, r, mode["color"] if selected else UIDraw.CREAM, true, -1.0, true)
	draw_arc(Vector2.ZERO, r, 0, TAU, 48, UIDraw.INK, 2.0, true)
	UIDraw.dots(self, -r, -r, r * 2, r * 2, UIDraw.INK if selected else mode["color"], 0.08, 10)
	match String(mode["motif"]):
		"network":
			for side in [-1, 1]:
				draw_rect(Rect2(side * 22 - 12, -18, 24, 20), UIDraw.INK)
				draw_rect(Rect2(side * 22 - 9, -15, 18, 14), UIDraw.CYAN if side < 0 else UIDraw.PINK)
				draw_line(Vector2(side * 22, 4), Vector2(side * 22, 16), UIDraw.INK, 3, true)
			draw_line(Vector2(-22, 16), Vector2(22, 16), UIDraw.INK, 3, true)
			draw_circle(Vector2(sin(t * 2) * 17, 16), 4, UIDraw.ORANGE, true, -1, true)
		"clock":
			draw_circle(Vector2.ZERO, 42, UIDraw.CREAM, true, -1.0, true)
			draw_arc(Vector2.ZERO, 42, 0, TAU, 48, UIDraw.INK, 3.0, true)
			for i in 12:
				var a := i * PI / 6.0
				draw_line(Vector2(cos(a) * 34, sin(a) * 34), Vector2(cos(a) * 39, sin(a) * 39),
					UIDraw.INK, 2.0, true)
			draw_line(Vector2.ZERO, Vector2(0, -24), UIDraw.INK, 4.0, true)
			draw_line(Vector2.ZERO, Vector2(18, 10), UIDraw.INK, 4.0, true)
			draw_circle(Vector2.ZERO, 6, UIDraw.ORANGE, true, -1.0, true)
		"versus":
			UIDraw.star(self, -21, -5, 28, 12, UIDraw.CYAN, 5, 0.3)
			UIDraw.star(self, 21, -5, 28, 12, UIDraw.PINK, 5, -0.25)
			UIDraw.text(self, "VS", 0, 30, {"size": 26, "weight": 900, "family": "impact",
				"fill": UIDraw.INK, "stroke": UIDraw.CREAM, "strokeWidth": 2, "align": "center"})
		_:
			var cell := 22.0
			var ox := -33.0
			var oy := -33.0
			for p in [[0, 0], [2, 0], [1, 1], [0, 2], [2, 2]]:
				draw_rect(Rect2(ox + p[0] * cell, oy + p[1] * cell, cell - 3, cell - 3), UIDraw.INK, true, -1.0, true)
			draw_polyline(PackedVector2Array([
				Vector2(ox + 11, oy + 11), Vector2(ox + 11, oy + 55), Vector2(ox + 55, oy + 55),
			]), UIDraw.CREAM, 3.0, true)
			# menu.js:906 —— U.bomb 在 ctx.translate(cx, cy) 之内，落点是母题局部 (26, 24)；
			# UIDraw.bomb 自带 draw_set_transform（替换而非叠加），所以这里要传绝对坐标。
			UIDraw.bomb(self, cx + 26.0 * scale_factor, cy + 24.0 * scale_factor, 12 * scale_factor, 0.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_char_header() -> void:
	draw_rect(Rect2(0, 0, Cfg.VIEW_W, 18), UIDraw.INK, true, -1.0, true)
	UIDraw.text(self, "BOMBIT®  /  SPIRIT SELECT", 13, 9,
		{"size": 11, "family": "mono", "weight": 700, "fill": UIDraw.CREAM, "alpha": 0.82})
	UIDraw.text(self, "MOTION UI  /  2026", Cfg.VIEW_W - 13, 9,
		{"size": 11, "family": "mono", "weight": 700, "fill": UIDraw.CREAM, "alpha": 0.55, "align": "right"})
	UIDraw.text(self, "STEP 02 / SPIRIT SELECT", 24, 33,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CYAN})
	UIDraw.text(self, "选择精灵", 22, 61, {"size": 28, "weight": 900, "family": "cn",
		"fill": UIDraw.INK, "shadow": UIDraw.ORANGE, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "CHOOSE YOUR SPIRIT  /  6 AVAILABLE", 25, 85,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.48})
	draw_line(Vector2(294, 32), Vector2(294, 90), Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.18), 1.0, true)
	var mode := _mode()
	UIDraw.tag(self, mode["label"], 310, 44, {"size": 11, "family": "cn", "fill": mode["color"],
		"fg": UIDraw.INK, "padX": 7, "h": 16, "align": "left", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.text(self, "MODE " + String(mode["no"]) + " / " + String(mode["abbr"]), 310, 66,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.48})
	var cid := _char(player)
	UIDraw.text(self, ("2P" if player == 1 else "1P") + " 正在选择  /  " + Cfg.char_cfg(cid)["name"],
		310, 84, {"size": 11, "weight": 700, "family": "cn", "fill": _player_color()})
	draw_line(Vector2(20, 92), Vector2(700, 92), Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.22), 1.0, true)

func _draw_player_tabs() -> void:
	var tabs := _tab_rects()
	if int(_mode()["players"]) == 1:
		var tr: Rect2 = tabs[0]
		UIDraw.panel(self, tr.position.x, tr.position.y, tr.size.x, tr.size.y, {
			"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
			"shadow": UIDraw.CYAN, "shadowX": 3, "shadowY": 3})
		draw_rect(Rect2(tr.position.x, tr.position.y, 5, tr.size.y), UIDraw.CYAN, true, -1.0, true)
		UIDraw.text(self, "1P", tr.position.x + 16, tr.position.y + 14,
			{"size": 11, "weight": 900, "family": "impact", "fill": UIDraw.INK})
		UIDraw.text(self, "单人选择", tr.position.x + 38, tr.position.y + 14,
			{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.INK})
		UIDraw.text(self, "6 SPIRITS", tr.position.x + tr.size.x - 10, tr.position.y + 14,
			{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.45, "align": "right"})
		return
	for i in tabs.size():
		var tr: Rect2 = tabs[i]
		var active := player == i
		var pc := UIDraw.PINK if i == 1 else UIDraw.CYAN
		var cid := _char(i)
		UIDraw.panel(self, tr.position.x, tr.position.y, tr.size.x, tr.size.y, {
			"fill": UIDraw.INK if active else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
			"shadow": pc if active else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16),
			"shadowX": 4 if active else 2, "shadowY": 4 if active else 2})
		draw_rect(Rect2(tr.position.x, tr.position.y, 5, tr.size.y), pc, true, -1.0, true)
		UIDraw.text(self, "2P" if i == 1 else "1P", tr.position.x + 15, tr.position.y + 14,
			{"size": 11, "weight": 900, "family": "impact", "fill": pc if active else UIDraw.INK})
		UIDraw.text(self, Cfg.char_cfg(cid)["name"], tr.position.x + 38, tr.position.y + 14,
			{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.CREAM if active else UIDraw.INK})
		if active:
			UIDraw.text(self, "选择中", tr.position.x + tr.size.x - 10, tr.position.y + 14,
				{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.YELLOW, "align": "right"})

func _draw_poster() -> void:
	var cid := _char(player)
	var v := _char_visual(cid)
	var data := Cfg.skill_cfg(cid)
	var cfg := Cfg.char_cfg(cid)
	var idx := int(char_index[player])
	var x := float(POSTER["x"])
	var y := float(POSTER["y"])
	var w := float(POSTER["w"])
	var h := float(POSTER["h"])
	var pc := _player_color()
	var tex: Texture2D = char_tex.get(cid)
	var enter := ease_out(minf(1.0, step_t * 3.0))
	var swap := ease_out(minf(1.0, switch_t * 4.5))
	var disk_x := x + 520
	var disk_y := y + 170
	var bottom := y + 282 + sin(t * 2.2) * 3.0
	var shift := Vector2((1.0 - enter) * -22, (1.0 - enter) * 12)

	draw_set_transform(shift, 0.0, Vector2.ONE)
	UIDraw.panel(self, x, y, w, h, {
		"fill": UIDraw.INK, "stroke": UIDraw.INK, "lw": 3, "r": 5,
		"shadow": v["color"], "shadowX": 9, "shadowY": 9})
	# menu.js:1106-1107 —— D.roundRect(x, y, w, h, 5) + ctx.clip()：
	# 放射线半径 184 > 海报内边距，原作被裁到海报圆角矩形内，这里求交后再填充。
	var clip_poly := UIDraw.rr_points(x, y, w, h, 5)
	var clip_local := PackedVector2Array()
	var disk_rotation := t * 0.055
	for cp in clip_poly:
		clip_local.append((cp - Vector2(disk_x, disk_y)).rotated(-disk_rotation))
	draw_set_transform(shift + Vector2(disk_x, disk_y), disk_rotation, Vector2.ONE)
	for ray in 22:
		var ra := ray * TAU / 22.0
		var dir := Vector2(cos(ra), sin(ra))
		var perp := Vector2(-dir.y, dir.x)
		_fill_clipped(PackedVector2Array([
			dir * 124.0, dir * 184.0 + perp * 9.0, dir * 184.0 - perp * 9.0,
		]), clip_local, v["color"])
	draw_set_transform(shift, 0.0, Vector2.ONE)
	draw_circle(Vector2(disk_x, disk_y), 118, UIDraw.CREAM, true, -1.0, true)
	draw_arc(Vector2(disk_x, disk_y), 128, 0, TAU, 64, v["color"], 13.0, true)
	draw_arc(Vector2(disk_x, disk_y), 136, 0, TAU, 64, UIDraw.INK, 2.0, true)
	draw_arc(Vector2(disk_x, disk_y), 118, 0, TAU, 64, UIDraw.INK, 2.0, true)
	UIDraw.dots(self, x, y, w, h, UIDraw.CREAM, 0.045, 12)
	for l in 7:
		draw_line(Vector2(x + 10, y + 70 + l * 21), Vector2(x + 54 + l * 9, y + 52 + l * 21),
			Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.16), 2.0, true)
	UIDraw.text(self, pad2(idx + 1), x + w - 22, y + 102, {"size": 112, "weight": 900,
		"family": "impact", "fill": Color(0, 0, 0, 0),
		"stroke": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.12), "strokeWidth": 1.5, "align": "right"})
	# menu.js:1163-1169 —— globalAlpha .32 + ctx.ellipse(diskX, bottom + 4, 76, 11, 0, 0, TAU)
	CanvasArt.ellipse_rot_fill(self, disk_x, bottom + 4.0, 76.0, 11.0, 0.0,
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.32))
	draw_set_transform(shift + Vector2(disk_x, bottom), (1.0 - swap) * -0.06 + sin(t * 1.4) * 0.01,
		Vector2(0.9 + 0.1 * swap, 0.9 + 0.1 * swap))
	_draw_texture_fit(tex, Vector2.ZERO, 260, 266, v["color"])
	# menu.js:1099-1100 的 translate 直到 1268 才 restore：闪白 / 标签 / 文案 / 跑马灯
	# 都在同一层位移里，这里不能提前归零。
	draw_set_transform(shift, 0.0, Vector2.ONE)
	if switch_t < 0.3:
		_fill_clipped(_rect_poly(x, y, w, h), clip_poly,
			Color(245 / 255.0, 235 / 255.0, 216 / 255.0, (1.0 - switch_t / 0.3) * 0.22))

	UIDraw.tag(self, "SPIRIT " + pad2(idx + 1), x + 18, y + 20, {"size": 11, "family": "mono",
		"fill": v["color"], "fg": UIDraw.INK, "padX": 7, "h": 16, "align": "left",
		"stroke": UIDraw.INK, "lw": 1})
	UIDraw.tag(self, "2P" if player == 1 else "1P", x + w - 18, y + 20, {"size": 11, "family": "mono",
		"fill": pc, "fg": UIDraw.INK, "padX": 7, "h": 16, "align": "right", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.tag(self, String(v["role"]) + "系", x + 20, y + 45, {"size": 11, "family": "cn",
		"fill": v["accent"], "fg": UIDraw.INK, "padX": 6, "h": 14, "align": "left",
		"stroke": UIDraw.INK, "lw": 1})
	UIDraw.text(self, cfg["name"], x + 20, y + 84, {"size": 40, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM, "shadow": v["color"], "shadowX": 3, "shadowY": 3})
	var skill_label := ("被动 · " if bool(data.get("passive", false)) else "") + String(data["name"])
	UIDraw.text(self, skill_label, x + 22, y + 126, {"size": 14, "weight": 900, "family": "cn", "fill": v["color"]})
	draw_rect(Rect2(x + 22, y + 138, minf(UIDraw.measure(skill_label, 14, 900, "cn"), 300), 2), v["color"], true, -1.0, true)
	UIDraw.wrap(self, data["desc"], x + 22, y + 156, 300, 12, 17,
		Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.72), 2, 500, "cn")
	if bool(data.get("passive", false)):
		UIDraw.text(self, "放弹%d次或%s通灵" % [int(data["bombs_to_evolve"]), "击倒" if int(_mode()["players"]) == 2 else "击杀"],
			x + 22, y + 196, {"size": 11, "weight": 700, "family": "cn",
			"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55)})
	if cfg.has("intro"):
		UIDraw.text(self, "LORE", x + 22, y + 216, {"size": 11, "weight": 700, "family": "mono", "fill": v["accent"]})
		_draw_lore(String(cfg["intro"]), x + 66, y + 216, 260)
	var key_text := "被动"
	if not bool(data.get("passive", false)):
		# 键位跟着设置走：改绑之后海报上的技能键提示同步更新。
		var skill_group := "p2" if player == 1 else ("p1vs" if int(_mode()["players"]) == 2 else "p1")
		key_text = InputSettings.first_key_label(InputSettings.action_for(skill_group, "skill"))
		var slot := "p2" if player == 1 else "p1"
		if InputSettings.last_source(slot) == "gamepad":
			var labels := InputSettings.pad_labels(InputSettings.action_for(slot, "skill"))
			key_text = String(labels[0]) if not labels.is_empty() else "未绑定"
	var key_width := maxf(44, UIDraw.measure(key_text, 11, 700, "mono") + 12)
	UIDraw.keycap(self, key_text, x + 22, y + 240, key_width, 20, v["color"], UIDraw.INK)
	UIDraw.text(self, ("6 格通灵" if bool(data.get("passive", false)) else "冷却%s秒" % str(data["cd"])),
		x + 34 + key_width, y + 250, {"size": 11, "weight": 700, "family": "mono",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55)})
	UIDraw.text(self, "BOMBIT / CHARACTER FILE", x + 22, y + 273,
		{"size": 11, "weight": 700, "family": "mono", "fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.35)})
	var deco := [
		[x + 340, y + 46, 6.0, UIDraw.YELLOW, 0.2],
		[x + 386, y + 128, 4.0, UIDraw.CREAM, 1.1],
		[x + 348, y + 236, 4.0, v["accent"], 0.7],
		[disk_x + 74, y + 272, 5.0, UIDraw.YELLOW, 1.6],
	]
	for dd in deco:
		UIDraw.star(self, dd[0], dd[1] + sin(t * 2 + float(dd[4]) * 5) * 4, dd[2],
			float(dd[2]) * 0.45, dd[3], 5, t * 0.35)
	draw_rect(Rect2(x, y + h - 24, w, 24), v["color"], true, -1.0, true)
	# menu.js:1252-1266 —— 先 ctx.rect(x, y + h - 24, w, 24) + ctx.clip() 再画跑马灯文字
	var marquee := "BOMBIT / SPIRIT SELECT / %s / %s   " % ["2P" if player == 1 else "1P", pad2(idx + 1)]
	var stride := UIDraw.measure(marquee, 11, 700, "mono")
	var mshift := -fmod(t * 32.0, stride)
	var adv := {}
	for m in ceili(w / stride) + 2:
		_draw_text_clipped_x(marquee,
			x + mshift + m * stride, y + h - 12, x, x + w,
			{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK}, adv)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_lore(s: String, x: float, y: float, max_w: float) -> void:
	UIDraw.text(self, s, x, y, {"size": 11, "weight": 500, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.72), "max_width": max_w})

# ---------------- ctx.clip() 的等价物 ----------------

## ctx.clip() 之后填充任意多边形的等价物：与裁剪多边形求交，只画交集部分。
func _fill_clipped(poly: PackedVector2Array, clip: PackedVector2Array, color: Color) -> void:
	if poly.size() < 3 or clip.size() < 3 or color.a <= 0.0:
		return
	for piece in Geometry2D.intersect_polygons(poly, clip):
		if piece.size() >= 3:
			draw_colored_polygon(piece, color)

func _rect_poly(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h),
	])

## ctx.clip() 到一个矩形之后绘制文本的等价物：逐字判位，落在裁剪区外的字形不画。
## 整串都在裁剪区内时仍走 UIDraw.text，字距与原作完全一致。
func _draw_text_clipped_x(s: String, x: float, y: float, clip_x0: float,
		clip_x1: float, o: Dictionary, _adv: Dictionary = {}) -> void:
	if s.is_empty():
		return
	var f := UIDraw.font(String(o.get("family", "cn")), int(o.get("weight", 700)))
	if f == null:
		return
	var size := int(o.get("size", 12))
	var run_w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if x + run_w <= clip_x0 or x >= clip_x1:
		return
	if x >= clip_x0 and x + run_w <= clip_x1:
		UIDraw.text(self, s, x, y, o)
		return
	var cx := x
	var prefix_width := 0.0
	for i in s.length():
		var ch := s.substr(i, 1)
		# Summing separately rounded glyph widths makes clipped runs wider than
		# the shaped string (245px vs 212px at 11px), overlapping the next copy.
		var next_width := f.get_string_size(s.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var cw := next_width - prefix_width
		if cx + cw > clip_x0 and cx < clip_x1:
			UIDraw.text(self, ch, cx, y, o)
		cx += cw
		prefix_width = next_width
		if cx >= clip_x1:
			return

func _draw_texture_fit(tex: Texture2D, bottom_center: Vector2, max_w: float, max_h: float, fallback: Color) -> void:
	if tex == null:
		# menu.js:131-148 —— 素材未就绪时的占位小剪影（椭圆身体 + 奶油头 + 两只墨色眼）
		var ph := minf(max_h, 220.0)
		var pw := ph * 0.72
		var pcx := bottom_center.x
		var pbtm := bottom_center.y
		CanvasArt.ellipse_rot_fill(self, pcx, pbtm - ph * 0.45, pw * 0.38, ph * 0.42, 0.0, fallback)
		draw_circle(Vector2(pcx, pbtm - ph * 0.62), pw * 0.2, UIDraw.CREAM, true, -1.0, true)
		draw_circle(Vector2(pcx - pw * 0.07, pbtm - ph * 0.64), 2.2, UIDraw.INK, true, -1.0, true)
		draw_circle(Vector2(pcx + pw * 0.07, pbtm - ph * 0.64), 2.2, UIDraw.INK, true, -1.0, true)
		return
	var ts := tex.get_size()
	var s := minf(max_w / ts.x, max_h / ts.y)
	var dw := ts.x * s
	var dh := ts.y * s
	draw_texture_rect(tex, Rect2(bottom_center.x - dw * 0.5, bottom_center.y - dh, dw, dh), false)

func _draw_char_tiles() -> void:
	var rects := _char_rects()
	for i in Cfg.CHAR_IDS.size():
		_draw_char_tile(i, rects[i])

func _draw_char_tile(idx: int, rect: Rect2) -> void:
	var cid: String = Cfg.CHAR_IDS[idx]
	var v := _char_visual(cid)
	var active: bool = int(char_index[player]) == idx
	var other: bool = int(_mode()["players"]) == 2 and int(char_index[1 - player]) == idx
	var pcolor := _player_color()
	var hovered: bool = hover.get("kind", "") == "card" and int(hover.get("index", -1)) == idx
	var lift := (sin(pulse * 3 + idx * 0.4) * 1.2 if active else 0.0) + (-3.0 if hovered else 0.0)
	var x := rect.position.x
	var y := rect.position.y + lift
	var w := rect.size.x
	var h := rect.size.y
	var tex: Texture2D = char_tex.get(cid)
	if active:
		UIDraw.panel(self, x, y, w, h, {"fill": v["color"], "stroke": UIDraw.INK, "lw": 2.6, "r": 4,
			"shadow": pcolor, "shadowX": 4, "shadowY": 4})
		UIDraw.panel(self, x + 4, y + 4, w - 8, h - 28, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK,
			"lw": 1, "r": 2})
		UIDraw.tag(self, "2P" if player == 1 else "1P", x + 4, y + 4, {"size": 11, "family": "mono",
			"fill": pcolor, "fg": UIDraw.INK, "padX": 4, "h": 12, "align": "left",
			"stroke": UIDraw.INK, "lw": 1})
		UIDraw.star(self, x + w - 10, y + 11, 4, 1.8, UIDraw.YELLOW, 5, 0.2)
	else:
		UIDraw.panel(self, x, y, w, h, {"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.6, "r": 4,
			"shadow": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16), "shadowX": 2, "shadowY": 2})
		draw_rect(Rect2(x, y, w, 4), v["color"], true, -1.0, true)
	_draw_head(tex, Rect2(x + 4, y + (4 if active else 5), w - 8, h - 29), v["color"])
	var strip_y := y + h - 23
	draw_rect(Rect2(x + 2, strip_y, w - 4, 21), UIDraw.INK, true, -1.0, true)
	UIDraw.text(self, Cfg.char_cfg(cid)["name"], x + 7, strip_y + 10,
		{"size": 11, "weight": 900, "family": "cn", "fill": UIDraw.CREAM})
	UIDraw.text(self, pad2(idx + 1), x + w - 7, strip_y + 10, {"size": 11, "weight": 700,
		"family": "mono", "fill": pcolor if active else Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.55), "align": "right"})
	if other:
		UIDraw.tag(self, "1P" if 1 - player == 0 else "2P", x + w - 4, y + 12, {"size": 11, "family": "mono",
			"fill": UIDraw.CYAN if 1 - player == 0 else UIDraw.PINK, "fg": UIDraw.INK, "padX": 4,
			"h": 12, "align": "right", "stroke": UIDraw.INK, "lw": 1})
	if active:
		draw_rect(Rect2(x + 4, y + h - 4, w - 8, 3), pcolor, true, -1.0, true)

func _draw_head(tex: Texture2D, rect: Rect2, fallback: Color) -> void:
	if tex == null:
		# draw.js:404-428 U.head → sprites.js:1179-1192 drawAssetFit 未就绪时的占位小人
		var hx := rect.position.x + rect.size.x * 0.5
		var hy := rect.position.y + rect.size.y * 0.5
		var edge := Color(0, 0, 0, 0.38)
		UIDraw.fill_rr(self, hx - 13.0, hy - 4.0, 26.0, 26.0, 9.0, fallback)
		UIDraw.stroke_rr(self, hx - 13.0, hy - 4.0, 26.0, 26.0, 9.0, edge, 2.0)
		draw_circle(Vector2(hx, hy - 18.0), 17.0, fallback, true, -1.0, true)
		draw_arc(Vector2(hx, hy - 18.0), 17.0, 0.0, TAU, 48, edge, 2.0, true)
		draw_circle(Vector2(hx, hy - 18.0), 12.5, Color(1, 1, 1, 0.92), true, -1.0, true)
		CanvasArt.ellipse_rot_fill(self, hx - 5.0, hy - 19.0, 2.6, 3.4, 0.0, Color("2b2b3d"))
		CanvasArt.ellipse_rot_fill(self, hx + 5.0, hy - 19.0, 2.6, 3.4, 0.0, Color("2b2b3d"))
		return
	var ts := tex.get_size()
	var crop_h := ts.y * 0.68
	var s := minf(rect.size.x / ts.x, rect.size.y / crop_h)
	var dw := ts.x * s
	var dh := crop_h * s
	draw_texture_rect_region(tex, Rect2(rect.position.x + (rect.size.x - dw) * 0.5,
		rect.position.y + rect.size.y - dh + 2, dw, dh), Rect2(0, 0, ts.x, crop_h))

func _draw_cta() -> void:
	var mode := _mode()
	var active := step == "chars"
	var label := "进入精灵选择"
	var sub := "MODE " + String(mode["no"]) + "  →  SPIRIT SELECT"
	if mode["id"] == "lan":
		label = "进入联机大厅"
		sub = "MODE 04  →  LAN LOBBY"
	if active:
		if int(mode["players"]) == 1:
			label = "开始游戏"
			sub = "SPIRIT " + pad2(int(char_index[0]) + 1) + "  /  START"
		elif player == 0:
			label = "确认 1P"
			sub = "下一步：选择 2P 精灵"
		else:
			label = "开始对战"
			sub = "1P + 2P READY  /  START"
	var hovered: bool = hover.get("kind", "") == "cta"
	var x := (Cfg.VIEW_W - BTN["w"]) * 0.5
	var lift := sin(pulse * 3) * 1.2 + (-2.0 if hovered else 0.0)
	var y := BTN["y"] + lift
	UIDraw.panel(self, x, y, BTN["w"], BTN["h"], {"fill": UIDraw.ORANGE if hovered else UIDraw.YELLOW,
		"stroke": UIDraw.INK, "lw": 2.5, "r": 4, "shadow": UIDraw.INK, "shadowX": 5, "shadowY": 5})
	UIDraw.play(self, x + 30, y + BTN["h"] * 0.5, 13, UIDraw.INK)
	UIDraw.text(self, label, x + 48, y + BTN["h"] * 0.5 - 2, {"size": 21, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	UIDraw.text(self, sub, x + 48, y + BTN["h"] * 0.5 + 17, {"size": 11, "weight": 700, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7)})
	UIDraw.keycap(self, "ENTER", x + BTN["w"] - 80, y + 18, 56, 20, UIDraw.INK, UIDraw.CREAM)
	draw_rect(Rect2(x, y + BTN["h"] - 4, 44, 4), _player_color() if active else mode["color"], true, -1.0, true)

func _draw_back() -> void:
	var hovered: bool = hover.get("kind", "") == "back"
	UIDraw.panel(self, BACK_BTN["x"], BACK_BTN["y"], BACK_BTN["w"], BACK_BTN["h"], {
		"fill": UIDraw.INK if hovered else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
		"shadow": UIDraw.ORANGE if hovered else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16),
		"shadowX": 4 if hovered else 2, "shadowY": 4 if hovered else 2})
	UIDraw.text(self, "← 返回模式", BACK_BTN["x"] + 14, BACK_BTN["y"] + 23,
		{"size": 11, "weight": 900, "family": "cn", "fill": UIDraw.CREAM if hovered else UIDraw.INK})
	UIDraw.text(self, "ESC", BACK_BTN["x"] + 14, BACK_BTN["y"] + 41,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": UIDraw.CYAN if hovered else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.4)})

func _draw_replay() -> void:
	var r := _replay_rect()
	var hovered: bool = hover.get("kind", "") == "replay"
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.INK if hovered else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": UIDraw.ORANGE if hovered else UIDraw.INK, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "↗", r.position.x + 11, r.position.y + r.size.y * 0.5,
		{"size": 12, "weight": 900, "family": "mono", "fill": UIDraw.YELLOW if hovered else UIDraw.ORANGE})
	UIDraw.text(self, "对局回放", r.position.x + 27, r.position.y + r.size.y * 0.5 - 1,
		{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.CREAM if hovered else UIDraw.INK})

func _draw_settings_button() -> void:
	var r := _settings_rect()
	var hovered: bool = hover.get("kind", "") == "settings" and not settings_open
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.INK if hovered else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
		"shadow": UIDraw.ORANGE if hovered else UIDraw.INK, "shadowX": 2, "shadowY": 2})
	var gear := UIDraw.YELLOW if hovered else UIDraw.INK
	UIDraw.gear(self, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5, gear)
	# menu.js:1373-1376 —— 齿轮中心孔 hover 时是 ink，非 hover 才是 cream（UIDraw.gear 恒为 cream）
	if hovered:
		draw_circle(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5),
			3.1, UIDraw.INK, true, -1.0, true)

func _draw_footer() -> void:
	var hint := "← → 选择模式　·　ENTER 进入精灵选择" if step == "mode" else \
		"方向键 选择　·　ENTER 确认　·　" + ("1 / 2 切换玩家　·　" if int(_mode()["players"]) == 2 else "") + "ESC 返回"
	UIDraw.text(self, hint, Cfg.VIEW_W * 0.5, Cfg.VIEW_H - 39,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.INK, "alpha": 0.58, "align": "center"})
	for i in 22:
		var bw := 2.0 if i % 4 == 0 else 1.0
		draw_rect(Rect2(634 + i * 3, Cfg.VIEW_H - 23, bw, 11),
			Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.55), true, -1.0, true)

func _draw_settings() -> void:
	var c := SETTINGS_CARD
	draw_rect(Rect2(0, 0, Cfg.VIEW_W, Cfg.VIEW_H), Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.82), true, -1.0, true)
	UIDraw.dots(self, 0, 0, Cfg.VIEW_W, Cfg.VIEW_H, UIDraw.CREAM, 0.035, 15)
	UIDraw.panel(self, c["x"], c["y"], c["w"], c["h"], {"fill": UIDraw.CREAM, "stroke": UIDraw.INK,
		"lw": 3, "r": 5, "shadow": UIDraw.ORANGE, "shadowX": 7, "shadowY": 7})
	# menu.js:1396-1402 —— 墨色抬头被 clip 到卡片圆角矩形里（左上/右上角保持圆角）
	var card_clip := UIDraw.rr_points(c["x"], c["y"], c["w"], c["h"], 5)
	_fill_clipped(_rect_poly(c["x"], c["y"], c["w"], 54), card_clip, UIDraw.INK)
	UIDraw.dots(self, c["x"], c["y"], c["w"], 54, UIDraw.CREAM, 0.055, 12)
	UIDraw.text(self, "SETTINGS  /  设置", c["x"] + 20, c["y"] + 20,
		{"size": 11, "weight": 700, "family": "mono", "fill": UIDraw.CYAN})
	UIDraw.text(self, "设置即时生效，自动保存", c["x"] + 20, c["y"] + 39,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.62)})
	var close := _settings_close_rect()
	var close_hot := _h("settings_close")
	UIDraw.panel(self, close.position.x, close.position.y, close.size.x, close.size.y,
		{"fill": UIDraw.INK if close_hot else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.5, "r": 2})
	UIDraw.text(self, "×", close.position.x + 13, close.position.y + 13,
		{"size": 17, "weight": 900, "family": "mono",
		"fill": UIDraw.CREAM if close_hot else UIDraw.INK, "align": "center"})
	for i in SETTINGS_TABS.size():
		_draw_settings_tab(i, SETTINGS_TABS[i])
	match settings_tab:
		"pad":
			_draw_settings_pad()
		"keys":
			_draw_settings_keys()
		_:
			_draw_settings_audio()
	# 页脚
	var done := _settings_done_rect()
	var done_hot := _h("settings_done")
	UIDraw.panel(self, done.position.x, done.position.y, done.size.x, done.size.y,
		{"fill": UIDraw.ORANGE if done_hot else UIDraw.YELLOW, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
		"shadow": UIDraw.ORANGE, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "完成", done.position.x + done.size.x * 0.5, done.position.y + 15,
		{"size": 12, "weight": 900, "family": "cn", "fill": UIDraw.INK, "align": "center"})
	UIDraw.text(self, "点击页签切换　·　Esc 关闭设置", c["x"] + 24, done.position.y + 15,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7)})
	draw_rect(Rect2(c["x"], c["y"] + c["h"] - 4, 54, 4), UIDraw.ORANGE, true, -1.0, true)
	if not capture_target.is_empty():
		_draw_capture_overlay()

func _draw_settings_tab(i: int, tab: Dictionary) -> void:
	var r := _settings_tab_rect(i)
	var active := settings_tab == String(tab["id"])
	var hovered := _h("tab", -99, i)
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.INK if active else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": UIDraw.ORANGE if active else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16),
		"shadowX": 3 if active else 2, "shadowY": 3 if active else 2})
	UIDraw.text(self, tab["label"], r.position.x + 14, r.position.y + r.size.y * 0.5,
		{"size": 13, "weight": 900, "family": "cn", "fill": UIDraw.CREAM if active else UIDraw.INK})
	UIDraw.text(self, tab["en"], r.position.x + r.size.x - 12, r.position.y + r.size.y * 0.5 + 1,
		{"size": 11, "weight": 700, "family": "mono", "align": "right",
		"fill": UIDraw.CYAN if active else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.65)})
	if hovered and not active:
		draw_rect(r, Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.06), true, -1.0, true)

# ---------------- 声音 ----------------

func _draw_settings_audio() -> void:
	var bx := _settings_body_x()
	var by := _settings_body_y()
	UIDraw.text(self, "AUDIO MIXER / 音量调节（拖动时实时试听，松手即保存）", bx, by + 8,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.65)})
	_draw_slider_row("sfx", sfx_level, UIDraw.ORANGE, "音效 SFX", "UI / 炸弹 / 拾取 / 技能")
	_draw_slider_row("music", music_level, UIDraw.CYAN, "音乐 MUSIC", "菜单 / 关卡 / BOSS")
	UIDraw.text(self, "M 全局静音　·　Esc 关闭设置", bx + 8, by + 214,
		{"size": 11, "weight": 500, "family": "cn", "fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7)})
	# menu.js:1428-1433 —— BI.sfx.enabled === false（即静音）时补一个 MUTED 贴纸
	if audio != null and bool(audio.get("muted")):
		UIDraw.tag(self, "已静音 / MUTED", bx + float(SETTINGS_BODY["w"]) - 8, by + 210,
			{"size": 11, "family": "mono", "fill": UIDraw.PINK, "fg": UIDraw.INK,
			"padX": 6, "h": 14, "align": "right", "stroke": UIDraw.INK, "lw": 1})
	var r := _fullscreen_rect()
	var enabled := InputSettings.fullscreen_enabled()
	UIDraw.text(self, "DISPLAY / 画面", bx + 8, by + 260,
		{"size": 11, "family": "mono", "fill": UIDraw.INK})
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y,
		{"fill": UIDraw.YELLOW if _h("fullscreen") else UIDraw.PAPER, "stroke": UIDraw.INK, "lw": 2, "r": 3})
	UIDraw.text(self, "全屏显示", r.position.x + 14, r.get_center().y,
		{"size": 15, "fill": UIDraw.INK})
	UIDraw.text(self, "开启" if enabled else "关闭", r.end.x - 16, r.get_center().y,
		{"size": 14, "fill": UIDraw.INK, "align": "right"})
	UIDraw.text(self, "F11 快速切换 · 自动适应屏幕，保持游戏比例", bx + 8, by + 358,
		{"size": 11, "weight": 500, "fill": UIDraw.INK})

func _draw_slider_row(kind: String, value: float, color: Color, label: String, sub: String) -> void:
	var r := _settings_slider_rect(kind)
	var bx := _settings_body_x()
	UIDraw.text(self, label, bx + 8, r.position.y - 32, {"size": 15, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	UIDraw.text(self, sub, bx + 8, r.position.y - 12, {"size": 11, "weight": 500, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.42)})
	var range_v := _slider_range(kind)
	var t := clampf((value - range_v.x) / maxf(range_v.y - range_v.x, 0.0001), 0.0, 1.0)
	var shown := ("%.2f" % value) if kind == "deadzone" else ("%d%%" % int(round(t * 100.0)))
	UIDraw.text(self, shown, r.position.x + r.size.x, r.position.y - 32,
		{"size": 16, "weight": 900, "family": "mono", "fill": color, "align": "right"})
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, r.size.y),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.14), true, -1.0, true)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x * t, r.size.y), color, true, -1.0, true)
	for i in range(1, 10):
		draw_rect(Rect2(r.position.x + r.size.x * i / 10.0 - 0.5, r.position.y - 3, 1, r.size.y + 6),
			UIDraw.INK, true, -1.0, true)
	var kx := r.position.x + r.size.x * t
	var ky := r.position.y + r.size.y * 0.5
	draw_circle(Vector2(kx, ky), 8, UIDraw.CREAM, true, -1.0, true)
	draw_arc(Vector2(kx, ky), 8, 0, TAU, 24, UIDraw.INK, 2.0, true)
	draw_circle(Vector2(kx, ky), 3, color, true, -1.0, true)

# ---------------- 控制器 ----------------

func _draw_settings_pad() -> void:
	var bx := _settings_body_x()
	var by := _settings_body_y()
	var w := float(SETTINGS_BODY["w"])
	UIDraw.text(self, "CONTROLLER / 控制器与手柄（热插拔即时刷新）", bx, by + 8,
		{"size": 11, "weight": 700, "family": "mono",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.65)})
	var devs := InputSettings.available_devices()
	var conn := "未检测到手柄（可只用键盘）"
	if devs.size() > 0:
		var parts: Array = []
		for d in devs:
			parts.append(InputSettings.device_name(int(d)))
		conn = "可用手柄：  " + "　·　".join(parts)
	UIDraw.text(self, UIDraw.fit(conn, w, 11), bx, by + 26, {"size": 11, "weight": 700, "family": "cn",
		"fill": UIDraw.INK if devs.size() > 0 else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7)})
	draw_line(Vector2(bx, by + 38), Vector2(bx + w, by + 38),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16), 1.0, true)
	for s in 2:
		_draw_pad_block(s)
	_draw_slider_row("deadzone", InputSettings.deadzone(), UIDraw.GREEN,
		"摇杆死区 DEADZONE", "低于该幅度的摇杆漂移不会触发方向（松手即保存）")
	# 震动
	var ry := _settings_body_y() + PAD_RUMBLE_Y
	var rr := _pad_rumble_rect()
	var on := InputSettings.rumble_enabled()
	UIDraw.text(self, "震动反馈 RUMBLE", bx + 4, ry + 20,
		{"size": 13, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	_draw_seg_button(rr, "开 / ON" if on else "关 / OFF", on, _h("rumble"), UIDraw.YELLOW)
	var note := "放弹或施放技能时短震动"
	if not InputSettings.any_rumble_device():
		note += "。当前设备暂不支持震动。"
	UIDraw.wrap(self, note, rr.position.x + rr.size.x + 16, ry + 12,
		bx + w - rr.end.x - 20, 11, 16, Color(0.15, 0.12, 0.18, 0.78), 3)
	UIDraw.wrap(self, "自动：键盘与手柄均可用。手柄：连接时只读手柄；断开时回退键盘。两名玩家分别使用独立手柄。",
		bx + 4, by + PAD_HINT_Y, w - 8, 11, 17, Color(0.15, 0.12, 0.18, 0.78), 2)

func _draw_pad_block(s: int) -> void:
	var bx := _settings_body_x()
	var by := _settings_body_y()
	var slot := "p1" if s == 0 else "p2"
	var color := UIDraw.CYAN if s == 0 else UIDraw.PINK
	var mode := InputSettings.device_mode(slot)
	var dev := InputSettings.slot_device(slot)
	var seg_y := by + float(PAD_SEG["y"]) + s * PAD_BLOCK_H
	UIDraw.text(self, "%s 操作方式" % slot.to_upper(), bx + 4, seg_y + 14,
		{"size": 13, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	for i in InputSettings.MODES.size():
		var m := String(InputSettings.MODES[i])
		_draw_seg_button(_pad_seg_rect(s, i), String(InputSettings.MODE_LABELS[m]),
			mode == m, _h("pad_seg", s, i), color)
	var dy := by + float(PAD_DEV["y"]) + s * PAD_BLOCK_H
	UIDraw.text(self, "手柄设备", bx + 4, dy + 14,
		{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.INK})
	var prev := _pad_dev_rect(s, "prev")
	var next := _pad_dev_rect(s, "next")
	_draw_arrow_button(prev, "◀", _h("pad_dev", s, -99) and String(hover.get("part", "")) == "prev")
	_draw_arrow_button(next, "▶", _h("pad_dev", s, -99) and String(hover.get("part", "")) == "next")
	var box := _pad_dev_rect(s, "box")
	UIDraw.panel(self, box.position.x, box.position.y, box.size.x, box.size.y,
		{"fill": UIDraw.WHITE, "stroke": UIDraw.INK, "lw": 1.5, "r": 3})
	var setting := InputSettings.device_setting(slot)
	var text := "自动"
	if setting >= 0:
		text = InputSettings.device_name(setting)
	elif dev >= 0:
		text = "自动 → " + InputSettings.device_name(dev)
	text = UIDraw.fit(text, box.size.x - 16, 11, 700, "cn")
	UIDraw.text(self, text, box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5,
		{"size": 11, "weight": 700, "family": "cn", "fill": UIDraw.INK, "align": "center"})
	var hint := String(InputSettings.MODE_HINTS[mode])
	if mode != InputSettings.MODE_KEYBOARD and dev < 0:
		hint = "当前没有可用手柄 → 自动回退到键盘"
	UIDraw.text(self, hint, bx + float(PAD_DEV["x"]), dy + 38,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.7)})

func _draw_seg_button(r: Rect2, label: String, active: bool, hovered: bool, color: Color) -> void:
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.INK if active else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
		"shadow": color if active else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16),
		"shadowX": 3 if active else 2, "shadowY": 3 if active else 2})
	UIDraw.text(self, label, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5,
		{"size": 11, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM if active else UIDraw.INK, "align": "center"})
	if hovered and not active:
		draw_rect(r, Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.07), true, -1.0, true)

func _draw_arrow_button(r: Rect2, glyph: String, hovered: bool) -> void:
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.INK if hovered else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.6, "r": 3,
		"shadow": UIDraw.ORANGE if hovered else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16),
		"shadowX": 2, "shadowY": 2})
	UIDraw.text(self, glyph, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5,
		{"size": 11, "weight": 900, "family": "mono",
		"fill": UIDraw.CREAM if hovered else UIDraw.INK, "align": "center"})

# ---------------- 键位 ----------------

func _draw_settings_keys() -> void:
	var bx := _settings_body_x()
	var by := _settings_body_y()
	for i in 2:
		_draw_seg_button(_keys_player_rect(i), "%dP" % (i + 1), keys_player == i,
			_h("keys_player", -99, i), UIDraw.CYAN if i == 0 else UIDraw.PINK)
	if keys_player == 0:
		for i in 2:
			_draw_seg_button(_keys_profile_rect(i), "主键位" if i == 0 else "备用键位",
				keys_profile == ("main" if i == 0 else "alt"), _h("keys_profile", -99, i), UIDraw.YELLOW)
	else:
		UIDraw.text(self, "2P 没有备用键位（Tab 只切 1P）", bx + 170, by + 18,
			{"size": 11, "weight": 500, "family": "cn",
			"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.65)})
	UIDraw.wrap(self, "选中按键格后确认改绑；Back / Esc 取消，Del 清除。1P 手柄键位在单人和对战中通用。",
		bx + 8, by + 40, float(SETTINGS_BODY["w"]) - 16, 11, 16,
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.55), 2, 500, "cn")
	for i in InputSettings.FUNCS.size():
		_draw_keys_row(i)
	var rr := _keys_reset_rect()
	var hot := _h("keys_reset")
	UIDraw.panel(self, rr.position.x, rr.position.y, rr.size.x, rr.size.y, {
		"fill": UIDraw.INK if hot else UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 1.8, "r": 3,
		"shadow": UIDraw.ORANGE if hot else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.16),
		"shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "恢复默认键位", rr.position.x + rr.size.x * 0.5, rr.position.y + rr.size.y * 0.5,
		{"size": 11, "weight": 900, "family": "cn",
		"fill": UIDraw.CREAM if hot else UIDraw.INK, "align": "center"})
	if InputSettings.has_custom_bindings():
		UIDraw.tag(self, "已自定义", rr.position.x + rr.size.x + 14, rr.position.y + rr.size.y * 0.5,
			{"size": 11, "family": "cn", "fill": UIDraw.PINK, "fg": UIDraw.INK, "padX": 6, "h": 14,
			"align": "left", "stroke": UIDraw.INK, "lw": 1})
	UIDraw.text(self, "M 静音　·　Tab 战斗中切 1P 备用键位", bx + 4, by + 400,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.65)})

func _draw_keys_row(i: int) -> void:
	var f := String(InputSettings.FUNCS[i])
	var action := InputSettings.action_for(_keys_group(), f)
	var r := _keys_row_rect(i)
	var capturing := int(capture_target.get("index", -1)) == i
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.YELLOW if capturing else UIDraw.WHITE, "stroke": UIDraw.INK, "lw": 1.6, "r": 4,
		"shadow": Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.14), "shadowX": 2, "shadowY": 2})
	UIDraw.text(self, String(InputSettings.FUNC_LABELS[f]), r.position.x + 12, r.position.y + r.size.y * 0.5,
		{"size": 12, "weight": 900, "family": "cn", "fill": UIDraw.INK})
	_draw_keys_zone(i, "key", action)
	_draw_keys_zone(i, "pad", action)

func _draw_keys_zone(i: int, kind: String, action: String) -> void:
	var r := _keys_zone_rect(i, kind)
	var hovered := _h("key_zone" if kind == "key" else "pad_zone", -99, i)
	var is_target := int(capture_target.get("index", -1)) == i \
		and String(capture_target.get("kind", "")) == kind
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": UIDraw.YELLOW if is_target else UIDraw.CREAM,
		"stroke": UIDraw.INK if (hovered or is_target) else Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.22),
		"lw": 1.8 if (hovered or is_target) else 1.0, "r": 3})
	var labels: Array = InputSettings.pad_labels(action) if kind == "pad" else InputSettings.key_labels(action)
	var text_color := Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.4)
	if labels.is_empty():
		var empty_text := "未绑定" if kind == "pad" else ("—" if not InputSettings.PAD_GROUPS.has(_keys_group()) else "未绑定")
		UIDraw.text(self, empty_text, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5,
			{"size": 11, "weight": 500, "family": "cn", "fill": text_color, "align": "center"})
		return
	var x := r.position.x + 8
	for lab in labels:
		var s := String(lab)
		var w := maxf(30.0, UIDraw.measure(s, 11, 700, "mono") + 16.0)
		if x + w > r.position.x + r.size.x - 6:
			break
		if kind == "pad":
			UIDraw.keycap(self, s, x, r.position.y + r.size.y * 0.5 - 10, w, 20, UIDraw.INK, UIDraw.CREAM)
		else:
			UIDraw.keycap(self, s, x, r.position.y + r.size.y * 0.5 - 10, w, 20, UIDraw.CREAM, UIDraw.INK)
		x += w + 6

func _draw_capture_overlay() -> void:
	var c := SETTINGS_CARD
	draw_rect(Rect2(c["x"], c["y"], c["w"], c["h"]),
		Color(20 / 255.0, 16 / 255.0, 25 / 255.0, 0.6), true, -1.0, true)
	var rect := Rect2(c["x"] + 44, c["y"] + 250, c["w"] - 88, 150)
	UIDraw.panel(self, rect.position.x, rect.position.y, rect.size.x, rect.size.y, {
		"fill": UIDraw.INK, "stroke": UIDraw.CREAM, "lw": 2.4, "r": 4,
		"shadow": UIDraw.ORANGE, "shadowX": 7, "shadowY": 7})
	var cx := rect.position.x + rect.size.x * 0.5
	var kind := String(capture_target.get("kind", "key"))
	UIDraw.text(self, "请按下新的%s" % ("键盘按键" if kind == "key" else "手柄按钮 / 摇杆方向"),
		cx, rect.position.y + 44,
		{"size": 19, "weight": 900, "family": "cn", "fill": UIDraw.YELLOW, "align": "center"})
	UIDraw.text(self, "%s · %s" % [
		String(InputSettings.GROUP_LABELS.get(String(capture_target.get("group", "")), "")),
		String(InputSettings.FUNC_LABELS.get(String(capture_target.get("func", "")), ""))],
		cx, rect.position.y + 80,
		{"size": 12, "weight": 700, "family": "cn", "fill": UIDraw.CREAM, "align": "center"})
	UIDraw.text(self, "Back / Esc 取消　·　Del 清除　·　Start 保留为暂停键",
		cx, rect.position.y + 112,
		{"size": 11, "weight": 500, "family": "cn",
		"fill": Color(245 / 255.0, 235 / 255.0, 216 / 255.0, 0.6), "align": "center"})

func _draw_toast() -> void:
	if toast_time <= 0.0:
		return
	UIDraw.tag(self, toast_text, Cfg.VIEW_W * 0.5, Cfg.VIEW_H - 76,
		{"size": 11, "family": "cn", "fill": UIDraw.INK, "fg": UIDraw.CREAM,
		"padX": 10, "h": 22, "stroke": UIDraw.CREAM, "lw": 1})

func pad2(n: int) -> String:
	return ("0" + str(n)) if n < 10 else str(n)

func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
