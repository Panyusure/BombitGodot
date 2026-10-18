extends Control

## In-game replay archive and player.
## Godot replays replay and verify their SHA-256 history; original JavaScript
## replays can be watched in compatibility mode (no hash verification).

const Core = preload("res://scripts/cli/BombitCore.gd")

const SPEEDS = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
## 定位/拖动时每帧最多花多少微秒在重演历史上。回放没有快照，向后跳只能从第 0 帧
## 重新演算（实测一步 GameEngine.step ≈ 92µs），一帧里塞 500 步曾造成 ~62ms 卡顿；
## 改成按时间预算分片后，定位期间依然保持 60fps 以上。
const SEEK_BUDGET_USEC := 7000

var main: Node = null
var core
var mode = "off"                 # off / browse / play
var files: Array = []
var selected = 0
var page = 0
var error_text = ""
var model: Dictionary = {}
var play_state: Dictionary = {}
var playing = false
var speed = 1.0
var speed_index = 2
var accum = 0.0
var verified = false
var compat = false
var markers: Array = []
var seeking = false
var seek_target = 0
var seek_state: Dictionary = {}
var _dragging = false
var drag_frame = -1              # 拖动进度条时预览的帧（-1 = 当前没在拖）
var _hits: Dictionary = {}
var _font: Font = null
var _dialog: FileDialog = null
var _music_track = ""            # 当前回放里已生效的 BGM
var _history: Array = []         # model["history"] 的引用缓存，避免每步查字典
var _inputs_index := -1          # 当前缓存的输入对应第几条历史记录
var _inputs_first: Dictionary = {}   # 该记录第一帧的输入（bomb/skill 只在首帧触发）
var _inputs_rest: Dictionary = {}    # 该记录其余帧的输入

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	core = Core.new()
	_font = UIDraw.font("cn", 700)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.json ; BombIt replay"])
	_dialog.title = "选择 BombIt 回放 / 会话 JSON"
	_dialog.size = Vector2i(720, 480)
	_dialog.file_selected.connect(_on_file_selected)
	add_child(_dialog)

func setup(m: Node) -> void:
	main = m

var _pad_prev := {}
var _pad_direction := ""
var _pad_repeat := 0.0

func _sync_pad() -> void:
	_pad_prev = InputSettings.poll_nav(false)
	_pad_direction = ""
	_pad_repeat = 0.0

func _process(delta: float) -> void:
	if not visible or (_dialog != null and _dialog.visible):
		_sync_pad()
		return
	var nav := InputSettings.poll_nav(false)
	var direction := ""
	for name in ["up", "down", "left", "right"]:
		if nav[name]:
			direction = name
			break
	_pad_repeat -= delta
	var move := not direction.is_empty() and (direction != _pad_direction or _pad_repeat <= 0.0)
	if move:
		_pad_repeat = 0.35 if direction != _pad_direction else 0.12
		if mode == "browse":
			var amount := -1 if direction == "up" else (1 if direction == "down" else (-5 if direction == "left" else 5))
			selected = clampi(selected + amount, 0, maxi(0, files.size() - 1))
			page = selected / 5
		elif mode == "play":
			if direction in ["left", "right"]:
				_request_seek(_current_frame() + (-60 if direction == "left" else 60))
			else:
				_cycle_speed(1 if direction == "up" else -1)
	_pad_direction = direction
	if nav["accept"] and not _pad_prev.get("accept", false):
		if mode == "browse":
			_load_selected()
		elif mode == "play" and not seeking:
			playing = not playing
	if nav["cancel"] and not _pad_prev.get("cancel", false):
		if mode == "browse":
			main.exit_replay()
		elif seeking:
			_finish_seek()
		else:
			_go_browser()
	_pad_prev = nav
	if move or nav["accept"] or nav["cancel"]:
		queue_redraw()

func open_browser() -> void:
	_sync_pad()
	visible = true
	mode = "browse"
	playing = false
	seeking = false
	_dragging = false
	drag_frame = -1
	error_text = ""
	_refresh_files()
	grab_focus()
	queue_redraw()

func close() -> void:
	visible = false
	mode = "off"
	playing = false
	seeking = false
	_dragging = false
	drag_frame = -1
	if _dialog != null:
		_dialog.hide()

func _refresh_files() -> void:
	files = core.list_replays()
	if selected >= files.size():
		selected = maxi(0, files.size() - 1)
	page = selected / 5
	queue_redraw()

func _draw() -> void:
	_hits.clear()
	if mode == "browse":
		_draw_browser()
	elif mode == "play":
		_draw_player()

# ---------------------------------------------------------------- browser

func _draw_browser() -> void:
	draw_rect(Rect2(0, 0, 720, 696), UIDraw.PAPER, true, -1.0, true)
	UIDraw.dots(self, 0, 0, 720, 696, UIDraw.INK, 0.05, 14)
	draw_rect(Rect2(0, 0, 720, 50), UIDraw.INK, true, -1.0, true)
	UIDraw.text(self, "BOMBIT  /  MATCH ARCHIVE", 20, 25, {"size": 11, "family": "mono", "fill": UIDraw.CREAM})
	UIDraw.text(self, "MOTION UI  /  2026", 700, 25, {"size": 11, "family": "mono", "fill": Color(245, 235, 216, 0.55), "align": "right"})
	UIDraw.text(self, "对局回放", 24, 92, {"size": 30, "weight": 900, "fill": UIDraw.INK,
		"shadow": UIDraw.ORANGE, "shadowX": 3, "shadowY": 3})
	UIDraw.text(self, "REPLAY ARCHIVE  /  可观看、逐帧检查、拖动定位", 24, 122,
		{"size": 11, "family": "mono", "fill": UIDraw.MUTED})
	var card_x = 24.0
	var card_y = 140.0
	var card_w = 672.0
	var rows_visible = mini(5, maxi(1, files.size()))
	var card_h = (108.0 + rows_visible * 72.0) if not files.is_empty() else 260.0
	UIDraw.panel(self, card_x, card_y, card_w, card_h, {
		"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 3, "r": 4,
		"shadow": UIDraw.ORANGE, "shadowX": 8, "shadowY": 8,
	})
	if files.is_empty():
		UIDraw.text(self, "还没有回放。", card_x + 30, card_y + 70, {"size": 22, "fill": UIDraw.INK})
		UIDraw.wrap(self, "用 CLI 或 MCP 打一局并执行 finish，回放会归档到 data/replays 或用户回放目录；也可以直接打开一个 .replay.json。",
			card_x + 30, card_y + 108, card_w - 60, 11, 18, UIDraw.MUTED, 4, 500)
	else:
		var page_rows = 5
		var max_page = maxi(0, (files.size() - 1) / page_rows)
		page = clampi(page, 0, max_page)
		var start = page * page_rows
		for i in page_rows:
			var idx = start + i
			if idx >= files.size():
				break
			var entry: Dictionary = files[idx]
			var ry = card_y + 16 + i * 72
			var sel = idx == selected
			UIDraw.panel(self, card_x + 16, ry, card_w - 32, 62, {
				"fill": UIDraw.INK if sel else UIDraw.WHITE,
				"stroke": UIDraw.INK, "lw": 2, "r": 3,
				"shadow": UIDraw.ORANGE if sel else null, "shadowX": 4, "shadowY": 4,
			})
			var title_color = UIDraw.CREAM if sel else UIDraw.INK
			var sub_color = Color(245, 235, 216, 0.6) if sel else UIDraw.MUTED
			var nm = String(entry.get("name", "replay"))
			if nm.length() > 48:
				nm = nm.substr(0, 47) + "…"
			UIDraw.text(self, nm, card_x + 30, ry + 22, {"size": 11, "family": "mono", "fill": title_color})
			var meta = "%s  /  %s  /  %s  /  %d actions" % [String(entry.get("mode", "")).to_upper(),
				String(entry.get("agent", "unknown")), String(entry.get("outcome", "?")), int(entry.get("actions", 0))]
			UIDraw.text(self, meta, card_x + 30, ry + 44, {"size": 11, "family": "mono", "fill": sub_color})
			var fmt = "GODOT" if String(entry.get("format", "")) == Core.REPLAY_FORMAT else "JS COMPAT"
			UIDraw.tag(self, fmt, card_x + card_w - 42, ry + 14, {
				"size": 11, "family": "mono", "fill": UIDraw.GREEN if fmt == "GODOT" else UIDraw.YELLOW,
				"fg": UIDraw.INK, "padX": 6, "h": 14, "align": "right",
				"stroke": UIDraw.INK, "lw": 1,
			})
			_hits["row_%d" % idx] = Rect2(card_x + 16, ry, card_w - 32, 62)
		# selected metadata
		var m: Dictionary = files[selected]
		var meta_y = card_y + 24 + rows_visible * 72 + 6
		UIDraw.text(self, "SELECTED  /  %s" % String(m.get("name", "")), card_x + 22, meta_y,
			{"size": 11, "family": "mono", "fill": UIDraw.MUTED})
		var cinfo = "%s  ·  %s  ·  %s  ·  %s" % [String(m.get("mode", "")), ", ".join(m.get("characters", [])),
			String(m.get("outcome", "")), String(m.get("startedAt", ""))]
		UIDraw.text(self, cinfo, card_x + 22, meta_y + 22, {"size": 11, "fill": UIDraw.INK})
		var pager = "PAGE  %d / %d" % [page + 1, max_page + 1]
		UIDraw.text(self, pager, card_x + card_w - 22, meta_y + 22, {"size": 11, "family": "mono",
			"fill": UIDraw.MUTED, "align": "right"})
		var by = card_y + card_h - 42
		_button(Rect2(card_x + 22, by, 50, 32), "‹", UIDraw.WHITE, UIDraw.INK, "prev")
		_button(Rect2(card_x + 80, by, 50, 32), "›", UIDraw.WHITE, UIDraw.INK, "next")
		_button(Rect2(card_x + card_w - 250, by, 112, 32), "打开文件…", UIDraw.WHITE, UIDraw.INK, "open")
		_button(Rect2(card_x + card_w - 128, by, 106, 32), "载入回放", UIDraw.YELLOW, UIDraw.INK, "load")
	_button(Rect2(24, 638, 120, 38), "← 返回菜单", UIDraw.CREAM, UIDraw.INK, "close")
	if error_text != "":
		UIDraw.text(self, error_text, 160, 660, {"size": 11, "family": "mono", "fill": UIDraw.HOT})

func _button(r: Rect2, label: String, fill: Color, fg: Color, id: String) -> void:
	UIDraw.panel(self, r.position.x, r.position.y, r.size.x, r.size.y, {
		"fill": fill, "stroke": UIDraw.INK, "lw": 2, "r": 3,
		"shadow": UIDraw.INK, "shadowX": 3, "shadowY": 3,
	})
	UIDraw.text(self, label, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5,
		{"size": 11, "weight": 900, "fill": fg, "align": "center"})
	_hits[id] = r

# ---------------------------------------------------------------- player

func _draw_player() -> void:
	# top bar
	draw_rect(Rect2(0, 0, 720, 72), UIDraw.INK, true, -1.0, true)
	UIDraw.text(self, "REPLAY  /  MOTION ARCHIVE", 18, 20, {"size": 11, "family": "mono",
		"fill": Color(245, 235, 216, 0.65)})
	var name = String(model.get("recording", {}).get("name", model.get("name", "replay")))
	if name.length() > 44:
		name = name.substr(0, 43) + "…"
	UIDraw.text(self, name, 18, 47, {"size": 13, "weight": 900, "fill": UIDraw.CREAM, "max_width": 400})
	var badge = "已验证"
	var badge_col = UIDraw.GREEN
	if compat:
		badge = "原作兼容 · 未校验"
		badge_col = UIDraw.YELLOW
	elif not verified:
		badge = "校验失败"
		badge_col = UIDraw.HOT
	UIDraw.tag(self, badge, 560, 36, {"size": 11, "family": "mono", "fill": badge_col, "fg": UIDraw.INK,
		"padX": 7, "h": 16, "align": "right", "stroke": UIDraw.INK, "lw": 1})
	_button(Rect2(596, 18, 98, 36), "返回回放库", UIDraw.CREAM, UIDraw.INK, "browser")
	# bottom control card
	var cy = 608.0
	UIDraw.panel(self, 10, cy, 700, 78, {
		"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 3, "r": 4,
		"shadow": UIDraw.INK, "shadowX": 5, "shadowY": 5,
	})
	_button(Rect2(22, cy + 17, 44, 44), "Ⅱ" if playing else "▶", UIDraw.YELLOW if not playing else UIDraw.ORANGE,
		UIDraw.INK, "playpause")
	_button(Rect2(74, cy + 17, 36, 44), "◀", UIDraw.WHITE, UIDraw.INK, "back")
	_button(Rect2(116, cy + 17, 36, 44), "▶", UIDraw.WHITE, UIDraw.INK, "forward")
	# slider
	var sx = 164.0
	var sw = 300.0
	var sy = cy + 34
	draw_rect(Rect2(sx, sy - 2, sw, 4), UIDraw.INK, true, -1.0, true)
	var total = int(model.get("totalFrames", 0))
	var frame = _current_frame()
	# 拖动时旋钮跟手，但只在松手时才真正重演一次（每帧都重演会让进度条越拖越卡）。
	var shown: int = drag_frame if (_dragging and drag_frame >= 0) else frame
	var frac = 1.0 if total <= 0 else clampf(float(shown) / float(total), 0.0, 1.0)
	draw_rect(Rect2(sx, sy - 2, sw * frac, 4), UIDraw.ORANGE, true, -1.0, true)
	for mk in markers:
		var mf = int(mk.get("frame", 0))
		var mx = sx + sw * (float(mf) / float(maxi(1, total)))
		draw_rect(Rect2(mx - 1, sy - 8, 2, 16), UIDraw.CYAN if String(mk.get("type", "")) != "onDeath" else UIDraw.HOT, true, -1.0, true)
	draw_circle(Vector2(sx + sw * frac, sy), 6, UIDraw.ORANGE, true, -1.0, true)
	draw_circle(Vector2(sx + sw * frac, sy), 3, UIDraw.CREAM, true, -1.0, true)
	_hits["slider"] = Rect2(sx - 8, sy - 14, sw + 16, 28)
	# time + speed
	var cur = float(shown) / 60.0
	var dur = float(total) / 60.0
	UIDraw.text(self, "%s / %s" % [_duration(cur), _duration(dur)], sx + sw + 14, cy + 24,
		{"size": 11, "family": "mono", "fill": UIDraw.INK})
	UIDraw.text(self, "FRAME %d / %d" % [shown, total], sx + sw + 14, cy + 42,
		{"size": 11, "family": "mono", "fill": UIDraw.MUTED})
	_button(Rect2(606, cy + 17, 84, 44), "x%s" % _speed_label(), UIDraw.CYAN, UIDraw.INK, "speed")
	if seeking:
		var p = clampf(float(seek_state.get("frame", 0)) / float(maxi(1, seek_target)), 0.0, 1.0)
		draw_rect(Rect2(10, cy - 20, 700, 12), UIDraw.INK, true, -1.0, true)
		draw_rect(Rect2(10, cy - 20, 700 * p, 12), UIDraw.ORANGE, true, -1.0, true)
		UIDraw.text(self, "定位中… %d%%" % int(p * 100), 360, cy - 26, {"size": 11, "family": "mono",
			"fill": UIDraw.CREAM, "align": "center"})
	# help line
	var hint = "A / 空格 播放暂停 · ←→ 跳转 · ↑↓ 倍速 · B / Esc 返回"
	draw_rect(Rect2(0, 582, 720, 22), Color(20, 16, 25, 0.72), true, -1.0, true)
	UIDraw.text(self, hint, 360, 593, {"size": 11, "family": "mono", "fill": Color(245, 235, 216, 0.85), "align": "center"})
	var current_marker = ""
	for mk in markers:
		if int(mk.get("frame", 0)) <= frame:
			current_marker = String(mk.get("label", ""))
	UIDraw.text(self, "MARKER  /  %s" % current_marker, 20, 84,
		{"size": 11, "family": "mono", "fill": Color(245, 235, 216, 0.6)})

func _duration(seconds: float) -> String:
	if seconds < 10.0:
		return "%.1fs" % maxf(0.0, seconds)
	var s = maxi(0, int(round(seconds)))
	return "%02d:%02d" % [s / 60, s % 60]

## 定位中时以“正在演算到的那一帧”为准，这样进度条/K 帧提示会跟着走。
func _current_frame() -> int:
	if seeking:
		return int(seek_state.get("frame", 0))
	return int(play_state.get("frame", 0))

func _speed_label() -> String:
	if is_equal_approx(speed, 0.25):
		return "0.25"
	if is_equal_approx(speed, 0.5):
		return "0.5"
	return str(int(speed))

# ---------------------------------------------------------------- input

func handle_key(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key = event.keycode
	if mode == "browse":
		if key == KEY_ESCAPE:
			main.exit_replay()
		elif key == KEY_UP:
			selected = maxi(0, selected - 1)
			page = selected / 5
			queue_redraw()
		elif key == KEY_DOWN:
			selected = clampi(selected + 1, 0, maxi(0, files.size() - 1))
			page = selected / 5
			queue_redraw()
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			_load_selected()
		elif key == KEY_PAGEUP:
			selected = maxi(0, selected - 5)
			page = selected / 5
			queue_redraw()
		elif key == KEY_PAGEDOWN:
			selected = mini(files.size() - 1, selected + 5)
			page = selected / 5
			queue_redraw()
		elif key == KEY_O:
			_dialog.popup_centered()
		get_viewport().set_input_as_handled()
		return
	if mode != "play":
		return
	match key:
		KEY_ESCAPE:
			if seeking:
				# 停在当前演算到的位置，而不是把画面留在半截的定位世界上。
				_finish_seek()
			else:
				_go_browser()
		KEY_SPACE:
			playing = not playing
			if playing and seeking:
				playing = false
		KEY_LEFT:
			_request_seek(_current_frame() - (300 if event.shift_pressed else 60))
		KEY_RIGHT:
			_request_seek(_current_frame() + (300 if event.shift_pressed else 60))
		KEY_UP:
			_cycle_speed(1)
		KEY_DOWN:
			_cycle_speed(-1)
		KEY_HOME:
			_request_seek(0)
		KEY_END:
			_request_seek(int(model.get("totalFrames", 0)))
	get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos = event.position
			for id in _hits.keys():
				if id == "slider":
					continue
				if (_hits[id] as Rect2).has_point(pos):
					_on_hit(String(id), pos)
					accept_event()
					return
			if mode == "play" and _hits.has("slider") and (_hits["slider"] as Rect2).has_point(pos):
				_dragging = true
				drag_frame = _frame_from_x(pos.x)
				queue_redraw()
				accept_event()
				return
		else:
			if _dragging:
				_dragging = false
				var target: int = drag_frame
				drag_frame = -1
				if target >= 0 and mode == "play":
					_request_seek(target)
				queue_redraw()
				accept_event()
				return
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		# 拖动期间只更新预览帧，不重演历史：松手时再落地一次定位。
		drag_frame = _frame_from_x(event.position.x)
		queue_redraw()
		accept_event()

func _on_hit(id: String, pos: Vector2) -> void:
	match id:
		"close":
			main.exit_replay()
		"browser":
			_go_browser()
		"load":
			_load_selected()
		"open":
			_dialog.popup_centered()
		"prev":
			page = maxi(0, page - 1)
			selected = page * 5
			queue_redraw()
		"next":
			page = mini(maxi(0, (files.size() - 1) / 5), page + 1)
			selected = mini(files.size() - 1, page * 5)
			queue_redraw()
		"playpause":
			playing = not playing
			if seeking:
				playing = false
		"back":
			_request_seek(_current_frame() - 60)
		"forward":
			_request_seek(_current_frame() + 60)
		"speed":
			_cycle_speed(1)
		_:
			if id.begins_with("row_"):
				selected = int(id.substr(4))
				queue_redraw()
				_load_selected()

func _frame_from_x(x: float) -> int:
	# _hits["slider"] 是给鼠标用的加宽命中区（左右各 +8），映射要按真正的滑轨算，
	# 否则拖到最右端只能到 ~98%，松手后时间轴永远差一截。
	var slider = _hits.get("slider", Rect2(164, 0, 300, 0))
	var total = int(model.get("totalFrames", 0))
	if total <= 0:
		return 0
	var width := maxf(1.0, slider.size.x - 16.0)
	return clampi(int(round((x - slider.position.x - 8.0) / width * float(total))), 0, total)

func _cycle_speed(dir: int) -> void:
	speed_index = clampi(speed_index + dir, 0, SPEEDS.size() - 1)
	speed = float(SPEEDS[speed_index])

# ---------------------------------------------------------------- loading

func _on_file_selected(path: String) -> void:
	load_path(path)

func _load_selected() -> void:
	if selected < 0 or selected >= files.size():
		return
	load_path(String(files[selected].get("file", "")))

func load_path(path: String) -> void:
	error_text = ""
	var raw = core._read_json(path)
	if raw.is_empty():
		error_text = "无法读取回放 JSON"
		queue_redraw()
		return
	var fmt = String(raw.get("format", ""))
	var config = raw.get("config", {})
	var history = raw.get("history", [])
	if typeof(config) != TYPE_DICTIONARY or typeof(history) != TYPE_ARRAY:
		error_text = "回放缺少 config/history"
		queue_redraw()
		return
	var is_godot = fmt == Core.REPLAY_FORMAT
	var cfg = core.normalize_config({"mode": config.get("mode", "adventure"),
		"seed": config.get("seed", "demo"),
		"character": config.get("chars", ["xiaonuo"])[0] if config.get("chars", []).size() > 0 else "xiaonuo",
		"character2": config.get("chars", ["xiaonuo", "axiu"])[1] if config.get("chars", []).size() > 1 else "axiu"})
	if cfg.is_empty():
		error_text = "回放开局配置无效"
		queue_redraw()
		return
	var built = _build_model(cfg, history, is_godot, raw)
	if not bool(built.get("ok", false)):
		error_text = String(built.get("error", "回放读取失败"))
		queue_redraw()
		return
	model = built
	model["name"] = path.get_file()
	model["recording"] = raw.get("recording", {})
	model["compat"] = not is_godot
	compat = not is_godot
	verified = bool(model.get("verified", false))
	markers = model.get("markers", [])
	_history = model.get("history", [])
	speed_index = 2
	speed = 1.0
	_reset_playback()
	mode = "play"
	playing = false
	if main != null:
		main.enter_replay_world(play_state["world"])
		_music_track = "level-2" if String(play_state["world"].theme) == "factory" else "level-1"
	queue_redraw()

func _build_model(cfg: Dictionary, history: Array, check_hashes: bool, raw: Dictionary) -> Dictionary:
	var w = core._create_world(cfg)
	w.briefing = false
	var marks = [{"frame": 0, "label": "第 1 关" if cfg["mode"] == "adventure" else "开局", "type": "start"}]
	var total = 0
	var ok_hashes = true
	var advanced_ok = true
	for entry in history:
		var action = entry.get("action", {})
		if typeof(action) != TYPE_DICTIONARY:
			continue
		var step = core._advance(w, action)
		var adv = int(step.get("advancedFrames", 0))
		total += adv
		if check_hashes:
			if adv != int(entry.get("advancedFrames", -1)):
				advanced_ok = false
			if core.state_hash(w) != String(entry.get("hash", "")):
				ok_hashes = false
		for e in step.get("events", []):
			var t = String(e.get("type", ""))
			var label = ""
			if t == "level_started":
				label = "第 %d 关" % int(e.get("level", 1))
			elif t == "round_started":
				label = "第 %d 回合" % int(e.get("round", 1))
			elif t == "onDeath":
				label = "阵亡 · 剩 %d 命" % int(e.get("lives", 0))
			elif t == "match_over":
				label = "挑战完成" if String(w.match.winner) == "p1" else "对局结束"
			if label != "":
				marks.append({"frame": total, "label": label, "type": t})
	var verified = check_hashes and ok_hashes and advanced_ok
	if check_hashes and raw.has("finalHash"):
		if core.state_hash(w) != String(raw.get("finalHash", "")):
			verified = false
	return {"ok": true, "config": cfg, "history": history, "totalFrames": total,
		"markers": marks, "verified": verified, "advancedOk": advanced_ok, "hashesOk": ok_hashes}

func _reset_playback() -> void:
	var w = core._create_world(model["config"])
	w.briefing = false
	play_state = {"world": w, "index": 0, "offset": 0, "frame": 0}
	playing = false
	seeking = false
	accum = 0.0
	_inputs_index = -1

func _go_browser() -> void:
	mode = "browse"
	playing = false
	seeking = false
	_dragging = false
	drag_frame = -1
	if main != null:
		main.leave_replay_stage()
	_refresh_files()
	queue_redraw()

# ---------------------------------------------------------------- playback

func update(delta: float) -> void:
	if mode != "play" or main == null:
		return
	if seeking:
		_process_seek()
	queue_redraw()

func physics_step(delta: float) -> void:
	if mode != "play" or seeking or not playing:
		return
	accum += delta * 60.0 * speed
	var steps = int(accum)
	accum -= float(steps)
	steps = mini(steps, 180)
	for i in steps:
		if not _advance_one(play_state):
			playing = false
			break
	# 0 步的帧（0.25× 常见）不需要同步视图：sync 会遍历角色/炸弹，白花 ~3µs~1ms。
	if steps > 0 and main != null and play_state.has("world"):
		main.sync_replay_view(play_state["world"])
	queue_redraw()

## 回放的一步：把「第 index 条记录的第 offset 帧」喂给 GameEngine。
## 输入字典按记录缓存（bomb/skill 只在记录首帧触发），避免每帧重建 Dictionary。
func _advance_one(st: Dictionary) -> bool:
	var index = int(st.get("index", 0))
	if index >= _history.size():
		return false
	if index != _inputs_index:
		_inputs_index = index
		_build_inputs(_history[index], index)
	var offset = int(st.get("offset", 0))
	GameEngine.step(st["world"], _inputs_first if offset == 0 else _inputs_rest, 1.0 / 60.0)
	if st["world"].briefing:
		st["world"].briefing = false
	st["offset"] = offset + 1
	st["frame"] = int(st.get("frame", 0)) + 1
	var entry: Dictionary = _history[index]
	var action: Dictionary = entry.get("action", {})
	var limit = int(entry.get("advancedFrames", int(action.get("frames", 1))))
	if int(st["offset"]) >= limit:
		st["index"] = index + 1
		st["offset"] = 0
	return true

func _build_inputs(entry: Dictionary, _index: int) -> void:
	var action: Dictionary = entry.get("action", {})
	var acts: Dictionary = action.get("actions", {})
	_inputs_first = {}
	_inputs_rest = {}
	for id in acts.keys():
		var a = acts[id]
		var d = core.DIRS.get(String(a.get("move", "none")), Vector2i.ZERO)
		var key := String(id)
		_inputs_first[key] = {"hx": d.x, "hy": d.y, "bomb": bool(a.get("bomb", false)),
			"skill": bool(a.get("skill", false))}
		_inputs_rest[key] = {"hx": d.x, "hy": d.y, "bomb": false, "skill": false}

## 跳转到某个帧。
## 前向跳转直接从当前播放状态续跑（不重建世界、不重放整段，也不会让 Board 重画地图）；
## 后向跳转只能从第 0 帧重新演算（回放没有快照），交给 _process_seek 按时间预算分片推进。
func _request_seek(frame: int) -> void:
	if mode != "play":
		return
	var total = int(model.get("totalFrames", 0))
	frame = clampi(frame, 0, total)
	if not seeking and frame == int(play_state.get("frame", 0)):
		return
	seek_target = frame
	if seeking:
		# 已经在定位中：只要目标还在当前位置之前方，改目标即可，绝不重放。
		if frame >= int(seek_state.get("frame", 0)):
			queue_redraw()
			return
	elif frame > int(play_state.get("frame", 0)):
		seek_state = play_state
		seeking = true
		playing = false
		queue_redraw()
		return
	if frame <= 0:
		_reset_playback()
		if main != null:
			main.enter_replay_world(play_state["world"])
		queue_redraw()
		return
	var w = core._create_world(model["config"])
	w.briefing = false
	seek_state = {"world": w, "index": 0, "offset": 0, "frame": 0}
	seeking = true
	playing = false
	queue_redraw()

func _process_seek() -> void:
	var started = Time.get_ticks_usec()
	var done := false
	while Time.get_ticks_usec() - started < SEEK_BUDGET_USEC:
		if int(seek_state.get("frame", 0)) >= seek_target:
			done = true
			break
		if not _advance_one(seek_state):
			done = true
			break
	# 注意：这里刻意不逐帧把 seek_state 推给 Main。回放里砖块被打掉会让
	# world.map_revision 变化，Board 的静态地图缓存因此失效并整张重画（一次 ~80ms）；
	# 边定位边同步会让整段重放里每次“跳过一个炸砖帧”都付一次这笔钱。
	# 定位期间只更新 UI 进度条，算完再统一扶正一次。
	if done:
		_finish_seek()
	queue_redraw()

## 定位结束（算到目标帧，或历史耗尽）：把演算中的状态扶正成播放状态。
func _finish_seek() -> void:
	seeking = false
	play_state = seek_state
	if main == null:
		return
	if main.world == play_state["world"]:
		main.sync_replay_view(play_state["world"])
	else:
		main.enter_replay_world(play_state["world"])
	_sync_replay_music(play_state["world"])

## 跳关后 BGM 跟着主题走（以前这件事由 enter_replay_world 顺带做了；
## 现在定位过程只调 sync_replay_view，避免每次跳转都重画整张静态地图）。
func _sync_replay_music(w) -> void:
	if w == null or main == null or main.audio == null:
		return
	var track: String = "level-2" if String(w.theme) == "factory" else "level-1"
	if track == _music_track:
		return
	_music_track = track
	main.audio.play_music(track)
