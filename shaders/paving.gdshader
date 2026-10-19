shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// 人行道砖：世界坐标网格缝隙 + 细微斑驳 + 三渲二分层

uniform vec4 base_color : source_color = vec4(0.56, 0.57, 0.60, 1.0);
uniform vec4 line_color : source_color = vec4(0.30, 0.32, 0.37, 1.0);
uniform float tile_size = 0.9;
uniform float line_width = 0.012;
uniform float mottle = 0.06;
uniform float shade_floor : hint_range(0.0, 1.0) = 0.55;
uniform float band_edge : hint_range(-1.0, 1.0) = 0.02;
uniform float band_soft : hint_range(0.001, 0.5) = 0.05;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.22;
uniform vec3 rim_color : source_color = vec3(0.55, 0.7, 1.0);
uniform float rim_strength = 0.14;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = wpos.xz / tile_size;
	vec2 cell = fract(uv);
	vec2 d2 = min(cell, 1.0 - cell);
	float d = min(d2.x, d2.y) * tile_size;
	float line = 1.0 - smoothstep(line_width * 0.5, line_width, d);

	float n = hash(floor(uv)) * mottle + hash(floor(uv * 0.27)) * mottle * 0.6;
	vec3 col = mix(base_color.rgb * (1.0 + n), line_color.rgb, line);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.5);
	EMISSION = rim_color * rim * rim_strength;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float wrapped = ndl + light_wrap * (1.0 - abs(ndl));
	float lit = smoothstep(band_edge - band_soft, band_edge + band_soft, wrapped);
	float amt = mix(shade_floor, 1.0, lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * amt * 0.318309886;
}
