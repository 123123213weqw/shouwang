shader_type canvas_item;
// 石阶沉浮（scripts/uis/transitions/transition_steps.gd）里"潜进水里"的那一层：铺满画面、压在所有界面上。
// depth 是 0 的时侯整张透明（装上样式先白画两帧，着色器要编译，见 transition_style.gd 的 warm_up），是 1 的时侯整张不透明：
// 换棋盘那一帧就藏在这底下。
// 画的就是这条河，只是从水底往外看，分四层：
//   底色   和水面上的底色一模一样（tint，样式照水面的算法算好了给）；越往下越深、越接近墨，贴着水面的那一头透着亮
//   月光   棋盘底下那一汪月光（stage_water.gdshader 的 layout 3）就在头顶上：位置、大小、亮度都照水面上的那一汪（pool、pool_r），
//          所以浮上来、暗幕散开的时侯，露出来的正是同一汪光
//   光柱   几道斜着落下来的软光，整片慢慢摆、亮度慢慢起伏；越往下越弱
//   碎光   稀稀拉拉的几团小光点，顺着潜下去 / 浮上来的方向漂（潜下去的时侯它往上走，浮上来的时侯往下走）
// 厚度也不是处处一样：四边比正中先合拢，顶上（光来的那一头）最后暗、最先清。
// 噪声是现算的值噪声（插值的算法和 stage_water.gdshader 的一样；哈希换成了输入到几十也稳的那一种：
// 抄来的那个输入过了十几，噪声会沿着格子边裂开，出直缝）。
// 没拿 FlowMap 当噪声：那张图是逐个像素的随机色，画出来是雪花点。

uniform float depth = 0.0;                                   // 0 看不见，1 盖严
uniform float flow = 0.0;                                    // -1 正在潜下去，1 正在浮上来：碎光、光柱往哪边走
uniform float shine = 0.0;                                   // 破水那一下顶上漫下来的光（0 到 1）
uniform vec3 tint: source_color = vec3(0.03, 0.08, 0.075);  // 这条河水的底色
uniform vec3 light: source_color = vec3(0.80, 0.90, 0.86);  // 水面透下来的光：玉色
uniform vec2 pool = vec2(0.5, 0.5);                          // 月光那一汪的中心（画面上的位置，0 到 1）
uniform vec2 pool_r = vec2(0.001, 0.001);                    // 和它的半径（横着、竖着）；没有棋盘的时侯很小，等于没有
uniform float aspect = 1.6;                                  // 画面多宽（宽 / 高），按实际画面算，不写死

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 平滑的值噪声，0 到 1。格子坐标按 period 取余：噪声每隔 period 个格子原样重复，漂移的偏移量也取同样的余数，
// 时间再长也不会跳一下，数也不会大到浮点数算不准
float vnoise(vec2 p, vec2 period) {
	vec2 i = mod(floor(p), period);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(mod(i + vec2(1.0, 0.0), period));
	float c = hash21(mod(i + vec2(0.0, 1.0), period));
	float d = hash21(mod(i + vec2(1.0, 1.0), period));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float up = uv.y;                        // 0 在画面顶上，1 在底下
	float t = TIME;

	// 底色：和水面上一模一样；越往下越深；贴着水面的那一头透着亮
	vec3 col = tint * (1.0 - 0.6 * smoothstep(0.0, 1.0, up)) + light * 0.012 * (1.0 - smoothstep(0.0, 0.55, up));

	// 月光那一汪：边不那么圆，像水里的影子（和 stage_water.gdshader 是同一个式子）
	vec2 pq = (uv - pool) / pool_r;
	float pl = 1.0 - smoothstep(0.70, 1.0, length(pq) + (vnoise(uv * 3.0 + vec2(3.7, 1.1), vec2(64.0)) - 0.5) * 0.06);
	col += vec3(0.95, 0.93, 0.85) * pl * 0.045;

	// 光柱：噪声拉成斜着的长条（横着密、竖着疏），两层疏密不同，整片一起慢慢摆，也顺着潜 / 浮的方向走；会呼吸
	float drift = mod(flow * t * 0.09, 8.0);
	vec2 n = vec2(p.x * 3.4 - up * 2.0 + sin(t * 0.8) * 0.35 + sin(t * 2.1) * 0.08, up * 0.45 + drift);
	float a = vnoise(n, vec2(8.0, 8.0));
	float b = vnoise(n * 2.3 + vec2(1.7, 0.9) + vec2(sin(t * 1.1 + 1.7) * 0.3, 0.0), vec2(16.0, 16.0));
	float shaft = smoothstep(0.40, 0.82, a) * (0.55 + 0.45 * smoothstep(0.3, 0.8, b));
	shaft *= (1.0 - smoothstep(0.0, 1.2, up)) * (0.4 + 0.6 * pl);
	shaft *= 0.8 + 0.2 * sin(t * 1.4 + p.x * 2.0);

	// 碎光：小而软的光点，顺着潜下去 / 浮上来的方向漂
	vec2 m = p * vec2(12.0, 7.0) + vec2(0.13, mod(flow * t * 3.0, 32.0));
	float mote = smoothstep(0.74, 0.94, vnoise(m, vec2(32.0, 32.0))) * (1.0 - 0.5 * smoothstep(0.3, 1.0, up));

	col += light * (shaft * 0.16 + mote * 0.09);
	// 破水那一下：顶上漫下来一片光
	col += light * shine * (0.10 * (1.0 - smoothstep(0.0, 0.85, up)) + 0.10 * shaft);

	// 厚度。盖严（depth 是 1）的时侯处处都是 1，一点不漏
	float edge = smoothstep(0.30, 1.05, length((uv - vec2(0.5, 0.52)) * vec2(aspect * 0.72, 1.0)));
	float thick = mix(depth, smoothstep(0.0, 0.8, depth), edge);
	thick *= mix(mix(0.6, 1.15, up), 1.0, smoothstep(0.7, 1.0, depth));
	COLOR = vec4(col, clamp(thick, 0.0, 1.0));
}
