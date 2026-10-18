extends SceneTree

## 实测 Godot 4.7.2（gl_compatibility）里 antialiased 的生效范围与副作用。
##
## 两件事一起量：
##   1. 哪些图元支持 antialiased（文档只含糊说"部分方法支持"）；
##   2. **副作用**：工程里有大量 `+0.5` 偏移的 1px 细线（Canvas 里保证锐利的经典写法），
##      开抗锯齿后会不会被抹成两行半透明 —— 如果会，就不能无脑全开。
##
## 判据：数"既不是纯底色也不是纯前景色"的过渡像素。
##   过渡像素从 0 变多  => 抗锯齿生效；
##   细线本来 0 过渡（锐利），开了还是 0 => 没被抹糊，安全。

const W := 480
const H := 160
const BG := Color(0, 0, 0, 1)
const FG := Color(1, 1, 1, 1)

class Probe extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, W, H), BG, true)
		var dx := W / 2
		var y := 20.0
		# 填充圆
		draw_circle(Vector2(60, y), 16, FG, true, -1.0, false)
		draw_circle(Vector2(60 + dx, y), 16, FG, true, -1.0, true)
		# 空心圆描边
		y += 36.0
		draw_circle(Vector2(60, y), 14, FG, false, 3.0, false)
		draw_circle(Vector2(60 + dx, y), 14, FG, false, 3.0, true)
		# 斜线（未对齐像素，最需要 AA）
		y += 34.0
		draw_line(Vector2(20, y), Vector2(100, y + 9), FG, 3.0, false)
		draw_line(Vector2(20 + dx, y), Vector2(100 + dx, y + 9), FG, 3.0, true)
		# 圆弧
		y += 34.0
		draw_arc(Vector2(60, y), 16, -0.6, 2.4, 20, FG, 3.0, false)
		draw_arc(Vector2(60 + dx, y), 16, -0.6, 2.4, 20, FG, 3.0, true)
		# 关键副作用测试：+0.5 对齐的 1px 细线（工程里的地板网格就是这种写法）
		draw_line(Vector2(20.5, 143.5), Vector2(100.5, 143.5), FG, 1.0, false)
		draw_line(Vector2(20.5 + dx, 143.5), Vector2(100.5 + dx, 143.5), FG, 1.0, true)
		# +0.5 对齐的 1px 矩形描边
		draw_rect(Rect2(120.5, 130.5, 60, 20), FG, false, 1.0, false)
		draw_rect(Rect2(120.5 + dx, 130.5, 60, 20), FG, false, 1.0, true)

func _initialize() -> void:
	_run()

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var probe := Probe.new()
	vp.add_child(probe)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null:
		print("PROBE_FAIL: no image")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var dx := W / 2
	var cases := [
		["填充圆", Rect2i(30, 4, 60, 32)],
		["空心圆描边", Rect2i(30, 40, 60, 32)],
		["斜线 3px", Rect2i(10, 74, 110, 22)],
		["圆弧 3px", Rect2i(30, 108, 60, 32)],
		["1px 细线(+0.5)", Rect2i(10, 138, 110, 12)],
		["1px 矩形描边(+0.5)", Rect2i(112, 126, 76, 28)],
	]
	print("--- 过渡像素数（0 = 硬边；变多 = 抗锯齿生效）---")
	print("  %-22s %10s %10s   %s" % ["图元", "AA=false", "AA=true", "结论"])
	for c in cases:
		var name: String = c[0]
		var r: Rect2i = c[1]
		var a := _count_soft(img, r)
		var b := _count_soft(img, Rect2i(r.position.x + dx, r.position.y, r.size.x, r.size.y))
		var verdict := "AA 生效"
		if b <= a:
			verdict = "无差异（可能不支持）"
		if a == 0 and b == 0:
			verdict = "两边都锐利 → 安全"
		print("  %-22s %10d %10d   %s" % [name, a, b, verdict])
	quit(0)

func _count_soft(img: Image, r: Rect2i) -> int:
	var n := 0
	for yy in range(r.position.y, mini(r.position.y + r.size.y, img.get_height())):
		for xx in range(r.position.x, mini(r.position.x + r.size.x, img.get_width())):
			var l := img.get_pixel(xx, yy).r
			if l > 0.06 and l < 0.94:
				n += 1
	return n
