extends Node3D
## 角色：加载 VRoid 导出的 glb，套姿势，并换成带贴图的三渲二材质。
##
## 为什么需要姿势代码：VRoid 导出的是 T-pose（双臂平伸），而且**不带任何动画**
## （glb 里 animations 数量为 0）。所以在接入真正的动画剪辑之前，
## 站立、抱头这些姿态只能靠直接旋转骨骼来摆。
##
## 材质：VRoid 的 MToon 在 Godot 里会退化成 unshaded 的 StandardMaterial3D，
## 结果是不吃场景灯光、像贴纸贴在画面上。这里按每个 surface 原来的贴图
## 重建一套带贴图三渲二材质（shaders/toon_tex.gdshader），并挂同款反向外壳描边。

const TOON_TEX := preload("res://shaders/toon_tex.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const K := preload("res://scripts/kit.gd")

## 平涂取色表：按 surface 原材质名做「包含匹配」，从上往下第一个命中的生效。
##
## VRoid 的材质名长这样（实测自 gaia.glb）：
##   N00_000_00_Body_00_SKIN / N00_005_01_Tops_01_CLOTH / N00_000_00_EyeIris_00_EYE
## 所以用关键字匹配比精确名可靠，换一套衣服也不会全部掉到兜底色。
const FLAT_COLORS := [
	["FaceMouth", Color("#2a2a33")],
	["FaceBrow", Color("#2a2a33")],
	["FaceEyeline", Color("#2a2a33")],
	["EyeIris", Color("#6f8fb8")],
	["EyeWhite", Color("#f0f0f2")],
	["EyeHighlight", Color("#f0f0f2")],   # 高光跟眼白同色，否则是一颗灰点
	["Face_00_SKIN", Color("#e8c4a8")],
	["Body_00_SKIN", Color("#e8c4a8")],
	["Hair", Color("#3a3f52")],
	["CLOTH", Color("#4a5568")],
]
const FLAT_FALLBACK := Color("#808080")
## 平涂模式的暗部下限。比夜景用的 0.38 亮，白天太暗会显得脏。
const FLAT_SHADE := 0.55

## 模型路径
@export_file("*.glb") var model_path := "res://assets/characters/gaia.glb"
## 朝向（度）。0 = 面向 +Z，180 = 面向 -Z
@export var face_yaw_deg := 180.0

## 起始姿势
@export_enum("stand", "cover_head") var pose := "cover_head"
## 手臂下垂角度（弧度），stand 姿势用
@export_range(0.0, 1.6) var arm_drop := 1.22

## 描边厚度，0 = 不描边
@export_range(0.0, 0.03) var outline_width := 0.006

## true = 不加载 VRM 贴图，改用 kit.toon() 上纯色平涂（异世界草原用）。
## 默认 false：雨夜练手场景已经按贴图版验收过，不能因为加了这个开关就变样。
@export var use_flat_colors := false

## 整体色调与亮度。VRoid 的贴图亮度接近 0.5，而这个夜景里建筑 albedo 只有 0.3~0.5，
## 不压暗的话角色会是全场最亮的物体。乘到贴图上，同时偏冷以匹配月光。
@export var tint := Color(0.58, 0.60, 0.70)
## 暗部亮度下限。和建筑用的 0.45 对齐，否则角色连阴影都比环境亮。
@export_range(0.0, 1.0) var shade_floor := 0.38
## 边缘光强度。注意它加的是自发光，夜景里稍微大一点就糊成一团光。
@export_range(0.0, 0.5) var rim_strength := 0.05

@export_group("冲刺")
## 往雨里冲多远（米）
@export var dash_distance := 2.8
## 冲刺速度（米/秒）
@export var dash_speed := 3.0
## 开场等待多久再起跑，负数 = 不自跑（由外部调用 dash()）
@export var dash_delay := 1.2
## 跑动时上下颠的幅度（米）
@export var bob_height := 0.035
## 颠动频率（每秒次）
@export var bob_hz := 2.6
## 左右摇晃幅度（度）
@export var sway_deg := 3.5

var _skel: Skeleton3D
var _model: Node3D
var _model_base_y := 0.0
var _dashing := false
var _dash_t := 0.0


func _ready() -> void:
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("角色模型加载失败: " + model_path)
		return
	_model = packed.instantiate()
	add_child(_model)

	rotation.y = deg_to_rad(face_yaw_deg)

	_skel = _find_first(_model, "Skeleton3D")
	if _skel != null:
		_apply_pose(pose)

	_apply_toon(_model)

	_model_base_y = _model.position.y
	if dash_delay >= 0.0:
		get_tree().create_timer(dash_delay).timeout.connect(dash)


## 抱着头往正前方（角色面朝的方向）冲出去
func dash() -> void:
	if _dashing:
		return
	_dashing = true
	_dash_t = 0.0
	# 这个 VRoid 模型的脸朝 +Z（实测头发 AABB 在 Z 上是 -0.169→+0.109，后脑勺在 -Z），
	# 所以朝向前方 = basis.z，不是常见的 -basis.z。
	var forward := global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var target := global_position + forward * dash_distance
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, dash_distance / dash_speed) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func() -> void:
		_dashing = false
		# 收尾复位，避免停在颠到一半的高度
		_model.position.y = _model_base_y
		_model.rotation.z = 0.0)


func _process(delta: float) -> void:
	if not _dashing:
		return
	_dash_t += delta
	# 上下颠 + 左右晃，套在模型子节点上，避免和位移 Tween 抢 transform
	var phase := _dash_t * bob_hz * TAU
	_model.position.y = _model_base_y + absf(sin(phase)) * bob_height
	_model.rotation.z = sin(phase * 0.5) * deg_to_rad(sway_deg)


## 切换到指定姿势
func _apply_pose(pose_name: String) -> void:
	if _skel == null:
		return
	_reset_pose()
	match pose_name:
		"cover_head":
			_pose_cover_head()
		_:
			_pose_stand()


func _reset_pose() -> void:
	for i in _skel.get_bone_count():
		_skel.set_bone_pose_rotation(i, Quaternion.IDENTITY)


## 自然站立：手臂垂下，略微内收
func _pose_stand() -> void:
	var z := Vector3(0.0, 0.0, 1.0)
	_set_rot("J_Bip_L_UpperArm", Quaternion(z, -arm_drop))
	_set_rot("J_Bip_R_UpperArm", Quaternion(z, arm_drop))
	_set_rot("J_Bip_L_LowerArm", Quaternion(z, -0.12))
	_set_rot("J_Bip_R_LowerArm", Quaternion(z, 0.12))


## 双手抱头，像准备冲进雨里
##
## 参数是实测出来的（绕 Z 轴，上臂抬 1.20、前臂弯 1.75）：
## 手落在头顶上方约 10 cm、距身体中线约 2 cm，双臂几乎并拢在头顶。
## 注意前臂的肘关节只能绕 Z 轴弯 —— 绕 X 轴转是沿骨头自身扭转，手不会动。
func _pose_cover_head() -> void:
	var z := Vector3(0.0, 0.0, 1.0)
	_set_rot("J_Bip_L_UpperArm", Quaternion(z, 1.20))
	_set_rot("J_Bip_R_UpperArm", Quaternion(z, -1.20))
	_set_rot("J_Bip_L_LowerArm", Quaternion(z, 1.75))
	_set_rot("J_Bip_R_LowerArm", Quaternion(z, -1.75))


func _set_rot(bone: String, q: Quaternion) -> void:
	var idx := _skel.find_bone(bone)
	if idx < 0:
		push_warning("找不到骨骼: " + bone)
		return
	_skel.set_bone_pose_rotation(idx, q)


# ---------------------------------------------------------------- 程序化移动动画
##
## gaia.glb 里没有任何动画剪辑（animations 数量为 0，连 AnimationPlayer 都没有），
## 所以走路摆臂摆腿只能直接驱动骨骼。
##
## 轴向是实测出来的，不是猜的：
##   大腿 / 小腿  绕本地 X 轴 → 前后摆（正角 = 向后；绕 Z 是侧摆 dx=0.42）
##   上臂        绕本地 Y 轴 → 前后摆（绕 X 位移 0.000，纯粹是沿骨长扭转）
##
## phase 是步态相位（弧度），amount 是幅度 0..1。
## 调用方按「速度 × 时间」推进 phase —— 走得快步频自然变高，不用另设参数。

func set_locomotion(phase: float, amount: float) -> void:
	if _skel == null or pose != "stand":
		return
	var a := clampf(amount, 0.0, 1.0)
	var swing := sin(phase)
	var r := Vector3(1.0, 0.0, 0.0)
	var y := Vector3(0.0, 1.0, 0.0)
	var z := Vector3(0.0, 0.0, 1.0)

	# 大腿：左右反相。0.50 rad ≈ 28°，接近真人行走的摆幅
	_set_rot("J_Bip_L_UpperLeg", Quaternion(r, swing * 0.50 * a))
	_set_rot("J_Bip_R_UpperLeg", Quaternion(r, -swing * 0.50 * a))

	# 膝盖只能向后弯（正角）。在腿往后回摆的阶段弯得最多，
	# 前摆时接近伸直 —— 这是走和「原地蹬腿」的区别所在
	_set_rot("J_Bip_L_LowerLeg", Quaternion(r, maxf(0.0, -swing + 0.25) * 0.85 * a))
	_set_rot("J_Bip_R_LowerLeg", Quaternion(r, maxf(0.0, swing + 0.25) * 0.85 * a))

	# 上臂：与同侧腿反相（左腿前 → 左臂后），基础姿势是「手臂放下」
	_set_rot("J_Bip_L_UpperArm",
		Quaternion(z, -arm_drop) * Quaternion(y, -swing * 0.38 * a))
	_set_rot("J_Bip_R_UpperArm",
		Quaternion(z, arm_drop) * Quaternion(y, swing * 0.38 * a))

	# 前臂保持一点预弯，完全笔直会显得僵硬
	_set_rot("J_Bip_L_LowerArm", Quaternion(z, -0.14))
	_set_rot("J_Bip_R_LowerArm", Quaternion(z, 0.14))


## 空中姿势：收腿 + 手臂略微抬起。
## 不做的话跳跃时腿完全伸直，一眼就看得出「没有动画」。
func set_air_pose() -> void:
	if _skel == null or pose != "stand":
		return
	var r := Vector3(1.0, 0.0, 0.0)
	var z := Vector3(0.0, 0.0, 1.0)
	# 大腿负角 = 向前抬
	_set_rot("J_Bip_L_UpperLeg", Quaternion(r, -0.45))
	_set_rot("J_Bip_R_UpperLeg", Quaternion(r, -0.18))
	_set_rot("J_Bip_L_LowerLeg", Quaternion(r, 0.80))
	_set_rot("J_Bip_R_LowerLeg", Quaternion(r, 0.35))
	_set_rot("J_Bip_L_UpperArm",
		Quaternion(z, -arm_drop) * Quaternion(r, -0.30))
	_set_rot("J_Bip_R_UpperArm",
		Quaternion(z, arm_drop) * Quaternion(r, -0.30))


## 按 surface 重建材质。
## use_flat_colors = true 走平涂分支（kit.toon 纯色 + 描边），否则走原来的贴图分支。
func _apply_toon(n: Node) -> void:
	for node in _find_all(n, "MeshInstance3D"):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i) as BaseMaterial3D
			if use_flat_colors:
				mi.set_surface_override_material(i, K.toon(_flat_color(src), {
					"line": outline_width,
					"shade": FLAT_SHADE,
					"rim": 0.12,
				}))
				continue

			var m := ShaderMaterial.new()
			m.shader = TOON_TEX
			if src != null:
				m.set_shader_parameter("base_tex", src.albedo_texture)
				m.set_shader_parameter("base_color", src.albedo_color * tint)
				# 头发 / 睫毛 / 眉毛是镂空的，需要 alpha 剪裁
				m.set_shader_parameter("use_alpha_scissor",
					src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			m.set_shader_parameter("shade_floor", shade_floor)
			m.set_shader_parameter("rim_strength", rim_strength)
			if outline_width > 0.0:
				var om := ShaderMaterial.new()
				om.shader = OUTLINE
				om.set_shader_parameter("thickness", outline_width)
				om.set_shader_parameter("line_color", Color(0.045, 0.05, 0.075))
				m.next_pass = om
			mi.set_surface_override_material(i, m)


## 按材质名关键字平涂取色，未命中用兜底灰
func _flat_color(src: BaseMaterial3D) -> Color:
	if src == null:
		return FLAT_FALLBACK
	var nm := src.resource_name
	for pair in FLAT_COLORS:
		if nm.contains(pair[0]):
			return pair[1]
	return FLAT_FALLBACK


## 模型根节点（glb 实例）。外部做姿势补间用，比如「躺在地上 → 站起来」。
## 注意别拿自己去补间：CharacterBody3D 的 transform 归物理管。
func get_model_node() -> Node3D:
	return _model


func _find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null


func _find_all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
