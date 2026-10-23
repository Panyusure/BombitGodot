extends SceneTree

const Carousel = preload("res://scripts/CarouselArt.gd")
var output := ""
var checks := 0
var failures := 0

class Probe extends Node2D:
	const Art = preload("res://scripts/CarouselArt.gd")
	var theme := "park"
	var landmark := {"theme":"park", "c":7, "r":6}
	var time := 0.0
	func _draw() -> void:
		Art.draw(self, theme, landmark, time)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL=" + message)

func _initialize() -> void:
	call_deferred("_run")

func viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp

func settle() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func _run() -> void:
	output = OS.get_environment("BOMBIT_CAROUSEL_CAPTURE_DIR")
	if output.is_empty():
		output = ProjectSettings.globalize_path("user://carousel-verification")
	output = output.trim_suffix("/").trim_suffix("\\") + "/"
	check(Carousel.SHEET.get_size() == Vector2(2048,1024), "32-frame H3 atlas imported")
	check(Carousel.frame_at(0) == Carousel.frame_at(2.5), "exact loop boundary")
	check(Carousel.frame_at(0.8) == Carousel.frame_at(1000.8), "replay seek uses absolute game time")
	check(Carousel.frame_at(-0.1) >= 0 and Carousel.frame_at(-0.1) < 32, "rewind phase stays inside atlas")
	check(not Carousel.applies("forest", {"theme":"park"}), "mismatched world theme hides carousel")
	check(not Carousel.applies("park", {}), "boss / no-landmark map hides carousel")
	var vp := viewport(Vector2i(1440,1248))
	var probe := Probe.new()
	probe.scale = Vector2(2,2)
	vp.add_child(probe)
	await settle()
	var first := vp.get_texture().get_image()
	probe.time = 0.625
	probe.queue_redraw()
	await settle()
	var moving := vp.get_texture().get_image()
	check(first.get_data() != moving.get_data(), "actual GPU frames show horse motion")
	check(Rect2i(576,480,288,288).encloses(moving.get_used_rect()), "moving silhouette stays inside 3x3 collision core")
	check(first.get_region(Rect2i(576,480,288,116)).get_data() == moving.get_region(Rect2i(576,480,288,116)).get_data(), "canopy remains pixel-stable")
	check(first.get_region(Rect2i(576,732,288,36)).get_data() == moving.get_region(Rect2i(576,732,288,36)).get_data(), "foundation remains pixel-stable")
	probe.time = 2.5
	probe.queue_redraw()
	await settle()
	check(first.get_data() == vp.get_texture().get_image().get_data(), "GPU loop closes on exactly the same frame")
	probe.queue_redraw()
	await settle()
	check(first.get_data() == vp.get_texture().get_image().get_data(), "paused game time holds the frame")
	probe.theme = "factory"
	probe.queue_redraw()
	await settle()
	check(vp.get_texture().get_image().get_used_rect().size == Vector2i.ZERO, "switching themes leaves no animated ghost")
	probe.queue_free()
	var board = load("res://scripts/Board.gd").new()
	board.scale = Vector2(2,2)
	vp.add_child(board)
	var w := GameEngine.create_world({"mode":"dig", "seed":"carousel-integration"})
	GameEngine.apply_level(w,LevelGen.generate(Rng.new(147),{"mode":"dig","theme":"park","spawns":w.spawns}))
	board.world = w
	board.anim_time = 0.0
	await settle()
	var base: PackedByteArray = board._vp_base.get_texture().get_image().get_data()
	var dest: PackedByteArray = board._vp_dest.get_texture().get_image().get_data()
	var redraws: int = board._painter_dest.cell_redraws
	var map_before := w.map.duplicate()
	board.anim_time = 0.8
	board.queue_redraw()
	await settle()
	check(base == board._vp_base.get_texture().get_image().get_data(), "animation keeps ground/hard-wall cache unchanged")
	check(dest == board._vp_dest.get_texture().get_image().get_data(), "animation keeps brick/foundation cache unchanged")
	check(redraws == board._painter_dest.cell_redraws, "animation rebuilds zero bricks")
	check(w.map == map_before and w.time == 0.0, "animation does not mutate gameplay or collision")
	board.world = null
	await settle()
	check(vp.get_texture().get_image().get_used_rect().size == Vector2i.ZERO, "clearing world removes carousel and cached map")
	board.queue_free()
	vp.queue_free()
	await process_frame
	# Capture the same Board inside the project's existing map preview, including
	# the real EntityView and the rest of the park's scenery layers.
	var preview_vp := viewport(Vector2i(720,696))
	var preview = load("res://map_preview.tscn").instantiate()
	preview_vp.add_child(preview)
	preview.set_process(false)
	preview.show_theme(2)
	DirAccess.make_dir_recursive_absolute(output + "frames")
	for i in 32:
		preview.board.anim_time = i / 12.8
		preview.board.queue_redraw()
		for actor in preview.actors.get_children():
			actor.update_view(1.0, i / 12.8, 0.0)
		await settle()
		var image := preview_vp.get_texture().get_image()
		image.save_png(output + "frames/%02d.png" % i)
		if i == 8:
			image.save_png(output + "park-gameplay.png")
	print("CAROUSEL_RENDER_CHECKS=%d FAILURES=%d" % [checks,failures])
	quit(1 if failures else 0)
