extends SceneTree
const Core = preload("res://scripts/cli/BombitCore.gd")
func _initialize() -> void:
	print("STEP1")
	var core = Core.new("E:/BombitGodot/.bombit-test")
	var a = core.handle({"op":"new","agent":"probe","mode":"dig","seed":"batchtest","session":"batch-probe"})
	print("STEP2 ", a.get("ok"))
	var b = core.handle({"op":"batch","session":"batch-probe","steps":[{"move":"down","frames":2}]})
	print("STEP3 ", b.get("ok"), " ", b.get("revision"))
	quit(0)
