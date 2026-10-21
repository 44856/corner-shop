extends RefCounted

const K := preload("res://scripts/kit.gd")

# 便利店主体：外墙 / 玻璃立面 / 自动门 / 雨棚 / 招牌 / 屋顶 / 店内

const X0 := -1.7
const X1 := 3.1
const Z0 := -5.5
const Z1 := -0.9
const FLOOR := 0.17
const TOP := 3.58
const GLASS_Z := Z1 - 0.11


## opts:
##   walkable  = true 时店内改成「能走进去」的布局：门洞打通、货架留出 ≥0.8m 过道、
##               收银台挪到东墙。默认 false，保持原来那个只做橱窗展示的摆法。
##   auto_door = true 时不再画两扇门叶，交给 autodoor.gd 画（它要带着碰撞一起滑）
static func build(root: Node3D, opts: Dictionary = {}) -> void:
	var walkable: bool = opts.get("walkable", false)
	var auto_door: bool = opts.get("auto_door", false)
	var g := K.group(root, "Store")
	_shell(g, walkable)
	_facade(g, auto_door)
	_west_wall(g)
	_awning(g)
	_signage(g)
	_roof(g)
	_interior(g, walkable)


## 店内布局的唯一真源：视觉（_interior）与碰撞（collision_layout.gd）都读这里，
## 免得改一个数字以后「看得见走不过去」。
static func layout(walkable: bool) -> Dictionary:
	if walkable:
		return {
			# 两块横向货架，x -0.95..0.95，中间留 0.83m 过道
			"racks": [
				{"x0": -0.95, "x1": 0.95, "z": -3.85},
				{"x0": -0.95, "x1": 0.95, "z": -2.50},
			],
			# 冷柜贴后墙，前面留 0.85m 站立区
			"fridge": {"x0": 0.15, "x1": 2.55, "z0": -5.38, "z1": -4.96},
			# 收银台沿东墙摆，正面朝 −X（绕 Y 转 −90°）。
			# cx 贴到 2.58：台面背后正好抵住内墙（2.88），过道留出 1.33m。
			"counter": {"cx": 2.58, "cz": -3.00, "rot": -90.0, "w": 1.1, "d": 0.6},
			"magazine": {"x0": -1.48, "x1": -1.03, "z0": -2.65, "z1": -1.25},
			"promos": [Vector3(-0.55, FLOOR + 0.3, -1.35), Vector3(2.45, FLOOR + 0.3, -1.45)],
		}
	return {
		"racks": [
			{"x0": -1.20, "x1": 2.30, "z": -4.25},
			{"x0": -1.20, "x1": 2.30, "z": -3.20},
			{"x0": -1.20, "x1": 2.30, "z": -2.15},
		],
		"fridge": {"x0": 0.15, "x1": 2.55, "z0": -5.38, "z1": -4.96},
		"counter": {"cx": 2.10, "cz": -1.55, "rot": 0.0, "w": 1.1, "d": 0.6},
		"magazine": {"x0": -1.475, "x1": -1.025, "z0": -2.65, "z1": -1.25},
		"promos": [Vector3(-0.55, FLOOR + 0.3, -1.35), Vector3(1.75, FLOOR + 0.3, -1.40)],
	}

## 门叶几何（视觉与碰撞共用）。两扇门各走一条轨道，错开 3cm 免得 z-fighting。
## slide 是开启时相对初始位置的 x 位移：各自滑到旁边的固定玻璃后面。
static func door_leaves() -> Array:
	return [
		{"x": 0.03, "z": GLASS_Z - 0.03, "w": 0.62, "h": 2.24, "slide": -0.66},
		{"x": 0.68, "z": GLASS_Z + 0.03, "w": 0.62, "h": 2.24, "slide": 0.66},
	]


# ---------------------------------------------------------------- 外壳

static func _shell(g: Node3D, walkable: bool) -> void:
	var wall := K.toon(Color("#918a7c"), {"shade": 0.42, "rim": 0.18, "line": 0.009})
	# 可玩版会被人仰视天花板：三盏暖光就吊在它下面 0.4m，用原来的亮色会直接烧白
	var inner := K.toon(Color("#9c9587") if walkable else Color("#bdb6a8"),
		{"shade": 0.7, "rim": 0.0, "line": 0.0})

	K.box(g, Vector3(0.22, TOP - FLOOR, Z1 - Z0), Vector3(X0 + 0.11, (TOP + FLOOR) * 0.5, (Z0 + Z1) * 0.5), wall)
	K.box(g, Vector3(0.22, TOP - FLOOR, Z1 - Z0), Vector3(X1 - 0.11, (TOP + FLOOR) * 0.5, (Z0 + Z1) * 0.5), wall)
	K.box(g, Vector3(X1 - X0, TOP - FLOOR, 0.22), Vector3((X0 + X1) * 0.5, (TOP + FLOOR) * 0.5, Z0 + 0.11), wall)

	# 店面基座（踢脚墙）
	var tile := K.toon(Color("#3a3f47"), {"shade": 0.45, "rim": 0.15, "line": 0.008})
	# 门洞净宽（两扇门叶合计）。walkable 时踢脚墙与压条都按这两段断开，
	# 否则 0.55m 高的踢脚墙会横在门口，人是走不进去的。
	var segs: Array = [[X0, -0.33], [1.04, X1]]
	if walkable:
		for s in segs:
			var w: float = s[1] - s[0]
			K.box(g, Vector3(w, 0.55, 0.22), Vector3((s[0] + s[1]) * 0.5, FLOOR + 0.275, Z1 - 0.11), tile)
	else:
		K.box(g, Vector3(X1 - X0, 0.55, 0.22), Vector3((X0 + X1) * 0.5, FLOOR + 0.275, Z1 - 0.11), tile)

	# 踢脚墙上的两道细压条，同样在门洞处断开
	var seam := K.toon(Color("#43474f"), {"line": 0.0})
	if walkable:
		for s in segs:
			var sw: float = s[1] - s[0]
			for i in 2:
				K.box(g, Vector3(sw, 0.012, 0.012), Vector3((s[0] + s[1]) * 0.5, FLOOR + 0.24 + i * 0.22, Z1 + 0.002), seam, Vector3.ZERO, false)
	else:
		for i in 2:
			K.box(g, Vector3(X1 - X0, 0.012, 0.012), Vector3((X0 + X1) * 0.5, FLOOR + 0.24 + i * 0.22, Z1 + 0.002), seam, Vector3.ZERO, false)

	# 玻璃上方的过梁
	K.box(g, Vector3(X1 - X0, TOP - 2.55, 0.22), Vector3((X0 + X1) * 0.5, (TOP + 2.55) * 0.5, Z1 - 0.11), wall)

	# 室内地板
	K.box(g, Vector3(X1 - X0 - 0.44, 0.08, Z1 - Z0 - 0.44), Vector3((X0 + X1) * 0.5, FLOOR + 0.04, (Z0 + Z1) * 0.5), K.paving(Color("#8b8579"), Color("#6a6459"), 0.45), Vector3.ZERO, false)

	# 室内天花
	K.box(g, Vector3(X1 - X0 - 0.44, 0.06, Z1 - Z0 - 0.44), Vector3((X0 + X1) * 0.5, 2.9, (Z0 + Z1) * 0.5), inner, Vector3.ZERO, false)


# ---------------------------------------------------------------- 立面

static func _facade(g: Node3D, auto_door: bool = false) -> void:
	var frame := K.toon(Color("#242b34"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	var glass := K.glass(Color(0.45, 0.62, 0.8, 0.08), 0.35)
	var f := K.group(g, "Facade")

	# 竖向分隔
	for mx in [-1.48, -0.42, -0.30, 1.00, 1.12, 2.88]:
		K.box(f, Vector3(0.09, 1.86, 0.16), Vector3(mx, 1.64, GLASS_Z), frame)
	# 门框更粗
	K.box(f, Vector3(0.1, 2.4, 0.18), Vector3(-0.36, 1.37, GLASS_Z), frame)
	K.box(f, Vector3(0.1, 2.4, 0.18), Vector3(1.06, 1.37, GLASS_Z), frame)
	K.box(f, Vector3(1.52, 0.12, 0.18), Vector3(0.35, 2.5, GLASS_Z), frame)

	# 窗玻璃
	K.box(f, Vector3(0.9, 1.82, 0.02), Vector3(-0.95, 1.64, GLASS_Z), glass, Vector3.ZERO, false)
	K.box(f, Vector3(1.7, 1.82, 0.02), Vector3(2.0, 1.64, GLASS_Z), glass, Vector3.ZERO, false)

	# 自动门（双扇）
	# auto_door 模式下门叶交给 autodoor.gd：它要把玻璃 + 门框 + 把手打包成可滑动、
	# 带碰撞的一整片，静态这里再画一遍会重叠成两层。
	if not auto_door:
		for leaf in door_leaves():
			var lx: float = leaf["x"]
			var lz: float = leaf["z"]
			K.box(f, Vector3(leaf["w"], leaf["h"], 0.02), Vector3(lx, 1.32, lz), glass, Vector3.ZERO, false)
			K.box(f, Vector3(0.66, 0.06, 0.05), Vector3(lx, 2.42, lz), frame)
			K.box(f, Vector3(0.66, 0.05, 0.05), Vector3(lx, 0.23, lz), frame)
			K.box(f, Vector3(0.05, 2.24, 0.05), Vector3(lx - 0.31, 1.32, lz), frame)
			K.box(f, Vector3(0.05, 2.24, 0.05), Vector3(lx + 0.31, 1.32, lz), frame)
	# 自动门标识条
	var strip := K.toon(Color("#1b7259"), {"shade": 0.7, "line": 0.0, "rim": 0.0})
	K.box(f, Vector3(1.2, 0.1, 0.03), Vector3(0.35, 2.16, GLASS_Z + 0.06), strip, Vector3.ZERO, false)
	K.label(f, "AUTO DOOR", Vector3(0.35, 2.16, GLASS_Z + 0.08), 0.065, Color("#e8fff6"))

	# 橱窗内的 OPEN 霓虹
	K.label(f, "OPEN", Vector3(2.05, 2.3, GLASS_Z - 0.28), 0.16, Color("#7dffc4"), Vector3(0, 0, 0), 10, Color("#2fd68c"))

	# 玻璃上的反光斜条
	var streak := K.glow(Color("#bfe0ff"), 0.3)
	K.quad(f, Vector2(0.045, 1.3), Vector3(-1.22, 1.8, GLASS_Z + 0.03), streak, Vector3(0, 0, 18), false)
	K.quad(f, Vector2(0.035, 1.1), Vector3(-0.78, 1.8, GLASS_Z + 0.03), streak, Vector3(0, 0, 18), false)
	K.quad(f, Vector2(0.045, 1.3), Vector3(-0.02, 1.35, GLASS_Z - 0.06), streak, Vector3(0, 0, 15), false)
	K.quad(f, Vector2(0.04, 1.2), Vector3(2.3, 1.75, GLASS_Z + 0.03), streak, Vector3(0, 0, 16), false)

	# 门把手
	if not auto_door:
		K.box(f, Vector3(0.04, 0.32, 0.03), Vector3(0.26, 1.12, GLASS_Z - 0.08), frame)
		K.box(f, Vector3(0.04, 0.32, 0.03), Vector3(0.44, 1.12, GLASS_Z + 0.08), frame)

	# 玻璃上的海报
	var poster_a := K.toon(Color("#c93f34"), {"shade": 0.8, "line": 0.004, "rim": 0.0, "emit": Color("#c93f34"), "emit_amt": 0.12})
	K.quad(f, Vector2(0.34, 0.46), Vector3(-1.1, 1.58, GLASS_Z + 0.02), poster_a)
	K.label(f, "SALE", Vector3(-1.1, 1.67, GLASS_Z + 0.035), 0.11, Color("#fff2e2"))
	K.label(f, "-20%", Vector3(-1.1, 1.5, GLASS_Z + 0.035), 0.095, Color("#ffe9d6"))
	var poster_b := K.toon(Color("#e2c05e"), {"shade": 0.85, "line": 0.004, "rim": 0.0})
	K.quad(f, Vector2(0.32, 0.42), Vector3(2.45, 1.62, GLASS_Z + 0.02), poster_b)
	K.label(f, "NEW", Vector3(2.45, 1.69, GLASS_Z + 0.035), 0.095, Color("#22293a"))
	K.label(f, "HOT", Vector3(2.45, 1.54, GLASS_Z + 0.035), 0.095, Color("#b23a28"))


# ---------------------------------------------------------------- 西侧外墙

static func _west_wall(g: Node3D) -> void:
	var w := K.group(g, "WestWall")
	var dark := K.toon(Color("#3f444c"), {"shade": 0.5, "rim": 0.2, "line": 0.006})
	var metal := K.toon(Color("#5a6068"), {"shade": 0.55, "rim": 0.25, "line": 0.005})

	# 侧面灯箱
	var sign_bg := K.toon(Color("#141d33"), {"shade": 0.65, "rim": 0.3, "line": 0.007, "emit": Color("#0a1c33"), "emit_amt": 0.35})
	K.box(w, Vector3(0.06, 0.42, 2.4), Vector3(X0 - 0.03, 3.02, -2.3), sign_bg)
	K.label(w, "HOSHI MART", Vector3(X0 - 0.065, 3.02, -2.3), 0.16, Color("#e8f6ff"), Vector3(0, -90, 0), 8, Color("#bfe4ff"))
	K.box(w, Vector3(0.07, 0.035, 2.4), Vector3(X0 - 0.035, 2.79, -2.3), K.glow(Color("#2fbf71"), 1.1))

	# 通风格栅
	for i in 4:
		K.box(w, Vector3(0.04, 0.03, 0.62), Vector3(X0 - 0.02, 2.1 + i * 0.09, -4.15), dark, Vector3.ZERO, false)
	K.box(w, Vector3(0.03, 0.42, 0.72), Vector3(X0 - 0.005, 2.24, -4.15), K.toon(Color("#2c3037"), {"line": 0.0}), Vector3.ZERO, false)

	# 海报
	K.quad(w, Vector2(0.42, 0.56), Vector3(X0 - 0.02, 1.55, -3.2), K.toon(Color("#c8c2b2"), {"shade": 0.8, "line": 0.003}), Vector3(0, -90, 0))
	K.label(w, "24H", Vector3(X0 - 0.035, 1.62, -3.2), 0.16, Color("#25303c"), Vector3(0, -90, 0))
	K.label(w, "OPEN", Vector3(X0 - 0.035, 1.42, -3.2), 0.08, Color("#b23a28"), Vector3(0, -90, 0))

	# 西墙壁灯
	var wl := OmniLight3D.new()
	wl.light_color = Color("#ffcf9a")
	wl.light_energy = 0.7
	wl.omni_range = 2.6
	wl.position = Vector3(X0 - 0.25, 2.35, -3.9)
	w.add_child(wl)
	K.box(w, Vector3(0.16, 0.05, 0.09), Vector3(X0 - 0.08, 2.4, -3.9), K.toon(Color("#33383e"), {"line": 0.004}))
	K.sphere(w, 0.055, Vector3(X0 - 0.16, 2.36, -3.9), K.glow(Color("#ffd7a0"), 2.2), Vector3.ZERO, 8, 1.0, false)

	# 落水管与电表箱
	K.cyl(w, 0.045, 3.2, Vector3(X0 - 0.06, 1.75, -0.98), metal, Vector3.ZERO, 8)
	K.box(w, Vector3(0.12, 0.34, 0.26), Vector3(X0 - 0.06, 1.4, -1.35), metal)
	K.box(w, Vector3(0.02, 0.26, 0.2), Vector3(X0 - 0.125, 1.4, -1.35), K.toon(Color("#20242a"), {"line": 0.0}))
	# 后墙：后门 / 小窗 / 管道
	var back_door := K.toon(Color("#4a5158"), {"shade": 0.55, "rim": 0.2, "line": 0.006})
	K.box(w, Vector3(0.86, 1.9, 0.06), Vector3(0.6, 1.12, Z0 - 0.03), back_door)
	K.box(w, Vector3(0.05, 0.05, 0.08), Vector3(0.26, 1.5, Z0 - 0.06), K.toon(Color("#b9bcc0"), {"line": 0.0}))
	K.box(w, Vector3(1.1, 0.1, 0.24), Vector3(0.6, 2.16, Z0 - 0.12), K.toon(Color("#33383f"), {"shade": 0.6, "line": 0.006}))
	K.box(w, Vector3(0.6, 0.06, 0.12), Vector3(0.6, 2.09, Z0 - 0.18), K.glow(Color("#ffd9a2"), 1.5), Vector3.ZERO, false)
	for wx in [2.05, 2.55]:
		K.box(w, Vector3(0.3, 0.42, 0.06), Vector3(wx, 2.15, Z0 - 0.02), K.toon(Color("#2a2f36"), {"line": 0.004}))
		K.box(w, Vector3(0.24, 0.36, 0.02), Vector3(wx, 2.15, Z0 - 0.055), K.glow(Color("#ffcf8e"), 0.5))
	K.cyl(w, 0.04, 3.3, Vector3(-0.9, 1.7, Z0 - 0.07), K.toon(Color("#5a6068"), {"shade": 0.55, "line": 0.004}), Vector3.ZERO, 8)

	# 东墙：竖管 / 爬梯 / 海报
	K.cyl(w, 0.045, 3.3, Vector3(X1 + 0.06, 1.7, -3.55), metal, Vector3.ZERO, 8)
	K.cyl(w, 0.032, 3.3, Vector3(X1 + 0.06, 1.7, -3.42), metal, Vector3.ZERO, 8)
	var rung := 0.6
	while rung < 3.2:
		K.box(w, Vector3(0.05, 0.02, 0.34), Vector3(X1 + 0.06, rung, -4.55), metal, Vector3.ZERO, false)
		rung += 0.32
	K.cyl(w, 0.02, 2.9, Vector3(X1 + 0.06, 1.6, -4.72), metal, Vector3.ZERO, 6)
	K.cyl(w, 0.02, 2.9, Vector3(X1 + 0.06, 1.6, -4.38), metal, Vector3.ZERO, 6)
	K.quad(w, Vector2(0.4, 0.54), Vector3(X1 + 0.02, 1.45, -1.35), K.toon(Color("#b8b09c"), {"shade": 0.75, "line": 0.003}), Vector3(0, 90, 0))
	K.label(w, "STAFF", Vector3(X1 + 0.035, 1.45, -1.35), 0.075, Color("#2b323c"), Vector3(0, 90, 0))

	# 墙面污渍/踢脚
	K.box(w, Vector3(0.02, 0.35, 4.5), Vector3(X0 - 0.005, 0.34, -3.2), K.toon(Color("#8b8478"), {"shade": 0.6, "line": 0.0}), Vector3.ZERO, false)


# ---------------------------------------------------------------- 雨棚

static func _awning(g: Node3D) -> void:
	var a := K.group(g, "Awning")
	var green := K.toon(Color("#17564a"), {"shade": 0.5, "rim": 0.25, "line": 0.008})
	var white := K.toon(Color("#dddcd2"), {"shade": 0.55, "rim": 0.2, "line": 0.006})

	K.box(a, Vector3(4.9, 0.09, 1.1), Vector3(0.7, 2.6, -0.38), green, Vector3(7.0, 0, 0))
	K.box(a, Vector3(4.86, 0.03, 0.2), Vector3(0.7, 2.53, 0.09), white, Vector3(7.0, 0, 0))
	# 前缘板
	K.box(a, Vector3(4.9, 0.19, 0.07), Vector3(0.7, 2.45, 0.16), green)
	K.box(a, Vector3(4.9, 0.045, 0.02), Vector3(0.7, 2.38, 0.2), white)
	# 雨棚白色条纹
	for sx in [-1.15, -0.25, 0.65, 1.55, 2.45]:
		K.box(a, Vector3(0.17, 0.012, 1.12), Vector3(sx, 2.652, -0.38), white, Vector3(7.0, 0, 0), false)

	# 雨棚下灯带
	K.box(a, Vector3(4.4, 0.02, 0.07), Vector3(0.7, 2.51, -0.02), K.glow(Color("#ffe3b4"), 1.9), Vector3.ZERO, false)
	# 斜撑
	var strut_mat := K.toon(Color("#2f3741"), {"shade": 0.6, "line": 0.005})
	for sx in [-1.3, 0.7, 2.7]:
		K.strut(a, Vector3(sx, 3.1, Z1 + 0.01), Vector3(sx, 2.6, 0.06), 0.02, strut_mat, 6)
	# 落水管
	K.cyl(a, 0.045, 2.4, Vector3(-1.42, 1.35, 0.19), strut_mat, Vector3.ZERO, 8)


# ---------------------------------------------------------------- 招牌

static func _signage(g: Node3D) -> void:
	var s := K.group(g, "Signage")
	var board_z := Z1 + 0.055
	var indigo := K.toon(Color("#131c33"), {"shade": 0.7, "rim": 0.3, "line": 0.008, "emit": Color("#0a1c33"), "emit_amt": 0.4})

	K.box(s, Vector3(4.86, 0.64, 0.06), Vector3(0.7, 3.11, board_z), indigo)
	# 三色品牌条
	K.box(s, Vector3(4.86, 0.045, 0.065), Vector3(0.7, 2.82, board_z + 0.002), K.glow(Color("#2fbf71"), 1.25))
	K.box(s, Vector3(1.5, 0.045, 0.065), Vector3(-0.75, 2.82, board_z + 0.004), K.glow(Color("#ff8b3d"), 1.25))
	K.box(s, Vector3(0.9, 0.045, 0.065), Vector3(2.35, 2.82, board_z + 0.004), K.glow(Color("#3fa9ff"), 1.25))

	K.label(s, "HOSHI MART", Vector3(0.66, 3.25, board_z + 0.04), 0.32, Color("#ffffff"), Vector3.ZERO, 11, Color("#bfe4ff"))
	K.label(s, "OPEN 24 HOURS", Vector3(0.66, 2.93, board_z + 0.04), 0.075, Color("#7fc7f2"))

	# 屋顶灯箱立柱
	var pylon := K.group(s, "Pylon", Vector3(-1.45, TOP + 0.12, Z1 - 0.05))
	K.box(pylon, Vector3(0.6, 1.55, 0.42), Vector3(0, 0.775, 0), K.toon(Color("#b8b2a5"), {"shade": 0.55, "rim": 0.25, "line": 0.007}))
	K.box(pylon, Vector3(0.64, 0.1, 0.46), Vector3(0, 1.58, 0), K.toon(Color("#17564a"), {"line": 0.006}))
	K.box(pylon, Vector3(0.5, 0.66, 0.02), Vector3(0, 1.2, 0.22), K.glow(Color("#f2fff8"), 1.4))
	K.label(pylon, "24", Vector3(0, 1.2, 0.235), 0.4, Color("#14805e"), Vector3.ZERO, 8, Color("#14805e"))
	K.label(pylon, "HOSHI", Vector3(0, 0.75, 0.235), 0.13, Color("#2c3a44"))
	K.box(pylon, Vector3(0.5, 0.05, 0.02), Vector3(0, 0.47, 0.22), K.glow(Color("#ff8b3d"), 1.1))

	# 侧面小灯箱（朝向后巷）
	var side := K.toon(Color("#17564a"), {"shade": 0.55, "line": 0.006, "emit": Color("#17564a"), "emit_amt": 0.35})
	K.box(s, Vector3(0.05, 0.34, 2.0), Vector3(X1 + 0.01, 3.11, -3.0), side)
	K.label(s, "HOSHI MART", Vector3(X1 + 0.05, 3.11, -3.0), 0.13, Color("#d7f5e9"), Vector3(0, 90, 0))


# ---------------------------------------------------------------- 屋顶

static func _roof(g: Node3D) -> void:
	var r := K.group(g, "Roof")
	var slab := K.toon(Color("#3a3e45"), {"shade": 0.5, "rim": 0.12, "line": 0.008})
	var parapet := K.toon(Color("#6d675e"), {"shade": 0.45, "rim": 0.18, "line": 0.008})
	var metal := K.toon(Color("#5f646c"), {"shade": 0.55, "rim": 0.3, "line": 0.006})

	K.box(r, Vector3(X1 - X0 + 0.12, 0.12, Z1 - Z0 + 0.12), Vector3((X0 + X1) * 0.5, TOP + 0.06, (Z0 + Z1) * 0.5), slab)
	K.box(r, Vector3(X1 - X0 + 0.12, 0.3, 0.12), Vector3((X0 + X1) * 0.5, TOP + 0.26, Z1 + 0.06), parapet)
	K.box(r, Vector3(X1 - X0 + 0.12, 0.3, 0.12), Vector3((X0 + X1) * 0.5, TOP + 0.26, Z0 - 0.06), parapet)
	K.box(r, Vector3(0.12, 0.3, Z1 - Z0), Vector3(X0 - 0.06, TOP + 0.26, (Z0 + Z1) * 0.5), parapet)
	K.box(r, Vector3(0.12, 0.3, Z1 - Z0), Vector3(X1 + 0.06, TOP + 0.26, (Z0 + Z1) * 0.5), parapet)

	# 空调外机
	for d in [[Vector3(2.1, 0, -4.1), 0.0], [Vector3(0.9, 0, -5.05), 0.0]]:
		var base: Vector3 = d[0]
		K.box(r, Vector3(0.9, 0.66, 0.7), base + Vector3(0, TOP + 0.45, 0), metal)
		K.cyl(r, 0.23, 0.05, base + Vector3(0, TOP + 0.45, 0.36), K.toon(Color("#32363c"), {"line": 0.0}), Vector3(90, 0, 0), 14)
		K.cyl(r, 0.18, 0.02, base + Vector3(0, TOP + 0.45, 0.38), K.toon(Color("#8b9199"), {"line": 0.0}), Vector3(90, 0, 0), 14)
		for i in 4:
			K.box(r, Vector3(0.86, 0.02, 0.02), base + Vector3(0, TOP + 0.2 + i * 0.13, 0.36), K.toon(Color("#464c54"), {"line": 0.0}), Vector3.ZERO, false)

	# 排气管
	K.cyl(r, 0.1, 1.0, Vector3(-0.5, TOP + 0.56, -4.2), metal, Vector3.ZERO, 8)
	K.cyl(r, 0.16, 0.1, Vector3(-0.5, TOP + 1.08, -4.2), metal, Vector3.ZERO, 8)
	# 通风帽
	K.cyl(r, 0.2, 0.35, Vector3(1.7, TOP + 0.24, -5.25), metal, Vector3.ZERO, 12, 0.28)
	# 天线
	K.cyl(r, 0.018, 1.9, Vector3(2.75, TOP + 1.0, -1.55), metal, Vector3.ZERO, 6)
	for i in 3:
		K.box(r, Vector3(0.46 - i * 0.12, 0.016, 0.016), Vector3(2.75, TOP + 0.66 + i * 0.32, -1.55), metal, Vector3.ZERO, false)
	# 楼梯间
	var hut := K.toon(Color("#6f6a60"), {"shade": 0.45, "rim": 0.15, "line": 0.008})
	K.box(r, Vector3(1.25, 0.95, 1.15), Vector3(-0.55, TOP + 0.56, -4.55), hut)
	K.box(r, Vector3(1.35, 0.09, 1.25), Vector3(-0.55, TOP + 1.07, -4.55), K.toon(Color("#6f6960"), {"line": 0.006}))
	K.box(r, Vector3(0.62, 0.76, 0.05), Vector3(-0.55, TOP + 0.46, -3.97), K.toon(Color("#4a5158"), {"shade": 0.5, "line": 0.005}))
	K.box(r, Vector3(0.1, 0.1, 0.03), Vector3(-0.4, TOP + 0.42, -3.94), K.toon(Color("#c8c3b6"), {"line": 0.0}))
	# 屋顶风管
	var duct := K.toon(Color("#6d737b"), {"shade": 0.5, "rim": 0.3, "line": 0.006})
	K.box(r, Vector3(1.9, 0.22, 0.28), Vector3(1.6, TOP + 0.28, -5.15), duct)
	K.box(r, Vector3(0.22, 0.22, 0.28), Vector3(0.72, TOP + 0.28, -5.0), duct, Vector3(0, 45, 0))
	# 前檐栏杆
	var rail := K.toon(Color("#5c626a"), {"shade": 0.55, "rim": 0.3, "line": 0.004})
	var rx := -1.5
	while rx < 3.1:
		K.box(r, Vector3(0.03, 0.62, 0.03), Vector3(rx, TOP + 0.31, Z1 + 0.02), rail)
		rx += 0.75
	K.strut(r, Vector3(-1.55, TOP + 0.62, Z1 + 0.02), Vector3(3.12, TOP + 0.62, Z1 + 0.02), 0.022, rail, 6)
	K.strut(r, Vector3(-1.55, TOP + 0.34, Z1 + 0.02), Vector3(3.12, TOP + 0.34, Z1 + 0.02), 0.016, rail, 6)

	# 屋顶小航空灯
	K.sphere(r, 0.07, Vector3(0.75, TOP + 0.12, -1.35), K.glow(Color("#ff5a3a"), 2.2), Vector3.ZERO, 8, 1.0, false)


# ---------------------------------------------------------------- 店内

static func _interior(g: Node3D, walkable: bool) -> void:
	var it := K.group(g, "Interior")
	var shelf := K.toon(Color("#8a8477"), {"shade": 0.6, "rim": 0.0, "line": 0.0})
	var shelf_dark := K.toon(Color("#4d4a43"), {"shade": 0.7, "line": 0.0})
	var L := layout(walkable)

	# 冷柜（后墙）
	var fr: Dictionary = L["fridge"]
	var fc := Vector3((fr["x0"] + fr["x1"]) * 0.5, 0.0, (fr["z0"] + fr["z1"]) * 0.5)
	var fw: float = fr["x1"] - fr["x0"]
	var fd: float = fr["z1"] - fr["z0"]
	var fridge := K.toon(Color("#a8b2b9"), {"shade": 0.8, "rim": 0.0, "line": 0.0})
	K.box(it, Vector3(fw, 2.0, fd), Vector3(fc.x, FLOOR + 1.0, fc.z), fridge)
	K.box(it, Vector3(fw - 0.12, 1.64, 0.03), Vector3(fc.x, FLOOR + 1.07, fr["z1"] + 0.03), K.glow(Color("#bfe0ff"), 0.75))
	for i in 4:
		K.box(it, Vector3(fw - 0.18, 0.04, 0.04), Vector3(fc.x, FLOOR + 0.38 + i * 0.41, fr["z1"] + 0.05), shelf_dark, Vector3.ZERO, false)
	for row in 4:
		for col in 9:
			var c: Color = [Color("#d94a3c"), Color("#3f7fd9"), Color("#e8c34a"), Color("#f0eee6"), Color("#4aa86a")][(row * 3 + col) % 5]
			K.cyl(it, 0.043, 0.19, Vector3(fr["x0"] + 0.18 + col * 0.225, FLOOR + 0.52 + row * 0.41, fr["z1"] + 0.07), K.toon(c, {"shade": 0.95, "line": 0.0}), Vector3.ZERO, 6, -1.0, false)

	# 货架
	for r in L["racks"]:
		_rack(it, r["x0"], r["x1"], r["z"], shelf, shelf_dark)

	# 收银台。walkable 时沿东墙摆，整组绕 Y 转 −90°，正面朝过道；
	# 内部坐标沿用原来的相对偏移，所以两套布局的台面细节一模一样。
	var cspec: Dictionary = L["counter"]
	var counter := K.group(it, "Counter", Vector3(cspec["cx"], FLOOR, cspec["cz"]), Vector3(0, cspec["rot"], 0))
	var cw: float = cspec["w"]
	var cd: float = cspec["d"]
	K.box(counter, Vector3(cw, 0.92, cd), Vector3(0, 0.46, 0), K.toon(Color("#a39d90"), {"shade": 0.85, "line": 0.0}))
	K.box(counter, Vector3(cw + 0.06, 0.06, cd + 0.06), Vector3(0, 0.95, 0), K.toon(Color("#aca698"), {"shade": 0.9, "line": 0.0}))
	K.box(counter, Vector3(0.32, 0.24, 0.28), Vector3(0.25, 1.1, -0.05), K.toon(Color("#bcc0c6"), {"shade": 0.9, "line": 0.0}))
	K.box(counter, Vector3(0.2, 0.1, 0.02), Vector3(0.25, 1.15, 0.09), K.glow(Color("#9fe6c4"), 1.1))
	K.box(counter, Vector3(0.95, 0.03, 0.1), Vector3(-0.05, 2.6, -0.05), K.glow(Color("#ffe9c9"), 1.7), Vector3.ZERO, false)
	# 服务铃（交互目标就摆在台面上，看得见才按得下去）
	K.cyl(counter, 0.055, 0.05, Vector3(-0.22, 1.0, 0.02), K.toon(Color("#c9a24a"), {"shade": 0.55, "rim": 0.5, "line": 0.004}), Vector3.ZERO, 12)
	K.sphere(counter, 0.045, Vector3(-0.22, 1.03, 0.02), K.toon(Color("#e6c470"), {"shade": 0.5, "rim": 0.55, "line": 0.004}), Vector3.ZERO, 12, 0.7)

	# 杂志架（靠窗）
	var mg: Dictionary = L["magazine"]
	var mcx: float = (mg["x0"] + mg["x1"]) * 0.5
	var mcz: float = (mg["z0"] + mg["z1"]) * 0.5
	K.box(it, Vector3(mg["x1"] - mg["x0"], 1.1, mg["z1"] - mg["z0"]), Vector3(mcx, FLOOR + 0.55, mcz), shelf)
	for r in 3:
		var y := FLOOR + 0.4 + r * 0.32
		for c in 8:
			var col: Color = [Color("#d9584a"), Color("#4a9fd9"), Color("#f0d05a"), Color("#78c48e"), Color("#e8e4da")][(r + c) % 5]
			K.box(it, Vector3(0.06, 0.2, 0.13), Vector3(mcx + 0.15, y, mg["z0"] + 0.15 + c * 0.16), K.toon(col, {"shade": 0.95, "line": 0.0}), Vector3(0, 0, 8), false)

	# 靠窗促销堆头
	var promo_cols := [Color("#d94a3c"), Color("#e8c34a")]
	for i in L["promos"].size():
		var base: Vector3 = L["promos"][i]
		K.box(it, Vector3(0.62, 0.56, 0.42), base, K.toon(Color("#8f8778"), {"shade": 0.8, "line": 0.0}))
		for j in 6:
			K.box(it, Vector3(0.12, 0.16, 0.12), base + Vector3(-0.22 + (j % 3) * 0.22, 0.36 + (j / 3) * 0.18, -0.1 + (j % 2) * 0.15), K.toon(promo_cols[i % 2], {"shade": 0.9, "line": 0.0}), Vector3.ZERO, false)

	# walkable 时东墙会空出一大片，挂两排壁架补上（只做视觉，不占过道）
	if walkable:
		for wz in [-4.75, -4.05]:
			K.box(it, Vector3(0.22, 0.05, 1.15), Vector3(2.78, FLOOR + 1.25, wz), shelf)
			K.box(it, Vector3(0.22, 0.05, 1.15), Vector3(2.78, FLOOR + 1.75, wz), shelf)
			for k in 6:
				var pc: Color = [Color("#e0453a"), Color("#3f7fd9"), Color("#f0c93f"), Color("#5cbf7a")][k % 4]
				K.box(it, Vector3(0.14, 0.2, 0.16), Vector3(2.78, FLOOR + 1.38 + (k / 6) * 0.5, wz - 0.5 + k * 0.19), K.toon(pc, {"shade": 0.95, "line": 0.0}), Vector3.ZERO, false)


	# 店内暖光
	for p in [Vector3(0.2, 2.5, -1.9), Vector3(0.2, 2.5, -4.1), Vector3(2.0, 2.5, -3.2)]:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffdcae")
		l.light_energy = 1.0
		l.omni_range = 3.2
		l.omni_attenuation = 1.2
		l.shadow_enabled = true
		l.shadow_bias = 0.08
		l.position = p
		it.add_child(l)

	# 天花板灯带
	for z in [-1.9, -3.0, -4.1]:
		K.box(it, Vector3(3.4, 0.03, 0.15), Vector3(0.6, 2.9, z), K.glow(Color("#fff0d4"), 1.1), Vector3.ZERO, false)

	# 店外暖光溢出
	var spill := OmniLight3D.new()
	spill.light_color = Color("#ffd39a")
	spill.light_energy = 0.85
	spill.omni_range = 3.4
	spill.omni_attenuation = 1.6
	spill.position = Vector3(0.6, 1.8, 0.35)
	it.add_child(spill)


static func _rack(parent: Node3D, x0: float, x1: float, z: float, shelf: Material, dark: Material) -> void:
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	K.box(parent, Vector3(w, 0.12, 0.52), Vector3(cx, FLOOR + 0.06, z), dark)
	K.box(parent, Vector3(w, 0.05, 0.5), Vector3(cx, FLOOR + 0.4, z), shelf)
	K.box(parent, Vector3(w, 0.05, 0.5), Vector3(cx, FLOOR + 0.74, z), shelf)
	K.box(parent, Vector3(w, 0.05, 0.5), Vector3(cx, FLOOR + 1.08, z), shelf)
	K.box(parent, Vector3(w, 0.46, 0.06), Vector3(cx, FLOOR + 1.33, z), shelf)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(z * 1000.0) + 7
	var colors := [Color("#d9483f"), Color("#3f7fd9"), Color("#e8c34a"), Color("#efeee6"), Color("#4aa86a"), Color("#e08a3c")]
	for level in 3:
		var y: float = FLOOR + 0.14 + level * 0.34
		var px := x0 + 0.08
		while px < x1 - 0.1:
			var wd := rng.randf_range(0.09, 0.18)
			var ht := rng.randf_range(0.11, 0.2)
			var c: Color = colors[rng.randi() % colors.size()]
			K.box(parent, Vector3(wd, ht, rng.randf_range(0.16, 0.28)), Vector3(px + wd * 0.5, y + ht * 0.5, z + rng.randf_range(-0.06, 0.06)), K.toon(c, {"shade": 0.95, "line": 0.0}), Vector3.ZERO, false)
			px += wd + 0.032
