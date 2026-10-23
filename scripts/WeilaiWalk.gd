extends RefCounted

const FRAME_COUNT := 16
const FRAME_SIZE := Vector2(256, 320)
const CONTENT_HEIGHT := 296.0
const PIVOT := Vector2(0.5, 0.9625)
const ROOT := "res://assets/characters/animations/weilai/"
static var _frames: Dictionary = {}

static func frame_index(phase: float) -> int:
	return posmod(floori(phase * FRAME_COUNT), FRAME_COUNT)

static func frame(back: bool, phase: float) -> Texture2D:
	var key := "back" if back else "front"
	if not _frames.has(key):
		var atlas: Texture2D = load(ROOT + "walk_" + key + ".png")
		var textures: Array[Texture2D] = []
		for i in FRAME_COUNT:
			var texture := AtlasTexture.new()
			texture.atlas = atlas
			texture.region = Rect2(Vector2(i % 4, floori(float(i) / 4)) * FRAME_SIZE, FRAME_SIZE)
			texture.filter_clip = true
			textures.append(texture)
		_frames[key] = textures
	return _frames[key][frame_index(phase)]
