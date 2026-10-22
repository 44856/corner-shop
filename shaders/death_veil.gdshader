shader_type canvas_item;

// 死亡面纱：把已经渲染好的画面做去色、块状撕裂、噪点与暗角。
//
// 为什么用 screen texture 而不是给场景加后处理：工程里没有 post-process 管线，
// 为一个只出现 30 秒的演出去改 WorldEnvironment 不划算；这层 CanvasLayer
// 覆盖在 HUD 下面、LetterTransition 上面，算得少、删得掉，也不影响别的场景。
//
// 块状撕裂只偏移采样坐标，不动 UI：HUD 已经被这层盖住，
// 所以「UI 碎裂」读起来是整幅画面在碎，而不是某个控件在动。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float alpha : hint_range(0.0, 1.0) = 0.0;
uniform float desat : hint_range(0.0, 1.0) = 0.0;
uniform float noise_amount : hint_range(0.0, 0.35) = 0.0;
uniform float block_amount : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 2.0) = 0.0;
uniform float blackout : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint_color : source_color = vec3(1.0, 0.96, 0.90);
uniform float time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// 块尺寸固定，偏移量随 block_amount 长大；同一块内的偏移一致，
	// 所以看起来是「画面裂成小方块」，而不是逐像素的电视雪花。
	vec2 cells = vec2(26.0, 15.0);
	vec2 cell = floor(SCREEN_UV * cells);
	float r = hash(cell + floor(time * 9.0));
	vec2 jitter = (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.018 * block_amount;
	if (r < block_amount * 0.30) {
		jitter *= 3.2;
	}
	vec2 uv = clamp(SCREEN_UV + jitter, vec2(0.001), vec2(0.999));
	vec3 col = texture(screen_texture, uv).rgb;

	// 色相剥离：先退到亮度，再往暖灰上压一点。纯灰度像黑白电视，
	// 带一点 tint 才像「血从画面里退出去」。
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * tint_color, desat);

	float grain = hash(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(time * 37.0, time * 61.0));
	col += (grain - 0.5) * noise_amount;

	vec2 d = SCREEN_UV - vec2(0.5);
	float v = smoothstep(0.72, 0.10, length(d) * 1.45);
	col *= mix(1.0, v, clamp(vignette, 0.0, 1.0));
	col *= 1.0 - blackout;

	COLOR = vec4(max(col, vec3(0.0)), alpha);
}
