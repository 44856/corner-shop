extends CanvasLayer
## 跨场景转场：英文字母逐字点亮的「下一站」加载屏。
##
## 挂在 get_tree().root 下面（不是当前场景），所以 change_scene_to_file 之后
## 它还活着，能继续把旧场景的黑场淡开、露出新场景。
##
## 新场景不认这个节点：SceneRouter 会在 play() 期间把 arrival 上下文交给它，
## 场景据此跳过自己的开场黑幕与运镜，否则会出现「转场淡出 → 新场景又黑一下」。
##
## 主题不是随便挑的：这条路是雨夜国道，画面里出现的都是日本车站/加油站的
## 英文标识（NEXT STOP / SERVICE STATION / 24H），字距和等宽字体都按老式
## LED 里程牌来做。字母不整块淡入，而是一个一个亮起来，进度条再走一遍，
## 让「等」这件事本身成为氛围。

const BG := Color("#05070d")
const TEXT := Color("#efe4d2")
const AMBER := Color("#ffcf8a")
const COOL := Color("#cfe6ff")
const MUTED := Color("#5f7487")

## 文案在 add_child 之前赋值；默认值就是去加油站那一趟。
var title_text := "HOSHIMI"
var subtitle_text := "SERVICE STATION"
var footer_text := "ROUTE 17 · 00:06"
var accent := AMBER

var _bg: ColorRect
var _content: Control
var _title_row: HBoxContainer
var _sub_row: HBoxContainer
var _load_row: HBoxContainer
var _pct: Label
var _bar_fill: ColorRect
var _title_letters: Array = []
var _sub_letters: Array = []
var _load_letters: Array = []
var _progress := 0.0
var _revealed := 0
var _started := false
var _finished := false
var _destination := ""


func _ready() -> void:
	layer = 100
	_build_ui()


# ---------------------------------------------------------------- 对外接口

## 标题里真正参与逐字动画的字母数（空格不算）。测试用。
func total_letters() -> int:
	return _title_letters.size()


## 已经亮起来的标题字母数。测试用。
func letters_revealed() -> int:
	return _revealed


## 0.0 ~ 1.0。测试用，也是进度条的唯一数据源。
func loading_progress() -> float:
	return _progress


## 只跑加载动画，不切场景。探针直接调这个，免得测试真的换场景。
func start_loading() -> void:
	if _started:
		while not _finished:
			await get_tree().process_frame
		return

	_started = true
	var fade := create_tween()
	fade.tween_property(_bg, "modulate:a", 1.0, 0.38)
	await fade.finished

	var content_in := create_tween()
	content_in.tween_property(_content, "modulate:a", 1.0, 0.25)
	await content_in.finished

	_reveal_title()
	await get_tree().create_timer(0.55).timeout
	_reveal_row(_sub_letters, 0.0, 0.03)
	await get_tree().create_timer(0.42).timeout
	_reveal_row(_load_letters, 0.0, 0.05)
	await get_tree().create_timer(0.22).timeout

	var bar := create_tween()
	bar.tween_method(_set_progress, 0.0, 1.0, 1.75)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await bar.finished
	_set_progress(1.0)
	_finished = true


## 完整转场：黑场 → 字母加载 → 切场景 → 淡出黑场 → 自毁。
## destination 为空时只播放动画（测试用）。
func play(destination: String) -> void:
	_destination = destination
	if not _started:
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("lock_for_transition"):
			scene.call("lock_for_transition")
		await start_loading()
	else:
		while not _finished:
			await get_tree().process_frame

	await get_tree().create_timer(0.4).timeout
	if _destination != "":
		var err := get_tree().change_scene_to_file(_destination)
		if err != OK:
			push_error("LetterTransition: 切换场景失败 %s（错误码 %d）" % [_destination, err])
		# change_scene_to_file 是延迟执行的：等两帧，新场景的 _ready 已跑完并取走 arrival，
		# SceneRouter 才能安全地清空上下文、宣布转场结束。
		await get_tree().process_frame
		await get_tree().process_frame

	var out := create_tween().set_parallel(true)
	out.tween_property(_bg, "modulate:a", 0.0, 1.0)
	out.tween_property(_content, "modulate:a", 0.0, 0.5)
	await out.finished
	queue_free()


# ---------------------------------------------------------------- 搭界面

func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var th := Theme.new()
	th.default_font = _mono_font()
	th.default_font_size = 14
	root.theme = th

	_bg = ColorRect.new()
	_bg.color = BG
	_bg.modulate.a = 0.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_bg)

	_content = Control.new()
	_content.modulate.a = 0.0
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_content)

	_build_corner(root, true)
	_build_corner(root, false)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(780, 0)
	box.add_theme_constant_override("separation", 0)
	center.add_child(box)

	_caption(box, "NEXT STOP   /   NIGHT SERVICE   /   ROUTE 17")
	box.add_child(_spacer(16))

	_title_row = _letter_row(title_text, 64, TEXT, 4)
	box.add_child(_title_row)
	box.add_child(_spacer(8))

	_sub_row = _letter_row(subtitle_text, 20, accent, 4)
	box.add_child(_sub_row)
	box.add_child(_spacer(46))

	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.09)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = accent
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_right = 0.0
	_bar_fill.anchor_bottom = 1.0
	bar.add_child(_bar_fill)

	box.add_child(_spacer(12))

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 12)
	box.add_child(status)

	_load_row = _letter_row("LOADING", 12, MUTED, 6)
	_load_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	status.add_child(_load_row)

	_pct = _label("000%", 12, COOL)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.custom_minimum_size = Vector2(64, 0)
	status.add_child(_pct)

	box.add_child(_spacer(38))
	_caption(box, footer_text)


func _build_corner(root: Control, top: bool) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.offset_left = 42
	row.offset_right = -42
	if top:
		row.anchor_top = 0.0
		row.anchor_bottom = 0.0
		row.offset_top = 34
		row.offset_bottom = 54
	else:
		row.anchor_top = 1.0
		row.anchor_bottom = 1.0
		row.offset_top = -54
		row.offset_bottom = -34
	_content.add_child(row)

	var dot := ColorRect.new()
	dot.color = accent
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)

	var left_text := "HOSHIMI LINE   /   ALL LINES NORMAL" if top else "RAIN   /   12°C   /   WIND NE 3"
	# 右上角时钟从 footer_text 里取（「ROUTE 17 · 00:06」→「00:06」），
	# 不然回程那趟 footer 写 00:07、角落还停在 00:06。
	var right_text := footer_text.get_slice("·", 1).strip_edges() if top \
		else "HOSHIMI SERVICE NETWORK"
	var left := _label(left_text, 11, MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_color_override("font_color", Color(MUTED, 0.85))
	row.add_child(left)
	var right := _label(right_text, 11, MUTED)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_color_override("font_color", Color(MUTED, 0.85))
	row.add_child(right)


func _caption(parent: VBoxContainer, text: String) -> void:
	var l := _label(text, 12, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 把一句话拆成一格一格的字母，空格用固定宽的空白占位。
## 用 HBoxContainer 而不是给单个 Label 调字距：逐字动画需要每个字母独立 modulate。
func _letter_row(text: String, size: int, color: Color, spacing: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", spacing)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var letters: Array = []
	for ch in text:
		if ch == " ":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(float(size) * 0.42, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
			continue
		var l := _label(ch, size, color)
		l.modulate.a = 0.0
		row.add_child(l)
		letters.append(l)

	if text == title_text:
		_title_letters = letters
	elif text == subtitle_text:
		_sub_letters = letters
	else:
		_load_letters = letters
	return row


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"JetBrains Mono", "Noto Sans Mono", "DejaVu Sans Mono",
		"Consolas", "Courier New", "monospace",
	])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


# ---------------------------------------------------------------- 动画

func _reveal_title() -> void:
	for i in _title_letters.size():
		var l: Label = _title_letters[i]
		var tw := create_tween()
		tw.tween_interval(0.04 + float(i) * 0.055)
		tw.tween_callback(func() -> void: _revealed += 1)
		tw.tween_property(l, "modulate:a", 1.0, 0.14)


func _reveal_row(letters: Array, delay: float, step: float) -> void:
	for i in letters.size():
		var l: Label = letters[i]
		var tw := create_tween()
		tw.tween_interval(delay + float(i) * step)
		tw.tween_property(l, "modulate:a", 1.0, 0.12)


## 进度条的填充直接改 anchor_right：放在容器里也不受排版时机影响。
## LOADING 那一行同时做一个扫描高光，让进度不是干巴巴的一条线。
func _set_progress(v: float) -> void:
	_progress = clampf(v, 0.0, 1.0)
	_bar_fill.anchor_right = _progress
	_pct.text = "%03d%%" % int(round(_progress * 100.0))
	if _load_letters.is_empty():
		return
	if _progress >= 1.0:
		for l in _load_letters:
			l.modulate.a = 1.0
		return
	var n := _load_letters.size()
	var head := int(_progress * float(n) * 2.4) % (n + 4) - 2
	for i in n:
		var d: int = absi(head - i)
		_load_letters[i].modulate.a = 1.0 - minf(float(d), 4.0) * 0.16
