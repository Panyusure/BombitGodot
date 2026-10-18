extends SceneTree
func _initialize() -> void:
	print(ProjectSettings.globalize_path("user://"))
	print(ProjectSettings.globalize_path("user://bombit"))
	quit(0)
