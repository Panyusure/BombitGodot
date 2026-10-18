extends SceneTree

## 静态地图重画开销分解：地板 / 硬墙 / 软砖 / 设施 各占多少。
##
## 背景：`World.set_tile` 炸掉一块软砖会让 `map_revision+1`，
## `Board._ensure_map()` 于是把**整张**静态地图（2× 分辨率）重画一遍。
## 要决定怎么优化，得先知道钱花在哪一段。

const W := 1440   # 2× 超采样，与 Board 的 SubViewport 一致
const H := 1248

class Painter extends Node2D:
	var world: World
	var mode := "full"
	func _draw() -> void:
		match mode:
			"full":
				_draw_all()
			"floor":
				MapArt.draw_floor(self, world.theme, world.map)
				MapArt.draw_track(self, world.landmark)
			"walls":
				for r in Cfg.ROWS:
					for c in Cfg.COLS:
						if Grid.at(world.map, c, r) == Cfg.T_HARD:
							MapArt.draw_hard(self, c, r, world.theme)
			"bricks":
				for r in Cfg.ROWS:
					for c in Cfg.COLS:
						if Grid.at(world.map, c, r) == Cfg.T_BRICK:
							MapArt.draw_brick(self, c, r, world.theme, int(world.brick_variants[r * Cfg.COLS + c]))
			"landmark":
				MapArt.draw_landmark(self, world.landmark)

	func _draw_all() -> void:
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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	print("--- 单次重画耗时（中位数，每项 40 帧；vsync 关闭）---")
	var counts := {"HARD": 0, "BRICK": 0, "EMPTY": 0}
	var w0 := make_world("forest")
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			var v := Grid.at(w0.map, c, r)
			if v == Cfg.T_HARD:
				counts["HARD"] += 1
			elif v == Cfg.T_BRICK:
				counts["BRICK"] += 1
			else:
				counts["EMPTY"] += 1
	print("  格数：硬墙 %d / 软砖 %d / 空 %d" % [counts["HARD"], counts["BRICK"], counts["EMPTY"]])

	var prev_us := 0
	for mode in ["full", "floor", "walls", "bricks", "landmark"]:
		var p := Painter.new()
		p.world = w0
		p.mode = mode
		vp.add_child(p)
		# 预热
		for i in 4:
			p.queue_redraw()
			await RenderingServer.frame_post_draw
		var samples := []
		for i in 40:
			p.queue_redraw()
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			if prev_us > 0:
				samples.append((now - prev_us) / 1000.0)
			prev_us = now
		samples.sort()
		var med: float = samples[samples.size() / 2]
		print("  %-10s 中位帧耗时 %7.2f ms   (p90 %.2f)" % [mode, med, samples[int(samples.size() * 0.9)]])
		p.queue_free()
		await process_frame
	quit(0)
