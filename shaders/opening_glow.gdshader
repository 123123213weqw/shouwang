shader_type canvas_item;
render_mode blend_add, unshaded;
// 一团光：中间亮、往外柔下去。叠在别的东西上面用（只加不减）
uniform vec3 color: source_color = vec3(1.0);
uniform float strength = 1.0;
uniform float falloff = 2.2;       // 越大光收得越紧

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = pow(max(0.0, 1.0 - d), falloff) * strength;
	COLOR = vec4(color * a, a);
}
