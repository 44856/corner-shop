extends Button
## 主菜单的按钮：一块硬边方框，悬停时整块翻成青草绿、文字反白。
##
## 为什么继承 Button 而不是 Control 自绘：
## Button 自带鼠标判定、焦点导航（ui_up/ui_down 走焦点邻居）、disabled 语义。
## 但它的原生绘制跟脚本 _draw 的先后顺序不受控，所以这里把五个状态样式全换成
## StyleBoxEmpty、不设 text，画面完全由 _draw 负责 —— 保留输入，丢弃外观。
##
## 「清脆」由三件事组成，缺一件就软：
##   1. 硬边：圆角 2px、边框纯填充不用抗锯齿描边
##   2. 快：0.09s 的反色过渡、0.07s 的按压回弹，比常规 UI 快一倍
##   3. 位移：悬停时文字右移 6px、左竖条加粗，让「被选中」有物理感

signal hovered

const P := preload("res://scripts/ui/menu_palette.gd")

## 反色过渡时长（秒）
const HOT_TIME := 0.09
## 悬停时文字右移量（px）
const SHIFT := 6.0
## 按下时缩到多少。0.985 是刚好能感觉到「陷下去」又不至于看出变形
const PRESS_SCALE := 0.985

var cn_text := ""
var en_text := ""
## 禁用时替代 en_text 显示的说明，例如「暂无存档」
var dead_note := ""

var _hot := 0.0
var _hot_tween: Tween


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# 五个状态全清空：外观由 _draw 决定，原生样式只会在底下透出来
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	text = ""
	custom_minimum_size = Vector2(340.0, 62.0)
	resized.connect(_sync_pivot)
	_sync_pivot()
	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)
	focus_entered.connect(_on_hover_in)
	focus_exited.connect(_on_hover_out)
	pressed.connect(_on_pressed)
	button_down.connect(_on_down)
	button_up.connect(_on_up)


func _sync_pivot() -> void:
	# 缩放要以自身中心为轴，否则按下时整块往左上跑
	pivot_offset = size * 0.5


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var hot := _hot
	var dead := disabled

	# 底：深墨绿 → 青草绿实心。
	# 常态给到 0.72 而不是更透：按钮压在草坡上，0.5 左右时底下的草会透出来，
	# 方框的边就没「一块实心板」的重量了。
	var bg := P.DEEP.lerp(P.LIME, hot)
	bg.a = lerpf(0.72, 1.0, hot)
	if dead:
		bg = P.DEEP
		bg.a = 0.46
	draw_rect(r, bg, true)

	# 边框：细、亮、硬
	var edge := P.LIME.lerp(P.CREAM, hot)
	edge.a = lerpf(0.30, 1.0, hot)
	if dead:
		edge.a = 0.18
	P.stroke(self, r, edge, 2.0)

	# 左竖条：常态 4x18，悬停拉长到 62% 高度并加粗到 8px
	var bar_h := lerpf(18.0, size.y * 0.62, hot)
	var bar_w := lerpf(4.0, 8.0, hot)
	# 反色时竖条必须跟着翻成墨绿：不然 LIME 的条画在 LIME 的底上，等于没画
	var bar_col := P.LIME.lerp(P.INK, hot) if not dead else P.MOSS
	bar_col.a = 0.95 if not dead else 0.5
	draw_rect(Rect2(2.0, (size.y - bar_h) * 0.5, bar_w, bar_h), bar_col, true)

	# 文字
	var shift := SHIFT * hot
	var cn_col := P.CREAM.lerp(P.INK, hot)
	var en_col := P.HAZE.lerp(P.MOSS, hot)
	if dead:
		cn_col = P.HAZE
		cn_col.a = 0.55
		en_col = cn_col
	P.draw_text(self, cn_text, 26.0 + shift, size.y * 0.5, 21, cn_col, "bold")
	var tail := en_text
	if dead and dead_note != "":
		tail = dead_note
	# 右边留 34px 给箭头：只留 20px 的话，反色 + 右移 6px 之后
	# 「SETTINGS」和「▶」会挤成一条
	P.draw_text(self, tail, 0.0, size.y * 0.5, 11, en_col, "wide", size.x - 34.0 + shift)

	# 悬停时右侧点一个小三角，指向「进场」
	if hot > 0.02 and not dead:
		var cx := size.x - 10.0 + shift
		var cy := size.y * 0.5
		var tri := PackedVector2Array([
			Vector2(cx - 5.0, cy - 5.0), Vector2(cx + 2.0, cy), Vector2(cx - 5.0, cy + 5.0),
		])
		var tri_col := P.INK
		tri_col.a = hot
		draw_colored_polygon(tri, tri_col)

	# 角标：左上角一个小方块。看着是装饰，实际是这套 UI 的「标点」——
	# 没有它，四个大小一样的方框会读成一排表格行
	var tick := P.CREAM if hot > 0.5 else P.LIME
	tick.a = 0.9 if not dead else 0.3
	draw_rect(Rect2(size.x - 8.0, 2.0, 6.0, 6.0), tick, true)


# ---------------------------------------------------------------- 状态

func _on_hover_in() -> void:
	if disabled:
		return
	_set_hot(1.0)
	hovered.emit()


func _on_hover_out() -> void:
	# 焦点还在身上时鼠标移开不该灭 —— 键盘选中的那一项要一直亮着
	if has_focus():
		return
	_set_hot(0.0)


func _on_down() -> void:
	if disabled:
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * PRESS_SCALE, 0.05)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)


func _on_up() -> void:
	scale = Vector2.ONE


func _on_pressed() -> void:
	scale = Vector2.ONE


## 键盘导航用：焦点落到本项但没有鼠标经过时，也要亮起来
func light(on: bool) -> void:
	_set_hot(1.0 if on else 0.0)


func _set_hot(target: float) -> void:
	if _hot_tween != null and _hot_tween.is_valid():
		_hot_tween.kill()
	_hot_tween = create_tween()
	_hot_tween.tween_method(_apply_hot, _hot, target, HOT_TIME).set_ease(Tween.EASE_OUT)


func _apply_hot(v: float) -> void:
	_hot = v
	queue_redraw()
