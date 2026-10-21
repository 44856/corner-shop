extends Node
## 交互中枢：谁离得最近就给谁出提示，按 E 触发谁。
##
## 没用 Area3D：这个场景的交互目标都是静止的、数量很少，
## 每帧算几个水平距离比铺一堆触发器便宜，也不会因为碰撞层配错而静默失效。
## 和 dog.gd 的「距离 + 按键」是同一套思路，只是把「谁最合适」集中到了一处，
## 免得两个目标同时弹提示。

const Hud := preload("res://scripts/hud.gd")

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


func add_target(pos: Vector3, radius: float, text: String, cb: Callable) -> void:
	_targets.append({"pos": pos, "radius": radius, "text": text, "cb": cb})


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
		var pos: Vector3 = t["pos"]
		var d := pos - p
		d.y = 0.0
		var dist := d.length()
		if dist <= float(t["radius"]) and dist < best_d:
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


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _focus.is_empty():
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		var cb: Callable = _focus["cb"]
		if cb.is_valid():
			cb.call()
