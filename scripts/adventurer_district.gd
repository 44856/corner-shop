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
	{"name": "武具店", "wall": "#8a7a5e", "sign": "#2c3f56", "text": "#f0dfae"},
	{"name": "防具店", "wall": "#7d6b55", "sign": "#3a2b22", "text": "#e8cf9a"},
	{"name": "薬師屋", "wall": "#8f8570", "sign": "#243d33", "text": "#dceccb"},
	{"name": "鍛冶屋", "wall": "#6e6258", "sign": "#2a2622", "text": "#ffc98a"},
	{"name": "雑貨店", "wall": "#867a68", "sign": "#332a3f", "text": "#e3d5f0"},
	{"name": "酒場", "wall": "#7a6050", "sign": "#4a2224", "text": "#ffd9a8"},
	{"name": "宿屋", "wall": "#6b6f7a", "sign": "#1f2a38", "text": "#ffe0a8"},
	{"name": "馬具屋", "wall": "#7b6752", "sign": "#33281c", "text": "#f0dcc0"},
	{"name": "古道具", "wall": "#6a6258", "sign": "#2b2431", "text": "#d8cff0"},
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

	# ---- 主体：两层墙做成一个盒子，挡人也靠它
	_solid(g, Vector3(DEPTH, EAVE, half_w * 2.0),
		Vector3(cx, EAVE * 0.5, 0.0), wall_mat)

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
