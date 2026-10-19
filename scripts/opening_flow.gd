extends Node
## 开场流程串联：雨夜便利店的开场动画播完 → 切到异世界草原。
##
## 为什么做成一个独立场景，而不是在 cutscene.gd 末尾加一行 change_scene：
##   任务书要求不动 cutscene.gd / main.gd 的现有行为（开场动画已验收）。
##   所以这里把 main.tscn 当**子场景**加载，只在外面观察它的状态，
##   播完再换场景。两个文件一行不用改。
##
## 结束判定：cutscene 收尾时 _cleanup() 会把它的 UI CanvasLayer 隐藏，
##   而且正常播完和按空格跳过都走这条路 —— 一个条件覆盖两种情况。
##
## 遮罩的必要性：_cleanup() 把 UI 收掉的同时，cutscene 自己的黑场 ColorRect
##   也跟着不可见了，画面会突然跳回雨夜场景。所以这里必须自己盖一层黑。

const MAIN := preload("res://scenes/main.tscn")
const CUTSCENE_SCRIPT := preload("res://scripts/cutscene.gd")
const NEXT_SCENE := "res://scenes/grassland.tscn"

## 盖黑用多久（秒）
const VEIL_SECONDS := 0.25
## 全黑之后停多久再切场景（秒）
const HOLD_SECONDS := 0.55

var _main: Node3D
var _cutscene: Node
var _veil: ColorRect
var _finished := false


func _ready() -> void:
	_build_veil()
	_main = MAIN.instantiate()
	add_child(_main)

	# main.gd 在 _ready() 里就把 cutscene 加进来了，add_child 是同步的，
	# 所以这里能立刻拿到它
	_cutscene = _find_cutscene(_main)
	if _cutscene == null:
		push_warning("[opening_flow] 找不到开场动画节点，流程不会自动推进")
		set_process(false)


func _process(_delta: float) -> void:
	if _finished or not is_instance_valid(_cutscene):
		return
	var ui := _cutscene.get("_ui") as CanvasLayer
	if ui != null and not ui.visible:
		_finished = true
		_go_next()


## cutscene 是用 Cutscene.new() 动态加的节点，没有固定名字，
## 只能按脚本资源认人
func _find_cutscene(root: Node) -> Node:
	for c in root.get_children():
		if c.get_script() == CUTSCENE_SCRIPT:
			return c
	return null


func _build_veil() -> void:
	# layer 128 远高于 cutscene 的 20，保证盖在所有演出之上
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)

	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.anchor_right = 1.0
	_veil.anchor_bottom = 1.0
	layer.add_child(_veil)


func _go_next() -> void:
	var tw := create_tween()
	tw.tween_property(_veil, "color", Color(0, 0, 0, 1), VEIL_SECONDS)
	await tw.finished
	await get_tree().create_timer(HOLD_SECONDS).timeout
	print("[opening_flow] 开场结束，切到草原")
	get_tree().change_scene_to_file(NEXT_SCENE)
