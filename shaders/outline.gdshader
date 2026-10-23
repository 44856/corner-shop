shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// 反向外壳描边

uniform vec4 line_color : source_color = vec4(0.045, 0.05, 0.075, 1.0);
uniform float thickness = 0.009;

// 台面裁剪：必须和 toon.gdshader 用同一组 clip_* 参数，
// 否则车身被裁掉了、描边外壳还留在那儿，等于给空气描了一圈边。
uniform bool clip_on = false;
uniform vec3 clip_min = vec3(-5.6, -2.0, -5.6);
uniform vec3 clip_max = vec3(5.6, 8.0, 5.6);

varying vec3 v_world;

void vertex() {
	VERTEX += normalize(NORMAL) * thickness;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clip_on && (any(lessThan(v_world, clip_min)) || any(greaterThan(v_world, clip_max)))) {
		discard;
	}
	ALBEDO = line_color.rgb;
}
