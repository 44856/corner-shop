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

// 台面裁剪：世界坐标超出台面范围的部分直接 discard。
// 给「从场外开进来」的东西用（货车），否则半截车身会浮在微缩底座外面。
// 默认关闭，其余材质完全不受影响；需要逐材质独立参数，
// 所以挂了裁剪的材质必须用 kit.toon_clipped() 生成（不走材质缓存）。
uniform bool clip_on = false;
uniform vec3 clip_min = vec3(-5.6, -2.0, -5.6);
uniform vec3 clip_max = vec3(5.6, 8.0, 5.6);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clip_on && (any(lessThan(v_world, clip_min)) || any(greaterThan(v_world, clip_max)))) {
		discard;
	}

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
