extends RefCounted
## 星见町商店街的碰撞层。
##
## 视觉（town.gd / shop_row.gd）与碰撞分两处写，但尺寸都从对方的公开常量读：
##   - 街道高度、路缘、店面进深 → Town.*
##   - 两排建筑体块 → ShopRow.NORTH / ShopRow.SOUTH
## 改建筑宽度时只改 ShopRow 那张表，这里自动跟着变。
##
## 原则沿用 collision_layout.gd：
##   1. 只挡大体块（地面 / 建筑 / 杆件 / 候车亭 / 车），招牌、暖帘、花盆不挡；
##   2. 16cm 路缘用隐形斜面补，不给角色加自动上台阶；
##   3. 便利店那组墙 / 货架 / 柜台直接复用 collision_layout，不抄第二份。

const Town := preload("res://scripts/town.gd")
const ShopRow := preload("res://scripts/shop_row.gd")
const CollisionLayout := preload("res://scripts/collision_layout.gd")

const WALK_Y := Town.WALK_Y


static func build(root: Node3D) -> void:
	var g := Node3D.new()
	g.name = "TownCollision"
	root.add_child(g)
	_ground(g)
	_store(g)
	_buildings(g)
	_alley(g)
	_street_furniture(g)
	_bounds(g)


# ---------------------------------------------------------------- 地面

static func _ground(g: Node3D) -> void:
	# 底座 / 马路：35.6 × 15.2，顶面 0
	CollisionLayout.solid(g, Vector3(Town.CENTER_X, -1.0, Town.CENTER_Z),
		Vector3(Town.X1 - Town.X0, 2.0, Town.Z1 - Town.Z0))

	# 北人行道（含路缘石，到 z 2.07）与南人行道（含路缘石，从 z 5.0 起）
	CollisionLayout.solid(g, Vector3(Town.CENTER_X, WALK_Y - 1.0, (Town.Z0 + 2.07) * 0.5),
		Vector3(Town.X1 - Town.X0, 2.0, 2.07 - Town.Z0))
	CollisionLayout.solid(g, Vector3(Town.CENTER_X, WALK_Y - 1.0, (Town.ROAD_Z1 + Town.SOUTH_WALK_Z1) * 0.5),
		Vector3(Town.X1 - Town.X0, 2.0, Town.SOUTH_WALK_Z1 - Town.ROAD_Z1))

	# 16cm 路缘：坡铺在马路一侧，别铺到石头底下
	CollisionLayout.slope(g, Vector3(Town.CENTER_X, 0.0, 2.195), 17.6, 0.125, 0.0, WALK_Y, 180.0)
	CollisionLayout.slope(g, Vector3(Town.CENTER_X, 0.0, Town.ROAD_Z1 - 0.125), 17.6, 0.125,
		0.0, WALK_Y, 0.0)

	# 投币停车场：和人行道同高，人可以走进去
	CollisionLayout.solid(g, Vector3(1.1, WALK_Y - 1.0, 7.95), Vector3(4.2, 2.0, 3.3))

	# 便利店店内地面 + 90mm 门槛斜面
	CollisionLayout.store_ground(g)


# ---------------------------------------------------------------- 便利店

static func _store(g: Node3D) -> void:
	CollisionLayout.store_collision(g)


# ---------------------------------------------------------------- 两排建筑

static func _buildings(g: Node3D) -> void:
	for b in ShopRow.NORTH:
		var h: float = b["h"]
		var w: float = float(b["x1"]) - float(b["x0"])
		CollisionLayout.solid(g,
			Vector3((float(b["x0"]) + float(b["x1"])) * 0.5, (WALK_Y + h) * 0.5,
				(ShopRow.N_FRONT + ShopRow.N_BACK) * 0.5),
			Vector3(w, h - WALK_Y, ShopRow.N_FRONT - ShopRow.N_BACK))

	for b in ShopRow.SOUTH:
		var h: float = b["h"]
		var w: float = float(b["x1"]) - float(b["x0"])
		var z0: float = ShopRow.S_FRONT
		if b["name"] == "corner_house":
			# 街角民居退到院子里，z 6.3..7.3 是前院，由矮墙挡住
			z0 = 7.3
		CollisionLayout.solid(g,
			Vector3((float(b["x0"]) + float(b["x1"])) * 0.5, (WALK_Y + h) * 0.5,
				(z0 + ShopRow.S_BACK) * 0.5),
			Vector3(w, h - WALK_Y, ShopRow.S_BACK - z0))

	# 口袋公园矮墙（23.0..27.0）与街角民居院墙（27.0..30.0）
	CollisionLayout.solid(g, Vector3(25.0, WALK_Y + 0.63, ShopRow.S_FRONT),
		Vector3(3.8, 1.26, 0.3))
	CollisionLayout.solid(g, Vector3(28.5, WALK_Y + 0.6, ShopRow.S_FRONT),
		Vector3(3.0, 1.2, 0.28))

	# 停车场后墙
	CollisionLayout.solid(g, Vector3(1.1, WALK_Y + 0.6, 9.55), Vector3(4.2, 1.2, 0.24))


# ---------------------------------------------------------------- 缝隙与后巷

static func _alley(g: Node3D) -> void:
	# 便利店东侧后巷：铁栏 + 贩卖机
	CollisionLayout.solid(g, Vector3(5.36, 1.1, -3.02), Vector3(0.3, 2.2, 5.0))
	CollisionLayout.solid(g, Vector3(4.83, WALK_Y + 0.95, -4.95), Vector3(1.02, 1.9, 0.76))

	# 居酒屋与洗衣店之间 1.2m 的缝隙：能走进去，但尽头有实墙
	CollisionLayout.solid(g, Vector3(13.6, WALK_Y + 1.6, -4.35), Vector3(1.2, 3.2, 0.24))
	CollisionLayout.solid(g, Vector3(13.6, WALK_Y + 0.95, -0.58), Vector3(1.02, 1.9, 0.76))


# ---------------------------------------------------------------- 街具

static func _street_furniture(g: Node3D) -> void:
	# 电线杆
	for px in Town.POLES:
		CollisionLayout.pillar(g, Vector3(float(px), WALK_Y + 3.15, Town.POLE_Z), 0.145, 6.3)
	CollisionLayout.pillar(g, Town.SOUTH_POLE + Vector3(0, 2.6, 0), 0.12, 5.2)

	# 路灯
	for spec in Town.LAMPS:
		CollisionLayout.pillar(g, Vector3(float(spec["x"]), WALK_Y + 2.15, float(spec["z"])),
			0.075, 4.3)

	# 东口牌楼两根柱子
	for z in [Town.GATE_Z0, Town.GATE_Z1]:
		CollisionLayout.pillar(g, Vector3(Town.GATE_X, WALK_Y + 2.55, z), 0.2, 5.1)

	# 候车亭：两根立柱 + 背板 + 长椅
	CollisionLayout.pillar(g, Vector3(23.65, WALK_Y + 1.275, 5.55), 0.05, 2.55)
	CollisionLayout.pillar(g, Vector3(25.05, WALK_Y + 1.275, 5.55), 0.05, 2.55)
	CollisionLayout.solid(g, Vector3(24.35, WALK_Y + 1.55, 6.16), Vector3(1.8, 1.5, 0.06))
	CollisionLayout.solid(g, Vector3(24.35, WALK_Y + 0.26, 5.86), Vector3(1.5, 0.52, 0.4))

	# 凸面镜、停车场计费机与招牌、轻自动车
	CollisionLayout.pillar(g, Vector3(26.45, WALK_Y + 1.45, 1.92), 0.045, 2.9)
	CollisionLayout.solid(g, Vector3(-0.55, WALK_Y + 0.625, 6.7), Vector3(0.34, 1.25, 0.3))
	CollisionLayout.pillar(g, Vector3(2.85, WALK_Y + 1.15, 6.55), 0.04, 2.3)
	CollisionLayout.solid(g, Vector3(1.55, WALK_Y + 0.9, 8.15), Vector3(1.5, 1.8, 2.96))

	# 南侧护栏（x 16.8..21.4）：整段实心，过街只能走斑马线
	CollisionLayout.solid(g, Vector3(19.1, WALK_Y + 0.45, Town.ROAD_Z1 + 0.06),
		Vector3(4.8, 0.9, 0.08))


# ---------------------------------------------------------------- 边界

static func _bounds(g: Node3D) -> void:
	var h := 4.0
	var t := 0.2
	CollisionLayout.solid(g, Vector3(Town.CENTER_X, h * 0.5, Town.Z0 + t * 0.5),
		Vector3(Town.X1 - Town.X0, h, t))
	CollisionLayout.solid(g, Vector3(Town.CENTER_X, h * 0.5, Town.Z1 - t * 0.5),
		Vector3(Town.X1 - Town.X0, h, t))
	CollisionLayout.solid(g, Vector3(Town.X0 + t * 0.5, h * 0.5, Town.CENTER_Z),
		Vector3(t, h, Town.Z1 - Town.Z0))
	CollisionLayout.solid(g, Vector3(Town.X1 - t * 0.5, h * 0.5, Town.CENTER_Z),
		Vector3(t, h, Town.Z1 - Town.Z0))
