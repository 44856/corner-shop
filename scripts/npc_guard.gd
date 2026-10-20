extends Node3D
## 城门 NPC。
##
## 素材是 3Dmodel 里那套 Blender 2.79 角色，经 tools/convert_blend_to_glb.py
## 导出成 glb（每个 .blend 里塞了基础版 + 一堆换装版，转换时只留基础版）。
##
## 和主角（VRoid 的 gaia）的区别：
##   - 骨架是 3ds Max Biped 命名（Bip001-L-UpperArm），不是 VRM 的 J_Bip_*
##   - 导进来是 **A-pose**（手臂外张 36.8°、肘伸直、两腿并拢），
##     不是能直接站街的姿势 —— 这里用骨骼把它掰成自然站姿（见 _apply_stance）
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
## 目标身高（米）。加载后会自动等比缩放到这个高度：
## 那套模型是 2.79 的厘米单位工程，Blender 导出 → Godot 导入这条链路上
## 单位会被多除一次 100（实测导进来只有 2 厘米高），与其逐个数值补偿，
## 不如按「这个人应该多高」直接归一化，换哪套模型都不用改代码。
@export var target_height := 2.33

@export_group("站姿")
## 用哪套站姿（见 STANCES）。两人用不同预设，避免像复制粘贴
@export_enum("guard_a", "guard_b") var stance := "guard_a"
## 微动的相位偏移（秒）。两个 NPC 必须错开，同步呼吸是最容易被一眼看穿的假
@export var phase_offset := 0.0

@export_group("微动")
## 呼吸频率（每秒次）。静立时 13 次/分左右偏慢，显得沉得住
@export var breath_hz := 0.22
## 胸腔起伏的幅度（度）。实测 1.1° 在 3 米外才看得出胸口在动又不抖
@export var breath_deg := 1.1
## 头部巡视频率（每秒次）。很低，一秒钟转 0.05 圈 ≈ 20 秒看一圈
@export var look_hz := 0.055
## 头部巡视幅度（度）
@export var look_deg := 9.0
## 垂手时上臂随呼吸的轻微摆动（度）
@export var sway_deg := 1.4
## 玩家走近到多近开始转头看他（米）
@export var notice_radius := 5.0
## 转头最大角度（度）。超过这个角度就不是「歪头看」而是「扭断脖子」
@export var look_limit_deg := 58.0

# ---------------------------------------------------------------- 姿势数据

## 骨架空间的方向约定（dump 出来的实测值，别凭感觉改）：
##   +X = 角色的**左**手边 —— 因为模型面朝 +Z，前 × 上 = 右 = −X
##   +Y = 上
##   +Z = 前（脚趾指向；两只脚平均下来外八 8.4°，所以是"大致朝前"）
const AX := Vector3(1.0, 0.0, 0.0)
const AY := Vector3(0.0, 1.0, 0.0)
const AZ := Vector3(0.0, 0.0, 1.0)

## 站姿表：骨骼 → [[轴, 角度], ...]，按列表顺序叠加。
##
## 为什么不写欧拉角：Biped 骨骼的局部轴是 3ds Max 的约定（局部 X 朝上、
## 局部 Y 顺着骨长），对着它填 XYZ 角度几乎必错，而且换一套模型就失效。
## 这里一律「绕骨架空间的某个世界轴转多少度」，语义是能读懂的。
##
## 三条通用修正（数值都是照骨骼长度反推的，不是试出来的）：
##   1. 上臂内收 → 手臂落到身侧。留 6~8° 不贴身，真人手臂不会贴死躯干
##   2. 肘前屈 → 纯垂手也假，真人的小臂总是略向前、微微内旋
##   3. 膝微屈 → 膝盖锁死的人像立牌。但直接转小腿会让**脚离地**，
##      所以按 α（髋屈）/ β（膝屈）配对：L1·sinα = L2·sin(β−α) 才能让
##      脚踝的水平位置回到原处。实测 α=4°、β=8°，脚只抬高 0.6cm。
const STANCES := {
	# 站岗型：双脚与肩同宽，双手垂在体侧，右肘多屈一点（像手搭在剑柄上）
	"guard_a": {
		"Bip001-L-UpperArm": [[AZ, -33.0], [AX, -5.0]],
		"Bip001-R-UpperArm": [[AZ, 33.0], [AX, -6.0]],
		"Bip001-L-Forearm": [[AX, -13.0]],
		"Bip001-R-Forearm": [[AX, -21.0]],
		"Bip001-L-Thigh": [[AZ, 3.5], [AX, -4.0]],
		"Bip001-R-Thigh": [[AZ, -3.5], [AX, -4.0]],
		"Bip001-L-Calf": [[AX, 8.0]],
		"Bip001-R-Calf": [[AX, 8.0]],
		"Bip001-L-Foot": [[AX, -8.0]],
		"Bip001-R-Foot": [[AX, -8.0]],
	},
	# 松弛型：重心压在左腿、右腿松一点，左臂几乎伸直，右臂虚搭在腰前
	"guard_b": {
		"Bip001-L-UpperArm": [[AZ, -31.0], [AX, -4.0]],
		"Bip001-R-UpperArm": [[AZ, 32.0], [AX, -7.0]],
		"Bip001-L-Forearm": [[AX, -9.0]],
		"Bip001-R-Forearm": [[AX, -28.0]],
		"Bip001-L-Thigh": [[AZ, 3.0], [AX, -2.0]],
		"Bip001-R-Thigh": [[AZ, -4.0], [AX, -5.0]],
		"Bip001-L-Calf": [[AX, 4.0]],
		"Bip001-R-Calf": [[AX, 10.0]],
		"Bip001-L-Foot": [[AX, -4.0]],
		"Bip001-R-Foot": [[AX, -10.0]],
		# 头微微偏一点、身体略侧，像在听人说话而不是笔直立正
		"Bip001-Spine2": [[AY, 3.0], [AZ, 1.0]],
		"Bip001-Head": [[AY, -4.0]],
	},
}

## ---- 独立挂骨 ----
##
## Skadi 的臂甲（L_Arm01→02→03→04）和系带（String_L）挂在 **Dummy_Cloth**
## （Spine2 的子节点）下面，不在手臂链上 —— 建模时是拿骨骼直接套在上臂上的。
## 于是上臂内收 31° 之后，臂甲还留在 A-pose 的位置，看起来像两截黑筒
## 飘在肩膀外面。
##
## 补一次「绕肩关节、同轴同角度」的旋转就能贴回去：上臂的旋转本来就是
## 绕肩关节的 global 旋转，臂甲用同一个枢轴转同样的角度，两者严格同步。
## 只转链的根（L_Arm01），子骨骼和系带会自动跟随 —— 对父子都施加会转两遍。
const ARM_PARTS := [
	["L_Arm01", "Bip001-L-UpperArm"],
	["R_Arm01", "Bip001-R-UpperArm"],
]

## 微动要动的骨骼，**必须按父到子的顺序**排：
## 每帧先把它们恢复成基础站姿，再叠加微动；顺序错的话子骨骼会拿到父骨骼
## 本帧的新位置去当基准，微动会一层层放大成抽搐。
const IDLE_BONES := [
	"Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head",
	"Bip001-L-UpperArm", "Bip001-L-Forearm",
	"Bip001-R-UpperArm", "Bip001-R-Forearm",
]

## ---- 挂件 ----
##
## Isaac 那套素材（GuildWar 换装）肩上飘着四颗蓝水晶。问题是它们蒙皮到
## Crystal_Dummy 这一串骨骼上，而那串骨骼挂在 **Dummy_Root** 下 —— 一条
## 完全独立的、没有任何动画的根骨。于是角色在动，四颗水晶钉在半空不动，
## 从侧面看就是四盏浮空的灯。
##
## 改法：把它们改挂到 Spine2 上，落点收到背后肩胛两侧（相对 Spine2 的偏移），
## 这样会跟着呼吸、转头一起走，读起来像披风上嵌的晶石而不是浮空道具。
## Skadi 没有这组骨骼，会自动跳过。
const PROP_ANCHOR := "Bip001-Spine2"
const PROP_TARGETS := {
	"LF_Crystal_Dummy": Vector3(0.27, 0.05, -0.38),
	"LB_Crystal_Dummy": Vector3(0.27, -0.24, -0.44),
	"RF_Crystal_Dummy": Vector3(-0.27, 0.05, -0.38),
	"RB_Crystal_Dummy": Vector3(-0.27, -0.24, -0.44),
}

# ---------------------------------------------------------------- 状态

var _model: Node3D
var _skel: Skeleton3D
var _t := 0.0
## 尺寸归一化比例（世界跨度 → 目标身高）
var _unit_scale := 1.0
## 微动骨骼的索引与「基础站姿」下的 global pose，每帧从它出发
var _idle_idx: Array[int] = []
var _idle_base: Array[Transform3D] = []
## 挂件骨骼与它们相对 PROP_ANCHOR 的偏移
var _prop_idx: Array[int] = []
var _prop_off: Array[Vector3] = []
var _anchor_idx := -1
## 注目目标（世界坐标）与权重。权重做平滑，转头才不会是「啪一下扭过去」
var _look_point := Vector3.ZERO
var _look_has := false
var _look_w := 0.0
var _look_yaw := 0.0


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
	# 顺序有讲究：先归一化（用 A-pose 量身高最准），再掰姿势，
	# 最后记 baseline。姿势会让脚踝抬高 0.6cm，反过来量身高会偏小。
	_normalize_height()
	_apply_stance()
	_face_along(face_dir)
	_apply_material(_model)
	_capture_idle_base()
	_setup_props()


## 把模型等比缩放到 target_height，并把它挪到脚踩地面（世界 y=0）
##
## 必须量**骨骼在世界里的跨度**，不能量网格包围盒：
## 这是蒙皮网格，顶点由骨骼矩阵决定，MeshInstance3D 自己的变换根本不参与。
## 这套模型的网格节点带一层 ≈83 的缩放，包围盒量出来是「正常」的 2.33m，
## 但骨骼在厘米空间里（pelvis y≈108、头顶 y≈198），实际画出来是 197.8m 高的巨像。
## 于是照着包围盒归一化（s≈1.0）等于什么都没做 —— 城门口会站着一尊神像。
##
## 缩放打在 NPC 根节点上：实测世界跨度对它是线性的（197.8 × 0.01178 = 2.33），
## 所以量完直接按比例缩一次就够，不用迭代。
func _normalize_height() -> void:
	if _skel == null:
		push_warning("NPC 没有骨架，跳过尺寸归一化")
		return

	var lo := 1e9
	var hi := -1e9
	for i in _skel.get_bone_count():
		var y: float = (_skel.global_transform * _skel.get_bone_global_pose(i).origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)

	var height := hi - lo
	if height < 0.0001 or target_height <= 0.0:
		return

	_unit_scale = target_height / height
	scale = Vector3.ONE * _unit_scale
	# 最低那根骨骼不在 0 的话，缩放后补一次抬升，否则会埋地或悬空。
	# _model.position 在 NPC 本地空间（还会被 _unit_scale 缩一次），
	# 要让世界位移等于 −lo·k，本地位移就是 −lo
	if absf(lo) > 0.001:
		_model.position.y = -lo


## 在**骨架空间**里给某根骨骼叠加一次绕世界轴的旋转。
##
## 用 global pose 而不是 local pose：这样「转上臂」是绕肩膀这个点转，
## 前臂和手会自然跟着走；写 local 的话就得自己算父骨骼的坐标系。
func _rot_bone(bone: String, axis: Vector3, deg: float) -> void:
	if _skel == null or absf(deg) < 0.0001:
		return
	var i := _skel.find_bone(bone)
	if i < 0:
		return
	var g := _skel.get_bone_global_pose(i)
	var r := Basis(axis.normalized(), deg_to_rad(deg))
	# 只转方向、不动原点：骨骼是绕自己的关节点转的
	_skel.set_bone_global_pose(i, Transform3D(r * g.basis, g.origin))


## 绕**另一根骨骼的关节点**旋转（挂骨跟随用，见 ARM_PARTS）
func _rot_about(bone: String, pivot_bone: String, axis: Vector3, deg: float) -> void:
	if _skel == null or absf(deg) < 0.0001:
		return
	var i := _skel.find_bone(bone)
	var p := _skel.find_bone(pivot_bone)
	if i < 0 or p < 0:
		return
	var g := _skel.get_bone_global_pose(i)
	var pivot := _skel.get_bone_global_pose(p).origin
	var r := Basis(axis.normalized(), deg_to_rad(deg))
	_skel.set_bone_global_pose(i, Transform3D(r * g.basis, pivot + r * (g.origin - pivot)))


## 按 STANCES 把 A-pose 掰成自然站姿
func _apply_stance() -> void:
	if _skel == null:
		return
	var table: Dictionary = STANCES.get(stance, {})
	for bone in table:
		for step in table[bone]:
			_rot_bone(bone, step[0], step[1])
	# 顺序不能颠倒：挂骨要等手臂转完再跟着转，否则会被手臂的旋转带第二遍
	for pair in ARM_PARTS:
		var arm: String = pair[1]
		if not table.has(arm):
			continue
		for step in table[arm]:
			_rot_about(pair[0], arm, step[0], step[1])


## 记下微动骨骼在基础站姿下的 global pose
func _capture_idle_base() -> void:
	if _skel == null:
		return
	for b in IDLE_BONES:
		var i := _skel.find_bone(b)
		if i < 0:
			continue
		_idle_idx.append(i)
		_idle_base.append(_skel.get_bone_global_pose(i))


## 把浮空挂件（水晶）改挂到上半身：骨骼在就收，不在就跳过
func _setup_props() -> void:
	if _skel == null:
		return
	_anchor_idx = _skel.find_bone(PROP_ANCHOR)
	if _anchor_idx < 0:
		return
	for bone in PROP_TARGETS:
		var i := _skel.find_bone(bone)
		if i < 0:
			continue
		_prop_idx.append(i)
		_prop_off.append(PROP_TARGETS[bone])


## 每帧按锚点骨骼的当前姿态摆挂件。放在微动之后调用，
## 这样水晶跟着的是**本帧**的呼吸姿态，而不是上一帧的。
func _update_props() -> void:
	if _anchor_idx < 0 or _prop_idx.is_empty():
		return
	var a := _skel.get_bone_global_pose(_anchor_idx)
	for k in _prop_idx.size():
		var t := Transform3D(a.basis.orthonormalized(), a * _prop_off[k])
		_skel.set_bone_global_pose(_prop_idx[k], t)


## 让守卫看着世界里的某个点。每帧调用一次就行（内部做平滑），
## 一直不调用就保持原来的缓慢巡视 —— 这样「没人来」和「有人来」是两种状态，
## 玩家走近时它会自己转头看过来，比一动不动地朝向虚空自然得多。
func look_at_point(p: Vector3) -> void:
	_look_point = p
	_look_has = true


## 收回视线，回到自顾自的巡视
func look_away() -> void:
	_look_has = false


## 注视权重与目标角。权重走平滑，避免玩家进入半径那一瞬间「啪」地扭头。
func _update_attention(delta: float) -> void:
	_look_w = move_toward(_look_w, 1.0 if _look_has else 0.0, delta * 2.5)
	if not _look_has:
		return
	var local := global_transform.basis.inverse() * (_look_point - global_position)
	var target_yaw := clampf(rad_to_deg(atan2(local.x, local.z)), -look_limit_deg, look_limit_deg)
	# 玩家绕到背后时 clamp 会突然换边，限个角速度让它扭过去而不是瞬移
	_look_yaw = move_toward(_look_yaw, target_yaw, delta * 150.0)


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


## 微动：呼吸（胸腔）、巡视（头颈）、垂手轻摆（上臂）。
##
## 全部打在**上半身骨骼**上，故意不碰骨盆和腿 —— 骨盆一动，脚就会跟着在地上滑，
## 那种「滑冰感」比站着不动更假。脚钉死在地上，这个人才算站得住。
##
## 每帧从基础站姿重算而不是在上一帧上累加，否则浮点误差会慢慢漂移；
## 而 sin 里带多个不同频率，是为了不出现「一看就知道是循环动画」的规律感。
func _process(delta: float) -> void:
	if _skel == null:
		return
	_t += delta

	if not _idle_idx.is_empty():
		for k in _idle_idx.size():
			_skel.set_bone_global_pose(_idle_idx[k], _idle_base[k])

		var t := _t + phase_offset
		var br := sin(t * breath_hz * TAU)
		# 两个不成倍数关系的频率叠加：合成周期 20 秒 × 7 秒，实际不会重复
		var lk := sin(t * look_hz * TAU) + 0.35 * sin(t * look_hz * 2.7 * TAU + 1.1)
		var sw := sin(t * breath_hz * TAU - 0.9)

		_update_attention(delta)
		var yaw := lk * look_deg
		if _look_w > 0.001:
			yaw = lerpf(yaw, _look_yaw, _look_w)

		# 吸气时脊柱略伸（上胸展开），不吸气的时候微微含胸 —— 单摆一个方向会像点头
		_rot_bone("Bip001-Spine1", AX, br * breath_deg)
		_rot_bone("Bip001-Spine2", AX, -br * breath_deg * 0.6)
		# 转头分担到颈和头两节：全压在 Head 上会像戴了个转盘
		_rot_bone("Bip001-Neck", AY, yaw * 0.3)
		_rot_bone("Bip001-Head", AY, yaw * 0.7)
		# 头微微俯仰，视线有个落点；纯左右转会像雷达
		_rot_bone("Bip001-Head", AX, br * 0.8)
		_rot_bone("Bip001-L-UpperArm", AX, sw * sway_deg)
		_rot_bone("Bip001-R-UpperArm", AX, -sw * sway_deg)
		_rot_bone("Bip001-L-Forearm", AX, sw * sway_deg * 0.6)
		_rot_bone("Bip001-R-Forearm", AX, -sw * sway_deg * 0.6)

	_update_props()


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
