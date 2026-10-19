extends SceneTree

## Run with a display: checks the actual 2x framebuffer, including invalidation.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run()

func _painter(vp: SubViewport, w: World, layer: int, retained: bool) -> Node2D:
	var painter = load("res://scripts/MapPainter.gd").new()
	painter.world = w
	painter.layer = layer
	painter.retain_cells = retained
	painter.scale = Vector2(2, 2)
	vp.add_child(painter)
	if retained:
		painter.sync_cells()
	return painter

func _viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(Cfg.FIELD_W * 2, Cfg.FIELD_H * 2)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp

func _compare(a: SubViewport, b: SubViewport, label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	checks += 1
	var ia := a.get_texture().get_image()
	var ib := b.get_texture().get_image()
	if ia == null or ib == null:
		failures += 1
		printerr("CHECK_FAIL= %s missing framebuffer" % label)
		return
	var da := ia.get_data()
	var db := ib.get_data()
	if da != db:
		var bad := 0
		for i in da.size():
			if absi(int(da[i]) - int(db[i])) > 1:
				bad += 1
		# Separate CanvasItems may round antialiasing by one byte, but must not
		# change geometry, occlusion or leave stale tiles after invalidation.
		if bad > 0:
			failures += 1
			printerr("CHECK_FAIL= %s differs in %d channels" % [label, bad])
	print("CHECK= %s" % label)

func _run() -> void:
	for theme_id in Cfg.THEME_IDS:
		var w := GameEngine.create_world({"mode": "dig", "seed": "map-polish"})
		GameEngine.apply_level(w, LevelGen.generate(Rng.new(147), {
			"mode": "dig", "theme": theme_id, "spawns": w.spawns}))
		var cached := _viewport()
		var reference := _viewport()
		var cb := _painter(cached, w, 0, false)
		var cd := _painter(cached, w, 1, true)
		var rb := _painter(reference, w, 0, false)
		var rd := _painter(reference, w, 1, false)
		await _compare(cached, reference, "%s initial" % theme_id)
		var destroyed: int = cd._cells.keys()[0]
		w.set_tile(destroyed % Cfg.COLS, int(destroyed / Cfg.COLS), Cfg.T_EMPTY)
		cd.sync_cells()
		rd.queue_redraw()
		await _compare(cached, reference, "%s destroyed brick" % theme_id)
		w.set_tile(destroyed % Cfg.COLS, int(destroyed / Cfg.COLS), Cfg.T_BRICK)
		cd.sync_cells()
		rd.queue_redraw()
		await _compare(cached, reference, "%s restored brick order" % theme_id)
		w.brick_variants[destroyed] = (int(w.brick_variants[destroyed]) + 1) % 3
		cd.sync_cells()
		rd.queue_redraw()
		await _compare(cached, reference, "%s updated variant" % theme_id)
		for i in w.map.size():
			if int(w.map[i]) == Cfg.T_BRICK:
				w.set_tile(i % Cfg.COLS, int(i / Cfg.COLS), Cfg.T_EMPTY)
		cd.sync_cells()
		rd.queue_redraw()
		await _compare(cached, reference, "%s cleared bricks" % theme_id)
		var next_theme: String = "park" if theme_id == "factory" else "factory"
		GameEngine.apply_level(w, LevelGen.generate(Rng.new(68), {
			"mode": "dig", "theme": next_theme, "spawns": w.spawns}))
		cb.queue_redraw()
		cd.sync_cells()
		rb.queue_redraw()
		rd.queue_redraw()
		await _compare(cached, reference, "%s switched to %s" % [theme_id, next_theme])
		cached.queue_free()
		reference.queue_free()
		await process_frame
	print("RETAINED_RENDER_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
