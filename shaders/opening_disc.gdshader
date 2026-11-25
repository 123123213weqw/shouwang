shader_type canvas_item;
// 圆点或者圆环（普通的叠加方式，深色也画得出来）：radius 是环的半径（0 中心，1 边缘），width 是环的粗细
uniform vec3 color: source_color = vec3(1.0);
uniform float radius = 0.0;
uniform float width = 1.0;
uniform float strength = 1.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float ring = 1.0 - smoothstep(0.0, width, abs(d - radius));
	COLOR = vec4(color, ring * strength);
}
