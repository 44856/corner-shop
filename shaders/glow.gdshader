shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// 自发光面板（招牌 / 灯箱 / 霓虹），颜色可超过 1 触发辉光

uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength = 1.6;
uniform float band_scan = 0.0;

void fragment() {
	vec3 c = glow_color.rgb * strength;
	if (band_scan > 0.001) {
		float s = sin(UV.y * 220.0) * 0.5 + 0.5;
		c *= 1.0 - band_scan * s;
	}
	ALBEDO = c;
}
