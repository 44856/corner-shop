shader_type particles;

// 雨滴：自定义下落。
// 关键点：每帧按 xz 采样「该列最高的可接雨表面」，落到表面就回收重发，
// 因此雨不会穿过雨棚（平层）、屋面或人行道继续往下掉。
// 雨幕的范围被限制在底座顶面之内，不会漏到平台外面去。
//
// 两种配置：
//   旧场景（cover_count == 0 且 rect_half.x <= 0）走下面写死的表面表，
//   参数与视觉保持原样；新街区传 rect_center / rect_half 换矩形雨幕，
//   传 covers + cover_h 换通用表面表（最多 32 块）。
//
// 旧场景表面高度表（世界坐标，xz 用 vec2(x, z) 表示）：
//   底座外      -8.0  （兜底：万一飘出去就掉出场景）
//   马路         0.0
//   人行道       0.16
//   后巷地面     0.19
//   便利店雨棚   2.66
//   便利店屋面   3.71

uniform float area_half = 5.5;    // 旧方形雨幕半宽：底座顶面 5.6，留 0.1 内缩
uniform float top_y = 10.4;       // 循环起点高度
uniform vec2 rect_center = vec2(0.0);  // 矩形雨幕中心（xz）
uniform vec2 rect_half = vec2(0.0);    // > 0 时启用矩形雨幕
uniform int cover_count = 0;           // > 0 时使用 covers 通用表面表
uniform vec4 covers[32];               // x0, z0, x1, z1
uniform float cover_h[32];             // 对应顶面高度
uniform float speed_min = 11.5;
uniform float speed_max = 16.5;
uniform vec3 wind = vec3(0.16, 0.0, 0.06);   // 轻微斜雨
uniform float hit_epsilon = 0.012;


float surface_height(vec2 xz) {
	float h = -8.0;
	if (rect_half.x > 0.0) {
		if (abs(xz.x - rect_center.x) < rect_half.x && abs(xz.y - rect_center.y) < rect_half.y) {
			h = 0.0;
		}
	} else if (abs(xz.x) < 5.6 && abs(xz.y) < 5.6) {
		h = 0.0;
	}

	if (cover_count > 0) {
		for (int i = 0; i < 32; i++) {
			if (i >= cover_count) {
				break;
			}
			vec4 c = covers[i];
			if (xz.x > c.x && xz.x < c.z && xz.y > c.y && xz.y < c.w) {
				h = max(h, cover_h[i]);
			}
		}
	} else {
		// 人行道（L 形地块）
		if (xz.x > -1.9 && xz.y < 1.9) {
			h = 0.16;
		}
		// 后巷地面（店面东墙推到 4.30 之后，巷子只剩 4.30..5.36）
		if (xz.x > 4.3 && xz.y < -0.9) {
			h = 0.19;
		}
		// 便利店雨棚：雨停在这块平层上（跟着店面一起加宽到 4.36）
		if (xz.x > -1.76 && xz.x < 4.36 && xz.y > -0.96 && xz.y < 0.2) {
			h = 2.66;
		}
		// 便利店屋面
		if (xz.x > -1.77 && xz.x < 4.37 && xz.y > -5.57 && xz.y < -0.83) {
			h = 3.71;
		}
	}
	return h;
}


uint hash_uint(in uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}


float rand_from_seed(in uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	return float(s % 2147483647) / 2147483647.0;
}


vec2 rand_xz(in uint a, in uint b) {
	vec2 r = vec2(rand_from_seed(a), rand_from_seed(b)) * 2.0 - 1.0;
	if (rect_half.x > 0.0) {
		return rect_center + r * rect_half;
	}
	return r * area_half;
}


// 在雨幕范围内取一列，从顶部随机高度重新落下
vec3 respawn_pos(in uint base) {
	vec2 xz = rand_xz(hash_uint(base + uint(11)), hash_uint(base + uint(53)));
	float y = top_y - rand_from_seed(hash_uint(base + uint(97))) * 1.4;
	return vec3(xz.x, y, xz.y);
}


void start() {
	uint s1 = hash_uint(NUMBER + uint(1) + RANDOM_SEED);
	uint s2 = hash_uint(NUMBER + uint(37) + RANDOM_SEED);
	uint s3 = hash_uint(NUMBER + uint(73) + RANDOM_SEED);
	uint s4 = hash_uint(NUMBER + uint(151) + RANDOM_SEED);

	vec2 xz = rand_xz(s1, s2);
	float h = surface_height(xz);
	// 初始沿整段落程铺开，配合 preprocess 打开就是满屏雨
	float y = mix(h + 0.4, top_y, rand_from_seed(s3));

	TRANSFORM = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(xz.x, y, xz.y, 1.0)
	);
	// x: 速度系数  y: 雨丝长度系数
	CUSTOM = vec4(rand_from_seed(s4), rand_from_seed(hash_uint(s4 + uint(9))), 0.0, 0.0);
}


void process() {
	vec3 p = TRANSFORM[3].xyz;
	float sp = mix(speed_min, speed_max, CUSTOM.x);
	p += normalize(vec3(wind.x, -1.0, wind.z)) * sp * DELTA;

	// 触面，或随风飘出雨幕边界：都回到顶上的范围内重来
	bool hit_surface = p.y <= surface_height(p.xz) + hit_epsilon;
	bool out_of_bounds;
	if (rect_half.x > 0.0) {
		vec2 d = abs(p.xz - rect_center);
		out_of_bounds = d.x > rect_half.x || d.y > rect_half.y;
	} else {
		out_of_bounds = abs(p.x) > area_half || abs(p.z) > area_half;
	}
	if (hit_surface || out_of_bounds) {
		p = respawn_pos(NUMBER + INDEX + uint(TIME * 1373.0) + RANDOM_SEED);
	}

	TRANSFORM = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 0.82 + CUSTOM.y * 0.62, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(p, 1.0)
	);
}
