shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// 湿地面上的柔光池 / 霓虹反光（加色混合，边缘柔和衰减）

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.6, 1.0);
uniform float strength = 0.3;
uniform float softness = 0.6;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	ALBEDO = glow_color.rgb * strength;
	ALPHA = a * a;
}
