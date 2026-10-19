extends Node
## 开场剧情动画（无交互）。
##
## 三幕：日常 → 异变 → 穿越。
## 全部手段都是参数级的：相机目标值、灯光能量、粒子 speed_scale、着色器 uniform、
## 全屏色块 alpha。没有任何动画资源。
##
## 相机不用另写：main.gd 的 _yaw_t / _pitch_t / _dist_t / _target_t 本来就是
## 「目标值 + 每帧插值」的结构，这里只要给这四个值打 Tween，画面天然平滑。

## 占位标题，等定稿再换
const TITLE := "发生了什么？"

## 镜头注视点（和 main.gd 的初始 target 一致）
const TARGET := Vector3(0.0, 1.2, -0.95)

var _main: Node3D
var _actor: Node3D
var _ui: CanvasLayer
var _sub: Label
var _title: Label
var _flash: ColorRect
var _rain_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _drone_player: AudioStreamPlayer
var _aborted := false


func setup(main_node: Node3D, actor: Node3D) -> void:
	_main = main_node
	_actor = actor
	_build_ui()
	_build_audio()


# ---------------------------------------------------------------- 主时间轴

func play() -> void:
	# 从黑场开始
	_flash.color = Color(0, 0, 0, 1)
	_start_rain()

	# ---------- 第一幕 · 日常 ----------
	await _wait(0.8)
	if _aborted: return
	_snap_cam(46.0, 24.0, 15.4)
	_fade(Color(0, 0, 0, 0), 1.5)
	await _cam(46.0, 21.0, 11.5, TARGET, 5.5)
	if _aborted: return

	_say("那天晚上，我只是出门买点东西。", 3.0)
	await _cam(24.0, 14.0, 12.0, TARGET, 4.0)
	if _aborted: return

	# ---------- 第二幕 · 异变 ----------
	await _wait(0.3)
	if _aborted: return
	await _lightning()           # 一道雷 + 白光
	if _aborted: return
	_dash()                      # 抱着头冲进雨里
	await _wait(1.2)
	if _aborted: return

	_freeze_rain()               # 雨冻在空中，雨声同时被掐断
	_say("——雨停了。", 2.0)
	await _cam(92.0, 16.0, 13.0, TARGET, 4.5)
	if _aborted: return

	_dim_lights()                # 灯一盏盏灭
	await _cam(92.0, 18.0, 11.0, TARGET, 4.0)
	if _aborted: return

	_stop_ripples()              # 涟漪冻住
	await _wait(1.2)
	if _aborted: return

	_reverse_rain()              # 雨开始往上落
	_say("有什么东西，正在往回走。", 3.0)
	await _cam(-34.0, 22.0, 12.0, TARGET, 4.0)
	if _aborted: return

	_desaturate()                # 颜色抽走
	await _wait(1.8)
	if _aborted: return

	# ---------- 第三幕 · 穿越 ----------
	await _cam(26.0, 14.5, 17.0, TARGET, 3.0)
	if _aborted: return
	_stop_audio(0.6)             # 穿越的瞬间，这个世界的声音先消失
	_roll(26.0, 1.8)             # 画面开始倾斜
	await _wait(1.1)
	if _aborted: return
	await _flash_white(0.18)
	if _aborted: return

	# 白屏沉成深蓝，标题才有对比度（白底上放白字是看不见的）
	_settle_after_flash()
	await _wait(1.2)
	if _aborted: return
	_show_title(TITLE)
	await _wait(3.5)
	if _aborted: return

	await _fade_to_black(2.0)
	_cleanup()


# ---------------------------------------------------------------- 相机

## 画面倾斜。相机本身由 main.gd 驱动，这里只改它的 roll 值，
## main.gd 在 look_at 之后会绕视线轴旋转这个角度。
func _roll(deg: float, dur: float) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_main, "roll", deg_to_rad(deg), dur)


func _snap_cam(yaw_deg: float, pitch_deg: float, dist: float) -> void:
	_main.set("_yaw_t", deg_to_rad(yaw_deg))
	_main.set("_pitch_t", deg_to_rad(pitch_deg))
	_main.set("_dist_t", dist)
	_main.set("yaw", deg_to_rad(yaw_deg))
	_main.set("pitch", deg_to_rad(pitch_deg))
	_main.set("dist", dist)


func _cam(yaw_deg: float, pitch_deg: float, dist: float, target: Vector3, dur: float) -> void:
	if _aborted:
		return
	var tw := create_tween().set_parallel(true) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_main, "_yaw_t", deg_to_rad(yaw_deg), dur)
	tw.tween_property(_main, "_pitch_t", deg_to_rad(pitch_deg), dur)
	tw.tween_property(_main, "_dist_t", dist, dur)
	tw.tween_property(_main, "_target_t", target, dur)
	await tw.finished


# ---------------------------------------------------------------- 演出手段

func _dash() -> void:
	if _actor != null and _actor.has_method("dash"):
		_actor.dash()


## 雨冻在空中：粒子系统 speed_scale = 0 即暂停。
## 关键是**同时把雨声掐断**——视觉上雨停了、声音还在，冲击力会掉一半。
func _freeze_rain() -> void:
	var rain := _main.get_node_or_null("Rain") as GPUParticles3D
	if rain != null:
		rain.speed_scale = 0.0
	if _rain_player != null:
		_rain_player.stop()
	# 雨声一断就用低频底噪填住，不留绝对静音
	_start_drone()


## 雨往上落：把速度区间改成负值，位移方向就反了（不用改 shader）
func _reverse_rain() -> void:
	var rain := _main.get_node_or_null("Rain") as GPUParticles3D
	if rain == null:
		return
	var pm := rain.process_material as ShaderMaterial
	if pm != null:
		pm.set_shader_parameter("speed_min", -9.0)
		pm.set_shader_parameter("speed_max", -13.0)
	rain.speed_scale = 1.0


## 涟漪冻住：ring_speed 归零，相位不再推进
func _stop_ripples() -> void:
	var grp := _main.get_node_or_null("RainRipples")
	if grp == null:
		return
	for mi in grp.get_children():
		var mat := (mi as MeshInstance3D).material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("ring_speed", 0.0)


## 灯一盏盏灭：月光 → 补光 → 环境光，同时雾变浓
func _dim_lights() -> void:
	var moon: DirectionalLight3D = _main.get("_moon")
	var fill: DirectionalLight3D = _main.get("_fill")
	var env: Environment = _main.get("_env")
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	if moon != null:
		tw.tween_property(moon, "light_energy", 0.22, 5.0)
	if fill != null:
		tw.tween_property(fill, "light_energy", 0.03, 5.0)
	if env != null:
		tw.tween_property(env, "ambient_light_energy", 0.03, 5.0)
		tw.tween_property(env, "fog_density", 0.026, 5.0)


## 颜色抽走
func _desaturate() -> void:
	var env: Environment = _main.get("_env")
	if env != null:
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(env, "adjustment_saturation", 0.45, 2.5)


# ---------------------------------------------------------------- 声音

func _build_audio() -> void:
	var rain := load("res://audio/rain_loop.wav") as AudioStreamWAV
	if rain != null:
		rain.loop_mode = AudioStreamWAV.LOOP_FORWARD
		rain.loop_begin = 0
		rain.loop_end = int(rain.get_length() * float(rain.mix_rate))
		_rain_player = AudioStreamPlayer.new()
		_rain_player.stream = rain
		_rain_player.volume_db = -60.0
		add_child(_rain_player)

	var th := load("res://audio/thunder.wav") as AudioStreamWAV
	if th != null:
		_thunder_player = AudioStreamPlayer.new()
		_thunder_player.stream = th
		_thunder_player.volume_db = -1.0
		add_child(_thunder_player)

	var dr := load("res://audio/drone_loop.wav") as AudioStreamWAV
	if dr != null:
		dr.loop_mode = AudioStreamWAV.LOOP_FORWARD
		dr.loop_begin = 0
		dr.loop_end = int(dr.get_length() * float(dr.mix_rate))
		_drone_player = AudioStreamPlayer.new()
		_drone_player.stream = dr
		_drone_player.volume_db = -60.0
		add_child(_drone_player)


## 雨停后的沉闷底噪。雨声被掐断后不能留绝对静音，
## 否则观众会怀疑音频断了；用低频拍频填住，压迫感反而更强。
func _start_drone() -> void:
	if _drone_player == null:
		return
	_drone_player.volume_db = -60.0
	_drone_player.play()
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_drone_player, "volume_db", -11.0, 1.6)


func _stop_audio(dur: float) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	if _drone_player != null and _drone_player.playing:
		tw.tween_property(_drone_player, "volume_db", -60.0, dur)
	if _rain_player != null and _rain_player.playing:
		tw.tween_property(_rain_player, "volume_db", -60.0, dur)


## 从黑场淡入雨声
func _start_rain() -> void:
	if _rain_player == null:
		return
	_rain_player.volume_db = -60.0
	_rain_player.play()
	var tw := create_tween()
	tw.tween_property(_rain_player, "volume_db", -9.0, 2.0)


## 雷光 + 雷声。先闪，稍晚才响 —— 声音比光慢，这一下会让画面立刻变真。
func _lightning() -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "color", Color(1, 1, 1, 0.95), 0.05)
	tw.tween_property(_flash, "color", Color(1, 1, 1, 0.12), 0.09)
	tw.tween_property(_flash, "color", Color(1, 1, 1, 0.80), 0.06)
	tw.tween_property(_flash, "color", Color(0, 0, 0, 0), 0.45)
	await tw.finished
	# 雷声延后 0.25 秒，模拟声速
	get_tree().create_timer(0.25).timeout.connect(_play_thunder)


func _play_thunder() -> void:
	if _aborted or _thunder_player == null:
		return
	_thunder_player.play()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)

	# 电影黑边
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		if top:
			bar.anchor_top = 0.0
			bar.anchor_bottom = 0.0
			bar.offset_bottom = 78.0
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -78.0
		_ui.add_child(bar)

	# 字幕
	_sub = Label.new()
	_sub.anchor_left = 0.08
	_sub.anchor_right = 0.92
	_sub.anchor_top = 1.0
	_sub.anchor_bottom = 1.0
	_sub.offset_top = -160.0
	_sub.offset_bottom = -110.0
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 26)
	_sub.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.modulate.a = 0.0
	_ui.add_child(_sub)

	# 标题
	_title = Label.new()
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.anchor_top = 0.0
	_title.anchor_bottom = 1.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 72)
	_title.add_theme_color_override("font_color", Color(0.86, 0.9, 1.0))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.modulate.a = 0.0
	_ui.add_child(_title)

	# 全屏遮罩（黑场 / 白闪）
	_flash = ColorRect.new()
	_flash.color = Color(0, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.anchor_right = 1.0
	_flash.anchor_bottom = 1.0
	_ui.add_child(_flash)

	# 标题必须画在白闪遮罩之上，否则白屏会把标题盖住
	_ui.move_child(_title, _ui.get_child_count() - 1)


func _say(text: String, hold: float) -> void:
	if _aborted:
		return
	_sub.text = text
	var tw := create_tween()
	tw.tween_property(_sub, "modulate:a", 1.0, 0.4)
	tw.tween_interval(hold)
	tw.tween_property(_sub, "modulate:a", 0.0, 0.5)


func _show_title(text: String) -> void:
	_title.text = text
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.2)


func _fade(to: Color, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "color", to, dur)


func _flash_white(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_flash, "color", Color(1, 1, 1, 1), dur)
	await tw.finished


## 白屏沉成深蓝：给标题一个能看清的底色
func _settle_after_flash() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flash, "color", Color(0.02, 0.03, 0.08, 1.0), 2.0)


func _fade_to_black(dur: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_flash, "color", Color(0, 0, 0, 1), dur)
	tw.tween_property(_title, "modulate:a", 0.0, dur * 0.5)
	await tw.finished


func _wait(sec: float) -> void:
	if _aborted:
		return
	await get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- 跳过 / 收尾

func _unhandled_input(event: InputEvent) -> void:
	if _aborted:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_SPACE:
			skip()
			get_viewport().set_input_as_handled()


## 跳到结尾：停掉所有补间，直接黑场收尾
func skip() -> void:
	_aborted = true
	for t in get_tree().get_processed_tweens():
		t.kill()
	_flash.color = Color(0, 0, 0, 1)
	_sub.modulate.a = 0.0
	_title.modulate.a = 0.0
	_cleanup()


func _cleanup() -> void:
	# 动画结束后把 UI 和声音收掉，交还场景（相机是自由轨道，玩家可以自己转）
	if _ui != null:
		_ui.visible = false
	for p in [_rain_player, _thunder_player, _drone_player]:
		if p != null:
			p.stop()
	_main.set("roll", 0.0)       # 把画面扳正，否则交还场景后一直是歪的
	set_process_unhandled_input(false)
