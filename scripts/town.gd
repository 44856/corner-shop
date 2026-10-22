extends RefCounted
## 星见町商店街的街道层：底座 / 地面 / 标线 / 排水 / 电线杆 / 路灯 / 东口牌楼 / 街具。
##
## 为什么不复用 street.gd：
##   那一份的坐标是围绕 11.2m 见方底座手写的 L 形街角（西侧车道、转角凸面镜、
##   便利店前的停车位）。把底座直接拉长，这些相对位置会全部错位，
##   而且 store_walk 的探针钉着旧尺寸。这里用同一套 kit 原语重写一条直街，
##   地面高度、路缘做法、湿地面材质与旧场景保持一致，视觉语言不会分裂。

const K := preload("res://scripts/kit.gd")
const Props := preload("res://scripts/props.gd")

## 底座范围。碰撞脚本直接引用这些常量，改尺寸只改这一处。
const X0 := -5.6
const X1 := 30.0
const Z0 := -5.6
const Z1 := 9.6
const CENTER_X := 12.2
const CENTER_Z := 2.0

const WALK_Y := 0.16
## 马路：北缘 2.07（路缘石外沿），南缘 5.0
const ROAD_Z0 := 2.07
const ROAD_Z1 := 5.0
## 南侧人行道外沿（再往南就是南排店面的前墙）
const SOUTH_WALK_Z1 := 6.3

## 东口牌楼：跨住整条街，北柱在北人行道，南柱在南人行道
const GATE_X := 27.0
const GATE_Z0 := -0.55
const GATE_Z1 := 5.95

## 路灯：南北交替。arm = +1 时灯臂伸向马路（南），−1 反之。
const LAMPS := [
	{"x": 10.8, "z": 1.55, "arm": 1.0},
	{"x": 25.6, "z": 1.55, "arm": 1.0},
	{"x": 7.2, "z": 5.62, "arm": -1.0},
	{"x": 18.4, "z": 5.62, "arm": -1.0},
]

## 北侧电线杆。柱距 7.6m，比现实密一点 —— 这条街只有七间店面长。
const POLES := [7.6, 15.2, 22.8]
const POLE_Z := 1.62
## 马路对面那根，用来拉一根跨街线
const SOUTH_POLE := Vector3(28.2, 0.16, 6.02)


static func build(root: Node3D) -> void:
	var g := K.group(root, "Town")
	_plinth(g)
	_ground(g)
	_markings(g)
	_drainage(g)
	_poles(g)
	_lamps(g)
	_gate(g)
	_backdrop(g)
	_furniture(g)
	_light_pools(g)


# ---------------------------------------------------------------- 底座

static func _plinth(g: Node3D) -> void:
	var stone := K.toon(Color("#272a31"), {"shade": 0.5, "rim": 0.14, "line": 0.012})
	K.box(g, Vector3(X1 - X0 + 0.5, 0.6, Z1 - Z0 + 0.5), Vector3(CENTER_X, -0.36, CENTER_Z), stone)
	var foot := K.toon(Color("#15171c"), {"shade": 0.5, "rim": 0.08, "line": 0.01})
	K.box(g, Vector3(X1 - X0 + 0.72, 0.09, Z1 - Z0 + 0.72), Vector3(CENTER_X, -0.69, CENTER_Z), foot)
	K.box(g, Vector3(X1 - X0 + 0.2, 0.03, Z1 - Z0 + 0.2), Vector3(CENTER_X, -0.745, CENTER_Z), foot)

	var brass := K.toon(Color("#7d683f"), {"shade": 0.45, "rim": 0.55, "line": 0.006})
	K.box(g, Vector3(X1 - X0 + 0.55, 0.026, Z1 - Z0 + 0.55), Vector3(CENTER_X, -0.11, CENTER_Z), brass)
	K.box(g, Vector3(X1 - X0 + 0.55, 0.014, Z1 - Z0 + 0.55), Vector3(CENTER_X, -0.56, CENTER_Z), brass)

	# 铭牌朝南（默认观看面）。东口牌楼那一侧不重复放，免得底座侧面太吵。
	var plate := K.toon(Color("#26282f"), {"shade": 0.6, "rim": 0.3, "line": 0.005})
	K.box(g, Vector3(6.4, 0.26, 0.02), Vector3(CENTER_X, -0.37, Z1 + 0.26), plate)
	K.label_cjk(g, "HOSHIMI SHOTENGAI  ·  星見町商店街",
		Vector3(CENTER_X, -0.37, Z1 + 0.276), 0.075, Color("#bfa878"))


# ---------------------------------------------------------------- 地面

static func _ground(g: Node3D) -> void:
	var asphalt := K.pbr(Color("#12151b"), 0.28, 0.35, {"metallic_specular": 0.65})
	var road := K.box(g, Vector3(X1 - X0, 0.06, Z1 - Z0), Vector3(CENTER_X, -0.03, CENTER_Z),
		asphalt, Vector3.ZERO, false)
	road.name = "Asphalt"

	var walk_mat := K.paving(Color("#4a4e57"), Color("#2e3138"), 0.9)
	# 北侧：从底座北缘一直铺到路缘石内沿（z 1.9）。店面占掉的那一段在几何上
	# 被建筑盖住，但碰撞仍是 0.16 高的整块 —— 人不会掉进墙脚。
	var north := K.box(g, Vector3(X1 - X0, WALK_Y, 1.9 - Z0),
		Vector3(CENTER_X, WALK_Y * 0.5, (Z0 + 1.9) * 0.5), walk_mat, Vector3.ZERO, false)
	north.name = "SidewalkNorth"
	# 南侧：路缘石 5.0..5.17，铺面 5.17..6.3
	var south := K.box(g, Vector3(X1 - X0, WALK_Y, SOUTH_WALK_Z1 - 5.17),
		Vector3(CENTER_X, WALK_Y * 0.5, (5.17 + SOUTH_WALK_Z1) * 0.5), walk_mat, Vector3.ZERO, false)
	south.name = "SidewalkSouth"

	# 路缘石：顶面与人行道齐平。外移 1cm 避免共面 z-fighting。
	var curb := K.toon(Color("#63666c"), {"shade": 0.5, "rim": 0.28, "line": 0.007})
	K.box(g, Vector3(X1 - X0, WALK_Y, 0.17), Vector3(CENTER_X, WALK_Y * 0.5, 1.985), curb)
	K.box(g, Vector3(X1 - X0, WALK_Y, 0.17), Vector3(CENTER_X, WALK_Y * 0.5, ROAD_Z1 + 0.085), curb)

	# 店面贴地的暗部（整条街一条，不逐店画）
	K.box(g, Vector3(X1 - X0, 0.012, 0.05), Vector3(CENTER_X, WALK_Y + 0.004, -0.92),
		K.toon(Color("#2c2f36"), {"shade": 0.7, "line": 0.0}), Vector3.ZERO, false)


# ---------------------------------------------------------------- 标线

static func _markings(g: Node3D) -> void:
	var paint := K.toon(Color("#464c55"), {"shade": 0.45, "rim": 0.1, "line": 0.0})
	var grp := K.group(g, "Markings")

	# 中央虚线
	var x := -5.2
	while x < 26.4:
		K.plane(grp, Vector2(1.7, 0.07), Vector3(x + 0.85, 0.004, 3.535), paint, Vector3.ZERO, false)
		x += 3.4

	# 路缘边线。斑马线位置（x 22.3..25.1）断开，空出过街口。
	for z in [2.28, 4.81]:
		K.plane(grp, Vector2(27.5, 0.07), Vector3(8.5, 0.003, z), paint, Vector3.ZERO, false)
		K.plane(grp, Vector2(4.7, 0.07), Vector3(27.45, 0.003, z), paint, Vector3.ZERO, false)

	# 斑马线：条纹长边沿车行方向（X），沿 Z 排开。正好对着东口牌楼。
	var z := 2.28
	while z < 4.9:
		K.plane(grp, Vector2(2.6, 0.3), Vector3(23.7, 0.005, z), paint, Vector3.ZERO, false)
		z += 0.48

	# 井盖
	var metal := K.toon(Color("#31353c"), {"shade": 0.55, "rim": 0.4, "line": 0.006})
	for p in [Vector3(3.6, 0.006, 4.4), Vector3(11.4, 0.006, 2.7), Vector3(19.2, 0.006, 4.35)]:
		K.cyl(grp, 0.34, 0.012, p, metal, Vector3.ZERO, 20, -1.0, false)
		K.cyl(grp, 0.275, 0.014, p + Vector3(0, 0.002, 0),
			K.toon(Color("#3d4249"), {"line": 0.0}), Vector3.ZERO, 20, -1.0, false)
		K.cyl(grp, 0.09, 0.016, p + Vector3(0, 0.004, 0), metal, Vector3.ZERO, 14, -1.0, false)

	# 自行车停放区（东口牌楼北柱旁）
	var park := K.toon(Color("#b9bdb4"), {"shade": 0.6, "rim": 0.15, "line": 0.0})
	K.plane(grp, Vector2(0.06, 1.15), Vector3(25.55, WALK_Y + 0.004, 0.62), park, Vector3.ZERO, false)
	K.plane(grp, Vector2(0.06, 1.15), Vector3(27.02, WALK_Y + 0.004, 0.62), park, Vector3.ZERO, false)
	K.plane(grp, Vector2(1.47, 0.06), Vector3(26.28, WALK_Y + 0.004, 1.19), park, Vector3.ZERO, false)


static func _drainage(g: Node3D) -> void:
	var gutter := K.toon(Color("#15181d"), {"shade": 0.7, "line": 0.0})
	var grate := K.toon(Color("#4b5058"), {"shade": 0.5, "rim": 0.35, "line": 0.005})
	var slot := K.toon(Color("#0c0e11"), {"shade": 0.9, "line": 0.0})
	K.plane(g, Vector2(X1 - X0, 0.24), Vector3(CENTER_X, 0.005, 2.13), gutter, Vector3.ZERO, false)
	K.plane(g, Vector2(X1 - X0, 0.24), Vector3(CENTER_X, 0.005, ROAD_Z1 - 0.13), gutter, Vector3.ZERO, false)

	var x := 1.4
	while x < 29.0:
		K.box(g, Vector3(0.56, 0.02, 0.2), Vector3(x, 0.012, 2.13), grate, Vector3.ZERO, false)
		K.box(g, Vector3(0.56, 0.02, 0.2), Vector3(x + 2.4, 0.012, ROAD_Z1 - 0.13), grate, Vector3.ZERO, false)
		for i in 5:
			var ox := -0.22 + i * 0.11
			K.box(g, Vector3(0.04, 0.024, 0.18), Vector3(x + ox, 0.014, 2.13), slot, Vector3.ZERO, false)
			K.box(g, Vector3(0.04, 0.024, 0.18), Vector3(x + 2.4 + ox, 0.014, ROAD_Z1 - 0.13), slot, Vector3.ZERO, false)
		x += 5.2


# ---------------------------------------------------------------- 电线杆

static func _poles(g: Node3D) -> void:
	var concrete := K.toon(Color("#55585e"), {"shade": 0.52, "rim": 0.2, "line": 0.007})
	var dark := K.toon(Color("#33363d"), {"shade": 0.6, "line": 0.005})
	var ins := K.toon(Color("#9a958a"), {"shade": 0.5, "rim": 0.3, "line": 0.004})
	var grp := K.group(g, "Poles")
	var points: Array = []

	for px in POLES:
		var p := Vector3(float(px), WALK_Y, POLE_Z)
		points.append(p)
		K.cyl(grp, 0.145, 6.3, p + Vector3(0, 3.15, 0), concrete, Vector3.ZERO, 12)
		K.cyl(grp, 0.175, 0.24, p + Vector3(0, 0.12, 0), concrete, Vector3.ZERO, 12)
		K.box(grp, Vector3(1.45, 0.085, 0.09), p + Vector3(0, 5.86, 0), dark)
		K.box(grp, Vector3(1.15, 0.07, 0.08), p + Vector3(0, 5.4, 0), dark)
		K.box(grp, Vector3(0.08, 0.5, 0.08), p + Vector3(0, 5.62, 0), dark)
		for i in 3:
			var ox := -0.55 + i * 0.55
			K.cyl(grp, 0.05, 0.12, p + Vector3(ox, 5.96, 0), ins, Vector3.ZERO, 8)
			K.cyl(grp, 0.045, 0.1, p + Vector3(ox * 0.8, 5.5, 0), ins, Vector3.ZERO, 8)
		K.cyl(grp, 0.21, 0.66, p + Vector3(0.22, 4.5, 0),
			K.toon(Color("#5d6169"), {"shade": 0.55, "rim": 0.25, "line": 0.006}), Vector3.ZERO, 12)
		K.box(grp, Vector3(0.2, 0.28, 0.02), p + Vector3(0.02, 2.55, 0.16),
			K.toon(Color("#d8d6cf"), {"line": 0.004}))
		K.label(grp, str(int(px)) + "-2", p + Vector3(0.02, 2.55, 0.182), 0.075, Color("#2a2f38"))

	var wire_mat := K.toon(Color("#111318"), {"line": 0.0, "shade": 0.9})
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		for k in 3:
			var ox := -0.55 + k * 0.55
			K.wire(grp, a + Vector3(ox, 6.02, 0), b + Vector3(ox, 6.02, 0), 0.55, 0.011, wire_mat)
		for k in 2:
			var ox2 := -0.45 + k * 0.9
			K.wire(grp, a + Vector3(ox2 * 0.8, 5.55, 0), b + Vector3(ox2 * 0.8, 5.55, 0), 0.6, 0.012, wire_mat)

	# 场外支线：让街在画面边缘继续延伸，而不是在底座边一刀切断
	if points.size() > 0:
		var first: Vector3 = points[0]
		var last: Vector3 = points[points.size() - 1]
		for k in 3:
			var ox := -0.55 + k * 0.55
			K.wire(grp, first + Vector3(ox, 6.02, 0), Vector3(X0 - 0.3, 5.35 + k * 0.2, POLE_Z + 0.2),
				0.8, 0.011, wire_mat)
			K.wire(grp, last + Vector3(ox, 6.02, 0), Vector3(X1 + 0.3, 5.9, POLE_Z),
				0.35, 0.011, wire_mat)

	# 跨街线 + 南侧那根矮杆。杆子在门牌楼后面，不抢画面。
	var sp := SOUTH_POLE
	K.cyl(grp, 0.12, 5.2, sp + Vector3(0, 2.6, 0), concrete, Vector3.ZERO, 10)
	K.box(grp, Vector3(1.1, 0.07, 0.08), sp + Vector3(0, 4.9, 0), dark)
	var north_pole := Vector3(22.8, WALK_Y, POLE_Z)
	for k in 3:
		var ox3 := -0.55 + k * 0.55
		K.wire(grp, north_pole + Vector3(ox3, 5.55, 0), sp + Vector3(ox3 * 0.7, 4.95, 0),
			0.45, 0.01, wire_mat)


# ---------------------------------------------------------------- 路灯

static func _lamps(g: Node3D) -> void:
	var grp := K.group(g, "StreetLamps")
	for i in LAMPS.size():
		var spec: Dictionary = LAMPS[i]
		# 只让两盏投影：Omni 阴影是立方体贴图，六盏全开等于六次场景重绘。
		_lamp(grp, Vector3(float(spec["x"]), WALK_Y, float(spec["z"])),
			float(spec["arm"]), i < 2)


static func _lamp(g: Node3D, base: Vector3, arm: float, shadow: bool) -> void:
	var pole_mat := K.toon(Color("#4e535b"), {"shade": 0.55, "rim": 0.28, "line": 0.006})
	K.cyl(g, 0.075, 4.3, base + Vector3(0, 2.15, 0), pole_mat, Vector3.ZERO, 10)
	K.cyl(g, 0.14, 0.22, base + Vector3(0, 0.11, 0), pole_mat, Vector3.ZERO, 10)
	var reach := 1.5 * arm
	K.strut(g, base + Vector3(0, 4.24, 0), base + Vector3(0, 4.46, 0.6 * arm), 0.06, pole_mat, 8)
	K.strut(g, base + Vector3(0, 4.46, 0.6 * arm), base + Vector3(0, 4.38, reach), 0.055, pole_mat, 8)

	var head := base + Vector3(0, 4.32, reach)
	K.box(g, Vector3(0.34, 0.13, 0.62), head,
		K.toon(Color("#43474e"), {"shade": 0.6, "line": 0.006}))
	K.box(g, Vector3(0.29, 0.03, 0.5), head + Vector3(0, -0.07, 0),
		K.glow(Color("#ffd9a2"), 3.0))
	K.sphere(g, 0.24, head + Vector3(0, -0.06, 0),
		K.soft(Color("#ffb972"), 0.3, 1.8), Vector3.ZERO, 14, 0.6, false)

	var light := OmniLight3D.new()
	light.light_color = Color("#ffc07a")
	light.light_energy = 1.9
	light.omni_range = 9.5
	light.omni_attenuation = 1.5
	light.shadow_enabled = shadow
	light.position = head + Vector3(0, -0.22, 0)
	g.add_child(light)


# ---------------------------------------------------------------- 东口牌楼

static func _gate(g: Node3D) -> void:
	var grp := K.group(g, "EastGate")
	var steel := K.toon(Color("#3d4249"), {"shade": 0.5, "rim": 0.25, "line": 0.008})
	var dark := K.toon(Color("#252a31"), {"shade": 0.6, "line": 0.006})
	var brass := K.toon(Color("#8a7244"), {"shade": 0.45, "rim": 0.5, "line": 0.005})

	for z in [GATE_Z0, GATE_Z1]:
		var p := Vector3(GATE_X, WALK_Y, z)
		K.cyl(grp, 0.2, 5.1, p + Vector3(0, 2.55, 0), steel, Vector3.ZERO, 12)
		K.cyl(grp, 0.3, 0.18, p + Vector3(0, 0.09, 0), dark, Vector3.ZERO, 12)
		K.cyl(grp, 0.26, 0.14, p + Vector3(0, 5.14, 0), brass, Vector3.ZERO, 12)

	# 横梁 + 招牌。牌面只比梁厚一点，从东西两侧都能读。
	K.box(grp, Vector3(0.36, 0.34, GATE_Z1 - GATE_Z0 + 0.5),
		Vector3(GATE_X, 4.86, (GATE_Z0 + GATE_Z1) * 0.5), dark)
	var board := K.box(grp, Vector3(0.16, 1.02, 4.9), Vector3(GATE_X, 5.55, 2.7),
		K.toon(Color("#20302b"), {"shade": 0.55, "rim": 0.2, "line": 0.007}))
	board.name = "GateSign"
	K.box(grp, Vector3(0.19, 0.06, 5.0), Vector3(GATE_X, 6.08, 2.7), brass)
	# 两面各一块：西面（玩家出生后回头）与东面（开场机位）
	K.label_cjk(grp, "星見町商店街", Vector3(GATE_X - 0.095, 5.55, 2.7), 0.52,
		Color("#ffe6b0"), Vector3(0, -90, 0), 10, Color("#5a3c14"))
	K.label_cjk(grp, "星見町商店街", Vector3(GATE_X + 0.095, 5.55, 2.7), 0.52,
		Color("#ffe6b0"), Vector3(0, 90, 0), 10, Color("#5a3c14"))
	K.label(grp, "HOSHIMI SHOTENGAI", Vector3(GATE_X - 0.095, 5.24, 2.7), 0.13,
		Color("#e8d3a2"), Vector3(0, -90, 0))
	K.label(grp, "HOSHIMI SHOTENGAI", Vector3(GATE_X + 0.095, 5.24, 2.7), 0.13,
		Color("#e8d3a2"), Vector3(0, 90, 0))

	# 梁下三盏小灯：牌楼是整条街最亮的一处，从东口进来先看到它
	for z in [0.75, 2.7, 4.65]:
		K.sphere(grp, 0.07, Vector3(GATE_X, 4.66, z), K.glow(Color("#ffdca6"), 2.6),
			Vector3.ZERO, 10, 1.0, false)
		K.sphere(grp, 0.3, Vector3(GATE_X, 4.66, z), K.soft(Color("#ffbf7a"), 0.34, 1.9),
			Vector3.ZERO, 12, 0.9, false)
	var gl := OmniLight3D.new()
	gl.light_color = Color("#ffc98e")
	gl.light_energy = 1.3
	gl.omni_range = 9.0
	gl.position = Vector3(GATE_X, 4.4, 2.7)
	grp.add_child(gl)

	# 两根垂幅：颜色压得比招牌暗，近看有字，远看只是两条竖线
	var cloth := K.toon(Color("#8f2f2c"), {"shade": 0.5, "rim": 0.2, "line": 0.005})
	for z in [0.35, 5.15]:
		K.box(grp, Vector3(0.03, 1.5, 0.42), Vector3(GATE_X - 0.02, 3.85, z), cloth,
			Vector3.ZERO, false)
		K.label_cjk(grp, "星\n見\n町", Vector3(GATE_X - 0.04, 3.85, z), 0.15,
			Color("#f3dfb4"), Vector3(0, -90, 0))


# ---------------------------------------------------------------- 街具

static func _backdrop(g: Node3D) -> void:
	# 东口之外的「对面楼」。底座在 x=30 结束，没有这堵墙时从牌楼往东看
	# 是一个纯黑空洞 —— 像舞台布景漏了底。墙放在底座边缘之外，
	# 只做视觉收口，不参与碰撞（边界围栏已经把人拦在 x≈29.9）。
	var grp := K.group(g, "EastBackdrop")
	var wall := K.toon(Color("#292d35"), {"shade": 0.42, "rim": 0.12, "line": 0.01})
	K.box(grp, Vector3(0.5, 9.2, Z1 - Z0 + 0.4), Vector3(X1 + 0.2, 4.44, CENTER_Z), wall)
	var face_x := X1 - 0.05

	# 一层：卷帘门 + 横楣灯箱。尺度按街对面看，不按贴脸看。
	var shutter := K.toon(Color("#3b4049"), {"shade": 0.55, "rim": 0.2, "line": 0.006})
	K.box(grp, Vector3(0.06, 2.5, 3.4), Vector3(face_x, WALK_Y + 1.25, 1.6), shutter)
	var seam := K.toon(Color("#2a2e35"), {"line": 0.0})
	for i in 15:
		K.box(grp, Vector3(0.02, 0.018, 3.34),
			Vector3(face_x - 0.04, WALK_Y + 0.14 + i * 0.16, 1.6), seam, Vector3.ZERO, false)
	K.box(grp, Vector3(0.05, 0.56, 2.3), Vector3(face_x - 0.03, 3.05, 1.6),
		K.glow(Color("#ffe3b4"), 0.9))
	K.label_cjk(grp, "東口通り", Vector3(face_x - 0.07, 3.05, 1.6), 0.34,
		Color("#3a2a1c"), Vector3(0, -90, 0))

	# 楼上住户窗：约三分之一亮着。全部点亮会像写字楼，全灭又回到黑洞。
	var lit_warm := K.glow(Color("#ffd39a"), 0.55)
	var lit_cool := K.glow(Color("#cfe4ff"), 0.4)
	var dark_win := K.toon(Color("#11151c"), {"shade": 0.9, "line": 0.0})
	for row in 3:
		for col in 5:
			var wy := 4.05 + row * 1.65
			var wz := -4.0 + col * 2.85
			var m: Material = dark_win
			if (row * 5 + col) % 3 == 0:
				m = lit_warm
			elif (row * 5 + col) % 3 == 1:
				m = lit_cool
			K.box(grp, Vector3(0.04, 0.95, 1.15), Vector3(face_x - 0.02, wy, wz),
				m, Vector3.ZERO, false)

	# 屋顶水箱与女儿墙剪影，让天际线不是一刀平
	K.box(grp, Vector3(1.3, 0.85, 1.7), Vector3(X1 + 0.15, 9.15, -2.1),
		K.toon(Color("#1f232a"), {"line": 0.004}))
	K.box(grp, Vector3(0.16, 0.5, Z1 - Z0), Vector3(X1 + 0.02, 9.45, CENTER_Z),
		K.toon(Color("#333840"), {"line": 0.004}))


# ---------------------------------------------------------------- 街具

static func _furniture(g: Node3D) -> void:
	var grp := K.group(g, "Furniture")
	_bus_stop(grp)
	_convex_mirror(grp)
	_guardrail(grp)

	# 东口自行车停放区（标线在 _markings 里）：三辆并排、车头朝马路，
	# 长轴沿 Z，沿 X 每 0.56~0.60m 一辆 —— 与 1.47m 宽的划线车位对得上。
	Props.bicycle(grp, Vector3(25.82, WALK_Y, 0.62), 180.0)
	Props.bicycle(grp, Vector3(26.42, WALK_Y, 0.62), 180.0)
	Props.bicycle(grp, Vector3(26.98, WALK_Y, 0.62), 180.0)
	# 拉面店门口一辆，斜着停在雨棚下
	Props.bicycle(grp, Vector3(5.98, WALK_Y, 0.18), 78.0)


static func _bus_stop(g: Node3D) -> void:
	var steel := K.toon(Color("#5a6068"), {"shade": 0.55, "rim": 0.28, "line": 0.006})
	var glass := K.glass(Color(0.5, 0.62, 0.75, 0.1), 0.28)
	for x in [23.65, 25.05]:
		K.cyl(g, 0.05, 2.55, Vector3(x, WALK_Y + 1.275, 5.55), steel, Vector3.ZERO, 8)
	K.box(g, Vector3(1.9, 0.08, 1.05), Vector3(24.35, WALK_Y + 2.59, 5.75), steel)
	K.quad(g, Vector2(1.8, 1.5), Vector3(24.35, WALK_Y + 1.55, 6.16), glass,
		Vector3(0, 180, 0), false)
	# 长椅
	K.box(g, Vector3(1.5, 0.07, 0.34), Vector3(24.35, WALK_Y + 0.46, 5.86),
		K.toon(Color("#4a3a28"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	for x in [23.75, 24.95]:
		K.box(g, Vector3(0.06, 0.42, 0.3), Vector3(x, WALK_Y + 0.22, 5.86),
			K.toon(Color("#3a3e45"), {"line": 0.004}))

	# 站牌：圆牌 + 竖杆，牌面写东口
	K.cyl(g, 0.035, 2.45, Vector3(25.45, WALK_Y + 1.225, 5.28), steel, Vector3.ZERO, 8)
	K.cyl(g, 0.24, 0.04, Vector3(25.45, WALK_Y + 2.45, 5.28),
		K.toon(Color("#e7e2d4"), {"shade": 0.7, "rim": 0.2, "line": 0.005}), Vector3(90, 0, 0), 20)
	# 牌面朝北（马路一侧）。不转 180° 的话，站在街上看到的是圆牌的背面，
	# 而 Label3D 是单面的 —— 字直接消失。
	K.label_cjk(g, "東口", Vector3(25.45, WALK_Y + 2.45, 5.255), 0.14,
		Color("#2b4a63"), Vector3(0, 180, 0))
	K.label(g, "BUS", Vector3(25.45, WALK_Y + 2.31, 5.255), 0.07,
		Color("#48657d"), Vector3(0, 180, 0))

	# 候车亭底下的暖灯
	K.sphere(g, 0.05, Vector3(24.35, WALK_Y + 2.44, 5.75), K.glow(Color("#ffe1b0"), 2.0),
		Vector3.ZERO, 8, 1.0, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffd0a0")
	l.light_energy = 0.65
	l.omni_range = 3.6
	l.position = Vector3(24.35, WALK_Y + 2.2, 5.7)
	g.add_child(l)


static func _convex_mirror(g: Node3D) -> void:
	var p := Vector3(26.45, WALK_Y, 1.92)
	var frame := K.toon(Color("#98402a"), {"shade": 0.5, "rim": 0.2, "line": 0.005})
	K.cyl(g, 0.045, 2.9, p + Vector3(0, 1.45, 0), frame, Vector3.ZERO, 8)
	K.box(g, Vector3(0.07, 0.07, 0.34), p + Vector3(0, 2.95, 0.16), frame, Vector3.ZERO, false)
	var mp := p + Vector3(0, 2.82, 0.3)
	K.torus(g, 0.15, 0.21, mp, K.toon(Color("#c25a1e"), {"shade": 0.5, "rim": 0.35, "line": 0.005}),
		Vector3(90, 0, 0))
	K.cyl(g, 0.175, 0.02, mp, K.pbr(Color("#7c8896"), 0.1, 0.9), Vector3(90, 0, 0), 20)
	K.cyl(g, 0.165, 0.01, mp + Vector3(0, 0, 0.014),
		K.toon(Color("#aebdca"), {"shade": 0.9, "rim": 0.6, "line": 0.0}), Vector3(90, 0, 0), 20)


static func _guardrail(g: Node3D) -> void:
	var rail := K.toon(Color("#83898f"), {"shade": 0.55, "rim": 0.3, "line": 0.005})
	var x := 17.0
	while x <= 21.2:
		K.cyl(g, 0.035, 0.86, Vector3(x, WALK_Y + 0.43, ROAD_Z1 + 0.06), rail, Vector3.ZERO, 8)
		x += 1.05
	K.strut(g, Vector3(16.8, WALK_Y + 0.82, ROAD_Z1 + 0.06),
		Vector3(21.4, WALK_Y + 0.82, ROAD_Z1 + 0.06), 0.032, rail, 8)
	K.strut(g, Vector3(16.8, WALK_Y + 0.5, ROAD_Z1 + 0.06),
		Vector3(21.4, WALK_Y + 0.5, ROAD_Z1 + 0.06), 0.028, rail, 8)


# ---------------------------------------------------------------- 湿地反光

static func _light_pools(g: Node3D) -> void:
	var grp := K.group(g, "LightPools")
	for spec in LAMPS:
		var arm: float = spec["arm"]
		K.plane(grp, Vector2(5.4, 5.4),
			Vector3(float(spec["x"]), 0.012, float(spec["z"]) + arm * 2.3),
			K.wet(Color("#ffb46a"), 0.09), Vector3.ZERO, false)
		K.plane(grp, Vector2(2.0, 2.0),
			Vector3(float(spec["x"]), WALK_Y + 0.006, float(spec["z"])),
			K.wet(Color("#ffd7a1"), 0.06), Vector3.ZERO, false)

	# 牌楼脚下的暖光 + 斑马线两侧的冷反光
	K.plane(grp, Vector2(5.0, 7.6), Vector3(GATE_X, 0.013, 2.7),
		K.wet(Color("#ffc07a"), 0.06), Vector3.ZERO, false)
	K.plane(grp, Vector2(3.2, 3.0), Vector3(GATE_X, WALK_Y + 0.007, 0.5),
		K.wet(Color("#ffd3a0"), 0.07), Vector3.ZERO, false)
	K.plane(grp, Vector2(3.0, 2.0), Vector3(GATE_X, WALK_Y + 0.007, 5.4),
		K.wet(Color("#ffd3a0"), 0.05), Vector3.ZERO, false)
	K.plane(grp, Vector2(9.0, 1.2), Vector3(23.2, 0.016, 2.85),
		K.wet(Color("#79a8ff"), 0.03), Vector3.ZERO, false)

	# 候车亭
	K.plane(grp, Vector2(2.6, 2.4), Vector3(24.35, WALK_Y + 0.007, 5.72),
		K.wet(Color("#ffcf9a"), 0.08), Vector3.ZERO, false)


# ---------------------------------------------------------------- 雨 / 涟漪

## 雨要停在这些平层上。旧场景写死在着色器里的表面表在矩形雨幕下会失效，
## 所以新场景把「整条街的接雨面」显式传给 world_env。
## 这里的 6 块是街道层；店面屋顶 / 雨棚由 shop_row.gd 追加。
static func rain_covers() -> Array:
	return [
		# 两侧人行道（含路缘石，顶面都是 0.16）
		{"x0": X0, "z0": Z0, "x1": X1, "z1": 2.07, "h": WALK_Y},
		{"x0": X0, "z0": 5.0, "x1": X1, "z1": SOUTH_WALK_Z1, "h": WALK_Y},
		# 便利店东侧后巷
		{"x0": 4.30, "z0": -5.5, "x1": 5.36, "z1": -0.55, "h": 0.19},
		# 便利店雨棚
		{"x0": -1.76, "z0": -0.96, "x1": 4.36, "z1": 0.2, "h": 2.66},
		# 便利店屋面
		{"x0": -1.77, "z0": -5.57, "x1": 4.37, "z1": -0.83, "h": 3.71},
		# 候车亭顶
		{"x0": 23.4, "z0": 5.28, "x1": 25.3, "z1": 6.22, "h": 2.63},
	]


## 湿地面涟漪。旧场景那 4 块里，马路 / 店前步道 / 后巷 / 店屋顶都在这里保留，
## 只是马路从 11.2m 方块拉成整条街；店前步道的干燥区仍然是便利店雨棚的投影。
static func ripples() -> Array:
	return [
		{"pos": Vector3(CENTER_X, 0.007, 3.535), "size": Vector2(35.2, 2.9),
			"strength": 0.36, "dry": false},
		{"pos": Vector3(CENTER_X, 0.168, 0.55), "size": Vector2(35.2, 2.9),
			"strength": 0.26, "dry": true,
			"dry_min": Vector2(-1.76, -0.96), "dry_max": Vector2(4.36, 0.2)},
		{"pos": Vector3(CENTER_X, 0.168, 5.72), "size": Vector2(35.2, 1.12),
			"strength": 0.24, "dry": false},
		{"pos": Vector3(1.3, 3.712, -3.2), "size": Vector2(6.0, 4.6),
			"strength": 0.3, "dry": false},
	]
