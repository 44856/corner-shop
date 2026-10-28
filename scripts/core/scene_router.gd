extends Node
## 场景切换的唯一入口。任何「从这里去那里」都必须经过 use_portal / goto，
## 场景自己只负责触发（走到门口、按 E），不负责目的地。
## 连开场演出 opening_flow 也在落幕后走这里，代价是它要多等一段共享的字母屏。
##
## 这里只做五件事：查路由、锁旧场景、切掉旧场景的声音、播转场、
## 把「从哪来、落在哪个 spawn」交给新场景。剧情、提示文案、禁用的理由
## 全部不在这里判断。

const Links := preload("res://scripts/core/world_links.gd")
const LetterTransition := preload("res://scripts/letter_transition.gd")

signal portal_blocked(scene_id: StringName, portal_id: StringName, text: String)
signal arrival_finished(scene_id: StringName, spawn: StringName)

enum Phase { IDLE, LEAVING }

var _phase: int = Phase.IDLE
var _current_scene: StringName = &""
var _arrival: Dictionary = {}


# ---------------------------------------------------------------- 场景侧接口

## 场景 _ready 里登记自己是谁；到达上下文里的 from_scene 就取自这里。
func bind_scene(scene_id: StringName) -> bool:
	if not Links.SCENES.has(scene_id):
		push_warning("SceneRouter: 未注册的场景 %s" % scene_id)
		return false
	_current_scene = scene_id
	return true


func current_scene_id() -> StringName:
	return _current_scene


func is_transitioning() -> bool:
	return _phase != Phase.IDLE


# ---------------------------------------------------------------- 到达上下文

func has_arrival() -> bool:
	return not _arrival.is_empty()


## 新场景取走「我是怎么来的」。取一次就清空，避免停留期间反复触发入场逻辑。
func consume_arrival() -> Dictionary:
	if _arrival.is_empty():
		return {}
	var snapshot := _arrival.duplicate()
	_arrival.clear()
	return snapshot


## 只写到达上下文、不切场景。给 probe 和调试传送用。
func stage_arrival(scene_id: StringName, spawn: StringName,
		opts: Dictionary = {}) -> bool:
	if not Links.SCENES.has(scene_id):
		push_warning("SceneRouter: stage_arrival 收到未注册的场景 %s" % scene_id)
		return false
	if _phase != Phase.IDLE:
		return false
	_arrival = _arrival_context(scene_id, spawn, opts)
	return true


# ---------------------------------------------------------------- 切换

func resolve_portal(scene_id: StringName, portal_id: StringName) -> Dictionary:
	return Links.resolve(scene_id, portal_id, GameState.story_node())


func use_portal(scene_id: StringName, portal_id: StringName) -> bool:
	if _phase != Phase.IDLE:
		return false
	if scene_id != _current_scene:
		push_warning("SceneRouter: %s 未绑定，却想使用出口 %s" % [scene_id, portal_id])
		return false

	var result := resolve_portal(scene_id, portal_id)
	if not result.get("allowed", false):
		portal_blocked.emit(scene_id, portal_id, str(result.get("text", "")))
		return false

	return goto(result["scene"], result["spawn"], {
		"via_portal": portal_id,
		"transition": result.get("transition", {}),
		"set_story_node": result.get("set_story_node", &""),
	})


func goto(scene_id: StringName, spawn: StringName, opts: Dictionary = {}) -> bool:
	if _phase != Phase.IDLE:
		return false

	var path := Links.scene_path(scene_id)
	if path == "":
		push_error("SceneRouter: 没有登记场景 %s 的路径" % scene_id)
		return false

	# 旧场景可能还在自己起转场（P0 尚未收口）。两层转场叠在一起会把输入锁死。
	# 必须放在改剧情节点之前：失败的切换不该留下任何状态变更。
	if get_tree().root.has_node("LetterTransition"):
		push_warning("SceneRouter: 已有转场层，忽略这次切换")
		return false

	var next_node: StringName = opts.get("set_story_node", &"")
	if next_node != &"" and not GameState.set_story_node(next_node):
		push_error("SceneRouter: 路由要求切到未知剧情节点 %s，已中止" % next_node)
		return false

	_arrival = _arrival_context(scene_id, spawn, opts)
	_phase = Phase.LEAVING

	# 加载屏期间不放旧场景的声音：雨、低频、一次性音效、3D 发射器一起收掉。
	# 新场景的 _setup_audio() 在 change_scene 之后才跑，不会被这一刀误伤。
	# 放在所有校验之后——被拒绝的 goto 不该改变任何状态，包括正在响的声音。
	AudioBus.cut_for_transition()

	var scene := get_tree().current_scene
	if scene != null and scene.has_method("lock_for_transition"):
		scene.call("lock_for_transition")

	_run_transition(scene_id, path, opts.get("transition", {}), spawn)
	return true


func _arrival_context(scene_id: StringName, spawn: StringName,
		opts: Dictionary) -> Dictionary:
	return {
		"from_scene": _current_scene,
		"to_scene": scene_id,
		"spawn": spawn,
		"via_portal": opts.get("via_portal", &""),
		"mode": opts.get("mode", &"route"),
		"meta": opts.get("meta", {}),
		"story_node": GameState.story_node(),
	}


func _run_transition(scene_id: StringName, path: String, spec: Dictionary,
		spawn: StringName) -> void:
	var transition = _make_transition(spec)
	get_tree().root.add_child(transition)
	await transition.play(path)

	_phase = Phase.IDLE
	# 新场景的 _ready 跑在 play() 里面，此时它已经取走过 arrival 了。
	# 这里再清一次只是兜底：没登记到达逻辑的场景不会留下一份过期上下文。
	_arrival.clear()
	arrival_finished.emit(scene_id, spawn)


## 目前只有「字母加载屏」一种。style 字段先留着，第二套转场再接。
func _make_transition(spec: Dictionary):
	if spec.has("style") and spec["style"] != "letter":
		push_warning("SceneRouter: 未知转场样式 %s，退回 letter" % spec["style"])

	var transition = LetterTransition.new()
	transition.name = "LetterTransition"
	if spec.has("title"):
		transition.title_text = str(spec["title"])
	if spec.has("subtitle"):
		transition.subtitle_text = str(spec["subtitle"])
	if spec.has("footer"):
		transition.footer_text = str(spec["footer"])
	if spec.has("accent"):
		var accent_value: Variant = spec["accent"]
		if accent_value is Color:
			transition.accent = accent_value
		elif accent_value is String:
			transition.accent = Color.from_string(accent_value, transition.accent)
	return transition
