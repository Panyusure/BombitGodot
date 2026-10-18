extends SceneTree

## 径向渐变纹理生成耗时基准（无头运行，不干扰编辑器里的游戏）。
##
## 关注两点：
##   1. 冷启动（首次生成某个形状）要多久；
##   2. 换位置之后是否还重建 —— 这才是卡顿的根源。

func _initialize() -> void:
	var stops := [[0.0, Color(1, 1, 1, 0.6)], [1.0, Color(0, 0, 0, 0)]]
	var specs := [[117.0, "soul_pulse r=2"], [69.0, "soul_pulse r=1"], [21.0, "道具泡泡"]]

	print("--- 1) 冷启动：每个形状首次生成 ---")
	var cold := {}
	for spec in specs:
		var r1: float = spec[0]
		var t0 := Time.get_ticks_usec()
		CanvasArt._radial_texture(Vector2(0, 0), 2.0, Vector2.ZERO, r1, stops)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		cold[spec[1]] = ms
		print("  %-16s r1=%-6.0f  %7.1f ms" % [spec[1], r1, ms])

	print("--- 2) 换位置 100 次：c0 与 c1 同步平移（游戏里的真实用法）---")
	for spec in specs:
		var r1: float = spec[0]
		var t0 := Time.get_ticks_usec()
		for k in 100:
			var p := Vector2(1000.0 + 37.0 * k, 1000.0 + 11.0 * k)
			CanvasArt._radial_texture(p, 2.0, p, r1, stops)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("  %-16s 100 次不同位置共 %7.2f ms  (平均 %6.3f ms/次)" % [spec[1], ms, ms / 100.0])

	print("--- 2b) 带偏心内圆、随位置平移（道具泡泡的真实用法）---")
	var t0b := Time.get_ticks_usec()
	for k in 100:
		var c := Vector2(200.0 + 48.0 * k, 300.0 + 7.0 * (k % 13))
		CanvasArt._radial_texture(c + Vector2(-8.0, -9.0), 1.0, c, 21.0, stops)
	var msb := (Time.get_ticks_usec() - t0b) / 1000.0
	print("  道具泡泡 100 次不同位置共 %7.2f ms  (平均 %6.3f ms/次)" % [msb, msb / 100.0])

	print("--- 3) 道具泡泡：中心逐帧抖动 300 帧 ---")
	var t0 := Time.get_ticks_usec()
	for f in 300:
		var bob := sin(float(f) * 0.05) * 3.0
		CanvasArt._radial_texture(Vector2(-8.0, -9.0 + bob), 1.0,
			Vector2(200.0, 300.0 + bob), 21.0, stops)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  300 帧共 %7.2f ms  (平均 %6.3f ms/帧)" % [ms, ms / 300.0])

	print("--- 4) 缓存条目数（应保持为常数）---")
	print("  _rad_cache.size() = %d" % CanvasArt._rad_cache.size())
	quit(0)
