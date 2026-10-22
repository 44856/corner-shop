extends RefCounted
## 可玩版本的碰撞体：把「看得见」的几何换成「走得到」的胶囊/盒子。
##
## 原场景是纯展示用的：所有 MeshInstance3D 都没有碰撞，相机在天上飞，不需要。
## 一旦人物落地，就得有一层简化碰撞。
##
## 原则：
##   1. 只挡大体块（地面 / 墙 / 货架 / 台面 / 杆件），小摆件该穿就穿，不跟手感较劲；
##   2. 尺寸直接读 store.gd / street.gd 里的常量与 layout()，不另抄一份数字；
##   3. 需要「走上去」的 16–25cm 高差（路缘、店门槛）用隐形斜面补，而不是给
##      CharacterBody3D 加自动上台阶 —— 那套逻辑一改，草原场景的手感也会跟着变。

const Store := preload("res://scripts/store.gd")

## 路缘石 / 人行道顶面高度
const WALK_Y := 0.16
## 底座半宽（street.gd 的 B）
const BASE_HALF := 5.6


static func build(root: Node3D) -> void:
	var g := Node3D.new()
	g.name = "Collision"
	root.add_child(g)
	_ground(g)
	store_collision(g)
	_street(g)
	_bounds(g)


# ---------------------------------------------------------------- 公开入口

## 便利店那组墙 / 货架 / 柜台的碰撞。新街区摆的是同一家店，尺寸要跟
## store.gd 完全一致，所以直接复用，不再抄一遍。
static func store_collision(root: Node3D) -> void:
	_store(root)


## 店内地面 + 门槛斜面。新街区的地面形状不同，但这两块仍然属于便利店。
static func store_ground(root: Node3D) -> void:
	# 店内地面：x −1.48..2.88，z −5.28..−1.12，顶面 0.25
	_box(root, Vector3(0.7, 0.25 - 1.0, -3.2), Vector3(4.36, 2.0, 4.16))

	# 店门槛：人行道 0.16 → 店内 0.25，9cm 的坎。人物没有自动上台阶，
	# 不补这块斜面就会卡在门口。局部 +Z 是升高的方向，转到朝店里（−Z）。
	_wedge(root, Vector3(0.355, 0.0, -1.02), 0.665, 0.16, WALK_Y, 0.25, 180.0)


## 新区的地面 / 店面 / 杆件碰撞也走这一套原语。
## 公开转发，避免新场景再写一份 _box / _wedge（楔形的顶点顺序很容易抄错）。
static func solid(parent: Node3D, center: Vector3, size: Vector3, rot_y: float = 0.0) -> StaticBody3D:
	return _box(parent, center, size, rot_y)


static func pillar(parent: Node3D, center: Vector3, radius: float, height: float) -> StaticBody3D:
	return _cylinder(parent, center, radius, height)


static func slope(parent: Node3D, center: Vector3, half_w: float, half_d: float,
		y_lo: float, y_hi: float, rot_y: float = 0.0) -> StaticBody3D:
	return _wedge(parent, center, half_w, half_d, y_lo, y_hi, rot_y)


# ---------------------------------------------------------------- 工具

static func _box(parent: Node3D, center: Vector3, size: Vector3, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = deg_to_rad(rot_y)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	return body


static func _cylinder(parent: Node3D, center: Vector3, radius: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	return body


## 楔形：给门槛 / 路缘做一块「看不见的坡」。
## 局部坐标里沿 +Z 从 y_lo 升到 y_hi，需要别的朝向就转 body（rot_y）。
## 用凸包而不是旋转的盒子：顶面一定是水平的斜平面，不会因为角度算错卡住脚。
static func _wedge(parent: Node3D, center: Vector3, half_w: float, half_d: float,
		y_lo: float, y_hi: float, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = deg_to_rad(rot_y)
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = PackedVector3Array([
		Vector3(-half_w, 0.0, -half_d), Vector3(half_w, 0.0, -half_d),
		Vector3(-half_w, 0.0, half_d), Vector3(half_w, 0.0, half_d),
		Vector3(-half_w, y_lo, -half_d), Vector3(half_w, y_lo, -half_d),
		Vector3(-half_w, y_hi, half_d), Vector3(half_w, y_hi, half_d),
	])
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	return body


# ---------------------------------------------------------------- 地面

static func _ground(g: Node3D) -> void:
	# 底座顶面（马路）：11.2 × 11.2，顶面 y = 0
	_box(g, Vector3(0.0, -1.0, 0.0), Vector3(BASE_HALF * 2.0, 2.0, BASE_HALF * 2.0))
	# 人行道 L 形：x −2.07..5.6，z −5.6..2.07，顶面 0.16。
	# 外沿要把 0.17m 宽的路缘石一起包进来：路缘石是实心的可见几何，
	# 碰撞只到 −1.9 / 1.9 的话，人站在路缘石上脚就埋进石头里了。
	_box(g, Vector3(1.765, WALK_Y - 1.0, -1.765), Vector3(7.67, 2.0, 7.67))

	store_ground(g)

	# 路缘：人行道比马路高 16cm。两条临路的边各铺一条 25cm 宽的隐形坡，
	# 不然走出人行道以后就回不来了。
	# 坡必须整条铺在路缘石外侧（−2.07 / 2.07 以外）——铺到石头底下的话，
	# 人往上爬的那半秒里脚是埋在石头里的。
	_wedge(g, Vector3(-2.195, 0.0, -1.765), 3.835, 0.125, 0.0, WALK_Y, 90.0)   # 西侧，朝 +X 升
	_wedge(g, Vector3(1.765, 0.0, 2.195), 3.835, 0.125, 0.0, WALK_Y, 180.0)    # 南侧，朝 −Z 升（往人行道）


# ---------------------------------------------------------------- 便利店

static func _store(g: Node3D) -> void:
	var L := Store.layout(true)

	# 三面外墙 + 门洞两侧的前墙（门叶自己的碰撞在 autodoor.gd 里）
	var wh := Store.TOP - Store.FLOOR
	var wy := (Store.TOP + Store.FLOOR) * 0.5
	_box(g, Vector3(Store.X0 + 0.11, wy, (Store.Z0 + Store.Z1) * 0.5), Vector3(0.22, wh, Store.Z1 - Store.Z0))
	_box(g, Vector3(Store.X1 - 0.11, wy, (Store.Z0 + Store.Z1) * 0.5), Vector3(0.22, wh, Store.Z1 - Store.Z0))
	_box(g, Vector3((Store.X0 + Store.X1) * 0.5, wy, Store.Z0 + 0.11), Vector3(Store.X1 - Store.X0, wh, 0.22))
	# 前立面：左段 / 右段，中间留 1.37m 门洞
	_box(g, Vector3((Store.X0 - 0.33) * 0.5, wy, Store.Z1 - 0.11), Vector3(-0.33 - Store.X0, wh, 0.22))
	_box(g, Vector3((1.04 + Store.X1) * 0.5, wy, Store.Z1 - 0.11), Vector3(Store.X1 - 1.04, wh, 0.22))
	# 天花（挡相机，别让弹簧臂穿出屋顶）
	_box(g, Vector3((Store.X0 + Store.X1) * 0.5, 2.93, (Store.Z0 + Store.Z1) * 0.5),
		Vector3(Store.X1 - Store.X0 - 0.44, 0.1, Store.Z1 - Store.Z0 - 0.44))

	# 员工休息室隔墙：整面实心。
	# 门虽然画成「关着的门」，但碰撞不做门洞 —— 这个房间的设定就是进不去，
	# 留个洞迟早会被人挤进去（胶囊半径 0.32，0.9m 的门洞一挤就过）。
	var br: Dictionary = L["break_room"]
	_box(g, Vector3(br["x0"], wy, (br["z0"] + br["z1"]) * 0.5),
		Vector3(0.12, wh, br["z1"] - br["z0"]))

	# 货架
	for r in L["racks"]:
		var w: float = r["x1"] - r["x0"]
		_box(g, Vector3((r["x0"] + r["x1"]) * 0.5, Store.FLOOR + 0.75, r["z"]), Vector3(w, 1.5, 0.52))

	# 冷柜
	var fr: Dictionary = L["fridge"]
	_box(g, Vector3((fr["x0"] + fr["x1"]) * 0.5, Store.FLOOR + 1.0, (fr["z0"] + fr["z1"]) * 0.5),
		Vector3(fr["x1"] - fr["x0"], 2.0, fr["z1"] - fr["z0"]))

	# 收银台（整组转过 90°）
	var c: Dictionary = L["counter"]
	_box(g, Vector3(c["cx"], Store.FLOOR + 0.49, c["cz"]),
		Vector3(c["w"], 0.98, c["d"]), c["rot"])

	# 杂志架 / 促销堆头
	var mg: Dictionary = L["magazine"]
	# 高度跟着视觉走（货架现在是 1.20m 高，原来按 1.10 算，顶上会多出一截空气墙）
	_box(g, Vector3((mg["x0"] + mg["x1"]) * 0.5, Store.FLOOR + 0.60, (mg["z0"] + mg["z1"]) * 0.5),
		Vector3(mg["x1"] - mg["x0"], 1.20, mg["z1"] - mg["z0"]))
	for p in L["promos"]:
		# 碰撞盒和视觉盒子必须同心。原来这里 +0.28，比看得见的纸箱高出 28cm ——
		# 人会撞在堆头上方的一团空气里。
		_box(g, p, Vector3(0.62, 0.56, 0.42))


# ---------------------------------------------------------------- 街道设施

static func _street(g: Node3D) -> void:
	# 电线杆
	_cylinder(g, Vector3(-1.62, 3.15, 1.15), 0.17, 6.3)
	_cylinder(g, Vector3(5.2, 3.15, -4.85), 0.17, 6.3)
	# 路灯 / 凸面镜 / 停车牌
	_cylinder(g, Vector3(4.35, 2.15, 1.55), 0.09, 4.3)
	_cylinder(g, Vector3(-1.8, 1.45, 1.98), 0.06, 2.9)
	_cylinder(g, Vector3(-1.35, 1.02, 1.72), 0.05, 2.05)
	# 东侧护栏
	_box(g, Vector3(4.42, 0.66, 1.78), Vector3(2.15, 1.0, 0.09))
	# 伞架 / 垃圾桶 / 立式招牌 / 地灯
	_cylinder(g, Vector3(1.22, 0.39, -0.42), 0.2, 0.46)
	_box(g, Vector3(1.77, 0.41, -0.52), Vector3(0.68, 0.5, 0.3))
	_box(g, Vector3(1.85, 0.58, 0.6), Vector3(0.56, 0.86, 0.32), -26.0)
	_cylinder(g, Vector3(-0.55, 0.4, -0.6), 0.08, 0.48)
	# 自行车（侧着停，给个薄盒子就够）
	_box(g, Vector3(-1.02, 0.55, 0.5), Vector3(0.34, 1.0, 1.45), 62.0)
	# 贩卖机：后巷收窄到 1.06m 之后只剩巷子尽头放得下（1.0 × 0.72，面朝巷口）
	_box(g, Vector3(4.83, 0.16 + 0.95, -4.95), Vector3(1.02, 1.9, 0.76))
	# 后巷矮墙与铁栏
	_box(g, Vector3(5.36, 1.1, -3.02), Vector3(0.3, 2.2, 5.0))


# ---------------------------------------------------------------- 边界

## 底座边缘的隐形围栏：别让人走着走着掉出微缩模型。
static func _bounds(g: Node3D) -> void:
	var h := 4.0
	var t := 0.16
	_box(g, Vector3(0, h * 0.5, -BASE_HALF + t * 0.5), Vector3(BASE_HALF * 2.0, h, t))
	_box(g, Vector3(0, h * 0.5, BASE_HALF - t * 0.5), Vector3(BASE_HALF * 2.0, h, t))
	_box(g, Vector3(-BASE_HALF + t * 0.5, h * 0.5, 0), Vector3(t, h, BASE_HALF * 2.0))
	_box(g, Vector3(BASE_HALF - t * 0.5, h * 0.5, 0), Vector3(t, h, BASE_HALF * 2.0))
