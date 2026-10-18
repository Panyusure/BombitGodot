extends Node2D

## 静态地图图层：只在地图变化时重绘，由 Board 的 SubViewport 缓存成纹理。
##
## 分成两层，是为了让「炸掉一块软砖」不必把整张地图重画：
##   layer = 0（base）  ：地板 + 环路 + 硬墙 —— 同一关内**永不变化**
##   layer = 1（dest）  ：软砖 + 中央设施 + 主题边界灯串 —— 只在内容变化时重画
##
## 拆层的安全性：原作 drawMap 的顺序是「地板 → 环路 → 逐格(硬墙|软砖) → 中央设施 → 灯串」，
## 而硬墙与软砖**永远不会落在同一格**、也各自画在自己那一格内，互不重叠，
## 所以把硬墙提到软砖之前画，可见结果完全相同（这一点用 tests/verify_map_layers.gd
## 做了逐像素比对确认）。
##
## 实测（2× 超采样，森林 52 硬墙 / 39 软砖）：整张重画 45.20ms，
## 其中地板 13.71 / 硬墙 19.17 / 软砖 11.39 / 设施 1.19 —— 拆层后炸砖只需重画约 12.6ms。

var world: World = null
var layer := 0

func _draw() -> void:
	if world == null or world.map.is_empty():
		return
	# 原作 drawMap 只在 landmark 存在且主题一致时才认定「有中央设施」，
	# 并据此跳过中央 3×3 碰撞区（levelgen.isCore）；没有设施时那 3×3 也要照常画。
	var lm: Dictionary = world.landmark
	var has_landmark: bool = not lm.is_empty() and String(lm.get("theme", "")) == world.theme
	if layer == 0:
		_draw_base(lm, has_landmark)
	elif layer == 2:
		_draw_reference(lm, has_landmark)
	else:
		_draw_destructible(lm, has_landmark)

## 参考实现：完全照原作 drawMap 的单遍顺序画（地板 → 环路 → 逐格 硬墙|软砖 → 设施 → 灯串）。
## 正式渲染走 0/1 两层；这个模式只给 tests/verify_map_layers.gd 做
## 「拆层前后逐像素等价」的比对基准，不参与实际游戏渲染。
func _draw_reference(lm: Dictionary, has_landmark: bool) -> void:
	MapArt.draw_floor(self, world.theme, world.map)
	MapArt.draw_track(self, lm if has_landmark else {})
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			if has_landmark and c >= 6 and c <= 8 and r >= 5 and r <= 7:
				continue
			var v := Grid.at(world.map, c, r)
			if v == Cfg.T_HARD:
				MapArt.draw_hard(self, c, r, world.theme)
			elif v == Cfg.T_BRICK:
				var variant := int(world.brick_variants[r * Cfg.COLS + c]) if not world.brick_variants.is_empty() else 0
				MapArt.draw_brick(self, c, r, world.theme, variant)
	MapArt.draw_landmark(self, lm if has_landmark else {})
	if world.theme == "park":
		_draw_park_lights()

## 同一关内不会变化的部分。
func _draw_base(lm: Dictionary, has_landmark: bool) -> void:
	MapArt.draw_floor(self, world.theme, world.map)
	MapArt.draw_track(self, lm if has_landmark else {})
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			if has_landmark and c >= 6 and c <= 8 and r >= 5 and r <= 7:
				continue
			if Grid.at(world.map, c, r) == Cfg.T_HARD:
				MapArt.draw_hard(self, c, r, world.theme)

## 会随对局变化的部分：软砖被炸掉、中央设施（换关）、边界灯串。
func _draw_destructible(lm: Dictionary, has_landmark: bool) -> void:
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			if has_landmark and c >= 6 and c <= 8 and r >= 5 and r <= 7:
				continue
			if Grid.at(world.map, c, r) == Cfg.T_BRICK:
				var variant := int(world.brick_variants[r * Cfg.COLS + c]) if not world.brick_variants.is_empty() else 0
				MapArt.draw_brick(self, c, r, world.theme, variant)
	MapArt.draw_landmark(self, lm if has_landmark else {})
	if world.theme == "park":
		_draw_park_lights()

## 顶部边界灯串（原作画在 drawLandmark 之后，所以留在 dest 层的最上面）。
func _draw_park_lights() -> void:
	var fw := float(Cfg.FIELD_W)
	var str_pts := MapArt.quad(Vector2(12, 8), Vector2(fw * 0.5, 35), Vector2(fw - 12, 8))
	MapArt.poly_line(self, str_pts, Color("#8c718d"), 1.5)
	for k in range(1, 20):
		var xx := k * 36.0
		var yy := 8.0 + sin(k / 20.0 * PI) * 13.0
		var cols := [Color("#ffdf9a"), Color("#dcafc7"), Color("#a9e0d5")]
		draw_circle(Vector2(xx, yy), 3, cols[k % 3], true, -1.0, true)
