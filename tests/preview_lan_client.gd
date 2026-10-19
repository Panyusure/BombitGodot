extends SceneTree

## Optional graphical client for MCP/manual host inspection on localhost:24566.
## Uses isolated settings; writes previews inside .godot/ only.
func _init() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/lan-client-" + name + ".png")

func run() -> void:
	InputMap.load_from_project_settings()
	InputSettings.config_path = "res://.godot/lan-preview-settings.cfg"
	DirAccess.remove_absolute(InputSettings.config_path)
	InputSettings.ensure_loaded()
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main._open_lan()
	main.lan.join_room("127.0.0.1")
	var deadline := Time.get_ticks_msec() + 10000
	while main.lan.phase == "connecting" and Time.get_ticks_msec() < deadline:
		await process_frame
	if main.lan.phase == "lobby":
		main.lan.choose(5)
		main.lan.ready_player(true)
		await create_timer(0.4).timeout
		await capture("lobby")
		deadline = Time.get_ticks_msec() + 30000
		while main.lan.phase == "lobby" and Time.get_ticks_msec() < deadline:
			await process_frame
		if main.lan.phase in ["loading", "playing"]:
			await create_timer(1).timeout
			var press := InputEventKey.new()
			press.keycode = KEY_LEFT
			press.pressed = true
			Input.parse_input_event(press)
			Input.flush_buffered_events()
			await create_timer(0.2).timeout
			var release := InputEventKey.new()
			release.keycode = KEY_LEFT
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			print("LAN_PREDICTED_VIEW=%s" % str(main._views["p2"].actor == main.lan.prediction.actor and main._views["p2"].actor != main.world.players[1]))
			await capture("battle")
			await create_timer(3).timeout
	main._to_menu()
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(InputSettings.config_path)
	print("LAN_PREVIEW_DONE")
	quit()
