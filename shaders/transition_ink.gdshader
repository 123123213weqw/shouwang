shader_type canvas_item;
// 换关的过渡「墨迹晕开」（scripts/uis/transitions/transition_ink.gd）里那一层墨。
// 晕开的算法是从开场的 opening_ink.gdshader 学来的：每一点算一个数，墨的前沿是一个阈值，边的不规则揉在那个数里。
// 这里两头都要用——盖住是墨从落点往外晕，掀开是墨从主角落脚的地方往外化开——所以归成一个式子：
//   F   这一点离落点多"远"：0 在落点，1 在离落点最远的那一角。大瓣、小疙瘩、纸上的毛刺都揉在里面
//   s   这一点离墨的前沿多远，正的这边是墨：盖住 s = front - F，掀开 s = F - hole
//   湿边、渗开的那一圈、须都是照着 s 画的。所以晕开的边和化开的边是同一种质感，只是褪的时侯外面多留一圈淡痕
//
// 噪声不用贴图：算出来的值噪声是光滑的，边才像墨洇进纸里（opening_ink.gdshader 里也是这个道理）。贴图只用来做纸纹。
// 盖严是算出来的，不是试出来的：F 在画面里最大正好是 1——凹进去的湾到了画面边上要收平（见下面那一句 if）——
// 所以 front 走到 1.05（脚本里的 FRONT_END）时，画面里每个点都在墨里面，离前沿还隔着好几条湿边的宽度。
uniform sampler2D texture_flow_map: repeat_enable, filter_linear;   // 纸纹（开场动画抖笔触用的那一张）。要平铺着取样，得明说允许
uniform vec3 ink: source_color = vec3(0.02, 0.05, 0.05);   // 厚处的墨色：脚本把要去的这一关的底色掺了一成进来
uniform vec2 origin = vec2(0.5, 0.5);   // 墨从哪儿晕开；掀开的时侯是从哪儿化开
uniform float aspect = 1.6;             // 画面的宽高比
uniform float front = 0.0;              // 盖住：墨走到哪儿了。0 还没有墨，1.05 盖满
uniform float hole = 0.0;               // 掀开：化开的洞走到哪儿了。0 还没化，1.05 褪净
uniform float revealing = 0.0;          // 0 盖住（或者还没开始），1 掀开
uniform float residue = 1.0;            // 掀开的时侯退掉的墨留下的淡痕还剩多少，收尾时褪到 0
uniform float seed = 0.0;               // 每一趟换一个形状

// 几个宽度都按"到最远那一角的距离"算（1152×720 的画面上，0.01 大概是 7 到 8 个像素）
const float RIM = 0.016;         // 湿边多宽
const float RIM_IN = 0.06;       // 湿边往里多远是薄的：紧挨着湿边的墨淡一些，湿边才看得出是一道边
const float BLEED = 0.05;        // 盖住的时侯墨前面渗开的那一圈多宽
const float STAIN = 0.16;        // 掀开的时侯退掉的墨留下的淡痕多宽
const float BLEED_ALPHA = 0.34;  // 那一圈最浓的地方有多浓
const float STAIN_ALPHA = 0.30;

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

// 把一层半透明的东西盖到 c 上面（c 是直通的 rgba，不是预乘的）
vec4 over(vec4 c, vec3 rgb, float a) {
	float out_a = a + c.a * (1.0 - a);
	vec3 out_rgb = (rgb * a + c.rgb * c.a * (1.0 - a)) / max(out_a, 1e-4);
	return vec4(out_rgb, out_a);
}

void fragment() {
	vec2 p = UV;
	vec2 q = (p - origin) * vec2(aspect, 1.0);
	vec2 far = vec2(max(origin.x, 1.0 - origin.x) * aspect, max(origin.y, 1.0 - origin.y));
	float dist = length(q);
	float r = dist / max(length(far), 0.001);
	vec2 dir = q / max(dist, 1e-4);
	vec2 o1 = vec2(seed, seed * 1.37 + 7.1);
	vec2 o2 = vec2(seed * 0.71 + 31.7, seed * 1.91 + 3.3);
	vec2 o3 = vec2(seed * 1.13 + 17.9, seed * 0.53 + 23.3);

	// ---- 形状。大瓣和小疙瘩是"沿着方向"的起伏，乘着 r：离落点越远摆得越开，近处几乎是圆的（一滴墨刚落下来是圆的）
	float lobe = vnoise(dir * 1.7 + q * 0.4 + o1) - 0.5;
	float lump = vnoise(dir * 4.5 + q * 1.1 + o2) - 0.5;
	float grit = vnoise(q * 9.0 + o3) - 0.5;
	float d = r * (lobe * 0.36 + lump * 0.16) + grit * (0.004 + 0.04 * r);
	// 凹进去的湾（d > 0，这一边的墨走得慢）到了画面边上要收平：不然盖满的那一帧，远的那个角会漏出一条棋盘。
	// 收平以后 F 在画面里最大正好是 1：正的那一半最大是 0.28r + 0.002，乘上 (1 - r) / 0.3 以后不超过 r(1 - r) + 0.002
	if (d > 0.0) d *= clamp((1.0 - r) / 0.3, 0.0, 1.0);
	float f = r + d;
	// 须：几缕顺着半径方向渗出去的，越远越细；毛刺是短得多、密得多的小须
	float streak = vnoise(dir * 13.0 + q * vec2(0.8, 1.3) + o2.yx);
	float tend = smoothstep(0.60, 0.76, streak) * (0.03 + 0.05 * r);
	float hair = vnoise(dir * 26.0 + q * 2.6 + o3.yx);
	float burr = smoothstep(0.62, 0.78, hair) * (0.008 + 0.014 * r);
	float ft = f - tend - burr;

	// ---- 离前沿多远（正的这边是墨）
	float s = revealing > 0.5 ? f - hole : front - f;
	float st = revealing > 0.5 ? ft - hole : front - ft;
	float aa = fwidth(s) + 1e-4;                 // 一个像素
	float edge = smoothstep(RIM - aa, RIM + aa, s);
	float in_body = smoothstep(-aa, aa, s);
	float in_full = smoothstep(-aa, aa, st);
	float rim_a = in_body * (1.0 - edge);
	float body_a = in_body * edge;
	// 墨外面那一圈：盖住的时侯是墨往前渗开的，掀开的时侯是退掉的墨留下的淡痕
	float wash_w = mix(BLEED, STAIN, revealing);
	float wash_a = mix(BLEED_ALPHA, STAIN_ALPHA, revealing) * (1.0 - smoothstep(0.0, wash_w, -s)) * (1.0 - in_full);
	// 还没开始落墨的时侯（装上样式预热的那两帧）整张要透明；掀开的淡痕收尾时褪掉
	wash_a *= smoothstep(0.0, 0.02, front) * mix(1.0, residue, revealing);
	// 须的尾巴是淡的，尖上聚着一粒更深的墨珠（湿边缩成的一点）；毛刺短，整根都是深的
	float tail_a = max(in_full - in_body, 0.0) * smoothstep(0.0, 0.004, st) * (0.9 - 0.62 * smoothstep(0.0, max(tend + burr, 2e-4), st));
	float bead_a = in_full * (1.0 - smoothstep(0.004, 0.012, st)) * 0.95;

	// ---- 墨色。落点那儿厚、越往外越薄，大块的深浅不匀（渗进纸里有的地方吃墨多），细的是纸纹
	float mottle = vnoise(q * 2.4 + o3 + TIME * 0.012) * 0.65 + vnoise(q * 6.2 + o1) * 0.35;
	float thick = clamp(1.0 - r * 0.5 + (mottle - 0.5) * 0.9, 0.0, 1.0);
	vec3 fiber = texture(texture_flow_map, p * vec2(aspect, 1.0) * 5.6 + seed * 0.37).rgb;
	float grain = (fiber.r + fiber.g) * 0.5;     // 竖纤维和横纤维合起来
	vec3 thin = mix(ink, vec3(0.34, 0.37, 0.36), 0.26);      // 薄处发灰：纸的颜色透上来
	vec3 body = mix(thin, ink, thick);
	body *= 1.0 + (grain - 0.5) * (0.75 - 0.45 * thick);     // 纸纹：墨越薄越看得见纸
	body *= 1.0 + 0.22 * (1.0 - smoothstep(RIM, RIM + RIM_IN, s));   // 紧挨着湿边的里面淡一些
	body += (hash21(FRAGCOORD.xy) - 0.5) / 255.0;            // 底色很暗，只有几个色阶：掺一点抖动，免得一条一条的
	vec3 rim = ink * 0.22;                                  // 湿边：墨往前走的时侯色都堆在边上
	vec3 wash = vec3(0.44, 0.50, 0.48);

	vec4 c = over(vec4(0.0), wash, wash_a);
	c = over(c, mix(wash, ink, 0.5), tail_a);
	c = over(c, rim, bead_a);
	c = over(c, rim, rim_a);
	c = over(c, body, body_a);
	COLOR = c;
}
