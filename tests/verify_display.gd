extends SceneTree

## Graphical check: run separately from the headless suite. No player saves.
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/" + path)

func run() -> void:
	InputMap.load_from_project_settings()
	InputSettings.config_path = "res://.godot/display-preview-settings.cfg"
	DirAccess.remove_absolute(InputSettings.config_path)
	InputSettings.ensure_loaded()
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.menu._open_settings()
	main.menu._handle_settings_click(main.menu._fullscreen_rect().get_center())
	main.menu._close_settings()
	await create_timer(0.5).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "native window enters fullscreen")
	check(main.position.x >= 0 and main.position.y >= 0, "fullscreen playfield stays centered")
	main.menu.mode_index = 2
	main.menu._open_character()
	await create_timer(0.3).timeout
	await capture("display-lobby.png")
	main.menu.versus_lobby.close()
	main._on_menu_start("adventure", "xiaonuo", "axiu")
	main._on_overlay_action("start")
	main._pause()
	await create_timer(0.3).timeout
	await capture("display-pause.png")
	main._on_overlay_action("settings")
	await process_frame
	await capture("display-settings.png")
	InputSettings.set_fullscreen(false)
	await create_timer(0.5).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "native window exits fullscreen")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(InputSettings.config_path)
	print("DISPLAY_NATIVE_FAILURES=%d" % failures)
	quit(0 if failures == 0 else 1)
