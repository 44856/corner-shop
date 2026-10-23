extends Node3D
## 雨夜 · 星见町商店街（可玩场景）
##
## 和 store_walk 的关系：
##   store_walk 是一间店 + 一个街角，尺寸 11.2m 见方，探针钉死了它的每一米；
##   这个场景把同一家便利店放在街区西端，向东拉出一条 35.6m 的双侧商店街。
##   商店 / 雨棚 / 货架 / 碰撞原语全部复用，只有街面与两排背景建筑是新写的。
##
## 动线：
##   出生在东口牌楼内侧 → 沿北人行道往西 → 路过拉面 / 居酒屋 / 洗衣 / 烟店 /
##   公寓 / 交番 → 走到街尾的便利店。南侧是钱汤、喫茶店、诊所和口袋公园，
##   中间一条双向车道，斑马线在牌楼正前方。
##
## 交互沿用 interaction_hub：谁最近提示谁。街上的点只做「看一眼 / 听一声」，
## 真正能改变场景状态的仍然只有便利店那四个（冷柜 / 货架 / 铃 / 猫）。

const Town := preload("res://scripts/town.gd")
const ShopRow := preload("res://scripts/shop_row.gd")
const Store := preload("res://scripts/store.gd")
const Props := preload("res://scripts/props.gd")
const WorldEnv := preload("res://scripts/world_env.gd")
const TownCollision := preload("res://scripts/town_collision.gd")
const AutoDoor := preload("res://scripts/autodoor.gd")
const PlayerController := preload("res://scripts/player_controller.gd")
const Hud := preload("res://scripts/hud.gd")
const Hub := preload("res://scripts/interaction_hub.gd")
const Sfx := preload("res://scripts/sfx.gd")
const K := preload("res://scripts/kit.gd")
const CollisionLayout := preload("res://scripts/collision_layout.gd")
const PortalHost := preload("res://scripts/core/portal_host.gd")

## 出生点：东口牌楼内侧、北人行道上，面朝西。
## x 再往东 0.3m 就会落进「交番」交互点的半径里，开场提示会抢画面。
const SPAWN := Vector3(24.2, 0.17, 1.5)

## 西口：走到这里就切去加油站。边界墙内面在 x ≈ −5.4，
## 0.32m 半径的胶囊最远只能到 −5.08 —— 触发线必须留在它东边。
const WEST_EXIT_X := Town.X0 + 0.7
## 从加油站回来时的落点。离触发线 1.05m，转身再往回走要花半秒以上，
## 不会一落地就又被送回去。
const ARRIVE_FROM_GAS := Vector3(Town.X0 + 1.75, 0.17, 1.5)

## 场景路由登记。目的地不在这里，在 scripts/core/world_links.gd。
## spawn 的 pos/face/cam_yaw 必须和旧的落点分支一致，
## 否则从加油站回来时人物会突然转向。
const SCENE_ID := &"hoshi_street"
const SPAWNS := {
	&"default": {"pos": SPAWN, "face": -PI * 0.5, "cam_yaw": 90.0},
	&"west_gate": {"pos": ARRIVE_FROM_GAS, "face": PI * 0.5, "cam_yaw": 270.0},
}
## triggers 的矩形是 xz 平面：Rect2(x, z, 宽, 深)。
## 西口只认 x 是否跨过 WEST_EXIT_X，z 由街道两侧的碰撞边界去限制。
const PORTALS := [
	{"id": &"west_gate", "triggers": [
		{"kind": "walk",
			"rect": Rect2(WEST_EXIT_X - 1.2, Town.Z0, 1.2, Town.Z1 - Town.Z0)},
	]},
]

## 街道机位：与加油站同一套肩后视角。开阔处 4.9m 会把人物拉远，
## 收到 4.4m、支点降到胸口；窄处弹簧臂本来就会自己收短。
const CAM_OUT := {"dist": 4.4, "height": 1.45, "fov": 52.0, "shoulder": 0.30}
## 店内机位：与 store_walk 完全一致（4.2×4.2m 的店塞不下长摇臂）
const CAM_IN := {"dist": 1.6, "height": 1.55, "fov": 70.0, "shoulder": 0.28}

const EXPOSE_OUT := 1.12
const EXPOSE_IN := 0.92

## 店内包围盒：和 store_walk 同一个数字，判定「在店里」用
const INTERIOR := AABB(Vector3(-1.46, 0.0, -5.26), Vector3(5.52, 3.0, 4.12))

## 开场：从牌楼内侧上方俯冲进第三人称。
## 不能再放在 x>30 —— 东口对面补了一堵背景楼，机位会被自己的布景挡死。
## 起始 FOV 比游戏内宽：2.6m 处要装下 4.9m 宽的招牌，46° 只能拍到字。
const INTRO_FROM_POS := Vector3(29.6, 5.6, 3.0)
const INTRO_LOOK := Vector3(14.0, 2.4, 2.2)
const INTRO_FOV := 70.0

var player: CharacterBody3D
var door                       # autodoor.gd
var hud                        # hud.gd
var hub                        # interaction_hub.gd
var portals                    # portal_host.gd
var env: Environment

var _inside := false
var _zone := "gate"
var _shooting := false
## SceneRouter 在 _ready 里交给本场景的「我是怎么来的」。取一次就清空。
var _arrival: Dictionary = {}
var _shadow: MeshInstance3D
var _rain: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _intro_cam: Camera3D
var _intro_tween: Tween


func _ready() -> void:
	# 到达上下文必须最先取走：_setup_player 要用它决定落点和朝向。
	# 探针直接实例化本场景时没有上下文，走 default / 开场运镜。
	SceneRouter.bind_scene(SCENE_ID)
	_arrival = SceneRouter.consume_arrival()
	if not _arrival.is_empty() and not _is_arrival():
		push_warning("HoshiStreet: 到达上下文属于 %s，不是本场景" % _arrival.get("to_scene", &""))
		_arrival.clear()

	env = WorldEnv.build(self, {
		"fog_length": 48.0,
		"rain": {
			"center": Vector2(Town.CENTER_X, Town.CENTER_Z),
			"half": Vector2((Town.X1 - Town.X0) * 0.5, (Town.Z1 - Town.Z0) * 0.5),
			# 旧场景 11.2×11.2 用 1200；面积比约 4.3 倍，取 4600 维持同样的雨密度
			"amount": 4600,
			"top_y": 12.5,
			"covers": Town.rain_covers() + ShopRow.rain_covers(),
		},
		"ripples": Town.ripples() + ShopRow.ripples(),
	})["environment"]

	Town.build(self)
	ShopRow.build(self)
	Store.build(self, {"walkable": true, "auto_door": true})
	Props.storefront(self)
	Props.alley(self)
	TownCollision.build(self)
	_build_west_exit()
	# 静态街景到这里就装完了：合批后 2500+ 个 MeshInstance 收成几百批。
	# 自动门、碰撞、角色都在这一行之后创建，不会被误烘进静态网格。
	K.batch_static(self, ["Town", "ShopRow", "Store", "StorefrontProps", "AlleyProps", "WestExit"])

	_setup_player()
	_setup_door()
	_setup_hud()
	_setup_interactions()
	_setup_portals()
	_setup_audio()

	if "--shot" in OS.get_cmdline_user_args():
		_take_shots()
	elif _is_arrival():
		_on_arrival()
	else:
		_play_intro()


func _is_arrival() -> bool:
	return _arrival.get("to_scene", &"") == SCENE_ID


# ---------------------------------------------------------------- 装配

func _spawn_data() -> Dictionary:
	var key: StringName = &"default"
	if _is_arrival():
		key = _arrival.get("spawn", &"default")
	return SPAWNS.get(key, SPAWNS[&"default"])


func _setup_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	# 第一次进来落在东口、面朝西；从加油站回来则落在西口、面朝东。
	# 相机始终在身后 —— 若还按开场那套摆，玩家一回来就是镜头对着脸。
	var spawn := _spawn_data()
	var pos: Vector3 = spawn.get("pos", SPAWN)
	var face: float = float(spawn.get("face", -PI * 0.5))
	var cam_yaw: float = float(spawn.get("cam_yaw", 90.0))
	player.position = pos
	player.start_yaw_deg = cam_yaw
	player.capture_mouse_on_start = false
	player.actor_tint = Color(0.52, 0.55, 0.66)
	player.actor_shade_floor = 0.34
	player.actor_rim_strength = 0.06
	player.actor_outline_width = 0.006
	player.cam_distance = CAM_OUT["dist"]
	player.cam_height = CAM_OUT["height"]
	add_child(player)
	player.input_locked = true
	player.face(face)
	player.set_camera_profile(CAM_OUT["dist"], CAM_OUT["height"], CAM_OUT["fov"],
		CAM_OUT["shoulder"], 6.0)


func _setup_door() -> void:
	door = AutoDoor.new()
	door.name = "AutoDoor"
	add_child(door)
	door.bind_player(player)


func _setup_hud() -> void:
	hud = Hud.new()
	hud.name = "HUD"
	hud.title_text = "HOSHIMI SHOTENGAI"
	hud.subtitle_text = "雨夜 23:47　星见町商店街"
	hud.zone_text = "商店街 · 东口"
	hud.accent_color = Color("#ffcf8a")
	add_child(hud)
	hud.set_zone("商店街 · 东口", true)


func _setup_interactions() -> void:
	hub = Hub.new()
	hub.name = "InteractionHub"
	add_child(hub)
	hub.bind(player, hud)

	# ---- 便利店（和老场景同一组坐标）----
	hub.add_target(Vector3(1.35, 1.0, -4.55), 1.75, "拉开冷柜", _on_fridge)
	hub.add_target(Vector3(-0.20, 1.0, -3.85), 1.55, "翻一翻货架", _on_rack)
	hub.add_target(Vector3(1.68, 1.0, -2.92), 1.40, "按服务铃", _on_bell,
		func() -> bool: return _inside)
	hub.add_target(Vector3(0.98, 0.4, -0.52), 1.30, "摸摸猫", _on_cat)

	# ---- 北侧店面 ----
	hub.add_target(Vector3(7.70, 1.8, -0.52), 1.65, "掀开暖帘", _on_ramen)
	hub.add_target(Vector3(11.40, 1.8, -0.50), 1.55, "看看今晚的菜牌", _on_izakaya)
	hub.add_target(Vector3(13.60, 1.1, -0.42), 1.45, "买一罐热咖啡", _on_vending)
	hub.add_target(Vector3(16.10, 1.2, -0.38), 1.90, "看看洗衣机", _on_laundry)
	hub.add_target(Vector3(19.40, 1.2, -0.40), 1.55, "看一眼烟店", _on_tobacco)
	hub.add_target(Vector3(25.55, 1.4, -0.40), 1.70, "看一眼交番", _on_koban)

	# ---- 南侧店面与街具 ----
	hub.add_target(Vector3(8.50, 1.7, 6.14), 1.85, "看看钱汤的暖帘", _on_sento)
	hub.add_target(Vector3(16.00, 1.5, 6.14), 1.80, "在喫茶店门口站一会儿", _on_coffee)
	hub.add_target(Vector3(24.35, 1.2, 5.72), 1.80, "看看末班车时刻", _on_bus)
	hub.add_target(Vector3(25.00, 1.3, 6.20), 1.60, "看看口袋公园", _on_park)
	hub.add_target(Vector3(1.55, 1.0, 8.15), 1.90, "看一眼轻自动车", _on_van)


func _setup_portals() -> void:
	portals = PortalHost.new()
	portals.name = "PortalHost"
	add_child(portals)
	portals.bind(SCENE_ID, PORTALS, player, hud, hub)


func _setup_audio() -> void:
	_rain = _looping_player("res://audio/rain_loop.wav", -14.0)
	_hum = _looping_player("res://audio/drone_loop.wav", -38.0)


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


# ---------------------------------------------------------------- 西口

## 西口的路牌。牌面朝东（玩家沿街往西走时正对着它），比触发线早 0.7m，
## 读到字的时候还来得及回头；再往前一步才会切场景。
func _build_west_exit() -> void:
	var g := K.group(self, "WestExit")
	var steel := K.toon(Color("#4e535b"), {"shade": 0.55, "rim": 0.28, "line": 0.006})
	var green := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.007})
	var px := Town.X0 + 1.4
	var pz := 0.45

	K.cyl(g, 0.05, 2.55, Vector3(px, Town.WALK_Y + 1.275, pz), steel, Vector3.ZERO, 8)
	K.box(g, Vector3(0.07, 0.62, 1.5), Vector3(px, Town.WALK_Y + 2.3, pz), green)
	K.label_cjk(g, "国道 17 号", Vector3(px + 0.045, Town.WALK_Y + 2.42, pz), 0.15,
		Color("#f3dfb4"), Vector3(0, 90, 0))
	K.label(g, "HOSHIMI SERVICE STATION", Vector3(px + 0.045, Town.WALK_Y + 2.24, pz), 0.058,
		Color("#d7c8a8"), Vector3(0, 90, 0))
	K.label(g, "WEST  ·  300m", Vector3(px + 0.045, Town.WALK_Y + 2.12, pz), 0.05,
		Color("#9fb0a2"), Vector3(0, 90, 0))
	K.sphere(g, 0.05, Vector3(px, Town.WALK_Y + 2.62, pz), K.glow(Color("#ffd9a2"), 2.0),
		Vector3.ZERO, 8, 1.0, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffd0a0")
	l.light_energy = 0.5
	l.omni_range = 3.4
	l.position = Vector3(px, Town.WALK_Y + 2.3, pz)
	g.add_child(l)
	K.plane(g, Vector2(1.8, 1.8), Vector3(px, Town.WALK_Y + 0.007, pz),
		K.wet(Color("#ffcf9a"), 0.05), Vector3.ZERO, false)

	CollisionLayout.pillar(g, Vector3(px, Town.WALK_Y + 1.275, pz), 0.06, 2.55)


## 被转场送回来：黑幕由转场层负责淡开，这里只负责解锁和点灯。
## 到达后 1.2s 内不认西口：转场层自己还要约 1s 才淡完，
## 这段时间里再触发一次会撞上一个还没消失的层。
func _on_arrival() -> void:
	hud.fade_in(0.0)
	player.camera.current = true
	player.input_locked = false
	door.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_on_zone_changed("west")
	hud.toast("国道的水汽还挂在衣服上。商店街的灯，从街尾一路亮过来。", 4.5)
	portals.arm(1.2)


## 转场开始后锁住当前场景。SceneRouter 和 LetterTransition 各会调一次，重复调用无害。
func lock_for_transition() -> void:
	player.input_locked = true
	if portals != null:
		portals.enabled = false
	if hub != null:
		hub.enabled = false
	if hud != null:
		hud.hide_prompt()
		hud.hide_toast()


# ---------------------------------------------------------------- 开场

func _play_intro() -> void:
	player.input_locked = true
	player.camera.current = false

	_intro_cam = Camera3D.new()
	_intro_cam.name = "IntroCam"
	_intro_cam.fov = INTRO_FOV
	_intro_cam.near = 0.1
	_intro_cam.far = 300.0
	add_child(_intro_cam)
	_intro_cam.current = true

	var from := Transform3D(
		Basis.looking_at((INTRO_LOOK - INTRO_FROM_POS).normalized(), Vector3.UP),
		INTRO_FROM_POS)
	var to: Transform3D = player.camera.global_transform
	var to_fov: float = player.camera.fov
	_intro_cam.global_transform = from

	hud.fade_in(1.4)

	var cam := _intro_cam
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.tween_method(
		func(v: float) -> void: cam.global_transform = from.interpolate_with(to, v),
		0.0, 1.0, 3.8
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# FOV 和机位一起收，最后一帧才和游戏机位完全一致，避免结尾跳一下
	_intro_tween.tween_method(
		func(v: float) -> void: cam.fov = lerpf(INTRO_FOV, to_fov, v),
		0.0, 1.0, 3.8
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_intro_tween.finished.connect(func() -> void: _on_intro_finished(cam))


## 跳过开场（探针 / 调试）。补间必须 kill，否则几秒后它会再跑一次收尾，
## 把已经解开的输入重新锁上。
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


func _on_intro_finished(cam: Camera3D) -> void:
	if is_instance_valid(cam):
		cam.queue_free()
	_intro_cam = null
	_intro_tween = null
	player.camera.current = true
	player.input_locked = false
	door.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("WASD 移动 · 沿街往西，尽头是便利店和国道", 4.0)


# ---------------------------------------------------------------- 每帧

func _process(delta: float) -> void:
	if player == null:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var p: Vector3 = player.global_position
	var zone := _zone_at(p)
	if zone != _zone:
		_on_zone_changed(zone)

	# 雨声：街上比店里响一档；店里的低频压缩机声更近
	var rain_db := -26.0 if _inside else -14.0
	var hum_db := -24.0 if _inside else -38.0
	if _rain != null:
		_rain.volume_db = lerpf(_rain.volume_db, rain_db, 1.0 - exp(-1.6 * delta))
	if _hum != null:
		_hum.volume_db = lerpf(_hum.volume_db, hum_db, 1.0 - exp(-1.6 * delta))


## 公开给探针：当前区域。不要读 _zone。
func zone() -> String:
	return _zone


func is_inside() -> bool:
	return _inside


func _zone_at(p: Vector3) -> String:
	if INTERIOR.has_point(p):
		return "in"
	# 便利店西墙之外整段都算西口：牌子、路灯、出镇的触发线都在这一带
	if p.x < Town.X0 + 2.4:
		return "west"
	if p.z >= Town.ROAD_Z1:
		return "south"
	if p.z >= Town.ROAD_Z0:
		return "road"
	if p.x > Town.GATE_X - 3.0:
		return "gate"
	if p.x < 5.6:
		return "storefront"
	return "north"


func _on_zone_changed(zone: String) -> void:
	var was_inside := _inside
	_zone = zone
	_inside = zone == "in"

	match zone:
		"in":
			hud.set_zone("店内 · HOSHI MART", true)
		"road":
			hud.set_zone("马路 · 车行道", false)
		"south":
			hud.set_zone("商店街 · 南侧", false)
		"gate":
			hud.set_zone("商店街 · 东口", true)
		"storefront":
			hud.set_zone("便利店 · 门前", true)
		"west":
			hud.set_zone("商店街 · 西口", true)
		_:
			hud.set_zone("商店街 · 北侧", false)

	if _shooting:
		return
	if _inside == was_inside:
		return
	if _inside:
		player.set_camera_profile(CAM_IN["dist"], CAM_IN["height"], CAM_IN["fov"],
			CAM_IN["shoulder"], 3.6)
		hud.toast("暖光、冷柜的嗡嗡声，还有收银台上那本翻到一半的杂志。", 4.2)
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


func _on_ramen() -> void:
	_play_at(Vector3(7.7, 1.6, -0.5), Sfx.tap(), -9.0)
	hud.toast("暖帘后面飘出猪骨汤和葱花的气味。锅里还咕嘟着。", 4.2)


func _on_izakaya() -> void:
	hud.toast("红灯笼在雨里轻轻晃。木牌上写着：本日 焼き鳥  ¥180。", 4.2)


func _on_vending() -> void:
	_play_at(Vector3(13.6, 1.1, -0.3), Sfx.tap(), -7.0)
	hud.toast("投币口亮着。你买了一罐热咖啡，罐身暖得刚好能捂手。", 4.2)


func _on_laundry() -> void:
	hud.toast("四台滚筒还在转。玻璃上蒙着一层水汽，看不清里面是谁的衣服。", 4.2)


func _on_tobacco() -> void:
	hud.toast("卷帘门拉下来一半，柜台里只亮着一盏小灯。老板大概在后面看报。", 4.2)


func _on_koban() -> void:
	hud.toast("交番门口的青灯亮着。玻璃窗里贴着一张「落とし物」的告示。", 4.2)


func _on_sento() -> void:
	hud.toast("暖帘上印着一个「ゆ」。推门出来的人带出一阵热汽和肥皂味。", 4.2)


func _on_coffee() -> void:
	hud.toast("喫茶店的窗里亮着三盏吊灯。有人在靠窗的位置翻一本旧杂志。", 4.2)


func _on_bus() -> void:
	hud.toast("末班车 00:12。站牌下面只有一把收起来的伞。", 4.2)


func _on_park() -> void:
	hud.toast("口袋公园里那棵树被雨洗得发亮。长椅上落着几只麻雀。", 4.2)


func _on_van() -> void:
	hud.toast("轻自动车的雨刷停在一半，后座堆着纸箱和一把折叠伞。", 4.2)


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

func _only_shot() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(7)
	return ""


func _take_shots() -> void:
	_shooting = true
	portals.enabled = false
	player.input_locked = false
	door.enabled = false
	door.set_open(true, true)
	hub.enabled = false
	hud.fade_in(0.0)
	hud.hide_prompt()
	DirAccess.make_dir_recursive_absolute("res://shots")

	var specs := [
		{"name": "street_a_spawn", "player": true, "pos": SPAWN, "face": -PI * 0.5,
			"yaw": 90.0, "pitch": -0.10, "dist": 4.4, "height": 1.45, "fov": 52.0,
			"shoulder": 0.30, "exp": EXPOSE_OUT},
		{"name": "street_b_gate", "free": Vector3(29.6, 5.6, 3.0),
			"look": Vector3(14.0, 2.4, 2.2), "fov": 70.0, "exp": EXPOSE_OUT},
		{"name": "street_c_north", "free": Vector3(20.8, 2.7, 4.4),
			"look": Vector3(10.2, 2.2, -0.7), "fov": 56.0, "exp": EXPOSE_OUT},
		{"name": "street_d_south", "free": Vector3(12.8, 2.8, 1.6),
			"look": Vector3(12.5, 2.0, 7.0), "fov": 70.0, "exp": EXPOSE_OUT},
		{"name": "street_e_store", "free": Vector3(11.6, 4.4, 5.6),
			"look": Vector3(0.8, 1.1, -1.6), "fov": 46.0, "exp": EXPOSE_OUT},
		{"name": "street_f_gate_west", "free": Vector3(19.6, 3.4, 2.4),
			"look": Vector3(27.2, 4.5, 2.3), "fov": 52.0, "exp": EXPOSE_OUT},
		{"name": "street_g_inside", "player": true, "pos": Vector3(0.72, 0.25, -3.05),
			"face": PI, "yaw": 6.0, "pitch": -0.04, "dist": 1.95, "height": 1.55,
			"fov": 66.0, "shoulder": 0.52, "exp": EXPOSE_IN},
	]
	var only := _only_shot()

	for s in specs:
		if only != "" and s["name"] != only:
			continue
		env.tonemap_exposure = s["exp"]
		if s.has("free"):
			await _shot_free(s["name"], s["free"], s["look"], s["fov"])
			continue
		player.global_position = s["pos"]
		player.face(s["face"])
		player.set_view(s["yaw"], s["pitch"])
		player.snap_camera(s["dist"], s["height"], s["fov"], s["shoulder"])
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])

	get_tree().quit()


func _shot_free(shot_name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.current = true
	player.camera.current = false
	player.visible = false
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % shot_name)
	print("saved ", shot_name)
	cam.queue_free()
	player.visible = true
	player.camera.current = true
