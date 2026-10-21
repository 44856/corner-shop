extends RefCounted

const K := preload("res://scripts/kit.gd")
const Goods := preload("res://scripts/goods.gd")

# 便利店主体：外墙 / 玻璃立面 / 自动门 / 雨棚 / 招牌 / 屋顶 / 店内

const X0 := -1.7
## 东墙从 3.1 推到 4.30：让出「柜台 + 收银员站位 + 休息室」这条 3.5m 的进深。
## 代价是后巷从 2.35m 收窄到 1.06m（见 props.gd 的 _alley）。
const X1 := 4.30
const Z0 := -5.5
const Z1 := -0.9
const FLOOR := 0.17
const TOP := 3.58
const GLASS_Z := Z1 - 0.11

## 货架排面：每层摆什么。字符串是 goods.gd 的类型名，"" 表示缺货（价签留着）。
## 内容刻意对齐 store_walk.gd 里 _on_rack 的三句台词 —— 玩家看到的和读到的要是同一批货。
const PLAN_FOOD := {
	"name": "INSTANT FOOD",
	"color": Color("#c0503f"),
	"rows": [
		["cup", "bowl", "cup", "cup", "bowl", "cup", "cup"],
		["can", "carton", "can", "carton", "can", "carton", "can"],
		["carton", "bag", "carton", "", "carton", "bag", "down"],
	],
}
const PLAN_SNACK := {
	"name": "SNACKS",
	"color": Color("#d08a3a"),
	"rows": [
		["bag", "bag", "bread", "bag", "bag", "bread", "bag"],
		["carton", "bag", "carton", "bag", "carton", "bag", "carton"],
		["bread", "carton", "bread", "carton", "bread", "carton", "bread"],
	],
}
const PLAN_HOUSE := {
	"name": "HOUSEHOLD",
	"color": Color("#3f6fa8"),
	"rows": [
		["tissue", "carton", "tissue", "carton", "tissue", "carton", "tissue"],
		["carton", "tissue", "carton", "tissue", "carton", "tissue", "carton"],
		["tissue", "carton", "tissue", "carton", "tissue", "carton", "tissue"],
	],
}


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
			# 两块横向货架，x -0.95..0.60，中间留 0.83m 过道。
			# 东端从 0.95 收到 0.60：柜台前面要让出 0.80m 的选购过道。
			"racks": [
				{"x0": -0.95, "x1": 0.60, "z": -3.85},
				{"x0": -0.95, "x1": 0.60, "z": -2.50},
			],
			# 冷柜贴后墙，前面留 0.85m 站立区
			"fridge": {"x0": 0.15, "x1": 2.55, "z0": -5.38, "z1": -4.96},
			# 收银台：长度 1.1 → 2.2（面积 0.66 → 1.32 m²，正好翻倍），
			# 沿东侧纵向摆，正面朝 −X。台面背后留 0.67m 收银员站位（x 2.03..2.70），
			# 站位背后就是休息室的隔墙 —— 收银员的背对着员工休息室，和真店一样。
			"counter": {"cx": 1.70, "cz": -2.70, "rot": -90.0, "w": 2.2, "d": 0.6},
			"magazine": {"x0": -1.48, "x1": -1.03, "z0": -2.65, "z1": -1.25},
			"promos": [Vector3(-0.55, FLOOR + 0.3, -1.35), Vector3(2.30, FLOOR + 0.3, -1.45)],
			# 员工休息室：占东侧一整条 1.38 × 4.16 = 5.74 m²，
			# 约等于改造前店堂面积（4.36 × 4.16 = 18.14 m²）的 1/3。
			# 不可进入：门是关着的，隔墙整面都带碰撞（见 collision_layout.gd）。
			"break_room": {
				"x0": 2.70, "x1": 4.08, "z0": -5.28, "z1": -1.12,
				"door_z0": -4.90, "door_z1": -4.00,
				"window_z0": -3.55, "window_z1": -2.35,
			},
		}
	return {
		"racks": [
			{"x0": -1.20, "x1": 3.40, "z": -4.25},
			{"x0": -1.20, "x1": 3.40, "z": -3.20},
			{"x0": -1.20, "x1": 3.40, "z": -2.15},
		],
		"fridge": {"x0": 0.15, "x1": 2.55, "z0": -5.38, "z1": -4.96},
		"counter": {"cx": 3.30, "cz": -1.55, "rot": 0.0, "w": 1.1, "d": 0.6},
		"magazine": {"x0": -1.475, "x1": -1.025, "z0": -2.65, "z1": -1.25},
		"promos": [Vector3(-0.55, FLOOR + 0.3, -1.35), Vector3(1.75, FLOOR + 0.3, -1.40)],
		# 展示版不做休息室，东侧直接摆一排货架填满橱窗
		"break_room": {},
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

	# 竖向分隔。2.70 是休息室隔墙的落点，4.08 是新的东墙角。
	for mx in [-1.48, -0.42, -0.30, 1.00, 1.12, 2.70, 4.08]:
		K.box(f, Vector3(0.09, 1.86, 0.16), Vector3(mx, 1.64, GLASS_Z), frame)
	# 门框更粗
	K.box(f, Vector3(0.1, 2.4, 0.18), Vector3(-0.36, 1.37, GLASS_Z), frame)
	K.box(f, Vector3(0.1, 2.4, 0.18), Vector3(1.06, 1.37, GLASS_Z), frame)
	K.box(f, Vector3(1.52, 0.12, 0.18), Vector3(0.35, 2.5, GLASS_Z), frame)

	# 窗玻璃
	K.box(f, Vector3(0.9, 1.82, 0.02), Vector3(-0.95, 1.64, GLASS_Z), glass, Vector3.ZERO, false)
	K.box(f, Vector3(1.5, 1.82, 0.02), Vector3(1.91, 1.64, GLASS_Z), glass, Vector3.ZERO, false)

	# 东段（2.70..4.08）不是玻璃，是休息室的外墙：
	# 店面不是整面通玻璃 —— 员工休息室不该开在橱窗里。
	# 只留一条高窗（透光不透人）和一块 STAFF ONLY 铭牌。
	var br: Dictionary = layout(true)["break_room"]
	var brw: float = br["x1"] - br["x0"]
	var brc: float = (br["x0"] + br["x1"]) * 0.5
	var wall_mat := K.toon(Color("#918a7c"), {"shade": 0.42, "rim": 0.18, "line": 0.009})
	K.box(f, Vector3(brw, 2.0, 0.16), Vector3(brc, 1.55, GLASS_Z), wall_mat)
	K.box(f, Vector3(0.86, 0.32, 0.03), Vector3(brc, 2.24, GLASS_Z + 0.09),
		K.toon(Color("#8fa3ad"), {"shade": 0.9, "rim": 0.2, "line": 0.004,
			"emit": Color("#2a3a44"), "emit_amt": 0.25}), Vector3.ZERO, false)
	K.box(f, Vector3(0.42, 0.2, 0.03), Vector3(brc, 1.42, GLASS_Z + 0.09),
		K.toon(Color("#1e242b"), {"shade": 0.7, "line": 0.005}), Vector3.ZERO, false)
	K.label(f, "STAFF ONLY", Vector3(brc, 1.42, GLASS_Z + 0.105), 0.062, Color("#e6dfd0"))

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
	K.quad(f, Vector2(0.32, 0.42), Vector3(2.30, 1.62, GLASS_Z + 0.02), poster_b)
	K.label(f, "NEW", Vector3(2.30, 1.69, GLASS_Z + 0.035), 0.095, Color("#22293a"))
	K.label(f, "HOT", Vector3(2.30, 1.54, GLASS_Z + 0.035), 0.095, Color("#b23a28"))


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

	# 雨棚跟着店面一起加宽：−1.75..4.35（原来到 3.15，休息室那段会漏雨）
	K.box(a, Vector3(6.1, 0.09, 1.1), Vector3(1.3, 2.6, -0.38), green, Vector3(7.0, 0, 0))
	K.box(a, Vector3(6.06, 0.03, 0.2), Vector3(1.3, 2.53, 0.09), white, Vector3(7.0, 0, 0))
	# 前缘板
	K.box(a, Vector3(6.1, 0.19, 0.07), Vector3(1.3, 2.45, 0.16), green)
	K.box(a, Vector3(6.1, 0.045, 0.02), Vector3(1.3, 2.38, 0.2), white)
	# 雨棚白色条纹
	for sx in [-1.15, -0.25, 0.65, 1.55, 2.45, 3.35]:
		K.box(a, Vector3(0.17, 0.012, 1.12), Vector3(sx, 2.652, -0.38), white, Vector3(7.0, 0, 0), false)

	# 雨棚下灯带
	K.box(a, Vector3(5.6, 0.02, 0.07), Vector3(1.3, 2.51, -0.02), K.glow(Color("#ffe3b4"), 1.9), Vector3.ZERO, false)
	# 斜撑
	var strut_mat := K.toon(Color("#2f3741"), {"shade": 0.6, "line": 0.005})
	for sx in [-1.3, 0.8, 2.6, 4.2]:
		K.strut(a, Vector3(sx, 3.1, Z1 + 0.01), Vector3(sx, 2.6, 0.06), 0.02, strut_mat, 6)
	# 落水管
	K.cyl(a, 0.045, 2.4, Vector3(-1.42, 1.35, 0.19), strut_mat, Vector3.ZERO, 8)


# ---------------------------------------------------------------- 招牌

static func _signage(g: Node3D) -> void:
	var s := K.group(g, "Signage")
	var board_z := Z1 + 0.055
	var indigo := K.toon(Color("#131c33"), {"shade": 0.7, "rim": 0.3, "line": 0.008, "emit": Color("#0a1c33"), "emit_amt": 0.4})

	K.box(s, Vector3(5.8, 0.64, 0.06), Vector3(1.3, 3.11, board_z), indigo)
	# 三色品牌条
	K.box(s, Vector3(5.8, 0.045, 0.065), Vector3(1.3, 2.82, board_z + 0.002), K.glow(Color("#2fbf71"), 1.25))
	K.box(s, Vector3(1.5, 0.045, 0.065), Vector3(-0.75, 2.82, board_z + 0.004), K.glow(Color("#ff8b3d"), 1.25))
	K.box(s, Vector3(0.9, 0.045, 0.065), Vector3(3.60, 2.82, board_z + 0.004), K.glow(Color("#3fa9ff"), 1.25))

	K.label(s, "HOSHI MART", Vector3(1.20, 3.25, board_z + 0.04), 0.32, Color("#ffffff"), Vector3.ZERO, 11, Color("#bfe4ff"))
	K.label(s, "OPEN 24 HOURS", Vector3(1.20, 2.93, board_z + 0.04), 0.075, Color("#7fc7f2"))

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
	while rx < X1:
		K.box(r, Vector3(0.03, 0.62, 0.03), Vector3(rx, TOP + 0.31, Z1 + 0.02), rail)
		rx += 0.75
	K.strut(r, Vector3(-1.55, TOP + 0.62, Z1 + 0.02), Vector3(X1 + 0.02, TOP + 0.62, Z1 + 0.02), 0.022, rail, 6)
	K.strut(r, Vector3(-1.55, TOP + 0.34, Z1 + 0.02), Vector3(X1 + 0.02, TOP + 0.34, Z1 + 0.02), 0.016, rail, 6)

	# 屋顶小航空灯
	K.sphere(r, 0.07, Vector3(0.75, TOP + 0.12, -1.35), K.glow(Color("#ff5a3a"), 2.2), Vector3.ZERO, 8, 1.0, false)


# ---------------------------------------------------------------- 店内

static func _interior(g: Node3D, walkable: bool) -> void:
	var it := K.group(g, "Interior")
	var shelf := K.toon(Color("#8a8477"), {"shade": 0.6, "rim": 0.0, "line": 0.0})
	var shelf_dark := K.toon(Color("#4d4a43"), {"shade": 0.7, "line": 0.0})
	var L := layout(walkable)

	_fridge(it, L["fridge"], walkable)

	# 货架。可玩版双面摆（进店先看南面，绕过去是北面），展示版只在橱窗外看，
	# 做单面就够 —— 省一半节点，效果没差别。
	var plans := [PLAN_FOOD, PLAN_SNACK, PLAN_HOUSE]
	for i in L["racks"].size():
		_rack(it, L["racks"][i], plans[i % plans.size()], plans[(i + 1) % plans.size()],
			shelf, shelf_dark, walkable)

	_counter(it, L["counter"])
	_magazine(it, L["magazine"], shelf, shelf_dark)
	_promos(it, L["promos"])

	# 东侧改成员工休息室（不可进入）。隔墙 / 门 / 窗都在 _break_room 里，
	# 原来贴东墙的两排壁架被它取代了。
	if walkable and not L["break_room"].is_empty():
		_break_room(it, L["break_room"], shelf, shelf_dark)

	# 收银员站位背后的墙（休息室隔墙）上挂香烟架：只占墙面不占地面，
	# 收银员才有完整的 0.67m 站立位。
	if walkable:
		_cigarette_rack(it, L["counter"], shelf, shelf_dark)

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

	# 过道补光：三盏主灯挂在 2.5m，光被层板挡得死死的，货架格子里是一片黑，
	# 商品像浮在暗格里。这两盏放在和货架同高（1.12m）、不投影、范围只有 2.2m ——
	# 只照亮排面，不改变店里的整体氛围，也不会漏到街上。
	for p in [Vector3(0.05, 1.12, -3.20), Vector3(1.45, 1.15, -4.35)]:
		var fill := OmniLight3D.new()
		fill.light_color = Color("#ffe3bd")
		fill.light_energy = 0.30
		fill.omni_range = 2.2
		fill.omni_attenuation = 1.4
		fill.shadow_enabled = false
		fill.position = p
		it.add_child(fill)

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


## 冷柜（后墙）。原来是一个实心盒子 + 一块贴在前面的发光板，商品只能浮在板子外面 ——
## 走近看是「一排彩条粘在白板上」。这里改成开口的壳：背板 / 侧板 / 顶底 + 四层搁板，
## 商品真的放在柜内，前面装四扇玻璃门。碰撞仍然是整块实体（见 collision_layout.gd），
## 玩家拉不开门，但隔着玻璃能看清里面卖什么。
static func _fridge(parent: Node3D, fr: Dictionary, walkable: bool) -> void:
	var g := K.group(parent, "Fridge")
	var x0: float = fr["x0"]
	var x1: float = fr["x1"]
	var z0: float = fr["z0"]
	var z1: float = fr["z1"]
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var fw := x1 - x0
	var fd := z1 - z0
	var h := 2.0
	var shell := K.toon(Color("#a8b2b9"), {"shade": 0.8, "rim": 0.0, "line": 0.0})
	var inner := K.toon(Color("#d8dde0"), {"shade": 0.95, "rim": 0.0, "line": 0.0})
	var frame := K.toon(Color("#4d535a"), {"shade": 0.6, "rim": 0.1, "line": 0.0})

	K.box(g, Vector3(fw, h, 0.05), Vector3(cx, FLOOR + h * 0.5, z0 + 0.025), shell)
	for sx in [x0 + 0.025, x1 - 0.025]:
		K.box(g, Vector3(0.05, h, fd), Vector3(sx, FLOOR + h * 0.5, cz), shell)
	K.box(g, Vector3(fw, 0.05, fd), Vector3(cx, FLOOR + h - 0.025, cz), shell)
	K.box(g, Vector3(fw, 0.12, fd), Vector3(cx, FLOOR + 0.06, cz), shell)
	# 内胆 + 背光：没有背光的话，柜里的东西在雨夜里就是一团黑
	K.box(g, Vector3(fw - 0.10, h - 0.20, 0.02), Vector3(cx, FLOOR + h * 0.5, z0 + 0.06), inner, Vector3.ZERO, false)
	K.box(g, Vector3(fw - 0.24, h - 0.36, 0.01), Vector3(cx, FLOOR + h * 0.5, z0 + 0.075), K.glow(Color("#dcefff"), 0.55), Vector3.ZERO, false)

	var levels := [0.42, 0.86, 1.30, 1.74]
	var kinds := ["bento", "onigiri", "bottle", "can"]
	for li in levels.size():
		var y: float = FLOOR + levels[li]
		K.box(g, Vector3(fw - 0.10, 0.03, fd - 0.08), Vector3(cx, y, cz + 0.01), inner, Vector3.ZERO, false)
		# 层板下的灯条：冷柜的「亮」来自每一层的灯管，不是一块大发光板
		K.box(g, Vector3(fw - 0.20, 0.012, 0.02), Vector3(cx, y - 0.022, z1 - 0.05), K.glow(Color("#eaf6ff"), 0.85), Vector3.ZERO, false)

		# 每层 8 个排面。层高 0.40，最上层的 0.22 瓶装刚好塞得下（顶到 2.04，柜顶 2.17）
		var n := 8
		var pitch := (fw - 0.20) / float(n)
		for i in n:
			var px := x0 + 0.10 + pitch * (i + 0.5)
			Goods.make(g, kinds[li], Vector3(px, y + 0.015, z1 - 0.09), Goods.tint(i * 3 + li), Vector3.ZERO)
			if walkable and i % 2 == 0:
				Goods.price_tag(g, Vector3(px, y - 0.022, z1 - 0.032), _price(kinds[li]), 0.0, 0.046)

	# 四扇玻璃门。没有门框的话整面看起来像「没装门」，有了才像冷柜。
	var doors := 4
	var dw := fw / float(doors)
	for d in doors:
		var dx := x0 + dw * (d + 0.5)
		K.box(g, Vector3(0.035, h - 0.10, 0.04), Vector3(x0 + dw * d, FLOOR + h * 0.5, z1 - 0.01), frame)
		K.quad(g, Vector2(dw - 0.05, h - 0.16), Vector3(dx, FLOOR + h * 0.5, z1 - 0.005),
			K.glass(Color(0.72, 0.84, 0.92, 0.05), 0.25), Vector3.ZERO, false)
		K.box(g, Vector3(0.022, 0.36, 0.03), Vector3(dx + dw * 0.36, FLOOR + 1.12, z1 + 0.01), frame, Vector3.ZERO, false)
	K.box(g, Vector3(0.035, h - 0.10, 0.04), Vector3(x1, FLOOR + h * 0.5, z1 - 0.01), frame)
	K.box(g, Vector3(fw, 0.04, 0.04), Vector3(cx, FLOOR + h - 0.06, z1 - 0.01), frame)
	K.box(g, Vector3(fw, 0.06, 0.04), Vector3(cx, FLOOR + 0.09, z1 - 0.01), frame)


## 一组货架。walkable 时双面摆（进店先看南面，绕过去是北面），
## 展示版只摆 +Z 面 —— 橱窗在外面，背面永远看不到，没必要多花一倍节点。
static func _rack(parent: Node3D, r: Dictionary, plan_a: Dictionary, plan_b: Dictionary,
		shelf: Material, dark: Material, walkable: bool) -> void:
	var x0: float = r["x0"]
	var x1: float = r["x1"]
	var z: float = r["z"]
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var levels := [0.4, 0.74, 1.08]
	# 立板要顶到分类牌底下。原来停在 1.12，而分类牌从 1.29 起 ——
	# 中间那段是空的，牌子和架子看起来是两件东西。
	var y_top := FLOOR + 1.40

	# 底座 / 两端立板 / 中隔板。原来的货架只有三块悬空横板，侧面看是「飘」的，
	# 而且背面完全透空 —— 站在过道里能一眼看穿整组货架。
	K.box(parent, Vector3(w, 0.12, 0.52), Vector3(cx, FLOOR + 0.06, z), dark)
	# 端板用深色：浅色的话从过道东头看过去是一整块米色墙，
	# 把整组货架的排面全挡住了。深色端板读起来才是「货架的金属侧板」。
	for ex in [x0 + 0.015, x1 - 0.015]:
		K.box(parent, Vector3(0.03, y_top - FLOOR, 0.5), Vector3(ex, (FLOOR + y_top) * 0.5, z), dark)
	# 中隔板当货架背板用，必须浅色。用深色的话每层都是一个黑洞，
	# 商品像浮在暗格里 —— 真店的货架背板是白色 / 浅灰的洞洞板。
	K.box(parent, Vector3(w - 0.06, y_top - FLOOR - 0.02, 0.02), Vector3(cx, (FLOOR + y_top) * 0.5, z), shelf)

	for y in levels:
		K.box(parent, Vector3(w, 0.05, 0.5), Vector3(cx, FLOOR + y, z), shelf)

	var sides: Array[int] = [1]
	if walkable:
		sides.append(-1)
	for side in sides:
		var plan: Dictionary = plan_a if side > 0 else plan_b
		var rows: Array = plan["rows"]
		var zf: float = z + side * 0.25
		var rot_y := 0.0 if side > 0 else 180.0

		# 顶部挡板 + 分区字。挡板下沿必须高过顶层商品（1.28 + 0.22 = 1.50）：
		# 原来压到 1.29，顶层整排商品被挡得只剩一条边。
		K.box(parent, Vector3(w, 0.30, 0.03), Vector3(cx, FLOOR + 1.55, z + side * 0.245), shelf)
		K.label(parent, plan["name"], Vector3(cx, FLOOR + 1.55, z + side * 0.262),
			0.070, Color("#3a3931"), Vector3(0, rot_y, 0))
		# 分类色条：整块米色挡板太像一堵墙，一条色带就够把「这是哪个区」说清楚
		K.box(parent, Vector3(w, 0.035, 0.008), Vector3(cx, FLOOR + 1.425, z + side * 0.262),
			K.toon(plan["color"], {"shade": 0.95, "line": 0.0}), Vector3.ZERO, false)
		# 踢脚板：底层货架下面是 28cm 的暗格，不封起来像个洞
		K.box(parent, Vector3(w, 0.28, 0.02), Vector3(cx, FLOOR + 0.26, z + side * 0.245), dark)

		for li in levels.size():
			var y: float = FLOOR + levels[li] + 0.025
			var kinds: Array = rows[li]
			# 排面密度：0.155 一格。原来按 0.21 算，1.55m 的货架只有 7 格，
			# 商品之间能塞下两个手指，看着像「没上货」。
			var n := clampi(int(w / 0.155), 6, 20)
			var pitch := w / float(n)

			# 前沿价签轨。没有它，商品看起来是「浮在层板边缘」的。
			if walkable:
				K.box(parent, Vector3(w, 0.030, 0.015),
					Vector3(cx, FLOOR + levels[li] + 0.043, zf + side * 0.006), dark, Vector3.ZERO, false)

			for i in n:
				var kind: String = kinds[i % kinds.size()]
				var px := x0 + pitch * (i + 0.5)
				# 商品要压到前沿：留 5cm 是价签轨的厚度，再往里就像「没上货」
				var pz := zf - side * 0.050
				# 价签先摆：缺货那一格也要留着（台词：价签还在，东西没了）
				if walkable and i % 2 == 0:
					Goods.price_tag(parent, Vector3(px, FLOOR + levels[li] + 0.043, zf + side * 0.014),
						_price(kind), rot_y)
				if kind == "":
					continue
				if kind == "down":
					# 倒下的泡芙盒：台词里说「顺手扶正」，那它得先倒着
					Goods.make(parent, "carton", Vector3(px, y + 0.040, pz),
						Goods.tint(i + li * 3), Vector3(0, rot_y, 90))
				else:
					Goods.make(parent, kind, Vector3(px, y, pz), Goods.tint(i * 3 + li),
						Vector3(0, rot_y, 0))
				# 中层补一排背库存：斜着看的时候，货架纵深不会是一片空板。
				# 只补中层 —— 上层俯视看得见，下层被前沿挡住，补了是白花节点。
				if walkable and li == 1:
					Goods.make(parent, kind, Vector3(px, y, pz - side * 0.115),
						Goods.tint(i * 3 + li + 4), Vector3(0, rot_y, 0))


## 收银台。walkable 时沿东墙摆，整组绕 Y 转 −90°，正面朝过道；
## 内部坐标沿用原来的相对偏移，所以两套布局的台面细节一模一样。
static func _counter(parent: Node3D, cspec: Dictionary) -> void:
	var counter := K.group(parent, "Counter", Vector3(cspec["cx"], FLOOR, cspec["cz"]),
		Vector3(0, cspec["rot"], 0))
	var cw: float = cspec["w"]
	var cd: float = cspec["d"]
	K.box(counter, Vector3(cw, 0.92, cd), Vector3(0, 0.46, 0), K.toon(Color("#a39d90"), {"shade": 0.85, "line": 0.0}))
	K.box(counter, Vector3(cw + 0.06, 0.06, cd + 0.06), Vector3(0, 0.95, 0), K.toon(Color("#aca698"), {"shade": 0.9, "line": 0.0}))
	# 收银机：靠收银员那一侧、压在柜台南端。
	# 别摆在台面正中 —— 正中正好挡住对内小窗，隔着窗什么都看不见。
	K.box(counter, Vector3(0.32, 0.24, 0.28), Vector3(0.68, 1.1, -0.18), K.toon(Color("#bcc0c6"), {"shade": 0.9, "line": 0.0}))
	K.box(counter, Vector3(0.2, 0.1, 0.02), Vector3(0.68, 1.15, -0.04), K.glow(Color("#9fe6c4"), 1.1))
	K.box(counter, Vector3(0.95, 0.03, 0.1), Vector3(-0.05, 2.6, -0.05), K.glow(Color("#ffe9c9"), 1.7), Vector3.ZERO, false)
	# 服务铃（交互目标就摆在台面上，看得见才按得下去）
	K.cyl(counter, 0.055, 0.05, Vector3(-0.22, 1.0, 0.02), K.toon(Color("#c9a24a"), {"shade": 0.55, "rim": 0.5, "line": 0.004}), Vector3.ZERO, 12)
	K.sphere(counter, 0.045, Vector3(-0.22, 1.03, 0.02), K.toon(Color("#e6c470"), {"shade": 0.5, "rim": 0.55, "line": 0.004}), Vector3.ZERO, 12, 0.7)

	# 刷卡机：台面上除了铃和收银机，总得有个「正在营业」的证据
	K.box(counter, Vector3(0.10, 0.028, 0.13), Vector3(0.32, 0.964, 0.10),
		K.toon(Color("#33383f"), {"shade": 0.8, "line": 0.0}), Vector3(0, 18, 0))
	K.box(counter, Vector3(0.076, 0.014, 0.09), Vector3(0.32, 0.982, 0.10),
		K.glow(Color("#8fe3b8"), 0.7), Vector3(0, 18, 0), false)

	# 摊开的杂志。HUD 台词里说「收银台上那本翻到一半的杂志」，原来台上并没有 ——
	# 说了就得有，否则这句氛围文案是空的。
	var mag := K.group(counter, "OpenMag", Vector3(-0.78, 0.955, 0.06), Vector3(0, -12, 0))
	K.box(mag, Vector3(0.30, 0.006, 0.22), Vector3(0, 0.003, 0), K.toon(Color("#e6dfcd"), {"shade": 0.98, "line": 0.0}), Vector3.ZERO, false)
	K.quad(mag, Vector2(0.135, 0.19), Vector3(-0.074, 0.007, 0), K.toon(Color("#cfc6b1"), {"shade": 0.99, "line": 0.0}), Vector3(-90, 0, 0), false)
	K.quad(mag, Vector2(0.135, 0.19), Vector3(0.074, 0.007, 0), K.toon(Color("#f6f1e2"), {"shade": 0.99, "line": 0.0}), Vector3(-90, 0, 0), false)


## 杂志架（靠窗）。原来的做法是一整块实心方块，杂志贴在方块正面 ——
## 等于埋进墙里，外面只看得见几条彩边。这里改成背板 + 三层搁板 + 前挡条，
## 杂志斜靠在搁板上，封面朝 +X（店内方向）。
static func _magazine(parent: Node3D, mg: Dictionary, shelf: Material, dark: Material) -> void:
	var g := K.group(parent, "Magazine")
	var x0: float = mg["x0"]
	var x1: float = mg["x1"]
	var z0: float = mg["z0"]
	var z1: float = mg["z1"]
	var cz := (z0 + z1) * 0.5
	var top := FLOOR + 1.20
	var titles := ["WEEKLY", "MODE", "CAR", "GAME", "TRAVEL", "COOK", "BIKE", "FISH"]

	K.box(g, Vector3(0.02, top - FLOOR, z1 - z0), Vector3(x0 + 0.02, (FLOOR + top) * 0.5, cz), dark)
	K.box(g, Vector3(x1 - x0, top - FLOOR, 0.02), Vector3((x0 + x1) * 0.5, (FLOOR + top) * 0.5, z0 + 0.01), shelf)
	K.box(g, Vector3(x1 - x0, top - FLOOR, 0.02), Vector3((x0 + x1) * 0.5, (FLOOR + top) * 0.5, z1 - 0.01), shelf)
	K.box(g, Vector3(x1 - x0, 0.03, z1 - z0), Vector3((x0 + x1) * 0.5, top - 0.015, cz), shelf)

	var tiers := [0.30, 0.66, 1.02]
	for ti in tiers.size():
		var y: float = FLOOR + tiers[ti]
		K.box(g, Vector3(x1 - x0 - 0.04, 0.03, z1 - z0 - 0.04), Vector3((x0 + x1) * 0.5 + 0.01, y, cz), shelf)
		# 前挡条：杂志是斜靠着的，没有挡条会「滑出来」
		K.box(g, Vector3(0.018, 0.035, z1 - z0 - 0.04), Vector3(x1 - 0.02, y + 0.02, cz), dark, Vector3.ZERO, false)
		for i in 5:
			var mz := z0 + 0.16 + i * 0.255
			Goods.magazine(g, Vector3(x1 - 0.10, y + 0.03, mz),
				Goods.tint(ti * 3 + i), titles[(ti * 5 + i) % titles.size()], Vector3(-12, 90, 0))


## 靠窗促销堆头：纸箱底座 + 手写价签 + 两排货。
static func _promos(parent: Node3D, promos: Array) -> void:
	for i in promos.size():
		var base: Vector3 = promos[i]
		var g := K.group(parent, "Promo", base)
		K.box(g, Vector3(0.62, 0.56, 0.42), Vector3.ZERO, K.toon(Color("#8f8778"), {"shade": 0.8, "line": 0.0}))
		# 纸箱挡板：立在底座后沿、高出商品一截，正面朝 +Z（门口方向）。
		# 原来朝 −Z，从街上和进门第一眼看到的都是纸板背面。
		K.quad(g, Vector2(0.50, 0.26), Vector3(0, 0.43, -0.200), K.toon(Color("#d9cbb2"), {"shade": 0.95, "line": 0.0}), Vector3.ZERO, false)
		K.label(g, "SALE", Vector3(0, 0.48, -0.196), 0.07, Color("#b8352a"))
		K.label(g, "¥3.9", Vector3(0, 0.40, -0.196), 0.05, Color("#2b2f36"))
		var kind := "cup" if i == 0 else "bottle"
		for j in 6:
			Goods.make(g, kind, Vector3(-0.22 + (j % 3) * 0.22, 0.28, -0.06 + (j / 3) * 0.14),
				Goods.tint(j + i * 3), Vector3.ZERO)


## 香烟架：挂在休息室隔墙（窗南侧那段实墙）上，只占墙面不占地面，
## 收银员才有完整的 0.67m 站立位。三排烟盒面朝 −X（过道方向）。
static func _cigarette_rack(parent: Node3D, cspec: Dictionary, shelf: Material, dark: Material) -> void:
	var cz: float = cspec["cz"]
	K.box(parent, Vector3(0.02, 0.96, 1.02), Vector3(2.575, FLOOR + 1.58, cz + 0.95), dark)
	for i in 3:
		K.box(parent, Vector3(0.16, 0.05, 1.00), Vector3(2.56, FLOOR + 1.30 + i * 0.30, cz + 0.95), shelf)
		for j in 8:
			Goods.make(parent, "cigarette",
				Vector3(2.545, FLOOR + 1.325 + i * 0.30, cz + 0.51 + j * 0.125),
				Goods.tint(i * 5 + j), Vector3(0, -90, 0))
	# 收银员的凳子（雨夜无人店：椅子空着，但位置是留出来的）
	K.cyl(parent, 0.17, 0.05, Vector3(2.36, FLOOR + 0.44, cz - 0.35), K.toon(Color("#4a4038"), {"shade": 0.7, "line": 0.0}), Vector3.ZERO, 12)
	K.cyl(parent, 0.03, 0.42, Vector3(2.36, FLOOR + 0.21, cz - 0.35), K.toon(Color("#5c6066"), {"line": 0.0}), Vector3.ZERO, 8)


## 价签文字。缺货（""）也走这里 —— 那一格要留价签。
static func _price(kind: String) -> String:
	match kind:
		"cup": return "¥3.9"
		"bowl": return "¥5.5"
		"can": return "¥2.8"
		"bottle": return "¥1.5"
		"bread": return "¥2.2"
		"onigiri": return "¥1.8"
		"bento": return "¥5.8"
		"tissue": return "¥4.5"
		"bag": return "¥2.6"
		_: return "¥4.2"


# ---------------------------------------------------------------- 员工休息室

## 东侧一整条 1.38 × 4.16 = 5.74m² 的休息室，约等于改造前店堂（18.14m²）的 1/3。
##
## **不可进入**：门是关着的，隔墙整面都有碰撞（collision_layout.gd），
## 玩家只能隔着对内小窗看见里面 —— 有桌椅、储物柜、微波炉，但没人。
## 这也是它存在的意义：让「这家店有人上夜班」这件事有落点，而不是一句设定。
static func _break_room(parent: Node3D, br: Dictionary, shelf: Material, dark: Material) -> void:
	var g := K.group(parent, "BreakRoom")
	var x0: float = br["x0"]
	var x1: float = br["x1"]
	var z0: float = br["z0"]
	var z1: float = br["z1"]
	var dz0: float = br["door_z0"]
	var dz1: float = br["door_z1"]
	var wz0: float = br["window_z0"]
	var wz1: float = br["window_z1"]
	var t := 0.12
	var y0 := FLOOR
	var y1 := 2.87
	var cx := x0 - t * 0.5

	var wall := K.toon(Color("#8d8678"), {"shade": 0.62, "rim": 0.0, "line": 0.0})
	var trim := K.toon(Color("#5d564b"), {"shade": 0.6, "line": 0.005})

	# 隔墙按「实墙 / 门洞 / 窗洞」分段拼 —— 盒子挖不了洞，只能绕开
	var segs := [
		[z0, dz0, y0, y1],        # 门北侧
		[dz1, wz0, y0, y1],       # 门与窗之间
		[wz1, z1, y0, y1],        # 窗南侧
		[dz0, dz1, 2.20, y1],     # 门楣
		[wz0, wz1, y0, 1.00],     # 窗台以下
		[wz0, wz1, 1.90, y1],     # 窗楣以上
	]
	for s in segs:
		K.box(g, Vector3(t, float(s[3]) - float(s[2]), float(s[1]) - float(s[0])),
			Vector3(cx, (float(s[2]) + float(s[3])) * 0.5, (float(s[0]) + float(s[1])) * 0.5), wall)

	# 关着的门：门框 + 门板 + 上半截磨砂玻璃（透光，看不清人）
	var dc := (dz0 + dz1) * 0.5
	K.box(g, Vector3(t + 0.04, 2.03, 0.06), Vector3(cx, y0 + 1.015, dz0 - 0.03), trim)
	K.box(g, Vector3(t + 0.04, 2.03, 0.06), Vector3(cx, y0 + 1.015, dz1 + 0.03), trim)
	K.box(g, Vector3(t + 0.04, 0.06, dz1 - dz0 + 0.12), Vector3(cx, y0 + 2.23, dc), trim)
	K.box(g, Vector3(0.05, 2.03, dz1 - dz0 - 0.02), Vector3(cx + 0.02, y0 + 1.015, dc),
		K.toon(Color("#6a6055"), {"shade": 0.55, "rim": 0.15, "line": 0.005}))
	K.box(g, Vector3(0.02, 0.62, dz1 - dz0 - 0.18), Vector3(cx + 0.05, y0 + 1.58, dc),
		K.glass(Color(0.62, 0.66, 0.62, 0.35), 0.1), Vector3.ZERO, false)
	K.cyl(g, 0.014, 0.12, Vector3(cx + 0.07, y0 + 1.02, dz1 - 0.18), trim, Vector3(0, 0, 90), 6)
	K.label(g, "STAFF", Vector3(cx + 0.075, y0 + 1.80, dc), 0.055, Color("#d8d2c4"), Vector3(0, -90, 0))

	# 对内小窗：卖场这边能看见里面的灯和桌椅。
	# 玻璃要够清（alpha 0.06）：这是「展示用」的窗，不是磨砂隔断，
	# 糊一点整间屋子就只剩一片奶白。
	K.box(g, Vector3(t + 0.04, 0.05, wz1 - wz0 + 0.06), Vector3(cx, 1.00, (wz0 + wz1) * 0.5), trim)
	K.box(g, Vector3(t + 0.04, 0.05, wz1 - wz0 + 0.06), Vector3(cx, 1.90, (wz0 + wz1) * 0.5), trim)
	K.box(g, Vector3(0.02, 0.9, wz1 - wz0), Vector3(cx, 1.45, (wz0 + wz1) * 0.5),
		K.glass(Color(0.74, 0.80, 0.82, 0.06), 0.03), Vector3.ZERO, false)

	# ---- 室内陈设（只在窗外 / 门玻璃外看得到，玩家进不来）----
	var wood := K.toon(Color("#7a6448"), {"shade": 0.55, "rim": 0.15, "line": 0.005})
	var steel := K.toon(Color("#8b9099"), {"shade": 0.6, "rim": 0.35, "line": 0.005})
	var rx := (x0 + x1) * 0.5

	# 北端：水槽 + 微波炉
	K.box(g, Vector3(1.20, 0.86, 0.46), Vector3(rx, y0 + 0.43, -5.02), wood)
	K.box(g, Vector3(1.24, 0.05, 0.5), Vector3(rx, y0 + 0.88, -5.02), K.toon(Color("#a9a396"), {"shade": 0.9, "line": 0.0}))
	K.box(g, Vector3(0.34, 0.06, 0.28), Vector3(rx - 0.24, y0 + 0.87, -5.02), K.toon(Color("#2b3138"), {"shade": 0.8, "line": 0.0}), Vector3.ZERO, false)
	K.cyl(g, 0.014, 0.24, Vector3(rx - 0.24, y0 + 1.0, -5.16), steel, Vector3.ZERO, 6)
	K.cyl(g, 0.012, 0.12, Vector3(rx - 0.24, y0 + 1.11, -5.10), steel, Vector3(90, 0, 0), 6)
	K.box(g, Vector3(0.42, 0.28, 0.34), Vector3(rx + 0.28, y0 + 1.05, -5.02), K.toon(Color("#c8c3b8"), {"shade": 0.75, "rim": 0.2, "line": 0.005}))
	K.box(g, Vector3(0.3, 0.18, 0.01), Vector3(rx + 0.28, y0 + 1.05, -4.84), K.toon(Color("#3a3f46"), {"shade": 0.9, "line": 0.0}), Vector3.ZERO, false)

	# 员工冰箱
	K.box(g, Vector3(0.5, 0.9, 0.5), Vector3(x1 - 0.26, y0 + 0.45, -4.42), K.toon(Color("#b8bcc0"), {"shade": 0.85, "rim": 0.25, "line": 0.005}))
	K.box(g, Vector3(0.02, 0.9, 0.5), Vector3(x1 - 0.51, y0 + 0.45, -4.42), K.toon(Color("#9aa0a6"), {"line": 0.0}), Vector3.ZERO, false)
	K.cyl(g, 0.012, 0.14, Vector3(x1 - 0.53, y0 + 0.72, -4.30), steel, Vector3.ZERO, 6)

	# 桌椅：一张小桌 + 两把凳子（夜班的人坐这儿吃个饭）。
	# 桌子压在小窗正对面（窗 z −3.55..−2.35，桌心 −2.98），
	# 从卖场看进去先看到桌子和杯面，才知道这屋是干什么的。
	var tz := -2.98
	K.box(g, Vector3(0.78, 0.05, 0.56), Vector3(rx + 0.06, y0 + 0.72, tz), wood)
	for lx in [-0.32, 0.32]:
		for lz in [-0.2, 0.2]:
			K.box(g, Vector3(0.04, 0.72, 0.04), Vector3(rx + 0.06 + lx, y0 + 0.36, tz + lz), steel, Vector3.ZERO, false)
	K.cyl(g, 0.16, 0.04, Vector3(rx - 0.34, y0 + 0.45, tz + 0.26), K.toon(Color("#3f4750"), {"shade": 0.7, "line": 0.0}), Vector3.ZERO, 10)
	K.cyl(g, 0.025, 0.43, Vector3(rx - 0.34, y0 + 0.22, tz + 0.26), steel, Vector3.ZERO, 6)
	K.cyl(g, 0.16, 0.04, Vector3(rx + 0.42, y0 + 0.45, tz - 0.30), K.toon(Color("#3f4750"), {"shade": 0.7, "line": 0.0}), Vector3.ZERO, 10)
	K.cyl(g, 0.025, 0.43, Vector3(rx + 0.42, y0 + 0.22, tz - 0.30), steel, Vector3.ZERO, 6)
	# 桌上：一个杯面 + 一罐咖啡
	K.cyl(g, 0.055, 0.1, Vector3(rx - 0.06, y0 + 0.79, tz + 0.08), K.toon(Color("#e8e2d2"), {"shade": 0.9, "line": 0.0}), Vector3.ZERO, 10)
	K.cyl(g, 0.033, 0.12, Vector3(rx + 0.16, y0 + 0.80, tz - 0.08), K.toon(Color("#c04a3a"), {"shade": 0.85, "line": 0.0}), Vector3.ZERO, 8)

	# 南端：一排储物柜（3 格）
	for i in 3:
		var lz0 := -2.28 + i * 0.37
		K.box(g, Vector3(0.34, 1.88, 0.35), Vector3(x1 - 0.17, y0 + 0.94, lz0), K.toon(Color("#5f6a72"), {"shade": 0.6, "rim": 0.25, "line": 0.005}))
		K.box(g, Vector3(0.02, 1.72, 0.29), Vector3(x1 - 0.345, y0 + 0.94, lz0), K.toon(Color("#4b555c"), {"line": 0.0}), Vector3.ZERO, false)
		K.box(g, Vector3(0.015, 0.05, 0.05), Vector3(x1 - 0.355, y0 + 0.94, lz0 + 0.09), steel, Vector3.ZERO, false)
		K.box(g, Vector3(0.03, 0.09, 0.05), Vector3(x1 - 0.35, y0 + 1.68, lz0), K.toon(Color("#d8d3c6"), {"line": 0.0}), Vector3.ZERO, false)

	# 东墙上的海报：从窗口望进去，视线尽头总得有点东西，
	# 否则只剩一面空墙，屋子看着像没建完。
	K.quad(g, Vector2(0.42, 0.58), Vector3(x1 - 0.12, y0 + 1.60, -2.98),
		K.toon(Color("#9d9078"), {"shade": 0.88, "line": 0.004}), Vector3(0, -90, 0))
	for i in 3:
		K.quad(g, Vector2(0.26, 0.02), Vector3(x1 - 0.115, y0 + 1.72 - i * 0.10, -2.98),
			K.toon(Color("#8a7f6a"), {"shade": 0.9, "line": 0.0}), Vector3(0, -90, 0), false)

	# 墙上的钟 / 排班表
	K.cyl(g, 0.11, 0.03, Vector3(cx + 0.09, 2.28, -3.10), K.toon(Color("#d9d4c6"), {"shade": 0.95, "line": 0.0}), Vector3(0, 0, 90), 16)
	K.quad(g, Vector2(0.34, 0.44), Vector3(cx + 0.075, 1.62, -4.62), K.toon(Color("#e6e0d2"), {"shade": 0.9, "line": 0.003}), Vector3(0, -90, 0))
	for i in 4:
		K.quad(g, Vector2(0.22, 0.012), Vector3(cx + 0.08, 1.74 - i * 0.06, -4.62), K.toon(Color("#8a8578"), {"shade": 0.9, "line": 0.0}), Vector3(0, -90, 0), false)

	# 灯：一盏暖光 + 一条灯带，透到卖场这边就是「有人还在上班」的味道
	var l := OmniLight3D.new()
	l.light_color = Color("#ffd9a8")
	l.light_energy = 0.62
	l.omni_range = 2.8
	l.omni_attenuation = 1.5
	# 必须开阴影：否则这盏灯会直接穿过隔墙照到卖场，
	# 收银台那一片会白得像开了顶灯（实测过，不开就过曝）
	l.shadow_enabled = true
	l.shadow_bias = 0.08
	l.position = Vector3(rx, 2.45, -3.2)
	g.add_child(l)
	K.box(g, Vector3(1.0, 0.03, 0.14), Vector3(rx, 2.86, -3.2), K.glow(Color("#fff0d4"), 1.0), Vector3.ZERO, false)
	K.box(g, Vector3(1.0, 0.03, 0.14), Vector3(rx, 2.86, -4.6), K.glow(Color("#fff0d4"), 0.9), Vector3.ZERO, false)
