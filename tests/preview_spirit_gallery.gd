extends SceneTree

## Render all six gallery states with the real fonts, assets and input geometry.
## Run without --headless. Captures stay in .godot rather than player saves.
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/gallery-" + label + ".png")

func run() -> void:
	InputSettings.config_path = "res://.godot/gallery-preview-settings.cfg"
	InputMap.load_from_project_settings()
	InputSettings.ensure_loaded()
	root.size = Vector2i(1080, 1044)
	root.content_scale_size = Vector2i(720, 696)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	var menu: Menu = main.menu
	await process_frame
	menu._open_character()
	if "--gallery-motion" in OS.get_cmdline_user_args():
		await record_motion(menu)
		main.queue_free()
		await process_frame
		DirAccess.remove_absolute(InputSettings.config_path)
		quit()
		return
	var started: Array = []
	menu.start_requested.connect(func(mode, p1, p2): started.append([mode, p1, p2]))
	for i in Cfg.CHAR_IDS.size():
		menu._handle_click(menu._char_rects()[i].get_center())
		check(menu.poster_cid == Cfg.CHAR_IDS[i], "poster transition begins on the selection frame")
		await create_timer(0.3).timeout
		check(menu._char(0) == Cfg.CHAR_IDS[i], "card click selects " + Cfg.CHAR_IDS[i])
		menu.stage_t = 2
		menu.poster_mix = 1
		menu.hover = {}
		menu.set_process(false)
		menu.queue_redraw()
		await capture(Cfg.CHAR_IDS[i])
		menu.set_process(true)
		var tex: Texture2D = menu.poster_tex.get(Cfg.CHAR_IDS[i])
		check(tex != null, "poster imported for " + Cfg.CHAR_IDS[i])
		if tex != null:
			for push in [0.0, 0.04]:
				var uv := SpiritGallery.poster_uv(tex, i, push)
				check(Rect2(0, 0, 1, 1).encloses(uv), "poster crop stays inside source")
				var ratio := uv.size.x * tex.get_width() / (uv.size.y * tex.get_height())
				check(is_equal_approx(ratio, SpiritGallery.HERO.size.x / SpiritGallery.HERO.size.y),
					"poster preserves aspect ratio")
	menu.nav_mode = true
	menu.nav_focus["menu_chars"] = "card:5"
	menu._nav_move("left")
	check(menu._focus_key() == "card:4" and menu._char(0) == "xiaotian", "keyboard navigation selects character")
	await create_timer(0.3).timeout
	await capture("keyboard")
	root.size = Vector2i(720, 696)
	await process_frame
	await capture("720")
	root.size = Vector2i(1080, 1044)
	await process_frame
	menu._open_settings()
	await process_frame
	await capture("settings")
	menu._close_settings()
	menu._handle_click(SpiritGallery.BACK.get_center())
	check(menu.step == "mode", "back button returns to mode selection")
	menu.mode_index = 1
	menu._open_character()
	menu._select_char(5)
	menu._handle_click(SpiritGallery.START.get_center())
	check(started.size() == 1 and started[0][0] == "dig" and started[0][1] == "weilai",
		"start uses selected mode and character")
	check(main.state == main.State.PLAY and main.world != null,
		"dig gallery start enters the actual timed match")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(InputSettings.config_path)
	print("GALLERY_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

## Deterministic 30 fps capture for Godot's --write-movie option.
func record_motion(menu: Menu) -> void:
	root.size = Vector2i(720, 696)
	menu.set_process(false)
	menu.t = 0
	menu.stage_t = 0
	var peak_draws := 0.0
	for frame in 240:
		if frame == 80:
			menu._select_char(1)
		elif frame == 160:
			menu._select_char(4)
		menu.t += 1.0 / 30.0
		menu.stage_t += 1.0 / 30.0
		menu.switch_t = minf(1, menu.switch_t + 4.0 / 30.0)
		menu.poster_mix = minf(1, menu.poster_mix + 4.5 / 30.0)
		menu.gallery_pointer = Vector2(sin(frame * 0.025), cos(frame * 0.02)) * 0.65
		menu.hover = {"kind": "cta"} if frame % 80 > 60 else {}
		menu.queue_redraw()
		await RenderingServer.frame_post_draw
		peak_draws = maxf(peak_draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("GALLERY_MOTION_FRAMES=240 PEAK_DRAW_CALLS=%d" % int(peak_draws))
