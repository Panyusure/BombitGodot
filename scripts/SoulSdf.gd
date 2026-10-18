class_name SoulSdf
extends RefCounted

## 通灵柔光的几何底座：把角色立绘的 alpha 轮廓一次性烘成有符号距离场（SDF）。
##
## 为什么不是 blur：
##   - 没有高斯核、没有多遍降采样、没有后处理；
##   - 只在「角色第一次通灵」时对 alpha 做一次 chamfer 距离变换；
##   - 之后的柔光全部是解析衰减：shader 每层一次 SDF 采样，
##     rim / halo / ink shadow / echo 都由距离值直接算出。
##
## SDF 以 1/4 分辨率生成（168×140 左右）。距离值以角色原图像素为单位，
## 编码进 alpha：0.5 = 轮廓，>0.5 = 轮廓外，<0.5 = 轮廓内。
## shader 里 signed_px = (a - 0.5) * 2 * RANGE。
##
## 缓存以纹理 instance_id 为键；同一张立绘只烘一次。

const DOWNSAMPLE := 4
const RANGE_SRC := 160.0      # 编码范围：轮廓内外各 160 原图像素
const PAD_SRC := 160.0        # 四周留出一整段距离场，柔光才不会在贴图边缘被切成长方形
const ALPHA_CUTOFF := 0.42

static var _cache: Dictionary = {}

## 返回 { tex: ImageTexture, w: int, h: int, src_w: int, src_h: int, bake_ms: float }
static func for_texture(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {}
	var key := tex.get_instance_id()
	if _cache.has(key):
		return _cache[key]

	# 生产路径：优先读取离线烘好的 SDF（tools 生成 / 随包分发）。
	# 这样 Web、低端机、首帧都不会因为 60ms 的距离变换卡一下；
	# 找不到资产时才回退到运行时 chamfer。
	var res_path := String(tex.resource_path)
	if res_path.ends_with(".png"):
		var base := res_path.get_basename()
		var sdf_path := base + ".sdf.png"
		if ResourceLoader.exists(sdf_path):
			var baked: Texture2D = load(sdf_path)
			if baked != null:
				var baked_info := {
					"tex": baked,
					"w": baked.get_width(), "h": baked.get_height(),
					"src_w": tex.get_width(), "src_h": tex.get_height(),
					"pad_src": PAD_SRC, "bake_ms": 0.0, "baked": true,
				}
				var preview_path := base + ".sdf-preview.png"
				if ResourceLoader.exists(preview_path):
					baked_info["preview"] = load(preview_path)
				_cache[key] = baked_info
				return baked_info

	var t0 := Time.get_ticks_usec()
	var img := tex.get_image()
	if img == null:
		return {}
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var src_w := img.get_width()
	var src_h := img.get_height()
	var cw := maxi(2, int(round(float(src_w) / float(DOWNSAMPLE))))
	var ch := maxi(2, int(round(float(src_h) / float(DOWNSAMPLE))))
	var pad_texels := maxi(1, int(round(PAD_SRC / float(DOWNSAMPLE))))
	var w := cw + pad_texels * 2
	var h := ch + pad_texels * 2
	img.resize(cw, ch, Image.INTERPOLATE_BILINEAR)

	var inside := PackedByteArray()
	inside.resize(w * h)
	for y in ch:
		for x in cw:
			inside[(y + pad_texels) * w + (x + pad_texels)] = 1 if img.get_pixel(x, y).a > ALPHA_CUTOFF else 0

	# 到最近「实心」的距离（实心内部为 0，外部向外增大）
	var d_inside := _chamfer(inside, w, h, 1)
	# 到最近「空气」的距离（外部为 0，内部向内增大）
	var d_outside := _chamfer(inside, w, h, 0)

	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var preview := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var signed_texels := d_inside[i] if inside[i] == 0 else -d_outside[i]
			var signed_src := signed_texels * float(DOWNSAMPLE)
			var v := clampf(0.5 + signed_src / (2.0 * RANGE_SRC), 0.0, 1.0)
			# alpha 载数据；rgb 同步一份，方便直接查看
			out.set_pixel(x, y, Color(v, v, v, v))
			# 海报里的小缩略图：只留 0.5 等值线附近的亮带，让轮廓一眼可读
			var contour := pow(maxf(0.0, 1.0 - absf(v - 0.5) * 2.0), 2.0)
			preview.set_pixel(x, y, Color(contour, contour, contour, 1.0))

	var it := ImageTexture.create_from_image(out)
	var info := {
		"tex": it, "preview": ImageTexture.create_from_image(preview),
		"w": w, "h": h, "src_w": src_w, "src_h": src_h,
		"pad_src": float(pad_texels * DOWNSAMPLE),
		"bake_ms": (Time.get_ticks_usec() - t0) / 1000.0,
	}
	_cache[key] = info
	return info

static func cached_for(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {}
	return _cache.get(tex.get_instance_id(), {})

static func clear_cache() -> void:
	_cache.clear()

## 提前把会用到 SDF 的立绘烘好，避免第一次通灵 / 第一次转身时卡一帧。
static func prewarm(paths: Array) -> void:
	for p in paths:
		var path := String(p)
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex != null:
			for_texture(tex)

## 两遍 8 邻域 chamfer 距离变换。target=1 求「到实心」；target=0 求「到空气」。
static func _chamfer(mask: PackedByteArray, w: int, h: int, target: int) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for i in w * h:
		dist[i] = 0.0 if mask[i] == target else 1.0e9
	var diag := 1.41421356

	for y in h:
		var row := y * w
		for x in w:
			var v := dist[row + x]
			if v <= 0.0:
				continue
			if x > 0:
				v = minf(v, dist[row + x - 1] + 1.0)
			if y > 0:
				var up := row - w
				v = minf(v, dist[up + x] + 1.0)
				if x > 0:
					v = minf(v, dist[up + x - 1] + diag)
				if x < w - 1:
					v = minf(v, dist[up + x + 1] + diag)
			dist[row + x] = v

	for y in range(h - 1, -1, -1):
		var row := y * w
		for x in range(w - 1, -1, -1):
			var v := dist[row + x]
			if v <= 0.0:
				continue
			if x < w - 1:
				v = minf(v, dist[row + x + 1] + 1.0)
			if y < h - 1:
				var down := row + w
				v = minf(v, dist[down + x] + 1.0)
				if x > 0:
					v = minf(v, dist[down + x - 1] + diag)
				if x < w - 1:
					v = minf(v, dist[down + x + 1] + diag)
			dist[row + x] = v

	return dist
