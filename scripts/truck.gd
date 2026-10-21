extends Node3D
## 厢式大货车：全程序化搭建，车头朝 +X，原点在车身中心的地面上。
##
## 单独一个文件的原因不是「造型复杂」，而是**材质不能共用**：
## 它要挂 clip_* 着色器参数，把超出台面的部分 discard 掉
## （否则从场外开进来时，半截车身会浮在微缩底座外面）。
## kit 的材质缓存是按颜色/参数共享的，所以这里一律走 kit.toon_clipped()。
##
## 尺寸按真车来：长 6.2m、宽 2.16m、高 2.86m。
## 台面只有 11.2m 见方，这台车横穿画面时能占掉大半条马路，压迫感是对的。

const K := preload("res://scripts/kit.gd")

## 总长 / 车宽 / 轮径（米）
const L := 6.2
const W := 2.16
const WHEEL_R := 0.46

## 车厢与驾驶室的分界（局部 x）
const CARGO_X0 := -3.05
const CARGO_X1 := 0.62
const CAB_X1 := 2.60
const BODY_TOP := 2.86

## 轮位：前轴 + 双后轴
const AXLES := [1.95, -1.60, -2.50]

var _wheels: Array = []
var _tail_mat: ShaderMaterial
var _tail_light: OmniLight3D


func _ready() -> void:
	_build_chassis()
	_build_cargo()
	_build_cab()
	_build_wheels()
	_build_lights()


# ---------------------------------------------------------------- 材质

func _shell() -> ShaderMaterial:
	return K.toon_clipped(Color("#c9d2d9"), {"shade": 0.34, "rim": 0.34, "line": 0.008})


func _dark() -> ShaderMaterial:
	return K.toon_clipped(Color("#1a1f27"), {"shade": 0.55, "rim": 0.22, "line": 0.006})


func _stripe() -> ShaderMaterial:
	return K.toon_clipped(Color("#a83f36"), {"shade": 0.4, "rim": 0.28, "line": 0.006})


func _glass() -> ShaderMaterial:
	# 夜里车窗是「比车身更黑的一块」，不用真玻璃：真玻璃会把街灯反射成一片白
	return K.toon_clipped(Color("#121a24"), {"shade": 0.8, "rim": 0.55, "line": 0.005})


func _chrome() -> ShaderMaterial:
	return K.toon_clipped(Color("#7d868f"), {"shade": 0.42, "rim": 0.5, "line": 0.005})


# ---------------------------------------------------------------- 车体

func _build_chassis() -> void:
	var d := _dark()
	# 大梁
	K.box(self, Vector3(L - 0.35, 0.20, 1.52), Vector3(-0.1, 0.66, 0.0), d)
	# 尾部防撞梁 + 挡泥板
	K.box(self, Vector3(0.16, 0.20, 2.05), Vector3(-3.12, 0.52, 0.0), d)
	for z in [-0.98, 0.98]:
		K.box(self, Vector3(0.05, 0.34, 0.36), Vector3(-2.78, 0.30, z), d)
	# 油箱（挂在右侧大梁下）
	K.cyl(self, 0.21, 0.86, Vector3(0.05, 0.48, 0.92), _chrome(), Vector3(0, 0, 90), 12)


func _build_cargo() -> void:
	var shell := _shell()
	var mid := (CARGO_X0 + CARGO_X1) * 0.5
	var blen := CARGO_X1 - CARGO_X0

	# 厢体
	K.box(self, Vector3(blen, 2.00, W), Vector3(mid, 1.86, 0.0), shell)
	# 顶盖压边
	K.box(self, Vector3(blen + 0.04, 0.08, W + 0.04), Vector3(mid, BODY_TOP - 0.02, 0.0), shell)
	# 底部裙边
	K.box(self, Vector3(blen, 0.14, W + 0.02), Vector3(mid, 0.92, 0.0), _dark())
	# 腰线（红）：比厢体宽 5cm，夜里靠这条线读出车长
	K.box(self, Vector3(blen, 0.24, W + 0.05), Vector3(mid, 1.32, 0.0), _stripe())
	# 侧面 logo 方块
	for z in [-1.0, 1.0]:
		K.box(self, Vector3(0.92, 0.52, 0.03), Vector3(-2.05, 2.26, z * (W * 0.5 + 0.012)), _stripe())
		K.box(self, Vector3(0.62, 0.24, 0.03), Vector3(-2.05, 2.26, z * (W * 0.5 + 0.024)), shell)

	# 尾门：两扇对开，中间一道缝
	K.box(self, Vector3(0.06, 1.84, W - 0.06), Vector3(CARGO_X0 - 0.03, 1.86, 0.0), shell)
	K.box(self, Vector3(0.07, 1.84, 0.04), Vector3(CARGO_X0 - 0.04, 1.86, 0.0), _dark())
	for z in [-0.62, 0.62]:
		K.box(self, Vector3(0.05, 0.44, 0.05), Vector3(CARGO_X0 - 0.07, 1.30, z), _chrome())


func _build_cab() -> void:
	var shell := _shell()
	var cab_len := CAB_X1 - 0.62
	var cab_mid := (0.62 + CAB_X1) * 0.5

	# 驾驶室主体
	K.box(self, Vector3(cab_len, 1.66, 2.04), Vector3(cab_mid, 1.55, 0.0), shell)
	# 车顶导流罩：往车厢方向压下去，衔接驾驶室和厢体的高差
	K.box(self, Vector3(0.72, 0.40, 1.92), Vector3(0.72, 2.52, 0.0), shell, Vector3(0, 0, -14))
	# 前脸
	K.box(self, Vector3(0.10, 0.30, 1.66), Vector3(CAB_X1 - 0.02, 1.14, 0.0), _dark())
	# 前保险杠
	K.box(self, Vector3(0.24, 0.38, 2.10), Vector3(CAB_X1 + 0.06, 0.64, 0.0), _dark())
	K.box(self, Vector3(0.10, 0.12, 1.30), Vector3(CAB_X1 + 0.14, 0.50, 0.0), _chrome())

	# 风挡：向后倾 8°
	K.box(self, Vector3(0.06, 0.78, 1.86), Vector3(CAB_X1 - 0.03, 1.94, 0.0), _glass(), Vector3(0, 0, 8))
	# 侧窗 + 门把手
	for z in [-1.0, 1.0]:
		K.box(self, Vector3(0.94, 0.60, 0.04), Vector3(1.98, 1.96, z * 1.028), _glass())
		K.box(self, Vector3(0.16, 0.05, 0.04), Vector3(1.86, 1.46, z * 1.03), _chrome())
		# 后视镜
		K.strut(self, Vector3(2.36, 2.06, z * 1.02), Vector3(2.36, 2.06, z * 1.30), 0.028, _dark(), 6)
		K.box(self, Vector3(0.09, 0.30, 0.13), Vector3(2.36, 1.98, z * 1.32), _dark())


func _build_wheels() -> void:
	var tire := _dark()
	var hub := _chrome()
	for ax in AXLES:
		for z in [-0.94, 0.94]:
			# 轮毂节点只负责自转：网格绕自身 Y 轴 → 转 90° 后轴沿 Z，
			# 父节点绕 Z 旋转就等于让轮子滚起来
			var w := Node3D.new()
			w.position = Vector3(ax, WHEEL_R, z)
			add_child(w)
			K.cyl(w, WHEEL_R, 0.34, Vector3.ZERO, tire, Vector3(90, 0, 0), 16)
			K.cyl(w, 0.21, 0.36, Vector3.ZERO, hub, Vector3(90, 0, 0), 12)
			_wheels.append(w)


func _build_lights() -> void:
	var lamp := K.glow_clipped(Color("#ffe9c4"), 4.0)
	for z in [-0.74, 0.74]:
		K.box(self, Vector3(0.07, 0.20, 0.38), Vector3(CAB_X1 + 0.04, 0.98, z), lamp, Vector3.ZERO, false)
		var sl := SpotLight3D.new()
		sl.position = Vector3(CAB_X1 + 0.10, 0.98, z)
		sl.rotation_degrees = Vector3(0, -90, 0)   # 灯头朝 +X
		sl.light_color = Color("#ffe3b8")
		sl.light_energy = 5.0
		sl.spot_range = 16.0
		sl.spot_angle = 34.0
		sl.spot_attenuation = 0.9
		sl.shadow_enabled = false
		add_child(sl)

	# 尾灯：只给一点自发光 + 一盏很小的红光，够在湿地上留个红点
	_tail_mat = K.glow_clipped(Color("#ff4a32"), 2.2)
	for z in [-0.88, 0.88]:
		K.box(self, Vector3(0.06, 0.26, 0.20), Vector3(CARGO_X0 - 0.06, 1.02, z), _tail_mat, Vector3.ZERO, false)
	_tail_light = OmniLight3D.new()
	_tail_light.position = Vector3(CARGO_X0 - 0.35, 1.0, 0.0)
	_tail_light.light_color = Color("#ff5a3a")
	_tail_light.light_energy = 0.9
	_tail_light.omni_range = 3.2
	_tail_light.shadow_enabled = false
	add_child(_tail_light)


# ---------------------------------------------------------------- 接口

## 轮子自转。angle 是累计弧度，事件脚本每帧按「行驶距离 / 轮径」推进。
func spin(angle: float) -> void:
	for w in _wheels:
		w.rotation.z = -angle


## 刹车灯：撞击后点亮，让「它真的刹了」这件事有画面依据
func set_brake(on: bool) -> void:
	if _tail_mat != null:
		_tail_mat.set_shader_parameter("strength", 5.0 if on else 2.2)
	if _tail_light != null:
		_tail_light.light_energy = 2.4 if on else 0.9
