shader_type canvas_item;
// 换关的过渡「墨迹晕开」（scripts/uis/transitions/transition_ink.gd）里那一层墨。
// 晕开的算法是从开场的 opening_ink.gdshader 学来的：每一点算一个数，墨的前沿是一个阈值，边的不规则揉在那个数里。
// 这里两头都要用——盖住是墨从落点往外晕，掀开是墨从主角落脚的地方往外化开——所以归成一个式子：
//   F   这一点离落点多"远"：0 在落点，1 在离落点最远的那一角。大瓣、圆齿、纸上的毛刺都揉在里面
//   s   这一点离墨的前沿多远，正的这边是墨：盖住 s = front - F，掀开 s = F - hole
//   从里往外是：厚的墨、薄的墨、湿边（最深的细细一道）、渗出去的淡墨和几缕须。都是照着 s 画的，
//   所以晕开的边和化开的边是同一种质感，只是褪的时侯淡墨拖得长一些、最后褪掉
//
// 边分三层，各管一件事：
//   大瓣   沿着方向的起伏，乘着 r：离落点越远摆得越开，近处几乎是圆的（一滴墨刚落下来是圆的）
//   圆齿   各向同性的两档起伏，波长一百多和六十来个像素：边上圆鼓鼓的小凸和小湾
//   毛刺   纸纹贴图里细的纤维，只取最粗的那一些：边上细碎的小毛。不用"顺着半径的细条"：那是炸开的太阳，不是墨
// 噪声除了纸纹都是算出来的值噪声（光滑，边才像墨洇进纸里；opening_ink.gdshader 里也是这个道理）。
//
// 盖严是算出来的，不是试出来的：F 在画面里最大正好是 1——凹进去的湾到了画面边上要收平（见下面那一句 if）——
// 所以 front 走到 1.05（脚本里的 FRONT_END）时，画面里每个点都在墨里面，离前沿还隔着好几条湿边的宽度。
uniform sampler2D texture_flow_map: repeat_enable, filter_linear;   // 纸纹（开场动画抖笔触用的那一张）。要平铺着取样，得明说允许
uniform vec3 ink: source_color = vec3(0.02, 0.05, 0.05);   // 厚处的墨色：脚本把要去的这一关的底色掺了一成进来
uniform vec2 origin = vec2(0.5, 0.5);   // 墨从哪儿晕开；掀开的时侯是从哪儿化开
uniform float aspect = 1.6;             // 画面的宽高比
uniform float front = 0.0;              // 盖住：墨走到哪儿了。0 还没有墨，1.05 盖满
uniform float hole = 0.0;               // 掀开：化开的洞走到哪儿了。0 还没化，1.05 褪净
uniform float revealing = 0.0;          // 0 盖住（或者还没开始），1 掀开
uniform float residue = 1.0;            // 掀开的时侯前沿外面拖着的淡墨还剩多少，收尾时褪到 0
uniform float seed = 0.0;               // 每一趟换一个形状
uniform int peek = 0;                   // 排查用（临时）：把中间量画成灰度

// 几个宽度都按"到最远那一角的距离"算（1152×720 的画面上，0.01 大概是 7 到 8 个像素）
const float RIM_IN = 0.07;       // 湿边往里多远是薄的：刚晕到的墨薄，透一点、淡一些，湿边才看得出是一道边
const float WISP = 0.045;        // 前沿外面渗出去的淡墨拖多长（掀开的时侯再乘上 STAIN）
const float STAIN = 1.6;         // 掀开的时侯淡墨拖得比盖住长这么多倍
const float WISP_ALPHA = 0.50;   // 淡墨贴着湿边那儿有多浓
const float SET_AT = 0.80;       // front 过了这儿墨就"实"了：薄的墨也不再透，盖满的那一帧才看不见后面的棋盘

// 格点上的随机数（0 到 1）。要经得住大一点的输入：每趟换形状是靠把噪声的坐标整个挪开几十格，
// 常见的那种写法（fract(p * vec2(123.34, 456.21)) 打头）挪到几十就不准了——乘出来几千，小数只剩三四位有效数字，
// 同一个格点从左边那一格算、从右边那一格算会差出零点几，噪声里就多出一条条竖的接缝（2026-11-27 在服务器上量到过）
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

	// ---- 纸纹。R 是竖纤维，G 是横纤维，B 是小块的深浅。一张 64×64 的小图铺在画面上，一格二百多像素，一个纹素三个多像素
	vec3 fiber = texture(texture_flow_map, q * 3.2 + seed * 0.37).rgb;
	float fuzz = (fiber.r + fiber.g) * 0.5;

	// ---- 形状
	float lobe = vnoise(dir * 1.7 + q * 0.45 + o1) - 0.5;
	float lobe2 = vnoise(dir * 4.2 + q * 0.9 + o2.yx) - 0.5;
	float bump = vnoise(q * 5.0 + o2) * 0.6 + vnoise(q * 11.0 + o3) * 0.4 - 0.5;
	// 正的那一半最大是 0.28r + 0.005：大瓣小瓣各乘 r 的一半幅度，圆齿和细毛是定长的那一点
	float d = r * (lobe * 0.44 + lobe2 * 0.12) + bump * (0.012 + 0.028 * r) + (fuzz - 0.5) * 0.006;
	// 凹进去的湾（d > 0，这一边的墨走得慢）到了画面边上要收平：不然盖满的那一帧，远的那个角会漏出一条棋盘。
	// 收平以后 F 在画面里最大正好是 1：正的那一半不超过 0.3r + 0.011，乘上 (1 - r) / 0.3 以后
	// 加到 r 上不超过 2r - r² + 0.04(1 - r)，r 不超过 1 的时侯它也不超过 1
	if (d > 0.0) d *= clamp((1.0 - r) / 0.3, 0.0, 1.0);
	float f = r + d;

	// ---- 离前沿多远（正的这边是墨）
	float s = revealing > 0.5 ? f - hole : front - f;
	// 湿的地方：边上一处一处更湿的段落——那儿边更糊、湿边更宽、渗出去的淡墨更长。三者共用一个起伏，才像同一处湿
	float wet = vnoise(q * 8.0 + o2.yx);
	float wet2 = wet * wet;
	float aa = fwidth(s) + 1e-4;                 // 一个像素
	float feather = aa + 0.0035 * wet2;          // 边糊开多宽：一个像素到四个像素
	float in_body = smoothstep(-feather, feather, s);
	float out_body = 1.0 - in_body;

	// ---- 湿边：最深的细细一道，宽窄、深浅一处一个
	float rim_w = 0.002 + 0.014 * wet2;
	float rim_a = in_body * (1.0 - smoothstep(rim_w - feather, rim_w + feather, s)) * (0.4 + 0.6 * wet2);
	// 墨心：刚晕到的地方薄，透一点；盖满之前墨就实了（盖满的那一帧后面不能看见棋盘）
	float thin_band = (1.0 - smoothstep(0.0, RIM_IN, s)) * smoothstep(0.06, 0.2, front);
	float set = smoothstep(SET_AT, 0.98, front);
	float body_a = in_body * (1.0 - 0.30 * thin_band * (1.0 - set) * (1.0 - revealing));

	// ---- 前沿外面：拖着的淡墨，和从边上渗出去的须
	float x = -s;                                // 这一点在墨的外面多远
	float wisp_w = WISP * mix(1.0, STAIN, revealing) * (0.35 + 1.1 * wet);
	float wisp_a = WISP_ALPHA * pow(1.0 - smoothstep(0.0, wisp_w, x), 1.2) * (0.55 + 0.45 * fuzz) * out_body;
	// 还没开始落墨的时侯（装上样式预热的那两帧）整张要透明；掀开的淡墨收尾时褪掉
	wisp_a *= smoothstep(0.0, 0.02, front) * mix(1.0, residue, revealing);
	// 须和毛刺：一幅顺着半径方向拉长的噪声里，取值正好是一半的地方是一根根顺着半径的细线。
	// 处处都有的是短毛刺；只在几段边上（sparse）留长的，才是"几缕渗开的须"
	float strand_n = vnoise(dir * 22.0 + q * vec2(0.5, 0.8) + o3.yx);
	float half = 0.025 / max(r, 0.08);           // 换成"取值差多少"：离落点越远，同样几个像素对应的角度越小
	float strand = 1.0 - smoothstep(half, half + 2.0 * fwidth(strand_n), abs(strand_n - 0.5));
	float sparse = smoothstep(0.55, 0.72, vnoise(dir * 3.0 + q * 0.3 + o2.yx));
	float strand_len = mix(0.010, 0.075, sparse) * (0.6 + 0.8 * r);
	float tail_a = strand * (1.0 - smoothstep(0.0, strand_len, x)) * mix(0.5, 0.9, sparse) * out_body;
	tail_a *= mix(1.0, residue, revealing);

	// ---- 墨色。落点那儿厚、越往外越薄；大块的深浅不匀（渗进纸里有的地方吃墨多，干了留下一圈圈的痕）；细的是纸纹
	float pool = vnoise(q * 1.7 + o2.yx + TIME * 0.01) * 0.6 + vnoise(q * 3.9 + o3 + TIME * 0.014) * 0.4;
	float thick = clamp(0.9 - 0.55 * smoothstep(0.0, 1.0, r) + (pool - 0.5) * 1.4 + 0.2 * smoothstep(0.42, 0.52, pool), 0.0, 1.0);
	thick *= 1.0 - 0.55 * thin_band;                              // 紧挨着湿边的里面是薄的
	vec3 pale = mix(ink, vec3(0.40, 0.44, 0.43), 0.7);            // 薄处：墨淡了，纸的颜色透上来
	vec3 body = mix(pale, ink, thick);
	body += (fuzz - 0.5) * (1.0 - thick) * 0.20;                   // 纸纹：墨越薄越看得见纸
	body += (fiber.b - 0.5) * 0.04;                                // 小块的深浅
	body += (hash21(FRAGCOORD.xy) - 0.5) / 255.0;                 // 底色很暗，只有几个色阶：掺一点抖动，免得一条一条的
	vec3 rim = ink * 0.2;                                          // 湿边：墨往前走的时侯色都堆在边上
	vec3 wisp_col = mix(ink, vec3(0.46, 0.51, 0.50), mix(0.8, 0.4, revealing));   // 淡墨：渗出去的比退掉的浅一些
	vec3 tail_col = mix(ink, vec3(0.30, 0.34, 0.33), 0.35);

	vec4 c = over(vec4(0.0), wisp_col, wisp_a);
	c = over(c, tail_col, tail_a);
	c = over(c, body, body_a);
	c = over(c, rim, rim_a);
	if (peek == 1) c = vec4(vec3(pool), 1.0);
	if (peek == 2) c = vec4(vec3(thick), 1.0);
	if (peek == 3) c = vec4(vec3(fuzz), 1.0);
	if (peek == 4) c = vec4(vec3(fiber.b), 1.0);
	if (peek == 5) c = vec4(vec3(d * 4.0 + 0.5), 1.0);
	if (peek == 6) c = vec4(vec3(vnoise(q * 1.7 + o2.yx)), 1.0);
	if (peek == 7) c = vec4(vec3(vnoise(q * 3.9 + o3)), 1.0);
	if (peek == 8) c = vec4(vec3(vnoise(q * 3.9 + o3 + TIME * 0.014)), 1.0);
	if (peek == 9) c = vec4(vec3(r), 1.0);
	if (peek == 10) c = vec4(vec3(s), 1.0);
	COLOR = c;
}
