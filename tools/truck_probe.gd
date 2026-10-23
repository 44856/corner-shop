extends Node
## 车祸事件回归测试：不渲染，只跑状态机与物理。
##
##   ./Godot_v4.7.2-stable_linux.x86_64 --headless --path . res://tools/truck_probe.tscn
##
## 断言链（对应需求里的每一条）：
##   1. 没进过店，站在马路上不触发
##   2. 进店 → 出店 → 下马路 → 触发
##   3. 货车生成在台面之外，且材质带着台面裁剪参数
##   4. 车头追上人 → 判定命中，人被击飞
##   5. 黑场之后人回到路缘，输入锁解除
##   6. 车开出台面另一侧后被回收，事件不再重复触发

var world: Node3D
var player: CharacterBody3D
var event                       # truck_event.gd

var _pass := 0
var _fail := 0


func _ready() -> void:
	world = (load("res://scenes/store_walk.tscn") as PackedScene).instantiate()
	add_child(world)
	# 等开场推镜走完（3.6s）+ 一点余量
	await get_tree().create_timer(4.6).timeout

	player = world.player
	event = world.truck_event
	player.input_locked = false

	# ---- 1. 没进过店，站在马路中间：不该有车 ----
	player.global_position = Vector3(0.4, 0.0, 3.9)
	await get_tree().create_timer(0.8).timeout
	_check("没进过店 → 站在马路中间也不触发", event.has_fired() == false)

	# ---- 2. 真的走进店里再出来 ----
	player.global_position = Vector3(0.7, 0.25, -3.2)
	await get_tree().create_timer(0.25).timeout
	_check("进店被记录（区域判定走的是真代码）", event.store_visited())

	# ---- 2b. 刚踏下路缘不算：要走到路中间 ----
	player.global_position = Vector3(0.35, 0.0, 2.5)
	await get_tree().create_timer(0.8).timeout
	_check("刚踏下路缘（z=2.5）→ 不触发", event.has_fired() == false)

	player.global_position = Vector3(0.35, 0.17, 1.2)
	player.face(0.0)
	await get_tree().physics_frame
	await _step("走到马路中间", 0.9, ["move_backward"])
	_check("走到路中间 → 事件触发", event.has_fired())

	# ---- 3. 车从台面外开进来 ----
	var spawned: bool = await _wait_until(func() -> bool:
		return event.spawned_truck() != null and is_instance_valid(event.spawned_truck()), 3.0)
	_check("货车已生成", spawned)
	if spawned:
		var x: float = event.spawned_truck().global_position.x
		_check("生成点在台面之外（|x| > 5.6）", absf(x) > 5.6)
		_check("车道在马路范围内（z 3.0~4.6）",
			event.spawned_truck().global_position.z > 3.0 and event.spawned_truck().global_position.z < 4.6)
		_check("材质带台面裁剪参数", _clip_ok(event.spawned_truck()))
		_check("车灯有可见光束（锥体 ×2）", _beam_count(event.spawned_truck()) >= 2)
		# Label3D 不吃裁剪着色器：车还在台面外时，车身上的字必须藏起来，
		# 否则会孤零零飘在底座外面（曾经真的飘过）
		await get_tree().process_frame
		_check("台面外的车不显示车身文字", _labels_hidden(event.spawned_truck()))

	# ---- 4. 撞上 ----
	var hit: bool = await _wait_until(func() -> bool: return event.hit_landed(), 4.0)
	_check("车头追上人 → 判定命中", hit)
	if hit:
		# 击飞是物理推的：采一小段时间里的最高点，别赌某一帧
		var peak := player.global_position.y
		for i in 24:
			await get_tree().physics_frame
			peak = maxf(peak, player.global_position.y)
		_check("人被击飞（离地 %.2fm）" % peak, peak > 0.45)

	# ---- 5. 复位 ----
	# 用「输入锁解除」当复位信号：它是黑场结束、人已经被放回路缘的那一帧
	var back: bool = await _wait_until(func() -> bool: return player.input_locked == false, 4.0)
	_check("黑场后人被放回出生点（输入锁解除）", back)
	_check("位置回到出生点（z ≈ 0.95）", absf(player.global_position.z - 0.95) < 0.25)
	_check("人站在人行道高度（y ≈ 0.16）", absf(player.global_position.y - 0.16) < 0.08)

	# ---- 6. 车开走、事件不重复 ----
	var gone: bool = await _wait_until(func() -> bool: return event.is_done(), 4.0)
	_check("车开出台面后被回收", gone)
	_check("事件不会重复触发", event.is_done())

	print("\n==== truck_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## 车身材质必须挂着「台面裁剪」——这是需求里「超出平台不渲染」的落点。
## 顺带核对裁剪盒子和台面尺寸一致，不然会出现一条看不见的裁切缝。
##
## 递归整棵树：光柱挂在灯头 pivot 下面，只查直接子节点会漏掉它们。
func _clip_ok(truck: Node3D) -> bool:
	var found := 0
	var stack: Array = [truck]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if not (c is MeshInstance3D):
				continue
			var m := (c as MeshInstance3D).material_override as ShaderMaterial
			if m == null:
				continue
			found += 1
			if m.get_shader_parameter("clip_on") != true:
				return false
			var lo: Vector3 = m.get_shader_parameter("clip_min")
			var hi: Vector3 = m.get_shader_parameter("clip_max")
			if absf(lo.x + 5.6) > 0.001 or absf(hi.x - 5.6) > 0.001:
				return false
			if absf(lo.z + 5.6) > 0.001 or absf(hi.z - 5.6) > 0.001:
				return false
	return found > 0


## 车身文字必须全部隐藏（车在台面外时）
func _labels_hidden(truck: Node3D) -> bool:
	var n := 0
	var stack: Array = [truck]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
			if c is Label3D:
				n += 1
				if (c as Label3D).visible:
					return false
	return n > 0


## 光束网格 = headlamp 着色器、非光池模式的那些 MeshInstance
func _beam_count(truck: Node3D) -> int:
	var n := 0
	var stack: Array = [truck]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
			if not (c is MeshInstance3D):
				continue
			var m := (c as MeshInstance3D).material_override as ShaderMaterial
			if m == null or m.shader == null:
				continue
			if m.shader.resource_path.ends_with("headlamp.gdshader") \
					and m.get_shader_parameter("pool") != true:
				n += 1
	return n


func _wait_until(pred: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if pred.call():
			return true
		await get_tree().process_frame
	return false


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
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label, "  pos=", player.global_position if player != null else "?")
