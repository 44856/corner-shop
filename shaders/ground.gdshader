shader_type spatial;
render_mode diffuse_burley;
// 平原地面：土路铺满大地 → 城镇入口的方石铺装 → 大理石广场
//
// 这一版不再有草地。整片地形就是一个材质，按**世界坐标**（单位：米）计算：
//   1. 土面：夯土 + 碎石，铺满全场。这就是玩家脚下那块地的样子，一直延伸到雾里。
//   2. 主路：0 → road_z1 一条缓弧。比两侧压得更实、更干净、带两道车辙，
//      所以「路」是看得出来的，但它和两侧是同一种土，不是贴上去的一条带子。
//   3. 方石铺装：z 到 300m 之后路面让位给铺装，边缘用噪声打散。
//   4. 大理石：进镇越深权重越高（marble_z0 → marble_z1 长渐变），
//      侧向再收口，形成「土路 → 石铺 → 大理石广场」的连续过渡。
//
// 为什么不像素级叠面片：路要铺到 500m 外，那个距离上深度精度只有几厘米，
// 叠面必然 z-fighting；而且贴面片会有一条硬边，没有土咬进石缝的过渡。
//
// 为什么按米采样而不是 UV：玩法地面 1200m、远景地面 3000m 共用这一个材质，
// 同一个 0~1 UV 在两者上的实际尺寸差 2.5 倍，接缝处会突然换一种噪点密度。

// ---- 土面（整片大地的基底）
// 亮度定在 0.35~0.55 这一档：外部日光 + filmic tonemap + 饱和 1.22 下，
// 再亮一点就会「白得像盐碱地」（第一版给到 0.70 的白斑就是这个下场）。
// 色相往灰褐收，别太黄 —— 太黄就是沙滩，不是被人踩了几百年的土路
uniform vec4 dirt_light : source_color = vec4(0.412, 0.362, 0.288, 1.0);
uniform vec4 dirt_dark : source_color = vec4(0.290, 0.244, 0.190, 1.0);
uniform vec4 grit_color : source_color = vec4(0.470, 0.438, 0.378, 1.0);

// ---- 草地（出生点一侧）
// 地形分两区：出生点附近是草地，往城镇方向慢慢变成压实的土面（平地），
// 道路和铺装盖在两者之上，不受影响。
//
// 亮度刻意和土面对齐（0.26~0.58 对土面的 0.24~0.41）：
// 两边的平均亮度接近，过渡带才不会出现一条「明暗台阶」，
// 只会看到颜色在换。
uniform vec4 grass_light : source_color = vec4(0.420, 0.580, 0.300, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.258, 0.392, 0.198, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.520, 0.540, 0.280, 1.0);
// 草到哪儿结束（米），以及过渡带宽度（米）
uniform float grass_z1 = 120.0;
uniform float grass_fade = 45.0;

// ---- 主路
uniform float road_half_width = 3.2;
uniform float road_z1 = 300.0;
uniform float road_bend = 9.0;
// 铺装从这里开始，土路在这之前淡出，避免路面颜色从石板缝里透出来
uniform float road_end_z = 300.0;

// ---- 方石铺装（城镇地面）
// 偏暖的灰褐：石头被人踩了很久，脏得发褐。
// 它必须比大理石明显暗一档，否则「渐变成大理石」这件事在画面上不存在
// （上一版两个只差 5%，从空中看整片是一块均匀的灰）
uniform vec4 flag_a : source_color = vec4(0.372, 0.356, 0.332, 1.0);
uniform vec4 flag_b : source_color = vec4(0.288, 0.276, 0.256, 1.0);
uniform float flag_tile_m = 1.15;
uniform vec2 paved_center = vec2(0.0, 430.0);
uniform vec2 paved_half = vec2(150.0, 130.0);

// ---- 大理石
// 关键是别给太高：albedo 0.9 的石头在户外直射光下必然纯白一片（第一版就是这样），
// 真实的打磨大理石在晴天也就 0.5 上下的反射率。
// 色相走暖白而不是冷白 —— 饱和度被调到 1.22，冷白会被推成「结冰的湖面」
uniform vec4 marble_a : source_color = vec4(0.520, 0.510, 0.492, 1.0);
uniform vec4 marble_b : source_color = vec4(0.424, 0.416, 0.400, 1.0);
uniform float marble_tile_m = 1.75;
uniform float marble_z0 = 340.0;
uniform float marble_z1 = 430.0;
uniform float marble_half_w = 138.0;

// 1 = 会铺装（玩法地面）；0 = 只铺土（远景地面，那里不需要算石板）
uniform float paving_amount = 1.0;

varying vec3 wpos;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


float fbm(vec2 p) {
	return vnoise(p) * 0.62 + vnoise(p * 2.7 + 13.1) * 0.28 + vnoise(p * 6.1 - 7.3) * 0.10;
}


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 p = wpos.xz;

	// ================= 1. 土面 =================
	// big 管大块的干湿差，mid 管 1~3m 的斑驳。
	// mid 的频率不能再低了：0.85 时这些斑在中景透视下会被拉成一道道横纹，
	// 远看像沙丘，近看像轮胎印
	float big = fbm(p * 0.055);
	float mid = fbm(p * 1.45);

	vec3 dirt = mix(dirt_dark.rgb, dirt_light.rgb, big);
	dirt *= 0.91 + 0.15 * mid;

	// 碎石：亮点（小石子反光）+ 暗点（坑）都来一点，纯色会像泥塑。
	// 第一版阈值 0.66、权重 0.26 太狠，整片地像撒了碎纸屑，现在压低收细
	float grain = vnoise(p * 6.0);
	dirt = mix(dirt, grit_color.rgb, smoothstep(0.76, 0.97, grain) * 0.15);
	dirt *= 1.0 - smoothstep(0.80, 0.97, vnoise(p * 17.0)) * 0.16;

	// ================= 1b. 草地 =================
	// 出生点一侧铺草，往 +Z（城镇方向）渐渐变成压实的土面。
	// 边界用低频噪声扰动 ±15m，否则会在地面上看到一条笔直的换色线。
	float gz = wpos.z + (fbm(p * 0.021 + 9.0) - 0.5) * 30.0;
	float grass_mask = 1.0 - smoothstep(grass_z1 - grass_fade, grass_z1, gz);

	// 草的层次：大块深浅 + 1~2m 的斑驳 + 少量枯黄
	float g_big = fbm(p * 0.075 + 17.0);
	float g_mid = fbm(p * 2.1 - 5.0);
	vec3 grass = mix(grass_dark.rgb, grass_light.rgb, g_big);
	grass *= 0.86 + 0.28 * g_mid;
	grass = mix(grass, grass_dry.rgb, smoothstep(0.70, 0.94, fbm(p * 0.33 + 31.0)) * 0.20);
	// 近处几米的细碎草尖：一点点高频提亮，没有它近看是一块塑料绿
	grass *= 1.0 + smoothstep(0.72, 0.98, vnoise(p * 9.0)) * 0.10;

	// 土层与草地按遮罩混合，再让道路盖在最上面
	vec3 base = mix(dirt, grass, grass_mask);

	// ================= 2. 主路 =================
	// 中心线：0 → road_z1 一段缓弧，终点回到 x = 0（城镇就在正前方）；
	// 之后 t 夹到 1，sin(PI) = 0，路笔直继续延伸
	float t = clamp(wpos.z / road_z1, 0.0, 1.0);
	float center = road_bend * sin(PI * t);

	// 边缘抖动：±0.75m 的低频扰动，看起来是走出来的而不是画出来的
	float wob = (fbm(p * 0.085) - 0.5) * 1.5;
	float d = abs(wpos.x - center) - wob;

	float road = 1.0 - smoothstep(road_half_width - 1.3, road_half_width, d);
	road *= 1.0 - smoothstep(road_end_z - 14.0, road_end_z + 4.0, wpos.z);

	// 路面 = 土色 + 踩实（更亮更干净）+ 两道车辙 + 细砂
	vec3 road_col = mix(dirt_dark.rgb, dirt_light.rgb, big * 0.75 + mid * 0.25);
	road_col = mix(road_col, dirt_light.rgb * 1.10, 0.40);
	float rut = smoothstep(0.34, 0.02, abs(d - road_half_width * 0.44));
	road_col *= 1.0 - rut * 0.16;
	road_col = mix(road_col, road_col * 0.90, smoothstep(0.72, 0.96, vnoise(p * 26.0)) * 0.22);

	vec3 col = mix(base, road_col, road);

	// 路肩：土被反复踩到边上堆起来，压出一道暗边。
	// 不加这道暗边，土路和两侧是同一种土，二十米外就完全分不出来了
	float shoulder = smoothstep(road_half_width * 0.78, road_half_width * 1.0, d)
		* (1.0 - smoothstep(road_half_width * 1.0, road_half_width * 1.30, d));
	col *= 1.0 - shoulder * 0.14;

	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	// 铺装只占画面的很小一部分，远景地面又铺满半个屏幕，
	// 所以先用一个便宜的矩形判定把它挡在外面，省掉后面 6 次 fbm。
	// （Godot 的 fragment 不允许早退，只能整块包起来）
	if (paving_amount > 0.5) {
		// ================= 3. 铺装范围 =================
		// 矩形 SDF，<0 在内部。边界加 ±3.5m 噪声，否则会看到一条笔直的几何线
		vec2 pq = abs(p - paved_center) - paved_half;
		float sd = max(pq.x, pq.y) + (fbm(p * 0.11 + 5.0) - 0.5) * 7.0;
		float paved = (1.0 - smoothstep(-2.5, 2.5, sd)) * paving_amount;

		if (paved > 0.002) {
			// ================= 4. 方石铺装 =================
			vec2 ft = p / flag_tile_m;
			vec2 fi = floor(ft);
			vec2 ff = fract(ft);
			float fseam = min(min(ff.x, 1.0 - ff.x), min(ff.y, 1.0 - ff.y));
			// 远处一块砖只剩几个像素时，固定宽度的缝会闪成一片噪点；
			// 用 fwidth 按屏幕导数放宽，等于给缝做了一次抗锯齿
			float fw = max(fwidth(fseam), 0.008);
			float fjoint = smoothstep(fw * 0.5, fw * 3.0, fseam);
			vec3 flag = mix(flag_b.rgb, flag_a.rgb, hash12(fi));
			flag *= 0.94 + 0.12 * hash12(fi + 7.0);       // 每块砖自己的深浅
			flag *= 0.94 + 0.12 * vnoise(p * 2.4);        // 石面本身的斑驳
			// 缝的「压暗量」必须跟着 fwidth 衰减：一块砖在屏幕上只剩几像素时，
			// fjoint 会一路铺满整块砖，这时再乘 0.58 就等于给整片地盖了一层灰罩，
			// 远处看起来像沥青（第一版就是这样，越远越黑）
			float fdark = 0.58 + 0.42 * smoothstep(0.02, 0.10, fw);
			flag = mix(flag * fdark, flag, fjoint);

			// ================= 5. 大理石 =================
			// 进镇越深越是大理石：沿 z 一条 90m 的长渐变（这就是「渐变」本身）。
			// 侧向再接一个收口，让广场两边留一圈方石当路缘
			float edge = 1.0 - smoothstep(marble_half_w - 10.0, marble_half_w,
				abs(p.x) + (fbm(p * 0.16 + 19.0) - 0.5) * 14.0);
			float ramp = smoothstep(marble_z0, marble_z1,
				p.y + (fbm(p * 0.05 + 41.0) - 0.5) * 16.0);
			float marble = paved * edge * ramp;

			vec2 mt = p / marble_tile_m;
			vec2 mi = floor(mt);
			vec2 mf = fract(mt);
			float mseam = min(min(mf.x, 1.0 - mf.x), min(mf.y, 1.0 - mf.y));
			float mw = max(fwidth(mseam), 0.0035);
			float mjoint = smoothstep(mw * 0.4, mw * 2.0, mseam);   // 大理石板缝比方石细

			vec3 mb = mix(marble_b.rgb, marble_a.rgb, hash12(mi + 23.0));
			mb *= 0.93 + 0.12 * hash12(mi + 5.0);         // 每块板自己的色差

			// 污渍：几十米尺度的一层。没有它，200m 见方的石板就是一张均匀的白纸
			mb *= 0.88 + 0.24 * fbm(p * 0.035 + 77.0);

			// 石纹：用低频噪声扭曲一层中频噪声，得到「云絮」；
			// 直接叠 noise 会变成均匀麻点，不像石头
			float w = fbm(p * 0.16);
			float vein = fbm(p * 0.62 + vec2(w * 2.6, -w * 2.0));
			mb *= 0.84 + 0.30 * vein;
			mb = mix(mb, marble_a.rgb * 1.14, smoothstep(0.56, 0.72, vein) * 0.55);   // 亮脉
			float mdark = 0.62 + 0.38 * smoothstep(0.01, 0.05, mw);
			mb = mix(mb * mdark, mb, mjoint);             // 板缝（同样随距离衰减）

			vec3 pave_col = mix(flag, mb, marble);
			col = mix(col, pave_col, paved);

			// 大理石抛光，方石和土面哑光。SPECULAR 靠 render_mode 开了才有意义，
			// 所以这个 shader 不能用 specular_disabled。
			// 但别给太高：镜头贴地看时，半光的石板反射的是整片白天空，
			// ROUGHNESS 0.2 / SPECULAR 0.5 会把石板直接变成白瓷砖
			ROUGHNESS = mix(1.0, 0.34, marble);
			SPECULAR = mix(0.0, 0.22, marble);
		}
	}

	ALBEDO = col;
}
