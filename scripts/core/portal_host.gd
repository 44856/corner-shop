extends Node
## 一个出口在本场景里的「手」：走路触发盒、E 键交互点都挂在这里。
## 它知道门在哪，但不知道门通向哪——目的地与启用条件全在 WorldLinks / GameState。
##
## 禁用出口默认连提示都不出现（show_blocked=false）：玩家不该看见一个按了没反应的点。
## 只有确实需要「告诉玩家为什么不行」时才在数据里打开 show_blocked。

## 站在触发盒里时每秒最多敲两次路由，避免挡在门口刷出成串的 blocked 信号。
const WALK_RETRY_MS := 500
const BLOCKED_TOAST_MS := 900

signal blocked(portal_id: StringName, text: String)

var enabled := true

var _scene_id: StringName = &""
var _portals: Array = []
var _player: CharacterBody3D
## 用 Node + call()：PortalHost 不该为了调一个 toast 去 preload 整个 HUD。
var _hud: Node
var _hub: Node
var _show_blocked: Dictionary = {}
var _armed_until_msec := 0
var _last_walk_msec: Dictionary = {}
var _last_blocked_msec := 0


func _ready() -> void:
	if not SceneRouter.portal_blocked.is_connected(_on_portal_blocked):
		SceneRouter.portal_blocked.connect(_on_portal_blocked)


func bind(scene_id: StringName, portals: Array, player: CharacterBody3D,
		hud: CanvasLayer, hub: Node) -> void:
	_scene_id = scene_id
	_portals = portals
	_player = player
	_hud = hud
	_hub = hub

	for portal in _portals:
		var portal_id: StringName = portal.get("id", &"")
		for trig in portal.get("triggers", []):
			if String(trig.get("kind", "")) != "interact":
				continue
			_register_interact(portal, trig)
			if bool(trig.get("show_blocked", portal.get("show_blocked", false))):
				_show_blocked[portal_id] = true


## 切场景后给一小段冷却。人落在触发盒附近时，不该一落地又被送走。
func arm(seconds: float) -> void:
	_armed_until_msec = Time.get_ticks_msec() + int(maxf(seconds, 0.0) * 1000.0)


func _register_interact(portal: Dictionary, trig: Dictionary) -> void:
	if _hub == null:
		return
	var portal_id: StringName = portal.get("id", &"")
	_hub.call("add_target",
		trig.get("pos", Vector3.ZERO),
		float(trig.get("radius", 1.6)),
		String(trig.get("prompt", "走过去")),
		_use.bind(portal_id),
		_interact_gate.bind(portal_id),
		int(trig.get("priority", 0)))


func _process(_delta: float) -> void:
	if not enabled or _player == null or not is_instance_valid(_player):
		return
	if SceneRouter.is_transitioning() or bool(_player.get("input_locked")):
		return

	var now := Time.get_ticks_msec()
	if now < _armed_until_msec:
		return

	var p: Vector3 = _player.global_position
	var flat := Vector2(p.x, p.z)
	for portal in _portals:
		var portal_id: StringName = portal.get("id", &"")
		if now - int(_last_walk_msec.get(portal_id, -WALK_RETRY_MS)) < WALK_RETRY_MS:
			continue
		for trig in portal.get("triggers", []):
			if String(trig.get("kind", "")) != "walk":
				continue
			var rect: Rect2 = trig.get("rect", Rect2())
			if not rect.has_point(flat):
				continue
			_last_walk_msec[portal_id] = now
			SceneRouter.use_portal(_scene_id, portal_id)
			break


## gate 只决定「这个交互点要不要出提示」，不执行切换。
## 路由禁用且 show_blocked=false 时返回 false，提示就会消失。
func _interact_gate(portal_id: StringName) -> bool:
	if not enabled or SceneRouter.is_transitioning():
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	if bool(_player.get("input_locked")) or Time.get_ticks_msec() < _armed_until_msec:
		return false
	if SceneRouter.resolve_portal(_scene_id, portal_id).get("allowed", false):
		return true
	return bool(_show_blocked.get(portal_id, false))


func _use(portal_id: StringName) -> void:
	if not enabled:
		return
	SceneRouter.use_portal(_scene_id, portal_id)


func _on_portal_blocked(scene_id: StringName, portal_id: StringName,
		text: String) -> void:
	if scene_id != _scene_id:
		return
	blocked.emit(portal_id, text)

	if not bool(_show_blocked.get(portal_id, false)) or text.strip_edges() == "":
		return
	var now := Time.get_ticks_msec()
	if now - _last_blocked_msec < BLOCKED_TOAST_MS:
		return
	_last_blocked_msec = now
	if _hud != null:
		_hud.call("toast", text, 2.6)
