extends Node3D
## 马路车祸事件：进过店之后走下马路 → 右侧驶来一辆大货车。
##
## 为什么单独一个节点，而不是塞进 store_walk.gd：
##   它自带一套状态机（等触发 → 预警 → 冲刺 → 撞击 → 黑场 → 复位），
##   store_walk 只负责两件事：把「进过店」这个前置条件告诉它、给它 player / hud。
##
## 两处设计取舍：
##   1. **车是纯视觉体，不带碰撞**。真让它推 CharacterBody3D，高速下会把人挤进
##      底座或者卡在车底；撞击感交给「击飞 + 镜头抖 + 白闪 + 黑场」四件套，
##      手感更稳，也不会因为改物理参数影响别的场景。
##   2. **超出台面的部分不渲染**（见 toon.gdshader 的 clip_*）。
##      车从台面外 9m 处出发，靠裁剪「从画面边缘长出来」，
##      而不是凭空出现在底座上。

const Truck := preload("res://scripts/truck.gd")
const Sfx := preload("res://scripts/sfx.gd")

enum State { IDLE, BEAT, RUN, DONE }

## 从哪一侧驶入：−1 = 屏幕右侧（西），+1 = 屏幕左侧。改符号就能换边
const SIDE := -1.0
## 车速（米/秒），13 ≈ 47km/h —— 城里夜路，够撞飞人，又看得清车
const SPEED := 13.0
## 出场点离台面边缘的距离（米）
const SPAWN_GAP := 9.0
## 车道 z 的取值范围：再往北会蹭到路口的锥桶，再往南会压到台面边缘
const LANE_MIN := 3.05
const LANE_MAX := 4.55
## 台面半宽（与 street.gd 的 B 一致）
const B := 5.6
## 触发线：要走到马路中间才出事，不是刚踩下路缘就撞。
## 路面从 z 2.07（路缘石外沿）到 5.6（台面边缘），中线 3.83；
## 取 3.7 —— 站在路中间一定已经触发，贴着路缘走不会被点名。
const TRIGGER_Z := 3.7
## 撞上之前多远开始收时间（慢镜头）
const SLOWMO_GAP := 4.5
const SLOWMO_SCALE := 0.35

## 撞完之后人物被放回的位置：就是出生点。
## 不放回马路牙子上 —— 那里离店面只有 2m，弹簧臂会直接顶进店里，
## 一睁眼就是俯拍天灵盖。回到出生点，镜头朝向和开场完全一致。
const RESPAWN := Vector3(0.35, 0.17, 0.95)

var _state := State.IDLE
var _player: CharacterBody3D
var _hud                        # hud.gd（动态调用，不加类型）
var _truck                      # truck.gd
var _travel := 1.0              # 行驶方向（+1 = 朝 +X）
var _lane := 3.6                # 车道中心 z
var _t := 0.0
var _wheel_angle := 0.0
var _hit_done := false
var _slowmo := false
var _store_visited := false

## 截图 / 测试用：关掉自动触发，手动调 fire()
var auto_trigger := true


func bind(player: CharacterBody3D, hud: Node) -> void:
	_player = player
	_hud = hud


## store_walk 在人物第一次进店时调用。没进过店就不会触发 —— 这是任务要求的前置条件。
func notify_store_entered() -> void:
	_store_visited = true


func has_fired() -> bool:
	return _state != State.IDLE


func is_done() -> bool:
	return _state == State.DONE


func _exit_tree() -> void:
	# 兜底：慢镜头期间场景被切走，别把全局时间留在 0.35 倍
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			_watch()
		State.BEAT:
			_t += delta
			if _t >= 0.42:
				_spawn()
		State.RUN:
			_tick_run(delta)


## 等人走到马路中间（不是刚踏下路缘）
func _watch() -> void:
	if not auto_trigger or not _store_visited:
		return
	if _player == null or not is_instance_valid(_player):
		return
	# 开场推镜 / 别的演出期间不抢戏
	if _player.input_locked:
		return
	var p: Vector3 = _player.global_position
	if p.z > TRIGGER_Z and p.z < B - 0.15 and absf(p.x) < B - 0.15:
		fire()


# ---------------------------------------------------------------- 事件

## 开始演出。测试与截图模式可以直接调，跳过「进过店」的前置条件。
func fire() -> void:
	if _state != State.IDLE:
		return
	_state = State.BEAT
	_t = 0.0
	_hit_done = false
	_travel = -SIDE

	if _player != null:
		_player.input_locked = true
		# 车冲着人来：车道取人物所在的 z，夹在能开得下的范围里
		_lane = clampf(_player.global_position.z, LANE_MIN, LANE_MAX)

	if _hud != null:
		_hud.hide_prompt()

	# 喇叭先从画面外传过来，车再露头
	_play(Vector3(SIDE * (B + 1.2), 1.5, _lane), Sfx.horn(), 2.0, 60.0)


func _spawn() -> void:
	_truck = Truck.new()
	_truck.name = "Truck"
	_truck.position = Vector3(SIDE * (B + SPAWN_GAP + Truck.L * 0.5), 0.0, _lane)
	# 车头朝行驶方向：模型默认朝 +X，往 −X 开就整体转 180°
	_truck.rotation.y = 0.0 if _travel > 0.0 else PI
	add_child(_truck)
	_state = State.RUN
	_t = 0.0


func _tick_run(delta: float) -> void:
	if _truck == null or not is_instance_valid(_truck) \
			or _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return

	var dist := SPEED * delta
	_truck.position.x += _travel * dist
	_wheel_angle += dist / Truck.WHEEL_R
	_truck.spin(_wheel_angle)
	_t += delta

	# 车头离人还有 4.5m 时收时间：这一下是整段演出的重音
	if not _slowmo and not _hit_done:
		if _gap_to_player() < SLOWMO_GAP:
			_slowmo = true
			Engine.time_scale = SLOWMO_SCALE

	if not _hit_done:
		_check_hit()

	# 车开出台面另一侧就回收（此时它已经被着色器裁没了）
	if _travel * _truck.position.x > B + SPAWN_GAP + Truck.L:
		_truck.queue_free()
		_truck = null
		_state = State.DONE


## 车头到人物的距离（沿行驶方向，负值表示已经越过去了）
func _gap_to_player() -> float:
	var dx: float = _travel * (_player.global_position.x - _truck.position.x)
	return dx - Truck.L * 0.5


func _check_hit() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dx: float = _travel * (_player.global_position.x - _truck.position.x)
	var dz: float = absf(_player.global_position.z - _truck.position.z)
	# 车头碰到胶囊（半径 0.32）+ 一点余量；横向按车宽算
	if dx < Truck.L * 0.5 + 0.18 and dz < Truck.W * 0.5 + 0.30:
		_on_hit()


func _on_hit() -> void:
	_hit_done = true
	Engine.time_scale = 1.0
	_slowmo = false

	if _truck != null:
		_truck.set_brake(true)

	var hit_pos: Vector3 = _player.global_position
	# 侧向击飞：被车头右侧带一下，往路缘那边翻出去。
	# 不往车头正前方扔 —— 车还在往前开，人会一直被车头追着跑。
	if _player.has_method("knock"):
		_player.knock(Vector3(_travel * 3.6, 6.5, -2.8))
	if _player.has_method("add_shake"):
		_player.add_shake(0.11, 0.9)

	_play(hit_pos, Sfx.impact(), 6.0, 40.0)
	if _hud != null:
		_hud.hide_toast()
		_hud.flash(Color(1.0, 0.97, 0.92, 0.85), 0.24)

	# 撞完立刻收黑：车会从镜头上碾过去，再留 0.3 秒就只能看到一整块车皮，
	# 像镜头钻进车里。白闪 → 黑场这一下比「看自己被撞飞」更干脆。
	await get_tree().create_timer(0.10).timeout
	if _hud != null:
		_hud.fade_out(0.22)
	await get_tree().create_timer(0.95).timeout
	_respawn()
	if _hud != null:
		_hud.fade_in(1.4)
		_hud.toast("……雨还在下。马路上什么也没有。", 4.5)


## 黑场里把人放回路缘：位置、朝向、速度、击飞状态全部复位
func _respawn() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.global_position = RESPAWN
	_player.face(PI)           # 面朝店面，和开场同一个站位
	if _player.has_method("set_view"):
		_player.set_view(0.0, -0.12)
	if _player.has_method("reset_motion"):
		_player.reset_motion()


# ---------------------------------------------------------------- 工具

func _play(pos: Vector3, stream: AudioStream, db: float = 0.0, max_dist: float = 40.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.volume_db = db
	p.unit_size = 8.0
	p.max_distance = max_dist
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- 截图 / 调试

## 把车直接摆到指定位置（不跑状态机），用来拍裁剪效果
func debug_show(x: float, z: float, brake: bool = false) -> void:
	if _truck == null or not is_instance_valid(_truck):
		_truck = Truck.new()
		_truck.name = "Truck"
		add_child(_truck)
		_truck.rotation.y = 0.0
	_truck.position = Vector3(x, 0.0, z)
	_truck.set_brake(brake)


func debug_hide() -> void:
	if _truck != null and is_instance_valid(_truck):
		_truck.queue_free()
		_truck = null
