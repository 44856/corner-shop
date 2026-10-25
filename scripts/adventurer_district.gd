extends RefCounted
## 冒险者区：L 形的商业角。
##
## 两排店咬在一个角上：
##   第一排沿贯城大街（面朝 −X），从城门一直排到十字路；
##   第二排沿十字路（面朝 +Z），从街角往东伸出去。
## 转角处两排接头，形成一个能逛的「L」。
##
## 位置关系：
##   贯城大街 |x| ≤ 9，十字路 |z − 465| ≤ 9；
##   第一排立面在 x = 10，进深 14（到 x = 24）；
##   第二排立面在 z = 456，进深 14（到 z = 442），x 从 24 到 60。
##   公会占 z 386~414，所以第一排中间断开让给它。
##
## 为什么店是「沿街一层皮」而不是散布在整个区里：
##   冒险者区的重点是「一条能逛的街」。玩家从城门进来，右手边一路是武具店、
##   防具店、药铺、铁匠铺，走到街角一拐，又是宿屋和马具店 —— 这条动线才立得住。
##
## 层高刻意比公会低（檐口 7.8 / 屋脊 9.8 对公会的 7.8 / 10.6）：
##   公会是这一区的地标，店面压它一头就变成两个地标，视线会乱。
##
## 实现：每间店都在**局部空间**里搭（立面在 x=0，往 +x 进深，z 居中），
## 再由一个带旋转的父节点摆到世界。这样同一份代码能出一排朝 −X、一排朝 +Z，
## 不用把每个坐标写两遍。

const K := preload("res://scripts/kit.gd")

# ---------------------------------------------------------------- 尺寸

## 第一排：临街立面所在的 x（街道半宽 9，再留 1m 做门前步道）
const X_FRONT := 10.0
## 进深（沿局部 +x）
const DEPTH := 14.0
## 第一排每间沿街的面宽
const PITCH := 16.0

## 一层层高 / 檐口 / 屋脊
const G0 := 4.4
const EAVE := 7.8
const RIDGE := 9.8
const WALL_T := 0.35

## 第一排：南段 4 间（z 308~372），北段 2 间（z 420~452）
const SOUTH_Z0 := 308.0
const SOUTH_COUNT := 4
const NORTH_Z0 := 420.0
const NORTH_COUNT := 2

## 第二排：沿十字路，立面在 z=456（街道南缘），往 −Z 进深
const CROSS_FRONT_Z := 456.0
const CROSS_X0 := 24.0
const CROSS_PITCH := 12.0
const CROSS_COUNT := 3

## 店招文案。前六间是第一排（沿街自南向北），后三间是第二排（自西向东）。
const SHOPS := [
	{"name": "武具店", "kind": "weapon", "wall": "#8a7a5e", "sign": "#2c3f56", "text": "#f0dfae"},
	{"name": "防具店", "kind": "armor", "wall": "#7d6b55", "sign": "#3a2b22", "text": "#e8cf9a"},
	{"name": "薬師屋", "kind": "potion", "wall": "#8f8570", "sign": "#243d33", "text": "#dceccb"},
	{"name": "鍛冶屋", "kind": "smith", "wall": "#6e6258", "sign": "#2a2622", "text": "#ffc98a"},
	{"name": "雑貨店", "kind": "goods", "wall": "#867a68", "sign": "#332a3f", "text": "#e3d5f0"},
	{"name": "酒場", "kind": "tavern", "wall": "#7a6050", "sign": "#4a2224", "text": "#ffd9a8"},
	{"name": "宿屋", "kind": "inn", "wall": "#6b6f7a", "sign": "#1f2a38", "text": "#ffe0a8"},
	{"name": "馬具屋", "kind": "harness", "wall": "#7b6752", "sign": "#33281c", "text": "#f0dcc0"},
	{"name": "古道具", "kind": "curio", "wall": "#6a6258", "sign": "#2b2431", "text": "#d8cff0"},
]


static func build(root: Node3D) -> void:
	var g := K.group(root, "AdventurerDistrict")
	_street_edge(g)
	_row(g, SOUTH_Z0, SOUTH_COUNT, 0)
	_row(g, NORTH_Z0, NORTH_COUNT, SOUTH_COUNT)
	_cross_row(g)
	_clutter(g)


## 门前步道：把街道和店面之间那一条压出来，免得店直接长在路面上
static func _street_edge(g: Node3D) -> void:
	var walk := K.paving(Color("#5a5a5e"), Color("#3a3a3e"), 1.2)
	K.box(g, Vector3(1.2, 0.12, 456.0 - 300.0),
		Vector3(X_FRONT - 0.6, 0.06, (300.0 + 456.0) * 0.5), walk, Vector3.ZERO, false)
	# 第二排前面的步道（沿十字路南缘）
	K.box(g, Vector3(60.0 - X_FRONT, 0.12, 1.2),
		Vector3((X_FRONT + 60.0) * 0.5, 0.06, CROSS_FRONT_Z - 0.6), walk, Vector3.ZERO, false)


## 第一排：面朝 −X（朝贯城大街）
static func _row(g: Node3D, z0: float, count: int, index_offset: int) -> void:
	for i in count:
		var idx := index_offset + i
		if idx >= SHOPS.size():
			return
		var cz := z0 + PITCH * (i + 0.5)
		_place(g, Vector3(X_FRONT, 0.0, cz), 0.0, SHOPS[idx], PITCH)


## 第二排：面朝 +Z（朝十字路）。绕 Y 转 +90° 后，局部 −x 变成世界 +Z。
static func _cross_row(g: Node3D) -> void:
	for i in CROSS_COUNT:
		var idx := SOUTH_COUNT + NORTH_COUNT + i
		if idx >= SHOPS.size():
			return
		var cx := CROSS_X0 + CROSS_PITCH * (i + 0.5)
		_place(g, Vector3(cx, 0.0, CROSS_FRONT_Z), PI * 0.5, SHOPS[idx], CROSS_PITCH)


static func _place(parent: Node3D, pos: Vector3, yaw: float, spec: Dictionary,
		width: float) -> void:
	var node := Node3D.new()
	node.name = "Shop_" + String(spec["name"])
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)
	_shop_local(node, spec, width)


# ---------------------------------------------------------------- 一间店

## 局部空间：立面在 x=0，往 +x 进深 DEPTH；沿 z 居中、宽 width。
static func _shop_local(g: Node3D, spec: Dictionary, width: float) -> void:
	var wall_mat := K.toon(Color(spec["wall"]), {"shade": 0.52, "rim": 0.12, "line": 0.010})
	var trim_mat := K.toon(Color(spec["wall"]).darkened(0.28),
		{"shade": 0.6, "rim": 0.1, "line": 0.008})
	var roof_mat := K.toon(Color("#4a4a4e"), {"shade": 0.58, "rim": 0.16, "line": 0.008})
	var half_w := width * 0.5 - 0.4      # 店与店之间留缝
	var cx := DEPTH * 0.5

	# ---- 墙体：四面分开砌，前墙留门洞，人才能真的走进去
	#
	# 原来是一整块实心盒子（省事、挡人），但那样店里就是实心的，
	# 只能从外面看皮。拆成墙之后多了 3 个碰撞体/间，换来能进门。
	var t := WALL_T
	var door_z := -1.6
	var door_hw := 1.3
	var door_h := 3.0

	var left_w: float = (door_z - door_hw) - (-half_w)
	var right_w: float = half_w - (door_z + door_hw)
	if left_w > 0.05:
		_solid(g, Vector3(t, EAVE, left_w),
			Vector3(-t * 0.5, EAVE * 0.5, -half_w + left_w * 0.5), wall_mat)
	if right_w > 0.05:
		_solid(g, Vector3(t, EAVE, right_w),
			Vector3(-t * 0.5, EAVE * 0.5, door_z + door_hw + right_w * 0.5), wall_mat)
	# 门楣
	_solid(g, Vector3(t, EAVE - door_h, door_hw * 2.0),
		Vector3(-t * 0.5, door_h + (EAVE - door_h) * 0.5, door_z), wall_mat)

	# 后墙 + 两侧墙
	_solid(g, Vector3(t, EAVE, half_w * 2.0),
		Vector3(DEPTH - t * 0.5, EAVE * 0.5, 0.0), wall_mat)
	for side in [-1.0, 1.0]:
		_solid(g, Vector3(DEPTH, EAVE, t),
			Vector3(cx, EAVE * 0.5, side * (half_w - t * 0.5)), wall_mat)

	# 地板（木，比外面高 12cm，像店铺的门槛）与天花板（= 二层楼板）
	_solid(g, Vector3(DEPTH, 0.12, half_w * 2.0), Vector3(cx, 0.06, 0.0),
		K.pbr(Color("#4a3a28"), 0.85, 0.0))
	_solid(g, Vector3(DEPTH, 0.16, half_w * 2.0), Vector3(cx, G0, 0.0), trim_mat)

	_interior_local(g, spec, width)

	# ---- 一层：门 + 橱窗（都开在 x=0 那一面）
	K.box(g, Vector3(0.12, 3.0, 2.2), Vector3(-0.05, 1.5, -1.6),
		K.toon(Color("#241d18"), {"shade": 0.7, "line": 0.006}), Vector3.ZERO, false)

	# 橱窗：玻璃 + 上下窗台
	K.box(g, Vector3(0.10, 2.2, half_w * 1.5), Vector3(-0.04, 2.3, 1.6),
		K.glass(Color(0.42, 0.52, 0.6, 0.22), 0.3), Vector3.ZERO, false)
	K.box(g, Vector3(0.26, 0.16, half_w * 1.6), Vector3(-0.08, 1.2, 1.6), trim_mat, Vector3.ZERO, false)
	K.box(g, Vector3(0.26, 0.16, half_w * 1.6), Vector3(-0.08, 3.42, 1.6), trim_mat, Vector3.ZERO, false)

	# ---- 雨棚：斜出去一块，给门面压出一道深色影
	var awning := K.toon(Color("#3d2a22"), {"shade": 0.5, "rim": 0.1, "line": 0.006})
	K.box(g, Vector3(1.5, 0.08, half_w * 2.0 - 0.6),
		Vector3(-0.75, 3.9, 0.0), awning, Vector3(0.0, 0.0, deg_to_rad(-12.0)), false)

	# ---- 二层窗：三个小窗，一扇暖光、一扇冷光、一扇黑
	var lit := K.glow(Color("#ffd9a2"), 0.7)
	var cool := K.glow(Color("#cfe4ff"), 0.45)
	var dark := K.toon(Color("#151a20"), {"shade": 0.85, "line": 0.0})
	var win_step: float = minf(4.4, half_w * 0.9)
	for k in 3:
		var wz := -win_step + k * win_step
		var m: Material = dark
		if k == 1:
			m = lit
		elif k == 2:
			m = cool
		K.box(g, Vector3(0.10, 1.3, 1.9), Vector3(-0.04, 6.0, wz), m, Vector3.ZERO, false)
		K.box(g, Vector3(0.16, 1.55, 0.12), Vector3(-0.06, 6.0, wz - 1.02), trim_mat, Vector3.ZERO, false)
		K.box(g, Vector3(0.16, 1.55, 0.12), Vector3(-0.06, 6.0, wz + 1.02), trim_mat, Vector3.ZERO, false)

	# ---- 坡屋顶：脊沿局部 z，往 ±x 泻水
	var rise := RIDGE - EAVE
	var half_d := DEPTH * 0.5
	var slope_len := sqrt(half_d * half_d + rise * rise)
	var pitch := atan2(rise, half_d)
	for side in [-1.0, 1.0]:
		K.box(g, Vector3(slope_len + 0.5, 0.24, half_w * 2.0 + 0.6),
			Vector3(cx + side * half_d * 0.5, (EAVE + RIDGE) * 0.5, 0.0),
			roof_mat, Vector3(0.0, 0.0, -side * pitch), false)
	K.box(g, Vector3(0.42, 0.22, half_w * 2.0 + 0.8), Vector3(cx, RIDGE + 0.06, 0.0),
		trim_mat, Vector3.ZERO, false)

	# ---- 悬挑招牌：朝街，两面都有字
	var sign_mat := K.toon(Color(spec["sign"]), {"shade": 0.5, "rim": 0.18, "line": 0.007})
	var sign_z := -half_w + 1.1
	K.box(g, Vector3(1.05, 0.07, 0.07), Vector3(-0.55, 4.62, sign_z), trim_mat, Vector3.ZERO, false)
	K.box(g, Vector3(0.10, 1.05, 1.55), Vector3(-1.05, 4.05, sign_z), sign_mat, Vector3.ZERO, false)
	# Label3D 是单面的，两面各摆一块
	K.label_cjk(g, spec["name"], Vector3(-1.11, 4.05, sign_z), 0.34,
		Color(spec["text"]), Vector3(0, -90, 0), 4, Color(0, 0, 0, 0.6))
	K.label_cjk(g, spec["name"], Vector3(-0.99, 4.05, sign_z), 0.34,
		Color(spec["text"]), Vector3(0, 90, 0), 4, Color(0, 0, 0, 0.6))

	# ---- 门头灯
	K.sphere(g, 0.09, Vector3(-0.18, 3.62, -1.6),
		K.glow(Color("#ffd2a0"), 2.2), Vector3.ZERO, 8, 1.0, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffc98c")
	lamp.light_energy = 0.7
	lamp.omni_range = 5.5
	lamp.position = Vector3(-0.6, 3.4, -1.6)
	g.add_child(lamp)


# ---------------------------------------------------------------- 店内

## 店内布置。九间店共用一套「柜台 + 两侧货架 + 吊灯」，再按店型塞货。
##
## 为什么不每间单独写：九间店如果各写一套，改一次灯的高度要改九处。
## 共用的部分（柜台、货架、灯）只写一遍，差异集中在 _props() 的九个分支里。
##
## 动线：门在 z=−1.6，柜台在靠后墙正对门。中间留给玩家走路，
## 货架贴两侧墙 —— 进来不会一开门就撞在货堆上。
static func _interior_local(g: Node3D, spec: Dictionary, width: float) -> void:
	var half_w := width * 0.5 - 0.6
	var cx := DEPTH * 0.5
	var wood := K.toon(Color("#6b5236"), {"shade": 0.55, "rim": 0.16, "line": 0.007})
	var wood_dark := K.toon(Color("#43331f"), {"shade": 0.6, "rim": 0.1, "line": 0.006})

	# ---- 柜台：靠后墙，正对门
	var counter_w: float = minf(half_w * 2.0 - 2.0, 7.0)
	var counter_x := DEPTH - 3.0
	_solid(g, Vector3(0.9, 1.0, counter_w), Vector3(counter_x, 0.5, 0.0), wood)
	K.box(g, Vector3(1.16, 0.09, counter_w + 0.26), Vector3(counter_x, 1.05, 0.0), wood_dark)

	# ---- 两侧靠墙货架：三层板 + 两根立柱
	for side in [-1.0, 1.0]:
		var z: float = side * (half_w - 0.25)
		for k in 3:
			K.box(g, Vector3(DEPTH * 0.46, 0.06, 0.44),
				Vector3(cx * 0.88, 0.72 + k * 0.82, z), wood)
		for k in 2:
			K.box(g, Vector3(0.10, 2.5, 0.10),
				Vector3(cx * 0.88 + (k * 2 - 1) * DEPTH * 0.2, 1.25, z), wood_dark)

	# ---- 吊灯：一盏暖光挂在正中
	K.cyl(g, 0.022, 0.32, Vector3(cx, G0 - 0.16, 0.0), wood_dark, Vector3.ZERO, 6, -1.0, false)
	K.sphere(g, 0.13, Vector3(cx, G0 - 0.38, 0.0), K.glow(Color("#ffd8a6"), 2.4),
		Vector3.ZERO, 10, 1.0, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffcf9a")
	lamp.light_energy = 1.15
	lamp.omni_range = maxf(DEPTH, width) * 0.85
	lamp.position = Vector3(cx, G0 - 0.55, 0.0)
	g.add_child(lamp)

	_props(g, String(spec["kind"]), half_w, cx, counter_x)


## 按店型摆货。每种店三到五件东西，够读出「这是卖什么的」就行，
## 不做货品清单级别的细节 —— 那是以后接商店系统时才需要的。
static func _props(g: Node3D, kind: String, half_w: float, cx: float, counter_x: float) -> void:
	var wood := K.toon(Color("#6b5236"), {"shade": 0.55, "rim": 0.16, "line": 0.007})
	var dark := K.toon(Color("#40301e"), {"shade": 0.6, "line": 0.005})
	var iron := K.toon(Color("#4a4d52"), {"shade": 0.55, "rim": 0.28, "line": 0.006})
	var cloth := K.toon(Color("#7a2f2c"), {"shade": 0.55, "rim": 0.15, "line": 0.006})

	match kind:
		"weapon":
			# 后墙挂三件兵器 + 角落一桶长枪
			for k in 3:
				var z := -2.6 + k * 2.6
				K.box(g, Vector3(0.10, 1.9, 0.10), Vector3(DEPTH - 0.9, 1.7, z), iron)
				K.box(g, Vector3(0.34, 0.10, 0.10), Vector3(DEPTH - 1.05, 2.6, z), dark)
			K.cyl(g, 0.42, 0.95, Vector3(counter_x - 1.6, 0.48, -half_w + 1.4), wood, Vector3.ZERO, 12)
			for k in 3:
				K.strut(g, Vector3(counter_x - 1.6, 0.7, -half_w + 1.4),
					Vector3(counter_x - 1.6 + 0.35, 2.4 + k * 0.12, -half_w + 1.4 + (k - 1) * 0.18),
					0.03, iron, 6)
		"armor":
			# 两具甲架：木头人形 + 胸甲
			for k in 2:
				var p := Vector3(DEPTH * 0.45 + k * 2.4, 0.0, -half_w + 0.9)
				K.cyl(g, 0.16, 1.2, p + Vector3(0, 0.6, 0), dark, Vector3.ZERO, 10)
				K.box(g, Vector3(0.62, 0.72, 0.44), p + Vector3(0, 1.35, 0), iron)
				K.sphere(g, 0.19, p + Vector3(0, 1.86, 0), dark, Vector3.ZERO, 10, 1.0, false)
		"potion":
			# 货架上摆满小瓶：球 + 瓶颈，颜色分三种
			var cols := [Color("#8fd6a0"), Color("#d6b48f"), Color("#8fa8d6")]
			var i := 0
			for side in [-1.0, 1.0]:
				for k in 8:
					var z: float = side * (half_w - 0.25)
					var x: float = cx * 0.88 - DEPTH * 0.20 + (k % 4) * 1.35
					var y: float = 0.86 + (k / 4) * 0.82
					K.sphere(g, 0.10, Vector3(x, y, z), K.toon(cols[i % 3], {"line": 0.004}),
						Vector3.ZERO, 8, 1.25, false)
					K.cyl(g, 0.035, 0.07, Vector3(x, y + 0.14, z), dark, Vector3.ZERO, 6, -1.0, false)
					i += 1
		"smith":
			# 炉子 + 铁砧 + 淬火桶
			K.box(g, Vector3(1.6, 1.1, 2.0), Vector3(DEPTH - 1.4, 0.55, half_w - 2.0), dark)
			K.box(g, Vector3(1.2, 0.35, 1.5), Vector3(DEPTH - 1.4, 1.2, half_w - 2.0),
				K.glow(Color("#ff8c42"), 1.6))
			K.box(g, Vector3(0.55, 0.42, 1.05), Vector3(cx + 0.4, 0.55, -0.4), iron)
			K.box(g, Vector3(0.30, 0.20, 0.36), Vector3(cx + 0.4, 0.82, -0.4), dark)
			K.cyl(g, 0.45, 0.9, Vector3(cx - 2.2, 0.45, half_w - 1.6), wood, Vector3.ZERO, 12)
		"goods":
			# 麻袋堆 + 板条箱 + 成卷的绳子
			for k in 4:
				K.sphere(g, 0.34, Vector3(DEPTH * 0.5 + (k % 2) * 0.8, 0.28, half_w - 1.6 - (k / 2) * 0.75),
					K.toon(Color("#8a7a58"), {"line": 0.006}), Vector3.ZERO, 8, 1.15, false)
			for k in 3:
				K.box(g, Vector3(0.6, 0.55, 0.62),
					Vector3(counter_x - 1.2 + k * 0.7, 0.28, half_w - 1.3), dark)
			K.torus(g, 0.22, 0.30, Vector3(counter_x - 0.8, 1.16, 0.0), cloth, Vector3(90, 0, 0), false)
		"tavern":
			# 两张桌 + 凳子 + 柜台后的酒桶
			for k in 2:
				var p := Vector3(cx - 0.6 + k * 0.4, 0.0, -2.2 + k * 3.6)
				K.cyl(g, 0.62, 0.09, p + Vector3(0, 0.76, 0), wood, Vector3.ZERO, 12)
				K.cyl(g, 0.12, 0.76, p + Vector3(0, 0.38, 0), dark, Vector3.ZERO, 8)
				for s in 3:
					var a := TAU * s / 3.0
					K.cyl(g, 0.17, 0.42,
						p + Vector3(cos(a) * 1.05, 0.21, sin(a) * 1.05), dark, Vector3.ZERO, 8)
			for k in 3:
				K.cyl(g, 0.32, 0.85, Vector3(counter_x - 1.1, 0.43, -2.2 + k * 0.8),
					K.toon(Color("#6b4a2a"), {"line": 0.006}), Vector3.ZERO, 12)
		"inn":
			# 三张床靠两侧墙，门边一块挂钥匙的板
			for k in 3:
				var z: float = (-1.0 if k % 2 == 0 else 1.0) * (half_w - 1.4)
				var x: float = 2.6 + (k / 2) * 3.4
				K.box(g, Vector3(2.6, 0.32, 1.3), Vector3(x, 0.28, z), wood)
				K.box(g, Vector3(0.7, 0.18, 1.1), Vector3(x - 0.9, 0.5, z),
					K.toon(Color("#c9c3b2"), {"line": 0.005}))
				K.box(g, Vector3(1.4, 0.10, 1.3), Vector3(x + 0.55, 0.46, z), cloth)
			K.box(g, Vector3(0.06, 0.9, 0.7), Vector3(0.2, 1.9, half_w - 2.4), dark)
			for k in 4:
				K.box(g, Vector3(0.04, 0.12, 0.05), Vector3(0.16, 2.2 - k * 0.18, half_w - 2.7 + k * 0.16), iron)
		"harness":
			# 两副马鞍架 + 墙上挂着的皮带
			for k in 2:
				var p := Vector3(DEPTH * 0.45 + k * 2.6, 0.0, half_w - 1.2)
				K.cyl(g, 0.13, 0.9, p + Vector3(0, 0.45, 0), dark, Vector3.ZERO, 8)
				K.box(g, Vector3(0.9, 0.22, 0.55), p + Vector3(0, 1.0, 0), wood)
				K.box(g, Vector3(0.5, 0.3, 0.4), p + Vector3(0, 1.2, 0), cloth)
			for k in 5:
				K.box(g, Vector3(0.03, 1.1, 0.10),
					Vector3(DEPTH - 0.7, 1.9, -2.4 + k * 1.2), dark, Vector3.ZERO, false)
		"curio":
			# 货架上零散小物：谁也不知道是什么，这正是古道具店的意思
			var odd := [
				Color("#8a7a5e"), Color("#5e6f7a"), Color("#7a5e6f"), Color("#6f7a5e"),
			]
			var i := 0
			for side in [-1.0, 1.0]:
				for k in 6:
					var z: float = side * (half_w - 0.25)
					var x: float = cx * 0.88 - DEPTH * 0.18 + (k % 3) * 1.7
					var y: float = 0.82 + (k / 3) * 0.82
					var s := 0.10 + (i % 3) * 0.05
					K.box(g, Vector3(s, s * 1.4, s),
						Vector3(x, y + s * 0.7, z), K.toon(odd[i % 4], {"line": 0.005}),
						Vector3(0, i * 0.4, 0), false)
					i += 1
		_:
			pass


## 街边杂物：木桶、板条箱、武器架。没有这些，一排店看起来像一条贴纸。
static func _clutter(g: Node3D) -> void:
	var wood := K.toon(Color("#6b5236"), {"shade": 0.55, "rim": 0.18, "line": 0.007})
	var wood_dark := K.toon(Color("#4a3a26"), {"shade": 0.6, "rim": 0.12, "line": 0.006})
	var iron := K.toon(Color("#4a4d52"), {"shade": 0.55, "rim": 0.3, "line": 0.006})

	var spots := [
		Vector3(X_FRONT - 1.35, 0.0, 311.5),
		Vector3(X_FRONT - 1.35, 0.0, 344.0),
		Vector3(X_FRONT - 1.35, 0.0, 424.0),
		Vector3(X_FRONT - 1.35, 0.0, 449.0),
		# 第二排（沿十字路）门口
		Vector3(30.0, 0.0, CROSS_FRONT_Z - 1.4),
		Vector3(54.0, 0.0, CROSS_FRONT_Z - 1.4),
	]
	for p in spots:
		K.cyl(g, 0.34, 0.82, p + Vector3(0, 0.41, 0), wood, Vector3.ZERO, 12)
		K.cyl(g, 0.36, 0.07, p + Vector3(0, 0.78, 0), wood_dark, Vector3.ZERO, 12)
		K.cyl(g, 0.30, 0.72, p + Vector3(0.72, 0.36, 0.35), wood, Vector3.ZERO, 12)
		K.box(g, Vector3(0.66, 0.5, 0.62), p + Vector3(0.1, 0.25, -0.85), wood_dark)

	# 武具店门口的武器架：三杆长兵器斜靠
	var rack := Vector3(X_FRONT - 1.1, 0.0, 320.0)
	K.box(g, Vector3(0.5, 0.1, 2.4), rack + Vector3(0, 0.06, 0), wood_dark)
	for k in 3:
		var base := rack + Vector3(0.1, 0.1, -0.8 + k * 0.8)
		K.strut(g, base, base + Vector3(0.42, 2.05, 0.18), 0.035, iron, 8)
		K.box(g, Vector3(0.1, 0.42, 0.14), base + Vector3(0.40, 1.98, 0.17), iron)


# ---------------------------------------------------------------- 实体（视觉 + 碰撞）

## kit.box 只给视觉，这里补 StaticBody3D，让店面真的挡人。
static func _solid(g: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	K.box(g, size, pos, mat)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)
	g.add_child(body)
