extends RefCounted

## Source-texture cage animation: 16 leg poses plus an independent wing clock.
## All original RGBA pixels and the renderer's effect ordering are retained.
const FRAME_COUNT := 16
static var _cache: Dictionary = {}
var mesh: ArrayMesh
var back := false
var vertices := PackedVector2Array()
var _data: Dictionary

static func frame_index(phase: float) -> int:
	return posmod(floori(phase * FRAME_COUNT), FRAME_COUNT)

static func _ease(lo: float, hi: float, value: float) -> float:
	var t := clampf((value - lo) / (hi - lo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _oval(p: Vector2, center: Vector2, radius: Vector2) -> float:
	return 1.0 - _ease(0.65, 1.25, ((p - center) / radius).length())

static func wing_basis(p: Vector2, rear: bool) -> Array[Vector2]:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	for side in 2:
		var left := side == 0
		var root := Vector2(206, 126) if rear else Vector2(201, 148)
		if not left:
			root = Vector2(473, 126) if rear else Vector2(478, 136)
		var w: float
		if rear:
			w = 1.0 - _ease(175.0, 274.0, p.x) if left else _ease(422.0, 521.0, p.x)
			w *= 1.0 - _ease(495.0, 563.0, p.y)
		else:
			w = 1.0 - _ease(155.0, 252.0, p.x) if left else _ease(422.0, 519.0, p.x)
			w *= 1.0 - _ease(326.0, 436.0, p.y)
		# Keep the circular spirit weapons and wrists rigid, rather than
		# squeezing them as if they were feathers.
		var disk := Vector2(121, 375) if rear else Vector2(142, 380)
		if not left:
			disk = Vector2(556, 375) if rear else Vector2(584, 390)
		w *= 1.0 - _oval(p, disk, Vector2(76, 88))
		var sign_side := 1.0 if left else -1.0
		var d := p - root
		a += Vector2(-d.y, d.x) * (sign_side * (0.075 if rear else 0.110) * w)
		a += Vector2(d.x * (0.030 if rear else 0.045) * w, 0.0)
		var tip := _ease(70.0, 250.0, d.length())
		b += Vector2(sign_side * 3.0, 5.0) * (w * tip)
	# The guardian hovers subtly; the girl's face is below this mask.
	a.y += (1.0 - _ease(260.0, 330.0, p.y)) * 0.85
	return [a, b]

static func gait_offset(p: Vector2, rear: bool, phase: float) -> Vector2:
	var angle := phase * TAU
	var bob := 0.65 * (1.0 + cos(angle * 2.0))
	var center := 338.0 if rear else 355.0
	var girl := (1.0 - _ease(82.0, 121.0, absf(p.x - center))) * _ease(272.0, 320.0, p.y)
	var result := Vector2(0.30 * sin(angle), bob) * girl * (1.0 - _ease(479.0, 508.0, p.y))
	for side in 2:
		var left := side == 0
		var cx: float = (317.0 if left else 356.0) if rear else (333.0 if left else 386.0)
		var radius := 18.0 if rear else 24.0
		var weight := (1.0 - _ease(radius - 2.0, radius + 10.0, absf(p.x - cx))) * _ease(477.0 if rear else 475.0, 495.0, p.y)
		if weight < 0.00001:
			continue
		var local := angle + (0.0 if left else PI)
		var swing := maxf(0.0, -sin(local))
		var lift := swing * (9.0 if rear else 10.0)
		var forward := cos(local)
		var ys := PackedFloat32Array([482.0, 507.0, 536.0, 555.0])
		var offsets := PackedVector2Array([
			Vector2(0.30 * sin(angle), bob),
			Vector2(forward * 1.0, bob * 0.45 - lift * 0.40),
			Vector2(forward * 1.8, forward * 1.6 - lift),
			Vector2(forward * 1.8, forward * 1.6 - lift + 1.0 * maxf(0.0, sin(local))),
		])
		var segment := 0 if p.y < ys[1] else (1 if p.y < ys[2] else 2)
		var t := clampf((p.y - ys[segment]) / (ys[segment + 1] - ys[segment]), 0.0, 1.0)
		result += offsets[segment].lerp(offsets[segment + 1], t) * weight
	return result

static func _make_data(rear: bool) -> Dictionary:
	var size := Vector2(677 if rear else 674, 560)
	var xs: Array[float] = []
	var ys: Array[float] = []
	for x in range(0, int(size.x), 14):
		xs.append(float(x))
	for x in range(294, 423, 8):
		if not xs.has(float(x)):
			xs.append(float(x))
	xs.append(size.x)
	xs.sort()
	for y in range(0, 560, 12):
		ys.append(float(y))
	for y in range(478, 557, 6):
		if not ys.has(float(y)):
			ys.append(float(y))
	ys.append(560.0)
	ys.sort()
	var rest := PackedVector2Array()
	var uvs := PackedVector2Array()
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for y in ys:
		for x in xs:
			var p := Vector2(x, y)
			rest.append(p)
			uvs.append(p / size)
			var wings := wing_basis(p, rear)
			a.append(wings[0])
			b.append(wings[1])
	var indices := PackedInt32Array()
	for row in ys.size() - 1:
		for col in xs.size() - 1:
			var i := row * xs.size() + col
			indices.append_array(PackedInt32Array([i, i + 1, i + xs.size(), i + 1, i + xs.size() + 1, i + xs.size()]))
	var gaits: Array[PackedVector2Array] = []
	for frame in FRAME_COUNT:
		var posed := PackedVector2Array()
		for p in rest:
			posed.append(p + gait_offset(p, rear, float(frame) / FRAME_COUNT))
		gaits.append(posed)
	return {"size": size, "rest": rest, "uvs": uvs, "indices": indices, "wing_a": a, "wing_b": b, "gaits": gaits}

func configure(rear: bool) -> void:
	back = rear
	if not _cache.has(rear):
		_cache[rear] = _make_data(rear)
	_data = _cache[rear]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _data["rest"]
	arrays[Mesh.ARRAY_TEX_UV] = _data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = _data["indices"]
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.custom_aabb = AABB(Vector3(-60, -60, -1), Vector3(_data["size"].x + 120, 680, 2))
	vertices = _data["rest"].duplicate()

func pose(gait_phase: float, wing_phase: float, moving: bool) -> PackedVector2Array:
	var out: PackedVector2Array = (_data["gaits"][frame_index(gait_phase)] if moving else _data["rest"]).duplicate()
	var a: PackedVector2Array = _data["wing_a"]
	var b: PackedVector2Array = _data["wing_b"]
	var wrapped := fposmod(wing_phase, 1.0)
	var wave := sin(wrapped * TAU)
	var lag := sin(wrapped * TAU - 0.65)
	for i in out.size():
		out[i] += a[i] * wave + b[i] * lag
	return out

func update(gait_phase: float, wing_phase: float, moving: bool) -> void:
	vertices = pose(gait_phase, wing_phase, moving)
	mesh.surface_update_vertex_region(0, 0, vertices.to_byte_array())

func triangle_indices() -> PackedInt32Array:
	return _data["indices"]
