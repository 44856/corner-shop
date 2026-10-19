shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// 反向外壳描边

uniform vec4 line_color : source_color = vec4(0.045, 0.05, 0.075, 1.0);
uniform float thickness = 0.009;

void vertex() {
	VERTEX += normalize(NORMAL) * thickness;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
