extends Node2D

const Rig = preload("res://scripts/WeilaiSpiritRig.gd")
const OUTPUT := "E:/MinimaxH3/deliverables/weilai_spirit_walk/"

class SpritePreview extends Node2D:
	var rigs: Array = []
	var textures: Array[Texture2D] = []
	func _draw() -> void:
		for i in 2:
			var scale_value := 0.69
			var w := float(textures[i].get_width())
			var x := i * 512.0 + 256.0 - w * scale_value * 0.5
			var tr := Transform2D(0.0, Vector2.ONE * scale_value, 0.0, Vector2(x, 446.0 - 560.0 * scale_value))
			draw_mesh(rigs[i].mesh, textures[i], tr)

func _ready() -> void:
	call_deferred("render_assets")

func render_assets() -> void:
	for folder in ["front", "back", "idle_front", "idle_back", "video_frames"]:
		DirAccess.make_dir_recursive_absolute(OUTPUT + folder)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 480)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var preview := SpritePreview.new()
	for rear in [false, true]:
		var rig := Rig.new()
		rig.configure(rear)
		preview.rigs.append(rig)
		preview.textures.append(load("res://assets/characters/weilai-awakened%s.png" % ("-back" if rear else "")))
	viewport.add_child(preview)
	for moving in [true, false]:
		for frame in 16:
			for rig in preview.rigs:
				rig.update(float(frame) / 16.0, float(frame) / 16.0, moving)
			preview.queue_redraw()
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var prefix := "" if moving else "idle_"
			for side in 2:
				var name := prefix + ("front" if side == 0 else "back")
				image.get_region(Rect2i(side * 512, 0, 512, 480)).save_png(OUTPUT + name + "/%02d.png" % frame)
	for frame in 120:
		var t := frame / 24.0
		for rig in preview.rigs:
			rig.update(fposmod(t * 9.0 / TAU, 1.0), fposmod(t * 1.45, 1.0), true)
		preview.queue_redraw()
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(OUTPUT + "video_frames/%03d.png" % frame)
	var out := FileAccess.open(OUTPUT + "render_complete.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"walk_frames_per_direction": 16, "idle_wing_frames_per_direction": 16,
		"frame_size": [512, 480], "preview_frames": 120, "preview_fps": 24, "mesh_vertices": preview.rigs[0].vertices.size()}))
	out.close()
	print("SPIRIT_RENDER_COMPLETE=64 transparent frames and 120 video frames")
	get_tree().quit()
