extends Node
## 英文字母加载转场（letter_transition.gd）的回归测试。
##
##   ./tools/run.sh --headless transition_probe
##
## 只验动画本身，不真的换场景 —— 探针自己就是 current_scene，
## change_scene_to_file 会把它一起按掉。
##
## 钉住四件事：
##   - 盖在 HUD（layer 10）之上；
##   - 标题按字母切分，初始全暗；
##   - 加载跑完后每个字母都亮、进度正好 1.0；
##   - play("") 播完会自毁，不留在 root 上挡住下一次转场。

var _pass := 0
var _fail := 0


func _ready() -> void:
	var tr = load("res://scripts/letter_transition.gd").new()
	tr.name = "LetterTransition"
	tr.title_text = "HOSHIMI"
	tr.subtitle_text = "SERVICE STATION"
	tr.footer_text = "ROUTE 17 · 00:06"
	add_child(tr)
	await get_tree().process_frame

	_check("层级压在 HUD（10）之上", tr.layer == 100)
	_check("标题切成 7 个独立字母", tr.total_letters() == 7)
	_check("初始字母全暗", tr.letters_revealed() == 0)
	_check("初始进度为 0", is_zero_approx(tr.loading_progress()))

	# 不 await start_loading()：探针要在动画进行中轮询进度
	tr.start_loading()
	var elapsed := 0.0
	while tr.loading_progress() < 0.999 and elapsed < 6.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	_check("进度条走满", tr.loading_progress() >= 0.999)
	_check("7 个标题字母全部点亮", tr.letters_revealed() == tr.total_letters())

	tr.play("")
	elapsed = 0.0
	while is_instance_valid(tr) and elapsed < 3.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	_check("播完自毁（不会留在 root 上）", not is_instance_valid(tr))

	print("\n==== transition_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label)
