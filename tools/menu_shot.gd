extends Node
## 主菜单的目视验收：加载菜单场景，拍三张不同状态。
##
##   godot --path . res://tools/menu_shot.tscn
##   出图在 shots/menu_*.png
##
## 为什么需要它：「清爽」「脆」「和草原绿相称」这些词没法写成断言。
## 背景的层次、按钮反色后的对比度、设置面板的疏密，只能用眼睛收。
##
## 注意：不能加 --headless。这里调 get_viewport().get_texture() 拿帧，
## 无头模式下没有渲染目标，拿到的是空白图。

const SCENE := "res://scenes/main_menu.tscn"
## 入场动画约 0.6 秒收尾，留一点余量让云也飘出可见位移
const SETTLE := 1.1

var _menu: Control


func _ready() -> void:
	_menu = (load(SCENE) as PackedScene).instantiate()
	add_child(_menu)
	await get_tree().create_timer(SETTLE).timeout

	await _shot("menu_main")

	# 「设置」是第三项（索引 2）。第二项是置灰的「继续」，故意拍不到高亮，
	# 顺便验证 disabled 的按钮不会被 focus_item 点亮
	_menu.call("focus_item", 2)
	await get_tree().create_timer(0.4).timeout
	await _shot("menu_focus")

	_menu.call("show_settings")
	await get_tree().create_timer(0.5).timeout
	await _shot("menu_settings")

	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://shots")
	var path := "res://shots/%s.png" % shot_name
	img.save_png(path)
	print("saved ", path)
