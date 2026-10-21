extends Node
## 自动行走测试：不渲染，只驱动物理，验证「人真的能走进店里」。
##
## 手动试玩一次当然也能看出来，但这是回归测试：
## 以后改门的坐标、改货架宽度、改门槛高度，跑一条命令就能知道有没有把路堵死。
##
##   ./Godot_v4.7.2-stable_linux.x86_64 --headless --path . res://tools/walk_probe.tscn

var world: Node3D
var player: CharacterBody3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	world = (load("res://scenes/store_walk.tscn") as PackedScene).instantiate()
	add_child(world)
	# 等开场推镜走完（3.6s）+ 一点余量
	await get_tree().create_timer(4.6).timeout

	player = world.player
	player.input_locked = false
	# 这条测试走到马路上去是为了验路缘；车祸事件由 truck_probe 单独测，
	# 否则半路被车撞飞，后面几条断言全部作废
	world.truck_event.auto_trigger = false
	player.global_position = Vector3(0.35, 0.17, 0.95)
	await get_tree().physics_frame

	await _step("走到门口", 1.25, ["move_forward"])
	var door_open: bool = world.door.is_open()
	_check("自动门被感应打开", door_open)
	_check("人已经跨过门槛（z < −1.12）", player.global_position.z < -1.12)
	_check("脚下踩在店内地面（y ≈ 0.25）", absf(player.global_position.y - 0.25) < 0.06)

	await _step("向右让开货架", 0.30, ["move_right"])
	await _step("沿东侧过道走到冷柜前", 1.15, ["move_forward"])
	_check("能走到冷柜前（z < −4.4）", player.global_position.z < -4.4)

	var hub: Node = world.hub
	_check("冷柜交互提示已弹出", hub._focus.is_empty() == false)
	_check("提示文案是「拉开冷柜」",
		not hub._focus.is_empty() and String(hub._focus["text"]) == "拉开冷柜")

	await _step("退回店堂", 1.2, ["move_backward"])
	await _step("挪回门洞正中", 0.30, ["move_left"])
	await _step("走出店门", 1.4, ["move_backward"])
	await get_tree().create_timer(1.2).timeout
	_check("离开后门重新关上", world.door.is_open() == false)
	_check("人退回到室外（z > −0.9）", player.global_position.z > -0.9)

	# 马路 → 人行道：16cm 的路缘靠隐形斜面，这段专门用来防它失效
	await _step("走回人行道", 0.85, ["move_forward"])
	_check("能重新爬上 16cm 路缘（踩在人行道上）",
		player.global_position.y > 0.13 and player.global_position.y < 0.19
		and player.global_position.z > 0.3)

	print("\n==== walk_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## 按住若干动作 seconds 秒
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
