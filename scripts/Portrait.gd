extends Control

## 选角卡片里的立绘：按控件矩形等比缩放绘制，避免 TextureRect 的最小尺寸撑破卡片。

var texture: Texture2D = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	if texture == null:
		return
	var ts := texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	# 原作 drawAssetFit（sprites.js 1167-1175）：先在四周留 4px 内边距求等比缩放，
	# 再在整块矩形里居中贴图 —— 少了这个内边距，立绘会比原作贴边。
	var pad := 4.0
	var fit := minf((size.x - pad * 2.0) / ts.x, (size.y - pad * 2.0) / ts.y)
	var drawn := ts * fit
	var pos := (size - drawn) * 0.5
	draw_texture_rect(texture, Rect2(pos, drawn), false)
