extends SceneTree

class RecordingPainter extends "res://scripts/MapPainter.gd":
	var record_us := 0
	func _draw() -> void:
		var start := Time.get_ticks_usec()
		super._draw()
		record_us = Time.get_ticks_usec() - start

## CPU draw-command recording only, not whole-frame/GPU time.
## Run with --script res://tests/bench_map_cache.gd and a rendering display.
func _initialize() -> void:
	_run()

func _median(values: Array) -> float:
	values.sort()
	return float(values[int(values.size() / 2)]) / 1000.0

func _run() -> void:
	for theme_id in Cfg.THEME_IDS:
		var w := GameEngine.create_world({"mode": "dig", "seed": "map-polish-bench"})
		GameEngine.apply_level(w, LevelGen.generate(Rng.new(147), {
			"mode": "dig", "theme": theme_id, "spawns": w.spawns}))
		var vp := SubViewport.new()
		vp.size = Vector2i(Cfg.FIELD_W * 2, Cfg.FIELD_H * 2)
		vp.disable_3d = true
		root.add_child(vp)
		var old := RecordingPainter.new()
		old.layer = 1
		old.world = w
		vp.add_child(old)
		var cached = load("res://scripts/MapPainter.gd").new()
		cached.layer = 1
		cached.world = w
		cached.retain_cells = true
		vp.add_child(cached)
		cached.sync_cells()
		await process_frame
		await RenderingServer.frame_post_draw
		var key: int = cached._cells.keys()[0]
		var old_samples := []
		var new_samples := []
		for i in 35:
			w.set_tile(key % Cfg.COLS, int(key / Cfg.COLS), Cfg.T_EMPTY)
			var start := Time.get_ticks_usec()
			cached.sync_cells()
			var end := Time.get_ticks_usec()
			old.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			if i >= 5:
				old_samples.append(old.record_us)
				new_samples.append(end - start)
			w.set_tile(key % Cfg.COLS, int(key / Cfg.COLS), Cfg.T_BRICK)
			cached.sync_cells()
			await process_frame
			await RenderingServer.frame_post_draw
		print("METRICS= %s bricks=%d full_record_ms=%.3f retained_update_ms=%.3f" % [
			theme_id, w.count_bricks(), _median(old_samples), _median(new_samples)])
		vp.queue_free()
		await process_frame
	quit(0)
