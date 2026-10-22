extends Node
## 加油站场景：碰撞 / 路缘 / 交互 / 「被转场送来」的落地状态。
##
##   ./tools/run.sh --headless gas_station_probe
##
## 场景是程序化生成的，视觉坐标改了碰撞很容易忘记跟；这里用真走的方式
## 钉住三组会直接影响可玩性的东西：
##   - 加油机岛台 / 小卖亭真的挡人（相机贴着也不会穿进去）；
##   - 国道的 16cm 路缘靠隐形斜面能走上去（没有自动上台阶）；
##   - 顶棚下的提示与区域判定用的是同一套坐标。
##
## 最后一条是转场契约：root 上挂着 LetterTransition 时，场景必须
## 跳过自己的黑场并直接解锁输入 —— 否则「转场淡出 → 又黑一下」。

var world: Node3D
var player: CharacterBody3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	# root 在场景初始化期间处于「正在装子节点」状态，直接 add_child 会失败。
	# 等一帧再挂，否则下面的到达断言会因为没有转场层而假通过。
	await get_tree().process_frame

	# 模拟被转场送来：root 上先挂一个同名层，再实例化场景。
	var overlay := CanvasLayer.new()
	overlay.name = "LetterTransition"
	get_tree().root.add_child(overlay)

	world = (load("res://scenes/gas_station.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame

	_check("被转场送来时跳过自己的黑场（输入已解锁）", not world.player.input_locked)
	_check("落点在东侧人行道、回程触发线以西",
		world.player.global_position.x < 28.0 and absf(world.player.global_position.y - 0.17) < 0.08)
	overlay.queue_free()

	world.skip_intro()
	player = world.player
	await get_tree().physics_frame

	# ---- 1 号油机岛台：从北侧正面走上去，应该被挡住 ----
	await _goto(Vector3(12.2, 0.17, 6.8))
	player.set_view(180.0, -0.1)
	await _step("往 1 号油机走", 0.8, ["move_forward"])
	_check("油机岛台挡人（z < 8.45）", player.global_position.z < 8.45)
	_check("确实走到了岛台前（z > 7.9）", player.global_position.z > 7.9)

	# ---- 小卖亭：整块实心，柜台窗只是画上去的 ----
	await _goto(Vector3(8.5, 0.17, 10.5))
	player.set_view(90.0, -0.1)
	await _step("往小卖亭走", 0.8, ["move_forward"])
	_check("小卖亭挡人（x > 7.0）", player.global_position.x > 7.0)
	_check("确实走到了墙前（x < 8.0）", player.global_position.x < 8.0)

	# ---- 国道 → 前场：16cm 路缘靠隐形斜面 ----
	await _goto(Vector3(19.25, 0.02, 2.2))
	player.set_view(180.0, -0.1)
	await _step("从国道走进前场", 1.1, ["move_forward"])
	_check("能爬上路缘（z > 4.3）", player.global_position.z > 4.3)
	_check("站在 16cm 前场上（y ≈ 0.16）",
		player.global_position.y > 0.13 and player.global_position.y < 0.19)

	# ---- 顶棚区域 / 油枪提示 ----
	await _goto(Vector3(12.2, 0.17, 7.6))
	for i in 3:
		await get_tree().process_frame
	_check("顶棚下被识别为 canopy", world.zone() == "canopy")
	_check("油枪提示弹出", world.hub.focused_text() == "拿起油枪")

	# ---- 柜台提示：隔着窗，但目标点在窗外 0.12m，视线不该被墙挡 ----
	await _goto(Vector3(8.5, 0.17, 9.6))
	for i in 3:
		await get_tree().process_frame
	_check("柜台提示弹出（隔着窗也能交互）", world.hub.focused_text() == "敲敲柜台")

	# ---- 转场锁：把玩家和交互一起收起来 ----
	world.lock_for_transition()
	_check("锁定后玩家不再接受输入", bool(world.player.input_locked))
	_check("锁定后交互中枢停用", world.hub.enabled == false)

	print("\n==== gas_station_probe: %d passed, %d failed ====" % [_pass, _fail])
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
		print("  [ OK ] ", label, "  pos=", player.global_position if player != null else "-")
	else:
		_fail += 1
		print("  [FAIL] ", label, "  pos=", player.global_position if player != null else "-")
