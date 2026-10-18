shader_type canvas_item;
render_mode unshaded, blend_add;

// 通灵柔光 · 主光层
// 没有任何 blur / 后处理 / 多遍纹理。柔光形状来自 SoulSdf 烘出的有符号距离场：
//   一次 SDF 采样 → signed distance → 解析衰减（rim / halo / ribbon / body field）。
// 颜色、流动、呼吸、彩色边缘都是纯函数。运行时每像素 3 次 SDF 采样（主 + 色散两枚）。

uniform sampler2D sdf_tex : filter_linear, repeat_disable;
uniform vec4 quad_rect = vec4(-120.0, -220.0, 240.0, 260.0);
// 已含 PAD 的 SDF 映射矩形；比立绘大，四周各留 160 原图像素。
uniform vec4 sdf_rect = vec4(-88.0, -142.0, 176.0, 146.0);
uniform vec2 body_center = vec2(0.0, -80.0);
uniform float body_width = 176.0;
uniform float sdf_range = 160.0;
uniform float time = 0.0;
uniform float glow = 1.0;
uniform float awaken = 0.0;
uniform float seed = 0.0;
uniform vec4 col_cyan : source_color = vec4(0.42, 0.94, 1.0, 1.0);
uniform vec4 col_pink : source_color = vec4(1.0, 0.52, 0.86, 1.0);
uniform vec4 col_gold : source_color = vec4(1.0, 0.82, 0.36, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v;
}

// 轮廓外返回 1.0（远），避免 repeat_disable 把边缘像素拉成光带。
float sample_sdf(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 1.0;
	}
	return texture(sdf_tex, uv).a;
}

void fragment() {
	vec2 lpx = quad_rect.xy + UV * quad_rect.zw;
	vec2 cuv = (lpx - sdf_rect.xy) / sdf_rect.zw;

	// 缓慢的灵息漂移：柔光轮廓会轻轻呼吸，而不是一张贴纸。
	vec2 drift = vec2(sin(time * 0.55 + seed), cos(time * 0.43 + seed * 1.7));
	drift *= 0.0022 + awaken * 0.0045;
	float packed = sample_sdf(cuv + drift);

	// 0.5 = 轮廓；正 = 外，负 = 内。单位是原图像素 / sdf_range。
	float dn = (packed - 0.5) * 2.0;
	float outside = max(dn, 0.0);

	// 三层解析柔光：远晕 / 中辉 / 贴轮廓的芯。
	// 用 d² 的高斯型衰减，而不是长尾的 exp(-d)：在 SDF 边缘会自然归零，
	// 不会出现一块亮度均匀、边界可见的“光板”。
	float halo = exp(-outside * outside * 7.0);
	float mid = exp(-outside * outside * 18.0);
	float rim = exp(-abs(dn) * 26.0);

	// 用低频噪声让光有“灵体”的不均匀感，但绝不采样第二张图。
	float grain = fbm(cuv * 7.0 + vec2(time * 0.11, -time * 0.08) + seed * 1.37);
	halo *= 0.70 + 0.58 * grain;
	mid *= 0.80 + 0.34 * grain;
	rim *= 0.70 + 0.52 * grain;

	// 色散边缘：主轮廓左右各取一次 SDF，青 / 粉分离，像灵视里的重影。
	float rim_r = exp(-abs((sample_sdf(cuv + vec2(0.0036, 0.0)) - 0.5) * 2.0) * 25.0);
	float rim_b = exp(-abs((sample_sdf(cuv - vec2(0.0036, 0.0)) - 0.5) * 2.0) * 25.0);

	// 青色 → 粉色随高度过渡，再被噪声扰动。
	float hue = clamp(UV.y * 0.62 + 0.18 * sin(time * 0.33 + grain * 2.2), 0.0, 1.0);
	vec3 c = mix(col_cyan.rgb, col_pink.rgb, hue);
	c = mix(c, col_gold.rgb, max(0.0, grain - 0.70) * 0.85);
	c += vec3(rim_r * 0.20, 0.0, rim_b * 0.26);

	// 胸口附近一团很轻的体积光，给角色一个发光的“根”。
	vec2 bq = (lpx - body_center) / body_width;
	float br = length(bq * vec2(1.0, 1.22));
	float body = exp(-br * br * 4.2) * 0.18;

	// 绕身的灵丝：极坐标 + 噪声，像烟，不像模糊。
	float ang = atan(bq.y, bq.x);
	float rr = length(bq);
	float ribbon = fbm(vec2(ang * 1.8 + time * 0.22, rr * 3.6 - time * 0.35) + seed);
	ribbon = smoothstep(0.56, 0.82, ribbon) * smoothstep(0.96, 0.18, rr) * smoothstep(0.0, 0.10, rr);

	// 稀疏的灵屑，只在轮廓外侧出现。
	float spark = pow(max(0.0, fbm(cuv * 38.0 + vec2(time * 0.6, -time * 0.4) + seed) - 0.76), 2.0) * 18.0;
	spark *= smoothstep(0.0, 0.16, outside) * (1.0 - smoothstep(0.48, 0.95, outside));

	float energy = halo * 0.46 + mid * 0.24 + rim * 0.92 + body + ribbon * 0.34 + spark * 0.10;
	energy *= glow * (0.82 + 0.18 * sin(time * 2.0 + seed * 3.0));

	// 觉醒瞬间：光从轮廓里“溢出来”。
	energy += awaken * (exp(-outside * 1.25) * 0.32 + rim * 0.75);
	c = mix(c, vec3(1.0), awaken * 0.25);

	// 距离场范围之外平滑归零：四边形不能变成一块可见的“光板”。
	// 放在 awaken 之后，觉醒闪白也不会把四边形边界暴露出来。
	// 远场柔光交给 SoulGlow 的径向 bloom；这里只保留贴轮廓的近场。
	energy *= 1.0 - smoothstep(0.22, 0.78, outside);

	// 四边形边缘淡出，避免任何硬切。
	float edge_fade = smoothstep(0.0, 0.12, UV.x) * smoothstep(0.0, 0.12, 1.0 - UV.x)
		* smoothstep(0.0, 0.12, UV.y) * smoothstep(0.0, 0.12, 1.0 - UV.y);
	energy *= edge_fade;

	COLOR = vec4(c * energy, 1.0);
}
