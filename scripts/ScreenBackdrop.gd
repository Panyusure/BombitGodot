extends Control

## Fill expanded widescreen/portrait margins without stretching the playfield.
var clock := 0.0

static func content_origin(view_size: Vector2) -> Vector2:
	return (view_size - Vector2(Cfg.VIEW_W, Cfg.VIEW_H)) * 0.5

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIDraw.PAPER)
	UIDraw.dots(self, 0, 0, size.x, size.y, UIDraw.INK, 0.07, 18)
	var center := size * 0.5
	for side in [-1, 1]:
		var accent := UIDraw.CYAN if side < 0 else UIDraw.PINK
		var pivot := center + Vector2(side * 390, 0)
		for ray in 16:
			var angle: float = ray * TAU / 16 + clock * 0.025 * side
			draw_colored_polygon(PackedVector2Array([pivot,
				pivot + Vector2.from_angle(angle) * 700,
				pivot + Vector2.from_angle(angle + 0.12) * 700]), Color(accent, 0.1))
		for ring in 3:
			var angle: float = clock * side * 0.13 + ring * 0.8
			draw_arc(pivot, 140 + ring * 75, angle, angle + PI * 1.4, 96, Color(accent, 0.4), 2, true)
		for particle in 12:
			var angle: float = particle * TAU / 12 + clock * 0.08 * side
			var point := pivot + Vector2.from_angle(angle) * (180 + 35 * sin(particle))
			UIDraw.star(self, point.x, point.y, 5 + particle % 3, 2.5, accent, 5, angle)
	var origin := content_origin(size)
	UIDraw.panel(self, origin.x - 5, origin.y - 5, Cfg.VIEW_W + 10, Cfg.VIEW_H + 10,
		{"fill": UIDraw.CREAM, "stroke": UIDraw.INK, "lw": 3, "r": 4,
		"shadow": Color(UIDraw.INK, 0.18), "shadowX": 6, "shadowY": 6})
