extends Control
## 主菜单 / 登录屏。游戏的第一屏：开始 · 继续 · 设置 · 退出。
##
## 结构（全部在代码里搭，遵守 R1「场景不摆节点」）：
##   Sky     静态草原空镜（menu_sky）
##   Drift   会动的云、草叶、花粉（menu_drift）
##   Scrim   左侧渐变压暗，保证米白文字在任何草原亮度上都读得清
##   Ui      标题 / 按钮列 / 页脚
##   Settings 设置面板（浮在最上，默认隐藏）
##
## 「继续」为什么是灰的：本工程还没有存档系统，GameState 只活在内存里。
## 与其做一个点了会从头开始的假「继续」，不如明确显示 NO SAVE DATA ——
## 后者是诚实的，前者会在演示时骗人。等存档落地后，把这个按钮的 disabled
## 换成 GameState.has_save() 即可，其余部分不用动。
##
## 切场景只走 SceneRouter.goto()：直接 change_scene_to_file 会绕过转场锁与
## arrival 上下文，新场景拿不到「从菜单来的」这个 mode。

const P := preload("res://scripts/ui/menu_palette.gd")
const SkyLayer := preload("res://scripts/ui/menu_sky.gd")
const DriftLayer := preload("res://scripts/ui/menu_drift.gd")
const MenuEntry := preload("res://scripts/ui/menu_button.gd")
const MenuSlider := preload("res://scripts/ui/menu_slider.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SCENE_ID := &"main_menu"
## 「开始」去哪。第一幕是雨夜便利店，不是开场演出 ——
## opening_flow 是一条「看片 → 穿越」的演示路径，不该是默认体验。
const NEXT_SCENE := &"store_walk"

## 设置存这里。用 ConfigFile 而不是自定义格式：60 字节的东西不值得发明格式，
## 而且坏了能手工改。
const SETTINGS_PATH := "user://menu.cfg"

## 三条总线各自的音量键。顺序就是面板里的顺序。
const VOL_KEYS := ["music", "sfx", "ambience"]
const BUS_NAMES := {
	"music": &"Music",
	"sfx": &"SFX",
	"ambience": &"Ambience",
}
const VOL_LABELS := {
	"music": ["音乐", "MUSIC"],
	"sfx": ["音效", "SFX"],
	"ambience": ["环境", "AMBIENCE"],
}
const VOL_DEFAULT := {"music": 0.72, "sfx": 0.80, "ambience": 0.66}

## 映射区间。0.5 大约是 -20 dB，正常说话听得清但不吵。
const VOL_MIN_DB := -40.0
const VOL_MAX_DB := 0.0

## 菜单项。disabled 的那项不参与焦点导航（Button 的语义），
## 所以键盘上下会在「开始」和「设置」之间直接跳 —— 这正是我们要的。
const ITEMS := [
	{"id": &"start", "cn": "开始", "en": "START"},
	{"id": &"resume", "cn": "继续", "en": "CONTINUE", "dead": "NO SAVE DATA"},
	{"id": &"settings", "cn": "设置", "en": "SETTINGS"},
	{"id": &"quit", "cn": "退出", "en": "QUIT"},
]

var _sky: Control
var _drift: Control
var _scrim: TextureRect
var _ui: Control
var _title_block: Control

var _buttons: Array = []
var _settings: Control
var _panel: PanelContainer
var _sliders: Dictionary = {}
var _vol: Dictionary = {}
var _fullscreen := false
var _mode_btn: Button
var _busy := false
var _last_hover_ms := 0
var _tap: AudioStream


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 缓存一次：Sfx.tap() 每次都重新合成 PCM，在悬停这种高频路径上不能现调
	_tap = Sfx.tap()

	SceneRouter.bind_scene(SCENE_ID)
	_vol = VOL_DEFAULT.duplicate()
	_load_settings()

	_build_backdrop()
	_build_ui()
	_build_settings()

	for key in VOL_KEYS:
		_apply_audio(key)
	_apply_mode()

	_intro()


# ---------------------------------------------------------------- 背景

func _build_backdrop() -> void:
	_sky = SkyLayer.new()
	_sky.name = "Sky"
	add_child(_sky)

	_drift = DriftLayer.new()
	_drift.name = "Drift"
	add_child(_drift)

	# 左侧压暗。没有这一层，米白标题压在浅绿草坡上对比度只有 1.4:1，
	# 大字号勉强能认，11px 的英文小字直接消失。
	_scrim = TextureRect.new()
	_scrim.name = "Scrim"
	_scrim.texture = _scrim_gradient()
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.anchor_right = 0.78
	_scrim.anchor_bottom = 1.0
	add_child(_scrim)


func _scrim_gradient() -> GradientTexture2D:
	# 三段、跨度 78%：两段的话过渡带太陡，屏幕上能看见一条竖向的明暗分界，
	# 像给画面盖了半块玻璃。三段把落差摊开，边界就消失了。
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	g.colors = PackedColorArray([
		Color(P.DEEP.r, P.DEEP.g, P.DEEP.b, 0.74),
		Color(P.DEEP.r, P.DEEP.g, P.DEEP.b, 0.34),
		Color(P.DEEP.r, P.DEEP.g, P.DEEP.b, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 512
	t.height = 4
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(1.0, 0.0)
	return t


# ---------------------------------------------------------------- 前景

func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "Ui"
	# 锚点必须在 add_child 之后设：没有父节点时 set_anchors_and_offsets_preset
	# 算不出父矩形，size 会停在 0 —— 而且不会报错，只会让子节点的居中算错。
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_title()
	_build_menu()
	_build_footer()


func _build_title() -> void:
	_title_block = VBoxContainer.new()
	_title_block.name = "Title"
	_title_block.position = Vector2(112.0, 150.0)
	_title_block.add_theme_constant_override("separation", 6)
	_title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_title_block)

	var kicker := P.label("I S E K A I   ·   E P . 0 3", 12, P.LIME, "wide")
	_title_block.add_child(kicker)

	var big := P.label("RAINY CORNER", 58, P.CREAM, "title")
	# 描边 + 偏移阴影。二次元标题的「厚」几乎全靠这两样，
	# 光靠字号在浅色背景上会显得飘。
	big.add_theme_color_override("font_outline_color", P.INK)
	big.add_theme_constant_override("outline_size", 9)
	big.add_theme_color_override("font_shadow_color", Color(0.03, 0.07, 0.04, 0.55))
	big.add_theme_constant_override("shadow_offset_x", 3)
	big.add_theme_constant_override("shadow_offset_y", 4)
	big.add_theme_constant_override("shadow_outline_size", 2)
	_title_block.add_child(big)

	var rule := ColorRect.new()
	rule.color = P.LIME
	rule.custom_minimum_size = Vector2(64.0, 3.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 分隔线不占满整行：64px 是一段「语气」，拉满到 400px 就成了分割栏
	var rule_box := HBoxContainer.new()
	rule_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_box.add_child(rule)
	rule_box.add_child(Control.new())  # 撑开右侧留白
	_title_block.add_child(rule_box)

	var sub := P.label("雨夜便利店街角", 16, P.HAZE)
	sub.add_theme_color_override("font_outline_color", Color(0.03, 0.07, 0.04, 0.7))
	sub.add_theme_constant_override("outline_size", 5)
	_title_block.add_child(sub)


func _build_menu() -> void:
	var col := VBoxContainer.new()
	col.name = "Menu"
	col.position = Vector2(112.0, 442.0)
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(col)

	for i in ITEMS.size():
		var spec: Dictionary = ITEMS[i]
		var b := MenuEntry.new()
		b.name = String(spec["id"])
		b.cn_text = String(spec["cn"])
		b.en_text = String(spec["en"])
		if spec.has("dead"):
			b.disabled = true
			b.dead_note = String(spec["dead"])
		col.add_child(b)
		_buttons.append(b)
		b.hovered.connect(_sfx_hover)
		b.pressed.connect(_on_item.bind(StringName(spec["id"])))

	# 手动接上下焦点环，让它首尾相接。Godot 的自动邻居只在同容器内按几何位置算，
	# 到第一项/最后一项就停了 —— 键盘用户在「开始」按上会掉出菜单。
	if _buttons.size() > 1:
		var live: Array = []
		for b in _buttons:
			if not b.disabled:
				live.append(b)
		for i in live.size():
			var up: Control = live[(i - 1 + live.size()) % live.size()]
			var down: Control = live[(i + 1) % live.size()]
			live[i].focus_neighbor_top = live[i].get_path_to(up)
			live[i].focus_neighbor_bottom = live[i].get_path_to(down)

	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _build_footer() -> void:
	var row := HBoxContainer.new()
	row.name = "Footer"
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.offset_left = -560.0
	row.offset_right = -56.0
	row.offset_top = -52.0
	row.offset_bottom = -24.0
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(row)

	for text in ["↑ ↓ 选择", "ENTER 确定", "v0.3"]:
		var l := P.label(text, 11, P.HAZE, "wide")
		l.add_theme_color_override("font_color", Color(P.HAZE.r, P.HAZE.g, P.HAZE.b, 0.80))
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.09, 0.06, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		row.add_child(l)


# ---------------------------------------------------------------- 设置面板

func _build_settings() -> void:
	_settings = Control.new()
	_settings.name = "Settings"
	_settings.visible = false
	add_child(_settings)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.07, 0.05, 0.76)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	var sb := P.box(Color(0.055, 0.115, 0.08, 0.97), Color(0.74, 0.91, 0.43, 0.50), 2, 2)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 34
	sb.content_margin_bottom = 38
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(620.0, 0.0)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_panel.add_child(col)

	# 标题行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var t := P.label("设置", 26, P.CREAM, "bold")
	head.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(P.label("SETTINGS", 11, P.LIME, "wide"))

	col.add_child(_gap(16))
	col.add_child(_rule())
	col.add_child(_gap(20))

	for key in VOL_KEYS:
		col.add_child(_volume_row(key))
		col.add_child(_gap(10))

	col.add_child(_gap(8))
	col.add_child(_rule())
	col.add_child(_gap(16))
	col.add_child(_mode_row())
	col.add_child(_gap(22))

	# 底部按钮：右对齐的返回，宽度收窄
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(foot)
	var back := MenuEntry.new()
	back.cn_text = "返回"
	back.en_text = "BACK"
	back.custom_minimum_size = Vector2(190.0, 52.0)
	back.pressed.connect(_close_settings)
	back.hovered.connect(_sfx_hover)
	foot.add_child(back)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.74, 0.91, 0.43, 0.22)
	r.custom_minimum_size = Vector2(0.0, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _volume_row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var names: Array = VOL_LABELS[key]
	var cn := P.label(String(names[0]), 16, P.CREAM)
	cn.custom_minimum_size = Vector2(52.0, 0.0)
	row.add_child(cn)

	var en := P.label(String(names[1]), 10, P.HAZE, "wide")
	en.custom_minimum_size = Vector2(96.0, 0.0)
	en.add_theme_color_override("font_color", Color(P.HAZE.r, P.HAZE.g, P.HAZE.b, 0.45))
	row.add_child(en)

	var s := MenuSlider.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value = float(_vol.get(key, 0.7))
	row.add_child(s)

	var read := P.label("", 12, P.LIME, "wide")
	read.custom_minimum_size = Vector2(58.0, 0.0)
	read.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(read)

	_sliders[key] = {"slider": s, "read": read}
	_refresh_readout(key)
	s.value_changed.connect(_on_volume.bind(key))
	return row


func _mode_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var cn := P.label("显示", 16, P.CREAM)
	cn.custom_minimum_size = Vector2(52.0, 0.0)
	row.add_child(cn)
	var en := P.label("DISPLAY", 10, P.HAZE, "wide")
	en.custom_minimum_size = Vector2(96.0, 0.0)
	en.add_theme_color_override("font_color", Color(P.HAZE.r, P.HAZE.g, P.HAZE.b, 0.45))
	row.add_child(en)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_mode_btn = MenuEntry.new()
	_mode_btn.custom_minimum_size = Vector2(180.0, 48.0)
	_mode_btn.pressed.connect(_toggle_mode)
	_mode_btn.hovered.connect(_sfx_hover)
	row.add_child(_mode_btn)
	return row


func _refresh_readout(key: String) -> void:
	if not _sliders.has(key):
		return
	var v := float(_vol.get(key, 0.7))
	var read: Label = _sliders[key]["read"]
	read.text = "MUTE" if v <= 0.005 else "%d dB" % int(round(_db_from(v)))


# ---------------------------------------------------------------- 音量与显示

func _db_from(v: float) -> float:
	if v <= 0.005:
		return -80.0
	return lerpf(VOL_MIN_DB, VOL_MAX_DB, v)


func _on_volume(value: float, key: String) -> void:
	_vol[key] = value
	_apply_audio(key)
	_refresh_readout(key)
	# 音效条拖动时要能立刻听到结果，所以这里补一声；其余两条不补，
	# 不然调音乐时会被「叮」打断
	if key == "sfx":
		_sfx_press_soft()


func _apply_audio(key: String) -> void:
	var bus: StringName = BUS_NAMES[key]
	if not AudioBus.has_bus(bus):
		return
	AudioBus.set_bus_db(bus, _db_from(float(_vol.get(key, 0.7))))


func _apply_mode() -> void:
	if _mode_btn == null:
		return
	_mode_btn.cn_text = "全屏" if _fullscreen else "窗口"
	_mode_btn.en_text = "FULLSCREEN" if _fullscreen else "WINDOWED"


func _toggle_mode() -> void:
	_fullscreen = not _fullscreen
	# headless / 无窗口环境下 DisplayServer 不接受窗口模式，直接跳过去
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	_apply_mode()
	_save_settings()


# ---------------------------------------------------------------- 交互

func _on_item(id: StringName) -> void:
	if _busy:
		return
	match id:
		&"start":
			_sfx_press()
			_start_game()
		&"settings":
			_sfx_open()
			_open_settings()
		&"quit":
			_sfx_press()
			_quit_game()


func _start_game() -> void:
	_busy = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sky, "modulate:a", 0.0, 0.55)
	tw.tween_property(_drift, "modulate:a", 0.0, 0.55)
	tw.tween_property(_scrim, "modulate:a", 0.0, 0.35)
	tw.tween_property(_ui, "modulate:a", 0.0, 0.28)
	await tw.finished

	# 走路由而不是 change_scene：转场文案、抵达上下文、后续的剧情节点
	# 都归 SceneRouter 管，菜单不该绕过它自己开一条路。
	var started := SceneRouter.goto(NEXT_SCENE, &"default", {
		"mode": &"menu",
		"transition": {
			"title": "HOSHIMI",
			"subtitle": "CONVENIENCE STORE",
			"footer": "RAINY NIGHT · 23:47",
			"accent": Color("#bce86e"),
		},
	})
	if not started:
		_busy = false
		var back := create_tween()
		back.set_parallel(true)
		back.tween_property(_sky, "modulate:a", 1.0, 0.3)
		back.tween_property(_drift, "modulate:a", 1.0, 0.3)
		back.tween_property(_scrim, "modulate:a", 1.0, 0.3)
		back.tween_property(_ui, "modulate:a", 1.0, 0.3)


func _quit_game() -> void:
	_busy = true
	await get_tree().create_timer(0.16).timeout
	get_tree().quit()


func _open_settings() -> void:
	if _settings.visible:
		return
	_settings.visible = true
	_settings.modulate.a = 0.0
	# 只做淡入，不做位移。
	# 面板是 CenterContainer 管的，手改 position 会覆盖容器的居中结果 ——
	# 之前用「下坠 18px 再回弹」做入场，结果面板永久贴在了画面顶边，
	# 因为 tween 的终点 0 恰好也是容器还没来得及排版时的初始值。
	var tw := create_tween()
	tw.tween_property(_settings, "modulate:a", 1.0, 0.16)
	var first: Dictionary = _sliders.get("music", {})
	if first.has("slider"):
		(first["slider"] as Control).grab_focus()


func _close_settings() -> void:
	_sfx_close()
	_save_settings()
	var tw := create_tween()
	tw.tween_property(_settings, "modulate:a", 0.0, 0.14)
	await tw.finished
	_settings.visible = false
	_settings.modulate.a = 1.0
	for b in _buttons:
		if not b.disabled:
			b.grab_focus()
			break


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_cancel"):
		if _settings.visible:
			_close_settings()
		else:
			_sfx_open()
			_open_settings()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 音效

func _sfx_hover() -> void:
	var now := Time.get_ticks_msec()
	# 90ms 去重：鼠标扫过四个按钮时会连续触发四次，不拦的话是一串机关枪
	if now - _last_hover_ms < 90:
		return
	_last_hover_ms = now
	AudioBus.play_2d(_tap, {"bus": &"SFX", "db": -19.0, "pitch": 1.34})


func _sfx_press() -> void:
	AudioBus.play_2d(_tap, {"bus": &"SFX", "db": -4.0, "pitch": 0.94})


func _sfx_press_soft() -> void:
	AudioBus.play_2d(_tap, {"bus": &"SFX", "db": -12.0, "pitch": 1.16})


func _sfx_open() -> void:
	AudioBus.play_2d(Sfx.whoosh(), {"bus": &"SFX", "db": -14.0, "pitch": 1.2})


func _sfx_close() -> void:
	AudioBus.play_2d(Sfx.whoosh(), {"bus": &"SFX", "db": -16.0, "pitch": 0.86})


# ---------------------------------------------------------------- 存档

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for key in VOL_KEYS:
		_vol[key] = clampf(float(cf.get_value("audio", key, VOL_DEFAULT[key])), 0.0, 1.0)
	_fullscreen = bool(cf.get_value("video", "fullscreen", false))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for key in VOL_KEYS:
		cf.set_value("audio", key, float(_vol.get(key, 0.7)))
	cf.set_value("video", "fullscreen", _fullscreen)
	cf.save(SETTINGS_PATH)


# ---------------------------------------------------------------- 入场动画

func _intro() -> void:
	_title_block.modulate.a = 0.0
	var start_x := _title_block.position.x
	_title_block.position.x = start_x - 22.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_title_block, "modulate:a", 1.0, 0.42)
	tw.tween_property(_title_block, "position:x", start_x, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for i in _buttons.size():
		var b: Control = _buttons[i]
		b.modulate.a = 0.0
		b.scale = Vector2(0.965, 0.965)
		var t := create_tween()
		t.tween_interval(0.14 + float(i) * 0.055)
		t.tween_property(b, "modulate:a", 1.0, 0.20)
		t.parallel().tween_property(b, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- 供工具调用

## 让第 index 个菜单项亮起来。截图工具用它拍「悬停态」，
## 因为 headless 下没法真的把鼠标移到按钮上。
func focus_item(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	var b: Control = _buttons[index]
	if b.disabled:
		return
	b.grab_focus()
	b.call("light", true)


## 打开设置面板（截图用，跳过音效）。
func show_settings() -> void:
	_open_settings()


func button_count() -> int:
	return _buttons.size()
