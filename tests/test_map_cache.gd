extends "res://tests/test_core.gd"

func test_retained_bricks() -> void:
	for theme_id in Cfg.THEME_IDS:
		var w := make_world()
		GameEngine.apply_level(w, LevelGen.generate(Rng.new(147), {
			"mode": "dig", "theme": theme_id, "spawns": w.spawns}))
		var painter = load("res://scripts/MapPainter.gd").new()
		painter.layer = 1
		painter.retain_cells = true
		painter.world = w
		get_root().add_child(painter)
		painter.sync_cells()
		check(painter._cells.size() == w.count_bricks(), "%s records every brick" % theme_id)
		var before: int = painter.cell_redraws
		var ids := {}
		for key in painter._cells:
			ids[key] = painter._cells[key].get_instance_id()
		var removed: int = painter._cells.keys()[0]
		w.set_tile(removed % Cfg.COLS, int(removed / Cfg.COLS), Cfg.T_EMPTY)
		painter.sync_cells()
		check(not painter._cells.has(removed), "%s removes destroyed brick immediately" % theme_id)
		check(painter.cell_redraws == before, "%s destroying one brick rebuilds zero survivors" % theme_id)
		var retained := true
		for key in painter._cells:
			retained = retained and painter._cells[key].get_instance_id() == ids[key]
		check(retained, "%s keeps surviving draw nodes" % theme_id)
		painter.sync_cells()
		check(painter.cell_redraws == before, "%s unchanged map does no extra recording" % theme_id)
		var survivor: int = painter._cells.keys()[0]
		w.brick_variants[survivor] = (int(w.brick_variants[survivor]) + 1) % 3
		painter.sync_cells()
		check(painter.cell_redraws == before + 1, "%s changing one variant redraws exactly one brick" % theme_id)
		for i in w.map.size():
			if int(w.map[i]) == Cfg.T_BRICK:
				w.set_tile(i % Cfg.COLS, int(i / Cfg.COLS), Cfg.T_EMPTY)
		painter.sync_cells()
		check(painter._cells.is_empty(), "%s mass clearing leaves no phantom bricks" % theme_id)
		w.set_tile(removed % Cfg.COLS, int(removed / Cfg.COLS), Cfg.T_BRICK)
		painter.sync_cells()
		check(painter._cells.size() == 1, "%s adding a brick restores its drawing" % theme_id)
		var next_theme: String = "factory" if theme_id != "factory" else "park"
		GameEngine.apply_level(w, LevelGen.generate(Rng.new(71), {
			"mode": "dig", "theme": next_theme, "spawns": w.spawns}))
		painter.sync_cells()
		var correct_theme := true
		for cell in painter._cells.values():
			correct_theme = correct_theme and cell.theme == next_theme
		check(correct_theme and painter._cells.size() == w.count_bricks(), "%s theme switch refreshes all content" % theme_id)
		painter.world = null
		painter.sync_cells()
		check(painter._cells.is_empty(), "%s clearing world removes retained bricks" % theme_id)
		painter.world = w
		painter.sync_cells()
		check(painter._cells.size() == w.count_bricks(), "%s restoring world rebuilds retained bricks" % theme_id)
		painter.free()

func test_arrow_segments() -> void:
	var path := LevelGen.loop_path(4, 3, 10, 9)
	for phase in [0.0, 0.001, 0.25, 0.999]:
		var correct := true
		for i in path.size():
			var progress: float = i + phase
			var pt := Scenery.point(path, progress)
			var old := Scenery.nearest(path, pt.x, pt.y)
			var segment := int(floor(fposmod(progress, float(path.size()))))
			var dir := Vector2(path[(segment + 1) % path.size()] - path[segment]).normalized()
			correct = correct and dir.is_equal_approx(Vector2(old["dx"], old["dy"]).normalized())
		check(correct, "direct conveyor tangent matches nearest-segment result at phase %.3f" % phase)

func _initialize() -> void:
	test_retained_bricks()
	test_arrow_segments()
	print("MAP_CACHE_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
