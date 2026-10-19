class_name MapDetail
extends RefCounted

## Decorative geometry stays inside its tile and never changes collision or RNG.
## All ground and architectural detail is recorded in the static map cache.
static func ground(ci: CanvasItem, theme: String, c: int, r: int) -> void:
	var x := c * 48.0
	var y := r * 48.0
	var seed := (c * 73 + r * 31) % 19
	if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
		return
	if theme == "forest":
		# Moss islands soften the grid; pale stepping stones lead around the grove.
		if seed % 3 == 0:
			MapArt.ellipse(ci, x + 25, y + 33, 19, 9, Color("#7da66d22"))
			MapArt.ellipse(ci, x + 18, y + 30, 12, 6, Color("#eff3bc26"))
		if c == 5 or c == 9 or r == 4 or r == 8:
			var pts := PackedVector2Array([
				Vector2(x + 12, y + 19), Vector2(x + 28, y + 13),
				Vector2(x + 37, y + 23), Vector2(x + 30, y + 33), Vector2(x + 13, y + 32)])
			MapArt.poly_fill(ci, pts, Color("#718d6338"))
			_stone(ci, x, y, seed)
		elif seed % 4 == 1:
			for k in 3:
				var bx := x + 7 + k * 4
				ci.draw_line(Vector2(bx, y + 41), Vector2(bx - 2, y + 35 - k % 2 * 3), Color("#6b95674d"), 1.0, true)
		if seed == 7 or seed == 16:
			MapArt.ellipse(ci, x + 35, y + 37, 3, 1.7, Color("#8e9a7955"))
			ci.draw_line(Vector2(x + 33, y + 36), Vector2(x + 36, y + 36), Color("#f0efce99"), 1.0, true)
	elif theme == "factory":
		# Inset plates, seams, a restrained cyan service conduit and screw heads.
		MapArt.fill_rr_grad(ci, x + 4, y + 4, 40, 40, 4, Color("#e8f1ef38"), Color("#66889520"))
		ci.draw_line(Vector2(x + 7, y + 43), Vector2(x + 41, y + 43), Color("#54738033"), 1.0, true)
		if c == 2 or c == 12:
			ci.draw_line(Vector2(x + 10, y), Vector2(x + 10, y + 48), Color("#628e9d80"), 3.0, true)
			ci.draw_line(Vector2(x + 10, y), Vector2(x + 10, y + 48), Color("#cbfff0b0"), 1.0, true)
		if seed % 4 == 0:
			for dx in [8.0, 40.0]:
				ci.draw_circle(Vector2(x + dx, y + 40), 1.4, Color("#76919d"), true, -1, true)
				ci.draw_line(Vector2(x + dx - 0.7, y + 39.5), Vector2(x + dx + 0.7, y + 39.5), Color("#e5f1ef"), 0.7, true)
		if seed == 5:
			for k in 4:
				ci.draw_line(Vector2(x + 17, y + 19 + k * 3), Vector2(x + 31, y + 19 + k * 3), Color("#64848f55"), 1.0, true)
	else:
		# Porcelain biscuit paving with a warm bevel, alternating pastel inlays.
		var tint := Color("#f4d6de60") if (c + r) % 2 == 0 else Color("#d0e6df60")
		MapArt.blob(ci, x + 3, y + 4, 42, 41, 8, tint)
		UIDraw.stroke_rr(ci, x + 4, y + 5, 40, 38, 7, Color("#fff8e480"), 1.0)
		ci.draw_line(Vector2(x + 10, y + 44), Vector2(x + 38, y + 44), Color("#ac8d9a30"), 1.0, true)
		if seed % 5 == 1:
			MapArt._spirit_spark(ci, x + 12, y + 12, 3.0, Color("#fff8d4bb"))
		if seed == 4:
			for k in 3:
				ci.draw_circle(Vector2(x + 29 + k * 4, y + 35), 1, Color("#c39db066"), true, -1, true)

static func _stone(ci: CanvasItem, x: float, y: float, seed: int) -> void:
	var pts := PackedVector2Array([
		Vector2(x + 12, y + 17), Vector2(x + 28, y + 11), Vector2(x + 37, y + 21),
		Vector2(x + 30, y + 31), Vector2(x + 13, y + 30)])
	ci.draw_colored_polygon(pts, Color("#e1dfb765") if seed % 2 == 0 else Color("#ebe5c473"))
	ci.draw_polyline(PackedVector2Array([pts[4], pts[0], pts[1], pts[2]]), Color("#fff4cc70"), 1.0, true)

static func border(ci: CanvasItem, theme: String, c: int, r: int) -> void:
	var x := c * 48.0
	var y := r * 48.0
	var seed := (c * 7 + r * 11) % 5
	MapArt.blob(ci, x + 1, y + 8, 46, 39, 7, Color("#263d4938"))
	if theme == "forest":
		# A low stone plinth supports sculpted hedges rather than repeated trees.
		MapArt.fill_rr_grad(ci, x + 2, y + 26, 44, 18, 5, Color("#b7ba90"), Color("#788e70"))
		ci.draw_line(Vector2(x + 6, y + 31), Vector2(x + 42, y + 31), Color("#e0dcad"), 1.1, true)
		ci.draw_line(Vector2(x + 24, y + 32), Vector2(x + 24, y + 42), Color("#637e6855"), 1, true)
		MapArt.fill_rr_grad(ci, x + 1, y + 3, 46, 32, 11, Color("#9ac58b"), Color("#3f7962"))
		UIDraw.stroke_rr(ci, x + 1, y + 3, 46, 32, 11, Color("#376957"), 1.2)
		for k in 5:
			var lx := x + 8 + k * 7
			var ly := y + 12 + (k * 3 + seed) % 11
			MapArt.ellipse(ci, lx, ly, 4.5, 2.2, Color("#b4d49a80") if k % 2 == 0 else Color("#6fa57a99"))
		ci.draw_line(Vector2(x + 10, y + 7), Vector2(x + 31, y + 7), Color("#d7e6ad99"), 1.3, true)
		if seed == 1:
			_flower(ci, Vector2(x + 32, y + 21), Color("#ffe7cd"))
	elif theme == "factory":
		MapArt.fill_rr_grad(ci, x + 1, y + 3, 46, 40, 5, Color("#8eafb9"), Color("#3c586b"))
		UIDraw.stroke_rr(ci, x + 1, y + 3, 46, 40, 5, Color("#2e485b"), 1.5)
		MapArt.blob(ci, x + 5, y + 7, 38, 7, 2, Color("#c3d8d7"))
		MapArt.blob(ci, x + 8, y + 19, 32, 14, 3, Color("#284554"))
		for k in 4:
			ci.draw_line(Vector2(x + 13 + k * 6, y + 22), Vector2(x + 13 + k * 6, y + 29), Color("#7395a2"), 2.0, true)
		MapArt.blob(ci, x + 7, y + 37, 34, 2, 1, Color("#8ce4d1"))
		for dx in [5.0, 43.0]:
			ci.draw_circle(Vector2(x + dx, y + 38), 1.2, Color("#e7d6a6"), true, -1, true)
	else:
		MapArt.fill_rr_grad(ci, x + 2, y + 6, 44, 37, 8, Color("#edbfd1"), Color("#ad7eaa"))
		UIDraw.stroke_rr(ci, x + 2, y + 6, 44, 37, 8, Color("#926c93"), 1.3)
		MapArt.blob(ci, x + 1, y + 3, 46, 12, 5, Color("#fff0dc"), Color("#c8a0ad"), 1.0)
		for k in 4:
			MapArt.blob(ci, x + 6 + k * 11, y + 5, 6, 8, 2, Color("#e5a9c7") if (c + r) % 2 == 0 else Color("#a7d7cb"))
		MapArt.blob(ci, x + 8, y + 20, 32, 14, 5, Color("#e9cfdf"), Color("#b78faf"), 1)
		MapArt._spirit_spark(ci, x + 24, y + 27, 5, Color("#fff1b9"))
		for dx in [9.0, 39.0]:
			ci.draw_circle(Vector2(x + dx, y + 38), 2, Color("#fff2ba"), true, -1, true)

static func _flower(ci: CanvasItem, p: Vector2, col: Color) -> void:
	for k in 5:
		ci.draw_circle(p + Vector2.from_angle(k * TAU / 5) * 2.6, 2.0, col, true, -1, true)
	ci.draw_circle(p, 1.4, Color("#e3b768"), true, -1, true)

static func landmark_trim(ci: CanvasItem, theme: String) -> void:
	var x := Grid.center_x(7)
	var y := Grid.center_y(6)
	if theme == "forest":
		for i in 7:
			var px := x - 56 + i * 18
			MapArt.ellipse(ci, px, y + 56 + sin(i * 1.7) * 4, 6, 3, Color("#71946588"))
		for offset in [Vector2(-49, 48), Vector2(45, 52), Vector2(29, 61)]:
			_flower(ci, Vector2(x, y) + offset, Color("#ffe6c2"))
		for i in 9:
			var px := x - 45 + (i * 29) % 88
			var py := y - 46 + (i * 17) % 54
			MapArt.ellipse(ci, px, py, 3.2, 1.5, Color("#daebaa66"))
	elif theme == "factory":
		for dx in [-58.0, 58.0]:
			MapArt.blob(ci, x + dx - 2, y - 35, 4, 61, 2, Color("#b6f3d6"))
			for k in 4:
				ci.draw_line(Vector2(x + dx - 3, y - 29 + k * 13), Vector2(x + dx + 3, y - 29 + k * 13), Color("#385d6c"), 2.0, true)
		for dx in [-38.0, 38.0]:
			ci.draw_circle(Vector2(x + dx, y - 39), 3, Color("#e5d2a0"), true, -1, true)
			ci.draw_line(Vector2(x + dx - 1.5, y - 39), Vector2(x + dx + 1.5, y - 39), Color("#5e7985"), 1, true)
	else:
		for i in 9:
			var px := x - 52 + i * 13
			MapArt.blob(ci, px - 3, y + 42 + sin(i * PI / 8) * 9, 6, 5, 2, Color("#fff0bf"))
		for dx in [-43.0, 0.0, 43.0]:
			ci.draw_line(Vector2(x + dx - 1, y - 28), Vector2(x + dx - 1, y + 20), Color("#fff4d8aa"), 1, true)

## A few low-opacity accents, under actors and hazards, with bounded draw count.
static func atmosphere(ci: CanvasItem, theme: String, time: float) -> void:
	if theme == "forest":
		for i in 5:
			var px := 100.0 + i * 119 + sin(time * 0.16 + i * 2) * 17
			var py := fposmod(80 + i * 109 - time * 5, 516.0) + 48
			var a := 0.25 + sin(time * 1.4 + i) * 0.12
			ci.draw_circle(Vector2(px, py), 4, Color(1, 0.95, 0.63, a * 0.18), true, -1, true)
			ci.draw_circle(Vector2(px, py), 1.2, Color(1, 0.98, 0.76, a), true, -1, true)
	elif theme == "factory":
		# Steam stays over the reactor housing rather than crossing walking lanes.
		for i in 4:
			var age := fposmod(time * 0.32 + i * 0.25, 1.0)
			var px := 320.0 + (i % 2) * 80 + sin(age * 5 + i) * 4
			MapArt.ellipse(ci, px, 268 - age * 20, 3 + age * 5, 2 + age * 2, Color(0.9, 1, 0.98, sin(age * PI) * 0.16))
	else:
		for i in 8:
			var p := Vector2(301 + i * 17, 301)
			var a := 0.35 + sin(time * 2.4 - i * 0.65) * 0.25
			ci.draw_circle(p, 2.2, Color(1, 0.97, 0.72, a), true, -1, true)
