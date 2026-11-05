extends Node
## 草原场景交互回归：验证「狗与守卫都能用 E 说话、提示会正确出/收、区域标签跟着走」。
##
## 和 tools/walk_probe.gd 一样，这是给人跑的回归测试 —— 以后动 HUD、动交互中枢、
## 挪守卫位置或改对话剧本，跑一条命令就知道有没有把交互弄坏：
##
##   ./tools/run.sh --headless grassland_probe
##   ./tools/check.sh          # 连同便利店那一组一起跑
##
## 注意：按键必须用 parse_input_event 注入。
## Input.action_press() 只改动作状态、不产生事件，_unhandled_input 收不到，
## 用它测会「怎么按都没反应」，很容易被误判成交互坏了。

const SCENE := "res://scenes/grassland.tscn"
const TownPlan := preload("res://scripts/town_plan.gd")

var _pass := 0
var _fail := 0

var _scene: Node
var _player: CharacterBody3D
var _dog: Node3D
var _hub: Node
var _hud: CanvasLayer
var _dlg: Node


func _ready() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate()
	add_child(_scene)
	# 醒来补间 2 秒 + 余量
	await get_tree().create_timer(2.6).timeout

	_player = _scene.player
	_dog = _scene.dog
	_hub = _scene.hub
	_hud = _scene.hud
	_dlg = _scene.dialogue

	_check("HUD 已创建", _hud != null)
	_check("交互中枢已创建", _hub != null)
	# 交互点：狗 1 + 每个 NPC 各 1（守卫 / 公会接待 / 店主都走这条）+ 公会两块任务板。
	# 不写死总数：冒险者区每开一家店就多一个店主，写死的话每次开店都要回来改这条。
	# 中枢没有公开的计数接口，这里直接读内部数组 —— 断言的是「数量对不对」，
	# 不是「内部结构长什么样」，字段改名的时候这里一起改就行。
	_check("每个 NPC 各占一个交互点（狗 + %d NPC + 2 块任务板）" % _scene.guards.size(),
		_hub.get("_targets").size() == _scene.guards.size() + 3)
	_check("狗把按键与头顶提示交给了中枢", _dog.self_interaction == false)

	# ---- 区域标签
	# 3e13c6b 起，进城之后的区域名改由 TownPlan.zone_at() 按分区规划算：
	# x = 0 落在主街上，所以 z=330 / z=440 都报「贯城大街」。
	# 原来那两个点名（城门内 · 方石广场 / 广场 · 大理石）属于老的 z 轴分段，
	# 已经被四个象限的分区取代，采样点没挪，只是地名变了。
	await _zone_at(10.0, "草原")
	await _zone_at(200.0, "官道")
	await _zone_at(330.0, "贯城大街")
	await _zone_at(440.0, "贯城大街")
	# 公会不在主街上，单独判一次：站在世界中心（规划常量），
	# 不再硬编码坐标 —— 3e13c6b 把公会从西南角搬到冒险者区并转 90°，硬编码那次就是这么断的
	_player.global_position = Vector3(TownPlan.GUILD_CENTER.x, 0.05, TownPlan.GUILD_CENTER.z)
	await get_tree().process_frame
	await get_tree().process_frame
	var guild_zone := String(_hud.get("_zone_chip").text)
	_check("公会大厅区域=%s" % "冒险者公会 · 大厅", guild_zone == "冒险者公会 · 大厅",
		"" if guild_zone == "冒险者公会 · 大厅" else "实际 " + guild_zone)

	# ---- 狗
	_player.global_position = _dog.global_position + Vector3(0.0, 0.05, 1.1)
	await get_tree().create_timer(0.35).timeout
	_check("走近狗弹出提示", _hud.prompt_alpha() > 0.5)

	await _press_interact()
	_check("按 E 与狗开始对话", _dlg.is_active())
	_check("对话期间中枢停用", _hub.enabled == false)
	await get_tree().create_timer(0.3).timeout
	_check("对话期间提示收起", _hud.prompt_alpha() < 0.5)
	_check("狗对话能走完", await _finish_dialogue())
	_check("对话结束中枢恢复", _hub.enabled == true)

	# ---- 守卫
	var guard_node: Node3D = null
	for g in _scene.guards:
		if String(g["dialogue"]).ends_with("guard_isaac_01.txt"):
			guard_node = g["node"]
	_check("找到艾萨克节点", guard_node != null)
	if guard_node != null:
		_player.global_position = guard_node.global_position + Vector3(1.0, 0.05, 1.8)
		await get_tree().create_timer(0.35).timeout
		_check("走近守卫弹出提示", _hud.prompt_alpha() > 0.5)
		await _press_interact()
		_check("按 E 与守卫开始对话", _dlg.is_active())
		_check("守卫台词首句说话人是守卫", String(_dlg.current_who()) == "守卫")
		_check("守卫对话能走完", await _finish_dialogue())

	# ---- 走开
	_player.global_position = Vector3(0.0, 0.05, 150.0)
	await get_tree().create_timer(0.3).timeout
	_check("离开后提示收起", _hud.prompt_alpha() < 0.5)

	await _check_guard_stance()

	print("\n==== grassland_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## 守卫站姿与微动回归。
##
## 这几条守的是「别退回 A-pose 假人」：
##   - 手臂收到身侧：A-pose 时手离骨盆 0.59m，站姿后约 0.29m
##   - 脚踩在地上：掰姿势时最容易把脚抬离地面，回头调角度很容易忘
##   - 上半身在动：呼吸/巡视断了的话，人立刻又变成立牌
##   - 脚不跟着动：微动一旦碰到骨盆或腿，脚就会在地上滑
func _check_guard_stance() -> void:
	var rows: Array = []
	for g in _scene.guards:
		var npc: Node3D = g["node"]
		var nm := String(npc.name)
		# 只调公开的 pose_probe()：骨骼命名与骨架字段都留在 npc_guard.gd 内部，
		# 探针这边不该知道（AGENTS.md R2 —— 读私有字段会让重构静默打断测试）
		var pose: Dictionary = npc.call("pose_probe")
		_check("%s 有骨架" % nm, not pose.is_empty())
		if pose.is_empty():
			continue
		rows.append([nm, npc])

		var pelvis: Vector3 = pose["pelvis"]
		var hand: Vector3 = pose["hand_r"]
		var sep := Vector2(hand.x - pelvis.x, hand.z - pelvis.z).length()
		_check("%s 手臂收到身侧（离骨盆 %.2fm）" % [nm, sep], sep < 0.45,
			"A-pose 是 0.59m，说明 STANCES 没生效")

		var ankle: Vector3 = pose["ankle_l"]
		_check("%s 脚踩在地面（踝高 %.2fm）" % [nm, ankle.y],
			ankle.y > 0.05 and ankle.y < 0.35, "脚离地或埋进地里，检查膝盖补偿")

	if rows.is_empty():
		return

	# 采样 3 秒：巡视周期约 18 秒，3 秒足够跨出 sin 峰值的平坦段
	var head0: Array = []
	var foot0: Array = []
	for r in rows:
		var pose: Dictionary = (r[1] as Node3D).call("pose_probe")
		head0.append(pose["head_dir"])
		foot0.append(pose["ankle_l"])
	await get_tree().create_timer(3.0).timeout

	for i in rows.size():
		var nm: String = rows[i][0]
		var pose: Dictionary = (rows[i][1] as Node3D).call("pose_probe")
		var h: Vector3 = pose["head_dir"]
		var moved := (h - (head0[i] as Vector3)).length()
		_check("%s 上半身在动（头偏移 %.3f）" % [nm, moved], moved > 0.004,
			"微动没跑起来，守卫退化成静态模型")

		var slide := ((pose["ankle_l"] as Vector3) - (foot0[i] as Vector3)).length()
		_check("%s 脚没跟着滑（%.4fm）" % [nm, slide], slide < 0.001,
			"微动碰到了骨盆或腿，脚在地上滑")


func _zone_at(z: float, expect: String) -> void:
	_player.global_position = Vector3(0.0, 0.05, z)
	await get_tree().process_frame
	await get_tree().process_frame
	var got := String(_hud.get("_zone_chip").text)
	_check("z=%d 区域=%s" % [int(z), expect], got == expect,
		"" if got == expect else "实际 " + got)


## 注入一次真实按键：按下 → 一帧 → 抬起
func _press_interact() -> void:
	var down := InputEventAction.new()
	down.action = "interact"
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


## 一帧一帧翻，直到对话结束。返回是否在 40 帧内走完
func _finish_dialogue() -> bool:
	var n := 0
	while _dlg.is_active() and n < 40:
		_dlg.advance()
		await get_tree().process_frame
		n += 1
	return not _dlg.is_active()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if not detail.is_empty() else "")
