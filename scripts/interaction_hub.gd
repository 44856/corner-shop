extends Node
## 交互中枢：谁离得最近就给谁出提示，按 E 触发谁。
##
## 没用 Area3D：这个场景的交互目标都是静止的、数量很少，
## 每帧算几个水平距离比铺一堆触发器便宜，也不会因为碰撞层配错而静默失效。
## 和 dog.gd 的「距离 + 按键」是同一套思路，只是把「谁最合适」集中到了一处，
## 免得两个目标同时弹提示。

const Hud := preload("res://scripts/hud.gd")

## 视线容差（米）。提示点常常就落在物体内部（货架 / 冷柜的提示点），
## 射线会先打到那个物体自己 —— 不能把它当成「隔着墙」。
const SIGHT_TOLERANCE := 0.9

var enabled := true

var _player: Node3D
var _hud: CanvasLayer
var _targets: Array = []
var _focus: Dictionary = {}


func _ready() -> void:
	_ensure_action()


## 注册一个交互点。pos 是世界坐标（提示不会显示在物体上，靠屏幕下方的 HUD）。
func bind(player: Node3D, hud: CanvasLayer) -> void:
	_player = player
	_hud = hud


## gate 是可选条件（比如「必须站在店里」），返回 false 时这个点不参与提示。
func add_target(pos: Vector3, radius: float, text: String, cb: Callable,
		gate: Callable = Callable()) -> void:
	_targets.append({"pos": pos, "radius": radius, "text": text, "cb": cb, "gate": gate})


# ---------------------------------------------------------------- 对外查询
#
# 测试与外部模块**只能**通过下面两个方法读状态。
# 不要再碰 _focus / _targets —— 它们是内部结构，改个字段名不该打断调用方。

## 当前是否有聚焦目标。
func has_focus() -> bool:
	return not _focus.is_empty()


## 当前聚焦目标的提示文案；没有聚焦时返回空串。
func focused_text() -> String:
	return "" if _focus.is_empty() else String(_focus["text"])


## E 键在代码里注册；如果工程里已经有 interact（草原的狗用的是 F），
## 就把它补上 E，让两边的肌肉记忆一致。
func _ensure_action() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var has_key := false
	for e in InputMap.action_get_events("interact"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode in [KEY_E, KEY_F]:
			has_key = true
	if not has_key:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("interact", ev)


func _process(_delta: float) -> void:
	if not enabled or _player == null or not is_instance_valid(_player):
		return
	# 开场 / 过场锁输入时不弹提示
	if bool(_player.get("input_locked")):
		_clear_focus()
		return

	var p: Vector3 = _player.global_position
	var best: Dictionary = {}
	var best_d := INF
	for t in _targets:
		var gate: Callable = t.get("gate", Callable())
		if gate.is_valid() and not bool(gate.call()):
			continue
		var pos: Vector3 = t["pos"]
		var d := pos - p
		d.y = 0.0
		var dist := d.length()
		if dist > float(t["radius"]) or dist >= best_d:
			continue
		# 距离够了还得「看得见」。只按水平距离算的话，站在后巷贴着空调外机
		# 就能隔着东墙按到店里的服务铃 —— 那不是够得着，是穿墙。
		if not _has_sight(p, pos):
			continue
		best = t
		best_d = dist

	if best.is_empty():
		_clear_focus()
		return

	_focus = best
	if _hud != null:
		_hud.show_prompt(best["text"])


func _clear_focus() -> void:
	if _focus.is_empty():
		return
	_focus = {}
	if _hud != null:
		_hud.hide_prompt()


## 从胸口打一条射线到提示点，中间隔着东西就返回 false。
## 射线打到的位置离目标点还有 SIGHT_TOLERANCE 以上，才算被挡住 ——
## 目标点本身常常就落在物体里（货架 / 台面），射线先打到它自己是正常的。
## 公开版：probe 只准读公开接口，别让测试盯着内部实现。
func has_sight(from: Vector3, to: Vector3) -> bool:
	return _has_sight(from, to)


func _has_sight(from: Vector3, to: Vector3) -> bool:
	var eye := from + Vector3(0.0, 1.1, 0.0)
	var q := PhysicsRayQueryParameters3D.create(eye, to)
	q.exclude = [_player.get_rid()]
	q.collide_with_areas = false
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var d_hit := eye.distance_to(hit["position"])
	return d_hit >= eye.distance_to(to) - SIGHT_TOLERANCE


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _focus.is_empty():
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		# 先转身面向交互对象，再触发反馈。放在中枢里做，
		# 四个交互点（冷柜 / 货架 / 服务铃 / 猫）就都自动有了，不用各写一遍。
		if _player.has_method("look_at_point"):
			_player.look_at_point(_focus["pos"])
		var cb: Callable = _focus["cb"]
		if cb.is_valid():
			cb.call()
