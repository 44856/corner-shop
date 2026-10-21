shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// 柔光球：灯头光晕 / 贩卖机溢光 / 雨雾

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float power = 2.2;
uniform float strength = 0.45;

// 台面裁剪：货车灯头光晕会跟着车从底座外面进来，不裁就是一盏悬空的灯
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
	float f = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = glow_color.rgb * strength;
	ALPHA = f;
}
