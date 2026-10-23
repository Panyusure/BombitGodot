extends Node2D

const Rig = preload("res://scripts/CharacterMotionRig.gd")
var _index := 0
var _walking := true
var _slow := false
var _effects := true
var _flip := false
var _time := 0.0
var _actors: Array = []
var _views: Array = []
var _ui: Node2D

func _ready() -> void:
	_ui = Node2D.new()
	_ui.z_index = 2000
	add_child(_ui)
	_ui.draw.connect(_draw_ui)
	_select(0)

func _select(index: int) -> void:
	_index = posmod(index, Rig.IDS.size())
	for view in _views:
		view.queue_free()
	_views.clear()
	_actors.clear()
	for rear in [false, true]:
		var actor: Actor = GameEngine.make_player("p1", "1P", Cfg.P1_COLOR, 0, Rig.IDS[_index])
		actor.x = 525.0 if rear else 195.0
		actor.y = 505.0
		actor.px = actor.x
		actor.py = actor.y
		actor.facing_dir = "up" if rear else "down"
		var view := EntityView.new()
		view.show_tag = false
		view.scale = Vector2.ONE * 4.0
		add_child(view)
		view.setup(actor, null)
		_actors.append(actor)
		_views.append(view)

func _process(delta: float) -> void:
	var dt := delta * (0.22 if _slow else 1.0)
	_time += dt
	for i in _actors.size():
		_actors[i].moving = _walking
		_actors[i].facing = -1 if _flip else 1
		_views[i].update_view(1.0, _time, dt)
		if _views[i]._aura != null:
			_views[i]._aura.set_visible_layers(_effects)
	_ui.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_5:
		_select(event.keycode - KEY_1)
	match event.keycode:
		KEY_TAB:
			_select(_index + 1)
		KEY_SPACE:
			_walking = not _walking
		KEY_S:
			_slow = not _slow
		KEY_A:
			_effects = not _effects
		KEY_LEFT, KEY_RIGHT:
			_flip = event.keycode == KEY_LEFT
		KEY_ESCAPE:
			get_tree().quit()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 696), Color("171b2a"))
	draw_rect(Rect2(20, 205, 330, 410), Color("242c3c"))
	draw_rect(Rect2(370, 205, 330, 410), Color("242c3c"))
	draw_line(Vector2(35, 523), Vector2(335, 523), Color("4a5c73"), 1.0)
	draw_line(Vector2(385, 523), Vector2(685, 523), Color("4a5c73"), 1.0)

func _draw_ui() -> void:
	var profile: Dictionary = Rig.Profiles.PROFILES[Rig.IDS[_index]]
	UIDraw.text(_ui, "五位精灵 · 步态设计", 28, 42, {"size": 26, "weight": 900, "fill": Color("f5ebd8")})
	UIDraw.text(_ui, "1 小诺   2 阿修   3 阿瑞   4 小炎   5 小天", 28, 84, {"size": 15, "fill": Color("a8dafa")})
	UIDraw.text(_ui, String(profile["name"]) + "  /  " + String(profile["style"]), 28, 127, {"size": 18, "fill": Color("ffe382")})
	UIDraw.text(_ui, "正面 / 左右翻转", 195, 180, {"size": 15, "align": "center", "fill": Color("c8d9ec")})
	UIDraw.text(_ui, "背面", 525, 180, {"size": 15, "align": "center", "fill": Color("c8d9ec")})
	UIDraw.text(_ui, "空格：行走 / 待机    S：慢放    A：特效    ← →：翻转", 28, 650, {"size": 13, "fill": Color("c8d9ec")})
	UIDraw.text(_ui, ("行走" if _walking else "待机附属动态") + (" · 0.22×" if _slow else "") + "    Tab切换角色 · Esc退出", 28, 678, {"size": 12, "fill": Color("8dd8ff")})
