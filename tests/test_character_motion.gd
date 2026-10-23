extends SceneTree

const Rig = preload("res://scripts/CharacterMotionRig.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("CHECK_FAIL= " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for id in Rig.IDS:
		for rear in [false, true]:
			var rig := Rig.new()
			rig.configure(id, rear)
			var rest: PackedVector2Array = rig._data["rest"]
			var indices := rig.triangle_indices()
			var minimum := INF
			var where := ""
			var unique := {}
			for frame in 16:
				var gait := rig.pose(frame / 16.0, 0.0, true, 0.0)
				unique[hash(gait)] = true
				for secondary in 8:
					var points := rig.pose(frame / 16.0, secondary / 8.0, true)
					for i in range(0, indices.size(), 3):
						var a := indices[i]
						var b := indices[i + 1]
						var c := indices[i + 2]
						var before := (rest[b] - rest[a]).cross(rest[c] - rest[a])
						var after := (points[b] - points[a]).cross(points[c] - points[a])
						var ratio := after / before
						if ratio < minimum:
							minimum = ratio
							where = "%s frame=%d part=%d" % [rest[a], frame, secondary]
			print("METRICS=%s rear=%s min_area=%.4f %s" % [id, rear, minimum, where])
			check(minimum > 0.035, id + " no collapsed or inverted triangles, rear=" + str(rear))
			check(unique.size() == 16, id + " has 16 distinct primary poses")
			check(rig.pose(0.0, 0.0, true) == rig.pose(1.0, 1.0, true), id + " exact cycle closure")
			var a := rig.pose(0.0, 0.25, false)
			var b := rig.pose(0.0, 0.75, false)
			var active_parts := 0
			var stable_feet := true
			for n in rest.size():
				if a[n].distance_to(b[n]) > 0.5:
					active_parts += 1
				if rig._data["leg_weights"][0][n] >= 0.999 or rig._data["leg_weights"][1][n] >= 0.999:
					stable_feet = stable_feet and a[n].is_equal_approx(b[n])
			check(active_parts > 10, id + " has independent secondary motion")
			check(stable_feet, id + " idle secondary motion leaves feet stable")
			var other := Rig.new()
			other.configure(id, rear)
			rig.update(0.25, 0.25, true)
			check(rig.mesh != other.mesh and other.vertices == rest, id + " instances do not share mutable mesh state")
		var actor: Actor = GameEngine.make_player("p1", "1P", Cfg.P1_COLOR, 0, id)
		var view := EntityView.new()
		get_root().add_child(view)
		view.setup(actor, null)
		view.show_tag = false
		view.update_view(1.0, 0.0, 0.0)
		check(view._character_motion and view._character_rig.character_id == id, id + " uses character rig")
		check(view._aura != null and view._aura.tex == view.sprite.texture, id + " existing aura retains original source texture")
		actor.moving = true
		view.update_view(1.0, 0.1, 0.1)
		check(view._gait_phase > 0.0 and view._secondary_phase > 0.0, id + " primary and secondary clocks advance")
		check(view._sx == 1.0 and view._sy == 1.0 and view._bob == 0.0, id + " no extra whole-image distortion")
		var phase: float = view._gait_phase
		var part_phase: float = view._secondary_phase
		actor.facing_dir = "up"
		view.update_view(1.0, 0.1, 0.0)
		check(view._character_rig.back and view._gait_phase == phase and view._secondary_phase == part_phase, id + " turning preserves phases")
		view.notification(CanvasItem.NOTIFICATION_DRAW)
		actor.moving = false
		view.update_view(1.0, 0.2, 0.1)
		check(view._gait_phase == 0.0 and view._secondary_phase != part_phase, id + " stopping settles feet but keeps secondary motion")
		actor.facing_dir = "left"
		actor.facing = -1
		actor.moving = true
		view.update_view(1.0, 0.2, 0.0)
		check(view._flip == -1.0 and not view._character_rig.back, id + " left flips front view")
		view._gait_phase = 0.0
		view.update_view(1.0, 0.3, 0.01)
		var normal: float = view._gait_phase
		view._gait_phase = 0.0
		actor.speed_bonus = 0.5
		view.update_view(1.0, 0.3, 0.01)
		check(absf(view._gait_phase - normal * 1.5) < 0.00001, id + " speed effects scale cadence")
		actor.alive = false
		view.update_view(1.0, 0.3, 0.0)
		check(not view._character_motion and view._alpha == 0.55, id + " death leaves gait and keeps existing fade")
		view.free()
	print("CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
