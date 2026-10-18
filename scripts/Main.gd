extends Node2D

## 主状态机：菜单 → 关前档案 → 对局 → 暂停 / 结算；固定 60Hz 逻辑与插值渲染。

enum State { MENU, BRIEFING, PLAY, PAUSE, RESULT, REPLAY }

const FONT_PATH = "res://assets/fonts/msyh.ttc"

@onready var board: Node2D = $Board
@onready var actors: Node2D = $Actors
@onready var hud: Control = $UILayer/Hud
@onready var menu: Control = $UILayer/Menu
@onready var overlay: Control = $UILayer/Overlay
@onready var replay_ui: Control = $UILayer/Replay

var world: World = null
var state = State.MENU
var font: Font = null

var mode = "adventure"
var p1_char = "xiaonuo"
var p2_char = "axiu"
var muted = false
var alt_keys = false

var _views: Dictionary = {}
var _bomb_views: Dictionary = {}
var _prev_bomb: Dictionary = {}
var _prev_skill: Dictionary = {}
var _last_dir: Dictionary = {}
var _result_timer = 0.0
var _music_clock = 0.0
var audio: Node = null
var effects = null              # Effects.gd：粒子 / 飘字 / 震屏（原作 src/render/effects.js）

func _ready() -> void:
	audio = get_node_or_null("/root/GameAudio")
	# 输入层：读 user://settings.cfg，把操作方式 / 死区 / 绑定表装进 InputMap。
	InputSettings.ensure_loaded()
	_setup_display()
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)
	board.font = font
	hud.font = font
	menu.setup(muted)
	menu.start_requested.connect(_on_menu_start)
	menu.mute_toggled.connect(_toggle_mute)
	menu.replay_requested.connect(_on_replay_requested)
	menu.settings_closed.connect(_close_pause_settings)
	replay_ui.setup(self)
	replay_ui.visible = false
	overlay.action.connect(_on_overlay_action)
	board.visible = false
	actors.visible = false
	hud.visible = false
	menu.visible = true
	DisplayServer.window_set_title("Q版泡泡堂 BombIt")
	# 特效层：粒子画在角色之上、场地边框之下（边框在 Hud 的 CanvasLayer 里）。
	# 在 _ready 末尾 add_child → 同层内排在 Actors 之后；基准位置与 Board/Actors 一致。
	effects = load("res://scripts/Effects.gd").new()
	effects.name = "Effects"
	effects.position = Vector2(0.0, Cfg.HUD_H)
	add_child(effects)
	audio.play_music("menu")

func _setup_display() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var layer := CanvasLayer.new()
	layer.name = "ScreenBackdrop"
	layer.layer = -10
	add_child(layer)
	layer.add_child(preload("res://scripts/ScreenBackdrop.gd").new())
	get_viewport().size_changed.connect(_center_content)
	_center_content()
	if InputSettings.fullscreen_enabled() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _center_content() -> void:
	var origin := preload("res://scripts/ScreenBackdrop.gd").content_origin(get_viewport_rect().size)
	position = origin
	$UILayer.offset = origin

func _close_pause_settings() -> void:
	if state == State.PAUSE:
		overlay.visible = true
		overlay._sync_nav()
		_sync_action_edges()

func _on_menu_start(m: String, c1: String, c2: String) -> void:
	if state != State.MENU:
		return
	if m == "versus" and not menu.versus_start_authorized(c1, c2):
		return
	mode = m
	p1_char = c1
	p2_char = c2
	menu.visible = false
	_start_run()

func _on_replay_requested() -> void:
	if state == State.REPLAY:
		return
	state = State.REPLAY
	menu.visible = false
	hud.visible = false
	overlay.hide_overlay()
	board.visible = false
	actors.visible = false
	if effects != null:
		effects.reset()
	_clear_views()
	world = null
	board.world = null
	replay_ui.open_browser()
	if audio != null:
		audio.play_music("menu")

func enter_replay_world(w: World) -> void:
	state = State.REPLAY
	world = w
	board.world = w
	board.anim_time = w.time
	board.visible = true
	actors.visible = true
	hud.visible = false
	menu.visible = false
	overlay.hide_overlay()
	_clear_views()
	_sync_views()
	_sync_bombs()
	if audio != null:
		audio.play_music("level-2" if w.theme == "factory" else "level-1")

## 回放每个物理帧都会走到这里。Board.world 的 setter 会清空静态地图缓存
## （_map_key = ""）并把 SubViewport 标成 UPDATE_ONCE，等于把整张地图
## （168 格渐变 + 硬墙/砖块，2× 分辨率）重画一遍：实测一次 ~95ms。
## 同一局回放里世界对象是同一个，所以只在真的换了世界（载入 / 跳转 / 换关）时重新绑定；
## 每帧无条件赋值会让回放 1× 直接掉到 2~3fps。
func sync_replay_view(w: World) -> void:
	if w == null:
		return
	if board.world != w:
		board.world = w
	world = w
	board.anim_time = w.time
	_sync_views()
	_sync_bombs()

func leave_replay_stage() -> void:
	board.visible = false
	actors.visible = false
	board.world = null
	world = null
	_clear_views()

func exit_replay() -> void:
	replay_ui.close()
	state = State.MENU
	world = null
	board.world = null
	hud.world = null
	_clear_views()
	board.visible = false
	actors.visible = false
	hud.visible = false
	menu.reset()
	menu.visible = true
	if audio != null:
		audio.play_music("menu")

func _start_run() -> void:
	InputSettings.active_players = 2 if mode == "versus" else 1
	if world != null:
		GameEngine.clear_field(world)
	world = GameEngine.create_world({
		"mode": mode,
		"chars": [p1_char, p2_char],
		"seed": str(Time.get_ticks_usec()),
		"input_mode": "versus" if mode == "versus" else "solo",
	})
	board.world = world
	hud.world = world
	overlay.world = world
	board.anim_time = 0.0
	_clear_views()
	_sync_views()
	_sync_bombs()
	if p1_char == "weilai" or (mode == "versus" and p2_char == "weilai"):
		call_deferred("_prewarm_soul_sdf")
	board.visible = true
	actors.visible = true
	hud.visible = true
	overlay.hide_overlay()
	_result_timer = 0.0
	_prev_bomb.clear()
	_prev_skill.clear()
	_last_dir.clear()
	# 吃掉沿用自菜单的按键，避免开局第一帧误放炸弹
	_sync_action_edges()
	_game_music(true)
	if world.briefing:
		state = State.BRIEFING
		overlay.show_briefing(world)
	else:
		state = State.PLAY

## 通灵柔光要在第一次放弹 / 转身之前把 SDF 烘好，避免在特效高潮卡一帧。
## 正面与背面都提前烘；SoulSdf 内部按纹理缓存，重复调用无开销。
func _prewarm_soul_sdf() -> void:
	SoulSdf.prewarm([
		"res://assets/characters/weilai-awakened.png",
		"res://assets/characters/weilai-awakened-back.png",
	])

func _on_overlay_action(name: String) -> void:
	match name:
		"start":
			if state == State.BRIEFING and world != null:
				world.briefing = false
				state = State.PLAY
				overlay.hide_overlay()
				_sync_action_edges()
				_game_music(true)
		"resume":
			if state == State.PAUSE:
				state = State.PLAY
				overlay.hide_overlay()
				_sync_action_edges()
		"settings":
			if state == State.PAUSE:
				overlay.visible = false
				menu.open_pause_settings()
		"restart":
			_restart_run()
		"menu":
			_to_menu()

func _restart_run() -> void:
	overlay.hide_overlay()
	_start_run()

func _to_menu() -> void:
	state = State.MENU
	world = null
	board.world = null
	hud.world = null
	if effects != null:
		effects.reset()
	_clear_views()
	overlay.hide_overlay()
	menu.reset()
	menu.visible = true
	board.visible = false
	actors.visible = false
	hud.visible = false
	audio.play_music("menu")

func _toggle_mute() -> void:
	muted = audio.toggle_muted()
	menu.set_muted(muted)
	hud.muted = muted
	_play_ui_click()

func _play_ui_click() -> void:
	audio.play_sfx("ui_click")

## 手柄事件自带 device：部分平台（以及 MCP 注入的输入）不会广播
## joy_connection_changed，这里把见到的设备记给输入层，供「自动」设备解析。
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		InputSettings.note_device(int(event.device))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		InputSettings.set_fullscreen(not InputSettings.fullscreen_enabled())
		get_viewport().set_input_as_handled()
		return
	if state == State.PAUSE and menu.settings_open:
		return
	# 手柄 Start：暂停 / 继续（等价于键盘 Esc / P；键位捕获时 Menu 会先吃掉事件）
	if event is InputEventJoypadButton:
		if event.pressed and int(event.button_index) == JOY_BUTTON_START \
				and InputSettings.controls_player(int(event.device)):
			if state == State.PLAY:
				_pause()
			elif state == State.PAUSE:
				_on_overlay_action("resume")
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	match state:
		State.PLAY:
			if key == KEY_ESCAPE or key == KEY_P:
				_pause()
			elif key == KEY_R:
				_restart_run()
			elif key == KEY_M:
				_toggle_mute()
			elif key == KEY_TAB:
				alt_keys = not alt_keys
				audio.play_sfx("ui_move")
		State.PAUSE:
			if key == KEY_ESCAPE or key == KEY_P:
				_on_overlay_action("resume")
			elif key == KEY_R:
				_restart_run()
			elif key == KEY_M:
				_to_menu()
		State.RESULT:
			if key == KEY_ESCAPE:
				_to_menu()
		State.BRIEFING:
			if key == KEY_ESCAPE:
				_to_menu()
		State.REPLAY:
			replay_ui.handle_key(event)

func _pause() -> void:
	state = State.PAUSE
	overlay.show_pause()
	audio.play_sfx("ui_click")

func _physics_process(delta: float) -> void:
	if state == State.REPLAY:
		if replay_ui != null:
			replay_ui.physics_step(delta)
		return
	if state != State.PLAY or world == null:
		return
	if world.match.over:
		# 原作 main.js:183-188：结算等待期间战场冻结，但特效继续推进
		if effects != null:
			effects.update(delta)
		return
	var actions = _read_actions()
	GameEngine.step(world, actions, delta)
	_drain_events()
	if effects != null:
		# GameEngine.step 开头 clear 过 world.events，所以这里每个物理帧恰好消费一次
		effects.feed(world, delta)
	_sync_views()
	_sync_bombs()
	if world.briefing and state == State.PLAY:
		state = State.BRIEFING
		overlay.show_briefing(world)
		_game_music(true)
	if world.match.over:
		_result_timer = Cfg.RESULT_DELAY

func _process(delta: float) -> void:
	if world == null:
		return
	_apply_shake()
	var alpha = Engine.get_physics_interpolation_fraction() if state == State.PLAY else 0.0
	var view_time = world.time + (alpha / 60.0 if state == State.PLAY else 0.0)
	board.anim_time = view_time
	hud.hint_alpha = maxf(0.0, hud.hint_alpha - delta * (1.0 if world.time > 12.0 else 0.0))
	for id in _views.keys():
		var v = _views[id]
		if is_instance_valid(v):
			v.update_view(alpha, view_time, delta)
	for id in _bomb_views.keys():
		var bv = _bomb_views[id]
		if not is_instance_valid(bv):
			continue
		var bomb = bv.get("bomb")
		if bomb != null:
			var bp = Grid.bomb_position(bomb)
			bv.position = Vector2.ZERO
			bv.z_index = int(bp.y) + 18
			bv.set("anim_time", view_time)
			bv.queue_redraw()
	board.queue_redraw()
	hud.queue_redraw()

	if state == State.REPLAY:
		replay_ui.update(delta)
		return

	if state == State.PLAY and world.match.over and _result_timer > 0.0:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_show_result()

	_music_clock -= delta
	if _music_clock <= 0.0:
		_music_clock = 0.5
		_game_music(false)

## 震屏：原作 main.js:262 用 ctx.translate(FX.ox, CFG.HUD_H + FX.oy) 包住整个场地内容
## （Board + Actors + FX），HUD 不晃。这里等价地把偏移加到三者的位置上。
func _apply_shake() -> void:
	if effects == null:
		return
	var off: Vector2 = effects.shake_offset()
	var base := Vector2(0.0, Cfg.HUD_H)
	board.position = base + off
	actors.position = base + off
	effects.position = base + off

func _show_result() -> void:
	if state == State.RESULT:
		return
	state = State.RESULT
	overlay.show_result(Match.summary(world))
	audio.stop_music(0.7)

func _game_music(force: bool) -> void:
	if world == null or state == State.RESULT or state == State.MENU or state == State.REPLAY:
		return
	var track = "menu"
	if state == State.PLAY or state == State.BRIEFING or state == State.PAUSE:
		if mode == "versus":
			track = "level-2" if world.theme == "factory" else "level-1"
		elif world.boss_alive():
			track = "boss-1" if int(world.match.level) <= Cfg.BOSS_EVERY else "boss-2"
		else:
			track = "level-2" if world.theme == "factory" else "level-1"
	if force or audio._current_track != track:
		audio.play_music(track)

func _clear_views() -> void:
	for id in _bomb_views.keys():
		var bv = _bomb_views[id]
		if is_instance_valid(bv):
			bv.queue_free()
	_bomb_views.clear()
	for id in _views.keys():
		var v = _views[id]
		if is_instance_valid(v):
			v.queue_free()
	_views.clear()

func _sync_views() -> void:
	if world == null:
		return
	var keep = {}
	for p in world.players:
		keep[p.id] = true
		if not _views.has(p.id):
			var v = EntityView.new()
			actors.add_child(v)
			v.setup(p, font)
			_views[p.id] = v
	for e in world.enemies:
		keep[e.id] = true
		if not _views.has(e.id):
			var v = EntityView.new()
			actors.add_child(v)
			v.setup(e, font)
			_views[e.id] = v
	for id in _views.keys():
		if not keep.has(id):
			var v = _views[id]
			if is_instance_valid(v):
				v.queue_free()
			_views.erase(id)

func _sync_bombs() -> void:
	if world == null:
		return
	var keep = {}
	for b in world.bombs:
		var id = b.get_instance_id()
		keep[id] = true
		if not _bomb_views.has(id):
			var v = Node2D.new()
			v.set_script(load("res://scripts/BombView.gd"))
			v.set("bomb", b)
			actors.add_child(v)
			_bomb_views[id] = v
	for id in _bomb_views.keys():
		if not keep.has(id):
			var v = _bomb_views[id]
			if is_instance_valid(v):
				v.queue_free()
			_bomb_views.erase(id)

func _read_actions() -> Dictionary:
	var actions = {}
	if world == null:
		return actions
	for p in world.players:
		if p.id == "p2":
			actions[p.id] = _read_player("p2", 2)
		else:
			actions[p.id] = _read_player("p1", 1)
	return actions

## A/Space used to confirm a page must be released before it can place a bomb.
func _sync_action_edges() -> void:
	if world == null:
		return
	for p in world.players:
		var profile := "versus" if mode == "versus" else ("alt" if alt_keys else "solo")
		var keys := InputSettings.poll_player(p.id, profile)
		_prev_bomb[p.id] = bool(keys["bomb"])
		_prev_skill[p.id] = bool(keys["skill"])

func _read_player(id: String, _slot: int) -> Dictionary:
	# 键位分组：1P 单人=主键位（方向键/WASD），Tab=备用键位，对战=方向键+回车/Shift；
	# 2P 恒为 WASD 一组。键盘 / 手柄 / 自动、摇杆死区都在 InputSettings 里判定，
	# 这里只把 6 个功能状态合成原来的动作字典（键名与含义不变）。
	var profile := "solo"
	if id != "p2":
		if mode == "versus":
			profile = "versus"
		elif alt_keys:
			profile = "alt"
	var keys: Dictionary = InputSettings.poll_player(id, profile)
	var left := bool(keys["left"])
	var right := bool(keys["right"])
	var up := bool(keys["up"])
	var down := bool(keys["down"])
	var bomb_now := bool(keys["bomb"])
	var skill_now := bool(keys["skill"])

	var hx = int(right) - int(left)
	var hy = int(down) - int(up)
	var p = world.player_by_id(id)
	if p != null and hx != 0 and hy != 0:
		var last: Vector2i = _last_dir.get(id, Vector2i.ZERO)
		if last.x == 0:
			p.axis_pref = "x"
		elif last.y == 0:
			p.axis_pref = "y"
	_last_dir[id] = Vector2i(hx, hy)

	var bomb_prev: bool = _prev_bomb.get(id, false)
	var skill_prev: bool = _prev_skill.get(id, false)
	_prev_bomb[id] = bomb_now
	_prev_skill[id] = skill_now
	var bomb_edge := bomb_now and not bomb_prev
	var skill_edge := skill_now and not skill_prev
	# 输入反馈：按下瞬间的短震动（设置里可关；无手柄 / 不支持时静默跳过）。
	if bomb_edge:
		InputSettings.pulse(id, "bomb")
	if skill_edge:
		InputSettings.pulse(id, "skill")
	return {
		"hx": hx, "hy": hy,
		"bomb": bomb_edge,
		"skill": skill_edge,
	}

func _drain_events() -> void:
	if world == null:
		return
	for e in world.events:
		var kind = String(e.get("kind", ""))
		match kind:
			"explode":
				audio.play_sfx("explode")
			"bomb_place":
				audio.play_sfx("bomb_place")
			"pickup":
				if String(e.get("type", "")) == "fruit":
					audio.play_sfx("fruit")
				else:
					audio.play_sfx("item_pickup")
			"death":
				audio.play_sfx("death")
			"enemy_death":
				audio.play_sfx("hurt")
			"shield_break":
				audio.play_sfx("shield_break")
			"skill":
				audio.play_sfx("skill")
			"boss_phase":
				audio.play_sfx("boss_phase")
				overlay.show_banner("鲁鲁旦 · %s阶段" % String(e.get("name", "")), "", e.get("color", Cfg.UI_RED))
			"poison":
				audio.play_sfx("poison")
			"sudden_death":
				audio.play_sfx("sudden_death")
				overlay.show_banner("死亡加速", "软砖全部消失，正面交手！", Cfg.UI_RED)
			"level_clear":
				audio.play_sfx("level_clear")
				overlay.show_banner("第 %d 关清场" % int(e.get("level", 1)), "", Cfg.UI_YELLOW)
			"scenery":
				# 子类型读 "sub"：World.emit_event() 会把 payload 的 "kind" 覆盖成事件名，
				# 原来 Scenery 传的 "kind": "fruit" 在这里永远读不到，音效与横幅都不会播。
				var scenery_kind = String(e.get("sub", ""))
				if scenery_kind == "fruit":
					audio.play_sfx("fruit")
				elif scenery_kind == "carousel":
					audio.play_sfx("carousel")
					overlay.show_banner("环游一圈", "获得一次护盾", Cfg.UI_CYAN)
			"round_started":
				overlay.show_banner("第 %d 回合" % int(e.get("round", 2)), "", Cfg.UI_CYAN)
			"match_over":
				var won = String(e.get("winner", "")) == "p1"
				audio.play_sfx("win" if won else "lose")
