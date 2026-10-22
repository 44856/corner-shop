extends RefCounted
## 星见町商店街的两排店面。
##
## 北排（从西往东）：便利店（已有）→ 拉面 → 居酒屋 → 后巷缝隙 → 自助洗衣
##                   → 烟店 → 公寓 → 交番
## 南排：民居 → 投币停车场 → 民居 → 钱汤 → 公寓 → 喫茶店 → 洗衣店
##       → 诊所 → 口袋公园 → 街角民居
##
## 全部是「背景建筑」，不做可进入的室内：一层用发光橱窗、暖帘、卷帘门表达营业状态，
## 二层以上只做窗、外廊、空调外机和晾衣杆。碰撞由 town_collision.gd 按
## NORTH / SOUTH 两张表生成，别在这里另写一套尺寸。

const K := preload("res://scripts/kit.gd")
const Props := preload("res://scripts/props.gd")

const BASE := 0.16
const N_FRONT := -0.9
const N_BACK := -5.5
const S_FRONT := 6.3
const S_BACK := 9.6

## 建筑体块。h 是檐口 / 女儿墙的世界高度（不含坡屋顶）。
## 碰撞脚本直接遍历这两张表，所以「看得见的一间店」和「挡得住的一面墙」永远同源。
##
## 高度基准：角色胶囊 1.72m（player_controller.gd），二层店面檐口取 5.2~6.2m，
## 约等于「一层 2.8m + 二层 2.6m + 女儿墙」。初版普遍低 0.8~1.2m（檐口 4.0~5.4），
## 站在街上二层窗几乎与头顶齐平，整排房子像一套微缩模型，所以统一抬高。
## 一层门 / 雨棚 / 橱窗高度不动 —— 那些是 1.72m 的人直接对照的尺寸。
const NORTH := [
	{"name": "ramen", "x0": 5.6, "x1": 9.8, "h": 6.2},
	{"name": "izakaya", "x0": 9.8, "x1": 13.0, "h": 5.6},
	{"name": "laundry", "x0": 14.2, "x1": 18.0, "h": 5.2},
	{"name": "tobacco", "x0": 18.0, "x1": 20.8, "h": 5.8},
	{"name": "apartment", "x0": 20.8, "x1": 24.4, "h": 8.8},
	{"name": "koban", "x0": 24.4, "x1": 26.9, "h": 5.0},
]
const SOUTH := [
	{"name": "house_a", "x0": -5.0, "x1": -1.0, "h": 5.4},
	{"name": "house_b", "x0": 3.2, "x1": 6.4, "h": 6.0},
	{"name": "sento", "x0": 6.4, "x1": 10.6, "h": 6.2},
	{"name": "apartment_s", "x0": 10.6, "x1": 14.4, "h": 8.0},
	{"name": "coffee", "x0": 14.4, "x1": 17.6, "h": 4.9},
	{"name": "cleaner", "x0": 17.6, "x1": 20.4, "h": 5.6},
	{"name": "clinic", "x0": 20.4, "x1": 23.0, "h": 5.2},
	{"name": "corner_house", "x0": 27.0, "x1": 30.0, "h": 6.4},
]

## 雨棚：既是几何，也是雨和涟漪的覆盖区。坐标是世界 xz + 世界高度 y。
const AWNINGS := [
	{"x0": 5.75, "x1": 9.65, "z0": -0.92, "z1": -0.32, "h": 2.78, "owner": "ramen",
		"col": Color("#3a3f46"), "stripe": Color("#d9c9a6")},
	{"x0": 9.95, "x1": 12.85, "z0": -0.92, "z1": -0.35, "h": 2.62, "owner": "izakaya",
		"col": Color("#2f3a33"), "stripe": Color("#c9b98e")},
	{"x0": 14.35, "x1": 17.85, "z0": -0.92, "z1": -0.34, "h": 2.72, "owner": "laundry",
		"col": Color("#c9d9dc"), "stripe": Color("#7fa9bb")},
	{"x0": 18.15, "x1": 20.65, "z0": -0.92, "z1": -0.34, "h": 2.66, "owner": "tobacco",
		"col": Color("#7a2c28"), "stripe": Color("#e3d3ad")},
	{"x0": 24.55, "x1": 26.75, "z0": -0.92, "z1": -0.38, "h": 2.62, "owner": "koban",
		"col": Color("#2e4666"), "stripe": Color("#e3dcc4")},
	{"x0": 14.55, "x1": 17.45, "z0": 5.70, "z1": 6.30, "h": 2.72, "owner": "coffee",
		"col": Color("#3d553f"), "stripe": Color("#e3d3ad")},
	{"x0": 6.55, "x1": 10.45, "z0": 5.68, "z1": 6.30, "h": 2.86, "owner": "sento",
		"col": Color("#2f3f5a"), "stripe": Color("#d8c9a2")},
]

const WARM := Color("#ffd39a")
const COOL := Color("#dcefff")


static func build(root: Node3D) -> void:
	var g := K.group(root, "ShopRow")
	_north_row(g)
	_south_row(g)


static func rain_covers() -> Array:
	var out: Array = []
	for b in NORTH:
		out.append({"x0": b["x0"], "z0": N_BACK, "x1": b["x1"], "z1": N_FRONT, "h": b["h"]})
	for b in SOUTH:
		if b["name"] == "corner_house":
			out.append({"x0": 27.0, "z0": 7.3, "x1": 30.0, "z1": 9.6, "h": b["h"]})
		else:
			out.append({"x0": b["x0"], "z0": S_FRONT, "x1": b["x1"], "z1": S_BACK, "h": b["h"]})
	for a in AWNINGS:
		out.append({"x0": a["x0"], "z0": a["z0"], "x1": a["x1"], "z1": a["z1"], "h": a["h"]})
	# 公寓最高一层外廊。雨落在廊板上，不会穿进走廊。
	out.append({"x0": 20.8, "z0": N_FRONT, "x1": 24.4, "z1": -0.32, "h": 8.25})
	return out


static func ripples() -> Array:
	var out: Array = []
	for a in AWNINGS:
		var cx := (float(a["x0"]) + float(a["x1"])) * 0.5
		var cz := (float(a["z0"]) + float(a["z1"])) * 0.5
		out.append({
			"pos": Vector3(cx, float(a["h"]) + 0.004, cz),
			"size": Vector2(float(a["x1"]) - float(a["x0"]) - 0.1,
				absf(float(a["z1"]) - float(a["z0"])) - 0.06),
			"strength": 0.22, "dry": false,
		})
	# 顶层外廊
	out.append({"pos": Vector3(22.6, 8.254, -0.61), "size": Vector2(3.45, 0.52),
		"strength": 0.24, "dry": false})
	return out


# ---------------------------------------------------------------- 北排

static func _north_row(g: Node3D) -> void:
	_ramen(g)
	_izakaya(g)
	_gap(g)
	_laundry(g)
	_tobacco(g)
	_apartment(g)
	_koban(g)


static func _ramen(g: Node3D) -> void:
	var x0 := 5.6
	var x1 := 9.8
	var cx := 7.7
	_block(g, x0, x1, 6.2, N_FRONT, N_BACK, Color("#6c5642"), Color("#8a6b4c"))
	# 一楼：拉门 + 两侧木格窗，暖光从窗里漏出来
	_entrance(g, cx, N_FRONT + 0.02, 1.4, 2.25, 1.0, Color("#4a3325"),
		Color("#2a2119"), WARM)
	_window(g, 6.35, 1.55, N_FRONT + 0.02, 1.1, 1.05, WARM, 0.85, 1.0)
	_window(g, 9.05, 1.55, N_FRONT + 0.02, 1.1, 1.05, WARM, 0.85, 1.0)
	# 二楼
	_window(g, 6.33, 4.60, N_FRONT + 0.02, 1.3, 1.05, WARM, 0.5, 1.0)
	_window(g, 9.07, 4.60, N_FRONT + 0.02, 1.3, 1.05, WARM, 0.45, 1.0)
	_awning(g, AWNINGS[0])
	_noren(g, cx, 2.06, -0.52, 1.65, 0.62, Color("#b8442f"), "ラーメン", 1.0)
	_lit_sign(g, "麺処 星見", Vector3(cx, 3.42, N_FRONT - 0.01), 3.1, 0.6,
		Color("#f2e4c4"), Color("#5a2a1c"), 1.0, 1.0)
	_vert_sign(g, "ラーメン", 9.56, 5.85, N_FRONT - 0.02, 2.3, 0.4,
		Color("#8f2f27"), Color("#ffe8c4"), 1.0, 0.8)
	_warm_light(g, Vector3(cx, 2.5, -0.42), Color("#ffcf96"), 1.05, 4.6)
	_menu_board(g, 5.95, 0.34, -16.0, "らーめん\n¥780")
	_pot(g, 9.46, 0.18, 0.9)
	_ac(g, 9.15, 5.35, N_FRONT + 0.16, 1.0)
	# 门前的暖光池，和便利店雨棚下的那一块接上
	K.plane(g, Vector2(3.9, 1.6), Vector3(cx, BASE + 0.006, 0.25),
		K.wet(Color("#ffcf9a"), 0.09), Vector3.ZERO, false)


static func _izakaya(g: Node3D) -> void:
	var x0 := 9.8
	var x1 := 13.0
	var cx := 11.4
	_block(g, x0, x1, 5.6, N_FRONT, N_BACK, Color("#5b3f2d"), Color("#74513a"))
	_entrance(g, cx, N_FRONT + 0.02, 1.15, 2.2, 1.0, Color("#3b2a1e"),
		Color("#241b14"), WARM)
	_window(g, 10.35, 1.62, N_FRONT + 0.02, 0.9, 0.9, WARM, 0.9, 1.0)
	_window(g, 12.45, 1.62, N_FRONT + 0.02, 0.9, 0.9, WARM, 0.9, 1.0)
	_window(g, 10.55, 4.25, N_FRONT + 0.02, 0.9, 0.8, WARM, 0.35, 1.0)
	_window(g, 12.25, 4.25, N_FRONT + 0.02, 0.9, 0.8, WARM, 0.35, 1.0)
	_awning(g, AWNINGS[1])
	_noren(g, cx, 2.0, -0.55, 1.35, 0.6, Color("#2f3f5a"), "酒処", 1.0)
	_lantern(g, Vector3(10.18, 2.24, -0.5), Color("#d8462f"), "酒")
	_lantern(g, Vector3(12.62, 2.24, -0.5), Color("#d8462f"), "酒")
	_lit_sign(g, "居酒屋 ほし", Vector3(cx, 3.18, N_FRONT - 0.01), 2.5, 0.52,
		Color("#f0e4c8"), Color("#4a2318"), 1.0, 0.85)
	_vert_sign(g, "居酒屋", 12.76, 5.2, N_FRONT - 0.02, 1.7, 0.38,
		Color("#6b2a22"), Color("#ffe4b8"), 1.0, 0.7)
	_warm_light(g, Vector3(cx, 2.4, -0.4), Color("#ffc17e"), 0.8, 4.2)
	_menu_board(g, 12.05, 0.32, 12.0, "本日のおすすめ\n焼き鳥  ¥180")
	_ac(g, 10.25, 4.7, N_FRONT + 0.16, 1.0)


static func _gap(g: Node3D) -> void:
	# 两栋楼之间 1.2m 的缝隙：贩卖机、啤酒箱、垃圾袋。
	# 这是整条北排唯一能看见建筑侧墙的地方，故意不封死。
	var wall := K.toon(Color("#5a5d61"), {"shade": 0.5, "rim": 0.15, "line": 0.008})
	K.box(g, Vector3(1.2, 3.2, 0.24), Vector3(13.6, BASE + 1.6, -4.35), wall)
	K.box(g, Vector3(1.2, 0.05, 2.9), Vector3(13.6, BASE + 0.02, -2.6),
		K.paving(Color("#3d4047"), Color("#34373d"), 0.55), Vector3.ZERO, false)
	Props.vending(g, Vector3(13.6, BASE, -0.58), 0.0)

	# 啤酒箱：两层，靠东墙，不挡贩卖机
	var crate := K.toon(Color("#8a6d22"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	for i in 2:
		K.box(g, Vector3(0.42, 0.28, 0.34), Vector3(13.34, BASE + 0.14 + i * 0.29, -1.75), crate)
	for i in 2:
		K.box(g, Vector3(0.42, 0.28, 0.34), Vector3(13.34, BASE + 0.14 + i * 0.29, -2.08), crate)
	# 垃圾袋
	var bag := K.toon(Color("#24282f"), {"shade": 0.45, "rim": 0.4, "line": 0.005})
	for d in [[Vector3(13.25, BASE + 0.15, -2.48), 0.16],
			[Vector3(13.72, BASE + 0.14, -2.55), 0.14],
			[Vector3(13.46, BASE + 0.12, -2.9), 0.12]]:
		var s := K.sphere(g, d[1], d[0], bag, Vector3.ZERO, 10, 1.15)
		s.scale = Vector3(1.0, 1.0, 0.95)
	# 侧墙上的落水管与壁灯
	var pipe := K.toon(Color("#767b82"), {"shade": 0.5, "rim": 0.3, "line": 0.004})
	K.cyl(g, 0.03, 3.2, Vector3(13.06, BASE + 1.6, -3.4), pipe, Vector3.ZERO, 8)
	K.cyl(g, 0.03, 3.2, Vector3(14.14, BASE + 1.6, -3.2), pipe, Vector3.ZERO, 8)
	# 一盏防犯灯，把缝隙从「黑洞」变成「有生活气」
	K.box(g, Vector3(0.16, 0.08, 0.2), Vector3(13.05, 2.72, -2.25),
		K.toon(Color("#33383e"), {"line": 0.004}))
	K.sphere(g, 0.055, Vector3(13.14, 2.66, -2.25), K.glow(Color("#ffd8a4"), 2.0),
		Vector3.ZERO, 8, 1.0, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffcf96")
	l.light_energy = 0.55
	l.omni_range = 3.0
	l.position = Vector3(13.3, 2.5, -2.25)
	g.add_child(l)


static func _laundry(g: Node3D) -> void:
	var x0 := 14.2
	var x1 := 18.0
	var cx := 16.1
	_block(g, x0, x1, 5.2, N_FRONT, N_BACK, Color("#8d918f"), Color("#b8bcb8"))
	# 整面落地玻璃：这条街最亮的一块冷光
	var glass := K.glass(Color(0.72, 0.88, 0.95, 0.1), 0.3)
	K.box(g, Vector3(2.9, 1.75, 0.06), Vector3(cx, BASE + 1.35, N_FRONT + 0.03), glass,
		Vector3.ZERO, false)
	for px in [14.75, 16.1, 17.45]:
		K.box(g, Vector3(0.07, 1.85, 0.12), Vector3(px, BASE + 1.35, N_FRONT + 0.04),
			K.toon(Color("#2b3138"), {"line": 0.005}))
	K.box(g, Vector3(2.95, 0.09, 0.12), Vector3(cx, BASE + 2.25, N_FRONT + 0.04),
		K.toon(Color("#2b3138"), {"line": 0.005}))
	K.box(g, Vector3(2.95, 0.09, 0.12), Vector3(cx, BASE + 0.47, N_FRONT + 0.04),
		K.toon(Color("#2b3138"), {"line": 0.005}))
	K.box(g, Vector3(2.82, 0.02, 0.05), Vector3(cx, BASE + 1.04, N_FRONT + 0.02),
		K.glow(COOL, 1.1), Vector3.ZERO, false)

	# 玻璃后面的滚筒洗衣机：四台，圆窗朝街
	var washer := K.toon(Color("#d7dadd"), {"shade": 0.62, "rim": 0.2, "line": 0.005})
	var drum := K.toon(Color("#2c3942"), {"shade": 0.8, "line": 0.003})
	for i in 4:
		var px := 15.05 + i * 0.7
		K.box(g, Vector3(0.62, 0.72, 0.1), Vector3(px, BASE + 0.86, N_FRONT + 0.015), washer,
			Vector3.ZERO, false)
		K.cyl(g, 0.23, 0.03, Vector3(px, BASE + 0.86, N_FRONT + 0.08), drum,
			Vector3(90, 0, 0), 18, -1.0, false)
		K.cyl(g, 0.16, 0.02, Vector3(px, BASE + 0.86, N_FRONT + 0.095),
			K.glow(Color("#bfe8ff"), 0.6), Vector3(90, 0, 0), 16, -1.0, false)
		K.box(g, Vector3(0.3, 0.06, 0.02), Vector3(px, BASE + 1.2, N_FRONT + 0.1),
			K.glow(Color("#7fe0ff"), 0.7), Vector3.ZERO, false)

	# 二层原本整面留白，抬高层高后会变成一整块灰墙；补两扇冷光小窗压住体量
	_window(g, 15.25, 4.15, N_FRONT + 0.02, 1.0, 0.9, COOL, 0.3, 1.0)
	_window(g, 16.95, 4.15, N_FRONT + 0.02, 1.0, 0.9, COOL, 0.25, 1.0)
	_awning(g, AWNINGS[2])
	_lit_sign(g, "コインランドリー", Vector3(cx, 3.28, N_FRONT - 0.01), 3.2, 0.55,
		Color("#eaf6ff"), Color("#1e4f6e"), 1.0, 1.35)
	_vert_sign(g, "24H", 17.68, 4.95, N_FRONT - 0.02, 1.2, 0.36,
		Color("#eaf6ff"), Color("#1e4f6e"), 1.0, 1.2)
	_warm_light(g, Vector3(cx, 2.5, -0.4), Color("#cfeaff"), 1.15, 5.0)
	K.plane(g, Vector2(4.4, 1.9), Vector3(cx, BASE + 0.006, 0.35),
		K.wet(Color("#bfe6ff"), 0.09), Vector3.ZERO, false)
	# 门口的长凳：等洗衣的人坐的地方
	K.box(g, Vector3(1.3, 0.06, 0.32), Vector3(14.8, BASE + 0.44, 0.12),
		K.toon(Color("#6b6f74"), {"shade": 0.6, "rim": 0.2, "line": 0.005}))
	for px in [14.25, 15.35]:
		K.box(g, Vector3(0.05, 0.42, 0.28), Vector3(px, BASE + 0.21, 0.12),
			K.toon(Color("#3a3e45"), {"line": 0.004}))


static func _tobacco(g: Node3D) -> void:
	var x0 := 18.0
	var x1 := 20.8
	var cx := 19.4
	_block(g, x0, x1, 5.8, N_FRONT, N_BACK, Color("#6a5c46"), Color("#8f7d60"))
	_shutter(g, 18.95, N_FRONT + 0.02, 1.7, 2.25, 1.0, Color("#59616a"))
	_window(g, 20.1, 1.55, N_FRONT + 0.02, 0.85, 1.0, WARM, 1.0, 1.0)
	_window(g, 18.6, 4.40, N_FRONT + 0.02, 1.1, 0.9, WARM, 0.3, 1.0)
	_window(g, 20.0, 4.40, N_FRONT + 0.02, 1.1, 0.9, WARM, 0.3, 1.0)
	_awning(g, AWNINGS[3])
	_lit_sign(g, "たばこ", Vector3(cx, 3.25, N_FRONT - 0.01), 2.2, 0.58,
		Color("#f1e6cd"), Color("#a12b22"), 1.0, 1.0)
	_vert_sign(g, "煙草", 20.62, 5.45, N_FRONT - 0.02, 1.6, 0.4,
		Color("#f1e6cd"), Color("#a12b22"), 1.0, 0.9)
	_warm_light(g, Vector3(cx, 2.45, -0.38), Color("#ffcf96"), 0.65, 3.8)
	_pot(g, 18.22, 0.16, 1.0)
	_ac(g, 20.55, 4.70, N_FRONT + 0.16, 1.0)


static func _apartment(g: Node3D) -> void:
	var x0 := 20.8
	var x1 := 24.4
	var cx := 22.6
	_block(g, x0, x1, 8.8, N_FRONT, N_BACK, Color("#707780"), Color("#8e959d"))

	# 三层外廊：板 + 栏杆 + 每户的门。这是日本公寓最好认的轮廓。
	for i in 3:
		var top := 3.0 + i * 2.6
		K.box(g, Vector3(3.5, 0.13, 0.62), Vector3(cx, top - 0.065, -0.59),
			K.toon(Color("#9aa1a8"), {"shade": 0.55, "rim": 0.25, "line": 0.006}))
		# 栏杆
		var rail := K.toon(Color("#5b626a"), {"shade": 0.6, "rim": 0.2, "line": 0.004})
		K.strut(g, Vector3(20.9, top + 0.9, -0.31), Vector3(24.3, top + 0.9, -0.31),
			0.025, rail, 6, false)
		K.strut(g, Vector3(20.9, top + 0.45, -0.31), Vector3(24.3, top + 0.45, -0.31),
			0.018, rail, 6, false)
		var px := 20.95
		while px < 24.35:
			K.box(g, Vector3(0.02, 0.9, 0.02), Vector3(px, top + 0.45, -0.31), rail,
				Vector3.ZERO, false)
			px += 0.38
		# 门与门牌灯
		for dx in [21.45, 22.6, 23.75]:
			K.box(g, Vector3(0.82, 2.0, 0.06), Vector3(dx, top + 1.1, N_FRONT + 0.02),
				K.toon(Color("#4a4138"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
			K.box(g, Vector3(0.55, 0.5, 0.02), Vector3(dx, top + 1.6, N_FRONT + 0.055),
				K.toon(Color("#6f6557"), {"line": 0.003}), Vector3.ZERO, false)
			K.sphere(g, 0.045, Vector3(dx + 0.3, top + 1.95, N_FRONT + 0.07),
				K.glow(Color("#ffd9a0"), 1.2), Vector3.ZERO, 8, 1.0, false)
			# 走廊顶灯（每层两盏）
		for lx in [21.3, 23.9]:
			K.box(g, Vector3(0.24, 0.05, 0.14), Vector3(lx, top + 2.2, -0.5),
				K.glow(Color("#ffe2b4"), 0.9), Vector3.ZERO, false)

	# 一层入口
	_entrance(g, 22.6, N_FRONT + 0.02, 1.1, 2.2, 1.0, Color("#3e3a34"),
		Color("#25221e"), WARM)
	K.box(g, Vector3(2.0, 0.07, 0.7), Vector3(22.6, 2.5, -0.55),
		K.toon(Color("#3a4047"), {"shade": 0.55, "line": 0.005}))
	_lit_sign(g, "星見ハイツ", Vector3(22.6, 2.82, N_FRONT - 0.01), 1.8, 0.36,
		Color("#e6e2d5"), Color("#3a3e44"), 1.0, 0.55)
	# 信箱
	for i in 4:
		K.box(g, Vector3(0.22, 0.16, 0.12), Vector3(21.45 + i * 0.25, 1.25, -0.78),
			K.toon(Color("#7f858b"), {"line": 0.003}), Vector3.ZERO, false)
	_warm_light(g, Vector3(22.6, 2.25, -0.35), Color("#ffcf96"), 0.65, 4.0)
	_ac(g, 21.15, 4.45, N_FRONT + 0.16, 1.0)
	_ac(g, 23.95, 7.05, N_FRONT + 0.16, 1.0)


static func _koban(g: Node3D) -> void:
	var x0 := 24.4
	var x1 := 26.9
	var cx := 25.65
	_block(g, x0, x1, 5.0, N_FRONT, N_BACK, Color("#b9b2a0"), Color("#d8d1bd"))
	_entrance(g, 25.55, N_FRONT + 0.02, 1.15, 2.2, 1.0, Color("#b9c9cc"),
		Color("#454c52"), COOL)
	_window(g, 24.95, 1.6, N_FRONT + 0.02, 0.9, 1.0, COOL, 1.1, 1.0)
	_window(g, 26.35, 1.6, N_FRONT + 0.02, 0.9, 1.0, COOL, 1.1, 1.0)
	_awning(g, AWNINGS[4])
	_lit_sign(g, "交番", Vector3(cx, 3.2, N_FRONT - 0.01), 1.7, 0.52,
		Color("#f2ede0"), Color("#1d3d6b"), 1.0, 0.85)
	_vert_sign(g, "交番", 26.67, 4.85, N_FRONT - 0.02, 1.1, 0.34,
		Color("#f2ede0"), Color("#1d3d6b"), 1.0, 0.8)
	# 青灯：交番的标志。灯本身不大，靠 soft 晕开一圈。
	K.sphere(g, 0.11, Vector3(25.55, 4.55, -0.62), K.glow(Color("#7fb4ff"), 2.6),
		Vector3.ZERO, 12, 1.0, false)
	K.sphere(g, 0.42, Vector3(25.55, 4.55, -0.62), K.soft(Color("#6fa8ff"), 0.45, 1.8),
		Vector3.ZERO, 12, 1.0, false)
	var bl := OmniLight3D.new()
	bl.light_color = Color("#7fb4ff")
	bl.light_energy = 0.7
	bl.omni_range = 4.0
	bl.position = Vector3(25.55, 4.4, -0.35)
	g.add_child(bl)
	_warm_light(g, Vector3(cx, 2.35, -0.35), Color("#dff0ff"), 0.8, 4.2)
	_menu_board(g, 24.62, 0.32, -8.0, "落とし物\n相談窓口")


# ---------------------------------------------------------------- 南排

static func _south_row(g: Node3D) -> void:
	_house_a(g)
	_parking(g)
	_house_b(g)
	_sento(g)
	_apartment_s(g)
	_coffee(g)
	_cleaner(g)
	_clinic(g)
	_pocket_park(g)
	_corner_house(g)


static func _house_a(g: Node3D) -> void:
	var x0 := -5.0
	var x1 := -1.0
	var cx := -3.0
	_block(g, x0, x1, 5.4, S_FRONT, S_BACK, Color("#8a7a68"), Color("#a08d78"))
	_gable(g, cx, S_FRONT, S_BACK, x1 - x0, 5.4, 1.2, Color("#34383f"))
	_window(g, -3.45, 1.55, S_FRONT - 0.02, 1.0, 1.0, WARM, 0.75, -1.0)
	_window(g, -3.25, 4.15, S_FRONT - 0.02, 1.15, 1.0, WARM, 0.4, -1.0)
	_entrance(g, -2.15, S_FRONT - 0.02, 0.9, 2.1, -1.0, Color("#5a4030"),
		Color("#2e251d"), WARM)
	# 门廊灯
	K.sphere(g, 0.05, Vector3(-2.15, 2.28, S_FRONT - 0.12), K.glow(Color("#ffd9a0"), 1.6),
		Vector3.ZERO, 8, 1.0, false)
	_warm_light(g, Vector3(-2.15, 2.1, S_FRONT - 0.5), Color("#ffcf96"), 0.5, 3.0)
	_pot(g, -4.65, S_FRONT - 0.32, 1.0)
	K.plane(g, Vector2(3.0, 1.1), Vector3(cx, BASE + 0.006, S_FRONT - 0.35),
		K.wet(Color("#ffcf9a"), 0.05), Vector3.ZERO, false)


static func _parking(g: Node3D) -> void:
	# 投币停车场：没有建筑，只有地面、白线、一辆轻自动车和计费机。
	var cx := 1.1
	# 顶面压到人行道同一高度（0.16）：停车场是走进来的，1cm 的视觉台阶
	# 在无自动上台阶的角色身上就是一道看不见的墙。
	K.box(g, Vector3(4.2, 0.02, 3.3), Vector3(cx, BASE - 0.01, 7.95),
		K.paving(Color("#3c4047"), Color("#34383e"), 0.7), Vector3.ZERO, false)
	var paint := K.toon(Color("#b9bdb4"), {"shade": 0.65, "rim": 0.1, "line": 0.0})
	for i in 4:
		var px := -0.8 + i * 1.2
		K.plane(g, Vector2(0.06, 2.9), Vector3(px, BASE + 0.006, 7.95), paint,
			Vector3.ZERO, false)
	K.plane(g, Vector2(4.0, 0.06), Vector3(cx, BASE + 0.006, 9.38), paint, Vector3.ZERO, false)
	# 轮挡
	for px in [-0.2, 1.0, 2.2]:
		K.box(g, Vector3(0.7, 0.1, 0.16), Vector3(px, BASE + 0.07, 8.95),
			K.toon(Color("#8b8f94"), {"line": 0.004}))
	Props.kei_van(g, Vector3(1.55, BASE, 8.15), 0.0)

	# 计费机 + 招牌
	var steel := K.toon(Color("#5c626a"), {"shade": 0.55, "rim": 0.25, "line": 0.005})
	K.box(g, Vector3(0.34, 1.25, 0.3), Vector3(-0.55, BASE + 0.625, 6.7), steel)
	K.box(g, Vector3(0.22, 0.36, 0.02), Vector3(-0.55, BASE + 0.92, 6.86),
		K.glow(Color("#9fe0ff"), 0.8), Vector3.ZERO, false)
	K.cyl(g, 0.04, 2.3, Vector3(2.85, BASE + 1.15, 6.55), steel, Vector3.ZERO, 8)
	K.box(g, Vector3(0.9, 0.62, 0.06), Vector3(2.85, BASE + 2.2, 6.55),
		K.toon(Color("#1b4a72"), {"shade": 0.6, "rim": 0.3, "line": 0.005}))
	K.label(g, "P 24H", Vector3(2.85, BASE + 2.24, 6.585), 0.2, Color("#ffffff"))
	K.label(g, "COIN PARKING", Vector3(2.85, BASE + 2.05, 6.585), 0.075, Color("#cfe3f2"))

	# 场地后方的矮墙，给停车场一个边界
	K.box(g, Vector3(4.2, 1.2, 0.24), Vector3(cx, BASE + 0.6, 9.55),
		K.toon(Color("#55595f"), {"shade": 0.5, "rim": 0.15, "line": 0.007}))


static func _house_b(g: Node3D) -> void:
	var x0 := 3.2
	var x1 := 6.4
	var cx := 4.8
	_block(g, x0, x1, 6.0, S_FRONT, S_BACK, Color("#7e6a58"), Color("#9a8068"))
	# 二层小阳台
	K.box(g, Vector3(2.1, 0.1, 0.55), Vector3(4.65, 3.85, S_FRONT - 0.27),
		K.toon(Color("#8d9196"), {"shade": 0.6, "rim": 0.2, "line": 0.005}))
	var rail := K.toon(Color("#5b626a"), {"shade": 0.6, "line": 0.004})
	K.strut(g, Vector3(3.65, 4.70, S_FRONT - 0.52), Vector3(5.65, 4.70, S_FRONT - 0.52),
		0.022, rail, 6, false)
	var px := 3.7
	while px < 5.7:
		K.box(g, Vector3(0.02, 0.85, 0.02), Vector3(px, 4.27, S_FRONT - 0.52), rail,
			Vector3.ZERO, false)
		px += 0.36
	_window(g, 4.05, 1.6, S_FRONT - 0.02, 0.9, 1.0, WARM, 0.7, -1.0)
	_window(g, 5.55, 1.6, S_FRONT - 0.02, 0.9, 1.0, WARM, 0.55, -1.0)
	_window(g, 4.65, 4.90, S_FRONT - 0.02, 1.7, 1.0, WARM, 0.4, -1.0)
	_entrance(g, 5.95, S_FRONT - 0.02, 0.8, 2.05, -1.0, Color("#4a3b2c"),
		Color("#2b241d"), WARM)
	_ac(g, 3.55, 4.75, S_FRONT - 0.15, -1.0)
	_pot(g, 3.4, S_FRONT - 0.28, 1.1)
	_warm_light(g, Vector3(5.95, 2.1, S_FRONT - 0.45), Color("#ffcf96"), 0.45, 3.0)


static func _sento(g: Node3D) -> void:
	var x0 := 6.4
	var x1 := 10.6
	var cx := 8.5
	_block(g, x0, x1, 6.2, S_FRONT, S_BACK, Color("#8e8478"), Color("#a89d8e"))
	_gable(g, cx, S_FRONT, S_BACK, x1 - x0, 6.2, 1.4, Color("#2f343c"))
	# 入口：木门 + 暖帘
	_entrance(g, cx, S_FRONT - 0.02, 1.5, 2.4, -1.0, Color("#4f3826"),
		Color("#33251a"), WARM)
	_noren(g, cx, 2.15, S_FRONT - 0.12, 1.5, 0.66, Color("#2f3f5a"), "ゆ", -1.0)
	_window(g, 7.25, 1.72, S_FRONT - 0.02, 0.85, 0.8, WARM, 0.5, -1.0)
	_window(g, 9.75, 1.72, S_FRONT - 0.02, 0.85, 0.8, WARM, 0.5, -1.0)
	# 浴室高窗：钱汤二层不需要房间，但整面墙空着会显得屋顶飘着
	_window(g, 7.30, 4.60, S_FRONT - 0.02, 0.9, 0.7, WARM, 0.3, -1.0)
	_window(g, 9.70, 4.60, S_FRONT - 0.02, 0.9, 0.7, WARM, 0.3, -1.0)
	_awning(g, AWNINGS[6])
	_lit_sign(g, "星見湯", Vector3(cx, 3.48, S_FRONT - 0.01), 2.1, 0.54,
		Color("#f3e6c8"), Color("#3a2a1c"), -1.0, 0.85)
	_vert_sign(g, "銭湯", 6.62, 5.40, S_FRONT - 0.02, 1.55, 0.4,
		Color("#f3e6c8"), Color("#3a2a1c"), -1.0, 0.7)
	# 烟囱：必须始终高出屋脊（墙顶 6.2 + 屋顶 1.4 = 7.6）
	var brick := K.toon(Color("#5a4a42"), {"shade": 0.5, "rim": 0.2, "line": 0.006})
	K.cyl(g, 0.34, 8.6, Vector3(10.12, BASE + 4.3, 8.55), brick, Vector3.ZERO, 12)
	for y in [3.6, 5.8, 8.0]:
		K.cyl(g, 0.38, 0.12, Vector3(10.12, BASE + y, 8.55),
			K.toon(Color("#463a34"), {"line": 0.004}), Vector3.ZERO, 12)
	# 烟囱口的热气：三团soft，静态即可，比粒子便宜
	K.sphere(g, 0.45, Vector3(10.12, 9.9, 8.55), K.soft(Color("#dce8f2"), 0.1, 1.5),
		Vector3.ZERO, 12, 0.9, false)
	K.sphere(g, 0.62, Vector3(10.0, 10.5, 8.4), K.soft(Color("#dce8f2"), 0.07, 1.5),
		Vector3.ZERO, 12, 0.9, false)
	_warm_light(g, Vector3(cx, 2.25, S_FRONT - 0.45), Color("#ffcf96"), 0.8, 4.5)
	# 门口的长椅和木桶
	K.box(g, Vector3(1.2, 0.07, 0.34), Vector3(9.7, BASE + 0.46, S_FRONT - 0.45),
		K.toon(Color("#5a4028"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	K.cyl(g, 0.22, 0.5, Vector3(6.75, BASE + 0.25, S_FRONT - 0.45),
		K.toon(Color("#6d5234"), {"shade": 0.55, "line": 0.005}), Vector3.ZERO, 12)


static func _apartment_s(g: Node3D) -> void:
	var x0 := 10.6
	var x1 := 14.4
	var cx := 12.5
	_block(g, x0, x1, 8.0, S_FRONT, S_BACK, Color("#6e747c"), Color("#8b929b"))
	# 三层按 2.45m 层高排：初版 2.0m 一层，三层公寓只有 7m，窗台挤在一起
	for i in 3:
		var y := 1.70 + i * 2.45
		for px in [11.25, 12.45, 13.65]:
			_window(g, px, y, S_FRONT - 0.02, 0.82, 0.85, WARM if (i + int(px)) % 2 == 0 else COOL,
				0.55 if i < 2 else 0.35, -1.0)
		if i > 0:
			# 二、三层的小阳台
			K.box(g, Vector3(1.2, 0.08, 0.42), Vector3(12.45, y - 0.48, S_FRONT - 0.21),
				K.toon(Color("#8d9196"), {"shade": 0.6, "line": 0.005}))
			K.strut(g, Vector3(11.9, y - 0.02, S_FRONT - 0.4),
				Vector3(13.0, y - 0.02, S_FRONT - 0.4), 0.02,
				K.toon(Color("#5b626a"), {"line": 0.004}), 6, false)
	_entrance(g, 13.6, S_FRONT - 0.02, 0.9, 2.1, -1.0, Color("#4c4f54"),
		Color("#2b2d31"), WARM)
	_lit_sign(g, "メゾン星見", Vector3(12.0, 2.72, S_FRONT - 0.01), 1.6, 0.3,
		Color("#e4e0d4"), Color("#3a3e44"), -1.0, 0.4)
	_warm_light(g, Vector3(13.6, 2.0, S_FRONT - 0.4), Color("#ffcf96"), 0.4, 2.8)
	_ac(g, 11.1, 4.95, S_FRONT - 0.15, -1.0)
	_ac(g, 14.05, 7.35, S_FRONT - 0.15, -1.0)


static func _coffee(g: Node3D) -> void:
	var x0 := 14.4
	var x1 := 17.6
	var cx := 16.0
	_block(g, x0, x1, 4.9, S_FRONT, S_BACK, Color("#6e4e3a"), Color("#8a6549"))
	# 大玻璃窗，室内暖光
	_window(g, 15.55, 1.55, S_FRONT - 0.02, 1.75, 1.35, WARM, 1.15, -1.0)
	_entrance(g, 17.05, S_FRONT - 0.02, 0.85, 2.05, -1.0, Color("#4a3424"),
		Color("#2b2018"), WARM)
	# 窗内吊灯（贴在玻璃后的两个亮点）
	for px in [15.05, 16.05]:
		K.sphere(g, 0.07, Vector3(px, 2.1, S_FRONT - 0.1), K.glow(Color("#ffd9a0"), 2.0),
			Vector3.ZERO, 8, 1.0, false)
	_awning(g, AWNINGS[5])
	_lit_sign(g, "喫茶 星屑", Vector3(cx, 3.05, S_FRONT - 0.01), 2.35, 0.5,
		Color("#f3e3c3"), Color("#4a2a1a"), -1.0, 1.05)
	# 招牌上方补一扇二层窗，让加高后的檐口有落点
	_window(g, 15.55, 4.10, S_FRONT - 0.02, 1.2, 0.8, WARM, 0.4, -1.0)
	_vert_sign(g, "COFFEE", 14.62, 4.45, S_FRONT - 0.02, 1.25, 0.34,
		Color("#f3e3c3"), Color("#4a2a1a"), -1.0, 0.7)
	_warm_light(g, Vector3(cx, 2.35, S_FRONT - 0.4), Color("#ffcf96"), 0.9, 4.2)
	# 门外的一张小桌
	K.cyl(g, 0.03, 0.65, Vector3(14.85, BASE + 0.325, S_FRONT - 0.55),
		K.toon(Color("#3a3e44"), {"line": 0.004}), Vector3.ZERO, 8)
	K.cyl(g, 0.28, 0.04, Vector3(14.85, BASE + 0.67, S_FRONT - 0.55),
		K.toon(Color("#8a6a4a"), {"shade": 0.6, "line": 0.005}), Vector3.ZERO, 16)
	_pot(g, 17.35, S_FRONT - 0.3, 0.9)
	K.plane(g, Vector2(2.5, 1.0), Vector3(cx, BASE + 0.006, S_FRONT - 0.35),
		K.wet(Color("#ffcf9a"), 0.07), Vector3.ZERO, false)


static func _cleaner(g: Node3D) -> void:
	var x0 := 17.6
	var x1 := 20.4
	var cx := 19.0
	_block(g, x0, x1, 5.6, S_FRONT, S_BACK, Color("#7e8288"), Color("#9a9ea4"))
	_shutter(g, 19.0, S_FRONT - 0.02, 1.8, 2.3, -1.0, Color("#5d6670"))
	_window(g, 20.05, 1.55, S_FRONT - 0.02, 0.72, 0.95, COOL, 0.7, -1.0)
	_window(g, 18.3, 4.30, S_FRONT - 0.02, 1.0, 0.9, WARM, 0.25, -1.0)
	_vert_sign(g, "クリーニング", 17.82, 5.35, S_FRONT - 0.02, 2.3, 0.42,
		Color("#e7eef2"), Color("#2b5a7a"), -1.0, 1.0)
	# 小霓虹灯条
	K.box(g, Vector3(0.05, 1.2, 0.02), Vector3(18.05, 3.3, S_FRONT - 0.08),
		K.glow(Color("#6fe0ff"), 1.5), Vector3.ZERO, false)
	_warm_light(g, Vector3(cx, 2.2, S_FRONT - 0.35), Color("#cfeaff"), 0.45, 3.2)
	_pot(g, 20.2, S_FRONT - 0.3, 0.85)


static func _clinic(g: Node3D) -> void:
	var x0 := 20.4
	var x1 := 23.0
	var cx := 21.7
	_block(g, x0, x1, 5.2, S_FRONT, S_BACK, Color("#a8a294"), Color("#c4bead"))
	_entrance(g, 21.7, S_FRONT - 0.02, 1.1, 2.15, -1.0, Color("#c9d4d2"),
		Color("#4a5254"), COOL)
	_window(g, 20.95, 1.55, S_FRONT - 0.02, 0.85, 1.0, COOL, 0.9, -1.0)
	_window(g, 22.45, 1.55, S_FRONT - 0.02, 0.85, 1.0, COOL, 0.9, -1.0)
	_lit_sign(g, "星見クリニック", Vector3(cx, 2.85, S_FRONT - 0.01), 2.0, 0.42,
		Color("#eef4ea"), Color("#2c5a44"), -1.0, 0.8)
	# 绿十字
	K.box(g, Vector3(0.72, 0.2, 0.06), Vector3(cx, 4.35, S_FRONT - 0.06),
		K.glow(Color("#6fe39a"), 1.8), Vector3.ZERO, false)
	K.box(g, Vector3(0.2, 0.72, 0.06), Vector3(cx, 4.35, S_FRONT - 0.06),
		K.glow(Color("#6fe39a"), 1.8), Vector3.ZERO, false)
	_warm_light(g, Vector3(cx, 2.25, S_FRONT - 0.4), Color("#dff0ff"), 0.6, 3.5)


static func _pocket_park(g: Node3D) -> void:
	# 23.0..27.0 的空地做成口袋公园：矮墙 + 绿篱 + 一棵树 + 长椅。
	# 它正好在东口牌楼的斜对面，出生时向右看就是这里。
	var wall := K.toon(Color("#63666c"), {"shade": 0.5, "rim": 0.2, "line": 0.007})
	K.box(g, Vector3(3.8, 1.25, 0.28), Vector3(25.0, BASE + 0.625, S_FRONT), wall)
	K.box(g, Vector3(4.0, 0.1, 0.36), Vector3(25.0, BASE + 1.29, S_FRONT),
		K.toon(Color("#7b7e83"), {"line": 0.005}))
	var hedge := K.toon(Color("#2f4530"), {"shade": 0.6, "rim": 0.12, "line": 0.004})
	for i in 9:
		var s := K.sphere(g, 0.34, Vector3(23.25 + i * 0.44, BASE + 1.42, S_FRONT - 0.05),
			hedge, Vector3.ZERO, 10, 0.85)
		s.scale = Vector3(1.15, 1.0, 0.8)
	K.box(g, Vector3(0.9, 0.5, 0.04), Vector3(23.55, BASE + 0.85, S_FRONT - 0.16),
		K.toon(Color("#3f4a3a"), {"line": 0.004}))
	K.label_cjk(g, "星見公園", Vector3(23.55, BASE + 0.85, S_FRONT - 0.185),
		0.18, Color("#e6e0cc"), Vector3(0, 180, 0))
	# 树
	var trunk := K.toon(Color("#4b3a2a"), {"shade": 0.55, "rim": 0.2, "line": 0.006})
	K.cyl(g, 0.22, 2.5, Vector3(25.7, BASE + 1.25, 7.9), trunk, Vector3.ZERO, 10)
	var leaf := K.toon(Color("#263f2c"), {"shade": 0.55, "rim": 0.15, "line": 0.006})
	for d in [[Vector3(25.2, 4.1, 7.8), 1.2], [Vector3(26.2, 4.3, 8.0), 1.1],
			[Vector3(25.7, 4.9, 7.6), 1.0], [Vector3(26.0, 3.9, 8.5), 0.85]]:
		var p: Vector3 = d[0]
		K.sphere(g, d[1], p, leaf, Vector3.ZERO, 10, 0.9)
	# 长椅
	K.box(g, Vector3(1.4, 0.07, 0.36), Vector3(25.0, BASE + 0.47, 7.1),
		K.toon(Color("#5a4028"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	for px in [24.4, 25.6]:
		K.box(g, Vector3(0.06, 0.44, 0.3), Vector3(px, BASE + 0.23, 7.1),
			K.toon(Color("#3a3e45"), {"line": 0.004}))
	# 草坪
	K.box(g, Vector3(3.8, 0.02, 3.2), Vector3(25.0, BASE + 0.012, 7.9),
		K.toon(Color("#2a3f2c"), {"shade": 0.7, "rim": 0.05, "line": 0.0}), Vector3.ZERO, false)


static func _corner_house(g: Node3D) -> void:
	var x0 := 27.0
	var x1 := 30.0
	var cx := 28.5
	# 房子退到院子里，前面留矮墙和绿篱
	_block(g, x0, x1, 6.4, 7.3, S_BACK, Color("#665c50"), Color("#827463"))
	_gable(g, cx, 7.3, S_BACK, x1 - x0, 6.4, 1.3, Color("#2f343b"))
	_window(g, 27.95, 1.7, 7.3 - 0.02, 0.9, 1.0, WARM, 0.7, -1.0)
	_window(g, 29.15, 1.7, 7.3 - 0.02, 0.9, 1.0, WARM, 0.45, -1.0)
	_window(g, 28.5, 4.80, 7.3 - 0.02, 1.3, 0.95, WARM, 0.3, -1.0)
	var wall := K.toon(Color("#63666c"), {"shade": 0.5, "rim": 0.2, "line": 0.007})
	K.box(g, Vector3(3.0, 1.2, 0.26), Vector3(cx, BASE + 0.6, S_FRONT), wall)
	K.box(g, Vector3(3.1, 0.09, 0.32), Vector3(cx, BASE + 1.24, S_FRONT),
		K.toon(Color("#7b7e83"), {"line": 0.005}))
	var hedge := K.toon(Color("#2f4530"), {"shade": 0.6, "rim": 0.12, "line": 0.004})
	for i in 7:
		var s := K.sphere(g, 0.3, Vector3(27.25 + i * 0.42, BASE + 1.36, S_FRONT - 0.04),
			hedge, Vector3.ZERO, 10, 0.85)
		s.scale = Vector3(1.1, 1.0, 0.8)
	K.cyl(g, 0.16, 2.0, Vector3(27.6, BASE + 1.0, 6.9),
		K.toon(Color("#4b3a2a"), {"shade": 0.55, "line": 0.006}), Vector3.ZERO, 8)
	K.sphere(g, 1.0, Vector3(27.6, 3.0, 6.9),
		K.toon(Color("#263f2c"), {"shade": 0.55, "rim": 0.15, "line": 0.006}),
		Vector3.ZERO, 10, 0.9)


# ---------------------------------------------------------------- 构件

## 建筑体块 + 沿街立面。北排面朝 +Z，南排面朝 −Z；
## 用 z_front 与 z_back 的大小关系判朝向，别在每个店里手写 facing。
static func _block(g: Node3D, x0: float, x1: float, h: float,
		z_front: float, z_back: float, body_col: Color, front_col: Color) -> void:
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var depth := absf(z_back - z_front)
	var face := signf(z_front - z_back)
	var body := K.toon(body_col, {"shade": 0.46, "rim": 0.16, "line": 0.008})
	K.box(g, Vector3(w, h - BASE, depth), Vector3(cx, (BASE + h) * 0.5,
		(z_front + z_back) * 0.5), body)
	# 沿街立面单独一层略亮的皮：整块墙在夜景里才不会糊成黑片
	K.box(g, Vector3(w - 0.02, h - BASE, 0.04),
		Vector3(cx, (BASE + h) * 0.5, z_front + face * 0.012),
		K.toon(front_col, {"shade": 0.5, "rim": 0.14, "line": 0.007}))
	# 踢脚
	K.box(g, Vector3(w, 0.42, 0.05), Vector3(cx, BASE + 0.21, z_front + face * 0.03),
		K.toon(Color("#34383e"), {"shade": 0.55, "line": 0.005}))
	# 檐口压顶
	K.box(g, Vector3(w + 0.06, 0.09, depth + 0.04), Vector3(cx, h - 0.045,
		(z_front + z_back) * 0.5), K.toon(body_col.darkened(0.22),
		{"shade": 0.5, "line": 0.006}))


## 山墙屋顶：ridge 沿 X。K.prism 的三角剖面在 XY、沿 Z 挤出，
## 所以把 depth 和 width 对调后再绕 Y 转 90°。
static func _gable(g: Node3D, cx: float, z_front: float, z_back: float, w: float,
		wall_top: float, roof_h: float, col: Color) -> void:
	var depth := absf(z_back - z_front)
	var mat := K.toon(col, {"shade": 0.42, "rim": 0.12, "line": 0.008})
	K.prism(g, Vector3(depth + 0.1, roof_h, w + 0.1),
		Vector3(cx, wall_top + roof_h * 0.5, (z_front + z_back) * 0.5),
		mat, Vector3(0, 90, 0))
	K.box(g, Vector3(w + 0.18, 0.09, 0.16), Vector3(cx, wall_top + roof_h,
		(z_front + z_back) * 0.5), K.toon(col.darkened(0.2),
		{"shade": 0.5, "line": 0.005}))


static func _window(g: Node3D, x: float, y: float, z: float, w: float, h: float,
		col: Color, strength: float, face: float) -> void:
	var frame := K.toon(Color("#2b3037"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	K.box(g, Vector3(w + 0.12, h + 0.12, 0.08), Vector3(x, y, z), frame)
	K.box(g, Vector3(w, h, 0.03), Vector3(x, y, z + face * 0.045),
		K.glow(col, strength))
	# 窗棂：一横一竖，比整块发光面更像窗
	var rot := Vector3(0, 0 if face > 0.0 else 180, 0)
	K.box(g, Vector3(0.035, h, 0.02), Vector3(x, y, z + face * 0.065), frame,
		rot, false)
	K.box(g, Vector3(w, 0.035, 0.02), Vector3(x, y, z + face * 0.065), frame,
		rot, false)
	# 窗台
	K.box(g, Vector3(w + 0.2, 0.05, 0.12), Vector3(x, y - h * 0.5 - 0.04, z + face * 0.05),
		frame, Vector3.ZERO, false)


static func _entrance(g: Node3D, x: float, z: float, w: float, h: float, face: float,
		panel_col: Color, frame_col: Color, lit_col: Color) -> void:
	var yy := BASE + h * 0.5
	K.box(g, Vector3(w, h, 0.06), Vector3(x, yy, z + face * 0.01),
		K.toon(panel_col, {"shade": 0.55, "rim": 0.18, "line": 0.005}))
	# 两扇推拉门：中缝 + 门框
	K.box(g, Vector3(0.035, h - 0.08, 0.02), Vector3(x, yy, z + face * 0.05),
		K.toon(frame_col, {"line": 0.0}), Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		K.box(g, Vector3(0.07, h + 0.08, 0.08), Vector3(x + sx * w * 0.5, yy, z + face * 0.04),
			K.toon(frame_col, {"line": 0.004}))
	K.box(g, Vector3(w + 0.1, 0.07, 0.08), Vector3(x, BASE + h + 0.03, z + face * 0.04),
		K.toon(frame_col, {"line": 0.004}))
	# 上部玻璃：把店里的暖光透出来，门才像「开着」
	var rot := Vector3(0, 0 if face > 0.0 else 180, 0)
	K.quad(g, Vector2(w * 0.62, h * 0.32), Vector3(x, BASE + h * 0.7, z + face * 0.065),
		K.glow(lit_col, 0.9), rot, false)
	# 拉手
	var chrome := K.toon(Color("#b4b8bd"), {"shade": 0.5, "rim": 0.45, "line": 0.003})
	K.cyl(g, 0.014, 0.32, Vector3(x + 0.18, BASE + h * 0.46, z + face * 0.09),
		chrome, Vector3.ZERO, 6)
	# 门口台阶
	K.box(g, Vector3(w + 0.4, 0.06, 0.5), Vector3(x, BASE + 0.03, z + face * 0.28),
		K.toon(Color("#4a4e55"), {"shade": 0.6, "line": 0.005}), Vector3.ZERO, false)


static func _shutter(g: Node3D, x: float, z: float, w: float, h: float, face: float,
		col: Color) -> void:
	K.box(g, Vector3(w, h, 0.06), Vector3(x, BASE + h * 0.5, z),
		K.toon(col, {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	var dark := K.toon(Color("#2b2f35"), {"line": 0.0})
	for i in int(h / 0.16):
		K.box(g, Vector3(w, 0.014, 0.02), Vector3(x, BASE + 0.09 + i * 0.16, z + face * 0.04),
			dark, Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		K.box(g, Vector3(0.06, h + 0.1, 0.1), Vector3(x + sx * w * 0.5, BASE + h * 0.5, z + face * 0.02),
			K.toon(Color("#3d4249"), {"line": 0.004}))


static func _noren(g: Node3D, x: float, y: float, z: float, w: float, h: float,
		col: Color, text: String, face: float) -> void:
	var rot := Vector3(0, 0 if face > 0.0 else 180, 0)
	var mat := K.toon(col, {"shade": 0.72, "rim": 0.1, "line": 0.004, "wrap": 0.4})
	# 横杆
	K.cyl(g, 0.018, w + 0.2, Vector3(x, y + h * 0.5 + 0.03, z),
		K.toon(Color("#2a2b2f"), {"line": 0.0}), Vector3(0, 0, 90), 6)
	var n := 3
	var pw := w / float(n)
	for i in n:
		var px := x - w * 0.5 + pw * (i + 0.5)
		K.quad(g, Vector2(pw - 0.025, h), Vector3(px, y, z), mat, rot, false)
	K.label_cjk(g, text, Vector3(x, y, z + face * 0.015), h * 0.34,
		Color("#f4ead2"), rot, 4, Color("#2a1512"))


static func _awning(g: Node3D, spec: Dictionary) -> void:
	var x0: float = spec["x0"]
	var x1: float = spec["x1"]
	var z0: float = spec["z0"]
	var z1: float = spec["z1"]
	var y: float = spec["h"]
	var w := x1 - x0
	var depth := absf(z1 - z0)
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# 北排墙在 z0、檐口朝 +Z；南排反过来，墙在 z1、檐口朝 −Z。
	# 坡向、垂边、斜撑三处都从 street 推，别再按 z 的大小猜。
	var north := (z0 + z1) * 0.5 < 5.0
	var street := 1.0 if north else -1.0
	var wall_z := z0 if north else z1
	var outer_z := z1 if north else z0
	var ag := K.group(g, "Awning", Vector3(cx, y, cz), Vector3(8.0 * street, 0, 0))
	var mat := K.toon(spec["col"], {"shade": 0.55, "rim": 0.2, "line": 0.006})
	var stripe := K.toon(spec["stripe"], {"shade": 0.62, "rim": 0.15, "line": 0.0})
	K.box(ag, Vector3(w, 0.055, depth), Vector3.ZERO, mat)
	# 条纹沿进深方向，沿 X 交替
	var n := int(w / 0.42)
	for i in n:
		if i % 2 == 0:
			continue
		var px := -w * 0.5 + 0.21 + i * 0.42
		K.box(ag, Vector3(0.2, 0.012, depth - 0.04), Vector3(px, 0.034, 0), stripe,
			Vector3.ZERO, false)
	# 前檐垂边
	K.box(ag, Vector3(w, 0.16, 0.035),
		Vector3(0, -0.09, street * depth * 0.5 * 0.96), mat, Vector3.ZERO, false)
	# 两根斜撑
	for px in [x0 + 0.12, x1 - 0.12]:
		K.strut(g, Vector3(px, y - 0.62, wall_z), Vector3(px, y - 0.06, outer_z),
			0.022, K.toon(Color("#3a3e44"), {"line": 0.004}), 6, false)


static func _lit_sign(g: Node3D, text: String, pos: Vector3, w: float, h: float,
		bg: Color, fg: Color, face: float, strength: float) -> void:
	var rot := Vector3(0, 0 if face > 0.0 else 180, 0)
	K.box(g, Vector3(w + 0.12, h + 0.12, 0.07), pos,
		K.toon(Color("#22272d"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	K.box(g, Vector3(w, h, 0.03), pos + Vector3(0, 0, face * 0.045),
		K.glow(bg, strength))
	K.label_cjk(g, text, pos + Vector3(0, 0, face * 0.075), h * 0.55, fg, rot,
		5, bg)


static func _vert_sign(g: Node3D, text: String, x: float, y_top: float, z: float,
		h: float, w: float, bg: Color, fg: Color, face: float, strength: float) -> void:
	var rot := Vector3(0, 0 if face > 0.0 else 180, 0)
	var cx := x
	var cy := y_top - h * 0.5
	K.box(g, Vector3(w, h, 0.07), Vector3(cx, cy, z),
		K.toon(Color("#22272d"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	K.box(g, Vector3(w - 0.05, h - 0.05, 0.03), Vector3(cx, cy, z + face * 0.045),
		K.glow(bg, strength))
	var n := maxi(1, text.length())
	var step := h / float(n)
	for i in n:
		K.label_cjk(g, text.substr(i, 1),
			Vector3(cx, y_top - step * (i + 0.5), z + face * 0.075),
			step * 0.72, fg, rot, 4, bg)
	# 墙上支架
	for yy in [y_top - h * 0.2, y_top - h * 0.8]:
		K.box(g, Vector3(0.14, 0.04, 0.04), Vector3(cx, yy, z - face * 0.06),
			K.toon(Color("#3a3e44"), {"line": 0.0}), Vector3.ZERO, false)


static func _lantern(g: Node3D, pos: Vector3, col: Color, text: String) -> void:
	var dark := K.toon(Color("#262a31"), {"line": 0.0})
	K.cyl(g, 0.115, 0.3, pos, K.glow(col, 1.5), Vector3.ZERO, 12)
	K.cyl(g, 0.075, 0.02, pos + Vector3(0, -0.17, 0), dark, Vector3.ZERO, 12)
	K.cyl(g, 0.075, 0.02, pos + Vector3(0, 0.17, 0), dark, Vector3.ZERO, 12)
	K.label_cjk(g, text, pos + Vector3(0, 0, 0.12), 0.13, Color("#2a1512"))
	K.sphere(g, 0.34, pos, K.soft(col, 0.18, 2.0), Vector3.ZERO, 12, 0.9, false)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.35
	l.omni_range = 2.6
	l.position = pos + Vector3(0, 0, 0.35)
	g.add_child(l)


static func _warm_light(g: Node3D, pos: Vector3, col: Color, energy: float,
		rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.6
	l.position = pos
	g.add_child(l)


static func _ac(g: Node3D, x: float, y: float, z: float, face: float) -> void:
	var ag := K.group(g, "AC", Vector3(x, y, z), Vector3(0, 0 if face > 0.0 else 180, 0))
	var metal := K.toon(Color("#6f706c"), {"shade": 0.5, "rim": 0.25, "line": 0.006})
	K.box(ag, Vector3(0.66, 0.42, 0.3), Vector3.ZERO, metal)
	K.cyl(ag, 0.15, 0.02, Vector3(-0.1, 0, 0.16), K.toon(Color("#33383e"), {"line": 0.0}),
		Vector3(90, 0, 0), 14, -1.0, false)
	K.cyl(ag, 0.11, 0.01, Vector3(-0.1, 0, 0.175), K.toon(Color("#6d737b"), {"line": 0.0}),
		Vector3(90, 0, 0), 12, -1.0, false)
	for i in 3:
		K.box(ag, Vector3(0.02, 0.36, 0.02), Vector3(0.2, 0, -0.1 + i * 0.1),
			K.toon(Color("#5c626a"), {"line": 0.0}), Vector3.ZERO, false)


static func _menu_board(g: Node3D, x: float, z: float, rot_y: float, text: String) -> void:
	var a := K.group(g, "MenuBoard", Vector3(x, BASE, z), Vector3(0, rot_y, 0))
	var wood := K.toon(Color("#3f3322"), {"shade": 0.5, "rim": 0.2, "line": 0.005})
	K.box(a, Vector3(0.5, 0.84, 0.05), Vector3(0, 0.43, 0.08), wood, Vector3(-12, 0, 0))
	K.box(a, Vector3(0.5, 0.84, 0.05), Vector3(0, 0.43, -0.08), wood, Vector3(12, 0, 0))
	K.quad(a, Vector2(0.42, 0.7), Vector3(0, 0.45, 0.115),
		K.toon(Color("#e6e1d2"), {"shade": 0.85, "line": 0.0}), Vector3(-12, 0, 0), false)
	K.label_cjk(a, text, Vector3(0, 0.44, 0.128), 0.1, Color("#3a2a1c"), Vector3(-12, 0, 0))


static func _pot(g: Node3D, x: float, z: float, s: float) -> void:
	var p := K.group(g, "Pot", Vector3(x, BASE, z))
	var clay := K.toon(Color("#6a4a3a"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	K.cyl(p, 0.16 * s, 0.26 * s, Vector3(0, 0.13 * s, 0), clay, Vector3.ZERO, 10, 0.12 * s)
	var leaf := K.toon(Color("#2f4a34"), {"shade": 0.6, "rim": 0.12, "line": 0.004})
	for i in 3:
		K.sphere(p, 0.13 * s, Vector3(0.03 * (i - 1), (0.34 + i * 0.06) * s, 0.02 * i),
			leaf, Vector3.ZERO, 8, 1.2)
