extends Node
## 剧情状态。纯数据，不持有节点引用——
## 一旦这里开始存「门开了吗」，场景重载后状态就会和实际几何脱节。

signal story_node_changed(from: StringName, to: StringName)

const DEFAULT_NODE := &"ep1_store"

## 允许的剧情节点。写死在这里是为了让拼错的节点名当场失败，
## 而不是静默落进「没有路由覆盖」的黑洞。
const KNOWN_NODES := {
	&"ep1_store": "雨夜便利店",
	&"ep2_station": "加油站 · 逢魔前",
	&"ep2_dusk": "加油站 · 逢魔时",
	&"ep3_grassland": "异世界草原",
}

var _story_node: StringName = DEFAULT_NODE
var _flags: Dictionary = {}


func story_node() -> StringName:
	return _story_node


func is_known_node(id: StringName) -> bool:
	return KNOWN_NODES.has(id)


func set_story_node(id: StringName) -> bool:
	if not is_known_node(id):
		push_warning("GameState: 未知剧情节点 %s" % id)
		return false
	if id == _story_node:
		return true
	var from := _story_node
	_story_node = id
	story_node_changed.emit(from, id)
	return true


func has_flag(id: StringName) -> bool:
	return _flags.get(id, false)


func set_flag(id: StringName, on: bool = true) -> void:
	if on:
		_flags[id] = true
	else:
		_flags.erase(id)


func reset() -> void:
	var from := _story_node
	_story_node = DEFAULT_NODE
	_flags.clear()
	if from != _story_node:
		story_node_changed.emit(from, _story_node)
