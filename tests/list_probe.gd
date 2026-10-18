extends SceneTree
const Core = preload("res://scripts/cli/BombitCore.gd")
func _initialize() -> void:
	var core = Core.new()
	var list = core.list_replays()
	print("COUNT=", list.size())
	for x in list:
		print(x["file"], " | ", x["actions"])
	quit(0)
