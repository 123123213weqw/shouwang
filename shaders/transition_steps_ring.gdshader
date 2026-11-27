shader_type canvas_item;
// 石阶沉下去、浮上来的地方荡开的那一小圈（scripts/uis/transitions/transition_steps.gd 的涟漪池）。
// 画在三维棋盘上面、界面底下的那一层，样子照着 stage_backdrop.gd 落地的那圈环：俯着看，地上的圆在画面上是扁的（squash）。
// 一圈细细的亮线，后头跟着一圈更淡的；沿圈亮度有起伏，不是一个处处一样亮的几何圆。
// 在"还没开始"的状态下 strength 是 0，整张看不见（装上样式先白画两帧，把编译的钱趁黑幕花掉）
uniform vec3 color: source_color = vec3(0.86, 0.94, 0.90);   // 玉色，和落地那圈环一样
uniform float radius = 0.0;        // 主圈荡到哪儿了（0 中心，1 方块的边）
uniform float width = 0.05;        // 环多粗
uniform float strength = 0.0;      // 有多亮（0 看不见）
uniform float squash = 0.72;       // 顺着河的方向压成多扁

void fragment() {
	vec2 d2 = (UV - vec2(0.5)) * 2.0;
	d2.y /= squash;
	float d = length(d2);
	float ring = 1.0 - smoothstep(0.0, width, abs(d - radius));
	float trail = 0.35 * (1.0 - smoothstep(0.0, width * 1.6, abs(d - radius + 0.16)));
	float uneven = 0.75 + 0.25 * sin(atan(d2.y, d2.x) * 5.0 + radius * 9.0);
	COLOR = vec4(color, (ring + trail) * strength * uneven);
}
