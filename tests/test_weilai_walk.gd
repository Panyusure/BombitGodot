extends SceneTree

const Walk = preload("res://scripts/WeilaiWalk.gd")
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
	var a: Actor = GameEngine.make_player("p1", "1P", Cfg.P1_COLOR, 0, "weilai")
	var v := EntityView.new()
	get_root().add_child(v)
	v.setup(a, null)
	v.show_tag = false
	v.update_view(1.0, 0.0, 0.0)
	check(not v._walking and not v.sprite.texture is AtlasTexture, "idle uses original standing art")
	var standing_sole := v._display.y * (1.0 - v._anchor.y)
	a.moving = true
	v.update_view(1.0, 0.0, 0.0)
	check(v._walking and v.sprite.texture is AtlasTexture, "movement starts front animation")
	var sole := v.sprite.position.y + Walk.PIVOT.y * Walk.FRAME_SIZE.y * v._scale
	check(absf(sole - standing_sole) < 0.001, "idle and walk have matching sole baseline")
	var frames := {}
	for i in 192:
		v.update_view(1.0, i / 192.0, TAU / 10.8 / 192.0)
		var texture: AtlasTexture = v.sprite.texture
		frames[str(texture.region.position)] = true
		v.notification(CanvasItem.NOTIFICATION_DRAW)
	check(frames.size() == 16, "full cycle visits exactly 16 distinct frames")
	check(v._bob == 0.0 and v._wob == 0.0 and v._sx == 1.0 and v._sy == 1.0, "authored gait avoids extra procedural distortion")
	var phase: float = v._walk_phase
	a.facing_dir = "up"
	v.update_view(1.0, 1.0, 0.0)
	var back: AtlasTexture = v.sprite.texture
	check(back.atlas.resource_path.ends_with("walk_back.png"), "up selects back atlas")
	check(v._walk_phase == phase, "changing direction preserves cycle phase")
	a.moving = false
	v.update_view(1.0, 1.0, 0.0)
	check(not v._walking and v.sprite.texture.resource_path.ends_with("weilai-back.png"), "stop returns to back standing art")
	a.moving = true
	a.facing_dir = "left"
	a.facing = -1
	v.update_view(1.0, 1.0, 0.01)
	check(v._walking and v._flip == -1.0, "left flips front animation")
	a.facing_dir = "right"
	a.facing = 1
	v.update_view(1.0, 1.0, 0.01)
	check(v._flip == 1.0, "right uses unflipped front animation")
	v._walk_phase = 0.0
	v.update_view(1.0, 1.0, 0.01)
	var normal: float = v._walk_phase
	v._walk_phase = 0.0
	a.speed_bonus = 0.5
	v.update_view(1.0, 1.0, 0.01)
	check(absf(v._walk_phase - normal * 1.5) < 0.00001, "speed bonus scales cadence")
	a.speed_bonus = 0.0
	v._walk_phase = 0.0
	a.slow_time = 1.0
	v.update_view(1.0, 1.0, 0.01)
	check(absf(v._walk_phase - normal * 0.5) < 0.00001, "slow effect scales cadence")
	a.slow_time = 0.0
	a.soul_evolved = true
	v.update_view(1.0, 1.0, 0.01)
	check(not v._walking and not v.sprite.texture is AtlasTexture and v._soul_glow.visible, "awakening retains existing art and glow")
	a.soul_evolved = false
	a.alive = false
	v.update_view(1.0, 1.0, 0.01)
	check(not v._walking and v._alpha == 0.55, "death exits gait and retains fade")
	v.free()
	for id in ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian"]:
		var other: Actor = GameEngine.make_player("p1", "1P", Cfg.P1_COLOR, 0, id)
		other.moving = true
		var view := EntityView.new()
		get_root().add_child(view)
		view.setup(other, null)
		view.update_view(1.0, 0.2, 0.2)
		check(view._character_motion and not view._walking and not view.sprite.texture is AtlasTexture, id + " uses its own rig with the original texture")
		view.notification(CanvasItem.NOTIFICATION_DRAW)
		view.free()
	print("CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
