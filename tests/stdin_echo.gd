extends SceneTree
func _initialize() -> void:
	for i in 2:
		var buf := ""
		while true:
			var ch := OS.read_string_from_stdin(1)
			if ch == "":
				break
			if ch == "\n":
				break
			buf += ch
		print("ECHO:", buf)
	quit()
