shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_opaque;
// 游戏里的水面：和大厅那条河是同一种画法（见 lobby_river.gdshader），只是这里是真三维的水面——水纹画在世界上，透视自己对。
// 三个布局共用这一个着色器，layout 说的是光从哪来、装饰放在哪（scripts/stage_backdrop.gd）：
//   1 长河   整个画面都是水；月影在左边一侧的河面上，月光贴着那一侧往近处流
//   2 远岸   水到远处就到头了（far_z 以外不画），露出后面的天空和远山（stage_sky.gdshader）；水纹往远处越来越淡，让进雾里
//   3 月下   棋盘底下一汪月光（很大、很淡的一轮月影压在棋盘下面）；水纹在那一汪里让开，边上才亮（平时用的是这个）
// 和玩家的互动：角色落到哪个格子，哪个格子就荡开一圈涟漪。
// 前三个颜色的名字是原来那个着色器留下来的：colors.gd 每一帧按章节、连击的颜色改它们，名字不能换
uniform vec3 water_color: source_color = vec3(0.035, 0.137, 0.110);          // 河的底色
uniform vec3 light_foam_color: source_color = vec3(0.054, 0.21, 0.17);       // 水纹的颜色
uniform vec3 dark_foam_color: source_color = vec3(0.015, 0.024, 0.035);      // 压暗处的颜色
uniform int layout = 1;
uniform float night = 0.40;                  // 底色往墨色里压多少（0 是原来的颜色，1 是纯墨色）
uniform float line_alpha = 0.21;             // 水纹最亮的时候有多亮
uniform float line_px = 1.3;                 // 水纹多粗（屏幕像素，远近一样粗）
uniform float flow = 0.30;                   // 水流多快：每秒流过几条水纹
uniform float lines_per_unit = 0.62;          // 一个单位宽的河面上横着数得过去几条水纹（一格是 1.3 个单位）
uniform vec2 moon_xz = vec2(-7.4, 0.6);      // 长河：月影在河面上的位置（世界的 x、z）
uniform float moon_radius = 1.05;
uniform vec3 moon_color: source_color = vec3(0.95, 0.93, 0.85);
uniform float moon_path = 0.9;               // 月光里的水纹有多亮
uniform vec2 pool_xz = vec2(0.0, 0.0);       // 月下：那一汪月光的中心
uniform vec2 pool_size = vec2(7.0, 4.2);     //        和半径（横着、顺着河）
uniform float pool_glow = 0.045;             //        那一汪把水照亮多少
uniform float far_z = -11.5;                 // 远岸：水到这里就到头了
uniform vec3 mist_color: source_color = vec3(0.26, 0.29, 0.29);   // 远岸：水到头的地方和山脚下的雾。天空那头用的也是这个颜色，两边接得上
uniform vec4 ripple0 = vec4(0.0);            // 六圈涟漪，各是 (世界坐标 x, z, 已经荡了多久, 力度)；力度是 0 的那一圈不算
uniform vec4 ripple1 = vec4(0.0);
uniform vec4 ripple2 = vec4(0.0);
uniform vec4 ripple3 = vec4(0.0);
uniform vec4 ripple4 = vec4(0.0);
uniform vec4 ripple5 = vec4(0.0);

varying vec3 v_world;

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

// 一圈涟漪（世界的 x、z）。返回这一圈在这里有多亮；荡过的时侯把水纹的坐标 w 往外挤一下
float ripple(vec4 r, vec2 p, inout vec2 w) {
	if (r.w <= 0.0) {
		return 0.0;
	}
	vec2 off = p - r.xy;
	float d = length(off);
	float front = r.z * 1.3;                                   // 每秒荡开 1.3 个单位（一格）
	float e = d - front;                                       // 离这一圈多远（圈外面是正的）
	float fade = (1.0 - smoothstep(0.25, 1.6, r.z)) * smoothstep(0.0, 0.06, r.z) * r.w;
	float squeeze = e * 9.0 * exp(-e * e * 3.0);               // 圈的前面往外推，后面跟着回来
	w += off / max(d, 0.001) * squeeze * fade * 0.08;
	float ring = exp(-e * e / (2.0 * 0.045 * 0.045));          // 一圈细细的亮线
	ring += 0.35 * exp(-(e + 0.28) * (e + 0.28) / (2.0 * 0.05 * 0.05));   // 后面跟着一圈更淡的
	// 沿着圈亮度有起伏，不是一个处处一样亮的几何圆（每一圈起伏的地方不一样：拿力度当种子）
	float uneven = 0.7 + 0.3 * vnoise(off / max(d, 0.001) * 1.7 + vec2(r.w * 5.0, r.w * 3.0));
	return ring * fade * uneven;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 远岸：水到 far_z 就到头了，这一片让给后面的天空
	if (layout == 2 && v_world.z < far_z) {
		discard;
	}
	float t = TIME;
	vec2 p = v_world.xz;                        // 河面上的位置：x 是横着，z 是顺着河（越往近处越大）

	// ---- 涟漪
	vec2 w = p;
	float ring = ripple(ripple0, p, w);
	ring += ripple(ripple1, p, w);
	ring += ripple(ripple2, p, w);
	ring += ripple(ripple3, p, w);
	ring += ripple(ripple4, p, w);
	ring += ripple(ripple5, p, w);

	// ---- 水纹：和大厅里一样的算法，只是画在世界上
	float dens = lines_per_unit;
	float phase = w.y * dens - t * flow;
	float id = floor(phase + 0.5);                                  // 第几条
	float lid = mod(id, 97.0);                                       // 拿它当随机数的种子。数越积越大以后浮点数就不准了，所以取余
	float ys = w.y - t * flow / dens;                                // 跟着水一起往近处走的坐标
	float amp = (1.0 / dens) * (0.05 + 0.10 * vnoise(vec2(w.x * 0.5 + lid * 3.1, ys * 0.6)));
	float delta = amp * sin(w.x * 3.0 + lid * 1.9 + t * 0.15);
	delta += (1.0 / dens) * 0.02 * sin(w.x * 8.0 - lid * 2.6 + ys * 1.5 + t * 0.22);
	float aa = fwidth(phase);                                        // 一个屏幕像素横跨多少相位（远处的大）
	float d = abs(fract(phase + delta * dens) - 0.5);                // 离最近一条水纹的中线多远（相位）
	float half_w = line_px * 0.5 * aa;                               // 线的粗细按屏幕像素算，远近一样粗
	float ln = 1.0 - smoothstep(half_w, half_w + aa, d);
	// 远处的水纹挤到一起了（两条之间不到两三个像素）：别让它们糊成一片灰，淡出去
	ln *= 1.0 - smoothstep(0.16, 0.42, aa);
	// 断成一笔一笔的：每条线断的地方都不一样，一笔里面也有一段亮一段淡
	float stroke = smoothstep(0.40, 0.56, vnoise(vec2(w.x * 0.45 + lid * 13.7, ys * 0.9 + lid * 0.37)));
	stroke *= 0.75 + 0.25 * vnoise(vec2(w.x * 1.1 + lid * 5.0, ys * 2.2));
	// 远处的水纹淡一些（aa 是一个像素横跨多少相位：远处的大）
	float far = smoothstep(0.012, 0.11, aa);
	float a = ln * stroke * line_alpha * mix(1.0, 0.3, far);

	// ---- 底色：章节、连击的颜色往墨色里压一压（夜里）
	vec3 base = mix(water_color, vec3(0.012, 0.017, 0.024), night);
	vec3 line_tint = mix(light_foam_color, vec3(0.80, 0.90, 0.86), 0.6);
	vec3 col = base;

	// ---- 光从哪来
	float path = 0.0;                                               // 月光落在这里有多强
	if (layout == 1) {
		// 长河：月影在左侧，月光贴着它往近处流，越往近处越宽
		float dz = p.y - moon_xz.y;
		float dx = p.x - moon_xz.x;
		float spread = 0.5 + 0.9 * smoothstep(0.0, 12.0, dz);
		path = exp(-dx * dx / (2.0 * spread * spread)) * smoothstep(0.0, 1.6, dz);
		// 月影：水里的，边被水纹揉得弯弯曲曲（抖一秒钟换八次相位；取余，别让相位越积越大）
		float beat = mod(floor(t * 8.0), 64.0);
		vec2 mq = p;
		mq.x += sin(p.y * 9.0 + t * 1.1) * 0.03;
		float md = distance(mq, moon_xz);
		md += (vnoise(vec2(p.y * 7.0 + beat * 0.53, p.x * 1.3 - beat * 0.37)) - 0.5) * 0.05;
		float halo = moon_radius * 2.0;
		col += moon_color * exp(-md * md / (2.0 * halo * halo)) * 0.06;
		col = mix(col, moon_color * 0.9, (1.0 - smoothstep(moon_radius - 0.03, moon_radius + 0.03, md)) * 0.8);
	} else if (layout == 3) {
		// 月下：棋盘底下一汪月光。水纹在那一汪里让开
		vec2 q = (p - pool_xz) / pool_size;
		float rim = length(q) + (vnoise(p * 0.7 + vec2(3.7, 1.1)) - 0.5) * 0.06;     // 边不那么圆，像水里的影子
		path = 1.0 - smoothstep(0.70, 1.0, rim);                               // 往边上慢慢淡出去
		col += moon_color * path * pool_glow;
		a *= 1.0 - 0.7 * path;
	} else {
		// 长河：水纹走进月光里会亮起来，两条水纹之间也浮着一点
		a += ln * stroke * path * moon_path;
		col += moon_color * path * 0.045;
	}

	// ---- 涟漪的圈
	a += ring * 0.55;
	col += line_tint * ring * 0.04;

	// ---- 远岸：水纹往远处越来越淡，水让进雾里
	if (layout == 2) {
		float mist = 1.0 - smoothstep(far_z, far_z + 6.5, w.y);     // 离水到头的地方 6.5 个单位以内开始起雾
		a *= 1.0 - mist;
		col = mix(col, mist_color, mist * 0.88);
	}

	// ---- 四角压暗一点，把眼睛收到棋盘上
	vec2 suv = SCREEN_UV;
	vec2 asp = VIEWPORT_SIZE / max(VIEWPORT_SIZE.y, 1.0);
	float vig = smoothstep(0.55, 1.25, length((suv - vec2(0.5, 0.55)) * vec2(asp.x * 0.75, 1.0)));
	col *= 1.0 - 0.30 * vig;

	// 底色很暗，只有几个色阶，渐变会一条一条的（banding）：按屏幕像素掺一点抖动把它打散
	col += (hash21(mod(floor(SCREEN_UV * VIEWPORT_SIZE), 64.0)) - 0.5) / 255.0;
	ALBEDO = col + line_tint * a;
}
