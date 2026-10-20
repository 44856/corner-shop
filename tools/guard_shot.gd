extends Node
## 城门守卫站姿的目视验收：加载完整草原场景，在城门附近布一组机位截图。
##
##   godot --path . res://tools/guard_shot.tscn
##   出图在 shots/pose_*.png
##
## 为什么要有这个工具：站姿是「看」出来的，没法用断言描述。
## 改 STANCES / 微动 / 身高归一化之后跑一遍，几张图就能看出有没有退化：
## 手臂是不是又张开成 A-pose、脚是不是离地、水晶是不是又飘回肩膀外面。
##
## 数据类的回归（手臂收拢距离、脚不滑、上半身在动）在 tools/grassland_probe.gd 里。

const SCENE := "res://scenes/grassland.tscn"

var _cam: Camera3D
var _scene: Node


func _ready() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate()
	add_child(_scene)
	# 醒来补间 2 秒 + 余量
	await get_tree().create_timer(2.6).timeout

	# 玩家不出现（但坐标仍然有效，最后一张要靠它触发守卫转头）
	var p: Node3D = _scene.player
	if p != null:
		p.visible = false
		p.set_physics_process(false)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true

	var shots := [
		{"pos": Vector3(0.0, 1.60, 288.0), "look": Vector3(0.0, 1.25, 303.0), "name": "pose_front_pair"},
		{"pos": Vector3(-7.0, 1.55, 296.9), "look": Vector3(-7.0, 1.22, 302.4), "name": "pose_isaac"},
		{"pos": Vector3(7.0, 1.55, 298.0), "look": Vector3(7.0, 1.22, 303.5), "name": "pose_skadi"},
		{"pos": Vector3(-3.2, 1.55, 302.0), "look": Vector3(-7.0, 1.20, 302.4), "name": "pose_side"},
		{"pos": Vector3(-1.5, 0.95, 297.0), "look": Vector3(-6.6, 1.35, 302.4), "name": "pose_low"},
		{"pos": Vector3(-3.0, 1.70, 308.5), "look": Vector3(-7.0, 1.15, 302.4), "name": "pose_back"},
		# 玩家走到城门前时的真实视平线（第三人称相机大概就在这个高度）
		{"pos": Vector3(-0.6, 2.00, 292.5), "look": Vector3(-6.4, 1.25, 302.4), "name": "pose_walkup"},
		# 玩家站到守卫跟前，验证守卫会自己把头转过来
		{"pos": Vector3(-3.0, 1.60, 299.6), "look": Vector3(-7.0, 1.35, 302.4), "name": "pose_notice",
			"player": Vector3(-5.4, 0.05, 299.4)},
	]
	DirAccess.make_dir_recursive_absolute("res://shots")
	for s in shots:
		if s.has("player"):
			_scene.player.global_position = s["player"]
			await get_tree().create_timer(1.6).timeout
		_cam.global_position = s["pos"]
		_cam.look_at(s["look"], Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])
	get_tree().quit(0)
