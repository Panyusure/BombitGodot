extends RefCounted

## One atlas quad on Board's dynamic layer; no map cache invalidation per frame.
const SHEET = preload("res://assets/maps/animations/carousel-h3-sheet.png")
const FRAME_COUNT := 32
const COLUMNS := 8
const FRAME_SIZE := 256.0
const PERIOD := 2.5
const FPS := FRAME_COUNT / PERIOD

static func applies(theme: String, landmark: Dictionary) -> bool:
	return theme == "park" and String(landmark.get("theme", "")) == "park"

static func frame_at(time: float) -> int:
	return mini(FRAME_COUNT - 1, int(floor(fposmod(time, PERIOD) * FPS)))

static func draw(ci: CanvasItem, theme: String, landmark: Dictionary, time: float) -> void:
	if not applies(theme, landmark):
		return
	var frame := frame_at(time)
	var source := Rect2((frame % COLUMNS) * FRAME_SIZE, int(frame / COLUMNS) * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
	var c := int(landmark.get("c", 7))
	var r := int(landmark.get("r", 6))
	# Same 3x3 foundation and inset as the previous static landmark. Transparent
	# frame margins keep the entire moving silhouette inside the blocked core.
	var target := Rect2((c - 1) * 48 + 3, (r - 1) * 48 + 3, 138, 138)
	ci.draw_texture_rect_region(SHEET, target, source, Color.WHITE, false, true)
