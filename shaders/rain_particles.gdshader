shader_type particles;

// 雨滴：自定义下落。
// 关键点：每帧按 xz 采样「该列最高的可接雨表面」，落到表面就回收重发，
// 因此雨不会穿过雨棚（平层）、屋面或人行道继续往下掉。
// 雨幕的范围被限制在底座顶面之内，不会漏到平台外面去。
//
// 表面高度表（世界坐标，xz 用 vec2(x, z) 表示）：
//   底座外      -8.0  （兜底：万一飘出去就掉出场景）
//   马路         0.0
//   人行道       0.16
//   后巷地面     0.19
//   便利店雨棚   2.66
//   便利店屋面   3.71

uniform float area_half = 5.5;    // 雨幕半宽：底座顶面 5.6，留 0.1 内缩
uniform float top_y = 10.4;       // 循环起点高度
uniform float speed_min = 11.5;
uniform float speed_max = 16.5;
uniform vec3 wind = vec3(0.16, 0.0, 0.06);   // 轻微斜雨
uniform float hit_epsilon = 0.012;


float surface_height(vec2 xz) {
	float h = -8.0;
	if (abs(xz.x) < 5.6 && abs(xz.y) < 5.6) {
		h = 0.0;
	}
	// 人行道（L 形地块）
	if (xz.x > -1.9 && xz.y < 1.9) {
		h = 0.16;
	}
	// 后巷地面
	if (xz.x > 3.1 && xz.y < -0.9) {
		h = 0.19;
	}
	// 便利店雨棚：雨停在这块平层上
	if (xz.x > -1.76 && xz.x < 3.16 && xz.y > -0.96 && xz.y < 0.2) {
		h = 2.66;
	}
	// 便利店屋面
	if (xz.x > -1.77 && xz.x < 3.17 && xz.y > -5.57 && xz.y < -0.83) {
		h = 3.71;
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


// 在底座范围内取一列，从顶部随机高度重新落下
vec3 respawn_pos(in uint base) {
	float x = (rand_from_seed(hash_uint(base + uint(11))) * 2.0 - 1.0) * area_half;
	float z = (rand_from_seed(hash_uint(base + uint(53))) * 2.0 - 1.0) * area_half;
	float y = top_y - rand_from_seed(hash_uint(base + uint(97))) * 1.4;
	return vec3(x, y, z);
}


void start() {
	uint s1 = hash_uint(NUMBER + uint(1) + RANDOM_SEED);
	uint s2 = hash_uint(NUMBER + uint(37) + RANDOM_SEED);
	uint s3 = hash_uint(NUMBER + uint(73) + RANDOM_SEED);
	uint s4 = hash_uint(NUMBER + uint(151) + RANDOM_SEED);

	vec2 xz = (vec2(rand_from_seed(s1), rand_from_seed(s2)) * 2.0 - 1.0) * area_half;
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

	// 触面，或随风飘出底座边界：都回到顶上的底座范围内重来
	bool hit_surface = p.y <= surface_height(p.xz) + hit_epsilon;
	bool out_of_bounds = abs(p.x) > area_half || abs(p.z) > area_half;
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
