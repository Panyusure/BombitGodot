extends Node2D

## 战场动态层：静态地图用 SubViewport 缓存，动态层绘制传送带箭头、木马、
## 毒刺、道具、火焰、技能特效与爆炸范围。炸弹由 BombView 参与角色深度排序。
##
## 静态地图分两层缓存（细节见 MapPainter.gd）：
##   base：地板 + 环路 + 硬墙 —— 换关或 BOSS 破坏硬墙时重画
##   dest：软砖 + 中央设施 + 灯串 —— 炸掉一块软砖只重画这一层
## 实测（2× 超采样，森林 52 硬墙 / 39 软砖）：整张重画 45.20ms → 炸砖只重画约 12.6ms。

var world: World = null:
	set(value):
		world = value
		_base_key = ""
		_dest_key = ""
		if _painter_base != null:
			_painter_base.world = value
			_painter_base.queue_redraw()
		if _painter_dest != null:
			_painter_dest.world = value
			_painter_dest.queue_redraw()
		if _vp_base != null:
			_vp_base.render_target_update_mode = SubViewport.UPDATE_ONCE
		if _vp_dest != null:
			_vp_dest.render_target_update_mode = SubViewport.UPDATE_ONCE
var font: Font = null
var anim_time := 0.0
var hint_alpha := 1.0

var _vp_base: SubViewport = null
var _vp_dest: SubViewport = null
var _painter_base: Node2D = null
var _painter_dest: Node2D = null
var _base_key := ""
var _dest_key := ""

func _ready() -> void:
	_vp_base = _make_layer(0, -10)
	_vp_dest = _make_layer(1, -9)

## 建一层 2× 离屏缓存。原作把静态地图画进 2× 分辨率的离屏画布（pen.scale(2,2)），
## 再 drawImage 缩回 1× 上场，细线与渐变因此得到超采样；这里用 2× SubViewport
## + 0.5 缩放贴图做等价实现。z_index 决定两层的先后（dest 压在 base 上）。
func _make_layer(layer_id: int, z: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(Cfg.FIELD_W) * 2, int(Cfg.FIELD_H) * 2)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var painter := Node2D.new()
	painter.set_script(load("res://scripts/MapPainter.gd"))
	painter.set("layer", layer_id)
	painter.scale = Vector2(2, 2)
	vp.add_child(painter)
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = vp.get_texture()
	spr.scale = Vector2(0.5, 0.5)
	spr.z_index = z
	add_child(spr)
	if layer_id == 0:
		_painter_base = painter
	else:
		_painter_dest = painter
	return vp

func _draw() -> void:
	if world == null or world.map.is_empty():
		return
	_ensure_map()
	# 层序照原作 main.js renderPlaying：drawMap（缓存 → 环路动效 → 柔光微粒）
	# → 毒刺 → 爆炸范围预览 → 道具 → 火焰 → 技能特效。
	MapArt.draw_scenery_motion(self, world.landmark, anim_time)
	_draw_motes()
	MapArt.draw_poison(self, world.poison)
	MapArt.draw_bomb_zones(self, world, anim_time)
	MapArt.draw_items(self, world.items, anim_time)
	MapArt.draw_flames(self, world.flames)
	MapArt.draw_skill_effects(self, world, anim_time)
	# 场地边框不在这里画：原作 main.js:307-308 是先 restore 掉场地缩放、
	# 再调 HUD.drawFieldFrame，也就是压在角色/粒子之上、HUD 悬浮层之下。
	# Godot 侧 Board 在 Actors 之前，画在这里会被贴边角色盖住，
	# 所以搬到 Hud.gd（CanvasLayer 在 Actors 之上）里画。

## 原作 drawMap 末尾的前景柔光微粒（sprites.js 379-386 行）：
## 没有碰撞，也不盖住炸弹与道具；fh * 10 让取模结果保持非负。
func _draw_motes() -> void:
	var fw := float(Cfg.FIELD_W)
	var fh := float(Cfg.FIELD_H)
	var fall := 4.0 if world.theme == "forest" else 2.0
	for i in 14:
		var xx := fmod(i * 97.0 + sin(anim_time * 0.3 + i) * 13.0, fw)
		var yy := fmod(i * 83.0 - anim_time * fall + fh * 10.0, fh)
		draw_circle(Vector2(xx, yy), 2.0 if i % 3 == 0 else 1.0,
			Color(255 / 255.0, 249 / 255.0, 214 / 255.0, 0.38), true, -1.0, true)

## 两层缓存的键。抽成静态纯函数是为了能**直接断言**「炸砖不动 base 键」——
## headless 测试里手动发 NOTIFICATION_DRAW 并不会真的跑 _ready/_draw
## （实测 _painter_base 仍是 null），所以断言不能建立在"绘制已经发生过"之上。
static func layer_keys(w: World) -> Array:
	var base := "%d:%d:%s:%d" % [w.map_identity, w.hard_revision, w.theme, w.map.size()]
	var dest := "%d:%d:%s:%d" % [w.map_revision, w.map_identity, w.theme, w.map.size()]
	return [base, dest]

## base 在换关或硬墙变化时重画：map_identity + hard_revision，不能用 map_revision
## —— 后者炸一块软砖就会 +1，那就退化成整张重画了。
func _ensure_map() -> void:
	var keys := layer_keys(world)
	var bkey: String = keys[0]
	var dkey: String = keys[1]
	if bkey != _base_key:
		_base_key = bkey
		_painter_base.world = world
		_painter_base.queue_redraw()
		_vp_base.render_target_update_mode = SubViewport.UPDATE_ONCE
	if dkey != _dest_key:
		_dest_key = dkey
		_painter_dest.world = world
		_painter_dest.queue_redraw()
		_vp_dest.render_target_update_mode = SubViewport.UPDATE_ONCE
