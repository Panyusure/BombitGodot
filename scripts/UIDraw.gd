class_name UIDraw
extends RefCounted

## BombIt Motion UI 绘制层：奶油纸、墨线、硬阴影、半调网点、
## 贴纸标签与圆角面板。所有坐标/配色对照原作 src/render/draw.js。

const INK := Color("141019")
const INK2 := Color("211A2B")
const CREAM := Color("F5EBD8")
const PAPER := Color("F1E4CF")
const WHITE := Color("FFFDF6")
const ORANGE := Color("FF5533")
const PINK := Color("FF5E9E")
const HOT := Color("F5233C")
const CYAN := Color("5CE1F2")
const SKY := Color("66C8FF")
const YELLOW := Color("FFD23F")
const LEMON := Color("FFE979")
const GREEN := Color("62DF88")
const RED := Color("F5233C")
const NAVY := Color("17122E")
const MUTED := Color("9A8C7A")
const FIELD_W := 720.0
const VIEW_W := 720.0
const VIEW_H := 696.0

static var _fonts := {}
static var _dot_tex := {}

static func font(family: String = "cn", weight: int = 700) -> Font:
	var key := family + ":" + str(weight)
	if _fonts.has(key):
		return _fonts[key]
	var path := "res://assets/fonts/msyh.ttc"
	match family:
		"mono":
			path = "res://assets/fonts/consolab.ttf" if weight >= 700 else "res://assets/fonts/consola.ttf"
		"impact":
			path = "res://assets/fonts/impact.ttf"
		_:
			path = "res://assets/fonts/msyhbd.ttc" if weight >= 700 else "res://assets/fonts/msyh.ttc"
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path)
	if f == null and ResourceLoader.exists("res://assets/fonts/msyh.ttc"):
		f = load("res://assets/fonts/msyh.ttc")
	_fonts[key] = f
	return f

static func measure(text: String, size: int, weight: int = 700, family: String = "cn") -> float:
	var f := font(family, weight)
	if f == null:
		return 0.0
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

static func text(ci: CanvasItem, s: String, x: float, y: float, o: Dictionary = {}) -> void:
	if s.is_empty() or ci == null:
		return
	var size := int(o.get("size", 12))
	var weight := int(o.get("weight", 700))
	var family := String(o.get("family", "cn"))
	var f := font(family, weight)
	if f == null:
		return
	var col: Color = o.get("fill", INK)
	var alpha := float(o.get("alpha", 1.0))
	col.a *= alpha
	var align := String(o.get("align", "left"))
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var dx := x
	if align == "center":
		dx -= w * 0.5
	elif align == "right":
		dx -= w
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	var dy := y + (asc - desc) * 0.5
	var ci_id := ci.get_canvas_item()
	if o.has("shadow") and o["shadow"] != null:
		var sc: Color = o["shadow"]
		sc.a *= alpha
		var sx := float(o.get("shadowX", 2))
		var sy := float(o.get("shadowY", 2))
		f.draw_string(ci_id, Vector2(dx + sx, dy + sy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, sc)
	if o.has("stroke") and o["stroke"] != null:
		var stc: Color = o["stroke"]
		stc.a *= alpha
		f.draw_string_outline(ci_id, Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			int(o.get("strokeWidth", 4)), stc)
	f.draw_string(ci_id, Vector2(dx, dy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

static func wrap(ci: CanvasItem, s: String, x: float, y: float, max_w: float,
		size: float, line_h: float, color: Color, max_lines: int = 0,
		weight: int = 500, family: String = "cn") -> int:
	var chars := s.split("")
	var lines: Array = []
	var line := ""
	var f := font(family, weight)
	if f == null:
		return 0
	for i in chars.size():
		var ch: String = chars[i]
		var test := line + ch
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x > max_w and not line.is_empty():
			lines.append(line)
			line = ch
			if max_lines > 0 and lines.size() >= max_lines - 1:
				while i < chars.size() - 1:
					var nxt := line + chars[i + 1]
					if f.get_string_size(nxt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x > max_w:
						break
					i += 1
					line = nxt
				line += "…"
				break
		else:
			line = test
	if not line.is_empty():
		lines.append(line)
	for i in lines.size():
		text(ci, lines[i], x, y + i * line_h, {
			"size": size, "weight": weight, "family": family, "fill": color,
		})
	return lines.size()

## ctx.arcTo / ctx.arc 的等价采样：按弓高容差自适应细分，不再是固定 5 段折线。
## 起点由调用方（lineTo）压入，故跳过 arc_pts 的第 0 个点。
static func _arc(points: PackedVector2Array, cx: float, cy: float, r: float, a0: float, a1: float) -> PackedVector2Array:
	var arc := CanvasArt.arc_pts(cx, cy, r, r, 0.0, a0, a1, 0.1)
	for i in range(1, arc.size()):
		points.append(arc[i])
	return points

static func rr_points(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	r = minf(r, minf(w * 0.5, h * 0.5))
	var pts := PackedVector2Array()
	pts.append(Vector2(x + r, y))
	pts.append(Vector2(x + w - r, y))
	pts = _arc(pts, x + w - r, y + r, r, -PI * 0.5, 0.0)
	pts.append(Vector2(x + w, y + h - r))
	pts = _arc(pts, x + w - r, y + h - r, r, 0.0, PI * 0.5)
	pts.append(Vector2(x + r, y + h))
	pts = _arc(pts, x + r, y + h - r, r, PI * 0.5, PI)
	pts.append(Vector2(x, y + r))
	pts = _arc(pts, x + r, y + r, r, PI, PI * 1.5)
	return pts

static func fill_rr(ci: CanvasItem, x: float, y: float, w: float, h: float, r: float, color: Color) -> void:
	if color.a <= 0.002 or w <= 0.0 or h <= 0.0:
		return
	ci.draw_colored_polygon(rr_points(x, y, w, h, r), color)

static func stroke_rr(ci: CanvasItem, x: float, y: float, w: float, h: float, r: float, color: Color, width: float = 2.0) -> void:
	var pts := rr_points(x, y, w, h, r)
	pts.append(pts[0])
	ci.draw_polyline(pts, color, width, true)

static func panel(ci: CanvasItem, x: float, y: float, w: float, h: float, o: Dictionary = {}) -> void:
	var r := float(o.get("r", 6))
	if o.has("shadow") and o["shadow"] != null:
		var sc: Color = o["shadow"]
		fill_rr(ci, x + float(o.get("shadowX", 4)), y + float(o.get("shadowY", 4)), w, h, r, sc)
	if o.has("fill") and o["fill"] != null:
		fill_rr(ci, x, y, w, h, r, o["fill"])
	if o.has("stroke") and o["stroke"] != null:
		stroke_rr(ci, x, y, w, h, r, o["stroke"], float(o.get("lw", 2)))
	if o.has("inner"):
		stroke_rr(ci, x + 3, y + 3, w - 6, h - 6, maxf(0, r - 2), o["inner"], 1.0)

static func tag(ci: CanvasItem, s: String, x: float, y: float, o: Dictionary = {}) -> Rect2:
	var size := int(o.get("size", 9))
	var weight := int(o.get("weight", 700))
	var family := String(o.get("family", "mono"))
	var pad_x := float(o.get("padX", 7))
	var h := float(o.get("h", size + 8))
	var w := float(o.get("w", measure(s, size, weight, family) + pad_x * 2))
	var align := String(o.get("align", "center"))
	var left := x - w * 0.5
	if align == "right":
		left = x - w
	elif align == "left":
		left = x
	var rot := float(o.get("rot", 0.0))
	var cx: float = left + w * 0.5
	var cy: float = y
	if absf(rot) > 0.0001:
		ci.draw_set_transform(Vector2(cx, cy), rot, Vector2.ONE)
		panel(ci, -w * 0.5, -h * 0.5, w, h, {
			"r": float(o.get("r", 3)),
			"fill": o.get("fill", YELLOW),
			"stroke": o.get("stroke", INK),
			"lw": float(o.get("lw", 1.5)),
			"shadow": o.get("shadow", null),
			"shadowX": o.get("shadowX", 4), "shadowY": o.get("shadowY", 4),
		})
		text(ci, s, 0, 0.5, {"size": size, "weight": weight, "family": family,
			"fill": o.get("fg", INK), "align": "center"})
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		panel(ci, left, y - h * 0.5, w, h, {
			"r": float(o.get("r", 3)),
			"fill": o.get("fill", YELLOW),
			"stroke": o.get("stroke", INK),
			"lw": float(o.get("lw", 1.5)),
			"shadow": o.get("shadow", null),
			"shadowX": o.get("shadowX", 4), "shadowY": o.get("shadowY", 4),
		})
		text(ci, s, left + w * 0.5, y + 0.5, {"size": size, "weight": weight,
			"family": family, "fill": o.get("fg", INK), "align": "center"})
	return Rect2(left, y - h * 0.5, w, h)

## 原作 dotPattern：step×step 的 tile，在 (step/2, step/2) 填一个 r=1 的圆（带抗锯齿），
## 再用 ctx.createPattern(cv, 'repeat') 铺满。
## createPattern 的相位锚在画布原点，所以这里按 (x mod step, y mod step) 生成带相位的 tile，
## 让同一帧里所有面板的点阵落在同一条全局网格上；覆盖率用 4×4 超采样还原圆填充的抗锯齿。
## phase_x / phase_y 以 0.5px 为单位（残差 ≤0.25px）。
static func _dot_texture(step: int, phase_x: int, phase_y: int) -> Texture2D:
	var key := "%d:%d:%d" % [step, phase_x, phase_y]
	if _dot_tex.has(key):
		return _dot_tex[key]
	var img := Image.create(step, step, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var subs := 4
	var samples := float(subs * subs)
	# tile 像素 (xx,yy) 画在画布 (x+xx, y+yy)；点阵中心在画布 step/2 + k*step 处。
	var base_x := step * 0.5 - phase_x * 0.5
	var base_y := step * 0.5 - phase_y * 0.5
	for yy in step:
		for xx in step:
			var cx: float = base_x + step * round((xx + 0.5 - base_x) / step)
			var cy: float = base_y + step * round((yy + 0.5 - base_y) / step)
			var hits := 0
			for sy in subs:
				for sx in subs:
					var dx: float = xx + (sx + 0.5) / subs - cx
					var dy: float = yy + (sy + 0.5) / subs - cy
					if dx * dx + dy * dy <= 1.0:
						hits += 1
			if hits > 0:
				img.set_pixel(xx, yy, Color(1, 1, 1, float(hits) / samples))
	var tex := ImageTexture.create_from_image(img)
	_dot_tex[key] = tex
	return tex

static func dots(ci: CanvasItem, x: float, y: float, w: float, h: float,
		color: Color, alpha: float = 0.08, step: int = 16) -> void:
	var phase_x := int(round(fposmod(x, float(step)) * 2.0))
	var phase_y := int(round(fposmod(y, float(step)) * 2.0))
	var tex := _dot_texture(step, phase_x, phase_y)
	if tex == null:
		return
	var mod := Color(color.r, color.g, color.b, alpha)
	ci.draw_texture_rect(tex, Rect2(x, y, w, h), true, mod)

static func star(ci: CanvasItem, cx: float, cy: float, r1: float, r2: float,
		color: Color, points: int = 5, rot: float = -PI * 0.5) -> void:
	# 原作 ctx.rotate(rot || -Math.PI / 2)：rot 为 0 时同样落到 -90°。
	if rot == 0.0:
		rot = -PI * 0.5
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := rot + i * PI / points
		var rr := r2 if i % 2 == 1 else r1
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	ci.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	ci.draw_polyline(pts, INK, 1.0, true)

static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)

static func heart(ci: CanvasItem, x: float, y: float, size: float,
		fill: Color = PINK, stroke: Color = INK) -> void:
	var s := size / 16.0
	var pts := PackedVector2Array()
	var curves := [
		[Vector2(0, 6), Vector2(-2, 3), Vector2(-8, 0), Vector2(-8, -4)],
		[Vector2(-8, -4), Vector2(-8, -9), Vector2(-2, -10), Vector2(0, -5)],
		[Vector2(0, -5), Vector2(2, -10), Vector2(8, -9), Vector2(8, -4)],
		[Vector2(8, -4), Vector2(8, 0), Vector2(2, 3), Vector2(0, 6)],
	]
	for curve in curves:
		# 原作在 ctx.scale(s,s) 之后 flatten，故容差按 s 折算回局部空间，等价设备空间的 0.06。
		var seg := CanvasArt.bezier(curve[0], curve[1], curve[2], curve[3], 0.06 / maxf(absf(s), 0.0001))
		for p in seg:
			pts.append(Vector2(x + p.x * s, y + p.y * s))
	ci.draw_colored_polygon(pts, fill)
	var outline := pts
	outline.append(pts[0])
	# 原作 lineWidth 1.5 写在 ctx.scale(s,s) 之内，设备空间线宽为 1.5*s。
	ci.draw_polyline(outline, stroke, 1.5 * absf(s), true)

static func bomb(ci: CanvasItem, cx: float, cy: float, r: float, rot: float = -0.08) -> void:
	# 原作 ctx.rotate(o.rot || -.08)：rot 为 0 时同样落到 -0.08。
	if rot == 0.0:
		rot = -0.08
	ci.draw_set_transform(Vector2(cx, cy), rot, Vector2.ONE)
	# 引线：同一条 bezierCurveTo 自适应细分后描两遍（先粗墨线，再细橙线）
	var fuse := CanvasArt.bezier(Vector2(r * 0.25, -r * 0.88), Vector2(r * 0.7, -r * 1.3),
		Vector2(r * 1.35, -r * 1.05), Vector2(r * 1.12, -r * 1.5))
	ci.draw_polyline(fuse, INK, maxf(2.0, r * 0.12), true)
	ci.draw_polyline(fuse, ORANGE, maxf(1.2, r * 0.06), true)
	ci.draw_circle(Vector2(r * 1.12, -r * 1.5), r * 0.28, YELLOW, true, -1.0, true)
	ci.draw_circle(Vector2(r * 1.12, -r * 1.5), r * 0.1, CREAM, true, -1.0, true)
	ci.draw_circle(Vector2.ZERO, r, INK, true, -1.0, true)
	ci.draw_circle(Vector2(-r * 0.24, -r * 0.06), r * 0.13, WHITE, true, -1.0, true)
	ci.draw_circle(Vector2(r * 0.22, -r * 0.06), r * 0.13, WHITE, true, -1.0, true)
	ci.draw_circle(Vector2(-r * 0.21, -r * 0.04), r * 0.055, INK, true, -1.0, true)
	ci.draw_circle(Vector2(r * 0.23, -r * 0.04), r * 0.055, INK, true, -1.0, true)
	ci.draw_arc(Vector2(0, r * 0.1), r * 0.16, 0.35, PI - 0.35, 16, WHITE, maxf(1.5, r * 0.04), true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func sun(ci: CanvasItem, cx: float, cy: float, r: float, color: Color, rot: float = 0.0) -> void:
	ci.draw_set_transform(Vector2(cx, cy), rot, Vector2.ONE)
	var disc := CanvasArt.circle_pts(0.0, 0.0, r)
	if disc.size() >= 3:
		ci.draw_colored_polygon(disc, color)
	# 原作 arc(0,0,r-1) + clip() 之后再描 24 条光芒。
	# 光芒都从圆心出发，被半径 r-1 的圆裁掉后剩下的就是「圆心 → r-1」这一段，
	# 这是 ctx.clip() 在这一处的解析等价，且末梢本就被墨线外圈盖住。
	var ray_r := r - 1.0
	if ray_r > 0.0:
		var ray_col := Color(CREAM.r, CREAM.g, CREAM.b, 0.18)
		for i in 24:
			var a := i * TAU / 24.0
			ci.draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * ray_r, ray_col, 2.0, true)
	CanvasArt.stroke(ci, CanvasArt.circle_pts(0.0, 0.0, r), INK, 2.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func play(ci: CanvasItem, x: float, y: float, size: float, color: Color = INK) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x - size * 0.35, y - size * 0.5),
		Vector2(x + size * 0.55, y),
		Vector2(x - size * 0.35, y + size * 0.5),
	]), color)

static func keycap(ci: CanvasItem, s: String, x: float, y: float, w: float, h: float,
		bg: Color, fg: Color) -> void:
	# 原作：只有奶油底的键帽才描墨边；非奶油底才投影，且 shadowX 走 panel 的默认 4。
	panel(ci, x, y, w, h, {"fill": bg, "stroke": INK if bg == CREAM else null, "lw": 1.5, "r": 3,
		"shadow": null if bg == CREAM else Color(0, 0, 0, 0.28), "shadowX": 4, "shadowY": 2})
	text(ci, s, x + w * 0.5, y + h * 0.5 + 0.5, {"size": int(minf(9.0, h * 0.42)),
		"weight": 700, "family": "mono", "fill": fg, "align": "center"})

static func gear(ci: CanvasItem, cx: float, cy: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var teeth := 8
	for i in teeth * 2:
		var a := -PI * 0.5 + i * PI / teeth
		var rr := 10.0 if i % 2 == 0 else 7.4
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	ci.draw_colored_polygon(pts, color)
	# 原作中心孔：hover（齿轮为黄色）时填墨色，否则填奶油色。
	ci.draw_circle(Vector2(cx, cy), 3.1, INK if color == YELLOW else CREAM, true, -1.0, true)

static func gold_frame(ci: CanvasItem, x: float, y: float, w: float, h: float) -> void:
	stroke_rr(ci, x, y, w, h, 5, INK, 3.0)


static func _clip_edge(points: PackedVector2Array, axis: int, limit: float, keep_greater: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	for i in points.size():
		var cur := points[i]
		var prev := points[(i + points.size() - 1) % points.size()]
		var cur_v := cur.x if axis == 0 else cur.y
		var prev_v := prev.x if axis == 0 else prev.y
		var cur_in := (cur_v >= limit) if keep_greater else (cur_v <= limit)
		var prev_in := (prev_v >= limit) if keep_greater else (prev_v <= limit)
		if cur_in != prev_in:
			var denom := prev_v - cur_v
			if absf(denom) > 1e-6:
				var t := (limit - cur_v) / denom
				out.append(cur.lerp(prev, t))
		if cur_in:
			out.append(cur)
	return out

static func clip_polygon(points: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := points
	out = _clip_edge(out, 0, rect.position.x, true)
	out = _clip_edge(out, 0, rect.position.x + rect.size.x, false)
	out = _clip_edge(out, 1, rect.position.y, true)
	out = _clip_edge(out, 1, rect.position.y + rect.size.y, false)
	return out
