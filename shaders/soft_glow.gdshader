shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// 柔光球：灯头光晕 / 贩卖机溢光 / 雨雾

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float power = 2.2;
uniform float strength = 0.45;

void fragment() {
	float f = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	ALBEDO = glow_color.rgb * strength;
	ALPHA = f;
}
