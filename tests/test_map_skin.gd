extends SceneTree

const ArtSkin = preload("res://scripts/MapSkin.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("CHECK_FAIL=" + message)

func _initialize() -> void:
	for theme in Cfg.THEME_IDS:
		var tex: Texture2D = ArtSkin.texture(theme)
		check(tex != null, theme + " imported atlas exists")
		if tex == null:
			continue
		var image := tex.get_image()
		check(image.get_size() == Vector2i(1536, 1024), theme + " atlas dimensions")
		check(image.get_pixel(0, 0).a < 0.01, theme + " background has real alpha")
		for region in ArtSkin.REGIONS[theme]:
			check(Rect2(Vector2.ZERO, image.get_size()).encloses(region), theme + " source crop inside atlas")
			var crop := image.get_region(Rect2i(region))
			var opaque := 0
			var transparent := 0
			for y in range(0, crop.get_height(), 8):
				for x in range(0, crop.get_width(), 8):
					var alpha := crop.get_pixel(x, y).a
					if alpha > 0.9:
						opaque += 1
					if alpha < 0.1:
						transparent += 1
			check(opaque > 300, theme + " sprite contains opaque art")
			check(transparent > 20, theme + " sprite has transparent surroundings")
	print("MAP_SKIN_CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(1 if failures else 0)
