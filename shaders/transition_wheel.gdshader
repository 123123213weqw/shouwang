shader_type canvas_item;
// 「镜头钻进水车」的那层水（scripts/uis/transitions/transition_wheel.gd）。一张铺满画面的节点，画什么全在这儿算。
// 每一点算一个"水有多深"的数 W：比 0 小是干的，越大水越深。
//   盖住  cover 从 0 到 1：水从四面涌向 focus（最后被盖住的那一点，平时放水车），越靠边水越深
//   掀开  drain 从 0 到 1：水被抽走，上面抽得快、下面抽得慢——先是 focus 那儿破开一个洞，然后水线一路退到画面底下
//   两个都是 0 的时侯整张透明（刚装上样式、白画两帧预热用的就是这个状态）
// 噪声全靠算，不贴图：贴图铺满画面有缝，水线上会看出一条直的接缝
uniform float cover = 0.0;            // 盖住：0 还没有水，1 盖严
uniform float drain = 0.0;            // 掀开：0 盖严，1 全退净（这时 cover 一直是 1）
uniform vec2 focus = vec2(0.5, 0.5);  // 盖住时最后被盖住的那一点
uniform float aspect = 1.6;           // 画面的宽高比
uniform vec3 tint: source_color = vec3(0.13, 0.52, 0.44);   // 要去的这一关的底色
uniform float seed = 0.0;             // 每一趟换一个数：水线上的起伏不是每回都一样

const float SOFT = 0.08;      // 水线有多宽（画面的高度是 1）
const float AMP = 0.05;       // 水线起伏多大

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 平滑的值噪声，0 到 1（和游戏里的水面 stage_water.gdshader 是同一个）
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

// 一层噪声的"脊"：离一半越近越亮。两层脊叠在一起，暗的那层留下来，就是水面把光聚成的那张亮网（焦散）
float ridge(vec2 p) {
	return 1.0 - abs(vnoise(p) * 2.0 - 1.0);
}

float caustic(vec2 p, float t) {
	vec2 drift = vec2(t * 0.10, -t * 0.07);                       // 网慢慢漂
	vec2 w = p * 5.0 + vec2(seed * 7.0, seed * 3.0);
	// 先把坐标揉一揉：网才弯弯曲曲的，不是一格一格的
	vec2 warp = vec2(vnoise(w * 0.6 - drift * 1.7), vnoise(w * 0.6 + vec2(4.7, 1.3) + drift * 1.3)) - 0.5;
	float a = ridge(w + drift + warp * 0.9);
	float b = ridge(w * 1.37 + vec2(2.9, 5.1) - drift * 1.2 + warp.yx * 0.9);
	return pow(min(a, b), 3.0);
}

void fragment() {
	float t = TIME;
	vec2 P = UV * vec2(aspect, 1.0);          // 等比坐标：画面的高度是 1
	float live = smoothstep(0.0, 0.35, max(cover, drain));     // 还没开始的时侯是 0：这会儿边上不能先湿一条

	// ---- 盖住：这一点离 focus 多"深"。q 按 focus 到那一边的距离归一，那一边上全是 1
	vec2 F = focus * vec2(aspect, 1.0);
	vec2 q = P - F;
	vec2 room = mix(vec2(aspect, 1.0) - F, F, step(q, vec2(0.0)));
	vec2 u = abs(q) / max(room, vec2(0.02));
	float rho = pow(pow(u.x, 5.0) + pow(u.y, 5.0), 0.2);       // 圆角的方：四条边上是 1，角上比 1 大一点
	float phi = 1.0 - min(rho, 1.0);                           // focus 上是 1，四条边和四个角上都是 0
	// 盖严时 focus 上也要留出 SOFT 的两倍：水线上的起伏再大，最后那一帧也是实心的
	float W = cover * (1.0 + 2.0 * SOFT) - phi;

	// ---- 掀开：上面抽得快、下面抽得慢
	W -= drain * (1.34 + 4.46 * (1.0 - UV.y));

	// ---- 水线上的起伏：两层，一层大弯一层小碎
	float edge = (vnoise(P * 3.1 + vec2(seed * 13.0, seed * 7.0) + t * vec2(0.05, 0.02)) - 0.5) * 2.0;
	edge += vnoise(P * 7.3 + vec2(seed * 5.0, t * 0.09)) - 0.5;
	W += edge * AMP * live;

	// ---- 颜色
	float thick = smoothstep(0.0, 0.45, W);                    // 水有多深
	// 水底：暗青，越深越暗，透一点要去的这一关的底色
	vec3 deep = mix(vec3(0.012, 0.056, 0.064), tint * vec3(0.30, 0.45, 0.45), 0.35);
	vec3 col = mix(vec3(0.11, 0.27, 0.27), deep, thick);
	col *= 1.0 + 0.22 * (0.5 - UV.y);                          // 上面离水面近，亮一点
	col += vec3(0.62, 0.86, 0.80) * caustic(P, t) * 0.16 * thick;
	// 水线：一道亮边（玉色）；贴着边的外面压一道暗的，像水鼓起来挡了一线光
	float rim = exp(-(W - 0.012) * (W - 0.012) / (2.0 * 0.018 * 0.018)) * live;
	col = mix(col, vec3(0.010, 0.036, 0.042), 1.0 - smoothstep(-0.03, 0.0, W));
	col = mix(col, vec3(0.80, 0.90, 0.86), rim * 0.85);

	// ---- 画得多实。刚漫过的地方水浅，还看得见底下的棋盘；水线上是实的；快盖严的时侯都压实
	float shallow = mix(0.45, 1.0, smoothstep(0.05, 0.35, W));
	float a = smoothstep(0.0, 0.015, W) * mix(max(shallow, rim), 1.0, smoothstep(0.8, 0.97, cover));
	a = max(a, (1.0 - smoothstep(-0.03, 0.0, W)) * smoothstep(-0.12, -0.03, W) * live * 0.3);

	// 水底很暗、只有几个色阶，渐变会一条一条的：按屏幕像素掺一点抖动把它打散
	col += (hash21(mod(floor(FRAGCOORD.xy), 64.0)) - 0.5) / 255.0;
	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
