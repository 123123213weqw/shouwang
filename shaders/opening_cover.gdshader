shader_type canvas_item;
// 开场动画的底幕：一开始把整个画面盖住，收尾的时候让出一个洞（从一点向外、自下而上、或者像纸被水浸掉那样化开），
// 露出底下真正的标题页
uniform sampler2D texture_flow_map: repeat_enable, filter_linear;   // 要平铺着取样，得明说允许
uniform vec3 color: source_color = vec3(0.0);
uniform int mode = 0;              // 0 全盖住；1 从 origin 向外让开；2 自下而上让开；3 噪点化开
uniform float progress = 0.0;      // 0 全盖住，1 全让开
uniform vec2 origin = vec2(0.5, 0.5);
uniform float soft = 0.25;
uniform float aspect = 1.6;        // 画面的宽高比

void fragment() {
	vec2 p = UV;
	float keep = 1.0;               // 这一点还盖着多少
	if (mode == 1) {
		// d：离 origin 的距离，离得最远的那一角算作 1
		vec2 far = vec2(max(origin.x, 1.0 - origin.x) * aspect, max(origin.y, 1.0 - origin.y));
		float d = distance((p - origin) * vec2(aspect, 1.0), vec2(0.0)) / max(length(far), 0.001);
		float r = progress * (1.0 + soft);
		keep = smoothstep(r - soft, r, d);
	} else if (mode == 2) {
		float edge = 1.0 - progress * 1.3;
		keep = 1.0 - smoothstep(edge - soft, edge + soft, p.y);
	} else if (mode == 3) {
		float n = texture(texture_flow_map, p * vec2(3.0 * aspect, 3.0)).x;
		float n2 = texture(texture_flow_map, p * vec2(9.0 * aspect, 9.0) + vec2(0.31, 0.57)).y;
		float v = n * 0.7 + n2 * 0.3;
		keep = smoothstep(progress * 1.3 - soft, progress * 1.3 + soft, v);
	}
	COLOR = vec4(color, keep);
}
