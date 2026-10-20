extends RefCounted
## 城镇城墙。
##
## 沿「城镇地基」的四边围一圈，城门开在道路正对的位置（z=300、x=0）。
## 地基的范围来自 grassland.gd：x ∈ [-150, 150]，z ∈ [300, 630]。
##
## 做法沿用本工程的风格：全部由 GDScript 生成，不摆节点。
## 墙体用 kit.box() 出几何 + 手挂 StaticBody3D 做碰撞 —— kit 只给视觉，
## 不给碰撞，而城墙必须挡住玩家。
##
## 垛口（城墙顶部的小方块）**不加碰撞**：它们立在 12m 高，玩家够不着，
## 加了只是白白多 140 个碰撞体。

const K := preload("res://scripts/kit.gd")

## 地基边界，必须和 grassland.gd 的 PAVED_CENTER / PAVED_HALF 对得上
const HALF_X := 150.0
const Z_FRONT := 300.0
const Z_BACK := 630.0

## 墙体
const WALL_H := 12.0
const WALL_T := 4.0
## 城门洞的半宽。路面在这里只有 ±3.2，给到 ±11 是为了留出两尊 NPC 站的位置
const GATE_HALF := 11.0

## 转角塔：四角各一座，截面 16×16
const CORNER_W := 16.0
const CORNER_H := 17.0
## 门楼：城门两侧各一座，比转角塔更高一点，形成「门」的视觉重心
const GATE_TOWER_W := 12.0
const GATE_TOWER_H := 19.0
const GATE_TOWER_OFFSET := 16.0

## 垛口间距与尺寸
const CREN_STEP := 9.0
const CREN_W := 3.0
const CREN_H := 1.6


static func build(parent: Node3D) -> void:
	# 石头配色偏暖偏亮：这个场景是上午的晴天，用冷灰会显得像阴天的城堡
	var stone := K.toon(Color("#b9b3a5"), {"line": 0.010, "shade": 0.55})
	var stone_dark := K.toon(Color("#9a9486"), {"line": 0.012, "shade": 0.50})
	var tower := K.toon(Color("#aca695"), {"line": 0.012, "shade": 0.53})

	var g := K.group(parent, "CityWall")
	_front(g, stone, stone_dark, tower)
	_back(g, stone, stone_dark)
	_side(g, -1.0, stone, stone_dark, tower)
	_side(g, 1.0, stone, stone_dark, tower)


# ---------------------------------------------------------------- 正面（带城门）

static func _front(g: Node3D, stone: Material, dark: Material, tower: Material) -> void:
	var seg_len := HALF_X - GATE_HALF             # 139
	var seg_cx := GATE_HALF + seg_len * 0.5       # 80.5
	var y := WALL_H * 0.5

	for sign_ in [-1.0, 1.0]:
		_solid(g, Vector3(seg_len, WALL_H, WALL_T),
			Vector3(sign_ * seg_cx, y, Z_FRONT), stone)
		_crenels_along_x(g, sign_ * seg_cx, seg_len, Z_FRONT, stone, dark)

	# 门楣：架在城门洞上方，做出「门」的框
	var lintel_h := 3.0
	_solid(g, Vector3(GATE_HALF * 2.0, lintel_h, WALL_T),
		Vector3(0.0, WALL_H - lintel_h * 0.5, Z_FRONT), dark)

	# 门洞两侧的门楼
	for sign_ in [-1.0, 1.0]:
		var bx: float = sign_ * GATE_TOWER_OFFSET
		_solid(g, Vector3(GATE_TOWER_W, GATE_TOWER_H, GATE_TOWER_W),
			Vector3(bx, GATE_TOWER_H * 0.5, Z_FRONT), tower)
		# 门楼顶上一圈垛口，让它不只是一个方盒子
		_cren_ring(g, Vector3(bx, GATE_TOWER_H, Z_FRONT), GATE_TOWER_W, tower)

	# 两座门楼之间的横梁，把门做成「框」而不是「缺口」
	_solid(g, Vector3(GATE_TOWER_OFFSET * 2.0, 1.6, GATE_TOWER_W),
		Vector3(0.0, GATE_TOWER_H - 0.8, Z_FRONT), tower)


# ---------------------------------------------------------------- 背面 / 两侧

static func _back(g: Node3D, stone: Material, dark: Material) -> void:
	var full := HALF_X * 2.0 + CORNER_W      # 让背面墙和转角塔连成一体
	_solid(g, Vector3(full, WALL_H, WALL_T),
		Vector3(0.0, WALL_H * 0.5, Z_BACK), stone)
	_crenels_along_x(g, 0.0, full, Z_BACK, stone, dark)

	for sign_ in [-1.0, 1.0]:
		_solid(g, Vector3(CORNER_W, CORNER_H, CORNER_W),
			Vector3(sign_ * HALF_X, CORNER_H * 0.5, Z_BACK), stone)
		_cren_ring(g, Vector3(sign_ * HALF_X, CORNER_H, Z_BACK), CORNER_W, stone)


static func _side(g: Node3D, sign_x: float, stone: Material, dark: Material,
		tower: Material) -> void:
	var x := sign_x * HALF_X
	var z0 := Z_FRONT
	var z1 := Z_BACK
	var len_ := z1 - z0
	var cz := (z0 + z1) * 0.5

	_solid(g, Vector3(WALL_T, WALL_H, len_),
		Vector3(x, WALL_H * 0.5, cz), stone)
	_crenels_along_z(g, x, cz, len_, stone, dark)

	# 前侧转角塔（和后侧那两座对称）
	_solid(g, Vector3(CORNER_W, CORNER_H, CORNER_W),
		Vector3(x, CORNER_H * 0.5, Z_FRONT), tower)
	_cren_ring(g, Vector3(x, CORNER_H, Z_FRONT), CORNER_W, tower)


# ---------------------------------------------------------------- 垛口

## 沿 X 方向铺一排垛口
static func _crenels_along_x(g: Node3D, center_x: float, length: float, z: float,
		stone: Material, dark: Material) -> void:
	var n := int(length / CREN_STEP)
	if n <= 0:
		return
	var start := center_x - length * 0.5 + CREN_STEP * 0.5
	for i in n:
		var x := start + i * CREN_STEP
		var mat := dark if i % 2 == 0 else stone
		K.box(g, Vector3(CREN_W, CREN_H, WALL_T * 1.05),
			Vector3(x, WALL_H + CREN_H * 0.5, z), mat)


## 沿 Z 方向铺一排垛口
static func _crenels_along_z(g: Node3D, x: float, center_z: float, length: float,
		stone: Material, dark: Material) -> void:
	var n := int(length / CREN_STEP)
	if n <= 0:
		return
	var start := center_z - length * 0.5 + CREN_STEP * 0.5
	for i in n:
		var z := start + i * CREN_STEP
		var mat := dark if i % 2 == 0 else stone
		K.box(g, Vector3(WALL_T * 1.05, CREN_H, CREN_W),
			Vector3(x, WALL_H + CREN_H * 0.5, z), mat)


## 塔顶围一圈垛口
static func _cren_ring(g: Node3D, base: Vector3, w: float, mat: Material) -> void:
	var half := w * 0.5
	var step := 3.6
	var n := int(w / step)
	for i in n + 1:
		var t := -half + i * step
		for side in [[t, -half], [t, half], [-half, t], [half, t]]:
			K.box(g, Vector3(2.2, 1.4, 2.2),
				Vector3(base.x + side[0], base.y + 0.7, base.z + side[1]), mat)


# ---------------------------------------------------------------- 实体（视觉 + 碰撞）

## kit.box 只给视觉，这里补一个 StaticBody3D 让城墙真的挡人。
## 只接受轴对齐（rot 恒为 0）—— 转过的墙要自己算碰撞盒的世界朝向，得不偿失。
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
