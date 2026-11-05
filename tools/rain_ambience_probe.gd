extends Node
## 雨声「事件层」的回归测试：事件音、调度、距离剔除，以及三个场景的声明表。
##
##   ./tools/run.sh --headless rain_ambience_probe
##
## 只验不听日志就看不出的事：
##   - 三种事件音都是非循环的短 WAV，不会被 Sfx 缓存污染成循环流；
##   - 事件层不自己跑时钟、不占 3D 池（用 sink 替换播放）；
##   - 远处听者不触发、禁用后不再触发；
##   - 三个可玩场景都真的声明了挂在几何上的发射点。
##
## 场景只 new() 不 add_child()：脚本会被解析编译，但不会跑 _ready() 去搭几何。

const Sfx := preload("res://scripts/sfx.gd")
const RainEvents := preload("res://scripts/audio/rain_events.gd")
const HoshiStreet := preload("res://scripts/hoshi_street.gd")
const GasStation := preload("res://scripts/gas_station.gd")
const StoreWalk := preload("res://scripts/store_walk.gd")

var _pass := 0
var _fail := 0
var _finished := false
var seen: Array = []


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(_on_watchdog)
	_check_event_streams()
	_check_scheduler()
	_check_scene_declarations()
	_finish()


# ---------------------------------------------------------------- 事件音

func _check_event_streams() -> void:
	var sounds := {
		"drip": Sfx.drip(),
		"gutter": Sfx.gutter(),
		"splash": Sfx.splash(),
	}
	# 再取一次：static 缓存命中时必须是同一个实例，否则每次播放都在重新合成。
	var again := {
		"drip": Sfx.drip(),
		"gutter": Sfx.gutter(),
		"splash": Sfx.splash(),
	}
	for label in sounds:
		var s: AudioStreamWAV = sounds[label]
		_check("%s 生成出 WAV" % label, s != null)
		if s == null:
			continue
		# 单声道才能被 3D 声像正确定位；立体声素材会在 3D 池里丢掉方向感。
		_check("%s 是单声道" % label, not s.stereo)
		_check("%s 长度非零" % label, s.get_length() > 0.05)
		_check("%s 不是循环流" % label,
				s.loop_mode == AudioStreamWAV.LOOP_DISABLED)
		_check("%s 命中 static 缓存" % label, again[label] == s)
		var peak := _peak_of(s)
		_check("%s 有信号且未削平（峰值 %.3f）" % [label, peak],
				peak > 0.02 and peak < 0.99)


## 事件音是带通噪声，没有振荡器：这里只能验「没被削成方波」。
## 有没有音高要看频谱图的横向亮线，那属于人耳 / 频谱验收，不是回归断言。
func _peak_of(s: AudioStreamWAV) -> float:
	var data := s.data
	var peak := 0.0
	for i in range(0, data.size() - 1, 2):
		peak = maxf(peak, absf(float(data.decode_s16(i)) / 32768.0))
	return peak


# ---------------------------------------------------------------- 调度

func _check_scheduler() -> void:
	var re := RainEvents.new()
	add_child(re)
	var points := [
		{"pos": Vector3.ZERO, "kind": &"drip", "lo": 0.5, "hi": 1.0, "db": -20.0},
		{"pos": Vector3(1.0, 0.0, 0.0), "kind": &"gutter", "lo": 1.0, "hi": 2.0, "db": -24.0},
		{"pos": Vector3(2.0, 0.0, 0.0), "kind": &"splash", "lo": 2.0, "hi": 3.0, "db": -26.0},
	]
	seen.clear()
	re.bind(null, points)
	re.set_sink(Callable(self, "_collect"))
	_check("发射点全部登记", re.point_count() == points.size())
	_check("初始状态没有事件", re.event_count() == 0 and re.advance(0.0) == 0)

	var fired := 0
	for i in 40:
		fired += re.advance(0.5)
	_check("20 秒内持续产生事件", fired > 0)
	_check("累计计数与逐拍返回值一致", re.event_count() == fired)
	_check("sink 收到每一条事件", seen.size() == fired)
	_check("事件走环境总线，跟雨声一起被区域滤波", _all(seen, "bus", "Ambience"))
	_check("事件优先级低于交互音效", _all_low_priority(seen))
	_check("同一条缓存音被 pitch 抖动打散", _distinct_pitches(seen) > 3)
	_check("三种事件类型都出现过", _distinct_kinds(seen) == 3)

	# 远处听者不该触发：3D 池只有 12 个槽，白播一声既是浪费也是「凭空响」。
	var far := Node3D.new()
	far.position = Vector3(500.0, 0.0, 0.0)
	add_child(far)
	seen.clear()
	re.bind(far, points)
	for i in 40:
		re.advance(0.5)
	_check("远处的发射点不触发", seen.is_empty())
	far.queue_free()

	# 剧情死亡段会把事件层一起关掉，否则雨声淡出后还滴一滴水。
	seen.clear()
	re.bind(null, points)
	re.set_enabled(false)
	_check("禁用开关可读", not re.enabled())
	_check("禁用后不再触发", re.advance(100.0) == 0 and seen.is_empty())
	re.queue_free()


func _collect(kind: StringName, pos: Vector3, opts: Dictionary) -> void:
	seen.append({"kind": kind, "pos": pos, "opts": opts})


func _all(events: Array, key: String, value: String) -> bool:
	for e in events:
		if str(e["opts"].get(key, "")) != value:
			return false
	return not events.is_empty()


func _all_low_priority(events: Array) -> bool:
	for e in events:
		if int(e["opts"].get("priority", 0)) >= 0:
			return false
	return not events.is_empty()


func _distinct_pitches(events: Array) -> int:
	var out := {}
	for e in events:
		out[e["opts"].get("pitch", 1.0)] = true
	return out.size()


func _distinct_kinds(events: Array) -> int:
	var out := {}
	for e in events:
		out[e["kind"]] = true
	return out.size()


# ---------------------------------------------------------------- 场景声明

func _check_scene_declarations() -> void:
	for entry in [
			{"label": "商店街", "script": HoshiStreet},
			{"label": "加油站", "script": GasStation},
			{"label": "便利店", "script": StoreWalk},
	]:
		var scene: Node3D = entry["script"].new()
		_check("%s 脚本可实例化" % entry["label"], scene != null)
		if scene == null:
			continue
		var pts: Array = scene.rain_event_points()
		_check("%s 声明了事件发射点" % entry["label"], pts.size() >= 3)
		_check("%s 发射点字段完整" % entry["label"], _points_valid(pts))
		_check("%s 事件类型都合法" % entry["label"], _kinds_valid(pts))
		scene.free()


func _points_valid(pts: Array) -> bool:
	if pts.is_empty():
		return false
	for p in pts:
		if typeof(p) != TYPE_DICTIONARY:
			return false
		if typeof(p.get("pos")) != TYPE_VECTOR3:
			return false
		if not p.has("kind") or not p.has("lo") or not p.has("hi"):
			return false
		if float(p["lo"]) <= 0.0 or float(p["hi"]) < float(p["lo"]):
			return false
	return true


func _kinds_valid(pts: Array) -> bool:
	for p in pts:
		if not [&"drip", &"gutter", &"splash"].has(StringName(p["kind"])):
			return false
	return true


# ---------------------------------------------------------------- 框架

func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\n==== rain_ambience_probe: %d passed, %d failed ====" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _on_watchdog() -> void:
	if _finished:
		return
	_check("探针在 20s 内跑完", false)
	_finish()


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ OK ] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label)
