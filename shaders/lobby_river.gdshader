shader_type canvas_item;
// 大厅（标题页）的背景：一条夜里的河。不贴图，全靠算。
//   水纹  几道细细的线，弯弯曲曲、断断续续（国画里线描的水就是这样的；和游戏里别的涂鸦一样，是"手画的"），
//         从远处（画面上面：又密又细又淡）往近处（下面：又稀又粗又亮）流
//   月影  右上角一轮（水里的月影，边在水里晃）；底下有一道碎掉的月光，水纹走进月光里会亮起来
//   涟漪  从一点荡开的一圈，水纹被它往外挤一下
//   灯照  指针附近的水纹亮一点，像提着灯照在河面上
// 河上的灯不在这里画，是 scripts/uis/lobby_river.gd 摆的一张张小图
uniform vec3 water_top: source_color = vec3(0.024, 0.035, 0.051);
uniform vec3 water_bottom: source_color = vec3(0.040, 0.075, 0.086);
uniform vec3 line_color: source_color = vec3(0.78, 0.90, 0.86);
uniform float line_alpha = 0.20;          // 近处水纹最亮的时候有多亮
uniform float line_px = 1.5;              // 水纹多粗（屏幕像素）
uniform float flow = 0.28;                // 水流多快：每秒有几条水纹从眼前流过
uniform float view_h = 720.0;             // 画面有多高（屏幕像素），算线的粗细用
uniform float aspect = 1.6;               // 画面的宽高比
uniform vec2 moon = vec2(0.865, 0.165);   // 月亮在画面上的位置（宽、高各是几分之几）
uniform float moon_radius = 0.044;        // 月亮的半径（画面高度的几分之几）
uniform vec3 moon_color: source_color = vec3(0.95, 0.93, 0.85);
uniform float moon_alpha = 0.86;
uniform float moon_path = 0.9;            // 水里那道月光有多亮
uniform vec4 ripple0 = vec4(0.0);         // 六圈涟漪，各是 (位置的 x, y, 已经荡了多久, 力度)；力度是 0 的那一圈不算
uniform vec4 ripple1 = vec4(0.0);
uniform vec4 ripple2 = vec4(0.0);
uniform vec4 ripple3 = vec4(0.0);
uniform vec4 ripple4 = vec4(0.0);
uniform vec4 ripple5 = vec4(0.0);
uniform vec2 pointer = vec2(-1.0, -1.0);  // 指针在画面上的位置；x 小于 0 就是没有指针
uniform float pointer_strength = 0.0;     // 灯照有多亮（指针停下以后慢慢收掉）
uniform float strength = 1.0;             // 整体的亮度

const float FAR_LINES = 31.0;             // 画面最上面一行里横着数得过去几条水纹
const float NEAR_LINES = 12.0;            // 最下面一行里几条

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

// 一圈涟漪。返回这一圈在这里有多亮；荡过的时侯把水纹的坐标 w 往外挤一下
float ripple(vec4 r, vec2 p, float asp, inout vec2 w) {
	if (r.w <= 0.0) {
		return 0.0;
	}
	vec2 c = vec2(r.x * asp, r.y);
	vec2 off = p - c;
	float d = length(off);
	float front = r.z * 0.17;                                   // 每秒荡开 0.17 个画面高度
	float e = d - front;                                        // 离这一圈多远（圈外面是正的）
	float fade = (1.0 - smoothstep(0.25, 1.6, r.z)) * smoothstep(0.0, 0.06, r.z) * r.w;    // 头 0.25 秒是足亮的，之后淡下去
	float squeeze = e * 70.0 * exp(-e * e * 1800.0);            // 圈的前面往外推，后面跟着回来
	w += off / max(d, 0.001) * squeeze * fade * 0.012;
	float ring = exp(-e * e / (2.0 * 0.0055 * 0.0055));         // 一圈细细的亮线
	ring += 0.35 * exp(-(e + 0.03) * (e + 0.03) / (2.0 * 0.006 * 0.006));   // 后面跟着一圈更淡的
	// 沿着圈亮度有起伏，不是一个处处一样亮的几何圆（每一圈起伏的地方不一样：拿力度当种子）
	float uneven = 0.7 + 0.3 * vnoise(off / max(d, 0.001) * 1.7 + vec2(r.w * 5.0, r.w * 3.0));
	return ring * fade * uneven;
}

void fragment() {
	float asp = aspect;
	vec2 p = vec2(UV.x * asp, UV.y);            // 等比坐标：画面的高度是 1
	float t = TIME;

	// ---- 涟漪
	vec2 w = p;
	float ring = ripple(ripple0, p, asp, w);
	ring += ripple(ripple1, p, asp, w);
	ring += ripple(ripple2, p, asp, w);
	ring += ripple(ripple3, p, asp, w);
	ring += ripple(ripple4, p, asp, w);
	ring += ripple(ripple5, p, asp, w);

	// ---- 水纹
	float dens = density(w.y);
	float spacing = 1.0 / dens;                                     // 相邻两条水纹隔着多高
	float phase = FAR_LINES * w.y - 0.5 * (FAR_LINES - NEAR_LINES) * w.y * w.y - t * flow;
	float id = floor(phase + 0.5);                                  // 第几条
	float lid = mod(id, 97.0);                                      // 拿它当随机数的种子。数越积越大以后浮点数就不准了，所以取余（97 条一轮，看不出重复）
	float ys = w.y - t * flow / dens;                               // 跟着水一起往下走的坐标
	// 线是弯的：一条一条弯得不一样，弯的幅度沿着线慢慢变
	float amp = spacing * (0.10 + 0.20 * vnoise(vec2(w.x * 0.9 + lid * 3.1, ys * 0.7)));
	float delta = amp * sin(w.x * 4.0 + lid * 1.9 + t * 0.15);
	delta += spacing * 0.05 * sin(w.x * 11.0 - lid * 2.6 + ys * 2.0 + t * 0.22);
	float d = abs(fract(phase + delta * dens) - 0.5) * spacing * view_h;     // 离最近一条水纹的中线多远（像素）
	float ln = 1.0 - smoothstep(line_px * 0.5 - 0.7, line_px * 0.5 + 0.7, d);
	// 断成一笔一笔的：每条线断的地方都不一样，一笔里面也有一段亮一段淡
	float stroke = smoothstep(0.40, 0.56, vnoise(vec2(w.x * 6.5 + lid * 13.7, ys * 1.2 + lid * 0.37)));
	stroke *= 0.75 + 0.25 * vnoise(vec2(w.x * 14.0 + lid * 5.0, ys * 3.0));
	float near = smoothstep(-0.05, 1.05, w.y);                      // 0 远，1 近
	float a = ln * stroke * line_alpha * mix(0.30, 1.0, near);

	vec3 col = mix(water_top, water_bottom, smoothstep(0.0, 1.0, UV.y));

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

	// ---- 灯照：指针附近的水纹亮一点
	if (pointer.x >= 0.0 && pointer_strength > 0.0) {
		float pd = distance(p, vec2(pointer.x * asp, pointer.y));
		float lamp = exp(-pd * pd / (2.0 * 0.13 * 0.13));
		a += ln * stroke * lamp * 0.9 * pointer_strength;
		col += moon_color * lamp * 0.030 * pointer_strength;
	}

	// ---- 涟漪的圈
	a += ring * 0.55;
	col += line_color * ring * 0.04;

	// ---- 四角压暗一点，把眼睛收到中间（标志和按钮都在那儿）
	float vig = smoothstep(0.55, 1.25, length((UV - vec2(0.5, 0.55)) * vec2(asp * 0.75, 1.0)));
	col *= 1.0 - 0.30 * vig;

	col += line_color * a;
	// 底色很暗，只有几个色阶，渐变会一条一条的（banding）：掺一点抖动把它打散
	col += (hash21(mod(floor(p * view_h), 64.0)) - 0.5) / 255.0;    // 按像素坐标取，坐标小，哈希才准
	COLOR = vec4(col * strength, 1.0);
}
