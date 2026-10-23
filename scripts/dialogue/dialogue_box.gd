class_name DialogueBox
extends CanvasLayer
## 对话框 UI：底部横条 + 说话人名 + 正文 + 继续箭头。
##
## 全部用代码生成 —— 本工程不在编辑器里摆节点，所以连 UI 也不做成 .tscn。
##
## 职责边界（和 dev 工程一致，只改了一处）：
##   只负责「显示一行字」和「吃掉确认输入」，不知道剧本、不知道触发器。
##   dev 版直接调 Dialogue.advance()（有 autoload），这里没有单例可调，
##   所以改成发 advance_requested 信号，由 DialogueRunner 决定推进 —— 依赖方向反过来更好。
##
## 逐字显示用 _process 累加 visible_characters，不用 Tween：
## 每行只有 0.5 秒，Tween 每行新建一个再打断，成本比手动累加高。

signal advance_requested

## 每秒显示的字数
var chars_per_sec := 30.0
## 说话人配色：没登记的走默认色。狗给暖橙，主角在这里动态登记
var speaker_colors := {
	"狗": Color("#f0b46a"),
}

var _name_label: Label
var _text_label: RichTextLabel
var _arrow: Label
var _panel: Panel

var _revealed := 0.0
var _total := 0
var _typing := false
var _t := 0.0


func _ready() -> void:
	layer = 10
	visible = false
	_build()


# ---------------------------------------------------------------- 组装

func _build() -> void:
	var font: Font = preload("res://scripts/ui_font.gd").get_font()

	# 面板：整宽 84%，贴在屏幕下三分之一。深灰半透明在明亮草地上对比度最好
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.08
	_panel.anchor_top = 0.72
	_panel.anchor_right = 0.92
	_panel.anchor_bottom = 0.93
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.070, 0.088, 0.86)
	sb.border_color = Color(0.65, 0.74, 0.70, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	# 上方一条更亮的细线，像一格分镜框的顶边
	sb.border_width_top = 3
	sb.border_color = Color(0.86, 0.80, 0.62, 0.75)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	# 说话人名
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.position = Vector2(30.0, 8.0)
	_name_label.size = Vector2(520.0, 40.0)
	_name_label.add_theme_font_override("font", font)
	_name_label.add_theme_font_size_override("font_size", 25)
	_name_label.add_theme_color_override("font_color", Color("#f1c98d"))
	_panel.add_child(_name_label)

	# 正文：用 MarginContainer 撑满，留出边距
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.anchor_left = 0.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 30.0
	margin.offset_top = 54.0
	margin.offset_right = -30.0
	margin.offset_bottom = -42.0
	_panel.add_child(margin)

	_text_label = RichTextLabel.new()
	_text_label.name = "TextLabel"
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.fit_content = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_override("normal_font", font)
	_text_label.add_theme_font_override("bold_font", font)
	_text_label.add_theme_font_size_override("normal_font_size", 23)
	_text_label.add_theme_font_size_override("bold_font_size", 23)
	_text_label.add_theme_color_override("default_color", Color("#f4f6f8"))
	margin.add_child(_text_label)

	# 继续提示 + 箭头（右下角）
	var hint := Label.new()
	hint.name = "Hint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.anchor_left = 1.0
	hint.anchor_top = 1.0
	hint.anchor_right = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -186.0
	hint.offset_top = -36.0
	hint.offset_right = -54.0
	hint.offset_bottom = -8.0
	hint.text = "空格 / 左键 继续"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.42))
	_panel.add_child(hint)

	_arrow = Label.new()
	_arrow.name = "Arrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.anchor_left = 1.0
	_arrow.anchor_top = 1.0
	_arrow.anchor_right = 1.0
	_arrow.anchor_bottom = 1.0
	_arrow.offset_left = -46.0
	_arrow.offset_top = -40.0
	_arrow.offset_right = -20.0
	_arrow.offset_bottom = -6.0
	_arrow.text = "▼"
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_arrow.add_theme_font_override("font", font)
	_arrow.add_theme_font_size_override("font_size", 20)
	_arrow.add_theme_color_override("font_color", Color("#dfe6ea"))
	_panel.add_child(_arrow)


# ---------------------------------------------------------------- 显示

## 显示一行。who 为空时隐藏名字（旁白）。
func show_line(who: String, text: String) -> void:
	visible = true
	_name_label.text = who
	_name_label.visible = who != ""
	_apply_speaker_color(who)
	_text_label.text = text
	_total = text.length()
	_revealed = 0.0
	_text_label.visible_characters = 0
	_arrow.visible = false
	_typing = _total > 0
	# 一句只有 0 帧的情况（空文本）不该卡住在打字态
	if not _typing:
		_arrow.visible = true


## 登记某个说话人的配色。runner 用它把主角名染成冰蓝，和狗区分开
func set_speaker_color(who: String, color: Color) -> void:
	speaker_colors[who] = color


func _apply_speaker_color(who: String) -> void:
	var c: Color = speaker_colors.get(who, Color("#f1c98d"))
	_name_label.add_theme_color_override("font_color", c)


## 跳过逐字动画，整行立刻显示。
func reveal_all() -> void:
	_revealed = float(_total)
	_text_label.visible_characters = _total
	_typing = false
	_arrow.visible = true


func is_typing() -> bool:
	return _typing


func close() -> void:
	visible = false
	_typing = false


# ---------------------------------------------------------------- 输入

func _process(delta: float) -> void:
	if _typing:
		_revealed = minf(_revealed + chars_per_sec * delta, float(_total))
		_text_label.visible_characters = int(_revealed)
		if _revealed >= float(_total):
			_typing = false
			_arrow.visible = true
	if _arrow.visible:
		# 呼吸式闪烁，替代补间：省一个 Tween，也不会在切行时残留
		_t += delta
		_arrow.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 6.0))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var mb := event as InputEventMouseButton
	var confirm := event.is_action_pressed("ui_accept") \
		or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT)
	if not confirm:
		return
	# 吃掉输入，防止空格同时触发跳跃等底层逻辑
	get_viewport().set_input_as_handled()
	if _typing:
		reveal_all()
	else:
		advance_requested.emit()
