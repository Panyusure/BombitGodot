extends RefCounted

## Generated artwork is presentation only. Coordinates and RNG belong to LevelGen.
const PATHS := {
	"forest": "res://assets/maps/forest-chibi-atlas.png",
	"factory": "res://assets/maps/factory-chibi-atlas.png",
	"park": "res://assets/maps/park-atlas.png",
}
static var _textures := {}
## Explicit art bounds remove unused atlas padding and keep the tall landmarks intact.
const REGIONS := {
	"forest": [Rect2(25,45,475,450), Rect2(535,45,465,450), Rect2(1040,50,475,428), Rect2(35,525,465,460), Rect2(535,525,460,460), Rect2(995,478,535,530)],
	"factory": [Rect2(40,35,460,470), Rect2(540,35,460,470), Rect2(1040,45,475,455), Rect2(40,530,460,450), Rect2(540,530,460,450), Rect2(1010,500,515,500)],
	"park": [Rect2(65,35,425,455), Rect2(560,35,420,450), Rect2(1060,45,420,430), Rect2(70,540,420,435), Rect2(565,540,420,435), Rect2(1025,475,495,530)],
}
## Visible block bodies, excluding atlas gutters and soft cast shadows. These
## rectangular footprints fill the grid independently of sprite aspect ratio.
## The tree / generator / carousel keep their own proportional fitting below.
const BLOCK_REGIONS := {
	"forest": [Rect2(53,73,431,408), Rect2(555,72,426,409), Rect2(1063,82,410,394), Rect2(57,543,429,418), Rect2(561,552,413,403)],
	"factory": [Rect2(63,56,429,434), Rect2(563,56,412,434), Rect2(1057,65,427,419), Rect2(60,551,424,405), Rect2(560,551,414,405)],
	"park": [Rect2(83,56,398,417), Rect2(575,55,388,414), Rect2(1080,64,376,394), Rect2(96,559,376,394), Rect2(581,559,377,394)],
}

static func texture(theme: String) -> Texture2D:
	if not _textures.has(theme):
		var path: String = PATHS.get(theme, "")
		_textures[theme] = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	return _textures[theme]

static func sprite(ci: CanvasItem, theme: String, index: int, target: Rect2) -> bool:
	var tex := texture(theme)
	if tex == null:
		return false
	if index < 5:
		var body: Rect2 = BLOCK_REGIONS[theme][index]
		var fitted_block := target.grow(-0.35)
		# A material-colored contact edge fills chamfered corners; it stays inside
		# the collision cell, so adjacent tiles share a narrow grounded seam.
		var edge := Color("78a581") if index < 2 else Color("be8745")
		if theme == "factory":
			edge = Color("599e9d") if index < 2 else Color("c29158")
		elif theme == "park":
			edge = Color("92758f") if index < 2 else Color("b68799")
		UIDraw.fill_rr(ci, fitted_block.position.x, fitted_block.position.y,
			fitted_block.size.x, fitted_block.size.y, 2.0, edge)
		ci.draw_texture_rect_region(tex, fitted_block, body, Color.WHITE, false, true)
		return true
	var source: Rect2 = REGIONS[theme][index]
	var factor := minf((target.size.x - 2) / source.size.x, (target.size.y - 2) / source.size.y)
	var size := source.size * factor
	var fitted := Rect2(target.position + (target.size - size) / 2, size)
	ci.draw_texture_rect_region(tex, fitted, source, Color.WHITE, false, true)
	return true

static func hard(ci: CanvasItem, c: int, r: int, theme: String) -> bool:
	var edge := c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1
	return sprite(ci, theme, 0 if edge else 1, Rect2(c * 48, r * 48, 48, 48))

static func brick(ci: CanvasItem, c: int, r: int, theme: String, variant: int) -> bool:
	return sprite(ci, theme, 2 + posmod(variant, 3), Rect2(c * 48, r * 48, 48, 48))

static func landmark(ci: CanvasItem, lm: Dictionary) -> bool:
	var c := int(lm.get("c", 7))
	var r := int(lm.get("r", 6))
	var theme := String(lm.get("theme", ""))
	if texture(theme) == null:
		return false
	var x := (c - 1) * 48.0
	var y := (r - 1) * 48.0
	# A continuous foundation makes all nine blocked cells visible, even beside
	# the narrower tree trunk / carousel body. It never extends onto the loop.
	var edge := Color("82a477")
	var top := Color("d6e1b5")
	if theme == "factory":
		edge = Color("6caaa7")
		top = Color("b6d8d1")
	elif theme == "park":
		edge = Color("9d7d9f")
		top = Color("d6bfc9")
	UIDraw.fill_rr(ci, x + 1, y + 1, 142, 142, 7, edge)
	UIDraw.fill_rr(ci, x + 4, y + 3, 136, 136, 5, top)
	UIDraw.stroke_rr(ci, x + 6, y + 5, 132, 132, 4, Color("fff5d760"), 1)
	# Park's foundation is cached here; its H3 carousel is drawn by Board at
	# game time, so the old static pavilion never shows beneath transparent frames.
	if theme == "park":
		return true
	# The entire painted object is constrained to the same central 3x3 hard core.
	return sprite(ci, theme, 5, Rect2(x + 3, y + 3, 138, 138))

static func floor_map(ci: CanvasItem, theme: String) -> bool:
	if texture(theme) == null:
		return false
	var ground := Color("b6cf9a")
	var alternate := Color("bbd39f")
	var joint := Color("729d6b26")
	if theme == "factory":
		ground = Color("b8d8d4")
		alternate = Color("c0deda")
		joint = Color("6eaaa530")
	elif theme == "park":
		ground = Color("e6d6cb")
		alternate = Color("ecdcd3")
		joint = Color("ad8eaa35")
	ci.draw_rect(Rect2(0, 0, Cfg.FIELD_W, Cfg.FIELD_H), ground)
	for r in Cfg.ROWS:
		for c in Cfg.COLS:
			var x := c * 48.0
			var y := r * 48.0
			var seed := posmod(c * 73 + r * 31, 19)
			ci.draw_rect(Rect2(x, y, 48, 48), alternate if (c + r) % 2 == 0 else ground)
			ci.draw_rect(Rect2(x + 0.5, y + 0.5, 47, 47), joint, false, 0.75)
			if c == 0 or r == 0 or c == Cfg.COLS - 1 or r == Cfg.ROWS - 1:
				continue
			if theme == "forest":
				if seed % 4 == 0:
					for k in 3:
						var p := Vector2(x + 8 + k * 3, y + 39)
						ci.draw_line(p, p + Vector2(k - 1, -3 - k % 2), Color("577c5a60"), 1, true)
				if (c == 5 or c == 9 or r == 4 or r == 8) and seed % 2 == 0:
					UIDraw.fill_rr(ci, x + 12, y + 14, 25, 19, 6, Color("d4d3ac50"))
			elif theme == "factory":
				ci.draw_line(Vector2(x + 5, y + 5), Vector2(x + 42, y + 5), Color("e6efea65"), 1, true)
				if seed % 3 == 0:
					for dx in [7, 41]:
						ci.draw_circle(Vector2(x + dx, y + 41), 1.0, Color("79aaa680"), true, -1, true)
			else:
				UIDraw.stroke_rr(ci, x + 4, y + 4, 40, 40, 6, Color("fff6e850"), 1)
				if seed == 5:
					MapArt._spirit_spark(ci, x + 11, y + 12, 2.5, Color("fff6d588"))
	return true
