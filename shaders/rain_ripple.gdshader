shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 雨滴落点涟漪：按世界坐标切网格，每格随机相位生成扩散圆环。
// 铺在马路 / 人行道 / 屋顶的水平面上，深度写入关闭、加色混合，
// 不会和地面标线、光池打架。

uniform float cell_size = 0.5;
uniform float ring_speed = 0.7;      // 每秒循环次数
uniform float ring_width = 0.018;
uniform float max_radius = 0.2;
uniform float strength = 0.4;
uniform vec4 tint : source_color = vec4(0.62, 0.78, 1.0, 1.0);
// 干燥区：雨棚投影下的地面不产生涟漪
uniform vec2 dry_min = vec2(9999.0, 9999.0);
uniform vec2 dry_max = vec2(9999.0, 9999.0);

varying vec3 world_pos;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	if (world_pos.x > dry_min.x && world_pos.x < dry_max.x && world_pos.z > dry_min.y && world_pos.z < dry_max.y) {
		discard;
	}

	vec2 g = world_pos.xz / cell_size;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;

	// 每格一个随机圆心，避免整齐的格子感
	vec2 jitter = vec2(hash21(id + 3.1), hash21(id + 17.7)) - 0.5;
	float d = length(f - jitter * 0.62);

	float phase = fract(TIME * ring_speed * (0.85 + hash21(id + 41.7) * 0.3) + hash21(id + 91.3));
	float r = phase * max_radius;

	// 主环 + 拖后的小环
	float ring = smoothstep(ring_width, 0.0, abs(d - r));
	float r2 = max(0.0, r - 0.075);
	float ring2 = smoothstep(ring_width * 0.75, 0.0, abs(d - r2)) * step(0.075, r);
	// 落点瞬间的中心微亮
	float splash = smoothstep(0.12, 0.0, phase) * smoothstep(0.028, 0.0, d);

	float fade = pow(1.0 - phase, 1.35);
	float a = (ring + ring2 * 0.5 + splash * 0.22) * fade;

	ALBEDO = tint.rgb;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
