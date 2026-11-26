shader_type canvas_item;
// 开场动画里的剪影：和游戏里别的界面精灵一样会抖（用 FlowMap），另外能"亮起来"（从一点向外，或者像墨迹化开）、能"闪一下"
uniform sampler2D texture_albedo: source_color, filter_linear;
uniform sampler2D texture_flow_map: repeat_enable, filter_linear;   // 要平铺着取样，得明说允许
uniform vec3 color: source_color = vec3(1.0);
uniform float wobble = 2.0;        // 抖动的力度（同界面精灵的 displacement_power）
uniform float wobble_size = 5.0;
uniform int mode = 0;              // 0 整张直接画；1 从 origin 向外亮起；2 像墨迹那样化开
uniform float progress = 1.0;      // 0 到 1
uniform vec2 origin = vec2(0.5, 0.5);
uniform float soft = 0.2;          // 边缘的柔和程度
uniform float flash = 0.0;         // 亮一下：0 到 1
uniform float ghost = 0.0;         // 还没亮起来的那部分透出一点虚影（0 到 1）
uniform float alpha = 1.0;         // 整张剪影有多实。这个着色器自己算最终的颜色，节点的 modulate 管不到它，要淡只能调这里

void fragment() {
	vec3 displacement = texture(texture_flow_map, UV / wobble_size + vec2(float(int(TIME * 8.0) % 10) / 10.0)).xyz;
	vec2 pos = UV + displacement.xy * 0.02 * wobble;
	vec4 tex = texture(texture_albedo, pos);
	float lit = 1.0;
	if (mode == 1) {
		float d = distance(UV, origin);
		float r = progress * (1.0 + soft);
		lit = 1.0 - smoothstep(r - soft, r, d);
	} else if (mode == 2) {
		float n = texture(texture_flow_map, UV * 2.0 + vec2(0.37, 0.11)).x;
		float n2 = texture(texture_flow_map, UV * 6.0).y;
		float v = n * 0.65 + n2 * 0.35;
		lit = 1.0 - smoothstep(progress - soft, progress + soft * 0.3, v);
	}
	float a = tex.a * max(lit, ghost * 0.22);
	vec3 rgb = mix(tex.rgb * color, vec3(1.0, 0.98, 0.9), clamp(flash, 0.0, 1.0));
	COLOR = vec4(rgb, a * alpha);
}
