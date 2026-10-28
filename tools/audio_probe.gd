extends Node
## 音频合并层（AudioBus / AudioVoice）的回归测试。
##
##   ./tools/run.sh --headless audio_probe
##
## 只验「合并与生命周期」这类不听日志就看不出问题的事：
##   - 2D 一次性音效确实并进一个复音播放器，满了按优先级取舍；
##   - 3D 一次性音效走固定池，播完能回收；
##   - 同一发射器只建一个复音播放器；
##   - 命名声道会循环、淡出中能被接管、owner 释放后回收；
##   - 循环用的是流副本，不会把 Sfx 的静态缓存改成循环。

const Sfx := preload("res://scripts/sfx.gd")
const WorldLinks := preload("res://scripts/core/world_links.gd")

var _pass := 0
var _fail := 0
var _finished := false


func _ready() -> void:
	# 探针里有等待真实时间的计时器；万一中途脚本报错，没有看门狗会挂死 check.sh。
	get_tree().create_timer(30.0).timeout.connect(_on_watchdog)
	await _run()
	_finish()


func _run() -> void:
	var bus = get_node_or_null("/root/AudioBus")
	_check("AudioBus autoload 已加载", bus != null)
	if bus == null:
		return

	# 入口在 EP.03 从 store_walk 换成了 main_menu。原来这条锁死文件名，一换入口就红；
	# 它真正想守的是「main_scene 别写成坏路径、别指向没登记的场景」，按这个写才不挡后续调整。
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene"))
	_check("默认入口指向真实存在的场景", ResourceLoader.exists(main_scene))
	_check("默认入口已在世界连接表登记", _listed(main_scene))
	_check("Ambience 总线存在", bus.has_bus(&"Ambience"))
	_check("SFX 总线存在", bus.has_bus(&"SFX"))
	_check("Music 总线存在", bus.has_bus(&"Music"))
	_check("不存在的总线能被识别", not bus.has_bus(&"NoSuchBus"))
	_check("Master 限幅器已挂上",
			AudioServer.get_bus_effect_count(0) == 1
			and AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter)

	# ---- 2D：合并、上限、优先级
	var one = bus.play_2d(Sfx.tap(), {"db": -20.0})
	await get_tree().process_frame
	await get_tree().process_frame
	if one == null:
		one = bus.play_2d(Sfx.tap(), {"db": -20.0})
	_check("2D 一次性音效拿到句柄", one != null)
	if one != null:
		_check("句柄音量可读", is_equal_approx(one.volume_db, -20.0))
		one.volume_db = -12.0
		_check("句柄音量可写", is_equal_approx(one.volume_db, -12.0))
		one.stop()
		_check("句柄 stop 后不再播放", not one.playing)
	await get_tree().create_timer(0.5).timeout
	_check("2D 复音槽已清空", bus.active_2d_voices() == 0)

	# 用 0.85s 的 bell 填满，避免检查期间自然播完造成计数抖动。
	for i in bus.polyphony_2d():
		bus.play_2d(Sfx.bell(), {"db": -40.0})
	await get_tree().process_frame
	await get_tree().process_frame
	_check("2D 合并到 %d 条复音" % bus.polyphony_2d(),
			bus.active_2d_voices() == bus.polyphony_2d())

	var overflow = bus.play_2d(Sfx.tap(), {"db": -40.0})
	await get_tree().process_frame
	_check("同优先级塞满时丢新声音",
			overflow == null and bus.active_2d_voices() == bus.polyphony_2d())

	var high = bus.play_2d(Sfx.tap(), {"db": -40.0, "priority": 10})
	_check("抢占请求先返回空句柄（晚一帧补播）", high == null)
	# 槽位由音频线程释放，多久空出来和帧率无关；10 帧在负载高时偶发不够。
	# 60 帧只是「永远补不上」的兜底，不是延迟指标。
	var waited := 0
	while bus.active_2d_voices() < bus.polyphony_2d() and waited < 60:
		await get_tree().process_frame
		waited += 1
	_check("高优先级抢占后补播成功（%d 帧）" % waited,
			bus.active_2d_voices() == bus.polyphony_2d())
	await get_tree().create_timer(1.2).timeout
	_check("2D 播完后自动回收", bus.active_2d_voices() == 0)

	# ---- 3D：固定池
	for i in bus.pool_3d_size():
		bus.play_3d(Sfx.tap(), Vector3(i, 0, 0), {"db": -40.0})
	await get_tree().process_frame
	_check("3D 池最多 %d 条" % bus.pool_3d_size(),
			bus.active_3d_voices() == bus.pool_3d_size())
	bus.play_3d(Sfx.tap(), Vector3(99, 0, 0), {"db": -40.0})
	await get_tree().process_frame
	_check("3D 同优先级塞满时丢新声音",
			bus.active_3d_voices() == bus.pool_3d_size())
	await get_tree().create_timer(0.5).timeout
	_check("3D 池播完后自动回收", bus.active_3d_voices() == 0)

	# ---- 3D 发射器：一个节点一个复音播放器
	var emitter := Node3D.new()
	emitter.name = "ProbeEmitter"
	add_child(emitter)
	bus.play_on(emitter, Sfx.tap(), {"db": -20.0})
	await get_tree().process_frame
	await get_tree().process_frame
	var ev = bus.play_on(emitter, Sfx.tap(), {"db": -20.0})
	_check("同一发射器只建一个播放器", bus.emitter_player_count() == 1)
	_check("发射器复音返回可控制句柄", ev != null and ev.playing)
	emitter.queue_free()
	await get_tree().create_timer(0.4).timeout
	_check("发射器释放后播放器回收", bus.emitter_player_count() == 0)

	# ---- 命名声道：循环 / 缓存 / 淡变 / 接管
	var loop_src := Sfx.tap()
	bus.channel(&"probe_loop", loop_src, {"db": -12.0})
	await get_tree().process_frame
	_check("命名声道开始播放", bus.is_channel_playing(&"probe_loop"))
	_check("声道音量可读",
			is_equal_approx(bus.channel_volume_db(&"probe_loop"), -12.0))
	_check("循环使用流副本，未污染 Sfx 缓存",
			loop_src.loop_mode == AudioStreamWAV.LOOP_DISABLED)
	_check("声道名只出现一次",
			bus.channel_ids().count(&"probe_loop") == 1)

	await get_tree().create_timer(0.4).timeout
	_check("超过源长度仍在循环", bus.is_channel_playing(&"probe_loop"))

	bus.fade_channel(&"probe_loop", -30.0, 0.08)
	await get_tree().create_timer(0.2).timeout
	_check("声道淡变到目标",
			is_equal_approx(bus.channel_volume_db(&"probe_loop"), -30.0))

	bus.stop_channel(&"probe_loop", 0.3)
	bus.channel(&"probe_loop", loop_src, {"db": -12.0})
	await get_tree().create_timer(0.6).timeout
	_check("淡出中被重新申请会接管，而不是停下",
			bus.is_channel_playing(&"probe_loop"))
	_check("接管后音量回到目标",
			is_equal_approx(bus.channel_volume_db(&"probe_loop"), -12.0))

	var bell_src := Sfx.bell()
	bus.channel(&"probe_loop", bell_src, {"db": -12.0})
	await get_tree().process_frame
	_check("换流会重建，但仍只有一个同名声道",
			bus.is_channel_playing(&"probe_loop")
			and bus.channel_ids().count(&"probe_loop") == 1)
	_check("换流后新缓存也未被污染",
			bell_src.loop_mode == AudioStreamWAV.LOOP_DISABLED)
	bus.stop_channel(&"probe_loop", 0.0)
	_check("stop_channel(0) 立即移除", not bus.channel_ids().has(&"probe_loop"))

	# ---- 命名声道：owner 生命周期
	var owner_node := Node.new()
	owner_node.name = "ProbeOwner"
	add_child(owner_node)
	bus.channel(&"probe_owned", Sfx.tap(), {"owner": owner_node, "db": -20.0})
	# 同一 owner 的第二条声道：钉住「tree_exiting 只连一条、按 owner 收拢」的实现。
	# 之前两条各 bind 一次，Godot 不比较 bind 参数，第二条会静默不连、卸载时漏收。
	bus.channel(&"probe_owned_2", Sfx.bell(), {"owner": owner_node, "db": -24.0})
	await get_tree().process_frame
	_check("绑定 owner 的声道在播", bus.is_channel_playing(&"probe_owned"))
	_check("同一 owner 的第二条声道也在播", bus.is_channel_playing(&"probe_owned_2"))
	owner_node.queue_free()
	await get_tree().create_timer(0.8).timeout
	_check("owner 释放后两条声道都回收",
			not bus.is_channel_playing(&"probe_owned")
			and not bus.channel_ids().has(&"probe_owned")
			and not bus.is_channel_playing(&"probe_owned_2")
			and not bus.channel_ids().has(&"probe_owned_2"))

	# ---- 命名声道：非循环播完自动回收
	bus.channel(&"probe_once", Sfx.tap(), {"loop": false, "db": -20.0})
	await get_tree().process_frame
	_check("非循环声道在播", bus.is_channel_playing(&"probe_once"))
	await get_tree().create_timer(0.7).timeout
	_check("非循环声道播完自动回收", not bus.channel_ids().has(&"probe_once"))

	# ---- 转场切声：四种形态一起收，新场景之后再申请
	var cut_emitter := Node3D.new()
	cut_emitter.name = "ProbeCutEmitter"
	add_child(cut_emitter)
	bus.channel(&"probe_cut", Sfx.tap(), {"db": -20.0})
	bus.play_2d(Sfx.bell(), {"db": -32.0})
	bus.play_3d(Sfx.bell(), Vector3.ZERO, {"db": -32.0})
	bus.play_on(cut_emitter, Sfx.bell(), {"db": -32.0})
	await get_tree().process_frame
	await get_tree().process_frame
	_check("转场前声道 / 2D / 3D / 发射器都在播",
			bus.is_channel_playing(&"probe_cut") and bus.active_2d_voices() > 0
			and bus.active_3d_voices() > 0 and bus.emitter_player_count() == 1)

	bus.cut_for_transition()
	await get_tree().process_frame
	_check("转场切掉 2D 复音", bus.active_2d_voices() == 0)
	_check("转场切掉 3D 池", bus.active_3d_voices() == 0)
	_check("转场切掉发射器", bus.emitter_player_count() == 0)
	# 声道走 0.2s 淡出，等它真正从表里消失。
	await get_tree().create_timer(0.45).timeout
	_check("转场切掉命名声道", not bus.channel_ids().has(&"probe_cut"))

	bus.channel(&"probe_cut_after", Sfx.tap(), {"db": -20.0})
	await get_tree().process_frame
	_check("切完新场景能立刻重新申请声道",
			bus.is_channel_playing(&"probe_cut_after"))
	bus.stop_channel(&"probe_cut_after", 0.0)
	cut_emitter.queue_free()

	# ---- 总线混音
	_check("Music 初始为 0dB", is_equal_approx(bus.bus_db(&"Music"), 0.0))
	bus.fade_bus(&"Music", -20.0, 0.05)
	await get_tree().create_timer(0.2).timeout
	_check("总线淡变到目标", is_equal_approx(bus.bus_db(&"Music"), -20.0))
	bus.set_bus_db(&"Music", 0.0)
	_check("总线音量可直接设置", is_equal_approx(bus.bus_db(&"Music"), 0.0))


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n==== audio_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _on_watchdog() -> void:
	if _finished:
		return
	_check("探针在 30s 内跑完", false)
	_finish()


## 这个路径是否在 WorldLinks.SCENES 里登记过。
## 登记是 bind_scene 的前提：没登记的路径可以直接 load，但拿不到 from_scene 语义。
func _listed(path: String) -> bool:
	for key: StringName in WorldLinks.SCENES:
		if str(WorldLinks.SCENES[key].get("path", "")) == path:
			return true
	return false


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label)
