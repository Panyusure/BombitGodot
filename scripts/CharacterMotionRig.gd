extends RefCounted

## Short-limb gait cages with character-specific, independently clocked parts.
const Profiles = preload("res://scripts/CharacterMotionProfiles.gd")
const FRAME_COUNT := 16
const SECONDARY_COUNT := 32
const IDS := ["xiaonuo", "axiu", "arui", "xiaoyan", "xiaotian"]
static var _cache: Dictionary = {}
var mesh: ArrayMesh
var character_id := ""
var back := false
var vertices := PackedVector2Array()
var _data: Dictionary

static func supports(id: String) -> bool:
	return Profiles.PROFILES.has(id)

static func frame_index(phase: float) -> int:
	return posmod(floori(phase * FRAME_COUNT), FRAME_COUNT)

static func _v(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _ease(lo: float, hi: float, value: float) -> float:
	var t := clampf((value - lo) / (hi - lo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _leg_weight(p: Vector2, leg: Dictionary) -> float:
	var root := _v(leg["root"])
	var d := _v(leg["foot"]) - root
	var t := (p - root).dot(d) / d.length_squared()
	var across := absf((p - root).cross(d.normalized()))
	return (1.0 - _ease(float(leg["radius"]), float(leg["radius"]) + 17.0, across)) * _ease(-0.05, 0.40, t) * (1.0 - _ease(1.40, 2.05, t))

static func _part_weight(p: Vector2, part: Dictionary) -> float:
	var polygon := PackedVector2Array()
	for a in part["polygon"]:
		polygon.append(_v(a))
	if not Geometry2D.is_point_in_polygon(p, polygon):
		return 0.0
	var distance := INF
	for i in polygon.size():
		distance = minf(distance, p.distance_to(Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()])))
	return _ease(0.0, float(part["feather"]), distance)

static func _body_transform(profile: Dictionary, view: Dictionary, phase: float) -> Transform2D:
	var wave := sin(phase * TAU)
	var angle := float(profile["roll"]) * wave
	var root := _v(view["body_root"])
	var shift := Vector2(float(profile["sway"]) * wave, -float(profile["bob"]) * absf(wave))
	return Transform2D(angle, root - root.rotated(angle) + shift)

static func _make_data(id: String, rear: bool) -> Dictionary:
	var profile: Dictionary = Profiles.PROFILES[id]
	var view: Dictionary = profile["back" if rear else "front"]
	var size := _v(view["size"])
	var xs: Array[float] = []
	var ys: Array[float] = []
	for x in range(0, int(size.x), 12):
		xs.append(float(x))
	for y in range(0, 560, 10):
		ys.append(float(y))
	xs.append(size.x)
	ys.append(size.y)
	var rest := PackedVector2Array()
	var uv := PackedVector2Array()
	var weights: Array[PackedFloat32Array] = []
	for part in view["parts"]:
		weights.append(PackedFloat32Array())
	var leg_weights: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var face_values: Array = view["protected_face"]
	var face := Rect2(float(face_values[0]), float(face_values[1]), float(face_values[2]), float(face_values[3]))
	for y in ys:
		for x in xs:
			var p := Vector2(x, y)
			rest.append(p)
			uv.append(p / size)
			var total := 0.0
			for i in 2:
				var w := _leg_weight(p, view["legs"][i])
				leg_weights[i].append(w)
				total += w
			for i in view["parts"].size():
				var w := _part_weight(p, view["parts"][i])
				if face.has_point(p):
					w = 0.0
				if view["parts"][i]["clock"] == "secondary":
					w *= 1.0 - clampf(total / 0.995, 0.0, 1.0)
				weights[i].append(w)
	var indices := PackedInt32Array()
	for row in ys.size() - 1:
		for col in xs.size() - 1:
			var i := row * xs.size() + col
			indices.append_array(PackedInt32Array([i, i + 1, i + xs.size(), i + 1, i + xs.size() + 1, i + xs.size()]))
	var gaits: Array[PackedVector2Array] = []
	var secondary: Array[PackedVector2Array] = []
	for frame in FRAME_COUNT:
		var phase := float(frame) / FRAME_COUNT
		var transform := _body_transform(profile, view, phase)
		var posed := PackedVector2Array()
		for n in rest.size():
			var p := rest[n]
			var point := transform * p
			var total := maxf(1.0, leg_weights[0][n] + leg_weights[1][n])
			for i in 2:
				var leg: Dictionary = view["legs"][i]
				var a := (phase + i * 0.5) * TAU
				var forward := _v(leg["forward"])
				var foot := _v(leg["foot"])
				var step := Vector2(forward.x * cos(a), forward.y * cos(a) - float(leg["lift"]) * maxf(0.0, -sin(a)))
				point += (foot + step - transform * foot) * (leg_weights[i][n] / total)
			for i in view["parts"].size():
				var part: Dictionary = view["parts"][i]
				if part["clock"] != "gait" or weights[i][n] < 0.00001:
					continue
				var d := p - _v(part["root"])
				var angle := float(part["angle"]) * sin(phase * TAU + float(part["lag"]))
				point += (d.rotated(angle) - d).rotated(float(profile["roll"]) * sin(phase * TAU)) * weights[i][n]
			posed.append(point)
		gaits.append(posed)
	for frame in SECONDARY_COUNT:
		var phase := float(frame) / SECONDARY_COUNT
		var offsets := PackedVector2Array()
		for n in rest.size():
			var delta := Vector2.ZERO
			for i in view["parts"].size():
				var part: Dictionary = view["parts"][i]
				if part["clock"] != "secondary" or weights[i][n] < 0.00001:
					continue
				var d := rest[n] - _v(part["root"])
				var angle := float(part["angle"]) * sin(phase * TAU + float(part["lag"]))
				delta += (d.rotated(angle) - d) * weights[i][n]
			offsets.append(delta)
		secondary.append(offsets)
	return {"rest": rest, "uvs": uv, "indices": indices, "gaits": gaits, "secondary": secondary, "size": size, "leg_weights": leg_weights}

func configure(id: String, rear: bool) -> void:
	character_id = id
	back = rear
	var key := id + ("/back" if rear else "/front")
	if not _cache.has(key):
		_cache[key] = _make_data(id, rear)
	_data = _cache[key]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _data["rest"]
	arrays[Mesh.ARRAY_TEX_UV] = _data["uvs"]
	arrays[Mesh.ARRAY_INDEX] = _data["indices"]
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.custom_aabb = AABB(Vector3(-80, -80, -1), Vector3(_data["size"].x + 160, 720, 2))
	vertices = _data["rest"].duplicate()

func pose(gait_phase: float, secondary_phase: float, moving: bool, strength: float = 1.0) -> PackedVector2Array:
	var frame := frame_index(gait_phase)
	var out: PackedVector2Array = (_data["gaits"][frame] if moving else _data["rest"]).duplicate()
	var phase := fposmod(secondary_phase, 1.0) * SECONDARY_COUNT
	var i := floori(phase) % SECONDARY_COUNT
	var fraction := phase - floorf(phase)
	var a: PackedVector2Array = _data["secondary"][i]
	var b: PackedVector2Array = _data["secondary"][(i + 1) % SECONDARY_COUNT]
	var angle := float(Profiles.PROFILES[character_id]["roll"]) * sin(float(frame) / FRAME_COUNT * TAU) if moving else 0.0
	var c := cos(angle)
	var s := sin(angle)
	for n in out.size():
		var d := a[n].lerp(b[n], fraction) * strength
		out[n] += Vector2(d.x * c - d.y * s, d.x * s + d.y * c)
	return out

func update(gait_phase: float, secondary_phase: float, moving: bool, strength: float = 1.0) -> void:
	vertices = pose(gait_phase, secondary_phase, moving, strength)
	mesh.surface_update_vertex_region(0, 0, vertices.to_byte_array())

func triangle_indices() -> PackedInt32Array:
	return _data["indices"]
