class_name MapArt
extends RefCounted

## 战场美术：按原作 src/render/sprites.js 的几何与配色重绘。
## 静态地图（地板 / 砖 / 硬墙 / 设施）由 MapPainter 缓存；动态层由 Board 绘制。

const TILE = 48.0
const TAU2 = PI * 2.0
const ArtSkin = preload("res://scripts/MapSkin.gd")

static func ellipse(ci: CanvasItem, x: float, y: float, rx: float, ry: float, color: Color) -> void:
	# 交给 CanvasArt 按弓高自适应细分；原来固定 28 段，68×28 的大椭圆会有可见折角。
	CanvasArt.ellipse_rot_fill(ci, x, y, rx, ry, 0.0, color)

static func ellipse_stroke(ci: CanvasItem, x: float, y: float, rx: float, ry: float,
		color: Color, width: float = 2.0) -> void:
	CanvasArt.ellipse_rot_stroke(ci, x, y, rx, ry, 0.0, color, width)

static func ground_shadow(ci: CanvasItem, x: float, y: float, rx: float, ry: float, alpha: float) -> void:
	ellipse(ci, x, y, rx, ry, Color(20 / 255.0, 26 / 255.0, 45 / 255.0, alpha))

static func fill_rr_grad(ci: CanvasItem, x: float, y: float, w: float, h: float, r: float,
		c_top: Color, c_bottom: Color) -> void:
	var pts = UIDraw.rr_points(x, y, w, h, r)
	var cols = PackedColorArray()
	for p in pts:
		cols.append(c_top.lerp(c_bottom, clampf((p.y - y) / maxf(1.0, h), 0.0, 1.0)))
	ci.draw_polygon(pts, cols)

static func blob(ci: CanvasItem, x: float, y: float, w: float, h: float, r: float,
		fill: Variant, stroke: Variant = null, lw: float = 2.0) -> void:
	if fill != null:
		UIDraw.fill_rr(ci, x, y, w, h, r, fill)
	if stroke != null:
		UIDraw.stroke_rr(ci, x, y, w, h, r, stroke, lw)

## 自适应曲线细分统一放在 CanvasArt；这里保留原调用名，既有调用点无需改动。
static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, tol: float = 0.06) -> PackedVector2Array:
	return CanvasArt.bezier(p0, p1, p2, p3, tol)

static func quad(p0: Vector2, p1: Vector2, p2: Vector2, tol: float = 0.06) -> PackedVector2Array:
	return CanvasArt.quad(p0, p1, p2, tol)

# ---------------- Canvas 等价的渐变与旋转椭圆（实现见 CanvasArt）----------------

static func circle_pts(cx: float, cy: float, r: float, tol: float = 0.1) -> PackedVector2Array:
	return CanvasArt.circle_pts(cx, cy, r, tol)

static func fill_gradient(ci: CanvasItem, poly: PackedVector2Array,
		p0: Vector2, p1: Vector2, stops: Array) -> void:
	CanvasArt.fill_linear_gradient(ci, poly, p0, p1, stops)

static func fill_rr_gradient(ci: CanvasItem, x: float, y: float, w: float, h: float, r: float,
		p0: Vector2, p1: Vector2, stops: Array) -> void:
	CanvasArt.fill_linear_gradient(ci, UIDraw.rr_points(x, y, w, h, r), p0, p1, stops)

static func fill_circle_gradient(ci: CanvasItem, cx: float, cy: float, r: float,
		p0: Vector2, p1: Vector2, stops: Array) -> void:
	CanvasArt.fill_linear_gradient(ci, CanvasArt.circle_pts(cx, cy, r), p0, p1, stops)

static func ellipse_rot_stroke(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float,
		rot: float, color: Color, width: float = 2.0) -> void:
	CanvasArt.ellipse_rot_stroke(ci, cx, cy, rx, ry, rot, color, width)

static func poly_fill(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, color)

static func poly_line(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float = 2.0) -> void:
	if pts.size() >= 2:
		ci.draw_polyline(pts, color, width, true)

# ---------------- 地板 ----------------

static func draw_floor(ci: CanvasItem, theme: String, map_data: Array) -> void:
	if ArtSkin.floor_map(ci, theme):
		return
	var p = Cfg.theme(theme)
	ci.draw_rect(Rect2(0, 0, Cfg.FIELD_W, Cfg.FIELD_H), p["floor"], true, -1.0, true)
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			var x = c * TILE
			var y = r * TILE
			var seed = (c * 37 + r * 61) % 17
			# 每格是 (x,y)→(x+TILE,y+TILE) 的斜向渐变：奇数格两端同色（纯 floor），偶数格 floorAlt→floor。
			fill_gradient(ci, PackedVector2Array([
					Vector2(x, y), Vector2(x + TILE, y), Vector2(x + TILE, y + TILE), Vector2(x, y + TILE),
				]), Vector2(x, y), Vector2(x + TILE, y + TILE), [
					[0.0, p["floor"] if (c + r) % 2 == 1 else p["floor_alt"]],
					[1.0, p["floor"]],
				])
			var line_col = Color(80 / 255.0, 109 / 255.0, 64 / 255.0, 0.06) if theme == "forest" \
				else Color(80 / 255.0, 95 / 255.0, 115 / 255.0, 0.12)
			ci.draw_rect(Rect2(x + 0.5, y + 0.5, TILE - 1, TILE - 1), line_col, false, 1.0, true)
			MapDetail.ground(ci, theme, c, r)
			if theme == "forest":
				if seed % 3 == 0:
					var grass = PackedVector2Array()
					grass.append_array(quad(Vector2(x + 12, y + 35), Vector2(x + 9, y + 27), Vector2(x + 7, y + 29)))
					poly_line(ci, grass, Color(90 / 255.0, 125 / 255.0, 70 / 255.0, 0.3), 1.4)
					var g2 = PackedVector2Array()
					g2.append_array(quad(Vector2(x + 12, y + 35), Vector2(x + 14, y + 25), Vector2(x + 17, y + 28)))
					poly_line(ci, g2, Color(90 / 255.0, 125 / 255.0, 70 / 255.0, 0.3), 1.4)
				if seed == 4 or seed == 12:
					for k in 5:
						ci.draw_circle(Vector2(x + 33 + cos(k * TAU2 / 5.0) * 2.6,
							y + 17 + sin(k * TAU2 / 5.0) * 2.6), 2.2,
							Color("#fff7d8") if seed == 4 else Color("#f4c8b8"), true, -1.0, true)
					ci.draw_circle(Vector2(x + 33, y + 17), 1.5, Color("#d9b764"), true, -1.0, true)
				if seed % 4 == 1:
					ellipse(ci, x + 20, y + 14, 2.0, 1.2, Color(1, 1, 0.88, 0.5))
			elif theme == "factory":
				UIDraw.stroke_rr(ci, x + 3, y + 3, 42, 42, 5, Color(248 / 255.0, 255 / 255.0, 255 / 255.0, 0.35), 1.0)
				if seed % 3 == 0:
					for dx in [8.0, 40.0]:
						ci.draw_circle(Vector2(x + dx, y + 8), 1.2, Color("#8ea6ae"), true, -1.0, true)
					ci.draw_line(Vector2(x + 12, y + 36), Vector2(x + 36, y + 12),
						Color(80 / 255.0, 113 / 255.0, 127 / 255.0, 0.17), 1.5, true)
				if (c == 4 or c == 10) and r % 3 == 1:
					poly_line(ci, PackedVector2Array([
						Vector2(x + 17, y + 25), Vector2(x + 24, y + 18), Vector2(x + 31, y + 25),
					]), Color(221 / 255.0, 175 / 255.0, 74 / 255.0, 0.55), 2.0)
			else:
				if seed % 3 == 0:
					ci.draw_set_transform(Vector2(x + 24, y + 24), PI * 0.25, Vector2.ONE)
					var cols = [Color("#e8bccc"), Color("#b9d9d4"), Color("#ddcca7")]
					UIDraw.fill_rr(ci, -6, -6, 12, 12, 3, cols[seed % 3])
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if seed % 4 == 0:
					ci.draw_rect(Rect2(x + 9, y + 12, 2, 4), Color(190 / 255.0, 146 / 255.0, 182 / 255.0, 0.38), true, -1.0, true)
					ci.draw_circle(Vector2(x + 37, y + 36), 1.5, Color("#ebc387"), true, -1.0, true)

# ---------------- 硬墙 ----------------

static func draw_hard(ci: CanvasItem, c: int, r: int, theme: String) -> void:
	if ArtSkin.hard(ci, c, r, theme):
		return
	if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
		MapDetail.border(ci, theme, c, r)
		return
	var p = Cfg.theme(theme)
	var x = c * TILE
	var y = r * TILE
	var seed = (c * 13 + r * 7) % 5
	blob(ci, x + 3, y + 8, 43, 39, 12, Color(32 / 255.0, 54 / 255.0, 56 / 255.0, 0.22))
	# 墙面渐变轴是 (x,y)→(x,y+47)，比砖块本身略高，不能按砖块高度重算。
	fill_rr_gradient(ci, x + 2, y + 3, 44, 41, 11, Vector2(x, y), Vector2(x, y + 47), [
		[0.0, p["wall"]], [1.0, p["wall_dark"]],
	])
	UIDraw.stroke_rr(ci, x + 2, y + 3, 44, 41, 11, p["wall_dark"], 1.5)
	if theme == "forest" and seed == 1:
		# 三叶簇：每片叶子 = 顶点→外侧直线 + 一次 quadraticCurveTo 收口，并单独描边。
		blob(ci, x + 19, y + 27, 10, 15, 3, Color("#ad8b5b"), Color("#6d644b"), 1)
		var sprout = [[35.0, 21.0], [27.0, 17.0], [19.0, 13.0]]
		var sprout_cols = [Color("#47866a"), Color("#62a47d"), Color("#87bb90")]
		for i in 3:
			var vy: float = sprout[i][0]
			var vw: float = sprout[i][1]
			var leaf_pts = PackedVector2Array([Vector2(x + 24, y + vy - 26), Vector2(x + 24 + vw, y + vy)])
			leaf_pts.append_array(quad(Vector2(x + 24 + vw, y + vy), Vector2(x + 24, y + vy + 6), Vector2(x + 24 - vw, y + vy)))
			poly_fill(ci, leaf_pts, sprout_cols[i])
			poly_line(ci, leaf_pts, Color("#416b56"), 1.0)
	elif theme == "forest" and seed == 3:
		blob(ci, x + 18, y + 25, 12, 17, 4, Color("#b29469"), Color("#74674d"), 1)
		var bush = [[15, 20, 12], [30, 20, 13], [23, 11, 12]]
		var cols = [Color("#96b994"), Color("#aec999"), Color("#bdd5a1")]
		for i in 3:
			ci.draw_circle(Vector2(x + bush[i][0], y + bush[i][1]), bush[i][2], cols[i], true, -1.0, true)
		for v in [[12, 17], [29, 12], [33, 24], [22, 28]]:
			ci.draw_circle(Vector2(x + v[0], y + v[1]), 3, Color("#f5d1d1"), true, -1.0, true)
			ci.draw_circle(Vector2(x + v[0], y + v[1]), 1, Color("#e6ad87"), true, -1.0, true)
	elif theme == "forest":
		# 阔叶：三条三次贝塞尔 + 一条二次贝塞尔闭合；叶片自身渐变，并描 '#49705a' 外轮廓。
		blob(ci, x + 17, y + 24, 14, 19, 4, Color("#987b56"), Color("#695b46"), 1)
		ci.draw_line(Vector2(x + 22, y + 30), Vector2(x + 21, y + 39), Color("#ba9a6c"), 1.3, true)
		var leaf = PackedVector2Array()
		leaf.append(Vector2(x + 5, y + 29))
		leaf.append_array(bezier(Vector2(x + 5, y + 29), Vector2(x - 1, y + 20), Vector2(x + 7, y + 12), Vector2(x + 13, y + 13)))
		leaf.append_array(bezier(Vector2(x + 13, y + 13), Vector2(x + 10, y - 1), Vector2(x + 34, y - 1), Vector2(x + 35, y + 11)))
		leaf.append_array(bezier(Vector2(x + 35, y + 11), Vector2(x + 48, y + 11), Vector2(x + 48, y + 30), Vector2(x + 40, y + 32)))
		leaf.append_array(quad(Vector2(x + 40, y + 32), Vector2(x + 23, y + 41), Vector2(x + 5, y + 29)))
		fill_gradient(ci, leaf, Vector2(x, y), Vector2(x, y + 35), [
			[0.0, Color("#b4cf8e") if seed % 2 == 1 else Color("#a3c58c")],
			[0.5, p["wall"]],
			[1.0, Color("#4f8063")],
		])
		poly_line(ci, leaf, Color("#49705a"), 1.5)
		# 两道高光属于同一条路径，原作一次描边；这里分两段画，颜色与线宽一致。
		for hl in [
			[Vector2(x + 9, y + 20), Vector2(x + 15, y + 15), Vector2(x + 18, y + 18)],
			[Vector2(x + 21, y + 8), Vector2(x + 28, y + 4), Vector2(x + 31, y + 11)],
		]:
			poly_line(ci, quad(hl[0], hl[1], hl[2]), Color(232 / 255.0, 246 / 255.0, 177 / 255.0, 0.6), 2.2)
		ellipse(ci, x + 33, y + 26, 4, 2, Color("#a0bd79"))
		if seed == 0:
			ci.draw_circle(Vector2(x + 14, y + 27), 2.5, Color("#e7be9a"), true, -1.0, true)
	elif theme == "factory":
		blob(ci, x + 5, y + 4, 38, 9, 4, p["top"])
		blob(ci, x + 8, y + 17, 32, 19, 4, Color("#304e60"), Color("#a0bcc7"), 1)
		if seed % 2 == 1:
			for v in 4:
				blob(ci, x + 12, y + 20 + v * 3.5, 17, 1.6, 1, Color("#7798a6"))
			ci.draw_circle(Vector2(x + 35, y + 24), 2.3, Color("#b5e7d6"), true, -1.0, true)
			ci.draw_circle(Vector2(x + 35, y + 31), 1.7, Color("#ffcd84"), true, -1.0, true)
		else:
			# 观察窗玻璃：渐变轴 (x,y+18)→(x+36,y+35)。
			fill_rr_gradient(ci, x + 12, y + 20, 24, 12, 3, Vector2(x, y + 18), Vector2(x + 36, y + 35), [
				[0.0, Color("#9edbd2")], [1.0, Color("#4e94a7")],
			])
			poly_line(ci, PackedVector2Array([
				Vector2(x + 15, y + 26), Vector2(x + 20, y + 26), Vector2(x + 23, y + 22),
				Vector2(x + 26, y + 29), Vector2(x + 32, y + 25),
			]), Color(227 / 255.0, 255 / 255.0, 247 / 255.0, 0.65), 1.5)
		for v in [[8, 10], [40, 10], [8, 39], [40, 39]]:
			ci.draw_circle(Vector2(x + v[0], y + v[1]), 1.6, Color("#d1e3e6"), true, -1.0, true)
	else:
		blob(ci, x + 6, y + 15, 36, 26, 7, Color("#b28fb4"))
		blob(ci, x + 12, y + 22, 24, 14, 5, Color("#f6dcdf"), Color("#926e98"), 1)
		var top = Rect2(x + 3, y + 4, 42, 18)
		UIDraw.fill_rr(ci, top.position.x, top.position.y, top.size.x, top.size.y, 7, Color("#f9e5dc"))
		for k in 5:
			ci.draw_rect(Rect2(x + 3 + k * 9, y + 4, 6, 18),
				Color("#a5d5d0") if k % 2 else Color("#dc9fbd"), true, -1.0, true)
		UIDraw.stroke_rr(ci, x + 3, y + 4, 42, 18, 7, Color("#9c789e"), 1.5)
		ItemIcons.draw(ci, "star", x + 24, y + 29, 11)
		ci.draw_circle(Vector2(x + 9, y + 40), 2, Color("#ffe1a4"), true, -1.0, true)
		ci.draw_circle(Vector2(x + 39, y + 40), 2, Color("#ffe1a4"), true, -1.0, true)

# ---------------- 软砖 ----------------

static func draw_brick(ci: CanvasItem, c: int, r: int, theme: String, variant: int) -> void:
	if ArtSkin.brick(ci, c, r, theme, variant):
		return
	if variant != 0:
		draw_brick_variant(ci, c, r, theme, variant)
		return
	var x = c * TILE
	var y = r * TILE
	blob(ci, x + 5, y + 9, 39, 37, 8, Color(45 / 255.0, 50 / 255.0, 56 / 255.0, 0.18))
	if theme == "forest":
		# 木箱木纹：渐变轴是 (x,y)→(x+38,y+42) 的斜向三段色阶（中点是 #c49d6b）。
		fill_rr_gradient(ci, x + 5, y + 5, 38, 37, 6, Vector2(x, y), Vector2(x + 38, y + 42), [
			[0.0, Color("#dfbc87")], [0.5, Color("#c49d6b")], [1.0, Color("#ae8358")],
		])
		UIDraw.stroke_rr(ci, x + 5, y + 5, 38, 37, 6, Color("#947451"), 1.5)
		for j in 3:
			ci.draw_line(Vector2(x + 8, y + 14 + j * 8), Vector2(x + 40, y + 14 + j * 8), Color("#b18b5e"), 1.0, true)
		blob(ci, x + 8, y + 6, 5, 34, 1, Color("#efd2a2"), Color("#b48d61"), 1)
		blob(ci, x + 35, y + 6, 5, 34, 1, Color("#efd2a2"), Color("#b48d61"), 1)
		ci.draw_line(Vector2(x + 15, y + 34), Vector2(x + 33, y + 13), Color("#efd0a0"), 4.0, true)
		for pnt in [[10, 10], [38, 10], [10, 37], [38, 37]]:
			ci.draw_circle(Vector2(x + pnt[0], y + pnt[1]), 1, Color("#755e49"), true, -1.0, true)
	elif theme == "factory":
		# 木箱渐变轴是 (x,y)→(x,y+42)。
		fill_rr_gradient(ci, x + 5, y + 5, 38, 37, 5, Vector2(x, y), Vector2(x, y + 42), [
			[0.0, Color("#e5b57f")], [1.0, Color("#bf8a63")],
		])
		UIDraw.stroke_rr(ci, x + 5, y + 5, 38, 37, 5, Color("#956e56"), 1.5)
		blob(ci, x + 7, y + 7, 34, 5, 2, Color("#f3d2a0"))
		blob(ci, x + 8, y + 28, 32, 9, 2, Color("#f1cc7d"))
		# 斜纹被裁到黄色带内（原作 ctx.clip 到 roundRect(x+8,y+28,32,9,2)），不能画到带子外面。
		var hatch_clip := UIDraw.rr_points(x + 8, y + 28, 32, 9, 2)
		for i in 5:
			CanvasArt.stroke_clipped(ci, PackedVector2Array([
				Vector2(x + 7 + i * 9, y + 38), Vector2(x + 15 + i * 9, y + 27),
			]), hatch_clip, Color("#716558"), 4.0)
		blob(ci, x + 17, y + 15, 14, 9, 2, Color("#e6dfcd"))
		ci.draw_rect(Rect2(x + 21, y + 18, 6, 2), Color("#a09684"), true, -1.0, true)
	else:
		var pink: bool = (c + r) % 2 == 0
		blob(ci, x + 6, y + 10, 36, 32, 6, Color("#dcadbd") if pink else Color("#a9cfcb"),
			Color("#b7829b") if pink else Color("#76a6a3"), 1.5)
		blob(ci, x + 4, y + 6, 40, 10, 4, Color("#f4c9d5") if pink else Color("#c6e4dc"))
		blob(ci, x + 20, y + 6, 8, 36, 1, Color("#fff0ca"))
		blob(ci, x + 6, y + 23, 36, 6, 1, Color("#fff0ca"))
		# 礼物蝴蝶结：两个 ±0.4 弧度旋转的椭圆轮廓，必须保留旋转角。
		ellipse_rot_stroke(ci, x + 18, y + 6, 7, 4, 0.4, Color("#d8b77d"), 2.0)
		ellipse_rot_stroke(ci, x + 30, y + 6, 7, 4, -0.4, Color("#d8b77d"), 2.0)

static func draw_brick_variant(ci: CanvasItem, c: int, r: int, theme: String, variant: int) -> void:
	var x = c * TILE
	var y = r * TILE
	ground_shadow(ci, x + 24, y + 40, 18, 5, 0.18)
	if theme == "forest" and variant == 1:
		blob(ci, x + 6, y + 15, 35, 23, 9, Color("#ad855b"), Color("#806749"), 1.5)
		ellipse(ci, x + 37, y + 26, 7, 12, Color("#e4c69a"))
		ellipse_stroke(ci, x + 37, y + 26, 7, 12, Color("#916f4d"), 1.0)
		ellipse(ci, x + 38, y + 26, 3, 7, Color("#725f48"))
		poly_line(ci, quad(Vector2(x + 10, y + 20), Vector2(x + 22, y + 17), Vector2(x + 31, y + 20)), Color("#d2ae7e"), 2.0)
		ci.draw_line(Vector2(x + 11, y + 31), Vector2(x + 27, y + 32), Color("#d2ae7e"), 2.0, true)
		ellipse(ci, x + 18, y + 13, 7, 3, Color("#96b87c"))
	elif theme == "forest" and variant == 3:
		ellipse(ci, x + 24, y + 39, 17, 5, Color("#c0a97e"))
		blob(ci, x + 21, y + 20, 6, 20, 2, Color("#c8a276"), Color("#9c805d"), 1)
		var cols = [Color("#c2d99c"), Color("#a8cd8f"), Color("#d0e2ab")]
		for i in 3:
			var v = [[15, 20, 10], [32, 20, 10], [24, 11, 12]][i]
			fill_circle_gradient(ci, x + v[0], y + v[1], v[2],
				Vector2(x, y + v[1] - v[2]), Vector2(x, y + v[1] + v[2]),
				[[0.0, cols[i].lightened(0.12)], [1.0, cols[i].darkened(0.13)]])
			ci.draw_arc(Vector2(x + v[0], y + v[1]), v[2], 0, TAU2, 24, Color("#91b27c"), 1.0, true)
		ci.draw_arc(Vector2(x + 23, y + 10), 6, 3.6, 5.1, 10, Color("#eff3cb"), 2.0, true)
	elif theme == "forest":
		# 蘑菇丛：可破坏的森林软障碍。伞盖 = 上半椭圆弧 + 一次 quadraticCurveTo 收口，再描边。
		for v in [[16, 29, 11, Color("#d38f78")], [32, 33, 10, Color("#d8ad78")], [26, 19, 12, Color("#d89c9a")]]:
			blob(ci, x + v[0] - 3, y + v[1] - 2, 6, 12, 3, Color("#f3e4bf"), Color("#bcab83"), 1)
			var ccx: float = x + float(v[0])
			var ccy: float = y + float(v[1]) - 4.0
			var crx := float(v[2])
			var cry := 8.0
			var cap := PackedVector2Array()
			var segs := clampi(int(ceil(PI / acos(clampf(1.0 - 0.1 / crx, -1.0, 1.0)))), 12, 180)
			for k in segs + 1:
				var a := PI + PI * float(k) / float(segs)
				cap.append(Vector2(ccx + cos(a) * crx, ccy + sin(a) * cry))
			cap.append_array(quad(Vector2(ccx + crx, ccy), Vector2(ccx, ccy + 6.0), Vector2(ccx - crx, ccy)))
			fill_gradient(ci, cap, Vector2(ccx, ccy - cry), Vector2(ccx, ccy + 4),
				[[0.0, (v[3] as Color).lightened(0.19)], [1.0, (v[3] as Color).darkened(0.1)]])
			var cap_outline := cap
			cap_outline.append(cap[0])
			poly_line(ci, cap_outline, Color("#aa826e"), 1.0)
			ci.draw_circle(Vector2(x + v[0] - 3, y + v[1] - 8), 2, Color("#fff0d6"), true, -1.0, true)
	elif theme == "factory" and variant == 1:
		fill_rr_grad(ci, x + 8, y + 11, 32, 29, 6, Color("#d0ad8b"), Color("#9e795f"))
		UIDraw.stroke_rr(ci, x + 8, y + 11, 32, 29, 6, Color("#816e5e"), 1.5)
		ellipse(ci, x + 24, y + 11, 16, 6, Color("#d6b596"))
		ellipse_stroke(ci, x + 24, y + 11, 16, 6, Color("#907762"), 1.0)
		blob(ci, x + 7, y + 16, 34, 4, 2, Color("#677d87"))
		blob(ci, x + 7, y + 32, 34, 4, 2, Color("#677d87"))
		ci.draw_circle(Vector2(x + 24, y + 26), 4, Color("#f5d68e"), true, -1.0, true)
	elif theme == "factory":
		fill_rr_grad(ci, x + 9, y + 10, 30, 31, 6, Color("#dac3a3"), Color("#aa8e76"))
		UIDraw.stroke_rr(ci, x + 9, y + 10, 30, 31, 6, Color("#8b7a65"), 1.5)
		blob(ci, x + 16, y + 5, 16, 8, 3, Color("#b7c8c4"), Color("#6c868b"), 1)
		blob(ci, x + 14, y + 17, 20, 15, 4, Color("#7ca5a1"), Color("#5a8587"), 1)
		poly_line(ci, PackedVector2Array([
			Vector2(x + 20, y + 20), Vector2(x + 27, y + 20), Vector2(x + 22, y + 28), Vector2(x + 29, y + 28),
		]), Color("#d4f2d3"), 2.0)
	elif variant == 1:
		blob(ci, x + 9, y + 29, 30, 12, 4, Color("#d4a8bf"), Color("#a77f9d"), 1)
		for v in [[15, 15, Color("#a9dcd5")], [31, 14, Color("#efb7c8")], [24, 10, Color("#eed19b")]]:
			ci.draw_line(Vector2(x + v[0], y + v[1] + 9), Vector2(x + 24, y + 33), Color("#b894b3"), 1.0, true)
			fill_gradient(ci, CanvasArt.ellipse_pts(x + v[0], y + v[1], 7, 9),
				Vector2(x + v[0] - 4, y + v[1] - 7), Vector2(x + v[0] + 5, y + v[1] + 8),
				[[0.0, (v[2] as Color).lightened(0.22)], [1.0, (v[2] as Color).darkened(0.13)]])
			ellipse_stroke(ci, x + v[0], y + v[1], 7, 9, Color("#ac8da7"), 1.0)
			ci.draw_circle(Vector2(x + v[0] - 2, y + v[1] - 3), 1.5, Color("#fff1df"), true, -1.0, true)
	else:
		blob(ci, x + 8, y + 29, 32, 13, 4, Color("#a5cfcd"), Color("#7da4ab"), 1)
		ci.draw_line(Vector2(x + 24, y + 30), Vector2(x + 24, y + 12), Color("#bd9a7b"), 3.0, true)
		for v in [[18, 17, 9], [29, 16, 10], [24, 9, 10]]:
			fill_circle_gradient(ci, x + v[0], y + v[1], v[2], Vector2(x, y), Vector2(x, y + 28),
				[[0.0, Color("#ffe5e9")], [1.0, Color("#dba4c4")]])
		ci.draw_arc(Vector2(x + 24, y + 14), 8, 0.3, 2.6, 16, Color("#d7a3ba"), 1.5, true)

# ---------------- 环路 ----------------

static func draw_track(ci: CanvasItem, lm: Dictionary) -> void:
	var path: Array = lm.get("path", [])
	if path.is_empty():
		return
	var park: bool = String(lm.get("theme", "")) == "park"
	var pts = PackedVector2Array()
	for cell in path:
		pts.append(Vector2(Grid.center_x(cell.x), Grid.center_y(cell.y)))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color("#b38ba5") if park else Color("#80b9b7"), 46.0, true)
	ci.draw_polyline(pts, Color("#ead3b9") if park else Color("#d6e9dc"), 40.0, true)
	ci.draw_polyline(pts, Color("#dec0cb") if park else Color("#8fc4c0"), 32.0, true)
	_dashed_polyline(ci, pts, Color(255 / 255.0, 246 / 255.0, 213 / 255.0, 0.42) if park
		else Color(183 / 255.0, 208 / 255.0, 206 / 255.0, 0.22), 30.0,
		3.0 if park else 2.0, 9.0 if park else 10.0)

static func _dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float,
		dash: float, gap: float) -> void:
	var drawing = true
	var remain = dash
	for i in range(pts.size() - 1):
		var a = pts[i]
		var b = pts[i + 1]
		var seg = a.distance_to(b)
		var t = 0.0
		while t < seg:
			var step = minf(remain, seg - t)
			if drawing:
				var p0 = a.lerp(b, t / seg)
				var p1 = a.lerp(b, (t + step) / seg)
				ci.draw_line(p0, p1, color, width, true)
			t += step
			remain -= step
			if remain <= 0.001:
				drawing = not drawing
				remain = dash if drawing else gap

# ---------------- 中央设施 ----------------

static func draw_landmark(ci: CanvasItem, lm: Dictionary) -> void:
	if lm.is_empty():
		return
	if ArtSkin.landmark(ci, lm):
		return
	var x = Grid.center_x(7)
	var y = Grid.center_y(6)
	ground_shadow(ci, x, y + 58, 68, 17, 0.28)
	var theme = String(lm.get("theme", "forest"))
	if theme == "forest":
		for v in [[-42, 53, 27, 11], [35, 51, 29, 12], [-17, 60, 29, 9]]:
			ellipse(ci, x + v[0], y + v[1], v[2], v[3], Color("#927353"))
		# 树干木纹：渐变轴是 (x-25,y)→(x+30,y+65) 的斜向两段色阶。
		fill_rr_gradient(ci, x - 27, y - 12, 54, 76, 17, Vector2(x - 25, y), Vector2(x + 30, y + 65), [
			[0.0, Color("#c1a16c")], [1.0, Color("#80634d")],
		])
		UIDraw.stroke_rr(ci, x - 27, y - 12, 54, 76, 17, Color("#6e6248"), 2.0)
		poly_line(ci, quad(Vector2(x - 12, y + 5), Vector2(x - 20, y + 35), Vector2(x - 10, y + 53)),
			Color("#e3c38b"), 3.0)
		poly_line(ci, quad(Vector2(x + 17, y + 8), Vector2(x + 7, y + 31), Vector2(x + 18, y + 53)),
			Color("#e3c38b"), 3.0)
		ellipse(ci, x + 1, y + 30, 11, 16, Color("#6d6149"))
		var leaves = [[-39, -13, 29], [-32, -39, 32], [2, -43, 35], [37, -30, 30], [40, 0, 27], [2, 2, 37]]
		# 树冠叶簇：六个叶团共用同一条 (x,y-68)→(x,y+22) 的三段渐变，再各自描边。
		var leaf_stops = [[0.0, Color("#d0dc9d")], [0.4, Color("#8fba7a")], [1.0, Color("#4e8565")]]
		for v in leaves:
			fill_circle_gradient(ci, x + v[0], y + v[1], v[2], Vector2(x, y - 68), Vector2(x, y + 22), leaf_stops)
			CanvasArt.ellipse_rot_stroke(ci, x + v[0], y + v[1], v[2], v[2], 0.0, Color("#4e7857"), 1.0)
		for v in [[-41, -42], [2, -59], [37, -36]]:
			ci.draw_arc(Vector2(x + v[0], y + v[1]), 12, 3.7, 5.3, 12, Color("#e1e7af"), 3.0, true)
		for v in [[-42, -10], [17, -22], [42, 0], [-5, -52]]:
			ci.draw_circle(Vector2(x + v[0], y + v[1]), 5, Color("#f0c284"), true, -1.0, true)
			ellipse(ci, x + v[0] + 3, y + v[1] - 6, 4, 2, Color("#527c51"))
	elif theme == "factory":
		# 钢壳：渐变轴是 (x-60,y-60)→(x+60,y+60) 的斜向两段色阶。
		fill_rr_gradient(ci, x - 65, y - 63, 130, 129, 17, Vector2(x - 60, y - 60), Vector2(x + 60, y + 60), [
			[0.0, Color("#b6c8c9")], [1.0, Color("#4e6c7d")],
		])
		UIDraw.stroke_rr(ci, x - 65, y - 63, 130, 129, 17, Color("#40596d"), 3.0)
		blob(ci, x - 55, y - 51, 110, 106, 11, Color("#41596a"), Color("#c3d7d4"), 2)
		ci.draw_circle(Vector2(x, y - 1), 43, Color("#a4b8bc"), true, -1.0, true)
		ci.draw_arc(Vector2(x, y - 1), 43, 0, TAU2, 48, Color("#d4e0d6"), 4.0, true)
		ci.draw_circle(Vector2(x, y - 1), 33, Color("#547e8b"), true, -1.0, true)
		# 炉心辉光：偏心内圆的径向渐变 (x-7,y-12,2)→(x,y,28)，保留中心高光偏移。
		CanvasArt.fill_radial_gradient(ci, CanvasArt.circle_pts(x, y - 1, 25),
			Vector2(x - 7, y - 12), 2.0, Vector2(x, y), 28.0,
			[[0.0, Color("#e9f7d4")], [0.5, Color("#96d2c0")], [1.0, Color("#4c97a5")]])
		for k in 4:
			var a = k * PI / 2 + 0.4
			ci.draw_circle(Vector2(x + cos(a) * 51, y + sin(a) * 51), 4, Color("#efd39b"), true, -1.0, true)
		blob(ci, x - 42, y + 48, 84, 8, 3, Color("#d8ba79"))
		for n in 5:
			ci.draw_rect(Rect2(x - 35 + n * 16, y + 49, 7, 6), Color("#5b6670"), true, -1.0, true)
	else:
		ellipse(ci, x, y + 37, 68, 28, Color("#b68b9e"))
		ellipse_stroke(ci, x, y + 37, 68, 28, Color("#886d8c"), 2.0)
		ellipse(ci, x, y + 29, 65, 27, Color("#e6c6bb"))
		ellipse_stroke(ci, x, y + 29, 65, 27, Color("#f9e0b8"), 2.0)
		for dx in [-43, 43]:
			blob(ci, x + dx - 3, y - 31, 6, 62, 3, Color("#e7c791"), Color("#a48772"), 1)
		blob(ci, x - 7, y - 53, 14, 85, 5, Color("#efd5a8"), Color("#b29581"), 1)
		for i in 8:
			var a0 = PI + i * PI / 8.0
			var a1 = PI + (i + 1) * PI / 8.0
			var tri = PackedVector2Array([
				Vector2(x, y - 64),
				Vector2(x + cos(a0) * 69, y - 13 + sin(a0) * 15),
				Vector2(x + cos(a1) * 69, y - 13 + sin(a1) * 15),
			])
			poly_fill(ci, tri, Color("#f5dfb9") if i % 2 else Color("#d5a2c1"))
		blob(ci, x - 69, y - 17, 138, 12, 6, Color("#f0c9ca"), Color("#b58b9e"), 1.5)
		for j in 10:
			ci.draw_circle(Vector2(x - 59 + j * 13, y - 11), 2.7, Color("#fff1ba"), true, -1.0, true)
		ItemIcons.draw(ci, "star", x, y - 66, 17)
	MapDetail.landmark_trim(ci, theme)

# ---------------- 动态场景 ----------------

static func draw_scenery_motion(ci: CanvasItem, lm: Dictionary, time: float) -> void:
	if lm.is_empty():
		return
	var theme = String(lm.get("theme", ""))
	var path: Array = lm.get("path", [])
	if path.is_empty():
		return
	if theme == "factory":
		for i in path.size():
			var progress = i + fmod(time * 1.65, 1.0)
			var pt = Scenery.point(path, progress)
			# Progress already identifies the segment; avoid a full path scan per arrow.
			var segment := int(floor(fposmod(progress, float(path.size()))))
			var dir := Vector2(path[(segment + 1) % path.size()] - path[segment]).normalized()
			ci.draw_set_transform(pt, dir.angle(), Vector2.ONE)
			poly_line(ci, PackedVector2Array([Vector2(-4, -5), Vector2(2, 0), Vector2(-4, 5)]),
				Color("#e8ce8c"), 2.0)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var cx = Grid.center_x(7)
		var cy = Grid.center_y(6)
		ci.draw_set_transform(Vector2(cx, cy - 1), time * 0.6, Vector2.ONE)
		ci.draw_arc(Vector2.ZERO, 19, 0.3, 2.4, 20, Color(232 / 255.0, 255 / 255.0, 222 / 255.0, 0.65), 3.0, true)
		ci.draw_arc(Vector2.ZERO, 19, 3.4, 5.5, 20, Color(232 / 255.0, 255 / 255.0, 222 / 255.0, 0.65), 3.0, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif theme == "park":
		for k in 6:
			var p = Scenery.point(path, k * path.size() / 6.0 + time * 1.8)
			var bob = sin(time * 4.0 + k) * 2.0
			_draw_horse(ci, p + Vector2(0, bob), k % 2 == 1)

static func _draw_horse(ci: CanvasItem, p: Vector2, alt: bool) -> void:
	ci.draw_line(p + Vector2(0, -24), p + Vector2(0, 12), Color("#b29177"), 2.0, true)
	blob(ci, p.x - 12, p.y - 8, 24, 14, 6, Color("#f7e3bf") if alt else Color("#b7d7d0"), Color("#b2919d"), 1)
	blob(ci, p.x + 5, p.y - 18, 9, 17, 4, Color("#f7e3bf") if alt else Color("#b7d7d0"), Color("#b2919d"), 1)
	poly_fill(ci, PackedVector2Array([p + Vector2(7, -17), p + Vector2(4, -24), p + Vector2(10, -19)]),
		Color("#b58fa8"))
	ci.draw_line(p + Vector2(-8, 3), p + Vector2(-8, 11), Color("#a7839b"), 2.0, true)
	ci.draw_line(p + Vector2(8, 3), p + Vector2(8, 11), Color("#a7839b"), 2.0, true)
	blob(ci, p.x - 5, p.y - 10, 10, 6, 2, Color("#d09bb6"))
	ci.draw_circle(p + Vector2(11, -15), 1, Color("#5b5266"), true, -1.0, true)

# ---------------- 炸弹 ----------------

static func draw_bomb(ci: CanvasItem, bomb: Bomb, time: float) -> void:
	var pos = Grid.bomb_position(bomb)
	var danger = bomb.fuse <= Cfg.FUSE_BLINK
	var pulse_speed = 22.0 if danger else 6.0
	var pulse = 1.0 + sin(time * pulse_speed) * (0.13 if danger else 0.06)
	var blink: bool = danger and sin(time * 30.0) > 0.0
	var body: Color = Color("e2503f") if blink else Color("2f2f3d")
	ground_shadow(ci, pos.x, pos.y + 15, 15, 5.5, 0.22)
	ci.draw_set_transform(pos, 0.0, Vector2(pulse, pulse))
	ci.draw_circle(Vector2.ZERO, Cfg.BOMB_RADIUS, body, true, -1.0, true)
	ci.draw_arc(Vector2.ZERO, Cfg.BOMB_RADIUS, 0, TAU2, 32, Color(0, 0, 0, 0.45), 2.0, true)
	if bomb.break_hard:
		ci.draw_arc(Vector2.ZERO, Cfg.BOMB_RADIUS + 2, 0, TAU2, 32, Color("#f6a35e"), 2.0, true)
		poly_line(ci, PackedVector2Array([
			Vector2(-3, -8), Vector2(3, -1), Vector2(-2, 2), Vector2(4, 9),
		]), Color("#ffe2a3"), 2.0)
	ellipse(ci, -5.5, -6, 5, 3.6, Color(143 / 255.0, 143 / 255.0, 168 / 255.0, 0.55))
	poly_line(ci, quad(Vector2(0, -16), Vector2(6, -24), Vector2(2, -28)), Color("#c9a227"), 3.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------- 火焰 / 道具 / 毒刺 ----------------

static func draw_flames(ci: CanvasItem, flames: Array) -> void:
	for f in flames:
		var age: float = 1.0 - float(f["t"]) / float(f["total"])
		var grow: float = age / 0.25 if age < 0.25 else 1.0
		var fade: float = 1.0 if age < 0.7 else 1.0 - (age - 0.7) / 0.3
		var alpha = clampf(fade, 0.0, 1.0)
		for cell in f["cells"]:
			var cx: float = cell.x * TILE + TILE * 0.5
			var cy: float = cell.y * TILE + TILE * 0.5
			var size = (TILE * 0.5 - 1.0) * grow
			UIDraw.fill_rr(ci, cx - size, cy - size, size * 2, size * 2, size * 0.55,
				Color(255 / 255.0, 107 / 255.0, 53 / 255.0, alpha))
			var s2 = size * 0.62
			UIDraw.fill_rr(ci, cx - s2, cy - s2, s2 * 2, s2 * 2, s2 * 0.55,
				Color(255 / 255.0, 209 / 255.0, 102 / 255.0, alpha))
			var s3 = size * 0.30
			UIDraw.fill_rr(ci, cx - s3, cy - s3, s3 * 2, s3 * 2, s3 * 0.6,
				Color(1, 1, 1, alpha))

static func draw_items(ci: CanvasItem, items: Array, time: float) -> void:
	for i in items.size():
		# 防御：for 的上界只求值一次，若数组在绘制途中被外部改动（例如调试器
		# 在 _draw 中间求值），items[i] 会越界并把整个游戏打进调试断点。
		if i >= items.size():
			break
		var it: Dictionary = items[i]
		var cx = int(it["c"]) * TILE + TILE * 0.5
		var cy = int(it["r"]) * TILE + TILE * 0.5 + sin(time * 3.0 + i) * 3.0
		var info: Dictionary = Cfg.ITEM_INFO.get(String(it["type"]), Cfg.ITEM_INFO["fire"])
		var col = Color(info["color"])
		ci.draw_circle(Vector2(cx, cy), 19, Color(col.r, col.g, col.b, 0.30 + sin(time * 4.0 + i) * 0.10), true, -1.0, true)
		ground_shadow(ci, int(it["c"]) * TILE + TILE * 0.5, int(it["r"]) * TILE + TILE - 6, 13, 4.5, 0.18)
		# 透明泡泡：偏心内圆的径向玻璃渐变 (cx-8,cy-9,1)→(cx,cy,21)，中心保持通透。
		CanvasArt.fill_radial_gradient(ci, CanvasArt.circle_pts(cx, cy, 21),
			Vector2(cx - 8, cy - 9), 1.0, Vector2(cx, cy), 21.0, [
				[0.0, Color(1, 1, 1, 0.32)],
				[0.65, Color(222 / 255.0, 247 / 255.0, 255 / 255.0, 0.08)],
				[1.0, Color(191 / 255.0, 231 / 255.0, 255 / 255.0, 0.42)],
			])
		CanvasArt.ellipse_rot_stroke(ci, cx, cy, 21, 21, 0.0, Color(245 / 255.0, 253 / 255.0, 255 / 255.0, 0.92), 1.7)
		ItemIcons.draw(ci, String(it["type"]), cx, cy + 1, 29)
		ci.draw_arc(Vector2(cx, cy), 17.5, PI * 1.12, PI * 1.48, 18,
			Color(1, 1, 1, 0.9), 3.0, true)
		ci.draw_circle(Vector2(cx + 11, cy + 12), 2, Color(1, 1, 1, 0.75), true, -1.0, true)

static func draw_poison(ci: CanvasItem, poison: Array) -> void:
	for f in poison:
		var x = int(f["c"]) * TILE
		var y = int(f["r"]) * TILE
		var warning: bool = float(f["warn"]) > 0.0
		blob(ci, x + 3, y + 3, TILE - 6, TILE - 6, 7,
			Color(255 / 255.0, 205 / 255.0, 88 / 255.0, 0.26) if warning else Color(132 / 255.0, 64 / 255.0, 172 / 255.0, 0.40),
			Color("#d79026") if warning else Color("#77509a"), 2.0)
		var cx = x + TILE * 0.5
		var cy = y + TILE * 0.5
		if warning:
			ci.draw_arc(Vector2(cx, cy), 14, 0, TAU2, 32, Color("#d79026"), 2.0, true)
			UIDraw.text(ci, "!", cx, cy, {"size": 23, "weight": 900, "family": "cn",
				"fill": Color("#9f5228"), "align": "center"})
			var prog = clampf(1.0 - float(f["warn"]) / Cfg.BOSS_POISON_WARN, 0.0, 1.0)
			ci.draw_arc(Vector2(cx, cy), 18, -PI * 0.5, -PI * 0.5 + TAU2 * prog, 32, Color("#ffe59b"), 3.0, true)
		else:
			ci.draw_line(Vector2(cx, cy + 15), Vector2(cx, cy - 14), Color("#e5ffa3"), 5.0, true)
			# 三叉的横梁是一条 quadraticCurveTo（控制点 (0,5)），不是折线。
			var trident = PackedVector2Array([Vector2(cx - 10, cy - 14), Vector2(cx - 10, cy - 3)])
			trident.append_array(CanvasArt.quad(Vector2(cx - 10, cy - 3), Vector2(cx, cy + 5), Vector2(cx + 10, cy - 3)))
			trident.append(Vector2(cx + 10, cy - 14))
			poly_line(ci, trident, Color("#e5ffa3"), 5.0)
			ci.draw_circle(Vector2(cx, cy + 15), 3, Color("#c797f3"), true, -1.0, true)

static func draw_skill_effects(ci: CanvasItem, world, time: float) -> void:
	# 减速环
	for actor in world.players + world.enemies:
		if not actor.alive or actor.soul_slow_time <= 0.0:
			continue
		var strong: bool = actor.soul_slow_rate >= 0.5
		var col = Color("#dca5ed") if strong else Color("#82cfdf")
		ellipse_stroke(ci, actor.x, actor.y + 9, 17, 6, col, 2.5 if strong else 1.5)
		for i in 3:
			var a = time * 2.0 + i * TAU2 / 3.0
			var px = actor.x + cos(a) * 19
			var py = actor.y + sin(a) * 9
			poly_fill(ci, PackedVector2Array([
				Vector2(px, py - 4), Vector2(px + 2.5, py), Vector2(px, py + 4), Vector2(px - 2.5, py),
			]), col)
	if world.time_stop != null:
		ci.draw_rect(Rect2(0, 0, Cfg.FIELD_W, Cfg.FIELD_H), Color(146 / 255.0, 196 / 255.0, 235 / 255.0, 0.10), true, -1.0, true)
		for e in world.enemies:
			if not e.alive:
				continue
			ci.draw_arc(Vector2(e.x, e.y - 8), 24, 0, TAU2, 32, Color(186 / 255.0, 233 / 255.0, 255 / 255.0, 0.85), 2.0, true)
			poly_line(ci, PackedVector2Array([
				Vector2(e.x, e.y - 25), Vector2(e.x, e.y - 15), Vector2(e.x + 6, e.y - 12),
			]), Color(186 / 255.0, 233 / 255.0, 255 / 255.0, 0.85), 2.0)
	for fx in world.skill_effects:
		var phase = 1.0 - float(fx["t"]) / float(fx["total"])
		# 原作先 ctx.globalAlpha = (1-phase)*.8，再让各子函数用自带 alpha 的颜色绘制，
		# 两者相乘才是最终透明度，所以这里统一用 _ga() 折算。
		var ga = (1.0 - phase) * 0.8
		var t = String(fx["type"])
		if t == "soul_pulse":
			_soul_pulse(ci, fx, phase, ga)
		elif t == "soul_awaken":
			# 原作按 ownerId 找施法者，跟着施法者当前位置画；施法者没了就整段不画。
			var caster = null
			for pl in world.players:
				if String(pl.id) == String(fx.get("owner", "")):
					caster = pl
					break
			if caster != null and caster.alive:
				_soul_awaken(ci, caster.x, caster.y, phase, ga)
		elif t == "flame_reflect":
			_flame_reflect(ci, fx, phase, ga)
		elif t == "axiu":
			ci.draw_line(Vector2(fx["x"], float(fx["y"]) - 10),
				Vector2(fx["to_x"], float(fx["to_y"]) - 10),
				_ga(fx["color"], ga), 13.0 * (1.0 - phase) + 2.0, true)
		else:
			var c = _ga(fx["color"], ga)
			var rr = 16.0 + phase * (96.0 if t == "arui" else 48.0)
			CanvasArt.ellipse_rot_stroke(ci, fx["x"], float(fx["y"]) - 6, rr, rr, 0.0, c,
				4.0 * (1.0 - phase) + 1.0)
			var rr2 = 11.0 + phase * 40.0
			CanvasArt.ellipse_rot_stroke(ci, fx["x"], float(fx["y"]) - 6, rr2, rr2, 0.0, c, 1.0)

## globalAlpha 与颜色自带 alpha 相乘。
static func _ga(c: Color, ga: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * ga)

## 原作 sprites.spiritSpark：八角星，8 个顶点按 size 与 0.32 比例排布。
static func _spirit_spark(ci: CanvasItem, x: float, y: float, size: float, color: Color) -> void:
	poly_fill(ci, PackedVector2Array([
		Vector2(x, y - size), Vector2(x + size * 0.32, y - size * 0.32),
		Vector2(x + size, y), Vector2(x + size * 0.32, y + size * 0.32),
		Vector2(x, y + size), Vector2(x - size * 0.32, y + size * 0.32),
		Vector2(x - size, y), Vector2(x - size * 0.32, y - size * 0.32),
	]), color)

## 被 scale/rotate 变换过的八角星：先绕原点旋转，再按 sy 压扁，最后平移到 origin。
static func _spark_xform(ci: CanvasItem, origin: Vector2, c: Vector2, size: float,
		color: Color, rot: float, sy: float) -> void:
	var ca := cos(rot)
	var sa := sin(rot)
	var offs = [Vector2(0, -1), Vector2(0.32, -0.32), Vector2(1, 0), Vector2(0.32, 0.32),
		Vector2(0, 1), Vector2(-0.32, 0.32), Vector2(-1, 0), Vector2(-0.32, -0.32)]
	var out := PackedVector2Array()
	for o in offs:
		var q: Vector2 = c + (o as Vector2) * size
		var rp := Vector2(q.x * ca - q.y * sa, q.x * sa + q.y * ca)
		out.append(origin + Vector2(rp.x, rp.y * sy))
	poly_fill(ci, out, color)

## Canvas setLineDash 的圆弧版本，含 lineDashOffset 相位。
## 虚线弧：整圈只发一次 draw_multiline。
## 早先每段虚线单独 draw_polyline，半径 150 的一圈就是 80 次绘制调用；
## 未来连发炸弹时同时存在 3~4 个脉动特效，光这一项就吃掉好几毫秒。
static func _dashed_arc(ci: CanvasItem, cx: float, cy: float, r: float, color: Color,
		width: float, dash: float, gap: float, offset: float) -> void:
	if r <= 0.0 or color.a <= 0.0:
		return
	var circ := TAU * r
	var period := dash + gap
	if period <= 0.0:
		return
	# 虚线段只有几像素长，用弦代替弧肉眼无差；相位取模保证首尾同相位。
	var t := -fposmod(offset, period)
	var pts := PackedVector2Array()
	while t < circ:
		var d0 := maxf(t, 0.0)
		var d1 := minf(t + dash, circ)
		if d1 > d0:
			var a0 := d0 / r
			var a1 := d1 / r
			pts.append(Vector2(cx + cos(a0) * r, cy + sin(a0) * r))
			pts.append(Vector2(cx + cos(a1) * r, cy + sin(a1) * r))
		t += period
	if pts.size() >= 4:
		ci.draw_multiline(pts, color, width)

## 原作 sprites.drawSoulPulse：脉动方框 + 径向辉光 + 三圈（中间一圈虚线）+ 双旋臂 + 星屑。
static func _soul_pulse(ci: CanvasItem, fx: Dictionary, phase: float, ga: float) -> void:
	var radius: float = float(fx.get("radius", 1))
	var evolved: bool = bool(fx.get("evolved", false))
	var side: float = (radius * 2.0 + 1.0) * TILE
	var half: float = side * 0.5 - 3.0
	var fx_x: float = fx["x"]
	var fx_y: float = fx["y"]
	var box := UIDraw.rr_points(fx_x - half, fx_y - half, half * 2.0, half * 2.0, 12.0)
	UIDraw.fill_rr(ci, fx_x - half, fx_y - half, half * 2.0, half * 2.0, 12.0,
		_ga(Color(224 / 255.0, 171 / 255.0, 242 / 255.0, 0.14) if evolved
			else Color(139 / 255.0, 232 / 255.0, 249 / 255.0, 0.13), ga))
	CanvasArt.stroke(ci, box, _ga(fx["color"], ga), 2.0, true)
	CanvasArt.fill_radial_gradient(ci, box, Vector2(fx_x, fx_y), 2.0, Vector2(fx_x, fx_y), half, [
		[0.0, Color(255 / 255.0, 238 / 255.0, 255 / 255.0, 0.6) if evolved
			else Color(217 / 255.0, 253 / 255.0, 255 / 255.0, 0.5)],
		[1.0, Color(135 / 255.0, 223 / 255.0, 252 / 255.0, 0.0)],
	], Color(1, 1, 1, ga))
	for ring in 3:
		var rr: float = 8.0 + (half - 8.0) * minf(1.0, phase * 1.6 + ring * 0.18)
		var rc := _ga(Color("#edb7f4") if ring % 2 == 1 else Color("#a5efff"), ga)
		if ring == 1:
			_dashed_arc(ci, fx_x, fx_y, rr, rc, 1.2, 3.0, 8.0, -phase * 45.0)
		else:
			CanvasArt.ellipse_rot_stroke(ci, fx_x, fx_y, rr, rr, 0.0, rc, 2.8 if ring == 0 else 1.2)
	for arm in 2:
		var pts := PackedVector2Array()
		for step in 25:
			var tt := float(step) / 24.0
			var angle := tt * TAU2 + phase * 4.0 + arm * PI
			var rad := 8.0 + tt * half * 0.82
			pts.append(Vector2(fx_x + cos(angle) * rad, fx_y + sin(angle) * rad))
		CanvasArt.stroke(ci, pts, _ga(Color("#eebff2") if arm == 1 else Color("#b5f7ff"), ga), 1.4, false)
	var spark_n := 16 if evolved else 10
	for spark in spark_n:
		var theta := spark * 2.399 + phase * 1.4
		var sr := (0.3 + (spark % 5) * 0.13) * half
		_spirit_spark(ci, fx_x + cos(theta) * sr, fx_y + sin(theta) * sr, 2.0 + float(spark % 3),
			_ga(Color("#ffe0fb") if spark % 2 == 1 else Color("#cfffff"), ga))

## 原作 sprites.drawFlameReflect：火焰方框 + 径向辉光 + 扩张圆 + 虚线圆 + 星屑。
static func _flame_reflect(ci: CanvasItem, fx: Dictionary, phase: float, ga: float) -> void:
	var radius: float = float(fx.get("radius", 2))
	var side: float = (radius * 2.0 + 1.0) * TILE
	var half: float = side * 0.5 - 3.0
	var fx_x: float = fx["x"]
	var fx_y: float = fx["y"]
	var box := UIDraw.rr_points(fx_x - half, fx_y - half, half * 2.0, half * 2.0, 12.0)
	UIDraw.fill_rr(ci, fx_x - half, fx_y - half, half * 2.0, half * 2.0, 12.0,
		_ga(Color(255 / 255.0, 150 / 255.0, 70 / 255.0, 0.14), ga))
	CanvasArt.stroke(ci, box, _ga(fx["color"], ga), 2.0, true)
	CanvasArt.fill_radial_gradient(ci, box, Vector2(fx_x, fx_y), 3.0, Vector2(fx_x, fx_y), half, [
		[0.0, Color(255 / 255.0, 236 / 255.0, 180 / 255.0, 0.55)],
		[1.0, Color(255 / 255.0, 110 / 255.0, 40 / 255.0, 0.0)],
	], Color(1, 1, 1, ga))
	var grow: float = half * minf(1.0, phase * 1.35)
	CanvasArt.ellipse_rot_stroke(ci, fx_x, fx_y, grow, grow, 0.0, _ga(Color("#ffd08a"), ga),
		3.0 * (1.0 - phase) + 1.0)
	_dashed_arc(ci, fx_x, fx_y, half * 0.62, _ga(fx["color"], ga), 1.4, 4.0, 7.0, -phase * 40.0)
	for spark in 10:
		var theta := spark * 2.399 + phase * 2.0
		var sr := (0.35 + (spark % 5) * 0.13) * half
		_spirit_spark(ci, fx_x + cos(theta) * sr, fx_y + sin(theta) * sr, 2.0 + float(spark % 3),
			_ga(Color("#ffe6a8") if spark % 2 == 1 else Color("#ff9a4d"), ga))

## 原作 sprites.drawSoulAwaken：光柱 + 三层斜压法阵 + 十二星屑 + 五道引灵曲线 + 双旋光弧。
static func _soul_awaken(ci: CanvasItem, x: float, y: float, phase: float, ga: float) -> void:
	var power := sin(PI * phase)
	# 渐变轴是局部 (0,-145)→(0,20)，即世界 (x,y-145)→(x,y+20)。
	CanvasArt.fill_linear_gradient(ci, PackedVector2Array([
		Vector2(x - 10.0 - power * 18.0, y + 16.0),
		Vector2(x - 30.0 - power * 12.0, y - 145.0),
		Vector2(x + 30.0 + power * 12.0, y - 145.0),
		Vector2(x + 10.0 + power * 18.0, y + 16.0),
	]), Vector2(x, y - 145.0), Vector2(x, y + 20.0), [
		[0.0, Color(155 / 255.0, 235 / 255.0, 255 / 255.0, 0.0)],
		[0.55, Color(204 / 255.0, 249 / 255.0, 255 / 255.0, 0.2)],
		[1.0, Color(244 / 255.0, 207 / 255.0, 255 / 255.0, 0.45)],
	], Color(1, 1, 1, ga))
	# translate(0,12) → scale(1,.36) → rotate(phase*2)：三个同心圆变成压扁并旋转的椭圆。
	var origin := Vector2(x, y + 12.0)
	var radii := [34.0, 48.0, 62.0]
	for i in 3:
		var rr: float = radii[i] + power * 14.0
		var col := Color("#edb8fa") if i % 2 == 1 else Color("#b3f6ff")
		CanvasArt.ellipse_rot_stroke(ci, origin.x, origin.y, rr, rr * 0.36, phase * 2.0,
			_ga(col, ga), 3.0 if i == 1 else 1.5)
	for glyph in 12:
		var a := glyph * TAU2 / 12.0
		_spark_xform(ci, origin, Vector2(cos(a) * 59.0, sin(a) * 59.0), 4.0,
			_ga(Color("#eaffff"), ga), phase * 2.0, 0.36)
	var soul_cols = [Color("#9cefff"), Color("#f3b9ef"), Color("#d6c2ff"),
		Color("#fff0b0"), Color("#b8ffdf")]
	for soul in 5:
		var angle := soul * TAU2 / 5.0 + phase * 7.0
		var orbit := 18.0 + 75.0 * pow(1.0 - phase, 1.5)
		var sx := cos(angle) * orbit
		var sy := -40.0 + sin(angle) * orbit * 0.65
		var trail = PackedVector2Array([Vector2(x + sx, y + sy)])
		trail.append_array(CanvasArt.quad(Vector2(x + sx, y + sy),
			Vector2(x + sx * 0.6, y - 30.0), Vector2(x + sx * 0.12, y - 28.0)))
		CanvasArt.stroke(ci, trail, _ga(soul_cols[soul], ga), 2.0, false)
		_spirit_spark(ci, x + sx, y + sy, 5.0 + power * 3.0, _ga(soul_cols[soul], ga))
	for halo in 2:
		var a0 := phase * TAU2 + halo * PI
		CanvasArt.stroke(ci, CanvasArt.arc_pts(x, y - 45.0, 48.0 + phase * 37.0, 66.0 + power * 22.0,
			(-0.3 if halo == 1 else 0.3), a0, a0 + PI * 1.2, 0.12),
			_ga(Color("#f1c2ff") if halo == 1 else Color("#a8f4ff"), ga), 2.5, false)

static func draw_bomb_zones(ci: CanvasItem, world, time: float) -> void:
	var insight = false
	for p in world.players:
		if p.alive and p.asset_id == "xiaotian" and p.insight_time > 0.0:
			insight = true
			break
	if not insight:
		return
	for b in world.bombs:
		var geo = Rules.bomb_cells(world, b)
		var urgency = 1.0 - maxf(0.0, b.fuse) / b.fuse_total
		var danger = b.fuse <= Cfg.FUSE_BLINK
		for cell in geo["cells"]:
			var alpha = (0.52 if sin(time * 24.0) > 0.0 else 0.32) if danger else 0.30 + urgency * 0.16
			var col = Color(93 / 255.0, 199 / 255.0, 230 / 255.0, alpha)
			UIDraw.fill_rr(ci, cell.x * TILE + 3, cell.y * TILE + 3, TILE - 6, TILE - 6, 9, col)
			UIDraw.stroke_rr(ci, cell.x * TILE + 3, cell.y * TILE + 3, TILE - 6, TILE - 6, 9,
				Color(1, 1, 1, minf(1.0, alpha * 1.7)), 2.5)
