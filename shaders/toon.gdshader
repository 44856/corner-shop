shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// 三渲二主材质：硬边双色分层 + 冷色边缘光

uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.85, 1.0);
uniform float shade_floor : hint_range(0.0, 1.0) = 0.35;
uniform float band_edge : hint_range(-1.0, 1.0) = 0.02;
uniform float band_soft : hint_range(0.001, 0.5) = 0.05;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.22;
uniform vec3 rim_color : source_color = vec3(0.55, 0.7, 1.0);
uniform float rim_strength = 0.16;
uniform float rim_power = 3.5;
uniform vec3 emit_color : source_color = vec3(0.0);
uniform float emit_strength = 0.0;
uniform float ao_boost = 0.0;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = emit_color * emit_strength + rim_color * rim * rim_strength;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float wrapped = ndl + light_wrap * (1.0 - abs(ndl));
	float lit = smoothstep(band_edge - band_soft, band_edge + band_soft, wrapped);
	float amt = mix(shade_floor, 1.0, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * amt * 0.318309886;
}
