extends SceneTree

## Real Input events + instantiated UI. All settings writes stay in .godot/.
var checks := 0
var failures := 0
var main: Node
var actions: Array = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func button(device: int, index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index as JoyButton
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func axis(device: int, index: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = index as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code as Key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func defaults() -> void:
	InputSettings._assigned_devices = {"p1": -1, "p2": -1}
	InputSettings._cfg = InputSettings._default_cfg()
	InputSettings._live = InputSettings._clone_table(InputSettings._defaults)
	InputSettings._apply_live()
	InputSettings._seen = {6: true, 9: true}
	InputSettings.active_players = 2

func _init() -> void:
	call_deferred("run")

func run() -> void:
	InputMap.load_from_project_settings()
	InputSettings.config_path = "res://.godot/input-test-settings.cfg"
	DirAccess.remove_absolute(InputSettings.config_path)
	InputSettings.ensure_loaded()
	defaults()
	check(InputSettings.slot_device("p1") == 6 and InputSettings.slot_device("p2") == 9, "two automatic pads are distinct")
	InputSettings.set_device("p1", 9)
	check(InputSettings.slot_device("p1") == 9 and InputSettings.slot_device("p2") == 6, "explicit 1P reserves pad before auto 2P")
	InputSettings.set_device("p1", -1)
	InputSettings.set_device("p2", 6)
	check(InputSettings.slot_device("p1") == 9 and InputSettings.slot_device("p2") == 6, "explicit 2P reserves pad before auto 1P")
	InputSettings.set_device("p1", 6)
	check(InputSettings.slot_device("p2") == -1, "duplicate saved selections never control both players")
	InputSettings.notify_joy_connection(6, false)
	check(InputSettings.slot_device("p1") == -1, "disconnected explicit pad is unavailable")
	key(KEY_RIGHT, true)
	check(InputSettings.poll_player("p1", "solo")["right"], "disconnected pad falls back to keyboard")
	key(KEY_RIGHT, false)
	defaults()
	InputSettings.set_device_mode("p1", InputSettings.MODE_KEYBOARD)
	check(InputSettings.slot_device("p2") == 6, "keyboard 1P leaves first pad for 2P")
	defaults()
	InputSettings.active_players = 1
	InputSettings.set_device("p2", 6)
	check(InputSettings.slot_device("p1") == 6, "inactive 2P does not reserve the solo player's pad")
	defaults()
	axis(6, JOY_AXIS_LEFT_X, 0.1)
	check(not InputSettings.poll_player("p1", "solo")["right"], "stick drift stays below deadzone")
	axis(6, JOY_AXIS_LEFT_X, 0.8)
	check(InputSettings.poll_player("p1", "solo")["right"], "positive stick moves right")
	check(not InputSettings.poll_player("p2", "solo")["right"], "1P stick does not move 2P")
	axis(6, JOY_AXIS_LEFT_X, -0.8)
	check(InputSettings.poll_player("p1", "solo")["left"], "negative stick moves left")
	axis(6, JOY_AXIS_LEFT_X, 0.0)
	button(9, JOY_BUTTON_DPAD_DOWN, true)
	check(InputSettings.poll_player("p2", "solo")["down"], "2P d-pad works")
	check(not InputSettings.poll_player("p1", "solo")["down"], "2P d-pad does not move 1P")
	button(9, JOY_BUTTON_DPAD_DOWN, false)
	button(6, JOY_BUTTON_A, true)
	check(InputSettings.poll_player("p1", "versus")["bomb"], "1P pad bomb works in versus profile")
	check(not InputSettings.poll_player("p2", "solo")["bomb"], "pad bomb is isolated by device")
	InputSettings.set_device_mode("p1", InputSettings.MODE_KEYBOARD)
	check(not InputSettings.poll_player("p1", "solo")["bomb"], "keyboard-only gameplay ignores pad")
	check(InputSettings.poll_nav()["accept"], "pad can recover menu even in keyboard-only mode")
	button(6, JOY_BUTTON_A, false)
	InputSettings.set_device_mode("p1", InputSettings.MODE_GAMEPAD)
	key(KEY_SPACE, true)
	check(not InputSettings.poll_player("p1", "solo")["bomb"], "connected gamepad-only mode ignores keyboard")
	InputSettings.notify_joy_connection(6, false)
	InputSettings.notify_joy_connection(9, false)
	check(InputSettings.poll_player("p1", "solo")["bomb"], "gamepad-only mode recovers keyboard after disconnect")
	key(KEY_SPACE, false)
	defaults()
	check(InputSettings.bind_pad("p1", "bomb", {"type": "button", "index": JOY_BUTTON_B})["ok"], "1P remaps bomb")
	check(InputSettings.bind_pad("p2", "bomb", {"type": "button", "index": JOY_BUTTON_B})["ok"], "2P may use same button on its own pad")
	check(not InputSettings.bind_pad("p1", "skill", {"type": "button", "index": JOY_BUTTON_B})["ok"], "same-player binding conflict is rejected")
	check(not InputSettings.bind_pad("p1", "bomb", {"type": "button", "index": JOY_BUTTON_START})["ok"], "pause button is reserved")
	check(not InputSettings.bind_pad("p1", "bomb", {"type": "button", "index": -1})["ok"], "invalid button is rejected")
	InputSettings.set_deadzone(0.5)
	InputSettings._cfg = InputSettings._default_cfg()
	InputSettings._live = InputSettings._clone_table(InputSettings._defaults)
	InputSettings._load_file()
	check(is_equal_approx(InputSettings.deadzone(), 0.5), "deadzone persists through reload")
	check(InputSettings.pad_labels("p2_bomb") == ["B"], "2P remap persists through reload")
	defaults()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.set_physics_process(false)
	main.menu.set_process(false)
	main.overlay.set_process(false)
	main.menu.reset()
	check(main.menu.focus_state()["key"] == "mode:0", "menu focus begins on selected mode")
	button(6, JOY_BUTTON_A, true)
	main.menu._process_nav(0.016)
	check(main.menu.step == "chars", "A opens character selection")
	main.menu._process_nav(0.5)
	check(main.state == main.State.MENU, "holding A cannot skip character selection")
	button(6, JOY_BUTTON_A, false)
	main.menu._process_nav(0.016)
	button(6, JOY_BUTTON_A, true)
	main.menu._process_nav(0.016)
	check(main.state == main.State.BRIEFING, "second A opens briefing")
	main.overlay._process_nav(0.016)
	check(main.state == main.State.BRIEFING, "held A cannot skip briefing")
	button(6, JOY_BUTTON_A, false)
	main.overlay._process_nav(0.016)
	button(6, JOY_BUTTON_A, true)
	main.overlay._process_nav(0.016)
	check(main.state == main.State.PLAY, "fresh A starts stage")
	check(not main._read_player("p1", 1)["bomb"], "briefing confirmation does not place bomb")
	button(6, JOY_BUTTON_A, false)
	main._read_player("p1", 1)
	button(6, JOY_BUTTON_A, true)
	check(main._read_player("p1", 1)["bomb"], "fresh gameplay A places bomb")
	check(not main._read_player("p1", 1)["bomb"], "holding A produces only one bomb edge")
	button(6, JOY_BUTTON_A, false)
	button(9, JOY_BUTTON_START, true)
	check(main.state == main.State.PLAY, "unassigned pad cannot pause solo player")
	button(9, JOY_BUTTON_START, false)
	button(6, JOY_BUTTON_START, true)
	check(main.state == main.State.PAUSE, "assigned pad Start pauses gameplay")
	button(6, JOY_BUTTON_START, false)
	button(6, JOY_BUTTON_START, true)
	check(main.state == main.State.PLAY, "fresh Start resumes gameplay")
	button(6, JOY_BUTTON_START, false)
	main._pause()
	button(6, JOY_BUTTON_A, true)
	main.overlay._process_nav(0.016)
	check(main.state == main.State.PLAY, "A resumes pause")
	check(not main._read_player("p1", 1)["bomb"], "pause confirmation does not place bomb")
	button(6, JOY_BUTTON_A, false)
	main.overlay.action.disconnect(main._on_overlay_action)
	main.overlay.action.connect(func(name): actions.append(name))
	main.overlay.show_result({"mode": "dig", "winner": "p1"})
	button(6, JOY_BUTTON_DPAD_RIGHT, true)
	main.overlay._process_nav(0.016)
	check(main.overlay.index == 1, "result supports horizontal navigation")
	button(6, JOY_BUTTON_DPAD_RIGHT, false)
	button(6, JOY_BUTTON_A, true)
	main.overlay._process_nav(0.016)
	check(actions == ["menu"], "selected result button returns to menu")
	button(6, JOY_BUTTON_A, false)
	main._to_menu()
	main.menu._open_settings()
	check(main.menu._focus_items().any(func(item): return item["key"] == "done"), "settings Done is focusable")
	main.menu._nav_accept_settings("done")
	check(not main.menu.settings_open, "Done closes settings")
	main.menu._open_settings()
	main.menu.capture_target = {"group": "p1", "func": "bomb", "kind": "pad", "index": 4}
	button(6, JOY_BUTTON_BACK, true)
	check(main.menu.capture_target.is_empty(), "Back cancels rebinding with no keyboard")
	main.menu._process_nav(0.016)
	check(main.menu.settings_open, "capture cancel does not also close settings")
	button(6, JOY_BUTTON_BACK, false)
	main.menu._close_settings()
	main._on_replay_requested()
	button(6, JOY_BUTTON_B, true)
	main.replay_ui._process(0.016)
	check(main.state == main.State.MENU, "gamepad can exit replay browser without keyboard")
	button(6, JOY_BUTTON_B, false)
	var line := UIDraw.fit("超长手柄设备名称 Wireless Game Controller", 100, 12)
	check(line.ends_with("…") and UIDraw.measure(line, 12) <= 100, "long device names fit their actual font width")
	var single := UIDraw.wrap_lines("这是一段不能超过一行的很长说明文字", 80, 12, 1)
	check(single.size() == 1 and single[0].ends_with("…"), "one-line wrapping respects line limit")
	var multiline := UIDraw.wrap_lines("第一行\n第二行\n第三行", 100, 12, 2)
	check(multiline.size() == 2 and UIDraw.measure(multiline[1], 12, 500) <= 100, "wrapping handles explicit newlines and final ellipsis")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(InputSettings.config_path)
	print("INPUT_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
