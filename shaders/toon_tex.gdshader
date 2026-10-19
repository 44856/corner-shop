shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// 带贴图的三渲二（角色专用）
// 和 toon.gdshader 的区别：ALBEDO 来自贴图而不是纯色 uniform，
// 这样 VRoid 导出的脸 / 衣服 / 头发贴图能保住。
// 分层参数比建筑更柔和（shade_floor 更高、wrap 更大），避免人脸出现硬切边。

uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(1.0);

uniform float shade_floor : hint_range(0.0, 1.0) = 0.58;
uniform float band_edge : hint_range(-1.0, 1.0) = 0.02;
uniform float band_soft : hint_range(0.001, 0.5) = 0.07;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.38;

uniform vec3 rim_color : source_color = vec3(0.55, 0.7, 1.0);
uniform float rim_strength = 0.14;
uniform float rim_power = 3.5;

// 头发 / 睫毛 / 眉毛是镂空的，靠 alpha 剪裁
uniform float alpha_cutoff = 0.5;
uniform bool use_alpha_scissor = true;


void fragment() {
	vec4 c = texture(base_tex, UV) * base_color;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	if (use_alpha_scissor) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	}

	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color * rim * rim_strength;
}


void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float wrapped = ndl + light_wrap * (1.0 - abs(ndl));
	float lit = smoothstep(band_edge - band_soft, band_edge + band_soft, wrapped);
	float amt = mix(shade_floor, 1.0, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * amt * 0.318309886;
}
