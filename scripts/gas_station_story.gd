extends Node3D
## 加油站剧情：三颗子弹 → 逢魔时 → 撞击 → 死亡 → 转场。
##
## 设计原则是「自然 = 因果链 × 代价 × 阈值」，所以这里没有任务列表：
##   1. 收音机先说「深夜货运高峰」和「白色厢式货车刚驶出服务区」；
##   2. 玩家第一次踏进国道时，一辆轻自动车擦身而过，制造「我反应很快」的错觉；
##   3. 东侧停着一辆厢式货车，司机说「最后一趟，跑完就收车」。
## 三件事凑齐，时间才跳到逢魔时。撞车不是开关，是这三条因果的收束。
##
## 状态机只做一件事：决定「现在允许发生什么」。演出细节放在
## story_veil.gd（画面）和 gas_station.gd（现有场景）里，互不缠绕。
##
## 为什么停在路边的货车用 truck.gd，而不是另写一台：
## 它的材质全部走 clip_* 裁剪，gas 场景的 30×18m 台面只要换一个 AABB 就能复用；
## 另写一份迟早会和商店街那台车在比例 / 灯位上演化出两个版本。

const K := preload("res://scripts/kit.gd")
const Props := preload("res://scripts/props.gd")
const Truck := preload("res://scripts/truck.gd")
const PlayerController := preload("res://scripts/player_controller.gd")
const CollisionLayout := preload("res://scripts/collision_layout.gd")
const StoryVeil := preload("res://scripts/story_veil.gd")
const Sfx := preload("res://scripts/sfx.gd")

## 裁剪盒要罩住整条国道：车从 x = −9 开进来，默认的 11.2m 底座会把它整块 discard。
const STATION_CLIP := AABB(Vector3(-45.0, -6.0, -24.0), Vector3(110.0, 44.0, 70.0))

## 柜台窗外的收音机 / 东侧货车旁的司机
const RADIO_TARGET := Vector3(7.06, 1.12, 10.55)
const DRIVER_TARGET := Vector3(22.70, 1.12, 6.60)
const DRIVER_POS := Vector3(22.70, 0.16, 6.60)
const PARKED_TRUCK_POS := Vector3(25.40, 0.16, 8.40)

## 逢魔时之后、玩家第一次上路之前的缓冲。第三颗子弹可能就把人钉在国道上，
## 不缓冲的话，黑幕一淡出车就来了，连「天怎么变了」都来不及看。
const DUSK_GRACE := 3.4

## 角色躯干前缘到脚底中心的实测距离（gaia.glb 站立姿态，按高度切片量得
## 胸口 0.146m、髋部 0.174m）。胶囊半径 0.32m 是按物理形状算的，
## 比真人宽出一截；按胶囊表面留间隙，驾驶室会停在胸口外约 0.4m，像没撞上。
const ACTOR_FRONT := 0.17
## 撞车接触距离 = 驾驶室前脸 + 躯干前缘 + 可见间隙。
## 用 CAB_X1 而不是 FRONT_X（保险杠/雾灯最外沿）：那些件在 0.6m 高，
## 拿它们当接触面会让胸前的驾驶室退到 0.4m 外。按现在这组值，
## 大灯离髋部只剩几厘米，低处的保险杠会压进膝盖一点 ——
## 那一截在肩后机位里被身体挡住，且白闪紧接着就盖上，看不到穿模。
const CONTACT_GAP := Truck.CAB_X1 + ACTOR_FRONT + 0.10
## 撞击前的车速。140km/h ≈ 38.9m/s：26m 出场距离的正常段只跑约 0.5s，
## 进慢镜头后再约 0.3s 撞上 —— 车灯一亮就到眼前，不给反应时间。
const CRASH_SPEED := 140.0 / 3.6

enum Phase { WALK, DUSK, CRASH, DEATH, DONE }

var scene
var player
var hud
var hub
var env: Environment
var moon: DirectionalLight3D
var fill: DirectionalLight3D

## 测试用加速倍数：把每一段等待按比例缩短；StoryVeil 的字幕补间也跟着缩。
var speed := 1.0
## 探针里关掉，避免真的切场景。
var transition_enabled := true
## 截图模式关掉触发，只保留道具。
var enabled := true

var _phase := Phase.WALK
var _radio_heard := false
var _near_miss_done := false
var _driver_talked := false
var _crash_started := false
var _death_started := false
var _finished := false
var _stopped := false
var _dusk_done := false

var _props: Node3D
var _radio_audio: AudioStreamPlayer3D
var _parked_truck: Node3D
var _parked_body: StaticBody3D
var _driver: Node3D
var _near_van: Node3D
var _near_whoosh := false
var _crash_truck: Node3D
var _crash_hit := false
var _wheel_angle := 0.0
var _slowmo := false
var _impact_clearance := INF
var _horn_near := false
var _headlight_halo: Node3D
var _veil
var _tinnitus: AudioStreamPlayer
var _dusk_grace := DUSK_GRACE
var _dusk_hint_t := 0.0
var _dusk_hint_shown := false
var _dusk_pending := false


func bind(host: Node3D) -> void:
	scene = host
	player = host.get("player") as CharacterBody3D
	hud = host.get("hud") as CanvasLayer
	hub = host.get("hub") as Node
	env = host.get("env") as Environment
	moon = host.get("moon") as DirectionalLight3D
	fill = host.get("fill") as DirectionalLight3D


func _ready() -> void:
	_props = Node3D.new()
	_props.name = "StoryProps"
	add_child(_props)
	_build_radio()
	_build_parked_truck()
	_build_driver()
	_add_targets()
	_intro_hint()


func _exit_tree() -> void:
	# 慢动作是全局状态。场景被释放 / 转场打断时必须还原，
	# 不然下一场（草原）会以 0.35 倍速醒来。
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0


# ---------------------------------------------------------------- 对外查询
#
# probe 只准读这些方法。内部用 enum 还是字符串是私有决定，
# 不要让测试文件去读 _phase。

func phase() -> String:
	return ["walk", "dusk", "crash", "death", "done"][_phase]


func beat_count() -> int:
	return int(_radio_heard) + int(_near_miss_done) + int(_driver_talked)


func radio_heard() -> bool:
	return _radio_heard


func near_miss_done() -> bool:
	return _near_miss_done


func driver_talked() -> bool:
	return _driver_talked


func crash_started() -> bool:
	return _crash_started


## 撞击那一帧，驾驶室前脸到角色躯干前缘的可见间隙（米）。
## 负数 = 前脸已经切进躯干。按设计应保持在 0.10m 左右。
func impact_clearance() -> float:
	return _impact_clearance


func death_started() -> bool:
	return _death_started


func finished() -> bool:
	return _finished


## 逢魔时把东侧那台货车和司机一起撤掉；测试用来确认「最后一张完整画面」真的变了。
func parked_cleared() -> bool:
	return _parked_truck == null and _driver == null


## 逢魔时之后就不该再回商店街了：旧世界线已经收束。
## 三颗子弹之前随便走 —— 玩家选择离开，故事下次再开始。
func return_allowed() -> bool:
	return _phase == Phase.WALK


func blocks_return() -> bool:
	return _phase != Phase.WALK


## 死亡段由剧情自己接管雨声 / 环境声，gas_station 的 _process 不要再往回拉。
func audio_override() -> bool:
	return _phase == Phase.DEATH or _phase == Phase.DONE


func set_speed(value: float) -> void:
	speed = maxf(0.01, value)


func set_transition_enabled(on: bool) -> void:
	transition_enabled = on


## 截图 / 调试用：停在 WALK 或直接摆出逢魔时的光。
func stage_for_shot() -> void:
	enabled = false
	apply_dusk(true)
	_clear_parked()
	hud.set_subtitle("逢魔时 18:42　国道 17 号")
	hud.fade_in(0.0)


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if _stopped:
		return

	_step_near_van(delta)
	if not enabled:
		return

	match _phase:
		Phase.WALK:
			_watch_near_miss()
		Phase.DUSK:
			_tick_dusk(delta)
		Phase.CRASH:
			_step_crash(delta)


# ---------------------------------------------------------------- 三颗子弹

func _add_targets() -> void:
	if hub == null:
		return
	# 收音机在柜台窗台上（z=10.55）：往南 0.95m 是「敲敲柜台」，
	# 往东北 1.14m 是自动售货机。只比距离的话，玩家走到柜台前
	# 永远先弹日常交互，剧情目标反而按不到。priority=1 让它在
	# 未被听过时压过日常交互；听过之后 gate 关闭，自动让位。
	hub.add_target(RADIO_TARGET, 1.65, "听柜台里的收音机", _on_radio,
		func() -> bool: return enabled and not _radio_heard and _phase == Phase.WALK, 1)
	hub.add_target(DRIVER_TARGET, 1.75, "和司机说句话", _on_driver,
		func() -> bool: return enabled and not _driver_talked and _phase == Phase.WALK)


func _on_radio() -> void:
	if _radio_heard or _phase != Phase.WALK:
		return
	_radio_heard = true
	if _radio_audio != null:
		_radio_audio.volume_db = -6.0
	_play_at(RADIO_TARGET, Sfx.radio(), -4.0)
	hud.toast("……国道 17 号，深夜货运高峰。一辆白色厢式货车刚从星见町服务区驶出，"
		+ "请行人注意来车。……", 5.6)
	_after_beat(3.2)


func _on_driver() -> void:
	if _driver_talked or _phase != Phase.WALK:
		return
	_driver_talked = true
	_play_at(DRIVER_POS + Vector3(0.0, 1.0, 0.0), Sfx.tap(), -8.0)
	hud.toast("司机打了个哈欠。'最后一趟。跑完这趟就收车。' "
		+ "他看了眼国道，又看了眼手表。", 5.2)
	_after_beat(3.6)


## 三颗子弹可以任意顺序完成。最后一颗需要留一点时间把文案读完，
## 所以由「最后一颗」自己排逢魔时，而不是每颗都去抢。
func _after_beat(delay: float) -> void:
	if beat_count() < 3:
		return
	if _dusk_pending:
		return
	_dusk_pending = true
	var ok := await _wait(delay)
	# 擦身车还在路上就再等一会儿：变天的黑幕不能把它盖掉，
	# 否则第三颗子弹的「躲开了」会变成一句没有画面的文案。
	while ok and _near_van != null:
		ok = await _wait(0.2)
	if ok:
		_check_dusk()


func _watch_near_miss() -> void:
	if _near_miss_done or _near_van != null:
		return
	if scene == null or scene.zone() != "road":
		return
	_near_miss_done = true
	_launch_near_van()


## 擦身而过的车走玩家旁边那条「空车道」：站在路南半就贴着北侧过，
## 反之亦然。它不碰碰撞盒 —— 这是一次「成功躲开」，碰到就成事故了。
func _launch_near_van() -> void:
	var p: Vector3 = player.global_position
	var side := 1.0 if p.z < 2.0 else -1.0
	var lane_z := clampf(p.z + side * 1.28, 0.58, 3.42)
	var start_x := maxf(-6.0, p.x - 13.0)

	_near_van = Node3D.new()
	_near_van.name = "NearMissVan"
	_near_van.position = Vector3(start_x, 0.02, lane_z)
	add_child(_near_van)
	# kei_van 的正面朝 +Z；转 90° 之后正面朝 +X，和国道车流同向。
	Props.kei_van(_near_van, Vector3.ZERO, 90.0)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffe0b0")
	lamp.light_energy = 1.6
	lamp.omni_range = 4.5
	lamp.omni_attenuation = 1.8
	lamp.position = Vector3(1.35, 0.75, 0.0)
	_near_van.add_child(lamp)

	_near_whoosh = false
	hud.toast("一辆轻自动车贴着肩膀过去。你退了半步——反应比你想象得快。", 4.2)


func _step_near_van(delta: float) -> void:
	if _near_van == null:
		return
	_near_van.position.x += 13.0 * delta
	var dx: float = _near_van.position.x - player.global_position.x
	if not _near_whoosh and absf(dx) < 3.4:
		_near_whoosh = true
		_play_at(_near_van.global_position + Vector3(0.0, 0.6, 0.0), Sfx.whoosh(), -1.0)
		player.add_shake(0.20, 0.45)
	if _near_van.position.x > 35.0:
		_near_van.queue_free()
		_near_van = null
		# 如果这是第三颗子弹，等车真的开过去再变天。
		_after_beat(1.0)


func _check_dusk() -> void:
	if _phase != Phase.WALK or beat_count() < 3:
		return
	_begin_dusk()


# ---------------------------------------------------------------- 逢魔时

func _begin_dusk() -> void:
	if _phase != Phase.WALK:
		return
	_phase = Phase.DUSK
	# 从这一刻起「回商店街」整条出口作废。交给路由表判断，
	# 而不是让每个触发点各自去问 story.return_allowed()——漏问一次就会穿帮。
	GameState.set_story_node(&"ep2_dusk")
	_dusk_pending = true
	hub.enabled = false
	player.input_locked = true
	hud.hide_prompt()
	hud.hide_toast()

	# 先黑半秒再改天光：直接 tween 天空会读成「调色盘」，黑一下才像眨眼。
	hud.fade_out(0.45)
	var ok := await _wait(0.55)
	if not ok:
		return
	apply_dusk(false)
	_clear_parked()
	hud.set_subtitle("逢魔时 18:42　国道 17 号")

	var ok2 := await _wait(0.35)
	if not ok2:
		return
	hud.fade_in(1.5)
	var ok3 := await _wait(1.7)
	if not ok3:
		return

	_dusk_done = true
	_dusk_grace = DUSK_GRACE
	player.input_locked = false
	hub.enabled = true
	hud.toast("你看了一眼手表。18:42。东侧停货车的位置空了。", 5.4)


## 天光一次性推过去。为什么不用补间把每一帧都写进状态机：
## 这段只发生一次，tween 的插值比手写 lerp 更稳，也不会和 WorldEnv 抢参数。
func apply_dusk(instant: bool) -> void:
	var dur := 0.01 if instant else 2.6
	var sky_mat: ProceduralSkyMaterial = null
	if env.sky != null:
		sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	var tw := create_tween().set_parallel(true) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(env, "fog_light_color", Color("#6a3d31"), dur)
	tw.tween_property(env, "fog_light_energy", 0.72, dur)
	tw.tween_property(env, "fog_density", 0.019, dur)
	tw.tween_property(env, "volumetric_fog_density", 0.012, dur)
	tw.tween_property(env, "volumetric_fog_albedo", Color(0.72, 0.58, 0.52), dur)
	tw.tween_property(env, "ambient_light_energy", 0.30, dur)
	tw.tween_property(env, "adjustment_saturation", 1.34, dur)
	if sky_mat != null:
		tw.tween_property(sky_mat, "sky_top_color", Color("#241b33"), dur)
		tw.tween_property(sky_mat, "sky_horizon_color", Color("#c46a42"), dur)
		tw.tween_property(sky_mat, "ground_horizon_color", Color("#6e4436"), dur)
		tw.tween_property(sky_mat, "ground_bottom_color", Color("#1a1316"), dur)
	if moon != null:
		tw.tween_property(moon, "light_color", Color("#ffb27c"), dur)
		tw.tween_property(moon, "light_energy", 0.42, dur)
		tw.tween_property(moon, "rotation_degrees", Vector3(-24.0, -74.0, 0.0), dur)
	if fill != null:
		tw.tween_property(fill, "light_color", Color("#7a4a5e"), dur)
		tw.tween_property(fill, "light_energy", 0.24, dur)

	# 雨不关，只收一档。逢魔时最后的完整画面里，雨是最重要的那层运动。
	var rain := scene.get_node_or_null("Rain") as GPUParticles3D
	if rain != null:
		rain.amount = 2500

	_build_distant_headlights()


## 西边路上的两盏车灯。它不是那台肇事车，只是「路还醒着」的证据；
## 等真正的车灯从同一个方向亮起来，玩家会先想起这两点光。
func _build_distant_headlights() -> void:
	if _headlight_halo != null:
		return
	_headlight_halo = Node3D.new()
	_headlight_halo.name = "DistantHeadlights"
	_headlight_halo.position = Vector3(-5.6, 0.0, 2.0)
	add_child(_headlight_halo)
	for z in [-0.62, 0.62]:
		K.sphere(_headlight_halo, 0.10, Vector3(0.0, 0.86, z),
			K.glow(Color("#ffe3b8"), 3.2), Vector3.ZERO, 10, 1.0, false)
		K.sphere(_headlight_halo, 0.42, Vector3(0.0, 0.86, z),
			K.soft(Color("#ffbe80"), 0.36, 1.8), Vector3.ZERO, 12, 0.9, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffcf9a")
	l.light_energy = 1.1
	l.omni_range = 8.0
	l.omni_attenuation = 1.8
	l.position = Vector3(0.0, 0.7, 0.0)
	_headlight_halo.add_child(l)


func _tick_dusk(delta: float) -> void:
	if not _dusk_done:
		return
	_dusk_grace = maxf(0.0, _dusk_grace - delta)
	if _dusk_grace > 0.0:
		return
	if scene != null and scene.zone() == "road":
		trigger_crash()
		return
	_dusk_hint_t += delta
	if not _dusk_hint_shown and _dusk_hint_t > 10.0:
		_dusk_hint_shown = true
		hud.toast("商店街在国道对面。你把塑料袋换到左手，往斑马线走。", 4.8)


# ---------------------------------------------------------------- 碰撞

## 进入国道之后才撞：撞车是「穿过这条线」的代价，不是随机事件。
## 测试也走这个公开入口，避免 probe 去调私有状态。
func trigger_crash() -> void:
	if _phase != Phase.DUSK or _crash_started or _stopped:
		return
	_crash_started = true
	_phase = Phase.CRASH
	_crash_hit = false
	_slowmo = false
	_horn_near = false
	_wheel_angle = 0.0
	_impact_clearance = INF
	Engine.time_scale = 1.0
	player.input_locked = true
	hub.enabled = false
	hud.hide_prompt()
	hud.hide_toast()
	if _headlight_halo != null:
		_headlight_halo.queue_free()
		_headlight_halo = null

	# 车从西边来。出生点在玩家西侧 26m，最多从场地外 9m 处进画。
	var start_x := maxf(-9.0, player.global_position.x - 26.0)
	var lane_z := clampf(player.global_position.z, 1.0, 3.0)
	_crash_truck = Truck.new()
	_crash_truck.name = "CrashTruck"
	_crash_truck.clip_box = STATION_CLIP
	_crash_truck.position = Vector3(start_x, 0.0, lane_z)
	add_child(_crash_truck)

	# 把镜头和身体一起硬掰向西：玩家没有选择，只能看着灯过来。
	# 脚下也不给动 —— 触发瞬间就锁死，这段演出里没有任何可操作的空隙。
	var d: Vector3 = _crash_truck.global_position - player.global_position
	player.set_view(rad_to_deg(atan2(-d.x, -d.z)), -0.06)
	player.face(atan2(d.x, d.z))
	_horn_at_truck(2.0)


func _step_crash(delta: float) -> void:
	if _crash_truck == null or _crash_hit:
		return
	var p: Vector3 = player.global_position
	var truck_z: float = _crash_truck.position.z
	var gap: float = p.x - _crash_truck.position.x

	# 6m 处进慢动作。时间只慢一次，撞上的那一帧就还回 1.0，
	# 否则击飞会像在水里飘。
	if not _slowmo and gap < 6.5:
		_slowmo = true
		Engine.time_scale = 0.35
		player.add_shake(0.14, 1.6)
	if not _horn_near and gap < 12.0:
		_horn_near = true
		_horn_at_truck(5.0)

	# 车道跟着玩家偏。玩家已经锁输入，这一步是视觉上的「它不打算让」，
	# 和前面轻自动车「擦身而过」形成同一套因果。
	truck_z = move_toward(truck_z, clampf(p.z, 0.9, 3.1), 2.4 * delta)
	_crash_truck.position.z = truck_z
	_crash_truck.position.x += CRASH_SPEED * delta
	_wheel_angle += CRASH_SPEED * delta / Truck.WHEEL_R
	_crash_truck.spin(_wheel_angle)

	var gap_now := p.x - _crash_truck.position.x
	var side_gap := absf(p.z - _crash_truck.position.z)
	var lateral_limit := Truck.W * 0.5 + PlayerController.BODY_RADIUS
	if gap_now <= CONTACT_GAP and side_gap <= lateral_limit:
		# 低帧率下这一帧可能一步跨过接触点。把车夹回到车头刚好贴住胶囊的位置：
		# 宁可少走几厘米，也不能让保险杠插进身体。
		_crash_truck.position.x = p.x - CONTACT_GAP
		_on_crash_hit()


func _horn_at_truck(db: float) -> void:
	if _crash_truck == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = Sfx.horn()
	a.position = Vector3(2.6, 1.0, 0.0)
	a.volume_db = db
	a.unit_size = 6.0
	a.max_distance = 120.0
	_crash_truck.add_child(a)
	a.finished.connect(a.queue_free)
	a.play()


# ---------------------------------------------------------------- 死亡三层

func _on_crash_hit() -> void:
	_crash_hit = true
	_phase = Phase.DEATH
	_death_started = true
	Engine.time_scale = 1.0
	if _crash_truck != null:
		var front_x: float = _crash_truck.global_position.x + Truck.CAB_X1
		_impact_clearance = (player.global_position.x - ACTOR_FRONT) - front_x
		_crash_truck.set_brake(true)
	player.knock(Vector3(7.6, 3.2, randf_range(-0.55, 0.55)), 1.1)
	player.add_shake(0.48, 0.65)
	hud.flash(Color(1.0, 0.97, 0.9, 0.96), 0.10)
	_play_at(player.global_position + Vector3(0.0, 0.8, 0.0), Sfx.impact(), 6.0)
	_play_at(player.global_position + Vector3(0.0, 0.8, 0.0), Sfx.static_noise(), -1.0)
	_start_veil()
	_death_sequence()


func _start_veil() -> void:
	_veil = StoryVeil.new()
	_veil.name = "StoryVeil"
	_veil.speed = speed
	add_child(_veil)
	_veil.visible = true
	_veil.set_veil({
		"alpha": 0.0, "desat": 0.0, "block_amount": 0.0,
		"noise_amount": 0.0, "vignette": 0.0, "blackout": 0.0,
	})
	_veil.fade_alpha(1.0, 0.18)
	_veil.fade_param("desat", 0.52, 0.45)
	_veil.fade_param("block_amount", 0.20, 0.45)
	_veil.fade_param("noise_amount", 0.055, 0.45)
	_veil.fade_param("vignette", 0.42, 0.45)


## 视觉 → 听觉 → 触觉。
## 视觉先退（去色 + 撕裂 + 黑场），听觉随后（雨声 / 耳鸣），
## 触觉最后（操作从撞车前就锁着，始终没有交还）。
## 中间留给玩家一次「伸手」—— 那是演出提示，不是移动输入。
func _death_sequence() -> void:
	var ok := await _wait(0.95)
	if not ok:
		return

	_veil.fade_param("desat", 0.92, 1.2)
	_veil.fade_param("block_amount", 0.48, 1.2)
	_veil.fade_param("noise_amount", 0.11, 1.2)

	var ok2 := await _wait(1.9)
	if not ok2:
		return

	if player != null:
		player.reset_motion()
		# reset_motion 会解锁输入；死亡演出后半段仍然不给操作。
		player.input_locked = true
		# 撞飞落地后保持站立，不再切死亡躺姿；镜头也留在肩后视角，
		# 不给「从上面看见自己躺在地上」的机位。
		# 击飞时切过空中姿势，这里要把腿放下来，否则会一直保持收腿的蹲姿。
		if player.actor != null and player.actor.has_method("set_locomotion"):
			player.actor.set_locomotion(0.0, 0.0)

	# 视觉熄灭从这一刻开始；听觉慢半拍，触觉（操作）已经先没了。
	_veil.fade_param("blackout", 1.0, 4.4)
	if scene != null and scene.has_method("fade_station_audio"):
		scene.call("fade_station_audio", 4.2)
	if _radio_audio != null:
		var rt := create_tween()
		rt.tween_property(_radio_audio, "volume_db", -60.0, 4.2)
	_play_tinnitus()

	var ok3 := await _wait(0.8)
	if not ok3:
		return

	_veil.show_prompt()
	var waited := 0.0
	while waited < 4.6 and not _veil.prompt_pressed():
		await get_tree().create_timer(0.1 / speed).timeout
		if _stopped:
			return
		waited += 0.1

	if _veil.prompt_pressed():
		_veil.show_line("你伸出手。", 1.6, "指尖碰到雨。雨没有停。")
		var ok4 := await _wait(2.2)
		if not ok4:
			return
	else:
		_veil.hide_prompt()
		var ok4 := await _wait(0.4)
		if not ok4:
			return

	# 三件普通的事。不要解释、不要升华，死亡只是把它们一起拿走了。
	# 第三件里藏着「没做完的小事」：走廊的灯还开着，你出门时想回来再关。
	_veil.show_line("便利店的灯还亮着。店员把布丁放进袋子里，说了句什么。", 2.8, "00:04")
	var ok5 := await _wait(3.4)
	if not ok5:
		return
	_veil.show_line("厨房里有人喊你吃饭。你应了一声，没有回头。", 2.8, "19:12")
	var ok6 := await _wait(3.4)
	if not ok6:
		return
	_veil.show_line("同桌把橡皮掰成两半，大的那半推到你桌上。"
		+ "走廊的灯还开着 —— 你出门时想，回来再关。", 3.4, "第三节课")
	var ok7 := await _wait(4.6)
	if not ok7:
		return

	_veil.clear_line(0.6)
	if _tinnitus != null:
		var tt := create_tween()
		tt.tween_property(_tinnitus, "volume_db", -60.0, 1.2)
	var ok8 := await _wait(1.4)
	if not ok8:
		return
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_phase = Phase.DONE
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0

	if not transition_enabled:
		return
	# 「死」进草原是剧情强制转场，不走出口路由；目的地与到达方式仍归 SceneRouter 管，
	# 这样草原只需要看 arrival 的 mode 就知道该不该播那一段苏醒独白。
	var started := SceneRouter.goto(&"grassland", &"default", {
		"mode": &"story",
		"set_story_node": &"ep3_grassland",
		"transition": {
			"style": "letter",
			"title": "ISEKAI",
			"subtitle": "GRASSLAND",
			"footer": "SOMEWHERE · 06:12",
			"accent": Color("#ffd39a"),
		},
	})
	if not started:
		push_warning("GasStationStory: 草地转场未能启动")


## 转场锁：被别人切走时停下所有计时，别让一段 await 回来继续解锁输入。
func on_transition_lock() -> void:
	if _finished:
		return
	_stopped = true
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	if _veil != null and is_instance_valid(_veil):
		_veil.queue_free()


func _wait(seconds: float) -> bool:
	if _stopped:
		return false
	await get_tree().create_timer(maxf(0.01, seconds / maxf(speed, 0.01))).timeout
	return not _stopped


# ---------------------------------------------------------------- 道具

func _build_radio() -> void:
	var g := K.group(_props, "CounterRadio", RADIO_TARGET + Vector3(0.0, -0.10, 0.0))
	var wood := K.toon(Color("#3a2b22"), {"shade": 0.58, "rim": 0.16, "line": 0.005})
	var shell := K.toon(Color("#262b30"), {"shade": 0.52, "rim": 0.22, "line": 0.005})
	var chrome := K.toon(Color("#8d949b"), {"shade": 0.46, "rim": 0.4, "line": 0.004})

	# 窗台板：收音机不能浮在玻璃前面。板子挂在窗下沿，深度只伸出 12cm。
	K.box(g, Vector3(0.24, 0.055, 1.55), Vector3(-0.04, 0.0, -0.10), wood)
	K.box(g, Vector3(0.30, 0.16, 0.40), Vector3(0.0, 0.11, 0.0), shell)
	K.box(g, Vector3(0.012, 0.075, 0.19), Vector3(0.155, 0.13, 0.0),
		K.glow(Color("#ffb960"), 1.4), Vector3.ZERO, false)
	K.box(g, Vector3(0.012, 0.045, 0.14), Vector3(0.156, 0.055, -0.02),
		K.toon(Color("#14181c"), {"line": 0.003}), Vector3.ZERO, false)
	for i in 3:
		K.box(g, Vector3(0.008, 0.006, 0.13), Vector3(0.157, 0.16 - float(i) * 0.016, 0.0),
			chrome, Vector3.ZERO, false)
	for z in [0.11, 0.145]:
		K.cyl(g, 0.022, 0.018, Vector3(0.158, 0.055, z), chrome, Vector3(0, 0, 90), 10)
	K.strut(g, Vector3(0.06, 0.19, -0.14), Vector3(0.20, 0.39, -0.22), 0.006, chrome, 4, false)

	_radio_audio = AudioStreamPlayer3D.new()
	var s := Sfx.radio()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * float(s.mix_rate))
	_radio_audio.stream = s
	_radio_audio.position = RADIO_TARGET
	_radio_audio.volume_db = -20.0
	_radio_audio.unit_size = 1.6
	_radio_audio.max_distance = 9.0
	add_child(_radio_audio)
	_radio_audio.play()


func _build_parked_truck() -> void:
	_parked_truck = Truck.new()
	_parked_truck.name = "ParkedTruck"
	_parked_truck.clip_box = STATION_CLIP
	_parked_truck.position = PARKED_TRUCK_POS
	# 车头朝西：司机站在驾驶室旁边，正好面向加油机。
	_parked_truck.rotation.y = PI
	add_child(_parked_truck)

	_parked_body = CollisionLayout.solid(self,
		PARKED_TRUCK_POS + Vector3(0.0, 1.5, 0.0), Vector3(6.2, 3.0, 2.16))


func _build_driver() -> void:
	_driver = K.group(_props, "TruckDriver", DRIVER_POS, Vector3(0, -90, 0))
	var pants := K.toon(Color("#22262b"), {"shade": 0.62, "rim": 0.12, "line": 0.004})
	var jacket := K.toon(Color("#3b4a44"), {"shade": 0.55, "rim": 0.22, "line": 0.006})
	var skin := K.toon(Color("#c9a183"), {"shade": 0.58, "rim": 0.18, "line": 0.005})
	var cap := K.toon(Color("#1d2a33"), {"shade": 0.55, "rim": 0.2, "line": 0.005})

	for z in [-0.10, 0.10]:
		K.cyl(_driver, 0.085, 0.82, Vector3(0.0, 0.41, z), pants, Vector3.ZERO, 10)
	K.box(_driver, Vector3(0.36, 0.58, 0.42), Vector3(0.0, 1.12, 0.0), jacket)
	for z in [-0.20, 0.20]:
		K.strut(_driver, Vector3(0.0, 1.34, z), Vector3(0.10, 0.95, z * 1.18), 0.055, jacket, 6)
		K.sphere(_driver, 0.055, Vector3(0.10, 0.94, z * 1.18), skin, Vector3.ZERO, 8)
	K.sphere(_driver, 0.135, Vector3(0.0, 1.57, 0.0), skin, Vector3.ZERO, 12, 1.08)
	K.cyl(_driver, 0.145, 0.075, Vector3(0.0, 1.69, 0.0), cap, Vector3.ZERO, 12)
	K.box(_driver, Vector3(0.16, 0.018, 0.20), Vector3(0.12, 1.66, 0.0), cap, Vector3(0, 0, -8))
	# 手里的纸杯：打哈欠时总得有只手没处放。
	K.cyl(_driver, 0.042, 0.11, Vector3(0.14, 1.00, 0.20), K.toon(Color("#d8d2c2"), {"line": 0.004}),
		Vector3.ZERO, 10)


func _clear_parked() -> void:
	if _parked_truck != null:
		_parked_truck.queue_free()
		_parked_truck = null
	if _parked_body != null:
		_parked_body.queue_free()
		_parked_body = null
	if _driver != null:
		_driver.queue_free()
		_driver = null


func _intro_hint() -> void:
	var ok := await _wait(6.0)
	if not ok or _phase != Phase.WALK:
		return
	hud.toast("柜台里的收音机在响。东侧停着一辆厢式货车，司机靠在车门上。", 5.2)


# ---------------------------------------------------------------- 声音

func _play_at(pos: Vector3, stream: AudioStream, db: float = -4.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.volume_db = db
	p.unit_size = 3.4
	p.max_distance = 28.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _play_tinnitus() -> void:
	if _tinnitus != null:
		return
	_tinnitus = AudioStreamPlayer.new()
	_tinnitus.stream = Sfx.tinnitus()
	_tinnitus.volume_db = -13.0
	add_child(_tinnitus)
	_tinnitus.play()
