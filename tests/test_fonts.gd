extends SceneTree

func _initialize() -> void:
	for name in ["msyh.ttc", "msyhbd.ttc", "consola.ttf", "consolab.ttf", "impact.ttf", "Deng.ttf"]:
		var path = "res://assets/fonts/" + name
		if not ResourceLoader.exists(path):
			print(name, " NOT_IMPORTED")
			continue
		var font = load(path)
		if font == null:
			print(name, " NULL")
			continue
		var size = font.get_string_size("Q版泡泡堂 BOMBIT 12:30", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		print(name, " ok ", size, " faces=", font.get_face_count() if font.has_method("get_face_count") else "?")
	quit(0)
