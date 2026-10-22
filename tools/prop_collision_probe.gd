extends Node
## 商店街街具碰撞：验证「看得见的东西真的挡人」。
##
##   ./tools/run.sh --headless prop_collision_probe
##
## 以前这里只有建筑和杆件有碰撞，自行车、长凳、圆桌、花盆、菜单牌都能穿过去。
## 每一组都从物件外侧起步、朝它直走；断言停在物件前面，而不是穿过去。
## 这些坐标和 shop_row.gd / town.gd 里的视觉坐标一一对应，改视觉时记得同步
## town_collision.gd 的 _shop_props / _street_furniture。

var world: Node3D
var player: CharacterBody3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	world = (load("res://scenes/hoshi_street.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	world.skip_intro()
	player = world.player
	await get_tree().physics_frame

	# ---- 东口并排停放的自行车（三辆，正面挡住） ----
	await _goto(Vector3(27.8, 0.17, 0.62))
	player.set_view(90.0, -0.1)
	await _step("往东口自行车走", 0.5, ["move_forward"])
	_check("东口自行车挡人（x > 27.35）", player.global_position.x > 27.35)

	# ---- 拉面店门口的自行车（斜停） ----
	await _goto(Vector3(7.3, 0.17, 0.18))
	player.set_view(90.0, -0.1)
	await _step("往拉面店自行车走", 0.5, ["move_forward"])
	_check("拉面店自行车挡人（x > 6.9）", player.global_position.x > 6.9)

	# ---- 巴士站牌立杆 ----
	await _goto(Vector3(25.45, 0.0, 4.4))
	player.set_view(180.0, -0.1)
	await _step("往巴士站牌走", 0.6, ["move_forward"])
	_check("巴士站牌挡人（z < 5.2）", player.global_position.z < 5.2)

	# ---- 洗衣店门口长凳 ----
	await _goto(Vector3(14.8, 0.17, 1.3))
	player.set_view(0.0, -0.1)
	await _step("往洗衣店长凳走", 0.6, ["move_forward"])
	_check("洗衣店长凳挡人（z > 0.5）", player.global_position.z > 0.5)

	# ---- 喫茶店门外小圆桌 ----
	await _goto(Vector3(14.85, 0.16, 5.05))
	player.set_view(180.0, -0.1)
	await _step("往喫茶店小桌走", 0.5, ["move_forward"])
	_check("喫茶店小桌挡人（z < 5.4）", player.global_position.z < 5.4)

	# ---- 民居门口花盆 ----
	await _goto(Vector3(3.4, 0.17, 5.3))
	player.set_view(180.0, -0.1)
	await _step("往花盆走", 0.5, ["move_forward"])
	_check("门口花盆挡人（z < 5.75）", player.global_position.z < 5.75)

	# ---- 居酒屋菜单牌（斜放） ----
	await _goto(Vector3(12.05, 0.17, 1.2))
	player.set_view(0.0, -0.1)
	await _step("往居酒屋菜单牌走", 0.5, ["move_forward"])
	_check("菜单牌挡人（z > 0.75）", player.global_position.z > 0.75)

	# ---- 钱汤门口木桶 ----
	await _goto(Vector3(6.75, 0.16, 5.1))
	player.set_view(180.0, -0.1)
	await _step("往钱汤木桶走", 0.5, ["move_forward"])
	_check("木桶挡人（5.1 < z < 5.6）",
		player.global_position.z > 5.1 and player.global_position.z < 5.6)

	# ---- 便利店门前：伞架 ----
	# 这组是 store_walk 与 hoshi_street 共用 Props.storefront，
	# 但碰撞入口不同；漏掉时人能从伞架 / 垃圾桶里直接穿过去。
	await _goto(Vector3(1.22, 0.17, 0.6))
	player.set_view(0.0, -0.1)
	await _step("往便利店伞架走", 0.4, ["move_forward"])
	_check("便利店伞架挡人（z > 0）", player.global_position.z > 0.0)

	# ---- 便利店门前：三个垃圾桶 ----
	await _goto(Vector3(2.6, 0.17, -0.52))
	player.set_view(90.0, -0.1)
	await _step("往便利店垃圾桶走", 0.4, ["move_forward"])
	_check("便利店垃圾桶挡人（x > 2.38）", player.global_position.x > 2.38)

	# ---- 便利店门前：A 字招牌 ----
	await _goto(Vector3(2.8, 0.17, 0.6))
	player.set_view(90.0, -0.1)
	await _step("往便利店招牌走", 0.5, ["move_forward"])
	_check("便利店立式招牌挡人（x > 2.44）", player.global_position.x > 2.44)

	# ---- 便利店门前：自行车 ----
	# 车斜停 62°。必须沿车身长轴、从车头正面走：从侧面撞胶囊会顺着斜面滑开，
	# 看起来像「没挡住」，其实是擦边绕过去了。断言用车心距离，兼防原地不动。
	var bike_center := Vector2(-1.02, 0.5)
	await _goto(Vector3(-2.433, 0.17, -0.251))
	player.set_view(242.0, -0.1)
	await _step("往便利店自行车车头走", 0.5, ["move_forward"])
	var away := Vector2(player.global_position.x, player.global_position.z).distance_to(bike_center)
	_check("便利店自行车挡人（0.9 < 距车心 < 1.3）", away > 0.9 and away < 1.3)

	print("\n==== prop_collision_probe: %d passed, %d failed ====" % [_pass, _fail])
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
