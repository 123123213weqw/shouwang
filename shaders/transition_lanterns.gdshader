shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// 换关的过渡「河灯涌来」的光海（scripts/uis/transitions/transition_lanterns.gd）：一整条漂满河灯的河，从远处的消失点
// 涌到近处。全是算出来的，不贴图：
//   夜色   河的底。跟着要去的这一关的底色走（night_from 是离开的那一关，night_to 是要去的，night_mix 在两者之间走）
//   光点   河面上的灯：远处的小而密、暗一些，近处的大而疏、亮。画在 (斜率, u) 这个平面的方格子上，见 dots
//   烛光   近处那几十盏真的灯（小图是样式摆在上面这一层）的光晕，位置每帧从样式传进来（lamp_*）
// 这一层同时就是"盖严"的那一层：盖住做完的那一刻整张不透明，底下的棋盘一点看不见。
// 用预乘的混合方式：光的分量不乘透明度，前锋还没盖到的地方、掀开让出来的洞里照样有光（只加不减）。
// 这个着色器自己算最终的颜色，节点的 modulate 管不到它，所有的量都从参数进。
// 还没开始的时侯（front 在消失点后面、cover 是 0、洞关着）整张透明，连光也没有

uniform float aspect = 1.6;         // 画面的宽高比
uniform float view_h = 720.0;       // 画面有多高（逻辑像素）：算一个光点够不够一个像素
uniform vec3 candle: source_color = vec3(1.0, 0.84, 0.55);   // 烛火色
uniform vec3 ember: source_color = vec3(1.0, 0.50, 0.18);    // 烛火外圈偏红的那一圈
uniform vec3 night_from: source_color = vec3(0.02, 0.03, 0.035);   // 夜色：离开的那一关
uniform vec3 night_to: source_color = vec3(0.02, 0.03, 0.035);     // 夜色：要去的那一关
uniform float night_mix = 0.0;
uniform float flow = 0.0;           // 河灯已经流了多远（u 方向上），样式每帧给。TIME 在过渡中途没法归零，所以不用它
uniform float front = -0.4;         // 盖住：灯河的前锋离消失点多远（等比坐标，画面高是 1）。负得多 = 还没来
uniform float front_soft = 0.07;    // 前锋的柔边有多宽
uniform float cover = 0.0;          // 整张有多实：盖严那一瞬是 1（保险：不管前锋算到哪儿，四角和正中都不漏）
uniform vec2 hole_at = vec2(0.8, 0.55);   // 掀开：从哪一点先露（等比坐标）
uniform float hole_far = 1.0;       // 离这一点最远的那一角有多远：洞的半径拿它当 1
uniform float hole_r = 0.0;         // 洞现在多大（0 是关着的）
uniform float hole_soft = 0.2;      // 洞边有多柔
uniform int lamp_n = 0;             // 近处真的灯有几盏
uniform vec2 lamp_pos[36];          // 它们在画面上的位置（等比坐标：画面的高是 1）
uniform vec4 lamp_lit[36];          // x 光晕的半径（等比），y 亮度

const float VP_X = 0.5;             // 消失点横着在画面的正中
const float VP_Y = -0.08;           // 消失点竖着在画面上方外面这么多（画面高的几分之几）：越靠上，灯从远处涌到眼前越急

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec4 hash42(vec2 p) {
	vec4 h = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	h += dot(h, h.wzxy + 33.33);
	return fract((h.xxyz + h.yzzw) * h.zywx);
}

// 平滑的值噪声，0 到 1
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

// 一层光点。河面不是真的三维投影，是个"缩放场"：画面上离消失点越远，格子越大，是 dy 倍（dy 是这一点离消失点多高）。
// 所以把格子摆在 (斜率, u = log(dy)) 这个平面上，投到画面上近处的大而疏、远处的小而密，是同一件事。
// 灯顺流而下 = flow 涨：u 匀速地涨，画面上的位置是指数式地往外跑，远处的看着慢慢挪、近处的越涌越快
vec3 dots(vec2 p, vec2 vp, float cell, vec2 seed) {
	float dy = p.y - vp.y;
	float u = log(dy);
	float slope = (p.x - vp.x) / dy;
	vec2 g = vec2(slope / cell, (u - flow) / cell) + seed;
	vec2 id = floor(g);
	vec2 f = fract(g);
	vec4 h = hash42(id);
	float depth = smoothstep(0.08, 0.9, dy);                 // 0 远，1 近
	float density = mix(0.85, 0.30, depth);                  // 近处疏
	if (h.w > density) {
		return vec3(0.0);
	}
	vec2 centre = vec2(0.5) + (h.xy - 0.5) * 0.56;
	float d = length(f - centre) * dy * cell;                // 离这盏灯多远（等比坐标）
	float r = dy * cell * (0.22 + 0.10 * h.z);               // 灯的半径
	float aa = 1.2 / view_h;                                 // 一个像素（等比）：比它还小的光点摊开成一个像素，别一闪一闪
	float q = d / sqrt(r * r + aa * aa);
	float spot = exp(-q * q * 2.8);
	float energy = r * r / (r * r + aa * aa);                // 摊开以后总的光不变
	float flick = 0.78 + 0.22 * sin(TIME * (5.0 + 4.0 * h.z) + h.x * 6.2831);   // 火苗晃：各盏快慢不一
	float bright = mix(0.55, 1.0, depth) * flick * (0.45 + 0.55 * h.y);
	return mix(ember, candle, spot) * (spot * bright * energy);
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);            // 等比坐标：画面的高是 1
	vec2 vp = vec2(VP_X * aspect, VP_Y);            // 消失点（远处）
	vec2 off = p - vp;
	float r = length(off);
	vec2 dir = off / max(r, 0.0001);

	// ---- 盖住：灯河的前锋。以内（更远）已经淹没，以外还看得见棋盘。前锋不是一个正圆：沿着它有起伏，像水漫过来
	float fs = front_soft;
	float grow = smoothstep(0.0, 0.5, r);          // 刚从消失点冒出来的时侯还是个小圆点，不揉它
	float wob = (vnoise(dir * 2.3 + vec2(4.1, 7.7)) - 0.5) * 0.18 * grow
		+ (vnoise(dir * 5.1 + vec2(1.3, 9.2)) - 0.5) * 0.07 * grow;
	float fr = r + wob;
	float a = 1.0 - smoothstep(front - fs, front + fs, fr);
	a = max(a, cover);
	// 光比夜色先到：前锋外面先看见一层的灯，然后才被淹
	float lit = 1.0 - smoothstep(front - fs * 0.5, front + fs * 1.8, fr);
	lit = max(lit, cover);

	// ---- 掀开：从 hole_at 让开一个洞，边也不是圆的
	vec2 hq = p - hole_at;
	float hd0 = length(hq) / hole_far;
	vec2 hdir = hq / max(length(hq), 0.0001);
	float hole_on = smoothstep(0.0, 0.04, hole_r);
	float hwob = (vnoise(hdir * 2.1 + vec2(11.0, 3.0)) - 0.5) * 0.13
		+ (vnoise(hdir * 4.7 + vec2(2.0, 5.0)) - 0.5) * 0.05;
	float hd = hd0 + hwob * hole_on * smoothstep(0.0, 0.2, hd0);
	float open = smoothstep(hole_r - hole_soft, hole_r + hole_soft, hd);
	open = mix(1.0, open, hole_on);                // 洞关着的时侯什么都不让
	a *= open;

	// ---- 夜色：关卡的底色压进墨色里。四角再压暗一点，把眼睛收到中间
	vec3 night = mix(night_from, night_to, night_mix);
	float vig = smoothstep(0.55, 1.25, length((p - vec2(0.5 * aspect, 0.55)) * vec2(0.75, 1.0)));
	night *= 1.0 - 0.30 * vig;

	// ---- 光：远处的光点（两层：细的一层，粗的一层更亮）、近处真的灯的烛光（和 opening_glow 是一条衰减曲线）
	vec3 glow = dots(p, vp, 0.13, vec2(0.0, 0.0));
	glow += dots(p, vp, 0.27, vec2(3.7, 1.3)) * 1.5;
	for (int i = 0; i < lamp_n; i++) {
		float d = distance(p, lamp_pos[i]) / lamp_lit[i].x;
		if (d < 1.0) {
			float q = 1.0 - d;
			glow += mix(ember, candle, q) * (q * q * pow(q, 0.2) * lamp_lit[i].y);
		}
	}
	glow *= lit * open;
	// 前锋那一圈：最前面一排灯，更亮
	float edge = exp(-pow((fr - front) / (fs * 0.9 + 0.02), 2.0)) * smoothstep(-fs, 0.0, front);
	glow += candle * edge * 0.30 * open;
	// 洞边：让开的时侯灯被挤到边上，那一圈更亮
	float rim = exp(-pow((hd - hole_r) / (hole_soft + 0.03), 2.0)) * hole_on;
	glow *= 1.0 + 1.6 * rim;
	glow += candle * rim * 0.25 * lit;

	// ---- 合起来。光叠得多的地方偏白黄（烛火的芯）。夜色很暗，渐变会一条一条的：按像素掺一点抖动把它打散
	vec3 col = night * a;
	col += glow;
	float sum = dot(glow, vec3(0.33));
	col += vec3(1.0, 0.96, 0.88) * sum * sum * 0.30;
	// 刚露出来的地方留一点烛光的余晖，往洞里很快淡掉：这一关像是从灯底下送出来的
	float after = exp(-max(hole_r - hd, 0.0) * 4.0) * hole_on * (1.0 - open);
	col += candle * after * 0.06;
	col += (hash21(mod(floor(p * view_h), 64.0)) - 0.5) / 255.0 * a;
	COLOR = vec4(col, a);
}
