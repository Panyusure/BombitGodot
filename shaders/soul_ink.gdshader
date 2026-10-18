shader_type canvas_item;
render_mode unshaded, blend_mix;

// 通灵柔光 · 墨晕层
// 这是整个画面里唯一的“暗部”。在奶油纸 / 浅色地砖上，纯 additive 光容易发灰；
// 先在轮廓外铺一层极轻的紫墨晕，柔光就有了墨线的重量，也保住 Motion UI 的硬边性格。
// 形状同样只来自一次 SDF 采样，没有任何 blur。

uniform sampler2D sdf_tex : filter_linear, repeat_disable;
uniform vec4 quad_rect = vec4(-140.0, -240.0, 280.0, 300.0);
uniform vec4 sdf_rect = vec4(-88.0, -142.0, 176.0, 146.0);
uniform float sdf_range = 160.0;
uniform float time = 0.0;
uniform float strength = 0.26;
uniform float seed = 0.0;
uniform vec4 ink_color : source_color = vec4(0.055, 0.035, 0.115, 1.0);

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

float sample_sdf(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 1.0;
	}
	return texture(sdf_tex, uv).a;
}

void fragment() {
	vec2 lpx = quad_rect.xy + UV * quad_rect.zw;
	vec2 cuv = (lpx - sdf_rect.xy) / sdf_rect.zw;
	vec2 drift = vec2(sin(time * 0.31 + seed), cos(time * 0.27 + seed * 1.3)) * 0.0016;

	float packed = sample_sdf(cuv + drift);
	float dn = (packed - 0.5) * 2.0;
	float outside = max(dn, 0.0);

	// 墨晕比光更宽、更薄，紧贴角色时略深，向外很快散掉。
	float a = exp(-outside * outside * 6.0) * strength;
	a *= 0.82 + 0.18 * sin(time * 1.35 + seed);
	a *= 0.88 + 0.24 * vnoise(cuv * 5.0 + vec2(time * 0.04, -time * 0.03));
	// 同主光：范围外平滑归零，避免 normal-blend 四边形显形。
	a *= 1.0 - smoothstep(0.20, 0.72, outside);

	float edge_fade = smoothstep(0.0, 0.14, UV.x) * smoothstep(0.0, 0.14, 1.0 - UV.x)
		* smoothstep(0.0, 0.14, UV.y) * smoothstep(0.0, 0.14, 1.0 - UV.y);
	a *= edge_fade;

	COLOR = vec4(ink_color.rgb, a);
}
