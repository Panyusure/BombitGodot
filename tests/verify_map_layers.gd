extends SceneTree

## 验证「静态地图拆成两层」在视觉上与原来的单遍绘制等价。
##
## 做法：同一个 world 渲染两遍到同样大小的离屏目标——
##   A（拆层后）：一个 SubViewport 里挂两个 MapPainter 子节点，layer=0 与 layer=1，
##                按子节点顺序合成（正是 Board 现在的做法：base 层 + dest 层）
##   B（参考）  ：一个 MapPainter，layer=2，完全照原作 drawMap 的单遍顺序
## 然后逐像素比对。
##
## 预期：只有极少数像素有差异，且只出现在「硬墙与软砖相邻的格子边界」——
## 因为原作的逐格循环里先画的格会被后画的格压住，而拆层后软砖整体压在硬墙之上。
## 只要差异足够小且局限在边界，拆层就是安全的。

const W := 1440
const H := 1248

func make_world(theme: String) -> World:
	var w = World.new()
	w.mode = "adventure"
	w.theme = theme
	w.map = []
	w.map.resize(Cfg.COLS * Cfg.ROWS)
	w.map.fill(Cfg.T_EMPTY)
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
				w.map[r * Cfg.COLS + c] = Cfg.T_HARD
			elif (c * 7 + r * 11) % 5 < 2 and c > 1 and r > 1 and c < Cfg.COLS - 2 and r < Cfg.ROWS - 2:
				w.map[r * Cfg.COLS + c] = Cfg.T_BRICK
	w.brick_variants = []
	w.brick_variants.resize(Cfg.COLS * Cfg.ROWS)
	for i in w.brick_variants.size():
		w.brick_variants[i] = i % 4
	w.rng = Rng.new(99)
	w.match = Match.create("adventure")
	w.landmark = {"theme": theme, "c": 7, "r": 6,
		"path": LevelGen.loop_path(5, 4, 9, 8), "fruit_timer": 8.0}
	w.map_revision = 1
	return w

func _initialize() -> void:
	_run()

func _run() -> void:
	var total_bad := 0
	for theme in Cfg.THEME_IDS:
		var w := make_world(theme)
		# A：拆层（base + dest 两个 painter，与 Board 一致）
		var vp_a := _make_vp()
		var pa := _painter(w, 0)
		vp_a.add_child(pa)
		var pb := _painter(w, 1)
		vp_a.add_child(pb)
		# B：参考单遍
		var vp_b := _make_vp()
		var pc := _painter(w, 2)
		vp_b.add_child(pc)

		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var ia := vp_a.get_texture().get_image()
		var ib := vp_b.get_texture().get_image()
		if ia == null or ib == null:
			print("%-8s FAIL 取不到图" % theme)
			continue
		ia.convert(Image.FORMAT_RGBA8)
		ib.convert(Image.FORMAT_RGBA8)

		var diff_px := 0
		var max_ch := 0.0
		var worst := Vector2i.ZERO
		for y in H:
			for x in W:
				var ca := ia.get_pixel(x, y)
				var cb := ib.get_pixel(x, y)
				var d := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)),
					maxf(absf(ca.b - cb.b), absf(ca.a - cb.a)))
				if d > 0.004:
					diff_px += 1
					if d > max_ch:
						max_ch = d
						worst = Vector2i(x, y)
		var pct := 100.0 * float(diff_px) / float(W * H)
		total_bad += diff_px
		print("%-8s 差异像素 %6d / %d  (%.4f%%)   最大通道差 %.3f   最差处 %s"
			% [theme, diff_px, W * H, pct, max_ch, str(worst)])
		ia.save_png("%s/maplayer_%s_split.png" % [OS.get_environment("TEMP"), theme])
		ib.save_png("%s/maplayer_%s_ref.png" % [OS.get_environment("TEMP"), theme])
		vp_a.queue_free()
		vp_b.queue_free()
		await process_frame
	print("--- 合计差异像素 %d（占比 %.5f%%）---" % [total_bad, 100.0 * total_bad / float(W * H * 3)])
	quit(0)

func _make_vp() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	return vp

func _painter(w: World, layer: int) -> Node2D:
	var p := Node2D.new()
	p.set_script(load("res://scripts/MapPainter.gd"))
	p.set("world", w)
	p.set("layer", layer)
	p.scale = Vector2(2, 2)
	return p
