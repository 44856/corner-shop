extends Node
## 冒险者公会的目视验收：加载完整草原场景，在城西南角布一组机位截图。
##
##   godot --path . res://tools/guild_shot.tscn
##   出图在 shots/guild_*.png
##
## 为什么要有这个工具：这栋楼的问题几乎全是「看着不对」——
## 柱子够不够粗、12 m 的柜台会不会读成隔墙、楼梯在门口看过去像不像一堵墙、
## 门开着能不能看出里面有屋子。这些都没法用断言描述。
##
## 数据类的回归（尺寸、碰撞、柜台长度）在 tools/grassland_probe.gd 里。

const SCENE := "res://scenes/grassland.tscn"

var _cam: Camera3D
var _scene: Node


func _ready() -> void:
	_scene = (load(SCENE) as PackedScene).instantiate()
	add_child(_scene)
	# 醒来补间 2 秒 + 余量
	await get_tree().create_timer(2.6).timeout

	# 玩家藏起来（但坐标仍有效，守卫 / 接待的转头逻辑还要靠它）
	var p: Node3D = _scene.player
	if p != null:
		p.visible = false
		p.set_physics_process(false)
		# 挪到公会门口，让两个接待把视线转过来 —— 站着不动的接待像假人
		p.global_position = Vector3(-126.0, 0.05, 322.0)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.near = 0.05
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true

	var shots := [
		# 从城里往回看：玩家进城后往西走，公会逐渐从城墙角上露出来。
		# 相机必须站在城内（z > 302），城墙厚 4 m，站在 z=300 就是在墙里拍黑屏
		{"pos": Vector3(-70.0, 2.50, 306.0), "look": Vector3(-126.0, 5.50, 322.0),
			"name": "guild_distant", "fov": 55.0},
		# 正面全景。28 m 宽的楼在 14 m 外装不进 42°，要拉广角或者退到斜角
		{"pos": Vector3(-100.0, 2.80, 304.0), "look": Vector3(-126.0, 5.50, 319.0),
			"name": "guild_front", "fov": 55.0},
		# 门口近景：门开着，能不能看见里面的暖光
		{"pos": Vector3(-126.0, 1.70, 309.5), "look": Vector3(-126.0, 2.40, 318.0),
			"name": "guild_door", "fov": 42.0},
		# 进门第一步：正对大厅
		{"pos": Vector3(-126.0, 1.70, 317.6), "look": Vector3(-128.0, 2.30, 334.0),
			"name": "guild_hall", "fov": 42.0},
		# 柱列：进门左手
		{"pos": Vector3(-125.0, 1.62, 320.5), "look": Vector3(-132.2, 2.60, 331.0),
			"name": "guild_columns", "fov": 42.0},
		# 前台全景
		{"pos": Vector3(-128.5, 1.68, 332.5), "look": Vector3(-131.0, 1.55, 338.6),
			"name": "guild_counter", "fov": 42.0},
		# 接待近景：避开 x=−132 那根柱子，站位挪到 −130
		{"pos": Vector3(-130.0, 1.62, 334.8), "look": Vector3(-131.4, 1.50, 339.2),
			"name": "guild_clerks", "fov": 42.0},
		# 楼梯：从大厅看过去
		{"pos": Vector3(-124.0, 1.70, 318.5), "look": Vector3(-114.2, 2.40, 327.5),
			"name": "guild_stairs", "fov": 42.0},
		# 任务板：进门右手
		{"pos": Vector3(-125.0, 1.62, 322.5), "look": Vector3(-120.4, 1.45, 318.6),
			"name": "guild_boards", "fov": 42.0},
		# 站在二层楼梯口往下看 —— 「二楼不做」这件事得看得见
		{"pos": Vector3(-113.6, 5.40, 330.6), "look": Vector3(-128.0, 0.80, 320.0),
			"name": "guild_upper", "fov": 55.0},
		# 东侧：朝城镇中心那面
		{"pos": Vector3(-96.0, 3.20, 328.5), "look": Vector3(-112.0, 5.00, 328.5),
			"name": "guild_side", "fov": 55.0},
		# 屋顶：双坡的方向读不读得出来
		{"pos": Vector3(-100.0, 7.00, 306.0), "look": Vector3(-126.0, 9.20, 328.0),
			"name": "guild_roof", "fov": 55.0},
		# 前庭：从广场侧斜看，梯形路和两侧花池要一眼能看出来
		{"pos": Vector3(-111.0, 2.10, 303.5), "look": Vector3(-126.0, 1.30, 315.0),
			"name": "guild_court", "fov": 55.0},
		# 站在路上往里走：镜头压低，看石板缝和花池边
		{"pos": Vector3(-126.0, 1.55, 309.0), "look": Vector3(-126.0, 1.10, 316.6),
			"name": "guild_path", "fov": 50.0},
		# 花池近景：花草是「一丛一丛」还是「一片绿块」
		{"pos": Vector3(-133.2, 0.95, 311.2), "look": Vector3(-130.6, 0.28, 312.4),
			"name": "guild_flowers", "fov": 42.0},
	]
	DirAccess.make_dir_recursive_absolute("res://shots")
	for s in shots:
		_cam.fov = s.get("fov", 42.0)
		_cam.global_position = s["pos"]
		_cam.look_at(s["look"], Vector3.UP)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])
	get_tree().quit(0)
