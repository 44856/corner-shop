shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// 车灯光束：锥体（空气里的光柱）与地面光池（湿地上的一块亮斑）共用。
//
// 加色混合 + 不写深度：只「叠亮」，不和雨丝、涟漪抢排序；
// 深度测试照常开着，所以车体、地面、墙会正常挡住光束 ——
// 光柱落到地上就断，不会穿进地里继续亮。
//
// 台面裁剪：和 toon / outline / glow 同一组参数。车是从底座外面开进来的，
// 光束不裁就会在底座外面的空气里亮着，像两盏悬空的探照灯。

uniform vec4 beam_color : source_color = vec4(1.0, 0.9, 0.72, 1.0);
uniform float strength = 1.2;

// 锥体模式
uniform float length = 8.5;
uniform float radial_power = 1.7;
uniform float end_fade = 0.45;

// 光池模式：平面局部半尺寸（x = 横向，y = 沿光轴）
uniform bool pool = false;
uniform vec2 pool_half = vec2(1.5, 2.8);

uniform bool clip_on = false;
uniform vec3 clip_min = vec3(-5.6, -2.0, -5.6);
uniform vec3 clip_max = vec3(5.6, 8.0, 5.6);

varying vec3 v_world;
varying vec3 v_local;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
}

void fragment() {
	if (clip_on && (any(lessThan(v_world, clip_min)) || any(greaterThan(v_world, clip_max)))) {
		discard;
	}

	float a;
	if (pool) {
		// 椭圆光斑：中心最亮，边缘二次衰减；靠近车头那一侧更亮
		vec2 q = vec2(v_local.x / max(pool_half.x, 0.001),
				v_local.z / max(pool_half.y, 0.001));
		float d = length(q);
		a = pow(1.0 - smoothstep(0.0, 1.0, d), 2.0);
		a *= mix(1.0, 0.45, smoothstep(-0.7, 1.0, q.x));
	} else {
		// 锥体：沿 −Z 铺开，t = 0 在灯面、t = 1 在远端
		float t = clamp(-v_local.z / max(length, 0.001), 0.0, 1.0);
		// 正对镜头的那一侧最厚（N·V ≈ 1），轮廓边缘最薄（N·V ≈ 0）。
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float radial = pow(clamp(facing, 0.0, 1.0), radial_power);
		// 正对着光轴看时锥壁全是掠射角，留一点底光，否则整束光会「消失」
		radial = radial * 0.95 + 0.04;
		// 灯口处快速起亮，然后一路衰减到 0：光柱的远端本来就该化在雨里，
		// 顺带把「台面边缘一刀切」藏在透明度最低的地方
		float along = smoothstep(0.0, 0.04, t) * pow(1.0 - t, 1.2);
		a = radial * along;
	}

	ALBEDO = beam_color.rgb * strength;
	ALPHA = a;
}
