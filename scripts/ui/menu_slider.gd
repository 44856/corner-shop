extends Control
## 设置面板里的方框滑条。
##
## 为什么不用 HSlider：它的外观拆在 slider / grabber_area / grabber 三套样式里，
## 而 grabber 要一张 Texture2D —— 本工程零外部素材，为一个小方块去生成贴图
## 比自绘整个控件还麻烦，而且拿不到「硬边 + 刻度」这套观感。
##
## 交互只做三件事：点哪跳哪、按住拖、左右键微调。滚轮不支持 ——
## 音量滚轮很容易误触。

signal value_changed(value: float)

const P := preload("res://scripts/ui/menu_palette.gd")

## 键盘微调步长。0.05 在 41 dB 的映射区间里约等于 2 dB，正好是一格能听出来的量
const KEY_STEP := 0.05

var value := 0.5:
	set(v):
		var nv := clampf(v, 0.0, 1.0)
		if is_equal_approx(nv, value):
			return
		value = nv
		queue_redraw()
		value_changed.emit(value)

var _dragging := false
var _hot := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, 34.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	mouse_entered.connect(_on_focus.bind(true))
	mouse_exited.connect(_on_focus.bind(false))


func _on_focus(on: bool) -> void:
	if _hot == on:
		return
	_hot = on
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var cy := size.y * 0.5
	var track := P.MOSS
	track.a = 0.85
	draw_rect(Rect2(0.0, cy - 3.0, w, 6.0), track, true)

	# 刻度：四分之一处一道，纯装饰，但让这条轨道读起来像「有档位的设备」
	for i in range(1, 4):
		var tick_x := w * float(i) / 4.0
		draw_rect(Rect2(tick_x - 0.5, cy - 5.0, 1.0, 10.0),
			Color(0.78, 0.90, 0.62, 0.22), true)

	var fill := P.LIME
	fill.a = 1.0 if _hot else 0.85
	draw_rect(Rect2(0.0, cy - 3.0, w * value, 6.0), fill, true)

	# 手柄：14x20 竖块 + 2px 墨边。方角是刻意的，圆形手柄会把这套 UI 的
	# 「切出来的塑料」感觉冲掉
	var hx := clampf(w * value, 7.0, w - 7.0)
	var hr := Rect2(hx - 7.0, cy - 10.0, 14.0, 20.0)
	draw_rect(hr, P.CREAM, true)
	P.stroke(self, hr, P.INK, 2.0)
	# 手柄中间一道竖槽，让它看起来能被捏住
	draw_rect(Rect2(hx - 1.5, cy - 5.0, 3.0, 10.0), P.MOSS, true)

	if _hot:
		var frame := Rect2(0.0, cy - 15.0, w, 30.0)
		P.stroke(self, frame, Color(0.74, 0.91, 0.43, 0.55), 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				grab_focus()
				value = mb.position.x / maxf(size.x, 1.0)
				accept_event()
			else:
				_dragging = false
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		value = (event as InputEventMouseMotion).position.x / maxf(size.x, 1.0)
		accept_event()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.is_action("ui_left"):
				value -= KEY_STEP
				accept_event()
			elif k.is_action("ui_right"):
				value += KEY_STEP
				accept_event()
