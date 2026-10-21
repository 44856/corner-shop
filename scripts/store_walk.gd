extends Node3D
## 雨夜便利店 · 可玩版
##
## 和 scenes/main.tscn 的关系：
##   main.tscn / main.gd 是原来的「微缩模型 + 轨道相机」展示版，保持不动；
##   这个场景复用同一套 street / store / props 造型库，但把编排换成
##   「一人、一店、一台跟随镜头」，并且店内改成能走进去的布局。
##   改动前的完整编排另存为 scenes/diorama_orbit.tscn（冻结备份）。
##
## 交互清单：
##   自动门      —— 走近 2.35m 自动滑开，离开后自动关闭，有人卡在门洞里不关
##   店内物件    —— 冷柜 / 货架 / 服务铃 / 门口的猫，按 E 出反馈
##   摄像机      —— 第三人称弹簧臂跟随，街道 ↔ 店内自动切换焦段与距离
##   声音        —— 雨声 / 店内低频 / 自动门叮咚 / 服务铃（全部程序化或复用现有 wav）
##   马路车祸    —— 进过店之后走下马路，右侧驶来一辆大货车（见 truck_event.gd）

const Street := preload("res://scripts/street.gd")
const Store := preload("res://scripts/store.gd")
const Props := preload("res://scripts/props.gd")
const WorldEnv := preload("res://scripts/world_env.gd")
const CollisionLayout := preload("res://scripts/collision_layout.gd")
const AutoDoor := preload("res://scripts/autodoor.gd")
const PlayerController := preload("res://scripts/player_controller.gd")
const Hud := preload("res://scripts/hud.gd")
const Hub := preload("res://scripts/interaction_hub.gd")
const Sfx := preload("res://scripts/sfx.gd")
const TruckEvent := preload("res://scripts/truck_event.gd")

## 出生点：人行道上、雨棚底下，正对店门
const SPAWN := Vector3(0.35, 0.17, 0.95)

## 街道机位：稍微远一点，能同时看到人和店面
const CAM_OUT := {"dist": 3.9, "height": 1.52, "fov": 52.0, "shoulder": 0.10}
## 店内机位：店面只有 4.2×4.2m，臂长必须收到 1.6m 以内，
## 否则镜头永远卡在货架 / 柜台边上；FOV 拉大 + 右肩偏移补回视野
const CAM_IN := {"dist": 1.6, "height": 1.55, "fov": 70.0, "shoulder": 0.28}

## 曝光：店内暖光密集，按街道那档曝光进来会过曝（天花板直接烧白）
const EXPOSE_OUT := 1.12
const EXPOSE_IN := 0.92

## 店内包围盒（判定「在店里」用）。东墙从 3.1 推到 4.30，休息室也在里面。
const INTERIOR := AABB(Vector3(-1.46, 0.0, -5.26), Vector3(5.52, 3.0, 4.12))

## 开场镜头的起点：原微缩场景的机位
const ORBIT := {"yaw": 26.0, "pitch": 14.5, "dist": 17.0, "target": Vector3(0.0, 1.2, -0.95)}

var player: CharacterBody3D
var door                       # autodoor.gd（动态调用，故不加类型）
var hud                        # hud.gd
var hub                        # interaction_hub.gd
var truck_event                # truck_event.gd
var env: Environment

var _inside := false
var _zone := "side"
var _shooting := false
var _shadow: MeshInstance3D
var _rain: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _intro_cam: Camera3D
var _intro_tween: Tween


func _ready() -> void:
	env = WorldEnv.build(self)["environment"]

	Street.build(self)
	Store.build(self, {"walkable": true, "auto_door": true})
	Props.build(self)
	CollisionLayout.build(self)

	_setup_player()
	_setup_door()
	_setup_hud()
	_setup_interactions()
	_setup_audio()
	_setup_truck_event()

	if "--shot" in OS.get_cmdline_user_args():
		_take_shots()
	else:
		_play_intro()


# ---------------------------------------------------------------- 装配

func _setup_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	player.position = SPAWN
	# 相机落在 +Z 侧、看向 −Z：正好是「人的背后站着，店门在前方」
	player.start_yaw_deg = 0.0
	player.capture_mouse_on_start = false
	# 夜景角色：和原场景 actor 完全同一组压暗参数，否则人会亮得像贴纸
	player.actor_tint = Color(0.52, 0.55, 0.66)
	player.actor_shade_floor = 0.34
	player.actor_rim_strength = 0.06
	player.actor_outline_width = 0.006
	player.cam_distance = CAM_OUT["dist"]
	player.cam_height = CAM_OUT["height"]
	add_child(player)
	player.input_locked = true
	player.face(PI)          # 模型脸朝 +Z，转 180° 就是面朝店面
	player.set_camera_profile(CAM_OUT["dist"], CAM_OUT["height"], CAM_OUT["fov"],
		CAM_OUT["shoulder"], 6.0)


## 脚下的接触阴影。
## 夜景里主光是月光，能量只有 0.55，角色踩在地上几乎没有影子，
## 近看就像贴在画面上。这里铺一张跟着脚走的柔光斑（Decal 太重，一张 Alpha 面片足够）。
func _setup_shadow() -> void:
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.15, 1.15)
	_shadow.mesh = quad
	_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.62))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_shadow.material_override = m
	add_child(_shadow)


func _update_shadow() -> void:
	if _shadow == null or player == null:
		return
	var p: Vector3 = player.global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 0.4, 0.0), p + Vector3(0.0, -2.0, 0.0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var ground: Vector3 = hit["position"]
	_shadow.global_position = ground + Vector3(0.0, 0.012, 0.0)
	# 离地越高影子越小越淡（跳起來的时候）
	var h := clampf(p.y - ground.y, 0.0, 1.4)
	var k := 1.0 - h * 0.42
	_shadow.scale = Vector3(k, k, 1.0)
	var mat := _shadow.material_override as StandardMaterial3D
	mat.albedo_color.a = clampf(1.0 - h * 0.55, 0.25, 1.0)


func _setup_door() -> void:
	door = AutoDoor.new()
	door.name = "AutoDoor"
	add_child(door)
	door.bind_player(player)


func _setup_hud() -> void:
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.set_zone("店外 · 人行道")


func _setup_interactions() -> void:
	hub = Hub.new()
	hub.name = "InteractionHub"
	add_child(hub)
	hub.bind(player, hud)

	# 冷柜：站在它东侧 0.9m 处就能按
	hub.add_target(Vector3(1.35, 1.0, -4.55), 1.75, "拉开冷柜", _on_fridge)
	# 货架：两块货架中间那条过道（货架东端收到 0.60，中心跟着西移）
	hub.add_target(Vector3(-0.20, 1.0, -3.85), 1.55, "翻一翻货架", _on_rack)
	# 收银台：加长到 2.2m 之后铃铛在 (1.68, −2.92)。
	# inside_only：服务铃只在店里按得响 —— 隔着东墙 / 空调外机从后巷按，
	# 距离判定能过（1.4m），但那不是「按铃」，是「穿墙」。视线检查在中枢里做。
	hub.add_target(Vector3(1.68, 1.0, -2.92), 1.40, "按服务铃", _on_bell,
		func() -> bool: return _inside)
	# 门口的猫
	hub.add_target(Vector3(0.98, 0.4, -0.52), 1.3, "摸摸猫", _on_cat)


func _setup_audio() -> void:
	_rain = _looping_player("res://audio/rain_loop.wav", -15.0)
	_hum = _looping_player("res://audio/drone_loop.wav", -40.0)


## 马路车祸：独立节点，自己盯着「人是不是站在车行道上」
func _setup_truck_event() -> void:
	truck_event = TruckEvent.new()
	truck_event.name = "TruckEvent"
	add_child(truck_event)
	truck_event.bind(player, hud)


func _looping_player(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s := load(path) as AudioStreamWAV
	if s != null:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * float(s.mix_rate))
		p.stream = s
	p.volume_db = db
	add_child(p)
	p.play()
	return p


# ---------------------------------------------------------------- 开场

## 从微缩全景推镜到第三人称。比直接黑场切换更像「走进这个场景」。
func _play_intro() -> void:
	player.input_locked = true
	player.camera.current = false

	_intro_cam = Camera3D.new()
	_intro_cam.name = "IntroCam"
	_intro_cam.fov = 40.0
	_intro_cam.near = 0.1
	_intro_cam.far = 200.0
	add_child(_intro_cam)
	_intro_cam.current = true

	var from := _orbit_transform()
	var to: Transform3D = player.camera.global_transform
	_intro_cam.global_transform = from

	hud.fade_in(1.3)

	var cam := _intro_cam
	_intro_tween = create_tween()
	_intro_tween.tween_method(
		func(v: float) -> void: cam.global_transform = from.interpolate_with(to, v),
		0.0, 1.0, 3.6
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_intro_tween.finished.connect(func() -> void: _on_intro_finished(cam))


## 跳过开场推镜，直接落到第三人称（调试 / 实机快速验证用）。
## 补间必须 kill 掉：留着的话三秒后它会再跑一遍 _on_intro_finished，
## 把已经锁上的输入重新解开 —— 车祸演到一半人突然能走，很难查。
func skip_intro() -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	if _intro_cam != null and is_instance_valid(_intro_cam):
		_intro_cam.queue_free()
	_intro_cam = null
	_intro_tween = null
	hud.fade_in(0.0)
	player.camera.current = true
	player.input_locked = false
	door.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _orbit_transform() -> Transform3D:
	var yaw := deg_to_rad(ORBIT["yaw"])
	var pitch := deg_to_rad(ORBIT["pitch"])
	var target: Vector3 = ORBIT["target"]
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	var pos: Vector3 = target + dir * float(ORBIT["dist"])
	return Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)


func _on_intro_finished(cam: Camera3D) -> void:
	if is_instance_valid(cam):
		cam.queue_free()
	_intro_cam = null
	_intro_tween = null
	player.camera.current = true
	player.input_locked = false
	door.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("WASD 移动 · 走近店门会自动打开", 4.0)


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if player == null:
		return

	# Tab 释放鼠标：没有这个键，窗口化调试时会很难受
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var p: Vector3 = player.global_position
	var zone := _zone_at(p)
	if zone != _zone:
		_on_zone_changed(zone)

	_update_shadow()

	# 雨声跟着进出变化：进店之后只剩闷在玻璃外面的雨
	var rain_db := -26.0 if _inside else -15.0
	var hum_db := -24.0 if _inside else -40.0
	if _rain != null:
		_rain.volume_db = lerpf(_rain.volume_db, rain_db, 1.0 - exp(-1.6 * delta))
	if _hum != null:
		_hum.volume_db = lerpf(_hum.volume_db, hum_db, 1.0 - exp(-1.6 * delta))


## 三个区域：店内 / 人行道 / 车行道。
## 人行道是 L 形（含 0.17m 宽的路缘石，外沿 x −2.07 / z 2.07），
## 其余落在台面上的都是沥青路面。
func _zone_at(p: Vector3) -> String:
	if INTERIOR.has_point(p):
		return "in"
	if p.z > 2.07 or p.x < -2.07:
		return "road"
	return "side"


func _on_zone_changed(zone: String) -> void:
	var was_inside := _inside
	_zone = zone
	_inside = zone == "in"

	if _inside and truck_event != null:
		# 「进过店」是车祸事件的前置条件，只记第一次
		truck_event.notify_store_entered()

	match zone:
		"in":
			hud.set_zone("店内 · HOSHI MART", true)
		"road":
			hud.set_zone("马路 · 车行道", false)
		_:
			hud.set_zone("店外 · 人行道", false)

	# 截图模式下机位由 _take_shots 直接指定，别让区域切换把它拉回去
	if _shooting:
		return
	if _inside == was_inside:
		return
	if _inside:
		player.set_camera_profile(CAM_IN["dist"], CAM_IN["height"], CAM_IN["fov"],
			CAM_IN["shoulder"], 3.6)
		hud.toast("暖光、冷柜的嗡嗡声，还有收银台上那本翻到一半的杂志。", 4.0)
	else:
		player.set_camera_profile(CAM_OUT["dist"], CAM_OUT["height"], CAM_OUT["fov"],
			CAM_OUT["shoulder"], 3.6)


# ---------------------------------------------------------------- 交互回调

func _on_fridge() -> void:
	_play_at(Vector3(1.35, 1.0, -4.8), Sfx.tap(), -4.0)
	hud.toast("冷柜的灯管嗡嗡响。最上层那排罐装咖啡，指尖碰上去是温的。", 4.2)


func _on_rack() -> void:
	_play_at(Vector3(0.0, 1.0, -3.85), Sfx.tap(), -8.0)
	var lines := [
		"方便面、罐头、两排没什么人买的进口饼干。保质期都还早。",
		"货架第三层空了一格。价签还在，东西没了。",
		"你顺手把一盒倒下的泡芙扶正。店里安静得能听见雨敲雨棚。",
	]
	hud.toast(lines[randi() % lines.size()], 4.2)


func _on_bell() -> void:
	_play_at(Vector3(2.35, 1.1, -3.0), Sfx.bell(), -3.0)
	hud.toast("叮——没有人从后间出来。只有收银机上的待机灯在闪。", 4.2)


func _on_cat() -> void:
	_play_at(Vector3(0.98, 0.4, -0.52), Sfx.tap(), -12.0)
	hud.toast("猫抬头看了你一眼，尾巴尖晃了两下，又趴回干燥的台阶上。", 4.2)


## 一次性 3D 音源，播完自己回收
func _play_at(pos: Vector3, stream: AudioStream, db: float = -6.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.volume_db = db
	p.unit_size = 3.0
	p.max_distance = 14.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- 截图

## 调试用：`--only=walk_h_breakroom` 只拍这一张。
## 调机位的时候全套跑一遍要两分钟，只拍一张十几秒，改十次也不心疼。
func _only_shot() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(7)
	return ""


func _take_shots() -> void:
	_shooting = true
	var only := _only_shot()
	# 不锁输入：交互中枢在锁定状态下不出提示，而提示本身是要拍进图里的
	player.input_locked = false
	# 截图时手动控制门的开合，别让感应器把「关着」的那张也打开
	door.enabled = false
	# 摆拍的时候别让车祸事件自己触发
	truck_event.auto_trigger = false
	hud.fade_in(0.0)
	DirAccess.make_dir_recursive_absolute("res://shots")

	# 先来一张和原场景同机位的全景，用来对照「编排备份」和「可玩版」的差别。
	# --only 时跳过：调单张的时候不用每次都等这张。
	if only == "":
		await _shot_overview()

	var specs := [
		{"name": "walk_b_street", "pos": SPAWN, "face": PI, "yaw": 0.0, "pitch": -0.12,
			"dist": 3.9, "door": false, "fov": 52.0, "shoulder": 0.10, "exp": EXPOSE_OUT,
			"prompt": false},
		{"name": "walk_c_door", "pos": Vector3(0.35, 0.17, -0.62), "face": PI, "yaw": 0.0,
			"pitch": -0.05, "dist": 2.6, "door": true, "fov": 58.0, "shoulder": 0.10, "exp": 1.06,
			"prompt": false},
		# 进门后往北看：左边货架、右边加长到 2.2m 的柜台、柜台后面是休息室。
		# 机位必须留在店内 —— 后退 2.2m 会退到玻璃门外，拍出来是隔着橱窗往里看。
		{"name": "walk_d_inside", "pos": Vector3(0.72, 0.25, -3.05), "face": PI, "yaw": 6.0,
			"pitch": -0.04, "dist": 1.95, "door": true, "fov": 66.0, "shoulder": 0.52, "exp": EXPOSE_IN},
		# 两块货架之间那条 0.80m 的过道：从东侧看进去，证明「真的走得进去」
		{"name": "walk_e_aisle", "pos": Vector3(0.30, 0.25, -3.18), "face": -PI * 0.5, "yaw": 90.0,
			"pitch": 0.0, "dist": 1.9, "door": true, "fov": 68.0, "shoulder": 0.26, "exp": EXPOSE_IN},
		# 商品特写：站在过道东端沿货架看过去，三层排面、价签、分类牌一次拍全。
		# 用自由机位而不是第三人称：0.83m 的过道塞不下 1.9m 摇臂，人会挡住半个货架。
		{"name": "walk_j_goods", "free": Vector3(1.18, 1.50, -3.02),
			"look": Vector3(-0.85, 0.96, -3.80), "door": true, "fov": 58.0, "exp": EXPOSE_IN,
			"prompt": false},
		# 南侧货架正面（进门第一眼看到的那一面）。过道只有 0.83m，只能广角贴脸拍。
		{"name": "walk_k_goods_south", "free": Vector3(1.20, 1.46, -3.34),
			"look": Vector3(-0.55, 0.92, -2.62), "door": true, "fov": 64.0, "exp": EXPOSE_IN,
			"prompt": false},
		# 冷柜正面：隔着四扇玻璃门看四层货（便当 / 饭团 / 瓶装 / 罐装）
		{"name": "walk_l_fridge", "free": Vector3(0.92, 1.52, -3.36),
			"look": Vector3(1.30, 1.32, -5.00), "door": true, "fov": 72.0, "exp": EXPOSE_IN,
			"prompt": false},
		# 杂志架 + 靠窗堆头：这两个是「商品陈列」里最容易被忽略的两处
		{"name": "walk_m_magazine", "free": Vector3(0.55, 1.30, -1.86),
			"look": Vector3(-1.20, 0.92, -1.95), "door": true, "fov": 62.0, "exp": EXPOSE_IN,
			"prompt": false},
		# 休息室：隔窗看进去（灯亮着、桌椅在，但进不去）。
		# 这一张用自由机位：0.80m 的过道塞不下第三人称摇臂，
		# 人往窗前一站就把窗挡死，不如直接给一台固定机位拍建筑本身。
		{"name": "walk_h_breakroom", "free": Vector3(0.95, 1.52, -2.42),
			"look": Vector3(2.80, 1.26, -2.98), "door": true, "fov": 60.0, "exp": EXPOSE_IN,
			"prompt": false},
	]

	for s in specs:
		if only != "" and s["name"] != only:
			continue
		door.set_open(s["door"], true)
		env.tonemap_exposure = s["exp"]
		hub.enabled = s.get("prompt", true)
		if not hub.enabled:
			hud.hide_prompt()

		if s.has("free"):
			var fc := Camera3D.new()
			fc.fov = s["fov"]
			fc.near = 0.05
			fc.far = 200.0
			add_child(fc)
			fc.global_position = s["free"]
			fc.look_at(s["look"], Vector3.UP)
			fc.current = true
			player.camera.current = false
			player.visible = false
			_update_shadow()
			for i in 12:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % s["name"])
			print("saved ", s["name"])
			fc.queue_free()
			player.visible = true
			player.camera.current = true
			continue

		player.global_position = s["pos"]
		player.face(s["face"])
		player.snap_camera(s["dist"], 1.45, s["fov"], s["shoulder"])
		player.cam_rig.rotation = Vector3(s["pitch"], s["yaw"], 0.0)
		_update_shadow()
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])

	# ---- 货车：三张。裁剪 / 压到人面前 / 车头特写 ----
	# --only 也管这三张：调车灯和光柱时不用把前面六张一起重拍
	var want := func(n: String) -> bool:
		return only == "" or only == n

	env.tonemap_exposure = EXPOSE_OUT
	hub.enabled = false
	hud.hide_prompt()
	hud.visible = false

	if want.call("walk_f_truck_clip"):
		# 车尾还在台面外（x = −5.6 以远）：只画台面内的那一段
		truck_event.debug_show(-4.2, 3.6)
		var tcam := Camera3D.new()
		tcam.fov = 40.0
		tcam.near = 0.1
		tcam.far = 200.0
		add_child(tcam)
		# 高一点、偏南：把台面西缘那条线一起拍进去，切在哪儿才看得出来
		tcam.global_position = Vector3(1.6, 6.0, 9.2)
		tcam.look_at(Vector3(-4.9, 0.7, 3.3), Vector3.UP)
		tcam.current = true
		player.camera.current = false
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/walk_f_truck_clip.png")
		print("saved walk_f_truck_clip")
		tcam.queue_free()
		player.camera.current = true
		hud.visible = true

	if want.call("walk_g_truck_hit"):
		# 站在马路中间、车从右侧压过来：这一张用侧机位，人、车头、店招同框
		truck_event.debug_show(-3.9, 3.5)
		player.global_position = Vector3(0.55, 0.0, 2.5)
		player.face(-PI * 0.5)
		var hcam := Camera3D.new()
		hcam.fov = 46.0
		hcam.near = 0.1
		hcam.far = 200.0
		add_child(hcam)
		hcam.global_position = Vector3(3.75, 1.85, 5.15)
		hcam.look_at(Vector3(-1.8, 1.05, 3.1), Vector3.UP)
		hcam.current = true
		player.camera.current = false
		_update_shadow()
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/walk_g_truck_hit.png")
		print("saved walk_g_truck_hit")
		hcam.queue_free()
		player.camera.current = true

	if want.call("walk_i_truck_beam"):
		# 车头特写：看格栅 / 灯组 / 雨刷这些细节，也看两道光柱怎么压在湿路面上
		truck_event.debug_show(-1.2, 3.55)
		var bcam := Camera3D.new()
		bcam.fov = 42.0
		bcam.near = 0.05
		bcam.far = 200.0
		add_child(bcam)
		bcam.global_position = Vector3(4.30, 2.55, 7.60)
		bcam.look_at(Vector3(0.70, 1.05, 3.40), Vector3.UP)
		bcam.current = true
		player.camera.current = false
		player.visible = false
		hud.visible = false
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/walk_i_truck_beam.png")
		print("saved walk_i_truck_beam")
		bcam.queue_free()
		player.visible = true
		player.camera.current = true
		hud.visible = true

	get_tree().quit()


## 全景对照图（和微缩展示版同机位）
func _shot_overview() -> void:
	var orbit := Camera3D.new()
	orbit.fov = 40.0
	orbit.near = 0.1
	orbit.far = 200.0
	add_child(orbit)
	orbit.global_transform = _orbit_transform()
	orbit.current = true
	player.camera.current = false
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/walk_a_overview.png")
	print("saved walk_a_overview")
	orbit.queue_free()
	player.camera.current = true
