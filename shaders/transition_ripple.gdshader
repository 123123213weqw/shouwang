shader_type canvas_item;
// 换关的过渡「涟漪开合」（scripts/uis/transitions/transition_ripple.gd）画的河面。是照着标题页那条河
//（lobby_river.gdshader）抄过来改的：那一份标题页在用，别动，要改就改这一份。
//   画的是一圈从 center 荡开的涟漪：圈里是夜里的河面（水纹、月影、月光，和标题页同一种画法），圈外透明，
//   露出底下的棋盘；圈边一道亮的水纹，后面跟着两圈淡的拖尾。
//   圈荡到多大了、有多亮，外面每一帧传进来（front、rim、trails）；时间上的事着色器不管。
//   还没开始的时侯（front、rim 都是 0）整张是透明的：装上样式以后它要先白画两帧，把编译的钱花掉（TransitionStyle.add）
uniform float aspect = 1.6;             // 画面的宽高比
uniform float view_h = 720.0;           // 画面有多高（逻辑像素），算线的粗细用
uniform vec2 center = vec2(0.5, 0.5);   // 涟漪的心在画面的什么地方（宽、高各是几分之几）
uniform float squash = 1.0;             // 圈有多扁：1 是正圆；俯着看，地上的圆在画面上是扁的
uniform float front = 0.0;              // 主圈荡到多大了：半径是画面高度的几分之几
uniform float soft = 0.02;              // 圈边的软边有多宽。front 减去它才是盖严的地方
uniform float rim = 0.0;                // 圈边那道亮纹有多亮（0 到 1）
uniform vec4 trails = vec4(0.0);        // 两圈拖尾：(第一圈的半径, 亮度, 第二圈的半径, 亮度)；半径小于 0 就是没有
uniform vec3 water_tint = vec3(0.0);    // 这一关的水色：游戏里那条河在画面上看着的颜色（sRGB，算式在 transition_ripple.gd）
uniform float tint_amount = 0.0;        // 染多重：0 是标题页那条河本来的颜色，1 全是这一关的水色

// 底下这些和标题页那条河是同一套数（lobby_river.gdshader），两边看着才是同一条河
const vec3 water_top = vec3(0.024, 0.035, 0.051);
const vec3 water_bottom = vec3(0.040, 0.075, 0.086);
const vec3 line_color = vec3(0.78, 0.90, 0.86);
const float line_alpha = 0.20;          // 近处水纹最亮的时候有多亮
const float line_px = 1.5;              // 水纹多粗（逻辑像素）
const float flow = 0.28;                // 水流多快：每秒有几条水纹从眼前流过
const vec2 moon = vec2(0.865, 0.165);   // 月亮在画面上的位置（宽、高各是几分之几）
const float moon_radius = 0.044;        // 月亮的半径（画面高度的几分之几）
const vec3 moon_color = vec3(0.95, 0.93, 0.85);
const float moon_alpha = 0.86;
const float moon_path = 0.9;            // 水里那道月光有多亮
const float FAR_LINES = 31.0;           // 画面最上面一行里横着数得过去几条水纹
const float NEAR_LINES = 12.0;          // 最下面一行里几条
const float RIM_SIGMA = 0.0055;         // 亮纹那道细线有多粗（画面高度的几分之几）
const float RIM_GLOW = 0.02;            // 亮纹外头那层淡的光有多宽
const float WOBBLE = 0.05;              // 圈边沿着圈起伏多大的幅度（乘上一个 0 到 1 的噪声再减一半，所以最多偏 WOBBLE 的一半）

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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

// 这个高度上（0 是画面最上面，1 是最下面）横着数过去有几条水纹：远处密，近处稀
float density(float y) {
	return mix(FAR_LINES, NEAR_LINES, clamp(y, 0.0, 1.0));
}

void fragment() {
	float asp = aspect;
	vec2 p = vec2(UV.x * asp, UV.y);            // 等比坐标：画面的高度是 1
	float t = TIME;

	// ---- 主圈：心、到心的距离、从心指向这里的方向
	vec2 c = vec2(center.x * asp, center.y);
	vec2 off = p - c;
	off.y /= squash;                            // 拉圆了量，扁的圈才处处一样宽
	float d = length(off);
	vec2 dir = off / max(d, 0.001);
	// 圈边不是处处一样圆的：沿着圈慢慢起伏一点，像真的水纹。刚生出来的小圈是圆的，荡大了才起伏；
	// 起伏最多往里缩 WOBBLE 的一半，外面算盖严的半径时把这一段留出来了（transition_ripple.gd 的 _apply）
	d += (vnoise(dir * 2.6 + vec2(13.0, 5.0)) - 0.5) * WOBBLE * smoothstep(0.0, 0.3, front);
	float inside = 1.0 - smoothstep(front - soft, front, d);    // 圈里是 1，圈外是 0
	float e = d - (front - soft * 0.5);         // 离亮纹多远（圈外面是正的）。亮纹画在软边的正中：一半压着水，一半压着棋盘

	// ---- 水纹的坐标：亮纹荡过的地方往外挤一下（和标题页的涟漪一个道理），挤的方向换回等比坐标里去
	vec2 nd = vec2(dir.x, dir.y * squash);
	nd /= max(length(nd), 0.001);
	vec2 w = p + nd * (e * 70.0 * exp(-e * e * 1800.0)) * rim * 0.012;
	float dens = density(w.y);
	float spacing = 1.0 / dens;                                     // 相邻两条水纹隔着多高
	float phase = FAR_LINES * w.y - 0.5 * (FAR_LINES - NEAR_LINES) * w.y * w.y - t * flow;
	float id = floor(phase + 0.5);                                  // 第几条
	float lid = mod(id, 97.0);                                      // 拿它当随机数的种子。数越积越大以后浮点数就不准了，所以取余
	float ys = w.y - t * flow / dens;                               // 跟着水一起往下走的坐标
	// 线是弯的：一条一条弯得不一样，弯的幅度沿着线慢慢变
	float amp = spacing * (0.10 + 0.20 * vnoise(vec2(w.x * 0.9 + lid * 3.1, ys * 0.7)));
	float delta = amp * sin(w.x * 4.0 + lid * 1.9 + t * 0.15);
	delta += spacing * 0.05 * sin(w.x * 11.0 - lid * 2.6 + ys * 2.0 + t * 0.22);
	float dl = abs(fract(phase + delta * dens) - 0.5) * spacing * view_h;   // 离最近一条水纹的中线多远（像素）
	float ln = 1.0 - smoothstep(line_px * 0.5 - 0.7, line_px * 0.5 + 0.7, dl);
	// 断成一笔一笔的：每条线断的地方都不一样，一笔里面也有一段亮一段淡
	float stroke = smoothstep(0.40, 0.56, vnoise(vec2(w.x * 6.5 + lid * 13.7, ys * 1.2 + lid * 0.37)));
	stroke *= 0.75 + 0.25 * vnoise(vec2(w.x * 14.0 + lid * 5.0, ys * 3.0));
	float near = smoothstep(-0.05, 1.05, w.y);                      // 0 远，1 近
	float a = ln * stroke * line_alpha * mix(0.30, 1.0, near);

	// ---- 离画面正中多远（标题页那条河拿它压暗四角）
	float rad = length((UV - vec2(0.5, 0.55)) * vec2(asp * 0.75, 1.0));
	float vig = smoothstep(0.55, 1.25, rad);

	// ---- 底色：标题页那条河的渐变；在游戏里则换成这一关的水色，再照游戏里那条河的样子补上棋盘底下那一汪月光
	//（中间亮一点，往四角收下去）。淹上来的水和棋盘底下原来的水才是同一片，不是一块黑压过来
	float v = smoothstep(0.0, 1.0, UV.y);
	vec3 plain = mix(water_top, water_bottom, v);
	vec3 dyed = water_tint + moon_color * 0.030 * (1.0 - smoothstep(0.25, 0.75, rad));
	vec3 col = mix(plain, dyed, tint_amount);
	col *= 1.0 - 0.30 * vig;

	// ---- 月光：月亮底下一道，越往近处越宽；水纹走进去会亮起来，两条水纹之间也浮着一点
	float mx = moon.x * asp;
	float dx = p.x - mx;
	float below = smoothstep(moon.y + 0.035, moon.y + 0.22, p.y);
	float spread = 0.055 + 0.13 * smoothstep(moon.y, 1.0, p.y);         // 越往近处越宽
	float path = exp(-dx * dx / (2.0 * spread * spread)) * below;
	float shimmer = 0.6 + 0.4 * vnoise(vec2(dx * 30.0, (p.y - mod(t, 600.0) * 0.05) * 22.0));
	a += ln * stroke * path * moon_path;
	col += moon_color * path * (0.045 * shimmer);

	// ---- 月影：这是水里的月影，不是天上的月亮（这张图是俯着看河面，没有天空）。
	// 边被水纹横着揉得弯弯曲曲，还有细碎的抖（一秒钟换八次相位；取余，别让它越积越大）
	vec2 mc = vec2(mx, moon.y);
	float beat = mod(floor(t * 8.0), 64.0);
	vec2 mq = p;
	mq.x += sin(p.y * 140.0 + t * 1.1) * 0.0025;
	float md = distance(mq, mc);
	md += (vnoise(vec2(p.y * 46.0 + beat * 0.53, p.x * 9.0 - beat * 0.37)) - 0.5) * 0.004;
	float disc = 1.0 - smoothstep(moon_radius - 0.0012, moon_radius + 0.0012, md);
	float halo = moon_radius * 2.4;
	col += moon_color * exp(-md * md / (2.0 * halo * halo)) * 0.10;
	col = mix(col, moon_color, disc * moon_alpha);

	// ---- 亮纹：细的一道亮的，外头一层淡的光。沿着圈亮度和粗细都有起伏，不是一个处处一样亮的几何圆
	float uneven = 0.7 + 0.3 * vnoise(dir * 1.7 + vec2(3.1, 7.7));
	float thick = 1.0 + 0.6 * (vnoise(dir * 3.3 + vec2(27.1, 9.4)) - 0.5);
	float core = exp(-e * e / (2.0 * RIM_SIGMA * RIM_SIGMA * thick * thick));
	float ring = (core + 0.30 * exp(-e * e / (2.0 * RIM_GLOW * RIM_GLOW))) * uneven * rim;

	// ---- 拖尾：两圈细线，各在自己的半径上；起伏的地方和亮纹错开
	float et = d - trails.x;
	float tr = 0.0;
	if (trails.x > 0.0) {
		tr += exp(-et * et / (2.0 * RIM_SIGMA * RIM_SIGMA)) * (0.7 + 0.3 * vnoise(dir * 1.7 + vec2(11.3, 2.9))) * trails.y;
	}
	et = d - trails.z;
	if (trails.z > 0.0) {
		tr += exp(-et * et / (2.0 * RIM_SIGMA * RIM_SIGMA)) * (0.7 + 0.3 * vnoise(dir * 1.7 + vec2(5.3, 13.9))) * trails.w;
	}

	col += line_color * a;
	// 底色很暗，只有几个色阶，渐变会一条一条的（banding）：掺一点抖动把它打散
	col += (hash21(mod(floor(p * view_h), 64.0)) - 0.5) / 255.0;    // 按像素坐标取，坐标小，哈希才准

	// ---- 合成：河面盖在棋盘上，亮纹和拖尾再压上去。圈外只剩亮纹、拖尾那一点不透明度；圈里是它们把水提亮
	float ring_a = clamp(ring + tr, 0.0, 0.92);
	float alpha = inside + ring_a * (1.0 - inside);
	vec3 rgb = (col * inside * (1.0 - ring_a) + line_color * ring_a) / max(alpha, 0.0001);
	COLOR = vec4(rgb, clamp(alpha, 0.0, 1.0));
}
