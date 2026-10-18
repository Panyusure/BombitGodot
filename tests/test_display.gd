extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	InputMap.load_from_project_settings()
	InputSettings.config_path = "res://.godot/display-test-settings.cfg"
	DirAccess.remove_absolute(InputSettings.config_path)
	InputSettings.ensure_loaded()
	check(not InputSettings.fullscreen_enabled(), "new settings start windowed")
	var original_rumble := InputSettings.rumble_enabled()
	InputSettings.set_fullscreen(true)
	InputSettings.set_audio_value("music", 0.4)
	InputSettings._cfg = InputSettings._default_cfg()
	InputSettings._load_file()
	check(InputSettings.fullscreen_enabled(), "fullscreen survives other settings saves and reload")
	check(InputSettings.rumble_enabled() == original_rumble, "display setting preserves rumble preference")
	InputSettings.set_fullscreen(false)
	var backdrop = preload("res://scripts/ScreenBackdrop.gd")
	check(backdrop.content_origin(Vector2(1440, 696)) == Vector2(360, 0), "wide screen centers the fixed playfield")
	check(backdrop.content_origin(Vector2(720, 1000)) == Vector2(0, 152), "portrait screen centers the fixed playfield")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.position == backdrop.content_origin(main.get_viewport_rect().size), "world is centered in actual viewport")
	check(main.get_node("UILayer").offset == main.position, "UI and world share the same centered origin")
	main._on_menu_start("adventure", "xiaonuo", "axiu")
	main._on_overlay_action("start")
	main._pause()
	var frozen_time: float = main.world.time
	main.overlay._nav_step(-1)
	check(main.overlay.index == 3, "pause gear is reachable using controller navigation")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = main.overlay._pause_btn(3).get_center()
	main.overlay._gui_input(click)
	check(main.menu.settings_only and main.menu.settings_open and not main.overlay.visible, "pause gear opens the existing settings panel")
	check(main.menu._focus_items().any(func(item): return item.key == "fullscreen"), "fullscreen setting supports keyboard and controller focus")
	key(KEY_F11, true)
	await process_frame
	key(KEY_F11, false)
	check(InputSettings.fullscreen_enabled() and main.state == main.State.PAUSE, "F11 switches fullscreen while settings keep gameplay paused")
	main.menu._handle_settings_click(main.menu._fullscreen_rect().get_center())
	check(not InputSettings.fullscreen_enabled(), "fullscreen row responds to a mouse click")
	key(KEY_R, true)
	await process_frame
	key(KEY_R, false)
	check(main.state == main.State.PAUSE and main.world.time == frozen_time, "settings cannot restart or advance paused gameplay")
	key(KEY_ESCAPE, true)
	await process_frame
	check(main.state == main.State.PAUSE and main.overlay.visible and not main.menu.visible, "Esc closes settings and keeps the match paused")
	key(KEY_ESCAPE, false)
	await process_frame
	main.overlay._pause_action(3)
	main.menu._nav_accept_settings("done")
	check(main.state == main.State.PAUSE and main.overlay.visible and not main.menu.settings_open, "Done returns to pause without resuming")
	main._on_overlay_action("resume")
	check(main.state == main.State.PLAY and not main.overlay.visible, "pause can still resume after closing settings")
	main._to_menu()
	check(main.menu.visible and not main.menu.settings_only and not main.menu._started, "return to menu clears pause settings state")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(InputSettings.config_path)
	print("DISPLAY_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
