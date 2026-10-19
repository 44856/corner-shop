extends RefCounted

const K := preload("res://scripts/kit.gd")

# 街景：底座 / 人行道 / 马路 / 标线 / 电线杆 / 路灯 / 街角设施 / 湿地面光池

const ROAD_Y := 0.0
const WALK_Y := 0.16

const B := 5.6          # 底座半宽
const WALK_X0 := -1.9   # 人行道西边界
const WALK_Z1 := 1.9    # 人行道南边界


static func build(root: Node3D) -> void:
	var g := K.group(root, "Street")
	_plinth(g)
	_ground(g)
	_markings(g)
	_drainage(g)
	_poles(g)
	_lamp(g)
	_street_furniture(g)
	_light_pools(g)


# ---------------------------------------------------------------- 底座

static func _plinth(g: Node3D) -> void:
	var stone := K.toon(Color("#272a31"), {"shade": 0.5, "rim": 0.14, "line": 0.012})
	K.box(g, Vector3(B * 2 + 0.5, 0.6, B * 2 + 0.5), Vector3(0, -0.36, 0), stone)
	var foot := K.toon(Color("#15171c"), {"shade": 0.5, "rim": 0.08, "line": 0.01})
	K.box(g, Vector3(B * 2 + 0.72, 0.09, B * 2 + 0.72), Vector3(0, -0.69, 0), foot)
	K.box(g, Vector3(B * 2 + 0.2, 0.03, B * 2 + 0.2), Vector3(0, -0.745, 0), foot)
	# 黄铜腰线
	var brass := K.toon(Color("#7d683f"), {"shade": 0.45, "rim": 0.55, "line": 0.006})
	K.box(g, Vector3(B * 2 + 0.55, 0.026, B * 2 + 0.55), Vector3(0, -0.11, 0), brass)
	K.box(g, Vector3(B * 2 + 0.55, 0.014, B * 2 + 0.55), Vector3(0, -0.56, 0), brass)
	# 正面铭牌
	var plate := K.toon(Color("#26282f"), {"shade": 0.6, "rim": 0.3, "line": 0.005})
	K.box(g, Vector3(2.6, 0.26, 0.02), Vector3(0, -0.37, B + 0.26), plate)
	K.label(g, "RAINY CORNER  ·  HOSHI MART", Vector3(0, -0.37, B + 0.276), 0.075, Color("#bfa878"))


# ---------------------------------------------------------------- 地面

static func _ground(g: Node3D) -> void:
	var asphalt := K.pbr(Color("#12151b"), 0.28, 0.35, {"metallic_specular": 0.65})
	var road := K.box(g, Vector3(B * 2, 0.06, B * 2), Vector3(0, -0.03, 0), asphalt, Vector3.ZERO, false)
	road.name = "Asphalt"

	# 人行道 L 形地块
	var walk_mat := K.paving(Color("#4a4e57"), Color("#2e3138"), 0.9)
	var w := B - WALK_X0
	var d := WALK_Z1 + B
	var walk := K.box(g, Vector3(w, WALK_Y, d), Vector3((WALK_X0 + B) * 0.5, WALK_Y * 0.5, (WALK_Z1 - B) * 0.5), walk_mat, Vector3.ZERO, false)
	walk.name = "Sidewalk"

	# 路缘石
	var curb := K.toon(Color("#63666c"), {"shade": 0.5, "rim": 0.28, "line": 0.007})
	K.box(g, Vector3(0.17, 0.2, d), Vector3(WALK_X0 - 0.075, 0.1, (WALK_Z1 - B) * 0.5), curb)
	K.box(g, Vector3(w, 0.2, 0.17), Vector3((WALK_X0 + B) * 0.5, 0.1, WALK_Z1 + 0.075), curb)
	K.cyl(g, 0.15, 0.2, Vector3(WALK_X0 + 0.02, 0.1, WALK_Z1 - 0.02), curb, Vector3.ZERO, 12)

	# 店面贴地的暗部
	K.box(g, Vector3(w - 0.2, 0.012, 0.06), Vector3((WALK_X0 + B) * 0.5, WALK_Y + 0.004, -0.93), K.toon(Color("#2c2f36"), {"shade": 0.7, "line": 0.0}), Vector3.ZERO, false)


static func _markings(g: Node3D) -> void:
	var paint := K.toon(Color("#464c55"), {"shade": 0.45, "rim": 0.1, "line": 0.0})
	var grp := K.group(g, "Markings")

	# 斑马线：条纹长边平行于车行方向，一排排横跨路面
	# 南侧车道车流沿 X —— 条纹长边沿 X，沿 Z 排开
	var z := 2.35
	for i in 7:
		K.plane(grp, Vector2(4.2, 0.34), Vector3(0.42, 0.004, z), paint, Vector3.ZERO, false)
		z += 0.5
	# 西侧车道车流沿 Z —— 条纹长边沿 Z，沿 X 排开
	var x := -5.42
	for i in 7:
		K.plane(grp, Vector2(0.34, 3.2), Vector3(x, 0.004, 0.15), paint, Vector3.ZERO, false)
		x += 0.54

	# 车道边缘线（在斑马线处断开）
	K.plane(grp, Vector2(0.08, 3.95), Vector3(-2.08, 0.004, -3.58), paint, Vector3.ZERO, false)
	# 中央虚线
	var x2 := 3.4
	while x2 < 5.5:
		K.plane(grp, Vector2(1.0, 0.07), Vector3(x2, 0.004, 4.9), paint, Vector3.ZERO, false)
		x2 += 1.8

	# 停车位标线
	var park := K.toon(Color("#b9bdb4"), {"shade": 0.6, "rim": 0.15, "line": 0.0})
	K.plane(grp, Vector2(0.07, 2.3), Vector3(-1.72, WALK_Y + 0.004, 0.8), park, Vector3.ZERO, false)
	K.plane(grp, Vector2(1.45, 0.07), Vector3(-1.02, WALK_Y + 0.004, -0.35), park, Vector3.ZERO, false)
	K.plane(grp, Vector2(0.07, 0.6), Vector3(-0.3, WALK_Y + 0.004, -0.05), park, Vector3.ZERO, false)

	# 井盖
	var metal := K.toon(Color("#31353c"), {"shade": 0.55, "rim": 0.4, "line": 0.006})
	K.cyl(g, 0.34, 0.012, Vector3(3.9, 0.006, 4.4), metal, Vector3.ZERO, 20, -1.0, false)
	K.cyl(g, 0.275, 0.014, Vector3(3.9, 0.008, 4.4), K.toon(Color("#3d4249"), {"line": 0.0}), Vector3.ZERO, 20, -1.0, false)
	K.cyl(g, 0.09, 0.016, Vector3(3.9, 0.01, 4.4), metal, Vector3.ZERO, 14, -1.0, false)


static func _drainage(g: Node3D) -> void:
	var gutter := K.toon(Color("#15181d"), {"shade": 0.7, "line": 0.0})
	var grate := K.toon(Color("#4b5058"), {"shade": 0.5, "rim": 0.35, "line": 0.005})
	var slot := K.toon(Color("#0c0e11"), {"shade": 0.9, "line": 0.0})
	K.plane(g, Vector2(B - WALK_X0, 0.24), Vector3((WALK_X0 + B) * 0.5, 0.005, 2.13), gutter, Vector3.ZERO, false)
	K.plane(g, Vector2(0.24, B + WALK_Z1), Vector3(-2.14, 0.005, (WALK_Z1 - B) * 0.5), gutter, Vector3.ZERO, false)
	for px in [0.2, 2.9, 5.2]:
		K.box(g, Vector3(0.56, 0.02, 0.2), Vector3(px, 0.012, 2.13), grate, Vector3.ZERO, false)
		for i in 5:
			K.box(g, Vector3(0.04, 0.024, 0.18), Vector3(px - 0.22 + i * 0.11, 0.014, 2.13), slot, Vector3.ZERO, false)
	for pz in [-4.6, -2.2, 0.2]:
		K.box(g, Vector3(0.2, 0.02, 0.56), Vector3(-2.14, 0.012, pz), grate, Vector3.ZERO, false)


# ---------------------------------------------------------------- 电线杆

static func _poles(g: Node3D) -> void:
	var concrete := K.toon(Color("#55585e"), {"shade": 0.52, "rim": 0.2, "line": 0.007})
	var dark := K.toon(Color("#33363d"), {"shade": 0.6, "line": 0.005})
	var grp := K.group(g, "Poles")

	var p1 := Vector3(-1.62, WALK_Y, 1.15)
	var p2 := Vector3(5.2, WALK_Y, -4.85)

	for p in [p1, p2]:
		K.cyl(grp, 0.145, 6.3, p + Vector3(0, 3.15, 0), concrete, Vector3.ZERO, 12)
		K.cyl(grp, 0.175, 0.24, p + Vector3(0, 0.12, 0), concrete, Vector3.ZERO, 12)
		# 横担
		K.box(grp, Vector3(1.45, 0.085, 0.09), p + Vector3(0, 5.86, 0), dark)
		K.box(grp, Vector3(1.15, 0.07, 0.08), p + Vector3(0, 5.4, 0), dark)
		K.box(grp, Vector3(0.08, 0.5, 0.08), p + Vector3(0, 5.62, 0), dark)
		# 绝缘子
		var ins := K.toon(Color("#9a958a"), {"shade": 0.5, "rim": 0.3, "line": 0.004})
		for i in 3:
			var ox := -0.55 + i * 0.55
			K.cyl(grp, 0.05, 0.12, p + Vector3(ox, 5.96, 0), ins, Vector3.ZERO, 8)
			K.cyl(grp, 0.045, 0.1, p + Vector3(ox * 0.8, 5.5, 0), ins, Vector3.ZERO, 8)
		# 变压器
		K.cyl(grp, 0.21, 0.66, p + Vector3(0.22, 4.5, 0), K.toon(Color("#5d6169"), {"shade": 0.55, "rim": 0.25, "line": 0.006}), Vector3.ZERO, 12)
		# 杆号牌
		K.box(grp, Vector3(0.2, 0.28, 0.02), p + Vector3(0.02, 2.55, 0.16), K.toon(Color("#d8d6cf"), {"line": 0.004}))
		K.label(grp, "2-14", p + Vector3(0.02, 2.55, 0.182), 0.075, Color("#2a2f38"))

	# 电线
	var wire_mat := K.toon(Color("#111318"), {"line": 0.0, "shade": 0.9})
	for i in 3:
		var ox := -0.55 + i * 0.55
		K.wire(grp, p1 + Vector3(ox, 6.02, 0), p2 + Vector3(ox, 6.02, 0), 0.55, 0.011, wire_mat)
	for i in 2:
		var ox2 := -0.45 + i * 0.9
		K.wire(grp, p1 + Vector3(ox2 * 0.8, 5.55, 0), p2 + Vector3(ox2 * 0.8, 5.55, 0), 0.6, 0.012, wire_mat)
	# 通向场外的支线
	K.wire(grp, p1 + Vector3(-0.55, 6.0, 0), Vector3(-B - 0.25, 5.3, 1.0), 0.75, 0.011, wire_mat)
	K.wire(grp, p1 + Vector3(0, 5.5, 0), Vector3(-B - 0.25, 4.7, -2.6), 0.95, 0.01, wire_mat)
	K.wire(grp, p1 + Vector3(0.55, 6.0, 0), Vector3(-1.2, 5.15, B + 0.25), 0.85, 0.011, wire_mat)
	K.wire(grp, p2 + Vector3(0, 5.55, 0), Vector3(5.45, 5.1, -B - 0.25), 0.35, 0.011, wire_mat)


# ---------------------------------------------------------------- 路灯

static func _lamp(g: Node3D) -> void:
	var grp := K.group(g, "StreetLamp")
	var pole_mat := K.toon(Color("#4e535b"), {"shade": 0.55, "rim": 0.28, "line": 0.006})
	var base := Vector3(4.35, WALK_Y, 1.55)
	K.cyl(grp, 0.075, 4.3, base + Vector3(0, 2.15, 0), pole_mat, Vector3.ZERO, 10)
	K.cyl(grp, 0.14, 0.22, base + Vector3(0, 0.11, 0), pole_mat, Vector3.ZERO, 10)
	# 弯臂
	K.strut(grp, base + Vector3(0, 4.24, 0), base + Vector3(0, 4.46, 0.6), 0.06, pole_mat, 8)
	K.strut(grp, base + Vector3(0, 4.46, 0.6), base + Vector3(0, 4.38, 1.5), 0.055, pole_mat, 8)
	# 灯头
	var head := base + Vector3(0, 4.32, 1.52)
	K.box(grp, Vector3(0.34, 0.13, 0.62), head, K.toon(Color("#43474e"), {"shade": 0.6, "line": 0.006}))
	K.box(grp, Vector3(0.29, 0.03, 0.5), head + Vector3(0, -0.07, 0), K.glow(Color("#ffd9a2"), 3.0))
	K.sphere(grp, 0.24, head + Vector3(0, -0.06, 0), K.soft(Color("#ffb972"), 0.3, 1.8), Vector3.ZERO, 14, 0.6, false)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc07a")
	light.light_energy = 1.9
	light.omni_range = 9.0
	light.omni_attenuation = 1.5
	light.shadow_enabled = true
	light.position = head + Vector3(0, -0.22, 0)
	grp.add_child(light)


static func _light_pools(g: Node3D) -> void:
	# 地面上的柔光池（湿地面反光的简化表达）
	var grp := K.group(g, "LightPools")
	var pool := func(pos: Vector3, size: Vector2, col: Color, s: float) -> void:
		K.plane(grp, size, pos, K.wet(col, s), Vector3.ZERO, false)
	pool.call(Vector3(4.35, 0.012, 3.05), Vector2(6.6, 6.6), Color("#ffb46a"), 0.1)
	pool.call(Vector3(0.7, WALK_Y + 0.006, -0.3), Vector2(5.0, 2.1), Color("#ffd7a1"), 0.075)
	pool.call(Vector3(0.7, 0.014, 1.0), Vector2(4.2, 2.4), Color("#ffcf9a"), 0.03)
	pool.call(Vector3(4.75, WALK_Y + 0.006, -0.1), Vector2(1.8, 1.6), Color("#bfe6ff"), 0.08)
	pool.call(Vector3(4.4, 0.014, 2.6), Vector2(2.6, 2.2), Color("#79a8ff"), 0.035)


static func _street_furniture(g: Node3D) -> void:
	var grp := K.group(g, "Furniture")

	# 护栏（东侧路缘）
	var rail_mat := K.toon(Color("#83898f"), {"shade": 0.55, "rim": 0.3, "line": 0.005})
	var x := 3.55
	while x < 5.5:
		K.cyl(grp, 0.035, 0.86, Vector3(x, WALK_Y + 0.43, 1.78), rail_mat, Vector3.ZERO, 8)
		x += 1.1
	K.strut(grp, Vector3(3.35, WALK_Y + 0.82, 1.78), Vector3(5.5, WALK_Y + 0.82, 1.78), 0.032, rail_mat, 8)
	K.strut(grp, Vector3(3.35, WALK_Y + 0.5, 1.78), Vector3(5.5, WALK_Y + 0.5, 1.78), 0.028, rail_mat, 8)

	# 街角凸面镜
	var pole := Vector3(-1.8, WALK_Y, 1.98)
	K.cyl(grp, 0.045, 2.9, pole + Vector3(0, 1.45, 0), K.toon(Color("#98402a"), {"shade": 0.5, "rim": 0.2, "line": 0.005}), Vector3.ZERO, 8)
	K.box(grp, Vector3(0.07, 0.07, 0.34), pole + Vector3(0, 2.95, 0.16), K.toon(Color("#98402a"), {"line": 0.005}))
	var mirror_pos := pole + Vector3(0, 2.82, 0.3)
	K.torus(grp, 0.15, 0.21, mirror_pos, K.toon(Color("#c25a1e"), {"shade": 0.5, "rim": 0.35, "line": 0.005}), Vector3(90, 0, 0))
	K.cyl(grp, 0.175, 0.02, mirror_pos, K.pbr(Color("#7c8896"), 0.1, 0.9), Vector3(90, 0, 0), 20)
	K.cyl(grp, 0.165, 0.01, mirror_pos + Vector3(0, 0, 0.014), K.toon(Color("#aebdca"), {"shade": 0.9, "rim": 0.6, "line": 0.0}), Vector3(90, 0, 0), 20)

	# 路牌（独立立柱，牌面接在杆顶，不与路灯杆共用位置）
	var sp := Vector3(4.95, WALK_Y, 0.62)
	K.cyl(grp, 0.04, 2.44, sp + Vector3(0, 1.22, 0), K.toon(Color("#666b71"), {"shade": 0.55, "line": 0.005}), Vector3.ZERO, 8)
	K.box(grp, Vector3(0.035, 0.24, 1.05), sp + Vector3(0, 2.72, 0), K.toon(Color("#1b4a72"), {"shade": 0.6, "rim": 0.35, "line": 0.005}))
	K.label(grp, "SAKURA 2", sp + Vector3(-0.034, 2.72, 0), 0.12, Color("#e8f1f8"), Vector3(0, -90, 0))
	# 交通锥
	var cone := K.toon(Color("#d9603a"), {"shade": 0.55, "rim": 0.25, "line": 0.005})
	K.cyl(grp, 0.15, 0.05, Vector3(-2.35, 0.03, 2.55), cone, Vector3.ZERO, 10)
	K.cyl(grp, 0.1, 0.42, Vector3(-2.35, 0.24, 2.55), cone, Vector3.ZERO, 10, 0.03)
	K.cyl(grp, 0.055, 0.08, Vector3(-2.35, 0.31, 2.55), K.toon(Color("#e8e5dc"), {"line": 0.0}), Vector3.ZERO, 10, -1.0, false)

	# 停车位指示牌（立在门前的空地，避开雨棚、电线杆与凸面镜）
	var pp := Vector3(-1.35, WALK_Y, 1.72)
	K.cyl(grp, 0.032, 2.05, pp + Vector3(0, 1.025, 0), K.toon(Color("#666b71"), {"shade": 0.55, "line": 0.005}), Vector3.ZERO, 8)
	# 牌面挂在立柱前方，不让立杆从牌中间穿过去
	var pb := pp + Vector3(0, 2.02, 0.05)
	K.box(grp, Vector3(0.42, 0.42, 0.03), pb, K.toon(Color("#1b4a72"), {"line": 0.005, "rim": 0.3}))
	K.label(grp, "P", pb + Vector3(0, 0, 0.034), 0.26, Color("#ffffff"))
