extends Node
## 商店街回归测试：不渲染，只跑移动 / 交互 / 碰撞。
##
##   ./tools/run.sh --headless street_probe
##
## 这条探针只回答三个问题：
##   1. 人是不是真的出生在街区东侧、面朝西；
##   2. 整条街是不是走得通，路缘能不能上下（16cm 靠隐形斜面）；
##   3. 两排店面的墙是不是真的挡得住，自动门和交互提示有没有接上。
##
## 便利店内部那组交互（冷柜 / 货架 / 铃 / 猫）在 walk_probe 里已经覆盖，
## 这里只验证「从新街区的街上能走进同一家店」。

var world: Node3D
var player: CharacterBody3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	world = (load("res://scenes/hoshi_street.tscn") as PackedScene).instantiate()
	add_child(world)
	# 开场推镜 3.8s + 余量
	await get_tree().create_timer(4.8).timeout

	player = world.player
	player.input_locked = false

	# ---- 1. 出生点：东口、人行道、面朝西 ----
	var p0: Vector3 = player.global_position
	_check("出生在场景右侧（x > 20）", p0.x > 20.0)
	_check("出生在人行道上（y ≈ 0.16）", absf(p0.y - 0.16) < 0.06)
	_check("出生区域是东口牌楼", world.zone() == "gate")

	# ---- 2. 沿北人行道往西走 ----
	# 出生点正西 x=22.8 有一根电线杆（z=1.62），直着走会撞上。
	# 先横向让开半米，测的是「街走得通」，不是「人能穿柱」。
	await _goto(Vector3(p0.x, p0.y, 0.95))
	player.set_view(90.0, -0.1)
	await _step("沿街往西走", 1.4, ["move_forward"])
	var p1: Vector3 = player.global_position
	_check("往西走了 3m 以上", p1.x < p0.x - 3.0)
	_check("仍踩在北人行道上（y ≈ 0.16）", absf(p1.y - 0.16) < 0.06)
	_check("没有越过北侧路缘（z < 2.07）", p1.z < 2.07)

	# ---- 3. 拉面店交互 ----
	await _goto(Vector3(7.70, 0.17, 0.55))
	await get_tree().process_frame
	await get_tree().process_frame
	_check("拉面店暖帘有交互提示", world.hub.focused_text() == "掀开暖帘")

	# ---- 4. 店面挡得住 ----
	player.set_view(0.0, -0.1)
	await _step("往拉面店墙里走", 0.85, ["move_forward"])
	_check("被北排店面挡住（z > −0.7）", player.global_position.z > -0.7)

	# ---- 5. 过马路：北路缘下去、南路缘上来 ----
	# 走斑马线中段 x=24.15：x=22.8 是电线杆、x=23.65 和 25.05 是候车亭立柱，
	# 贴着它们过街会被街具挡住 —— 那是正常碰撞，不是路缘上不来。
	await _goto(Vector3(24.15, 0.0, 3.50))
	await get_tree().process_frame
	_check("站在车行道上，区域是 road", world.zone() == "road")
	await _goto(Vector3(24.15, 0.17, 1.60))
	player.set_view(180.0, -0.1)
	await _step("沿斑马线过马路", 1.9, ["move_forward"])
	var p2: Vector3 = player.global_position
	_check("走到南人行道（z > 5.2）", p2.z > 5.2)
	_check("爬上南侧 16cm 路缘（y ≈ 0.16）", absf(p2.y - 0.16) < 0.06)

	# ---- 6. 南排墙挡得住 ----
	await _goto(Vector3(16.0, 0.17, 5.4))
	player.set_view(180.0, -0.1)
	await _step("往喫茶店墙里挤", 0.85, ["move_forward"])
	_check("被南排店面挡住（z < 6.1）", player.global_position.z < 6.1)

	# ---- 7. 候车亭交互 ----
	await _goto(Vector3(24.35, 0.17, 4.60))
	await get_tree().process_frame
	await get_tree().process_frame
	_check("候车亭有交互提示", world.hub.focused_text() == "看看末班车时刻")

	# ---- 8. 从新街区走进同一家便利店 ----
	await _goto(Vector3(0.35, 0.17, 0.95))
	player.set_view(0.0, -0.1)
	await _step("走进店门", 1.5, ["move_forward"])
	await get_tree().process_frame
	_check("自动门被感应打开", world.door.is_open())
	_check("人已经进店（区域 in）", world.is_inside() or world.zone() == "in")
	_check("脚下是店内地面（y ≈ 0.25）", absf(player.global_position.y - 0.25) < 0.07)

	# ---- 9. 打开的门不会把相机顶飞（弹簧臂仍可用） ----
	_check("相机仍在前方（spring_length > 1.0）", player.cam_rig.spring_length > 1.0)

	print("\n==== street_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _goto(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


func _step(label: String, seconds: float, actions: Array) -> void:
	print("· ", label)
	for a in actions:
		Input.action_press(a)
	await get_tree().create_timer(seconds).timeout
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label, "  pos=", player.global_position)
	else:
		_fail += 1
		print("  [FAIL] ", label, "  pos=", player.global_position)
