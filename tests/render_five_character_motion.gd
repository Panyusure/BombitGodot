extends Node2D

const Rig = preload("res://scripts/CharacterMotionRig.gd")
const OUTPUT := "E:/MinimaxH3/deliverables/five_character_walks/"

class Gallery extends Node2D:
	var rigs: Array = []
	var textures: Array = []
	func _draw() -> void:
		for i in rigs.size():
			var index := i % 5
			var row := i / 5
			var cfg := Cfg.char_cfg(rigs[i].character_id)
			var anchor: Vector2 = cfg["anchor"]
			var source_width := float(textures[i].get_width())
			var offset := Vector2(index * 512.0 + 256.0 - source_width * 0.4, row * 640.0 + 530.0 - 560.0 * anchor.y * 0.8)
			draw_mesh(rigs[i].mesh, textures[i], Transform2D(0.0, Vector2.ONE * 0.8, 0.0, offset))

func _ready() -> void:
	call_deferred("render_assets")

func render_assets() -> void:
	for id in Rig.IDS:
		for name in ["front", "back", "idle_front", "idle_back"]:
			DirAccess.make_dir_recursive_absolute(OUTPUT + id + "/" + name)
	DirAccess.make_dir_recursive_absolute(OUTPUT + "video_frames")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560, 1280)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var gallery := Gallery.new()
	for rear in [false, true]:
		for id in Rig.IDS:
			var rig := Rig.new()
			rig.configure(id, rear)
			gallery.rigs.append(rig)
			gallery.textures.append(load("res://assets/characters/%s%s.png" % [id, "-back" if rear else ""]))
	viewport.add_child(gallery)
	for moving in [true, false]:
		for frame in 16:
			for rig in gallery.rigs:
				var profile: Dictionary = Rig.Profiles.PROFILES[rig.character_id]
				rig.update(frame / 16.0, frame / 16.0, moving, 1.0 if moving else float(profile["idle_strength"]))
			gallery.queue_redraw()
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			for i in gallery.rigs.size():
				var rig = gallery.rigs[i]
				var direction := "back" if rig.back else "front"
				var prefix := "" if moving else "idle_"
				image.get_region(Rect2i((i % 5) * 512, (i / 5) * 640, 512, 640)).save_png(OUTPUT + rig.character_id + "/" + prefix + direction + "/%02d.png" % frame)
	for frame in 120:
		var t := frame / 24.0
		for rig in gallery.rigs:
			var profile: Dictionary = Rig.Profiles.PROFILES[rig.character_id]
			rig.update(fposmod(t * float(profile["stride"]) / TAU, 1.0), fposmod(t * float(profile["secondary_rate"]), 1.0), true)
		gallery.queue_redraw()
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(OUTPUT + "video_frames/%03d.png" % frame)
	var output := FileAccess.open(OUTPUT + "render_complete.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"characters": Rig.IDS, "walk_frames_per_direction": 16, "idle_frames_per_direction": 16,
		"frame_size": [512, 640], "video_frames": 120, "fps": 24, "total_transparent_frames": 320}))
	output.close()
	print("CHARACTER_RENDER_COMPLETE=320 transparent frames and 120 gallery video frames")
	get_tree().quit()
