extends RefCounted
## 世界连接表。全部是数据：哪个场景、哪个出口、在哪个剧情节点通向哪里。
## 之所以单独成表而不是写在各场景里：出口本身（触发盒、提示点）是场景私有的，
## 但「通向哪里」是全局叙事事实。拆开之后，同一道门在不同章节里禁用或改指向
## 只需要改这里，不必去动任何一个场景脚本。
##
## 路由键的查找顺序：精确剧情节点 → "*" 通配 → default。
## 覆盖项与 default 做浅合并，所以「只禁用、不改目标」只写 enabled:false 就够。

const SCENES := {
	# 主菜单也登记：它不参与世界线，但「从菜单进游戏」这件事要靠 from_scene 说清楚，
	# 而且 bind_scene() 只认这张表。没有出口（ROUTES 里不出现），所以不可被 goto 回来。
	&"main_menu": {"path": "res://scenes/main_menu.tscn"},
	&"store_walk": {"path": "res://scenes/store_walk.tscn"},
	&"hoshi_street": {"path": "res://scenes/hoshi_street.tscn"},
	&"gas_station": {"path": "res://scenes/gas_station.tscn"},
	&"grassland": {"path": "res://scenes/grassland.tscn"},
	# 开场演出本身不设出口，但登记之后 from_scene 才记得住「从开场来的」。
	&"opening_flow": {"path": "res://scenes/opening_flow.tscn"},
}

const ROUTES := {
	&"hoshi_street": {
		&"west_gate": {
			"default": {
				"scene": &"gas_station",
				"spawn": &"east_sidewalk",
				# 只有「商店街 → 加油站」推进章节。反向出口不写，
				# 否则从加油站回来会把剧情节点倒回第二幕。
				"set_story_node": &"ep2_station",
				"transition": {
					"title": "HOSHIMI",
					"subtitle": "SERVICE STATION",
					"footer": "ROUTE 17 · 00:06",
				},
			},
			"routes": {
				&"ep2_dusk": {
					"enabled": false,
					"text": "国道方向只剩雨声。现在不是离开商店街的时候。",
				},
				&"ep3_grassland": {
					"enabled": false,
					"text": "旧世界线已经收束。",
				},
			},
		},
	},
	&"gas_station": {
		&"east_exit": {
			"default": {
				"scene": &"hoshi_street",
				"spawn": &"west_gate",
				"transition": {
					"title": "HOSHIMI",
					"subtitle": "SHOTENGAI",
					"footer": "WEST GATE · 00:07",
				},
			},
			"routes": {
				&"ep2_dusk": {
					"enabled": false,
					"text": "路牌已经湿透，字迹看不清了。",
				},
				&"ep3_grassland": {
					"enabled": false,
					"text": "旧世界线已经收束。",
				},
			},
		},
	},
}


static func scene_path(scene_id: StringName) -> String:
	var entry: Dictionary = SCENES.get(scene_id, {})
	var path: String = entry.get("path", "")
	return path


## 纯函数：给场景、出口、剧情节点，返回这次能不能走、走去哪。
## routes 参数只为回归 probe 注入合成表用，正常调用不传。
static func resolve(scene_id: StringName, portal_id: StringName,
		story_node: StringName, routes: Dictionary = ROUTES) -> Dictionary:
	var scene_routes: Dictionary = routes.get(scene_id, {})
	if scene_routes.is_empty():
		return _deny("这个场景没有配置出口")
	var portal: Dictionary = scene_routes.get(portal_id, {})
	if portal.is_empty():
		return _deny("这个出口没有配置路由")

	var merged: Dictionary = portal.get("default", {}).duplicate()
	var overrides: Dictionary = portal.get("routes", {})
	var override: Dictionary = {}
	if overrides.has(story_node):
		override = overrides[story_node]
	elif overrides.has(&"*"):
		override = overrides[&"*"]
	if not override.is_empty():
		merged.merge(override, true)

	if merged.is_empty():
		return _deny("这个出口在当前剧情下不可用")
	if not bool(merged.get("enabled", true)):
		var text: String = merged.get("text", "")
		return _deny(text if text != "" else "现在还不能往那边走")

	var target: StringName = merged.get("scene", &"")
	if target == &"":
		return _deny("路由缺少目标场景")
	if not SCENES.has(target):
		return _deny("路由指向了未注册的场景：%s" % target)

	return {
		"allowed": true,
		"scene": target,
		"spawn": merged.get("spawn", &"default"),
		"transition": merged.get("transition", {}),
		"set_story_node": merged.get("set_story_node", &""),
	}


static func _deny(text: String) -> Dictionary:
	return {"allowed": false, "text": text}
