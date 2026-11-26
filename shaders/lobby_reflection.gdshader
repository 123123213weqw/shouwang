shader_type canvas_item;
render_mode blend_add, unshaded;
// 河灯在水里的倒影：贴着灯的底下往下一道，越往下越淡、越散，还会左右轻轻地摆（水在流）。
// 方块的上边贴着灯的船底。只加不减，叠在河面上
uniform vec3 color: source_color = vec3(1.0);
uniform float strength = 0.5;
uniform float width = 0.20;         // 靠近灯的那一段有多宽（方块宽的几分之几），往下越来越散

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

void fragment() {
	float t = mod(TIME, 600.0);
	float y = UV.y;                                   // 0 是灯的底下，1 是最远
	// 左右摆：越远摆得越大，是两种快慢叠在一起的
	float sway = sin(y * 9.0 - t * 1.3) * 0.05 * y + sin(y * 23.0 + t * 2.1) * 0.02 * y;
	float x = abs(UV.x - 0.5 - sway) * 2.0;          // 0 在正中间，1 在方块的边上
	float w = width * (0.45 + y);
	float across = exp(-x * x / max(w, 0.001));
	float along = (1.0 - y) * (1.0 - y) * (1.0 - smoothstep(0.7, 1.0, y));
	// 一段一段的碎光：水纹把倒影切碎了，又在慢慢地换
	float glint = 0.62 + 0.38 * vnoise(vec2(x * 1.5, y * 13.0 - t * 0.7));
	glint *= 0.86 + 0.14 * sin(t * 5.3) * sin(t * 3.1);
	float a = across * along * glint * strength;
	COLOR = vec4(color * a, a);
}
