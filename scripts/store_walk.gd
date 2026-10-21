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

## 店内包围盒（判定「在店里」用）
const INTERIOR := AABB(Vector3(-1.46, 0.0, -5.26), Vector3(4.32, 3.0, 4.12))

## 开场镜头的起点：原微缩场景的机位
const ORBIT := {"yaw": 26.0, "pitch": 14.5, "dist": 17.0, "target": Vector3(0.0, 1.2, -0.95)}

var player: CharacterBody3D
var door                       # autodoor.gd（动态调用，故不加类型）
var hud                        # hud.gd
var hub                        # interaction_hub.gd
var env: Environment

var _inside := false
var _shooting := false
var _shadow: MeshInstance3D
var _rain: AudioStreamPlayer
var _hum: AudioStreamPlayer


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
	# 货架：两块货架中间那条过道
	hub.add_target(Vector3(0.0, 1.0, -3.85), 1.55, "翻一翻货架", _on_rack)
	# 收银台：沿东墙，正面朝 −X
	hub.add_target(Vector3(2.58, 1.0, -3.0), 1.35, "按服务铃", _on_bell)
	# 门口的猫
	hub.add_target(Vector3(0.98, 0.4, -0.52), 1.3, "摸摸猫", _on_cat)


func _setup_audio() -> void:
	_rain = _looping_player("res://audio/rain_loop.wav", -15.0)
	_hum = _looping_player("res://audio/drone_loop.wav", -40.0)


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

	var cam := Camera3D.new()
	cam.name = "IntroCam"
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	cam.current = true

	var from := _orbit_transform()
	var to: Transform3D = player.camera.global_transform
	cam.global_transform = from

	hud.fade_in(1.3)

	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void: cam.global_transform = from.interpolate_with(to, v),
		0.0, 1.0, 3.6
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func() -> void: _on_intro_finished(cam))


func _orbit_transform() -> Transform3D:
	var yaw := deg_to_rad(ORBIT["yaw"])
	var pitch := deg_to_rad(ORBIT["pitch"])
	var target: Vector3 = ORBIT["target"]
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	var pos: Vector3 = target + dir * float(ORBIT["dist"])
	return Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)


func _on_intro_finished(cam: Camera3D) -> void:
	cam.queue_free()
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
	var inside := INTERIOR.has_point(p)
	if inside != _inside:
		_on_zone_changed(inside)

	_update_shadow()

	# 雨声跟着进出变化：进店之后只剩闷在玻璃外面的雨
	var rain_db := -26.0 if _inside else -15.0
	var hum_db := -24.0 if _inside else -40.0
	if _rain != null:
		_rain.volume_db = lerpf(_rain.volume_db, rain_db, 1.0 - exp(-1.6 * delta))
	if _hum != null:
		_hum.volume_db = lerpf(_hum.volume_db, hum_db, 1.0 - exp(-1.6 * delta))


func _on_zone_changed(inside: bool) -> void:
	_inside = inside
	hud.set_zone("店内 · HOSHI MART" if inside else "店外 · 人行道", inside)
	# 截图模式下机位由 _take_shots 直接指定，别让区域切换把它拉回去
	if _shooting:
		return
	if inside:
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

func _take_shots() -> void:
	_shooting = true
	# 不锁输入：交互中枢在锁定状态下不出提示，而提示本身是要拍进图里的
	player.input_locked = false
	# 截图时手动控制门的开合，别让感应器把「关着」的那张也打开
	door.enabled = false
	hud.fade_in(0.0)
	DirAccess.make_dir_recursive_absolute("res://shots")

	# 先来一张和原场景同机位的全景，用来对照「编排备份」和「可玩版」的差别
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

	var specs := [
		{"name": "walk_b_street", "pos": SPAWN, "face": PI, "yaw": 0.0, "pitch": -0.12,
			"dist": 3.9, "door": false, "fov": 52.0, "shoulder": 0.10, "exp": EXPOSE_OUT,
			"prompt": false},
		{"name": "walk_c_door", "pos": Vector3(0.35, 0.17, -0.62), "face": PI, "yaw": 0.0,
			"pitch": -0.05, "dist": 2.6, "door": true, "fov": 58.0, "shoulder": 0.10, "exp": 1.06,
			"prompt": false},
		{"name": "walk_d_inside", "pos": Vector3(1.4, 0.25, -3.6), "face": PI, "yaw": 6.0,
			"pitch": -0.04, "dist": 1.95, "door": true, "fov": 66.0, "shoulder": 0.34, "exp": EXPOSE_IN},
		# 两块货架之间那条 0.83m 的过道：从东侧看进去，证明「真的走得进去」
		{"name": "walk_e_aisle", "pos": Vector3(0.3, 0.25, -3.18), "face": -PI * 0.5, "yaw": 90.0,
			"pitch": 0.0, "dist": 1.9, "door": true, "fov": 68.0, "shoulder": 0.26, "exp": EXPOSE_IN},
	]

	for s in specs:
		player.global_position = s["pos"]
		player.face(s["face"])
		player.snap_camera(s["dist"], 1.45, s["fov"], s["shoulder"])
		player.cam_rig.rotation = Vector3(s["pitch"], s["yaw"], 0.0)
		door.set_open(s["door"], true)
		env.tonemap_exposure = s["exp"]
		hub.enabled = s.get("prompt", true)
		if not hub.enabled:
			hud.hide_prompt()
		_update_shadow()
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])

	get_tree().quit()
