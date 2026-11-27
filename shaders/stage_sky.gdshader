shader_type canvas_item;
// 远岸（游戏里背景的第二种布局）：画面顶上的一条天空，画在三维场景的后面（挂在一个 layer 是 -1 的 CanvasLayer 上）。
// 从上往下是：墨色的夜空、一轮月亮、三层远山（远的又淡又高，近的一层比一层深）、山脚下的雾。
// 这一条的最底下就是水到头的地方——画面上在哪个高度，由 scripts/stage_backdrop.gd 每一帧对着镜头算出来，
// 这一块的高度跟着它变，所以山永远是立在水尽头的对面
uniform float aspect = 6.6;                  // 这一条天空的宽高比（宽除以它自己的高）
uniform vec2 moon = vec2(0.74, 0.17);        // 月亮在这一条天空里的位置（宽、高各是几分之几）
uniform float moon_radius = 0.10;            // 月亮的半径（这一条天空的高各是几分之几）
uniform vec3 sky_top: source_color = vec3(0.012, 0.016, 0.026);
uniform vec3 sky_low: source_color = vec3(0.050, 0.068, 0.082);       // 靠近山脚的天色
uniform vec3 moon_color: source_color = vec3(0.95, 0.93, 0.85);
uniform vec3 mist_color: source_color = vec3(0.26, 0.29, 0.29);       // 山脚下的雾。水到了尽头也是这个颜色（stage_water.gdshader），两边接得上

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

// 一道山脊：几个大小不一的起伏叠出来的。x 是横着走了多远（以这条天空的高算一），seed 把每一道错开
float ridge(float x, float seed) {
	float n = 0.62 * vnoise(vec2(x, seed * 3.1));
	n += 0.28 * vnoise(vec2(x * 2.3 + 5.0, seed * 5.7 + 1.0));
	n += 0.10 * vnoise(vec2(x * 5.1 + 9.0, seed * 2.3 + 4.0));
	return n;
}

void fragment() {
	float t = mod(TIME, 600.0);
	vec2 p = vec2(UV.x * aspect, UV.y);            // 等比坐标：这条天空的高是 1
	vec3 col = mix(sky_top, sky_low, smoothstep(0.0, 1.0, UV.y));

	// 月亮（天上的那轮，不是水里的）：四周一圈月晕
	vec2 mc = vec2(moon.x * aspect, moon.y);
	float md = distance(p, mc);
	float halo = moon_radius * 2.6;
	col += moon_color * exp(-md * md / (2.0 * halo * halo)) * 0.20;
	col = mix(col, moon_color, (1.0 - smoothstep(moon_radius - 0.003, moon_radius + 0.003, md)) * 0.92);

	// 三层远山：远的淡（快和天色分不开了，像隔着一层水汽），近的深。山脊极慢地横着走，像云在过
	float drift = t * 0.004;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float base = 0.50 + fk * 0.15;
		float amp = 0.26 - fk * 0.04;
		float x = (p.x + drift * (3.0 - fk)) * (0.9 + fk * 0.45) + fk * 7.3;
		float top = base - amp * (ridge(x, fk) - 0.5) * 2.0;
		float body = smoothstep(top - 0.004, top + 0.004, UV.y);        // 山脊以下才是山体
		// 山比它后面的天色深才算看得见。远的那层掺三成天色（像隔着水汽），近的一层比一层深
		vec3 mount = mix(vec3(0.010, 0.014, 0.019), col, 0.30 - fk * 0.10);
		col = mix(col, mount, body);
	}

	// 山脚下的雾：越往下越浓，到了水到头的地方就是雾的颜色
	float mist = smoothstep(0.70, 1.0, UV.y);
	col = mix(col, mist_color, mist * 0.92);

	// 天空很暗，只有几个色阶，渐变会一条一条的（banding）：按屏幕像素掺一点抖动把它打散
	col += (hash21(mod(floor(UV * vec2(aspect, 1.0) * 400.0), 64.0)) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
