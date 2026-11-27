shader_type canvas_item;
// 石阶沉浮（scripts/uis/transitions/transition_steps.gd）里"潜进水里"的那一层暗幕：铺满画面、压在所有界面上。
// depth 是 0 的时侯整张透明（装上样式先白画两帧，着色器要编译，见 transition_style.gd 的 warm_up），是 1 的时侯整张不透明：
// 换棋盘那一帧就藏在这底下。
// 画的是在水底往外看：上头透着一点光，底下是墨；几道斜着落下来的光柱慢慢摆；碎光顺着潜下去 / 浮上来的方向漂。
// 颜色跟要去的这一关的底色走（tint，往墨色里压）。噪声拿 FlowMap 那张图当。
uniform float depth = 0.0;                                   // 0 看不见，1 盖严
uniform float flow = 0.0;                                    // -1 正在潜下去，1 正在浮上来：碎光往哪边漂、哪一头先清 / 先暗
uniform float shine = 0.0;                                   // 破水那一下顶上漫下来的光（0 到 1）
uniform vec3 tint: source_color = vec3(0.05, 0.14, 0.13);   // 水底的墨色（样式按这一关的底色给）
uniform vec3 light: source_color = vec3(0.80, 0.90, 0.86);  // 水面透下来的光：玉色
uniform sampler2D noise_tex: repeat_enable, filter_linear_mipmap;
uniform float aspect = 1.6;                                  // 画面多宽（宽 / 高），按实际画面算，不写死

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	float up = uv.y;                        // 0 在画面顶上，1 在底下
	// 斜着落下来的光柱：噪声拉成长条，整片慢慢摆
	vec2 q = vec2(p.x * 1.1 - up * 0.45, up * 0.07);
	float sway = sin(t * 0.21) * 0.05;
	float a = texture(noise_tex, q + vec2(sway, -flow * t * 0.02)).r;
	float b = texture(noise_tex, q * 1.9 + vec2(0.37, 0.11) + vec2(sin(t * 0.33 + 1.7) * 0.05, -flow * t * 0.03)).g;
	float shaft = smoothstep(0.40, 0.95, a) * (0.55 + 0.45 * smoothstep(0.25, 0.85, b));
	shaft *= 1.0 - smoothstep(0.0, 1.1, up);          // 光从上面来，越往下越弱
	// 碎光：顺着潜下去 / 浮上来的方向漂（潜下去的时侯它往上走，浮上来的时侯往下走）
	float m = texture(noise_tex, p * vec2(3.0, 1.6) + vec2(0.13, -flow * t * 0.5)).b;
	float mote = smoothstep(0.70, 0.98, m);
	// 底色：上头透着光，底下是墨
	vec3 col = mix(tint + vec3(0.030, 0.062, 0.056), tint * 0.35, smoothstep(0.0, 1.0, up));
	col += light * (shaft * 0.13 + mote * 0.08);
	col += light * shine * (0.16 * (1.0 - smoothstep(0.0, 0.85, up)) + 0.10 * shaft);
	// 厚度：四边比正中先合拢；顶上（光来的那一头）最后暗、最先清。盖严（depth 是 1）的时侯处处都是 1，一点不漏
	float edge = smoothstep(0.30, 1.05, length((uv - vec2(0.5, 0.52)) * vec2(aspect * 0.72, 1.0)));
	float thick = mix(depth, smoothstep(0.0, 0.8, depth), edge);
	thick *= mix(mix(0.6, 1.15, up), 1.0, smoothstep(0.7, 1.0, depth));
	COLOR = vec4(col, clamp(thick, 0.0, 1.0));
}
