class_name CanvasArt
extends RefCounted

## Canvas 2D 等价图元层。
##
## 移植过程中最容易出现"等价简化"的四类绘制，在这里按原作的语义精确重建：
##   1. createLinearGradient —— 保留任意渐变轴、任意色阶（含中间停靠点）；
##   2. createRadialGradient —— 按规范解双圆锥面参数，保留偏心内圆的高光；
##   3. quadraticCurveTo / bezierCurveTo / arc —— 自适应细分，不做直折线近似；
##   4. ctx.ellipse(..., rotation, ...) —— 保留旋转角。
##
## 渐变用"渐变轴映射到 UV + 逐像素采样纹理"实现：UV 关于坐标是仿射的，
## 三角形内插后逐像素采样就等价于 Canvas 的逐像素渐变，不会在色阶处出现色带断层。

# ============================================================
# 曲线
# ============================================================

## Canvas 压平曲线用的是"控制点到弦的距离"判据，这里用同样判据做自适应细分。
## 默认容差 0.06px，比浏览器更细，肉眼即真实路径。
static func _flat_enough(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, tol: float) -> bool:
	var chord := p3 - p0
	var d := chord.length()
	if d < 0.0001:
		return maxf(p1.distance_to(p0), p2.distance_to(p0)) <= tol
	var n := Vector2(-chord.y, chord.x) / d
	return maxf(absf((p1 - p0).dot(n)), absf((p2 - p0).dot(n))) <= tol

static func _bezier_rec(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		tol: float, depth: int) -> void:
	if depth >= 12 or _flat_enough(p0, p1, p2, p3, tol):
		out.append(p3)
		return
	var p01 := (p0 + p1) * 0.5
	var p12 := (p1 + p2) * 0.5
	var p23 := (p2 + p3) * 0.5
	var p012 := (p01 + p12) * 0.5
	var p123 := (p12 + p23) * 0.5
	var mid := (p012 + p123) * 0.5
	_bezier_rec(out, p0, p01, p012, mid, tol, depth + 1)
	_bezier_rec(out, mid, p123, p23, p3, tol, depth + 1)

## ctx.bezierCurveTo 的等价点集（含起点）。
static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, tol: float = 0.06) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(p0)
	_bezier_rec(out, p0, p1, p2, p3, tol, 0)
	return out

## ctx.quadraticCurveTo 的等价点集（升阶成三次，是同一条曲线）。
static func quad(p0: Vector2, p1: Vector2, p2: Vector2, tol: float = 0.06) -> PackedVector2Array:
	return bezier(p0, p0 + (p1 - p0) * (2.0 / 3.0), p2 + (p1 - p2) * (2.0 / 3.0), p2, tol)

## 按弓高容差决定段数，等价 Canvas 的 arc 细分。
static func _segs_for(r: float, tol: float) -> int:
	if r <= tol:
		return 12
	return clampi(int(ceil(PI / acos(clampf(1.0 - tol / r, -1.0, 1.0)))), 12, 200)

## ctx.arc / ctx.ellipse 的等价点集。rot 为椭圆自身旋转角，与 Canvas 参数顺序一致。
static func arc_pts(cx: float, cy: float, rx: float, ry: float, rot: float = 0.0,
		a0: float = 0.0, a1: float = TAU, tol: float = 0.1) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if rx <= 0.0 or ry <= 0.0:
		return pts
	var span := absf(a1 - a0)
	var segs := maxi(2, int(ceil(_segs_for(maxf(rx, ry), tol) * span / TAU)))
	var ca := cos(rot)
	var sa := sin(rot)
	for i in segs + 1:
		var a := a0 + (a1 - a0) * float(i) / float(segs)
		var px := cos(a) * rx
		var py := sin(a) * ry
		pts.append(Vector2(cx + px * ca - py * sa, cy + px * sa + py * ca))
	return pts

static func circle_pts(cx: float, cy: float, r: float, tol: float = 0.1) -> PackedVector2Array:
	var pts := arc_pts(cx, cy, r, r, 0.0, 0.0, TAU, tol)
	if pts.size() > 1 and pts[0].is_equal_approx(pts[pts.size() - 1]):
		pts.remove_at(pts.size() - 1)
	return pts

static func ellipse_pts(cx: float, cy: float, rx: float, ry: float, rot: float = 0.0,
		tol: float = 0.1) -> PackedVector2Array:
	var pts := arc_pts(cx, cy, rx, ry, rot, 0.0, TAU, tol)
	if pts.size() > 1 and pts[0].is_equal_approx(pts[pts.size() - 1]):
		pts.remove_at(pts.size() - 1)
	return pts

# ============================================================
# 渐变
# ============================================================

static var _lin_cache := {}
static var _rad_cache := {}

## 色阶求值：stops = [[offset, Color], ...]，offset 递增。
static func grad_stops_color(t: float, stops: Array) -> Color:
	if stops.is_empty():
		return Color(0, 0, 0, 1)
	if t <= float(stops[0][0]):
		return stops[0][1]
	for i in range(stops.size() - 1):
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var ta := float(a[0])
		var tb := float(b[0])
		if t <= tb:
			if tb - ta <= 0.000001:
				return b[1]
			return (a[1] as Color).lerp(b[1], (t - ta) / (tb - ta))
	return stops[stops.size() - 1][1]

static func _stops_key(stops: Array) -> String:
	var key := ""
	for s in stops:
		key += "%f|%s;" % [float(s[0]), (s[1] as Color).to_html()]
	return key

static func _make_gradient(stops: Array) -> Gradient:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	return g

## createLinearGradient(p0, p1) 的等价纹理：横向色带，U 对应渐变轴参数。
static func _linear_texture(stops: Array) -> Texture2D:
	var key := _stops_key(stops)
	if _lin_cache.has(key):
		return _lin_cache[key]
	var tex := GradientTexture2D.new()
	tex.gradient = _make_gradient(stops)
	tex.width = 256
	tex.height = 8
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.repeat = GradientTexture2D.REPEAT_NONE
	_lin_cache[key] = tex
	return tex

## 双圆径向渐变在点 p 处的参数 t，按 Canvas 规范解锥面方程：
## 求 t 使圆 (c0 + t·dc, r0 + t·dr) 恰好过 p。
static func radial_t(p: Vector2, c0: Vector2, r0: float, c1: Vector2, r1: float) -> float:
	var d := p - c0
	var dc := c1 - c0
	var dr := r1 - r0
	var a := dc.length_squared() - dr * dr
	var b := -2.0 * (d.dot(dc) + r0 * dr)
	var c := d.length_squared() - r0 * r0
	var roots: Array[float] = []
	if absf(a) < 0.000001:
		if absf(b) > 0.000001:
			roots.append(-c / b)
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			roots.append((-b + sq) / (2.0 * a))
			roots.append((-b - sq) / (2.0 * a))
	var best := -1.0
	for t in roots:
		if t >= 0.0 and t <= 1.0:
			best = t if best < 0.0 else maxf(best, t)
	if best >= 0.0:
		return best
	# 锥面外：内圆之内取 0，外圆之外取 1。
	return 0.0 if c < 0.0 else 1.0

## createRadialGradient(c0, r0, c1, r1) 的等价纹理。
##
## 关键：纹理只描述**形状**，与摆放位置无关——把整条渐变按外圆半径归一化
## （外圆半径 = 1，内圆中心相对外圆中心的偏移 = (c0-c1)/r1，内圆半径 = r0/r1）。
## 归一化不改变渐变参数 t：把二次方程的 a/b/c 三个系数同乘 r1² 即可验证根不变。
## 采样端 UV 仍是 (p-c1)/r1*0.5+0.5，映射关系不变，因此画面完全等价。
##
## 早期版本把**绝对坐标**写进了缓存键，于是每个新位置都要重算一张纹理：
## soul_pulse(radius=2) 单次 132ms（≈8 帧），道具泡泡因为中心随呼吸抖动更是**每帧**重建 4.6ms。
## 归一化之后这些形状各只算一次，缓存条目数也从"随位置无限增长"变成常数。
static func _radial_texture(c0: Vector2, r0: float, c1: Vector2, r1: float, stops: Array) -> Texture2D:
	if r1 <= 0.0 or stops.is_empty():
		return null
	var off := (c0 - c1) / r1
	var r0n := r0 / r1
	var res := clampi(int(ceil(r1 * 3.0)), 16, 160)
	var key := "%.4f|%.4f|%.4f|%d|%s" % [off.x, off.y, r0n, res, _stops_key(stops)]
	if _rad_cache.has(key):
		return _rad_cache[key]
	# 用 PackedByteArray 直接写字节再一次性建图：比逐像素 set_pixel 快数倍。
	var buf := PackedByteArray()
	buf.resize(res * res * 4)
	var concentric := absf(off.x) < 0.0005 and absf(off.y) < 0.0005
	var inv := 1.0 / float(res)
	var idx := 0
	for j in res:
		var qy := (float(j) + 0.5) * inv * 2.0 - 1.0
		for i in res:
			var qx := (float(i) + 0.5) * inv * 2.0 - 1.0
			var t: float
			if concentric:
				# 同心时 t 退化成 |q| 的一元函数，省掉二次方程与开方之外的全部开销
				var d := sqrt(qx * qx + qy * qy)
				t = clampf((d - r0n) / maxf(0.0001, 1.0 - r0n), 0.0, 1.0)
			else:
				t = radial_t(Vector2(qx, qy), off, r0n, Vector2.ZERO, 1.0)
			var col := grad_stops_color(t, stops)
			buf[idx] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			buf[idx + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			buf[idx + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			buf[idx + 3] = int(clampf(col.a, 0.0, 1.0) * 255.0)
			idx += 4
	var tex := ImageTexture.create_from_image(
		Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, buf))
	# 安全阀：正常用法下形状只有个位数（同心光晕 / 道具泡泡 / 炉心辉光各一），
	# 这里只是防止异常输入把纹理缓存吃爆。
	if _rad_cache.size() > 64:
		_rad_cache.clear()
	_rad_cache[key] = tex
	return tex

## 用 p0→p1 渐变轴填充任意多边形。
static func fill_linear_gradient(ci: CanvasItem, poly: PackedVector2Array,
		p0: Vector2, p1: Vector2, stops: Array, tint: Color = Color(1, 1, 1, 1)) -> void:
	if poly.size() < 3 or stops.is_empty():
		return
	var axis := p1 - p0
	var len2 := axis.length_squared()
	if len2 <= 0.000001:
		ci.draw_colored_polygon(poly, Color(stops[0][1], (stops[0][1] as Color).a * tint.a))
		return
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for p in poly:
		uvs.append(Vector2((p - p0).dot(axis) / len2, 0.5))
		cols.append(tint)
	ci.draw_polygon(poly, cols, uvs, _linear_texture(stops))

## 用 (c0,r0)→(c1,r1) 双圆径向渐变填充任意多边形，保留偏心内圆高光。
## tint 是整体调色（通常只带 alpha）：色阶本身不要掺入每帧变化的透明度，
## 否则缓存键每帧都变，会退化成「每帧重建一张 160x160 的纹理」。
static func fill_radial_gradient(ci: CanvasItem, poly: PackedVector2Array,
		c0: Vector2, r0: float, c1: Vector2, r1: float, stops: Array,
		tint: Color = Color(1, 1, 1, 1)) -> void:
	if poly.size() < 3 or stops.is_empty() or r1 <= 0.0:
		return
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for p in poly:
		uvs.append((p - c1) / r1 * 0.5 + Vector2(0.5, 0.5))
		cols.append(tint)
	ci.draw_polygon(poly, cols, uvs, _radial_texture(c0, r0, c1, r1, stops))

# ============================================================
# 描边 / 填充
# ============================================================

## 闭合描边（Canvas 的 stroke() 默认圆角连接由 polyline 的 antialiased 覆盖）。
static func stroke(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float = 2.0,
		closed: bool = false) -> void:
	if pts.size() < 2 or color.a <= 0.0 or width <= 0.0:
		return
	var line := pts
	if closed and not line[0].is_equal_approx(line[line.size() - 1]):
		line = line.duplicate()
		line.append(line[0])
	ci.draw_polyline(line, color, width, true)

## ctx.ellipse(x, y, rx, ry, rot, 0, TAU) + stroke()
static func ellipse_rot_stroke(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float,
		rot: float, color: Color, width: float = 2.0) -> void:
	stroke(ci, ellipse_pts(cx, cy, rx, ry, rot), color, width, true)

## ctx.ellipse(x, y, rx, ry, rot, 0, TAU) + fill()
static func ellipse_rot_fill(ci: CanvasItem, cx: float, cy: float, rx: float, ry: float,
		rot: float, color: Color) -> void:
	var pts := ellipse_pts(cx, cy, rx, ry, rot)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, color)

## ctx.arc(x, y, r, a0, a1) + stroke()（不闭合，用于高光弧）
static func arc_stroke(ci: CanvasItem, cx: float, cy: float, r: float, a0: float, a1: float,
		color: Color, width: float = 2.0) -> void:
	stroke(ci, arc_pts(cx, cy, r, r, 0.0, a0, a1), color, width, false)

# ============================================================
# 裁剪（ctx.clip 对折线的等价物 —— 直线被裁成线段，不改变几何）
# ============================================================

## 把一条折线裁到给定多边形内，返回若干段可见折线（等价 ctx.clip() 之后的描边）。
##
## 坑：Geometry2D.clip_polyline_with_polygon() 返回的是多边形**外侧**的部分（补集），
## 不是我们要的内侧。取内侧必须用 intersect_polyline_with_polygon()。
## 已在运行中的游戏里实测确认（poly = circle_pts(0,0,50)，line = [(0,0),(0,1000)]）：
##   clip_polyline_with_polygon(line, poly)      -> [(0,49.90),(0,1000)]   外侧
##   intersect_polyline_with_polygon(line, poly) -> [(0,0),(0,49.90)]      内侧
static func clip_polyline(ci_unused: Variant, pts: PackedVector2Array, poly: PackedVector2Array) -> Array:
	if pts.size() < 2 or poly.size() < 3:
		return []
	return Geometry2D.intersect_polyline_with_polygon(pts, poly)

## 直接画出被裁剪后的折线。
static func stroke_clipped(ci: CanvasItem, pts: PackedVector2Array, poly: PackedVector2Array,
		color: Color, width: float = 2.0) -> void:
	for seg in clip_polyline(null, pts, poly):
		stroke(ci, seg, color, width, false)
