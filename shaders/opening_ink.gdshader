shader_type canvas_item;
// 一滴在纸上化开的墨：从 origin 往外铺，progress 越大铺得越开，边缘是不规则的、里面深浅不匀。
//
// 噪声不用贴图，用几个正弦叠出来的起伏（解析的）：贴图的噪声铺满全屏不管怎么调都是一层细纤维，
// 看着像长了毛；解析的起伏是光滑的，边缘才像墨洇进纸里。
uniform vec3 color: source_color = vec3(0.02, 0.05, 0.05);
uniform float progress = 0.0;      // 0 几乎没有墨，1.5 铺满全屏
uniform float soft = 0.08;         // 边缘过渡的宽度：小一点边就清楚（纸吸墨是"糊一点但清楚"，不是一团雾）
uniform vec2 origin = vec2(0.5, 0.45);
uniform float aspect = 1.6;        // 画面的宽高比

// 连续的不规则起伏：不用角度（角度在负半轴上有接缝，会出现一条笔直的切线），
// 只对坐标做——两个方向不同的正弦互相调制，叠出来就歪了，而且处处连续
float lump(vec2 q) {
	float a = sin(dot(q, vec2(2.7, 1.4)) + sin(dot(q, vec2(-1.3, 2.9)) + 0.6));
	float b = sin(dot(q, vec2(3.9, -2.2)) + sin(dot(q, vec2(2.1, 1.7)) + 2.4));
	return (a * 0.55 + b * 0.45) * 0.5 + 0.5;
}

// 里面深浅不匀（低频，光滑）
float body(vec2 q) {
	float a = sin(q.x * 1.9 + 0.4);
	float b = sin(q.y * 2.3 - 1.1);
	float c = sin((q.x + q.y) * 1.1 + 2.6);
	return (a * 0.4 + b * 0.35 + c * 0.25) * 0.5 + 0.5;
}

void fragment() {
	vec2 p = UV;
	vec2 q = (p - origin) * vec2(aspect, 1.0);
	vec2 far = vec2(max(origin.x, 1.0 - origin.x) * aspect, max(origin.y, 1.0 - origin.y));
	float r = length(q) / max(length(far), 0.001);
	// 边的不规则：同一圈上有的地方先化开、有的地方慢
	float v = r * (1.0 + (lump(q * 1.25) - 0.5) * 0.40) + (body(q) - 0.5) * 0.05;
	float a = 1.0 - smoothstep(progress - soft, progress + soft * 0.6, v);
	// 墨心实一些、边上再淡一点
	a *= 0.88 + 0.12 * (1.0 - r);
	COLOR = vec4(color, clamp(a, 0.0, 1.0));
}
