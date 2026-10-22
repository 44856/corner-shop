extends Node3D
## 厢式大货车：全程序化搭建，车头朝 +X，原点在车身中心的地面上。
##
## 单独一个文件的原因不是「造型复杂」，而是**材质不能走 kit 的全局缓存**：
## 它要挂 clip_* 着色器参数，把超出台面的部分 discard 掉
## （否则从场外开进来时，半截车身会浮在微缩底座外面）。
## 所以这里一律用 kit.toon_clipped() 复制一份，车内部再按颜色自己缓存。
##
## 尺寸按真车来：长 6.2m、宽 2.16m、高 2.86m。
## 台面只有 11.2m 见方，这台车横穿画面时能占掉大半条马路，压迫感是对的。
##
## 细节分四层：底盘（油箱 / 电瓶 / 气罐 / 挡泥板 / 侧防护）→ 厢体（加强筋、
## 立柱、侧标志灯、尾门铰链与锁杆）→ 驾驶室（格栅、灯组、雨刷、遮阳板、
## 踏板、后视镜）→ 车轮（轮胎 + 轮辋 + 轮毂三层同心圆）。
## 灯板 / 光柱 / 光晕一律不投影、不写深度；结构件照常投影。

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

## 前照灯灯面中心（局部坐标）
const LAMP_Y := 0.98
const LAMP_Z := 0.74
## 光束：5m 长，从 0.13m 张到 1.3m，向下压 6°。
## 灯面高 0.98m，压 6° 之后远端落到膝盖高度 —— 光柱不会整根飘在空中。
## 不做到 8m 是因为台面只有 11.2m 宽：光束越长，越容易被台面边缘切在
## 半空中；5m 的远端透明度已经接近 0，切口看不出来。
const BEAM_LEN := 5.0
const BEAM_NEAR := 0.13
const BEAM_FAR := 1.30
const BEAM_PITCH := -6.0
## 地面光池（湿地上那块亮斑）：x = 沿车头方向的半长，y = 横向半宽
const POOL_CENTER_X := 4.00
const POOL_HALF := Vector2(2.40, 1.50)

## 台面裁剪盒。默认是 11.2m 微缩底座；加油站是 30 × 18m 的完整场景，
## 必须换成覆盖整个场地的盒子，否则车一开出中心 5.6m 就会被整块 discard。
var clip_box := K.PLATFORM_CLIP

var _wheels: Array = []
## Label3D 走不了裁剪着色器（它自带字体材质），只能按台面范围开关可见性。
## 不处理的话，车还在台面外时，车身上的字会孤零零飘在底座外面。
var _labels: Array = []
var _tail_mat: ShaderMaterial
var _tail_light: OmniLight3D
var _beam_mat: ShaderMaterial
var _pool_mat: ShaderMaterial
## 同一台车只用这几份材质：每块板子都 duplicate 一遍会白白多出几十个材质
var _mats: Dictionary = {}


func _ready() -> void:
	_build_chassis()
	_build_cargo()
	_build_cab()
	_build_wheels()
	_build_lights()


func _process(_delta: float) -> void:
	for l in _labels:
		l.visible = clip_box.has_point((l as Label3D).global_position)


## 车身文字：记下来，_process 里按台面范围开关
func _text(text: String, pos: Vector3, height: float, color: Color,
		rot: Vector3 = Vector3.ZERO) -> Label3D:
	var l := K.label(self, text, pos, height, color, rot)
	_labels.append(l)
	return l


# ---------------------------------------------------------------- 材质

func _mat(key: String, color: Color, p: Dictionary) -> ShaderMaterial:
	if not _mats.has(key):
		_mats[key] = K.toon_clipped(color, p, clip_box)
	return _mats[key]


func _shell() -> ShaderMaterial:
	return _mat("shell", Color("#c9d2d9"), {"shade": 0.34, "rim": 0.34, "line": 0.008})


## 厢体加强筋 / 立柱：比蒙皮暗半档，靠明度差把「板」和「骨」分开
func _shell_dim() -> ShaderMaterial:
	return _mat("shell_dim", Color("#aeb8c1"), {"shade": 0.36, "rim": 0.30, "line": 0.006})


func _dark() -> ShaderMaterial:
	return _mat("dark", Color("#1a1f27"), {"shade": 0.55, "rim": 0.22, "line": 0.006})


func _stripe() -> ShaderMaterial:
	return _mat("stripe", Color("#a83f36"), {"shade": 0.4, "rim": 0.28, "line": 0.006})


func _glass() -> ShaderMaterial:
	# 夜里车窗是「比车身更黑的一块」，不用真玻璃：真玻璃会把街灯反射成一片白
	return _mat("glass", Color("#121a24"), {"shade": 0.8, "rim": 0.55, "line": 0.005})


func _chrome() -> ShaderMaterial:
	return _mat("chrome", Color("#7d868f"), {"shade": 0.42, "rim": 0.5, "line": 0.005})


## 雨刷：比纯黑亮一档，否则贴在黑玻璃上什么都看不见
func _wiper() -> ShaderMaterial:
	return _mat("wiper", Color("#3a444f"), {"shade": 0.6, "rim": 0.3, "line": 0.003})


## 镜面：比镀铬更亮一点，夜里后视镜是一小块冷光
func _mirror() -> ShaderMaterial:
	return _mat("mirror", Color("#9fb3c4"), {"shade": 0.85, "rim": 0.7, "line": 0.004})


## 牌照：淡灰白，靠描边把字框出来
func _plate() -> ShaderMaterial:
	return _mat("plate", Color("#cfd4cd"), {"shade": 0.72, "rim": 0.2, "line": 0.004})


func _lens() -> ShaderMaterial:
	if not _mats.has("lens"):
		_mats["lens"] = K.glow_clipped(Color("#ffe9c4"), 4.0, 0.0, clip_box)
	return _mats["lens"]


func _amber() -> ShaderMaterial:
	if not _mats.has("amber"):
		_mats["amber"] = K.glow_clipped(Color("#ffab3d"), 2.4, 0.0, clip_box)
	return _mats["amber"]


func _reverse() -> ShaderMaterial:
	if not _mats.has("reverse"):
		_mats["reverse"] = K.glow_clipped(Color("#cfe2ff"), 0.7, 0.0, clip_box)
	return _mats["reverse"]


## 雾灯：比大灯暗一档，不然车头会亮成四只眼睛
func _fog_lens() -> ShaderMaterial:
	if not _mats.has("fog"):
		_mats["fog"] = K.glow_clipped(Color("#ffe0b0"), 1.7, 0.0, clip_box)
	return _mats["fog"]


func _tail_lens() -> ShaderMaterial:
	if _tail_mat == null:
		_tail_mat = K.glow_clipped(Color("#ff4a32"), 2.2, 0.0, clip_box)
	return _tail_mat


# ---------------------------------------------------------------- 底盘

func _build_chassis() -> void:
	var d := _dark()
	var ch := _chrome()

	# 大梁
	K.box(self, Vector3(L - 0.35, 0.20, 1.52), Vector3(-0.1, 0.66, 0.0), d)
	# 车厢底下的暗板：不补这块，低机位能顺着轮缝看穿车底看到对面的街
	K.box(self, Vector3(3.62, 0.10, 1.92), Vector3(-1.22, 0.80, 0.0), d)
	# 尾部防撞梁 + 蹬车踏板
	K.box(self, Vector3(0.16, 0.20, 2.05), Vector3(-3.12, 0.52, 0.0), d)
	K.box(self, Vector3(0.34, 0.05, 1.10), Vector3(-3.01, 0.43, 0.0), ch)

	# 挡泥板：贴在轮胎后沿，不挡轮子转
	for z in [-0.94, 0.94]:
		K.box(self, Vector3(0.04, 0.44, 0.34), Vector3(-2.99, 0.30, z), d)
		K.box(self, Vector3(0.04, 0.38, 0.30), Vector3(1.44, 0.34, z), d)
		# 尾部挡泥板上的反光条
		K.box(self, Vector3(0.01, 0.05, 0.30), Vector3(-3.012, 0.44, z), _plate(), Vector3.ZERO, false)

	# 油箱（右）+ 两道箍带
	K.cyl(self, 0.21, 0.86, Vector3(0.05, 0.48, 0.92), ch, Vector3(0, 0, 90), 14)
	for x in [-0.28, 0.38]:
		K.box(self, Vector3(0.05, 0.46, 0.46), Vector3(x, 0.48, 0.92), d)
	K.cyl(self, 0.05, 0.06, Vector3(-0.30, 0.70, 0.92), ch, Vector3.ZERO, 8)
	# 电瓶箱（左）
	K.box(self, Vector3(0.52, 0.34, 0.36), Vector3(0.05, 0.50, -0.92), d)
	K.box(self, Vector3(0.12, 0.04, 0.02), Vector3(0.05, 0.60, -1.095), ch)
	# 储气罐
	K.cyl(self, 0.12, 0.60, Vector3(-1.02, 0.44, -0.72), ch, Vector3(0, 0, 90), 12)

	# 侧防护栏：只铺在前轴和后轴之间，穿过轮胎就穿帮了
	for z in [-1.04, 1.04]:
		K.strut(self, Vector3(-0.85, 0.46, z), Vector3(0.95, 0.46, z), 0.032, ch, 6, false)
		for x in [-0.70, 0.80]:
			K.strut(self, Vector3(x, 0.30, z), Vector3(x, 0.46, z), 0.024, ch, 6, false)

	# 排气管尾段
	K.cyl(self, 0.05, 0.34, Vector3(-3.00, 0.36, 0.56), ch, Vector3(0, 0, 90), 8)


# ---------------------------------------------------------------- 厢体

func _build_cargo() -> void:
	var shell := _shell()
	var dim := _shell_dim()
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

	# 侧板加强筋：logo 那一段留空，别让一根竖筋从字中间劈过去
	var x := CARGO_X0 + 0.16
	while x < CARGO_X1 - 0.10:
		if x < -2.60 or x > -1.50:
			for z in [-1.0, 1.0]:
				K.box(self, Vector3(0.05, 1.74, 0.05), Vector3(x, 1.90, z * 1.095), dim)
		x += 0.42
	# 四角立柱
	for cx in [CARGO_X0 + 0.035, CARGO_X1 - 0.035]:
		for z in [-1.0, 1.0]:
			K.box(self, Vector3(0.07, 1.96, 0.07), Vector3(cx, 1.88, z * 1.092), dim)

	# 侧面 logo 方块 + 字
	for z in [-1.0, 1.0]:
		K.box(self, Vector3(0.92, 0.52, 0.03), Vector3(-2.05, 2.26, z * (W * 0.5 + 0.012)), _stripe())
		K.box(self, Vector3(0.62, 0.24, 0.03), Vector3(-2.05, 2.26, z * (W * 0.5 + 0.024)), shell)
		_text("HOSHI", Vector3(-2.05, 2.26, z * (W * 0.5 + 0.045)), 0.15,
			Color("#a83f36"), Vector3(0, 0 if z > 0 else 180, 0))

	# 侧标志灯：贴着裙边，夜里一列车灯比什么都更能读出「这是一台长车」
	for z in [-1.105, 1.105]:
		for sx in [-2.68, -1.84, -1.00, -0.16]:
			K.box(self, Vector3(0.12, 0.045, 0.035), Vector3(sx, 0.955, z), _amber(), Vector3.ZERO, false)

	# 尾门：两扇对开，中间一道缝
	K.box(self, Vector3(0.06, 1.84, W - 0.06), Vector3(CARGO_X0 - 0.03, 1.86, 0.0), shell)
	K.box(self, Vector3(0.07, 1.84, 0.04), Vector3(CARGO_X0 - 0.04, 1.86, 0.0), _dark())
	# 门铰链（每侧三只）+ 通高锁杆 + 把手
	for z in [-0.98, 0.98]:
		for y in [1.16, 1.86, 2.56]:
			K.box(self, Vector3(0.05, 0.16, 0.11), Vector3(CARGO_X0 - 0.06, y, z), _chrome())
	for z in [-0.62, 0.62]:
		K.box(self, Vector3(0.05, 1.72, 0.05), Vector3(CARGO_X0 - 0.075, 1.86, z), _chrome())
		K.box(self, Vector3(0.04, 0.05, 0.24), Vector3(CARGO_X0 - 0.09, 1.24, z + signf(z) * 0.12), _chrome())

	# 尾灯组：红 / 琥珀 / 倒车灯三格，挂在后框两角
	for z in [-0.86, 0.86]:
		K.box(self, Vector3(0.06, 0.36, 0.26), Vector3(-3.14, 0.78, z), _dark())
		K.box(self, Vector3(0.02, 0.15, 0.20), Vector3(-3.175, 0.87, z), _tail_lens(), Vector3.ZERO, false)
		K.box(self, Vector3(0.02, 0.08, 0.20), Vector3(-3.175, 0.755, z), _amber(), Vector3.ZERO, false)
		K.box(self, Vector3(0.02, 0.09, 0.20), Vector3(-3.175, 0.665, z), _reverse(), Vector3.ZERO, false)
	# 后牌照
	K.box(self, Vector3(0.02, 0.15, 0.40), Vector3(-3.13, 0.78, 0.0), _plate())
	_text("HOSHI 500", Vector3(-3.142, 0.78, 0.0), 0.085, Color("#232830"), Vector3(0, -90, 0))


# ---------------------------------------------------------------- 驾驶室

func _build_cab() -> void:
	var shell := _shell()
	var dark := _dark()
	var chrome := _chrome()
	var cab_len := CAB_X1 - CARGO_X1
	var cab_mid := (CARGO_X1 + CAB_X1) * 0.5

	# 驾驶室主体
	K.box(self, Vector3(cab_len, 1.66, 2.04), Vector3(cab_mid, 1.55, 0.0), shell)
	# 车顶导流罩：往车厢方向压下去，衔接驾驶室和厢体的高差
	K.box(self, Vector3(0.72, 0.40, 1.92), Vector3(0.72, 2.52, 0.0), shell, Vector3(0, 0, -14))
	# 腰线：和厢体那条红线接上，整车看起来是一套设计，而不是两个盒子拼的
	K.box(self, Vector3(cab_len - 0.04, 0.12, 2.05), Vector3(cab_mid, 1.32, 0.0), _stripe())

	# 前脸：格栅 + 三条镀铬横条 + 车标
	K.box(self, Vector3(0.05, 0.30, 1.24), Vector3(CAB_X1 + 0.02, 1.30, 0.0), dark)
	for y in [1.22, 1.30, 1.38]:
		K.box(self, Vector3(0.03, 0.035, 1.16), Vector3(CAB_X1 + 0.045, y, 0.0), chrome)
	K.box(self, Vector3(0.04, 0.11, 0.26), Vector3(CAB_X1 + 0.055, 1.30, 0.0), chrome)

	# 前照灯组：镀铬框 + 深色灯碗 + 发光灯面；外侧角上是琥珀色转向灯
	for z in [-LAMP_Z, LAMP_Z]:
		K.box(self, Vector3(0.07, 0.30, 0.48), Vector3(CAB_X1 + 0.02, LAMP_Y, z), chrome)
		K.box(self, Vector3(0.05, 0.24, 0.42), Vector3(CAB_X1 + 0.045, LAMP_Y, z), dark)
		K.box(self, Vector3(0.02, 0.17, 0.34), Vector3(CAB_X1 + 0.07, LAMP_Y, z), _lens(), Vector3.ZERO, false)
		K.box(self, Vector3(0.05, 0.10, 0.10), Vector3(CAB_X1 + 0.02, LAMP_Y, z * 1.34), _amber(), Vector3.ZERO, false)

	# 前保险杠 + 镀铬饰条 + 雾灯 + 牌照
	K.box(self, Vector3(0.24, 0.38, 2.10), Vector3(CAB_X1 + 0.06, 0.64, 0.0), dark)
	K.box(self, Vector3(0.04, 0.13, 1.92), Vector3(CAB_X1 + 0.19, 0.67, 0.0), chrome)
	for z in [-0.62, 0.62]:
		K.cyl(self, 0.06, 0.05, Vector3(CAB_X1 + 0.20, 0.58, z), _fog_lens(), Vector3(0, 0, 90), 12, -1.0, false)
	K.box(self, Vector3(0.02, 0.16, 0.42), Vector3(CAB_X1 + 0.21, 0.66, 0.0), _plate())
	_text("HOSHI 500", Vector3(CAB_X1 + 0.235, 0.66, 0.0), 0.09, Color("#232830"), Vector3(0, 90, 0))

	# 风挡：向后倾 8°
	K.box(self, Vector3(0.06, 0.78, 1.86), Vector3(CAB_X1 - 0.03, 1.94, 0.0), _glass(), Vector3(0, 0, 8))
	# 雨刷：两根停在风挡下沿，一根抬起来一点，别让它们看起来像贴纸
	for w in [{"z": -0.55, "lift": 0.16}, {"z": 0.12, "lift": 0.10}]:
		K.strut(self, Vector3(CAB_X1 + 0.045, 1.55, w["z"]),
			Vector3(CAB_X1 + 0.035, 1.55 + w["lift"], w["z"] + 0.34), 0.012, _wiper(), 5, false)
	# 遮阳板
	K.box(self, Vector3(0.30, 0.05, 1.90), Vector3(CAB_X1 - 0.06, 2.35, 0.0), dark, Vector3(0, 0, -5))
	# 车顶示廓灯
	for i in 5:
		K.box(self, Vector3(0.09, 0.05, 0.10), Vector3(CAB_X1 - 0.16, 2.405, -0.66 + i * 0.33),
			_amber(), Vector3.ZERO, false)

	# 侧窗 / 窗台 / 门缝 / 门把手 / 后视镜 / 蹬车踏板
	for z in [-1.0, 1.0]:
		K.box(self, Vector3(0.94, 0.60, 0.04), Vector3(1.98, 1.96, z * 1.028), _glass())
		K.box(self, Vector3(0.98, 0.03, 0.05), Vector3(1.98, 1.64, z * 1.030), chrome)
		K.box(self, Vector3(0.02, 1.30, 0.02), Vector3(1.18, 1.60, z * 1.024), dark)
		K.box(self, Vector3(0.16, 0.05, 0.04), Vector3(1.86, 1.46, z * 1.03), chrome)
		# 后视镜：镜臂从门框顶上伸出去，镜面挂在窗外 —— 放在 x=2.36 会正好
		# 压在侧窗上，黑镜壳和黑玻璃糊成一块，远看像窗户破了个洞
		K.strut(self, Vector3(2.50, 2.32, z * 1.02), Vector3(2.50, 2.32, z * 1.30), 0.026, dark, 6)
		K.strut(self, Vector3(2.50, 2.32, z * 1.30), Vector3(2.50, 2.16, z * 1.30), 0.022, dark, 6)
		K.box(self, Vector3(0.09, 0.30, 0.13), Vector3(2.50, 2.02, z * 1.32), dark)
		K.box(self, Vector3(0.02, 0.24, 0.10), Vector3(2.452, 2.02, z * 1.32), _mirror())
		# 两级踏板：落在前轮后面，不然会插进轮胎里
		K.box(self, Vector3(0.42, 0.05, 0.26), Vector3(1.30, 0.44, z * 1.05), dark)
		K.box(self, Vector3(0.42, 0.05, 0.26), Vector3(1.30, 0.28, z * 1.05), dark)

	# 车门上的小字
	_text("HOSHI MART", Vector3(1.62, 1.13, 1.032), 0.085, Color("#8f99a3"))
	# 天线
	K.strut(self, Vector3(2.08, 2.38, -0.86), Vector3(1.98, 2.90, -0.90), 0.008, dark, 4, false)


func _build_wheels() -> void:
	var tire := _dark()
	var hub := _chrome()
	var wall := _mat("wall", Color("#0e1116"), {"shade": 0.8, "rim": 0.1, "line": 0.004})
	for ax in AXLES:
		for z in [-0.94, 0.94]:
			# 轮毂节点只负责自转：网格绕自身 Y 轴 → 转 90° 后轴沿 Z，
			# 父节点绕 Z 旋转就等于让轮子滚起来
			var w := Node3D.new()
			w.position = Vector3(ax, WHEEL_R, z)
			add_child(w)
			K.cyl(w, WHEEL_R, 0.34, Vector3.ZERO, tire, Vector3(90, 0, 0), 18)
			# 胎侧 + 轮辋 + 轮毂三层同心圆，远看才有「轮子在转」的层次
			K.cyl(w, 0.27, 0.35, Vector3.ZERO, wall, Vector3(90, 0, 0), 16)
			K.cyl(w, 0.20, 0.36, Vector3.ZERO, hub, Vector3(90, 0, 0), 12)
			_wheels.append(w)


# ---------------------------------------------------------------- 车灯

func _build_lights() -> void:
	for z in [-LAMP_Z, LAMP_Z]:
		# 灯头光晕：一盏柔光球，让灯面在雨雾里「发糊」
		K.sphere(self, 0.22, Vector3(CAB_X1 + 0.10, LAMP_Y, z),
			K.soft_clipped(Color("#ffd7a0"), 0.40, 1.6, clip_box), Vector3.ZERO, 12, 0.9, false)

		var sl := SpotLight3D.new()
		sl.position = Vector3(CAB_X1 + 0.12, LAMP_Y, z)
		# 灯头朝 +X 并下压 6°：和光柱同一个角度，光斑才落在地上而不是天上
		sl.rotation_degrees = Vector3(BEAM_PITCH, -90, 0)
		sl.light_color = Color("#ffe3b8")
		sl.light_energy = 5.0
		sl.spot_range = 16.0
		sl.spot_angle = 28.0
		sl.spot_attenuation = 1.0
		sl.light_volumetric_fog_energy = 2.5
		sl.shadow_enabled = false
		add_child(sl)

		# 空气里的光柱：锥体网格，跟着车一起转
		var pivot := Node3D.new()
		pivot.position = Vector3(CAB_X1 + 0.10, LAMP_Y, z)
		pivot.rotation_degrees = Vector3(BEAM_PITCH, -90, 0)
		add_child(pivot)
		var cone := MeshInstance3D.new()
		cone.mesh = _beam_mesh(BEAM_NEAR, BEAM_FAR, BEAM_LEN, 20)
		cone.material_override = _beam()
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(cone)

	# 地面光池：两盏灯各摊一块，中间重叠的地方自然更亮。
	# PlaneMesh 本来就是躺平的（法线 +Y），不用再转 90°。
	for z in [-0.55, 0.55]:
		K.plane(self, Vector2(POOL_HALF.x * 2.0, POOL_HALF.y * 2.0),
			Vector3(POOL_CENTER_X, 0.02, z), _pool(), Vector3.ZERO, false)

	# 尾灯：只给一点自发光 + 一盏很小的红光，够在湿地上留个红点
	_tail_light = OmniLight3D.new()
	_tail_light.position = Vector3(CARGO_X0 - 0.35, 1.0, 0.0)
	_tail_light.light_color = Color("#ff5a3a")
	_tail_light.light_energy = 0.9
	_tail_light.omni_range = 3.2
	_tail_light.shadow_enabled = false
	add_child(_tail_light)


func _beam() -> ShaderMaterial:
	if _beam_mat == null:
		_beam_mat = K.headlamp({
			"beam_color": Color("#ffdca8"),
			"strength": 0.72,
			"length": BEAM_LEN,
			"radial_power": 2.0,
			"end_fade": 0.5,
		}, clip_box)
	return _beam_mat


func _pool() -> ShaderMaterial:
	if _pool_mat == null:
		_pool_mat = K.headlamp({
			"beam_color": Color("#ffcf94"),
			"strength": 0.24,
			"pool": true,
			"pool_half": POOL_HALF,
		}, clip_box)
	return _pool_mat


## 光柱网格：沿 −Z 铺开的无盖锥筒。
## 不用 CylinderMesh 是因为它带封盖 —— 正对着灯看时，远端那块盖会变成一张
## 悬在空气里的发光圆盘；没有盖，看到的才是锥面叠出来的光。
func _beam_mesh(near_r: float, far_r: float, length: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var rows: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var r := lerpf(near_r, far_r, t)
		var z := -length * t
		var row: Array = []
		for s in seg:
			var a := TAU * float(s) / float(seg)
			row.append(Vector3(cos(a) * r, sin(a) * r, z))
		rows.append(row)
	for i in rings:
		for s in seg:
			var s2 := (s + 1) % seg
			var a: Vector3 = rows[i][s]
			var b: Vector3 = rows[i][s2]
			var c: Vector3 = rows[i + 1][s2]
			var d: Vector3 = rows[i + 1][s]
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


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
