shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// 换关的过渡「河灯涌来」的光海（scripts/uis/transitions/transition_lanterns.gd）：一条夜里漂满河灯的河。
// 全是算出来的，不贴图：
//   夜色   河的底，带着几道细水纹（和标题页那条河同一种画法）。跟着要去的这一关的底色走
//（night_from 是离开的那一关，night_to 是要去的，night_mix 在两者之间走）
//   灯     河面上的灯：远处的小而密、暗一些，近处的大而疏、亮。每盏是亮芯、光晕、水里的一道倒影（见 lamps）
//   光海   远处无数看不清的小灯合起来的那片光
//   烛光   近处那些真的灯（小图是样式摆在上面这一层）的光晕，位置每帧从样式传进来（lamp_*）
// 这一层同时就是"盖严"的那一层：盖住做完的那一刻整张不透明，底下的棋盘一点看不见。
// 用预乘的混合方式：光的分量不乘透明度，前锋还没盖到的地方、掀开让出来的洞里照样有光（只加不减）。
// 这个着色器自己算最终的颜色，节点的 modulate 管不到它，所有的量都从参数进。
// 还没开始的时侯（front 停在画面顶的外面、cover 是 0、洞关着）整张透明，连光也没有
//
// 河面是真的透视：画面上方外面很远有个消失点，河上的每一点由两个数定——
//   dy  离消失点多高（画面高的几分之几）：这一点画在 消失点 + (x × dy, dy)，灯有多大、光晕多大都和 dy 成正比
//   z   1 / dy，顺着河的距离，越小越近。灯顺流而下 = z 随时间匀速地变小（flow 匀速地涨）：
//       远处的看着慢慢挪，近处的越涌越快；横着一行的灯，远处挤成一片、近处散开
// 样式那边真的灯用的是同一个消失点、同一条 flow（见 transition_lanterns.gd 的 River）

uniform float aspect = 1.6;         // 画面的宽高比
uniform float view_h = 720.0;       // 画面有多高（逻辑像素）：算线的粗细、光点够不够一个像素
uniform vec3 candle: source_color = vec3(1.0, 0.84, 0.55);   // 烛火色
uniform vec3 ember: source_color = vec3(1.0, 0.50, 0.18);    // 烛火外圈、水里倒影偏红的那一圈
uniform vec3 night_from: source_color = vec3(0.02, 0.03, 0.035);   // 夜色：离开的那一关
uniform vec3 night_to: source_color = vec3(0.02, 0.03, 0.035);     // 夜色：要去的那一关
uniform float night_mix = 0.0;
uniform float flow = 0.0;           // 水已经流了多远（河面上的距离），样式每帧给。TIME 在过渡中途没法归零，所以不用它
uniform float front = 0.12;         // 盖住：灯河的前锋到了哪个深度（dy）。比它远的已经淹了
uniform float front_soft = 0.05;    // 前锋的柔边有多宽
uniform float cover = 0.0;          // 整张有多实：盖严那一瞬是 1（保险：不管前锋算到哪儿，四角和正中都不漏）
uniform vec2 hole_at = vec2(0.8, 0.55);   // 掀开：从哪一点先露（等比坐标：画面的高是 1）
uniform float hole_far = 1.0;       // 离这一点最远的那一角有多远：洞的半径拿它当 1
uniform float hole_r = 0.0;         // 洞现在多大（0 是关着的）
uniform float hole_soft = 0.2;      // 洞边有多柔
uniform int lamp_n = 0;             // 近处真的灯有几盏
uniform vec2 lamp_pos[36];          // 它们在画面上的位置（等比坐标）
uniform vec4 lamp_lit[36];          // x 光晕的半径（等比），y 亮度

const float VP_Y = -0.35;           // 消失点在画面上方外面这么远（画面高的几分之几）。越远透视越平，和游戏里俯着看棋盘的镜头越像
const float CELL_X = 0.14;          // 河面上横着相邻两盏灯隔多远（dy 是 1 的时候在画面上隔多宽）
const float CELL_Z = 0.22;          // 顺着河，一行灯有多厚（河面上的距离）
const float HALO = 0.030;           // dy 是 1 的灯：光晕的半径（等比坐标）
const float CORE = 0.0062;          // dy 是 1 的灯：亮芯的半径
const float REFL = 0.30;            // dy 是 1 的灯：倒影有多长。倒影是水面上的距离，近处按 dy 的平方拉长
const float LINE_GAP = 0.16;        // 水纹在河面上隔着多远

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

// 河面上的灯（船身看不清的那些，只画光）。gx、gz 是这一像素在河面上的位置（gz 已经算进了水流）。
// 返回 x 亮芯、y 光晕、z 倒影各有多亮。
// 灯摆在一个格子上（横着 CELL_X，顺着河 CELL_Z），可不能"查地面上相邻的九格"：透视是各向异性的，
// 旁边一行里一盏更近的灯，在画面上落到老远的地方，它的光晕伸过来的那片像素根本没查到它，就沿着格子边出现直的切口
//（2026-11-27 本机预览里看到的）。所以按画面找：每一行里只看屏幕位置真落在这一像素上下的那三列，
// 行多查一行近的（它的光晕往下搭过来）、两行远的（它们的倒影往下拖）
vec3 lamps(float gx, float gz, vec2 p, vec2 vp, float t) {
	// 揉一下：水流把灯冲散，别排成整齐的格子
	float wx = gx + (vnoise(vec2(gx * 0.8, gz * 0.8)) - 0.5) * 0.05;
	float wz = gz + (vnoise(vec2(gx * 0.8 + 7.3, gz * 0.8 + 2.1)) - 0.5) * 0.07;
	float jr = floor(wz / CELL_Z);
	vec3 sum = vec3(0.0);
	for (int a = 0; a < 4; a++) {
		float j = jr + float(a) - 1.0;
		float zc = (j + 0.5) * CELL_Z - flow;       // 这一行现在离镜头多远（格子是跟着水走的，要减去水流）
		if (zc < 0.3) {
			continue;                       // 比画面底还近得多的那一行，用不着
		}
		float dy_row = 1.0 / zc;
		// 这一行里，屏幕位置落在这一像素上下、左右一格以内的灯，列号只可能是这三个
		float i0 = floor((p.x - vp.x) / dy_row / CELL_X - 1.5);
		for (int b = 0; b < 3; b++) {
			vec2 id = vec2(i0 + float(b), j);
			vec4 h = hash42(id);
			float lamp_z = (j + 0.5 + (h.x - 0.5) * 0.6) * CELL_Z - flow;
			if (lamp_z < 0.3) {
				continue;
			}
			float lamp_dy = 1.0 / lamp_z;
			// 有没有灯：远处密、近处稀；一簇一簇的（水面上有的地方挤成一堆，有的地方空着）
			float p_here = mix(0.85, 0.15, smoothstep(0.45, 0.95, lamp_dy)) * (0.25 + 1.5 * vnoise(vec2(id.x * 0.7 + 3.1, id.y * 0.55)));
			if (h.w > p_here) {
				continue;
			}
			float lamp_x = (id.x + 0.5 + (h.y - 0.5) * 0.7) * CELL_X;
			vec2 off = p - (vp + vec2(lamp_x * lamp_dy, lamp_dy));
			float len = REFL * lamp_dy * lamp_dy;            // 倒影有多长
			if (off.y > len || off.y < -HALO * 4.0 * lamp_dy || abs(off.x) > max(HALO * 4.0 * lamp_dy, len * 0.5)) {
				continue;                       // 光晕够不着，倒影也不在下面
			}
			float varied = 0.7 + 0.6 * h.z;      // 灯有大有小
			float r = HALO * lamp_dy * varied;
			float d2 = dot(off, off);
			float rc = CORE * lamp_dy * varied;
			// 火苗晃：各盏快慢不一。远处暗一些
			float flick = 0.82 + 0.18 * sin(t * (5.0 + 4.0 * h.z) + h.x * 6.2831);
			float bright = mix(0.55, 1.0, smoothstep(0.35, 0.85, lamp_dy)) * (0.55 + 0.45 * h.y) * flick;
			// 查邻居只查到 3 倍光晕半径为止：边界上先淡到 0，看不出切口
			float fade = 1.0 - smoothstep(2.2 * r, 3.0 * r, sqrt(d2));
			float core = exp(-d2 / (2.0 * rc * rc));
			float halo = exp(-d2 / (2.0 * r * r));
			// 倒影：贴着灯往下一道，越往下越淡越宽，左右轻轻地摆（水在流），碎成一段一段的
			float refl = 0.0;
			if (off.y > 0.0) {
				float ry = off.y / len;
				float sway = sin(ry * 9.0 - t * 2.0 + h.x * 6.2831) * 0.12 * ry;
				float rx = (off.x / r - sway) / (0.42 * (1.0 + ry));
				float glint = 0.5 + 0.5 * vnoise(vec2(h.z * 37.0 + id.x, ry * 6.0 - t * 1.2));
				refl = exp(-rx * rx) * (1.0 - ry) * (1.0 - ry) * glint;
			}
			sum += vec3(core * fade, halo * fade, refl) * bright;
		}
	}
	return sum;
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);            // 等比坐标：画面的高是 1
	vec2 vp = vec2(0.5 * aspect, VP_Y);            // 消失点（远处）
	float t = mod(TIME, 600.0);
	float dy = p.y - vp.y;
	float gx = (p.x - vp.x) / dy;                  // 这一像素在河面上的位置
	float gz = 1.0 / dy + flow;

	// ---- 盖住：灯河的前锋从上游扫下来。灯打头，夜色跟在后面半步（先看见一排灯压过来，水才漫上来）
	float wob = (vnoise(vec2(p.x * 2.3, 4.1)) - 0.5) * 0.05 + (vnoise(vec2(p.x * 6.1, 9.2)) - 0.5) * 0.02;   // 前锋不是一条直线
	float fdy = dy + wob * smoothstep(0.3, 0.7, front);
	float lead = 0.05 + 0.10 * front;              // 灯比夜色领先这么多：越近灯越大，领先得越多
	float lit = 1.0 - smoothstep(front + lead - front_soft, front + lead + front_soft, fdy);
	lit = max(lit, cover);
	float a = 1.0 - smoothstep(front - front_soft, front + front_soft, fdy);
	a = max(a, cover);
	// 前锋前面先看见从灯河那边漫过来的一点暖光。只加不减：旧画面是被照亮的，不是被压暗的
	float spill = exp(-max(fdy - front - lead, 0.0) * 8.0) * (1.0 - lit) * smoothstep(0.2, 0.4, front);

	// ---- 掀开：从 hole_at 让开一个洞，边也不是圆的。夜色的边柔一些；灯贴着洞边就让开了，被挤成亮亮的一圈
	vec2 hq = p - hole_at;
	float hd0 = length(hq) / hole_far;
	vec2 hdir = hq / max(length(hq), 0.0001);
	float hole_on = smoothstep(0.0, 0.04, hole_r);
	float hwob = (vnoise(hdir * 2.1 + vec2(11.0, 3.0)) - 0.5) * 0.13
		+ (vnoise(hdir * 4.7 + vec2(2.0, 5.0)) - 0.5) * 0.05;
	float hd = hd0 + hwob * hole_on * smoothstep(0.0, 0.2, hd0);
	float open_n = mix(1.0, smoothstep(hole_r - hole_soft, hole_r + hole_soft, hd), hole_on);
	float open_l = mix(1.0, smoothstep(hole_r - 0.02, hole_r + 0.10, hd), hole_on);
	a *= open_n;
	float rim = exp(-pow((hd - hole_r) / (hole_soft + 0.04), 2.0)) * hole_on;

	// ---- 夜色：关卡的底色压进墨色里。四角再压暗一点，把眼睛收到中间
	vec3 night = mix(night_from, night_to, night_mix);
	float vig = smoothstep(0.55, 1.25, length((p - vec2(0.5 * aspect, 0.55)) * vec2(0.75, 1.0)));
	night *= 1.0 - 0.30 * vig;
	// 水纹：和标题页那条河同一种画法（细线、弯弯曲曲、断成一笔一笔），画在河面上跟着灯一起往近处流
	float zz = gz / LINE_GAP;
	float zid = floor(zz);
	float lwob = (vnoise(vec2(gx * 1.6 + zid * 3.7, zid * 1.3)) - 0.5) * 0.5 + (vnoise(vec2(gx * 6.0, zid * 5.1)) - 0.5) * 0.12;
	float thick = 0.65 / view_h / (LINE_GAP * dy * dy);        // 线有半个多像素粗，远近一样粗
	float ln = 1.0 - smoothstep(thick, thick * 2.2, abs(fract(zz + lwob) - 0.5));
	float stroke = smoothstep(0.42, 0.60, vnoise(vec2((p.x - vp.x) * 6.5 + zid * 13.7, zid * 0.37)));
	stroke *= 0.75 + 0.25 * vnoise(vec2((p.x - vp.x) * 14.0, zid * 5.0));
	float water = ln * stroke * (0.35 + 0.65 * smoothstep(0.4, 1.0, dy));

	// ---- 光：河面上的灯；远处的光海（越往远处越亮，带着一团一团的起伏）；近处真的灯的烛光
	vec3 l = lamps(gx, gz, p, vp, t);
	float sea = smoothstep(1.0, 0.36, dy) * (0.55 + 0.45 * vnoise(vec2(gx * 2.2, gz * 1.4)));
	vec3 halo = vec3(0.0);
	for (int i = 0; i < lamp_n; i++) {
		float d = distance(p, lamp_pos[i]) / lamp_lit[i].x;
		if (d < 1.0) {
			float q = 1.0 - d;
			halo += mix(ember, candle, q) * (q * q * pow(q, 0.2) * lamp_lit[i].y);   // 衰减曲线同 opening_glow
		}
	}
	float keep = lit * open_l;
	l *= keep * (1.0 + 1.6 * rim);                 // 洞边：让开的时侯灯被挤到边上，那一圈更亮
	halo *= keep;

	// ---- 合起来。亮芯偏白黄（烛火的芯）；光叠得多的地方也偏白
	vec3 col = night * a;
	col += candle * (l.y * 0.55 + sea * 0.16 * lit * open_l) + halo;
	col += vec3(1.0, 0.97, 0.90) * l.x * 1.3;
	col += ember * l.z * 0.6;
	col += mix(night, vec3(0.78, 0.90, 0.86), 0.6) * water * 0.16 * a;
	// 前锋前面漫过来的暖光
	col += candle * spill * 0.10 * open_n * (1.0 - cover);
	// 刚露出来的地方留一点烛光的余晖，往洞里很快淡掉：这一关像是从灯底下送出来的
	float after = exp(-max(hole_r - hd, 0.0) * 4.0) * hole_on * (1.0 - open_n);
	col += candle * after * 0.06;
	// 夜色很暗，渐变会一条一条的（banding）：按像素掺一点抖动把它打散
	col += (hash21(mod(floor(p * view_h), 64.0)) - 0.5) / 255.0 * a;
	COLOR = vec4(col, a);
}
