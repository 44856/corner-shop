shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx;

// 玻璃：轻度染色 + 边缘反光

uniform vec4 tint : source_color = vec4(0.55, 0.7, 0.85, 0.16);
uniform float edge_strength = 0.2;
uniform vec3 edge_color : source_color = vec3(0.55, 0.72, 1.0);

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	EMISSION = edge_color * f * edge_strength;
}
