extends Node2D

const ArtSkin = preload("res://scripts/MapSkin.gd")
const THEMES := ["forest", "factory", "park"]
const TITLES := ["晨露森林", "星汽工厂", "星糖游乐园"]
const NOTES := ["古树落果 · 石墙与木箱", "传送带运送 · 钢墙与纸箱", "木马环道 · 陶瓷与礼盒"]
var index := 0
var world: World
var board: Node2D
var actors: Node2D
var font: Font = preload("res://assets/fonts/msyh.ttc")
var elapsed := 1.25

func _ready() -> void:
	board = load("res://scripts/Board.gd").new()
	board.position = Vector2(0, 48)
	add_child(board)
	actors = Node2D.new()
	actors.position = board.position
	add_child(actors)
	show_theme(0)
	if "--capture-maps" in OS.get_cmdline_user_args():
		capture_maps()

func show_theme(value: int) -> void:
	index = posmod(value, THEMES.size())
	world = GameEngine.create_world({"mode": "dig", "seed": "map-redesign-20261023", "chars": ["xiaonuo"]})
	GameEngine.apply_level(world, LevelGen.generate(Rng.new(20261023), {
		"mode": "dig", "theme": THEMES[index], "spawns": world.spawns}))
	world.briefing = false
	board.world = world
	board.anim_time = elapsed
	for child in actors.get_children():
		actors.remove_child(child)
		child.queue_free()
	var player: Actor = world.players[0]
	player.invuln = 0
	var view := EntityView.new()
	actors.add_child(view)
	view.setup(player, font)
	view.update_view(1, elapsed, 0)
	# Reference props use free cells only, so previews show the actual layout.
	var available := []
	for r in range(2, 4):
		for c in range(2, 13):
			if Grid.at(world.map, c, r) == Cfg.T_EMPTY:
				available.append(Vector2i(c, r))
	for i in mini(3, available.size()):
		var cell: Vector2i = available[i]
		world.items.append({"c": cell.x, "r": cell.y, "type": ["fire", "bomb", "speed"][i], "born": 0.0})
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 48), Color("243d47"))
	draw_string(font, Vector2(18, 30), TITLES[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("fff2d5"))
	draw_string(font, Vector2(194, 29), NOTES[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b9d6ce"))
	draw_string(font, Vector2(549, 29), "1 / 2 / 3 切换主题", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff2d5"))
	draw_rect(Rect2(0, 672, 720, 24), Color("243d47"))
	draw_string(font, Vector2(16, 689), "低对比地面：通行     厚重硬墙：阻挡     包装箱/礼盒：可炸     中央设施：3×3", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e2e7d8"))

func _process(delta: float) -> void:
	elapsed += delta
	board.anim_time = elapsed
	board.queue_redraw()
	for child in actors.get_children():
		child.update_view(1, elapsed, delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_3:
			show_theme(event.keycode - KEY_1)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()

func capture_maps() -> void:
	var output := OS.get_environment("BOMBIT_MAP_CAPTURE_DIR")
	if output.is_empty():
		output = ProjectSettings.globalize_path("user://map-redesign")
	output = output.trim_suffix("/").trim_suffix("\\") + "/"
	DirAccess.make_dir_recursive_absolute(output)
	var contact := Image.create(2160, 696, false, Image.FORMAT_RGBA8)
	for i in THEMES.size():
		show_theme(i)
		for frame in 8:
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.resize(720, 696, Image.INTERPOLATE_LANCZOS)
		image.save_png(output + THEMES[i] + "-map.png")
		contact.blit_rect(image, Rect2i(0, 0, 720, 696), Vector2i(i * 720, 0))
	contact.save_png(output + "three-theme-overview.png")
	# Atlas extraction only: preserve the generated RGBA pixels exactly.
	for theme in THEMES:
		var atlas := Image.load_from_file(ProjectSettings.globalize_path(ArtSkin.PATHS[theme]))
		var names := ["border", "hard", "soft-a", "soft-b", "soft-c", "landmark"]
		for i in names.size():
			atlas.get_region(Rect2i(ArtSkin.REGIONS[theme][i])).save_png(output + theme + "-" + names[i] + ".png")
	print("MAP_PREVIEW_CAPTURE=3 themes, 18 sprites, overview")
	get_tree().quit()
