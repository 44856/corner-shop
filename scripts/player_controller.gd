extends CharacterBody3D
## 第三人称控制器（移植自 dev 工程的 scripts/player.gd）
##
## 相对原版删掉的：
##   - Dialogue.is_active() 冻结判定（本工程没这个 autoload）
##   - 自动上台阶（toggle_step_up / max_step_height / _probe_step_landing 全套）
##   - restart 输入
## 相对原版新增的：
##   - 输入动作在代码里注册（本任务禁止改 project.godot）
##   - input_locked：开场「躺着醒来」期间不接受输入
##   - 所有节点都用代码建（本工程不在编辑器里摆节点）
##
## 保留的手感设计：
##   - 相机相对移动 + SpringArm3D 贴墙回缩
##   - 跳跃用「高度 + 到顶耗时」表达，上升/下降两套重力
##   - coyote time / jump buffer / 可变跳跃高度
##   - 身体朝向与相机解耦（镜头转人不转，只朝移动方向）

const ActorScript := preload("res://scripts/actor.gd")

@export_group("移动")
## 常规移动速度（米/秒）
@export var walk_speed := 4.2
## 按住 Shift 的冲刺速度
@export var sprint_speed := 7.0
## 地面加速度
@export var acceleration := 40.0
## 空中加速度，低于地面以保留惯性
@export var air_acceleration := 12.0
## 松开按键后的地面减速
@export var friction := 40.0
## 身体转向速度
@export var turn_speed := 14.0

@export_group("跳跃")
## 跳跃最高能到多少米
@export var jump_height := 1.3
## 从起跳到最高点的时间
@export var jump_time_to_peak := 0.38
## 从最高点落到地面的时间
@export var jump_time_to_descent := 0.30
## 离地后仍允许起跳的宽限时间
@export var coyote_time := 0.12
## 落地前提前按跳的缓存时间
@export var jump_buffer_time := 0.14

@export_group("摄像机")
## 鼠标灵敏度
@export var mouse_sensitivity := 0.0025
## 俯仰下限（负值 = 从上方俯视）
@export var pitch_min := -1.05
## 俯仰上限
@export var pitch_max := 0.35
## 相机到角色的距离（米）
@export var cam_distance := 4.2
## 弹簧臂支点相对脚底的高度（米）。开场醒来时会被临时拉低再升回来
@export var cam_height := 1.45
## 启动时锁定鼠标
@export var capture_mouse_on_start := true
## 开场朝向（度）。180 = 相机在角色身后，角色面向 +Z（默认脸朝方向）
@export var start_yaw_deg := 180.0

## 开场期间锁住输入，由 grassland.gd 在醒来补间结束后置 false
var input_locked := true

# 生成出来的节点
var visual: Node3D
var actor: Node3D
var cam_rig: SpringArm3D
var camera: Camera3D

# 由跳跃参数反推的物理量
var _jump_velocity := 0.0
var _rise_gravity := 0.0
var _fall_gravity := 0.0

var _yaw := 0.0
var _pitch := -0.18
var _coyote_left := 0.0
var _buffer_left := 0.0

# 程序化行走动画的步态相位与幅度
var _walk_phase := 0.0
var _walk_amount := 0.0
var _was_airborne := false


func _ready() -> void:
	_ensure_actions()

	# 由「高度 h、到顶耗时 t」反推：g = 2h/t²，初速度 v = g·t
	_rise_gravity = 2.0 * jump_height / pow(jump_time_to_peak, 2.0)
	_fall_gravity = 2.0 * jump_height / pow(jump_time_to_descent, 2.0)
	_jump_velocity = _rise_gravity * jump_time_to_peak

	_yaw = deg_to_rad(start_yaw_deg)

	_build_body()
	_build_camera()

	if capture_mouse_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 键盘动作在代码里注册。只要 project.godot 里已经有了就跳过，
## 这样将来把动作写进工程配置也不会冲突。
func _ensure_actions() -> void:
	for spec in [
		{"name": "move_forward", "keys": [KEY_W, KEY_UP]},
		{"name": "move_backward", "keys": [KEY_S, KEY_DOWN]},
		{"name": "move_left", "keys": [KEY_A, KEY_LEFT]},
		{"name": "move_right", "keys": [KEY_D, KEY_RIGHT]},
		{"name": "jump", "keys": [KEY_SPACE]},
		{"name": "sprint", "keys": [KEY_SHIFT]},
	]:
		if InputMap.has_action(spec["name"]):
			continue
		InputMap.add_action(spec["name"])
		for k in spec["keys"]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(spec["name"], ev)


# ---------------------------------------------------------------- 组装

## 角色结构：本节点（物理）→ Visual（朝向）→ Actor（模型）
## 模型放在 Visual 下面而不是直接当子节点，是为了让「转身」和「物理位移」互不干扰。
func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	# 胶囊总高（含半球）1.72，半径 0.32；原点在脚底，所以形状中心抬到半高
	cap.height = 1.72
	cap.radius = 0.32
	shape.shape = cap
	shape.position = Vector3(0.0, 0.86, 0.0)
	add_child(shape)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	actor = ActorScript.new()
	actor.name = "Actor"
	# 用和场景一完全相同的带贴图三渲二材质。
	# 平涂（use_flat_colors = true）会把五官、布料、头发全部压成色块，
	# 远看就是「低精度」，所以这里必须走贴图版。
	actor.use_flat_colors = false
	# 白天不需要夜景那套压暗冷调：tint 提到接近白，暗部下限抬高
	actor.tint = Color(0.96, 0.96, 0.98)
	actor.shade_floor = 0.58
	actor.rim_strength = 0.08
	actor.outline_width = 0.005
	actor.pose = "stand"
	actor.face_yaw_deg = 0.0          # 模型脸朝 +Z，与朝向解算一致，不要加 180°
	actor.dash_delay = -1.0           # 不自动冲刺（那是雨夜场景的演出）
	visual.add_child(actor)


func _build_camera() -> void:
	cam_rig = SpringArm3D.new()
	cam_rig.name = "CamRig"
	cam_rig.position = Vector3(0.0, cam_height, 0.0)
	cam_rig.spring_length = cam_distance
	cam_rig.margin = 0.12
	add_child(cam_rig)
	# 不排除自己的话，弹簧臂会撞到角色胶囊把镜头顶飞
	cam_rig.add_excluded_object(get_rid())

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.0, cam_distance)
	camera.fov = 52.0
	camera.near = 0.05
	# 视距 2500m：城镇地面在 300~560m，远景地面铺到 ±2000m，
	# 800 会在 800m 处硬切一刀，把地面裁成天花板。雾在 2000m 处只剩一成，
	# 所以这个距离不是浪费 —— 它保证「裁掉的地方」永远在看不见的地方
	camera.far = 2500.0
	cam_rig.add_child(camera)
	camera.current = true

	_apply_camera()


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	# 醒来期间连视角也不给转，否则会把开场镜头带偏
	if input_locked:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			_yaw -= motion.relative.x * mouse_sensitivity
			_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, pitch_min, pitch_max)
			_apply_camera()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- 物理

func _physics_process(delta: float) -> void:
	# 醒来期间：清掉操作意图，但保留重力与贴地
	# （不要用 set_physics_process(false)，否则角色会卡在半空）
	if input_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= (_rise_gravity if velocity.y > 0.0 else _fall_gravity) * delta
		move_and_slide()
		return

	_update_timers(delta)

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var wish_dir := _wish_direction()

	_apply_horizontal(delta, wish_dir, speed)
	_apply_vertical(delta)
	_apply_facing(delta, wish_dir)

	move_and_slide()
	_update_locomotion(delta)


## 驱动程序化行走动画。
## 模型（gaia.glb）不带任何动画剪辑，走路的摆臂摆腿全靠这里推骨骼。
## 相位按「水平速度 × 时间」推进，所以走快走慢步频自动不同，不需要额外参数。
func _update_locomotion(delta: float) -> void:
	if actor == null:
		return

	if not is_on_floor():
		# 空中：收腿姿势。只在刚离地时更新一次，避免每帧覆盖
		if not _was_airborne:
			_was_airborne = true
			visual.position.y = 0.0    # 把地面行走的起伏归零，否则会悬着
			if actor.has_method("set_air_pose"):
				actor.set_air_pose()
		return
	_was_airborne = false

	var hspeed := Vector2(velocity.x, velocity.z).length()
	# 冲刺时幅度封顶在 1.0，腿摆得过大会穿模
	var target := clampf(hspeed / walk_speed, 0.0, 1.0)
	_walk_amount = lerpf(_walk_amount, target, 1.0 - exp(-9.0 * delta))
	_walk_phase += hspeed * 2.1 * delta

	if actor.has_method("set_locomotion"):
		actor.set_locomotion(_walk_phase, _walk_amount)

	# 髋部下沉补偿。
	# 大腿绕髋摆成圆弧，摆到 28° 时脚会被抬高 L(1−cosθ) ≈ 0.10m，
	# 于是支撑腿的脚浮在空中、影子和鞋分离。没有 IK，只能用髋部下沉来抵。
	# 0.85 是腿长；0.72 是经验系数 —— 补满会显得像在蹲着走。
	# 这个补偿本身就是上下起伏：腿摆得越开身体越低，每步一次。
	var leg_angle := 0.50 * _walk_amount * sin(_walk_phase)
	visual.position.y = -0.85 * (1.0 - cos(leg_angle)) * 0.72


## 把 WASD 按相机朝向映射到世界方向
func _wish_direction() -> Vector3:
	var input_vec := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	if input_vec == Vector2.ZERO:
		return Vector3.ZERO

	var cam_forward := -cam_rig.global_transform.basis.z
	var forward := Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)

	return (right * input_vec.x + forward * input_vec.y).normalized()


func _apply_horizontal(delta: float, wish_dir: Vector3, speed: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		if is_on_floor():
			horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	else:
		var accel := acceleration if is_on_floor() else air_acceleration
		horizontal = horizontal.move_toward(wish_dir * speed, accel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_vertical(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -0.1   # 轻微下压，避免贴合抖动
	else:
		velocity.y -= (_rise_gravity if velocity.y > 0.0 else _fall_gravity) * delta

	if _coyote_left > 0.0 and _buffer_left > 0.0:
		velocity.y = _jump_velocity
		_coyote_left = 0.0
		_buffer_left = 0.0
	elif velocity.y > 0.0 and not Input.is_action_pressed("jump"):
		# 松手就削峰 —— 可变跳跃高度
		velocity.y = lerpf(velocity.y, 0.0, minf(1.0, 12.0 * delta))


## 只转水平朝向。模型脸朝 +Z，所以 atan2(x, z) 就是「让 +Z 指向移动方向」
func _apply_facing(delta: float, wish_dir: Vector3) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var target := atan2(wish_dir.x, wish_dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target, 1.0 - exp(-turn_speed * delta))


func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)

	if Input.is_action_just_pressed("jump"):
		_buffer_left = jump_buffer_time
	else:
		_buffer_left = maxf(0.0, _buffer_left - delta)


func _apply_camera() -> void:
	# Node3D 默认欧拉序 YXZ：先偏航再俯仰，正是第一/三人称需要的
	cam_rig.rotation = Vector3(_pitch, _yaw, 0.0)
