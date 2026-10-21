shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// 自发光面板（招牌 / 灯箱 / 霓虹），颜色可超过 1 触发辉光

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength = 1.6;
uniform float band_scan = 0.0;

// 台面裁剪：和 toon / outline 同一组参数。灯板也得裁，
// 否则车身被切掉了、尾灯还亮在台面外面，像一盏悬空的红灯。
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
	vec3 c = glow_color.rgb * strength;
	if (band_scan > 0.001) {
		float s = sin(UV.y * 220.0) * 0.5 + 0.5;
		c *= 1.0 - band_scan * s;
	}
	ALBEDO = c;
}
