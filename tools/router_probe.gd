extends Node
## 场景路由与剧情状态的纯数据回归。
##
##   ./tools/run.sh --headless router_probe
##
## 不切场景、不建 3D 节点：转场一旦真的跑起来会把探针自己换掉。
## 钉住的是「同一道门在不同剧情节点下是否允许、指向哪、落在哪个 spawn」，
## 以及本地 PORTALS 与中央 ROUTES 有没有各自漂移。

const Links := preload("res://scripts/core/world_links.gd")
const HoshiStreet := preload("res://scripts/hoshi_street.gd")
const GasStation := preload("res://scripts/gas_station.gd")

var _pass := 0
var _fail := 0


func _ready() -> void:
	_check_scene_registry()
	_check_default_routes()
	_check_story_overrides()
	_check_denials()
	_check_redirect_capability()
	_check_route_integrity()
	_check_local_portals()
	_check_game_state()
	_check_router()

	print("\n==== router_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- 表本身

func _check_scene_registry() -> void:
	for scene_id in Links.SCENES:
		var path := Links.scene_path(scene_id)
		_check("场景 %s 已登记且文件存在（%s）" % [scene_id, path],
			path != "" and ResourceLoader.exists(path))


func _check_default_routes() -> void:
	var out := Links.resolve(&"hoshi_street", &"west_gate", &"ep1_store")
	_check("默认：商店街西口允许通行", out.get("allowed", false))
	_check("默认：西口去加油站", out.get("scene") == &"gas_station")
	_check("默认：落在加油站东侧人行道", out.get("spawn") == &"east_sidewalk")
	var spec: Dictionary = out.get("transition", {})
	_check("默认：西口带 LETTER 转场文案", spec.get("subtitle", "") == "SERVICE STATION")
	_check("默认：西口把剧情推进到 ep2_station",
		out.get("set_story_node") == &"ep2_station")

	var back := Links.resolve(&"gas_station", &"east_exit", &"ep1_store")
	_check("默认：加油站东口允许通行", back.get("allowed", false))
	_check("默认：东口回商店街", back.get("scene") == &"hoshi_street")
	_check("默认：落在商店街西口", back.get("spawn") == &"west_gate")
	_check("默认：反向出口不改剧情节点（避免倒回第二幕）",
		back.get("set_story_node", &"") == &"")

	_check("ep2_station 下两个出口仍可走",
		Links.resolve(&"hoshi_street", &"west_gate", &"ep2_station").get("allowed", false)
		and Links.resolve(&"gas_station", &"east_exit", &"ep2_station").get("allowed", false))


func _check_story_overrides() -> void:
	for node in [&"ep2_dusk", &"ep3_grassland"]:
		var west := Links.resolve(&"hoshi_street", &"west_gate", node)
		_check("%s：商店街西口禁用" % node, not west.get("allowed", true))
		_check("%s：西口禁用时给出理由" % node, String(west.get("text", "")) != "")

		var east := Links.resolve(&"gas_station", &"east_exit", node)
		_check("%s：加油站东口禁用" % node, not east.get("allowed", true))
		_check("%s：东口禁用时给出理由" % node, String(east.get("text", "")) != "")


func _check_denials() -> void:
	var unknown_portal := Links.resolve(&"hoshi_street", &"north_gate", &"ep1_store")
	_check("未知出口被拒绝", not unknown_portal.get("allowed", true))
	_check("未知出口有说明", String(unknown_portal.get("text", "")) != "")

	var no_routes := Links.resolve(&"grassland", &"west_gate", &"ep1_store")
	_check("没有路由的场景被拒绝", not no_routes.get("allowed", true))

	var unknown_scene := Links.resolve(&"nowhere", &"west_gate", &"ep1_store")
	_check("未登记场景被拒绝", not unknown_scene.get("allowed", true))


## 用合成表验证「同一出口换剧情节点就换目的地」和「* 通配兜底」。
## 这两条是架构承诺，不能只靠现有数据碰巧没覆盖到。
func _check_redirect_capability() -> void:
	var redirect_table := {
		&"hoshi_street": {
			&"west_gate": {
				"default": {"scene": &"gas_station", "spawn": &"east_sidewalk"},
				"routes": {
					&"ep3_grassland": {"scene": &"grassland", "spawn": &"default"},
				},
			},
		},
	}
	var redirected := Links.resolve(&"hoshi_street", &"west_gate", &"ep3_grassland",
		redirect_table)
	_check("同一出口可改指向另一个场景",
		redirected.get("allowed", false) and redirected.get("scene") == &"grassland")
	var fallback := Links.resolve(&"hoshi_street", &"west_gate", &"ep1_store",
		redirect_table)
	_check("未命中的剧情节点回落到 default",
		fallback.get("allowed", false) and fallback.get("scene") == &"gas_station")

	var wildcard_table := {
		&"hoshi_street": {
			&"west_gate": {
				"default": {"scene": &"gas_station", "spawn": &"east_sidewalk"},
				"routes": {&"*": {"enabled": false, "text": "路上有水。"}},
			},
		},
	}
	var wildcard := Links.resolve(&"hoshi_street", &"west_gate", &"ep2_station",
		wildcard_table)
	_check("未列出的节点命中 * 通配",
		not wildcard.get("allowed", true) and wildcard.get("text") == "路上有水。")


# ---------------------------------------------------------------- 表与场景的一致性

func _check_route_integrity() -> void:
	for scene_id in Links.ROUTES:
		_check("路由表里的 %s 已在 SCENES 注册" % scene_id, Links.SCENES.has(scene_id))
		var portals: Dictionary = Links.ROUTES[scene_id]
		for portal_id in portals:
			var portal: Dictionary = portals[portal_id]
			var overrides: Dictionary = portal.get("routes", {})
			for key in overrides:
				_check("%s/%s 覆盖键 %s 是已知节点或通配" % [scene_id, portal_id, key],
					key == &"*" or GameState.KNOWN_NODES.has(key))

			_check_route_target("%s/%s default" % [scene_id, portal_id],
				portal.get("default", {}))
			for key in overrides:
				var merged: Dictionary = portal.get("default", {}).duplicate()
				merged.merge(overrides[key], true)
				_check_route_target("%s/%s @%s" % [scene_id, portal_id, key], merged)


func _check_route_target(label: String, route: Dictionary) -> void:
	if not bool(route.get("enabled", true)):
		_check("%s 禁用但带提示文案" % label, String(route.get("text", "")) != "")
		return
	var target: StringName = route.get("scene", &"")
	_check("%s 指向已登记场景" % label, Links.SCENES.has(target))
	var spawn: StringName = route.get("spawn", &"default")
	_check("%s 的落点 %s 在目标场景 SPAWNS 里" % [label, spawn],
		_spawns_for(target).has(spawn))
	var next_node: StringName = route.get("set_story_node", &"")
	_check("%s 的 set_story_node %s 是已知剧情节点" % [label, next_node],
		next_node == &"" or GameState.KNOWN_NODES.has(next_node))


func _spawns_for(scene_id: StringName) -> Dictionary:
	match scene_id:
		&"hoshi_street":
			return HoshiStreet.SPAWNS
		&"gas_station":
			return GasStation.SPAWNS
	return {}


## 本地 PORTALS（门在哪）与中央 ROUTES（门通向哪）必须一一对应。
## 少一边就是静默失效：要么有门没路由，要么有路由没门。
func _check_local_portals() -> void:
	_check("商店街 SCENE_ID 与路由键一致", HoshiStreet.SCENE_ID == &"hoshi_street")
	_check("加油站 SCENE_ID 与路由键一致", GasStation.SCENE_ID == &"gas_station")
	_check_portal_pair(&"hoshi_street", HoshiStreet.PORTALS)
	_check_portal_pair(&"gas_station", GasStation.PORTALS)


func _check_portal_pair(scene_id: StringName, portals: Array) -> void:
	var route_ids: Array = Links.ROUTES.get(scene_id, {}).keys()
	var local_ids := _portal_ids(portals)
	for id in route_ids:
		_check("%s 的路由出口 %s 在本地 PORTALS 里" % [scene_id, id], local_ids.has(id))
	for id in local_ids:
		_check("%s 的本地出口 %s 有路由" % [scene_id, id], route_ids.has(id))


func _portal_ids(portals: Array) -> Array:
	var ids: Array = []
	for portal in portals:
		ids.append(portal.get("id", &""))
	return ids


# ---------------------------------------------------------------- GameState

func _check_game_state() -> void:
	GameState.reset()
	_check("默认剧情节点是 ep1_store", GameState.story_node() == GameState.DEFAULT_NODE)
	_check("拒绝未知剧情节点", not GameState.set_story_node(&"ep99"))
	_check("拒绝之后状态不变", GameState.story_node() == GameState.DEFAULT_NODE)

	var seen: Array = []
	var on_change := func(from: StringName, to: StringName) -> void:
		seen.append([from, to])
	GameState.story_node_changed.connect(on_change)
	_check("接受已知剧情节点", GameState.set_story_node(&"ep2_dusk"))
	_check("切换发出一次信号",
		seen.size() == 1 and seen[0][1] == &"ep2_dusk")
	GameState.story_node_changed.disconnect(on_change)

	GameState.set_flag(&"probe_flag")
	_check("flag 可写", GameState.has_flag(&"probe_flag"))
	GameState.set_flag(&"probe_flag", false)
	_check("flag 可清", not GameState.has_flag(&"probe_flag"))

	GameState.set_story_node(&"ep3_grassland")
	GameState.reset()
	_check("reset 回到默认节点", GameState.story_node() == GameState.DEFAULT_NODE)


# ---------------------------------------------------------------- SceneRouter

func _check_router() -> void:
	_check("拒绝绑定未登记场景", not SceneRouter.bind_scene(&"nowhere"))
	_check("可以绑定商店街", SceneRouter.bind_scene(&"hoshi_street"))
	_check("绑定后记录当前场景",
		SceneRouter.current_scene_id() == &"hoshi_street")
	_check("初始不在转场中", not SceneRouter.is_transitioning())

	_check("stage_arrival 拒绝未登记场景",
		not SceneRouter.stage_arrival(&"nowhere", &"default"))
	_check("stage_arrival 写入到达上下文",
		SceneRouter.stage_arrival(&"gas_station", &"east_sidewalk",
			{"via_portal": &"west_gate", "mode": &"probe"}))
	_check("has_arrival 能看到上下文", SceneRouter.has_arrival())

	var arrival := SceneRouter.consume_arrival()
	_check("到达上下文保留来源",
		arrival.get("from_scene") == &"hoshi_street"
		and arrival.get("to_scene") == &"gas_station")
	_check("到达上下文保留落点", arrival.get("spawn") == &"east_sidewalk")
	_check("到达上下文保留出口", arrival.get("via_portal") == &"west_gate")
	_check("到达上下文取一次就清空",
		not SceneRouter.has_arrival() and SceneRouter.consume_arrival().is_empty())

	GameState.set_story_node(&"ep2_dusk")
	var blocked: Array = []
	var on_blocked := func(scene_id: StringName, portal_id: StringName, text: String) -> void:
		blocked.append({"scene": scene_id, "portal": portal_id, "text": text})
	SceneRouter.portal_blocked.connect(on_blocked)
	_check("禁用出口的 use_portal 返回 false",
		not SceneRouter.use_portal(&"hoshi_street", &"west_gate"))
	SceneRouter.portal_blocked.disconnect(on_blocked)
	_check("被拦截时发出 portal_blocked",
		blocked.size() == 1 and blocked[0]["portal"] == &"west_gate"
		and String(blocked[0]["text"]) != "")
	_check("被拦截不会进入转场", not SceneRouter.is_transitioning())
	GameState.reset()

	var allowed := SceneRouter.resolve_portal(&"hoshi_street", &"west_gate")
	_check("resolve_portal 与中央路由一致",
		allowed.get("allowed", false) and allowed.get("scene") == &"gas_station")

	_check("goto 拒绝未登记场景", not SceneRouter.goto(&"nowhere", &"default"))
	_check("goto 拒绝未知剧情节点",
		not SceneRouter.goto(&"gas_station", &"east_sidewalk",
			{"set_story_node": &"ep99"}))
	_check("失败的 goto 不进入转场", not SceneRouter.is_transitioning())
	_check("use_portal 拒绝未绑定的场景",
		not SceneRouter.use_portal(&"gas_station", &"east_exit"))


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label)
