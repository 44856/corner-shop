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
##   也跟着不可见了，画面会突然跳回雨夜场景。所以这里必须自己盖一层黑，
##   撑到 SceneRouter 的字母屏接过去。

const MAIN := preload("res://scenes/main.tscn")
const CUTSCENE_SCRIPT := preload("res://scripts/cutscene.gd")
const SCENE_ID := &"opening_flow"
const NEXT_SCENE_ID := &"grassland"

## 盖黑用多久（秒）
const VEIL_SECONDS := 0.25
## 全黑之后停多久再交给 SceneRouter（秒）
const HOLD_SECONDS := 0.55

var _main: Node3D
var _cutscene: Node
var _veil: ColorRect
var _finished := false


func _ready() -> void:
	SceneRouter.bind_scene(SCENE_ID)
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
	# 高于 cutscene 的 20，遮住它撤 UI 的那一瞬间；
	# 但必须低于 LetterTransition 的 100，否则字母屏会被这层黑整个盖住。
	var layer := CanvasLayer.new()
	layer.layer = 90
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
	# 演出结束后的落点与世界线都交给 SceneRouter，不再直接 change_scene。
	# 旧流程靠「直接换场景」跳过加载屏；现在目的地与转场文案归路由层，
	# 两个进入草原的入口（开场 / 死亡）也就共用同一套转场语言。
	var started := SceneRouter.goto(NEXT_SCENE_ID, &"default", {
		"mode": &"opening",
		"set_story_node": &"ep3_grassland",
		"transition": {
			"style": "letter",
			"title": "ISEKAI",
			"subtitle": "GRASSLAND",
			"footer": "SOMEWHERE · 06:12",
			"accent": Color("#ffd39a"),
		},
	})
	if not started:
		push_warning("[opening_flow] 转场未能启动")
