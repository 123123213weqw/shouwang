shader_type canvas_item;
// 「镜头钻进水车」的那层水（scripts/uis/transitions/transition_wheel.gd）。一张铺满画面的节点，画什么全在这儿算。
// 它底下已经画好的画面（棋盘、河、界面）取得到（screen_tex）：水浅的地方隔着水看得见——被水揉得晃、吸掉了红发了青、
// 落着焦散的光；水越深越糊，最后只剩水色。
// 每一点算一个"水有多深"的数 W：比 0 小是干的，越大水越深。
//   盖住  cover 从 0 到 1：水从四面涌向 focus（最后被盖住的那一点，平时放水车），下面（近处）的水先漫上来
//   掀开  drain 从 0 到 1：一条水线从画面上边滑到下边（镜头正从水里升起来，水从镜片上滑下去），越滑越快
//   两个都是 0 的时侯整张透明（刚装上样式、白画两帧预热用的就是这个状态）
// 噪声全靠算，不贴图：贴图铺满画面有缝，水线上会看出一条直的接缝
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float cover = 0.0;            // 盖住：0 还没有水，1 盖严
uniform float drain = 0.0;            // 掀开：0 盖严，1 全退净（这时 cover 一直是 1）
uniform vec2 focus = vec2(0.5, 0.5);  // 盖住时最后被盖住的那一点
uniform float aspect = 1.6;           // 画面的宽高比
uniform vec3 tint: source_color = vec3(0.13, 0.52, 0.44);   // 要去的这一关的底色
uniform float seed = 0.0;             // 每一趟换一个数：水线上的起伏、焦散的网都不是每回都一样
uniform float zoom = 1.0;             // 焦散的网放大几倍：镜头推近时网跟着大，拉远时跟着小，水才像是镜头眼前的那一片

const float AMP = 0.05;       // 水线起伏多大（画面的高度是 1）。掀开时水线的两头要留出比它还宽的余量：
                              // 刚掀开的那一帧四角必须还是实的，退净的那一帧底边必须一条不剩

// 数值要稳：头一步只乘 0.1031，输入到几百上千小数部分还够用。原来抄水面那份的写法头一步乘 123.34，
// 输入上到十几以后小数只剩十几个比特，相邻像素算同一个格子角会得到不同的值，噪声沿着格子的边裂开——
// 直缝、带直边的暗三角（做河灯的同事把噪声原样画出来逐像素对拍查出来的）
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 平滑的值噪声，0 到 1（样子和游戏里的水面 stage_water.gdshader 一样，哈希换成上面那个稳的）
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

// 焦散：水面把光聚成的一张亮网。水面是几道方向、长短、快慢都不一样的波叠起来的；它把照下来的光折来折去，
// 有的地方挤到一起（亮），有的地方散开（暗）。挤的程度就是"水面上的点落到水底的哪儿"这张映射的雅可比行列式：
// 越接近 0 越亮。零线是弯弯扭扭的曲线，网就是这张网。每道波的斜率直接写得出来：不用叠代，也不用贴图。
//（试过"值噪声的脊"和"会漂的点阵的分界"：前者有横平竖直的格子味，后者是一堆直线段，像碎冰，都不像光）
// base_freq 是波的长短，slope 是波面最陡的地方有多陡（越陡线越密），sharp 是线有多细，off 把这一层挪一挪、转一转
float web(vec2 p, float t, float base_freq, float slope, float sharp, float off) {
	p += vec2(seed * 3.0 + off, seed * 5.0);
	float jxx = 1.0;
	float jxy = 0.0;
	float jyy = 1.0;
	for (int k = 0; k < 6; k++) {
		float f = float(k);
		float ang = f * 2.399 + seed + off;               // 方向：每道比上一道转 137°，方向才撒得开
		vec2 dir = vec2(cos(ang), sin(ang));
		float d = (slope + f * 0.05) * cos(dot(dir, p) * (base_freq + f * 2.2) + t * (0.8 + 0.31 * f) + f * 1.7);
		jxx += d * dir.x * dir.x;
		jxy += d * dir.x * dir.y;
		jyy += d * dir.y * dir.y;
	}
	float det = jxx * jyy - jxy * jxy;
	return sharp / (det * det + sharp);
}

// 两层网叠起来：一层粗、一层细，各漂各的，交叉的地方亮成一个结
float caustic(vec2 p, float t) {
	return min(web(p, t, 8.0, 0.7, 0.0012, 0.0) + 0.55 * web(p, t * 1.2, 15.0, 0.7, 0.0008, 2.6), 1.0);
}

void fragment() {
	float t = TIME;
	vec2 P = UV * vec2(aspect, 1.0);          // 等比坐标：画面的高度是 1
	float live = smoothstep(0.0, 0.05, max(cover, drain));     // 还没开始的时侯是 0：这会儿什么都不能画出来

	// ---- 水线上的起伏：一层大弯、一层小碎
	float bump = (vnoise(P * 1.9 + vec2(seed * 13.0, seed * 7.0) + t * vec2(0.05, 0.02)) - 0.5) * 2.6;
	bump += (vnoise(P * 5.3 + vec2(seed * 5.0, t * 0.09)) - 0.5);

	// ---- 这一点水有多深
	float W;
	float pack;                               // 这一点被"压实"到什么程度：压实了就只画水色，不再透底下的画面
	if (drain > 0.0) {
		// 水线先慢后快（水从镜片上滑下去是越滑越快），中间塌一点：两边的水多挂一会儿
		float across = (UV.x - 0.5) * 2.0;
		float line = -0.15 + 1.53 * (0.35 * drain + 0.65 * drain * drain) + 0.035 * across * across;
		W = UV.y - line;
		// 刚掀开还是实的；水线进了画面，它底下的才透出东西来
		pack = 1.0 - smoothstep(0.05, 0.25, drain);
	} else {
		// 离 focus 多"深"：q 按 focus 到那一边的距离归一，那一边上全是 1
		vec2 F = focus * vec2(aspect, 1.0);
		vec2 q = P - F;
		vec2 room = mix(vec2(aspect, 1.0) - F, F, step(q, vec2(0.0)));
		vec2 u = abs(q) / max(room, vec2(0.02));
		float rho = pow(pow(u.x, 3.0) + pow(u.y, 3.0), 1.0 / 3.0);      // 圆角的方：四条边上是 1，角上比 1 大一点
		float phi = 1.0 - min(rho, 1.0);                                // focus 上是 1，四条边和四个角上都是 0
		W = cover * 1.16 - phi * (1.0 - smoothstep(0.75, 1.0, cover));  // 快盖严的时侯各处的水深拉平
		// 镜头是往水里扎的：下面（近处）的水先漫上来
		W += (UV.y * 2.0 - 1.0) * 0.08 * smoothstep(0.0, 0.3, cover);
		pack = smoothstep(0.85, 0.99, cover);                           // 快盖严的时侯都压实
	}
	W += bump * AMP * live;

	// ---- 隔着水看的画面：水浅的地方整片在晃（两层流动的噪声各推一点）；贴着水线再鼓一下，
	//      像水珠鼓起来的边把旁边的东西挤大了。鼓的方向是往水里（W 变大的方向）
	vec2 flow = vec2(vnoise(P * 5.0 + vec2(t * 0.35, seed)), vnoise(P * 5.0 + vec2(4.7, 1.3) - vec2(t * 0.3, 0.0))) - 0.5;
	vec2 n = normalize(vec2(dFdx(W), dFdy(W)) + vec2(0.00001, 0.0));
	float bulge = exp(-W * W / (2.0 * 0.035 * 0.035));
	vec2 off = flow * 0.014 + n * bulge * 0.03;
	vec3 scene = texture(screen_tex, SCREEN_UV + off * live).rgb;

	// ---- 颜色
	float deep = max(smoothstep(0.0, 0.5, W), pack);                // 水有多浑：0 看得清底下的东西，1 只剩水色
	float soak = smoothstep(-0.05, 0.03, W) * live;                 // 这一点让水打湿了多少（水线外面那一圈也算一点）
	// 网上有的段亮、有的段暗（一张慢慢变的噪声），不是处处一样亮
	vec2 Z = (P - vec2(aspect * 0.5, 0.5)) * zoom + vec2(aspect * 0.5, 0.5);      // 以画面正中为准放大
	float light = caustic(Z, t) * (0.35 + 0.65 * vnoise(Z * 1.7 + vec2(t * 0.06, -t * 0.04) + seed));
	// 隔着水看的：红让水吸掉一点，发青；焦散的光落在底下的东西上，东西越亮越看得出来
	float luma = dot(scene, vec3(0.299, 0.587, 0.114));
	vec3 seen = scene * mix(vec3(1.0), vec3(0.72, 0.90, 0.90), soak);
	seen += vec3(0.55, 0.85, 0.80) * light * soak * (0.05 + 0.25 * luma);
	// 水色：暗青，上面（离水面近）亮、下面暗；透一点要去的这一关的底色
	vec3 base = mix(vec3(0.010, 0.062, 0.070), tint * vec3(0.26, 0.40, 0.40), 0.30);
	vec3 water = base * mix(1.6, 0.45, UV.y);
	water += vec3(0.55, 0.85, 0.80) * light * 0.22 * mix(1.0, 0.5, UV.y);
	vec3 col = mix(seen, water, deep);
	// 水线：一道细的亮边（玉色）。一段亮一段暗（反光只在对着光的那几段才亮），不是描出来的一圈白线；外面再晕开一点。
	// 贴着它外面还有一道细暗线：水鼓起来的边把外面的光挡了一线
	float sparkle = smoothstep(0.2, 0.8, vnoise(P * 11.0 + vec2(seed * 17.0, t * 0.25)));
	float rim = exp(-(W - 0.004) * (W - 0.004) / (2.0 * 0.0022 * 0.0022)) * sparkle;
	rim += 0.15 * exp(-(W - 0.004) * (W - 0.004) / (2.0 * 0.011 * 0.011));
	col += vec3(0.80, 0.90, 0.86) * rim * live * 0.9;
	col *= 1.0 - 0.45 * exp(-(W + 0.007) * (W + 0.007) / (2.0 * 0.0028 * 0.0028)) * live;

	// 水底很暗、只有几个色阶，渐变会一条一条的：按屏幕像素掺一点抖动把它打散
	col += (hash21(mod(floor(FRAGCOORD.xy), 64.0)) - 0.5) / 255.0;
	COLOR = vec4(col, smoothstep(-0.05, 0.0, W) * live);
}
