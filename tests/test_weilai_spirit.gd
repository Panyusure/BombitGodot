extends SceneTree

const Rig = preload("res://scripts/WeilaiSpiritRig.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CHECK_FAIL= " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for rear in [false, true]:
		var rig := Rig.new()
		rig.configure(rear)
		var rest: PackedVector2Array = rig._data["rest"]
		var indices: PackedInt32Array = rig.triangle_indices()
		var folded := 0
		var minimum := INF
		var minimum_at := ""
		var poses := {}
		for frame in 16:
			poses[str(Rig.gait_offset(Vector2(317 if rear else 333, 548), rear, frame / 16.0))] = true
			for wing in 8:
				var points: PackedVector2Array = rig.pose(frame / 16.0, wing / 8.0, true)
				for i in range(0, indices.size(), 3):
					var ia := indices[i]
					var ib := indices[i + 1]
					var ic := indices[i + 2]
					var before := (rest[ib] - rest[ia]).cross(rest[ic] - rest[ia])
					var after := (points[ib] - points[ia]).cross(points[ic] - points[ia])
					var ratio := after / before
					if ratio < minimum:
						minimum = ratio
						minimum_at = "point=%s frame=%d wing=%d" % [rest[ia], frame, wing]
					if ratio <= 0.02:
						folded += 1
		check(folded == 0, "rear=%s no folded/collapsed triangles: minimum %.4f %s" % [rear, minimum, minimum_at])
		check(poses.size() == 16, "rear=%s has 16 distinct leg poses" % rear)
		check(rig.pose(0.0, 0.0, true) == rig.pose(1.0, 1.0, true), "rear=%s exact loop closure" % rear)
		var a: PackedVector2Array = rig.pose(0.0, 0.25, false)
		var b: PackedVector2Array = rig.pose(0.0, 0.75, false)
		var moving_wings := 0
		var foot_motion := 0.0
		var face_motion := 0.0
		for i in rest.size():
			if rest[i].x < 100.0 and rest[i].y < 310.0 and a[i].distance_to(b[i]) > 5.0:
				moving_wings += 1
			if rest[i].y > 526.0 and absf(rest[i].x - 345.0) < 67.0:
				foot_motion = maxf(foot_motion, a[i].distance_to(b[i]))
			if rest[i].y > 336.0 and rest[i].y < 400.0 and rest[i].x > 305.0 and rest[i].x < 401.0:
				face_motion = maxf(face_motion, a[i].distance_to(b[i]))
		check(moving_wings > 50, "rear=%s wings move visibly while idle" % rear)
		check(foot_motion < 0.001, "rear=%s idle wings never drag feet" % rear)
		check(face_motion < 0.001, "rear=%s wing motion preserves girl face" % rear)
		rig.update(0.25, 0.50, true)
		check(rig.mesh.get_surface_count() == 1, "dynamic mesh updates without recreating surfaces")
	var actor: Actor = GameEngine.make_player("p1", "1P", Cfg.P1_COLOR, 0, "weilai")
	actor.soul_evolved = true
	var view := EntityView.new()
	get_root().add_child(view)
	view.setup(actor, null)
	view.update_view(1.0, 0.1, 0.1)
	check(view._spirit_active and not view._walking, "awake idle uses spirit rig")
	check(view._soul_glow.visible and view._soul_glow.sdf_info().get("baked", false), "keeps original offline SDF glow")
	var wing_before: float = view._wing_phase
	actor.moving = true
	view.update_view(1.0, 0.2, 0.1)
	check(view._spirit_phase > 0.0 and view._wing_phase != wing_before, "legs and wings have separate clocks")
	check(view._bob == 0.0 and view._wob == 0.0 and view._sx == 1.0 and view._sy == 1.0, "awake walking avoids procedural distortion")
	var gait_before: float = view._spirit_phase
	var wing_now: float = view._wing_phase
	actor.facing_dir = "up"
	view.update_view(1.0, 0.2, 0.0)
	check(view._spirit_rig.back and view._spirit_phase == gait_before and view._wing_phase == wing_now, "back turn preserves both clocks")
	actor.moving = false
	view.update_view(1.0, 0.3, 0.1)
	check(view._spirit_phase == 0.0 and view._wing_phase != wing_now, "stopping resets gait while wings continue")
	view.notification(CanvasItem.NOTIFICATION_DRAW)
	actor.facing_dir = "left"
	actor.facing = -1
	actor.moving = true
	view.update_view(1.0, 0.3, 0.0)
	check(not view._spirit_rig.back and view._flip == -1.0, "left flips complete front spirit")
	actor.soul_evolved = false
	view.update_view(1.0, 0.3, 0.0)
	check(not view._spirit_active and view._walking and view.sprite.texture is AtlasTexture, "normal form retains existing walk")
	actor.soul_evolved = true
	actor.alive = false
	view.update_view(1.0, 0.3, 0.0)
	check(not view._spirit_active and not view._walking, "death leaves both walk rigs")
	view.free()
	print("CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
