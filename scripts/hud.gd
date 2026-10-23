extends CanvasLayer
## 可玩场景的 HUD：交互提示 / 物件反馈 / 所在区域 / 操作说明。
##
## 全部用 Control 在代码里搭（本工程不在编辑器里摆节点）。
## 排版只做三件事：底部居中的交互提示、顶部居中的一行反馈、右下角操作说明。
## 不做血条不做小地图 —— 这是雨夜便利店，不是竞技游戏。

const UiFont := preload("res://scripts/ui_font.gd")

const ACCENT := Color("#4dffa8")
const WARM := Color("#ffd39a")
const TEXT := Color("#e6f2ff")
const MUTED := Color("#93a6b8")

## ---- 场景可覆盖的文案与强调色 ----
## **必须在本节点 add_child 之前赋值**：控件是 _ready() 里建的。
## 默认值就是雨夜便利店那一套，所以 store_walk 不用改任何代码；
## 草原场景只换文案和强调色，控件与交互提示的表现完全一致。
var title_text := "HOSHI MART"
var subtitle_text := "雨夜 23:47　便利店街角"
var zone_text := "店外 · 人行道"
## 交互提示方块里显示的按键名
var key_hint := "E"
## 右下角操作说明，元素是 [按键, 说明]
var controls: Array = [
	["WASD", "移动"],
	["Shift", "快跑"],
	["空格", "跳"],
	["鼠标", "转视角"],
	["Tab", "释放鼠标"],
]
## 强调色。夜景用霓虹绿，白天场景用暖金，提示框边框/按键块都跟着变。
## 名字带 _color 是为了不和 set_zone(text, accent: bool) 的参数撞名
var accent_color := ACCENT

var _prompt_panel: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _subtitle_label: Label
var _toast: Label
var _zone_chip: Label
var _fade: ColorRect
var _flash: ColorRect
var _flash_tween: Tween
var _toast_tween: Tween
## 提示面板的显隐补间。必须只保留一个：show/hide 各自 create_tween 的话，
## 快速进出交互范围时两个补间会同时写 modulate:a，后结束的那个决定最终值 ——
## 常见结果是 hide 后结束、面板停在 0，而 _prompt_shown 仍是 true，
## 于是这条提示再也不显示，直到文案变了才恢复
var _prompt_tween: Tween
var _prompt_shown := false


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var th := Theme.new()
	th.default_font = UiFont.get_font()
	th.default_font_size = 17
	root.theme = th
	add_child(root)

	_build_title(root)
	_build_zone(root)
	_build_prompt(root)
	_build_toast(root)
	_build_controls(root)
	_build_fade(root)


# ---------------------------------------------------------------- 构件

func _panel(bg: Color, border: Color, radius: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_title(root: Control) -> void:
	# 标题压在店招 / 室内墙上时白字会「消失」，所以整块垫一张深色半透明底板，
	# 而不是只靠描边硬撑。
	var card := _panel(Color(0.02, 0.035, 0.05, 0.55), Color(1, 1, 1, 0.07), 10)
	card.position = Vector2(36, 30)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)

	# 左侧竖线（用一条细 ColorRect 当装饰）
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var bar := ColorRect.new()
	bar.color = accent_color
	bar.custom_minimum_size = Vector2(3, 42)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 1)
	row.add_child(texts)
	texts.add_child(_label(title_text, 24, TEXT))
	_subtitle_label = _label(subtitle_text, 13, MUTED)
	texts.add_child(_subtitle_label)


func _build_zone(root: Control) -> void:
	var p := _panel(Color(0.03, 0.05, 0.08, 0.6), Color(1, 1, 1, 0.1), 8)
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.offset_left = -178
	p.offset_right = -40
	p.offset_top = 40
	p.offset_bottom = 76
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	_zone_chip = _label(zone_text, 13, MUTED)
	_zone_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_chip.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.85))
	_zone_chip.add_theme_constant_override("outline_size", 4)
	p.add_child(_zone_chip)


func _build_prompt(root: Control) -> void:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 1.0
	center.anchor_bottom = 1.0
	center.offset_top = -132
	center.offset_bottom = -78
	root.add_child(center)

	_prompt_panel = _panel(Color(0.04, 0.07, 0.1, 0.78), Color(accent_color, 0.35), 12)
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.modulate.a = 0.0
	center.add_child(_prompt_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_prompt_panel.add_child(row)

	var badge := _panel(Color(accent_color, 0.16), Color(accent_color, 0.55), 6)
	badge.custom_minimum_size = Vector2(28, 26)
	badge.add_theme_stylebox_override("panel", badge.get_theme_stylebox("panel"))
	row.add_child(badge)
	_prompt_key = _label(key_hint, 14, accent_color)
	_prompt_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_key.custom_minimum_size = Vector2(28, 26)
	badge.add_child(_prompt_key)

	_prompt_text = _label("", 16, TEXT)
	_prompt_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_prompt_text)


func _build_toast(root: Control) -> void:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.0
	center.anchor_bottom = 0.0
	center.offset_top = 640
	center.offset_bottom = 700
	root.add_child(center)

	_toast = _label("", 18, Color("#ffe8c4"))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	center.add_child(_toast)


func _build_controls(root: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -300
	box.offset_right = -40
	box.offset_top = -140
	box.offset_bottom = -36
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 3)
	root.add_child(box)

	for pair in controls:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var k := _label(pair[0], 12, TEXT)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# 描边不是装饰：这块文字没有底板，夜景靠深色背景还能读，
		# 但草原那种亮绿/亮白底上，MUTED 的蓝灰会直接糊掉
		k.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.85))
		k.add_theme_constant_override("outline_size", 5)
		var v := _label(pair[1], 12, MUTED)
		v.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.85))
		v.add_theme_constant_override("outline_size", 5)
		row.add_child(k)
		row.add_child(v)


func _build_fade(root: Control) -> void:
	# 白闪压在黑场底下：先加的是 flash，后加的 fade 盖在它上面，
	# 这样「撞一下白闪」不会把已经在淡出的黑场顶掉
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_flash)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)


# ---------------------------------------------------------------- 接口

func show_prompt(text: String, key: String = "") -> void:
	if key.is_empty():
		key = key_hint
	if _prompt_text.text != text:
		_prompt_text.text = text
	_prompt_key.text = key
	if _prompt_shown:
		return
	_prompt_shown = true
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_panel, "modulate:a", 1.0, 0.16)


func hide_prompt() -> void:
	if not _prompt_shown:
		return
	_prompt_shown = false
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_panel, "modulate:a", 0.0, 0.2)


func toast(text: String, seconds: float = 3.2) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


## 立刻收起顶部反馈。对话框是一次性的强占用区域，
## 它出现时如果 toast 还在飞（比如「前面就是城门」），两条字会叠在一起。
func hide_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0


func set_zone(text: String, accent: bool = false) -> void:
	_zone_chip.text = text
	_zone_chip.add_theme_color_override("font_color", accent_color if accent else MUTED)


## 标题卡副标题。加油站用它在「雨夜 00:06」和「逢魔时 18:42」之间切换。
func set_subtitle(text: String) -> void:
	if _subtitle_label == null:
		return
	_subtitle_label.text = text


## 全屏闪一下。和 fade 分开：fade 是黑场（剧情用），flash 是瞬时高光（撞击用）
func flash(color: Color = Color(1.0, 1.0, 1.0, 0.85), seconds: float = 0.24) -> void:
	if _flash == null:
		return
	_flash.color = color
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, seconds).set_ease(Tween.EASE_OUT)


## 从黑场淡入。传 0 就直接跳过（截图模式用）。
func fade_in(seconds: float = 1.4) -> void:
	if seconds <= 0.0:
		_fade.color.a = 0.0
		return
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, seconds)


func fade_out(seconds: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, seconds)


func prompt_alpha() -> float:
	return _prompt_panel.modulate.a
