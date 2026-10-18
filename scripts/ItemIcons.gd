class_name ItemIcons
extends RefCounted

## 道具图标：按原作 sprites.js drawItemIcon（565-627 行）的 32×32 路径逐点重绘。
##
## 原作的每条轮廓都是 moveTo/lineTo/quadraticCurveTo/bezierCurveTo 组成的真实路径，
## 由 shape() 一次 fill + stroke（lineWidth = 2、strokeStyle = '#39445c'，lineJoin/lineCap = round）。
## 这里不再用控制点当顶点做折线近似：曲线一律走 CanvasArt 的自适应细分（等价 Canvas 压平）。
##
## alpha 等价于原作的 ctx.globalAlpha（source-over 下与「颜色 alpha 乘 alpha」相同），
## HUD 的阵亡态（.48）靠它复刻；默认 1.0 时不改变任何颜色对象。

const INK := Color("39445c")

## globalAlpha 等价：alpha >= 0.999 时原样返回，零视觉/零开销。
static func _tint(c: Color, alpha: float) -> Color:
	if alpha >= 0.999:
		return c
	return Color(c.r, c.g, c.b, c.a * alpha)

## 追加一段 quadraticCurveTo（起点已在 out 末尾）。
static func _quad_into(out: PackedVector2Array, p0: Vector2, c: Vector2, p1: Vector2) -> void:
	var seg := CanvasArt.quad(p0, c, p1)
	for i in range(1, seg.size()):
		out.append(seg[i])

## 追加一段 bezierCurveTo（起点已在 out 末尾）。
static func _bez_into(out: PackedVector2Array, p0: Vector2, c0: Vector2, c1: Vector2, p1: Vector2) -> void:
	var seg := CanvasArt.bezier(p0, c0, c1, p1)
	for i in range(1, seg.size()):
		out.append(seg[i])

## 原作 shape(fill)：填充当前路径，再以 lineWidth 2 / '#39445c' 描边（路径闭合）。
static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, alpha: float = 1.0) -> void:
	if pts.size() < 3:
		return
	ci.draw_colored_polygon(pts, _tint(fill, alpha))
	var line := pts
	if not line[line.size() - 1].is_equal_approx(line[0]):
		line.append(line[0])
	ci.draw_polyline(line, _tint(INK, alpha), 2.0, true)

## 原作 dot(x, y, r, color)：只填充，不描边。
static func _dot(ci: CanvasItem, x: float, y: float, r: float, color: Color, alpha: float = 1.0) -> void:
	ci.draw_circle(Vector2(x, y), r, _tint(color, alpha), true, -1.0, true)

static func draw(ci: CanvasItem, type: String, x: float, y: float, size: float, alpha: float = 1.0) -> void:
	var a := clampf(alpha, 0.0, 1.0)
	var ink := _tint(INK, a)
	ci.draw_set_transform(Vector2(x, y), 0.0, Vector2(size / 32.0, size / 32.0))
	match type:
		"speed":
			# moveTo(-12,1) lineTo(-9,-9) quad(-4,-5 → 0,-8) lineTo(4,-1)
			# quad(14,-1 → 14,6) lineTo(13,10) lineTo(-12,10) close
			var pts := PackedVector2Array([Vector2(-12, 1), Vector2(-9, -9)])
			_quad_into(pts, Vector2(-9, -9), Vector2(-4, -5), Vector2(0, -8))
			pts.append(Vector2(4, -1))
			_quad_into(pts, Vector2(4, -1), Vector2(14, -1), Vector2(14, 6))
			pts.append(Vector2(13, 10))
			pts.append(Vector2(-12, 10))
			_shape(ci, pts, Color("6de0b6"), a)
			ci.draw_line(Vector2(-11, 6), Vector2(13, 6), ink, 2.0, true)
			# 两条白色高光在原作里是同一条路径的两个子路径，一次 stroke。
			ci.draw_line(Vector2(-3, -3), Vector2(2, -4), _tint(Color.WHITE, a), 2.0, true)
			ci.draw_line(Vector2(0, 0), Vector2(5, -1), _tint(Color.WHITE, a), 2.0, true)
		"glove":
			# moveTo(-8,8) lineTo(-13,-1) quad(-17,-10 → -11,-8) lineTo(-7,-3) lineTo(-7,-10)
			# bezier(-7,-17 10,-17 → 11,-8) lineTo(11,4) quad(11,11 → 5,11) lineTo(-5,11) close
			var pts := PackedVector2Array([Vector2(-8, 8), Vector2(-13, -1)])
			_quad_into(pts, Vector2(-13, -1), Vector2(-17, -10), Vector2(-11, -8))
			pts.append(Vector2(-7, -3))
			pts.append(Vector2(-7, -10))
			_bez_into(pts, Vector2(-7, -10), Vector2(-7, -17), Vector2(10, -17), Vector2(11, -8))
			pts.append(Vector2(11, 4))
			_quad_into(pts, Vector2(11, 4), Vector2(11, 11), Vector2(5, 11))
			pts.append(Vector2(-5, 11))
			_shape(ci, pts, Color("ffc077"), a)
			# D.blob(-8,7,17,7,3,'#f18b72','#39445c',2)
			UIDraw.fill_rr(ci, -8, 7, 17, 7, 3, _tint(Color("f18b72"), a))
			UIDraw.stroke_rr(ci, -8, 7, 17, 7, 3, ink, 2.0)
			var shine := CanvasArt.quad(Vector2(-2, -9), Vector2(4, -12), Vector2(7, -7))
			ci.draw_polyline(shine, _tint(Color("fff3d6"), a), 2.5, true)
		"fruit":
			# moveTo(0,-8) bezier(-14,-16 -17,5 → -6,12) quad(0,16 → 6,12)
			# bezier(17,5 14,-16 → 0,-8)
			var pts := PackedVector2Array([Vector2(0, -8)])
			_bez_into(pts, Vector2(0, -8), Vector2(-14, -16), Vector2(-17, 5), Vector2(-6, 12))
			_quad_into(pts, Vector2(-6, 12), Vector2(0, 16), Vector2(6, 12))
			_bez_into(pts, Vector2(6, 12), Vector2(17, 5), Vector2(14, -16), Vector2(0, -8))
			_shape(ci, pts, Color("efb389"), a)
			var stem := CanvasArt.quad(Vector2(0, -7), Vector2(-2, -12), Vector2(1, -15))
			ci.draw_polyline(stem, ink, 2.0, true)
			CanvasArt.ellipse_rot_fill(ci, 6, -12, 6, 3, 0.0, _tint(Color("8db775"), a))
			CanvasArt.ellipse_rot_fill(ci, -6, -1, 2, 4, 0.0, _tint(Color("ffe6bc"), a))
		"fire":
			# moveTo(0,-14) bezier(3,-5 12,-4 → 12,4) bezier(12,17 -13,17 → -12,3)
			# quad(-12,-2 → -6,-7) quad(-6,-1 → -3,0) quad(2,-5 → 0,-14)
			var pts := PackedVector2Array([Vector2(0, -14)])
			_bez_into(pts, Vector2(0, -14), Vector2(3, -5), Vector2(12, -4), Vector2(12, 4))
			_bez_into(pts, Vector2(12, 4), Vector2(12, 17), Vector2(-13, 17), Vector2(-12, 3))
			_quad_into(pts, Vector2(-12, 3), Vector2(-12, -2), Vector2(-6, -7))
			_quad_into(pts, Vector2(-6, -7), Vector2(-6, -1), Vector2(-3, 0))
			_quad_into(pts, Vector2(-3, 0), Vector2(2, -5), Vector2(0, -14))
			_shape(ci, pts, Color("ff8c58"), a)
			# 内焰：quad(10,11 → 0,12) + quad(-9,11 → 0,-2)，只填充不描边。
			var inner := PackedVector2Array([Vector2(0, -2)])
			_quad_into(inner, Vector2(0, -2), Vector2(10, 11), Vector2(0, 12))
			_quad_into(inner, Vector2(0, 12), Vector2(-9, 11), Vector2(0, -2))
			ci.draw_colored_polygon(inner, _tint(Color("ffe17e"), a))
		"bomb":
			# 引线先行：quad(1,-17 → 10,-12)，lineWidth 2 / '#39445c'。
			var fuse := CanvasArt.quad(Vector2(3, -8), Vector2(1, -17), Vector2(10, -12))
			ci.draw_polyline(fuse, ink, 2.0, true)
			_dot(ci, 10, -12, 3, Color("ffb957"), a)
			_shape(ci, CanvasArt.circle_pts(-1, 3, 11), Color("64719d"), a)
			CanvasArt.ellipse_rot_fill(ci, -5, -2, 3.5, 2, 0.0, _tint(Color("d6e5ff"), a))
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var ang := -PI * 0.5 + k * PI / 5.0
				var r := 7.5 if k % 2 == 1 else 15.0
				pts.append(Vector2(cos(ang) * r, sin(ang) * r))
			_shape(ci, pts, Color("ffdc65"), a)
			_dot(ci, -4, -1, 1.5, Color("55483c"), a)
			_dot(ci, 4, -1, 1.5, Color("55483c"), a)
			# 嘴：arc(0,1,3.5,0,PI)，仍用外轮廓的 strokeStyle（'#39445c'）与 lineWidth 2。
			CanvasArt.arc_stroke(ci, 0, 1, 3.5, 0.0, PI, ink, 2.0)
			_dot(ci, -7, 3, 1.9, Color("ffac9b"), a)
			_dot(ci, 7, 3, 1.9, Color("ffac9b"), a)
		"shield":
			# moveTo(0,-13) quad(6,-9 → 12,-10) lineTo(11,2) quad(10,10 → 0,15)
			# quad(-10,10 → -11,2) lineTo(-12,-10) quad(-6,-9 → 0,-13)
			var pts := PackedVector2Array([Vector2(0, -13)])
			_quad_into(pts, Vector2(0, -13), Vector2(6, -9), Vector2(12, -10))
			pts.append(Vector2(11, 2))
			_quad_into(pts, Vector2(11, 2), Vector2(10, 10), Vector2(0, 15))
			_quad_into(pts, Vector2(0, 15), Vector2(-10, 10), Vector2(-11, 2))
			pts.append(Vector2(-12, -10))
			_quad_into(pts, Vector2(-12, -10), Vector2(-6, -9), Vector2(0, -13))
			_shape(ci, pts, Color("7bcfff"), a)
			# 对勾是开放路径（原作没有 closePath），lineWidth 3 / '#e9faff'。
			ci.draw_polyline(PackedVector2Array([Vector2(-5, 0), Vector2(-1, 4), Vector2(6, -4)]),
				_tint(Color("e9faff"), a), 3.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
