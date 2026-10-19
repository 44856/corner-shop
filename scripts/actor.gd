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


## 按 surface 重建带贴图的三渲二材质
func _apply_toon(n: Node) -> void:
	for mi in _find_all(n, "MeshInstance3D"):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i) as BaseMaterial3D
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
