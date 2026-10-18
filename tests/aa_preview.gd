extends SceneTree

## 把**真实游戏美术**渲染到离屏 SubViewport 并存成 PNG，用来验证抗锯齿确实生效。
##
## 独立进程运行（需要真实窗口渲染，headless 出不了图），不碰编辑器里正在跑的游戏。
## 判据：过渡像素（既非底色也非前景）数量。AA 关闭时该值为 0（硬边），
## 开启后会大量出现。

const W := 720
const H := 624

func _initialize() -> void:
	_run()

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
	w.spawns = [[1, 1], [Cfg.COLS - 2, Cfg.ROWS - 2]]
	w.rng = Rng.new(99)
	w.match = Match.create("adventure")
	w.landmark = {"theme": theme, "c": 7, "r": 6,
		"path": LevelGen.loop_path(5, 4, 9, 8), "fruit_timer": 8.0}
	w.map_revision = 1
	w.time = 1.25
	return w

class Painter extends Node2D:
	var world: World
	func _draw() -> void:
		MapArt.draw_floor(self, world.theme, world.map)
		MapArt.draw_track(self, world.landmark)
		for r in Cfg.ROWS:
			for c in Cfg.COLS:
				var v := Grid.at(world.map, c, r)
				if c >= 6 and c <= 8 and r >= 5 and r <= 7:
					continue
				if v == Cfg.T_HARD:
					MapArt.draw_hard(self, c, r, world.theme)
				elif v == Cfg.T_BRICK:
					MapArt.draw_brick(self, c, r, world.theme, int(world.brick_variants[r * Cfg.COLS + c]))
		MapArt.draw_landmark(self, world.landmark)
		# 再叠几样动态美术，覆盖径向渐变/曲线路径
		MapArt.draw_items(self, [
			{"c": 2, "r": 2, "type": "fire", "born": 0.0},
			{"c": 3, "r": 2, "type": "star", "born": 0.0},
			{"c": 4, "r": 2, "type": "shield", "born": 0.0}], 1.25)
		MapArt.draw_poison(self, [{"c": 10, "r": 3, "warn": 0.0}])
		MapArt.draw_skill_effects(self, _fake_world(), 1.25)

	func _fake_world() -> World:
		var w = World.new()
		w.skill_effects = [{"type": "soul_pulse", "x": 500.0, "y": 300.0, "radius": 1,
			"evolved": false, "t": 0.35, "total": 1.0, "color": Color("a9eafa")}]
		return w

func _run() -> void:
	var out_dir := OS.get_environment("TEMP")
	if out_dir.is_empty():
		out_dir = "."
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	for theme in Cfg.THEME_IDS:
		var p := Painter.new()
		p.world = make_world(theme)
		vp.add_child(p)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null:
			print("FAIL no image for ", theme)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var path := "%s/aa_%s.png" % [out_dir, theme]
		img.save_png(path)
		print("%-8s 过渡像素=%6d   -> %s" % [theme, _count_soft(img), path])
		p.queue_free()
		await process_frame
	quit(0)

## 统计"既不是纯某色"的像素：用相邻像素差分的简单判据（沿水平方向有中间值）。
func _count_soft(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(1, img.get_width() - 1, 2):
			var a := img.get_pixel(x - 1, y)
			var b := img.get_pixel(x, y)
			var c := img.get_pixel(x + 1, y)
			var d1 := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			var d2 := absf(b.r - c.r) + absf(b.g - c.g) + absf(b.b - c.b)
			# 两侧都有差异 = 处在渐变/过渡带上，而不是纯色块
			if d1 > 0.02 and d2 > 0.02 and d1 < 0.6 and d2 < 0.6:
				n += 1
	return n
