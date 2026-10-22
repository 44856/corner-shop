extends CanvasLayer
## 死亡演出的面纱与字幕层。
##
## 这一层只做「看得见的东西」：去色/撕裂、噪点、暗角、告别字幕、伸手提示。
## 时序与音效由 gas_station_story.gd 掌握 —— 把两者混在一个文件里，
## 调字幕停留时间时会牵动状态机，改起来很痛。
##
## layer 30：压在 HUD（10）上面、LetterTransition（100）下面。
## 最后一帧黑场交给 LetterTransition，避免两层黑互相打架。

const UiFont := preload("res://scripts/ui_font.gd")
const VEIL_SHADER := preload("res://shaders/death_veil.gdshader")

const TEXT := Color("#f2e6cf")
const MUTED := Color("#a8967c")
const AMBER := Color("#ffcf8a")

var _veil: ColorRect
var _mat: ShaderMaterial
var _line: Label
var _sub: Label
var _prompt: Label
var _line_tween: Tween
var _prompt_shown := false
var _prompt_pressed := false
var _t := 0.0
## 测试用加速倍数。字幕 / 提示的补间都乘 1/speed。
var speed := 1.0


func _ready() -> void:
	layer = 30
	_build_root()
	set_veil({"alpha": 0.0})
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_mat.set_shader_parameter("time", _t)


func _build_root() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var th := Theme.new()
	th.default_font = UiFont.get_font()
	th.default_font_size = 18
	root.theme = th

	_veil = ColorRect.new()
	_veil.color = Color.WHITE
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = VEIL_SHADER
	_veil.material = _mat
	root.add_child(_veil)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(860, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	_line = _label("", 30, TEXT)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.modulate.a = 0.0
	box.add_child(_line)

	_sub = _label("", 15, MUTED)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.modulate.a = 0.0
	box.add_child(_sub)

	_prompt = _label("", 18, AMBER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -130
	_prompt.offset_bottom = -100
	_prompt.modulate.a = 0.0
	root.add_child(_prompt)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.01, 0.012, 0.016, 0.96))
	l.add_theme_constant_override("outline_size", 9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- 对外接口

## 一次性写入面纱参数。缺省的键保持当前值，方便只推动一个维度。
func set_veil(values: Dictionary) -> void:
	for key in values:
		_mat.set_shader_parameter(key, values[key])


func set_veil_alpha(value: float) -> void:
	_mat.set_shader_parameter("alpha", value)


func veil_alpha() -> float:
	return float(_mat.get_shader_parameter("alpha"))


## 单独推一个维度。死亡演出要同时推 alpha / desat / blackout 三条曲线，
## 每次都 set_veil 会互相打断补间，所以拆成「一个键一条补间」。
func fade_param(key: String, value: float, seconds: float) -> void:
	var from := float(_mat.get_shader_parameter(key))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter(key, v),
		from, value, _dur(seconds))


func fade_alpha(value: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_method(set_veil_alpha, veil_alpha(), value, _dur(seconds))


## 显示一行告别字幕。seconds 到了之后自动淡出；不 await 也可以。
func show_line(text: String, seconds: float, subtext: String = "") -> void:
	_line.text = text
	_sub.text = subtext
	_kill_line_tween()
	_line_tween = create_tween()
	_line_tween.tween_property(_line, "modulate:a", 1.0, _dur(0.55))
	if subtext != "":
		_line_tween.parallel().tween_property(_sub, "modulate:a", 1.0, _dur(0.55))
	_line_tween.tween_interval(seconds / speed)
	_line_tween.tween_property(_line, "modulate:a", 0.0, _dur(0.65))
	if subtext != "":
		_line_tween.parallel().tween_property(_sub, "modulate:a", 0.0, _dur(0.65))


func clear_line(seconds: float = 0.4) -> void:
	_kill_line_tween()
	_line_tween = create_tween().set_parallel(true)
	_line_tween.tween_property(_line, "modulate:a", 0.0, _dur(seconds))
	_line_tween.tween_property(_sub, "modulate:a", 0.0, _dur(seconds))


## 最后的「伸手」：能动，但什么也不会发生。提示只亮一次，按过就收。
func show_prompt(text: String = "E　伸出手") -> void:
	_prompt.text = text
	_prompt_shown = true
	_prompt_pressed = false
	_prompt.visible = true
	var tw := create_tween()
	tw.tween_property(_prompt, "modulate:a", 1.0, _dur(0.35))


func hide_prompt() -> void:
	if not _prompt_shown:
		return
	_prompt_shown = false
	var tw := create_tween()
	tw.tween_property(_prompt, "modulate:a", 0.0, _dur(0.35))


func prompt_pressed() -> bool:
	return _prompt_pressed


func prompt_shown() -> bool:
	return _prompt_shown


func reset() -> void:
	_kill_line_tween()
	_line.modulate.a = 0.0
	_sub.modulate.a = 0.0
	_prompt.modulate.a = 0.0
	_prompt_shown = false
	_prompt_pressed = false
	set_veil_alpha(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _prompt_shown:
		return
	if event.is_action_pressed("interact"):
		_prompt_pressed = true
		get_viewport().set_input_as_handled()
		hide_prompt()


func _kill_line_tween() -> void:
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()


func _dur(seconds: float) -> float:
	return maxf(0.01, seconds / speed)
