extends Node3D
## 城门 NPC。
##
## 素材是 3Dmodel 里那套 Blender 2.79 角色，经 tools/convert_blend_to_glb.py
## 导出成 glb（每个 .blend 里塞了基础版 + 一堆换装版，转换时只留基础版）。
##
## 和主角（VRoid 的 gaia）的区别：
##   - 骨架是 3ds Max Biped 命名（Bip001-L-UpperArm），不是 VRM 的 J_Bip_*
##   - 本来就是 A-pose（手臂自然下垂），**不需要掰姿势**
##   - 材质是 PBR 的 diff/mask/norm 三张图，只有部分 surface 带贴图
##
## 朝向不靠手填角度：用「脚踝 → 脚趾」的水平方向自动算。
## 手填 yaw 很容易差 180°，而脚趾方向是模型自己带的、不会骗人。

const K := preload("res://scripts/kit.gd")
const TOON_TEX := preload("res://shaders/toon_tex.gdshader")

@export_file("*.glb") var model_path := ""
## 面朝的方向（世界坐标，只需水平分量）。默认朝 -Z，也就是朝城外
@export var face_dir := Vector3(0.0, 0.0, -1.0)
## 平色时代替贴图的兜底色（surface 没有贴图时用）
@export var fallback_color := Color("#8a8f9c")
## 细节：站着的呼吸起伏幅度（米），0 = 不动
@export var idle_bob := 0.012
## 呼吸频率（每秒次）
@export var idle_hz := 0.28

var _model: Node3D
var _skel: Skeleton3D
var _t := 0.0
var _base_y := 0.0


func _ready() -> void:
	if model_path.is_empty():
		push_warning("NPC 未指定 model_path")
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("NPC 模型加载失败: " + model_path)
		return
	_model = packed.instantiate()
	add_child(_model)

	_skel = _find_first(_model, "Skeleton3D")
	_face_along(face_dir)
	_apply_material(_model)

	_base_y = _model.position.y


## 用脚趾方向对齐朝向。找不到脚趾骨就退回用 rotation.y = 0。
func _face_along(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		return
	d = d.normalized()
	var want := atan2(d.x, d.z)

	if _skel == null:
		rotation.y = want
		return

	var foot := _skel.find_bone("Bip001-L-Foot")
	var toe := _skel.find_bone("Bip001-L-Toe0")
	if foot < 0 or toe < 0:
		# 没有脚趾骨时只能假设模型本地朝 +Z
		rotation.y = want
		return

	# 两只脚的脚趾方向**取平均**：人站着的时候脚是外八的，
	# 只看一只脚会把朝向拧歪几度（实测 Isaac 单脚算出来是 171.6°，不是 180）。
	var sum := Vector3.ZERO
	var used := 0
	for side in ["L", "R"]:
		var fi := _skel.find_bone("Bip001-%s-Foot" % side)
		var ti := _skel.find_bone("Bip001-%s-Toe0" % side)
		if fi < 0 or ti < 0:
			continue
		var d2 := _skel.get_bone_global_pose(ti).origin - _skel.get_bone_global_pose(fi).origin
		d2.y = 0.0
		if d2.length() < 0.001:
			continue
		sum += d2.normalized()
		used += 1

	if used == 0 or sum.length() < 0.001:
		rotation.y = want
		return
	var local := sum.normalized()

	# 模型本地的「前方」角度，转到世界要多少度
	rotation.y = want - atan2(local.x, local.z)


## 套三渲二材质：有 albedo 贴图的走 toon_tex，没有的走 kit.toon 平色
func _apply_material(n: Node) -> void:
	for mi in _find_all(n, "MeshInstance3D"):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i) as BaseMaterial3D
			var m := ShaderMaterial.new()
			if src != null and src.albedo_texture != null:
				m.shader = TOON_TEX
				m.set_shader_parameter("base_tex", src.albedo_texture)
				m.set_shader_parameter("base_color", Color(1, 1, 1))
				m.set_shader_parameter("use_alpha_scissor", false)
				m.set_shader_parameter("shade_floor", 0.55)
				m.set_shader_parameter("rim_strength", 0.05)
				var om := ShaderMaterial.new()
				om.shader = preload("res://shaders/outline.gdshader")
				om.set_shader_parameter("thickness", 0.006)
				om.set_shader_parameter("line_color", Color(0.05, 0.05, 0.07))
				m.next_pass = om
			else:
				var col := fallback_color
				if src != null:
					col = src.albedo_color
				m = K.toon(col, {"line": 0.006, "shade": 0.55, "rim": 0.06})
			mi.set_surface_override_material(i, m)


func _process(delta: float) -> void:
	if idle_bob <= 0.0 or _model == null:
		return
	_t += delta
	_model.position.y = _base_y + sin(_t * idle_hz * TAU) * idle_bob


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
