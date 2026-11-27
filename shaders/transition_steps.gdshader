shader_type canvas_item;
// 石阶沉浮（scripts/uis/transitions/transition_steps.gd）里"潜进水里"的那一层暗幕：铺满画面、压在所有界面上。
// depth 是 0 的时侯整张透明（装上样式先白画两帧，着色器要编译，见 transition_style.gd 的 warm_up），是 1 的时侯整张不透明：
// 换棋盘那一帧就藏在这底下。颜色跟要去的这一关的底色走（tint，往墨色里压）；水里的光柱、碎光拿 FlowMap 当噪声算
uniform float depth = 0.0;                                  // 0 看不见，1 盖严
uniform float flow = 0.0;                                   // 正在潜下去（-1）还是浮上来（1）：碎光往哪边漂
uniform vec3 tint: source_color = vec3(0.05, 0.14, 0.13);  // 水底的墨色（样式按这一关的底色给）
uniform vec3 light: source_color = vec3(0.80, 0.90, 0.86); // 水面透下来的光：玉色
uniform sampler2D noise_tex: repeat_enable, filter_linear_mipmap;   // 着色器语言里过滤方式只能写一个
uniform float aspect = 1.6;                                 // 画面多宽（宽 / 高），按实际画面算，不写死

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	vec2 drift = vec2(0.0, -flow * TIME * 0.35);
	// 斜着的光柱：噪声拉成长条
	float shaft = texture(noise_tex, vec2(p.x * 0.9 - p.y * 0.35, p.y * 0.12) + drift * 0.25).r;
	shaft = smoothstep(0.42, 0.90, shaft);
	// 往上漂的碎光
	float mote = texture(noise_tex, p * vec2(2.2, 1.4) + drift).g;
	mote = smoothstep(0.62, 0.95, mote);
	vec3 col = tint + light * (shaft * 0.10 + mote * 0.07);
	COLOR = vec4(col, depth);
}
