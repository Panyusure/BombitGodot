extends SceneTree
func _initialize() -> void:
	print("ARGS=", OS.get_cmdline_user_args())
	quit(0)
