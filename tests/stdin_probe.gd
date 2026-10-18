extends SceneTree
func _initialize() -> void:
	var out := []
	for i in 8:
		var s := OS.read_string_from_stdin(1)
		out.append(s)
		if s == "":
			break
	print("STDIN=", out)
	quit()
