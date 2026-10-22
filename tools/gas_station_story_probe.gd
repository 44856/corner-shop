extends Node
## 加油站剧情：三颗子弹 / 逢魔时 / 撞击 / 死亡状态机。
##
##   ./tools/run.sh --headless gas_station_story_probe
##
## 只读公开接口（R2）：story.phase() / beat_count() / radio_heard() / ...
## 对话用真的 E 事件走 interaction_hub，而不是直接调回调 ——
## 「按 E 能不能触发」本身就是这条剧情链的一部分。
##
## 时间被 set_speed(12) 压短；但擦身车本身按物理帧走，不受 speed 影响，
## 所以「等它开过去」的那一段仍然是真实时间，不能把断言写在该帧之前。

var world: Node3D
var player
var story

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame

	world = (load("res://scenes/gas_station.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame

	world.skip_intro()
	player = world.player
	story = world.story
	story.set_speed(12.0)
	story.set_transition_enabled(false)
	await get_tree().physics_frame

	_check("剧情从 WALK 开始", story.phase() == "walk")
	_check("三颗子弹都还没触发", story.beat_count() == 0)
	_check("货车和司机还在场", not story.parked_cleared())

	# ---- 子弹 1：柜台里的收音机 ----
	# 这个位置同时在售货机（0.85m）和柜台（1.5m）的目标里，
	# 收音机（1.14m）能弹出来靠的是 priority，不是距离。
	await _goto(Vector3(8.2, 0.17, 10.55))
	await _frames(4)
	_check("收音机提示弹出", world.hub.focused_text() == "听柜台里的收音机")
	await _press_e()
	await _frames(3)
	_check("收音机被听过", story.radio_heard())
	_check("计数器 = 1", story.beat_count() == 1)
	_check("只听完收音机还不会变天", story.phase() == "walk")

	# ---- 子弹 2：东侧货车旁的司机 ----
	await _goto(Vector3(21.55, 0.17, 5.55))
	await _frames(4)
	_check("司机提示弹出", world.hub.focused_text() == "和司机说句话")
	await _press_e()
	await _frames(3)
	_check("和司机说过话", story.driver_talked())
	_check("计数器 = 2", story.beat_count() == 2)
	_check("两颗子弹还不会变天", story.phase() == "walk")

	# ---- 子弹 3：第一次踏上国道，擦身车 ----
	await _goto(Vector3(18.0, 0.02, 2.2))
	await _frames(6)
	_check("踏上国道触发擦身车", story.near_miss_done())
	_check("计数器 = 3", story.beat_count() == 3)

	# 变天要等擦身车真的开过去（_after_beat 里的等待），别抢跑。
	await _until(func() -> bool: return story.phase() == "dusk", 6.0)
	_check("三颗子弹后进入逢魔时", story.phase() == "dusk")
	_check("逢魔时不能回商店街", not story.return_allowed())
	_check("逢魔时没有新建第三份输入注册", InputMap.has_action("interact"))

	# 变天时玩家可能还站在国道上。等黑幕流程走完，先退回前场，
	# 否则 DUSK_GRACE 一过，撞车会在这里就把探针打断。
	await _until(func() -> bool: return not bool(player.input_locked), 3.0)
	await _goto(Vector3(18.0, 0.17, 6.4))
	await _frames(3)
	_check("逢魔时撤掉了东侧货车和司机", story.parked_cleared())

	# ---- 撞车：缓冲结束后再次踏上国道 ----
	await get_tree().create_timer(3.6).timeout
	await _goto(Vector3(18.0, 0.02, 2.2))
	await _frames(4)
	_check("缓冲后踏上国道触发撞车", story.crash_started())
	_check("进入 CRASH", story.phase() == "crash")

	# 车灯逼近时角色要有一个看得见的侧扑，而不是站着等撞。
	await _until(func() -> bool: return story.dodged(), 6.0)
	_check("撞车前角色做出了闪避", story.dodged())

	await _until(func() -> bool: return story.death_started(), 8.0)
	_check("货车真的撞上了（进入 DEATH）", story.death_started())
	_check("闪避产生了可见的侧向位移", story.dodge_shift() > 0.35)
	var clearance: float = story.impact_clearance()
	_check("撞击时车头停在角色表面（无穿模）", clearance >= -0.02 and clearance <= 0.10)
	_check("撞停后的货车有静态碰撞（死亡段走不进去）", story.crash_truck_solid())
	_check("死亡段接管环境声", story.audio_override())
	_check("死亡段不能回商店街", story.blocks_return())

	await _until(func() -> bool: return story.finished(), 12.0)
	_check("死亡演出走完", story.finished())
	_check("终态是 DONE", story.phase() == "done")
	_check("探针没有真的切走场景", get_tree().current_scene == null or get_tree().current_scene.name != "Grassland")

	print("\n==== gas_station_story_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _goto(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


func _press_e() -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_E
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_E
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _until(cond: Callable, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		if bool(cond.call()):
			return
		await get_tree().process_frame
		left -= get_process_delta_time()
	if not bool(cond.call()):
		print("  [wait] 超时：", cond)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label, "  phase=", story.phase() if story != null else "-",
			"  beats=", story.beat_count() if story != null else "-")
