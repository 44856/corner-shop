extends Node
## 雨声的「事件层」：把有来源、不重复的稀疏声音挂到具体几何上。
##
## 为什么单独一层：120s 的 rain_loop 是完美闭环，任何带语义的偶发声（某处
## 滴了一串水、一辆车压过水洼）一旦录进循环，就会每 120s 精确重播一次 ——
## 那比没有更假。所以循环只负责稳态噪声床，事件在运行时随机触发，不进循环。
##
## 场景只声明发射点（位置 / 类型 / 间隔 / 电平），调度和随机在这里统一做，
## 避免三个可玩场景各写一份时钟。播放仍全部经 AudioBus 的 3D 固定池。
##
## 故意不自己 _process：区域音量、低通截止和本层的 advance() 都在场景的
## _process 里同一拍推进，拆成两个 _process 会让「进门」那一刻声音和滤波错帧。

const Sfx := preload("res://scripts/sfx.gd")

## 触发距离：超过这个距离的事件不排程播放，省 3D 池，也避免远处凭空响一声。
const DEFAULT_RADIUS := 16.0
## 3D 衰减上限略大于触发距离，边缘的声音才不会刚冒出来就消失。
const SOUND_MAX_DISTANCE := 20.0
## 低优先级：池满时永远让位给交互 / 剧情音效，绝不抢掉服务铃或撞击。
const EVENT_PRIORITY := -5
const DEFAULT_SEED := 0x7A1FE5

var _points: Array[Dictionary] = []
var _timers: Array[float] = []
var _listener: Node3D
var _rng := RandomNumberGenerator.new()
var _sink: Callable
var _enabled := true
var _fired := 0


func _init() -> void:
	_rng.seed = DEFAULT_SEED


## 发射点字段：pos / kind（drip | gutter | splash）/ lo / hi / db / radius。
## listener 传 null 表示不做距离剔除（回归探针用）。
func bind(listener: Node3D, points: Array) -> void:
	_listener = listener
	_points.clear()
	_timers.clear()
	_fired = 0
	for raw in points:
		var p: Dictionary = Dictionary(raw).duplicate()
		p["kind"] = StringName(p.get("kind", &"drip"))
		p["lo"] = maxf(float(p.get("lo", 1.2)), 0.2)
		p["hi"] = maxf(float(p.get("hi", 4.0)), float(p["lo"]) + 0.1)
		p["db"] = float(p.get("db", -22.0))
		p["radius"] = maxf(float(p.get("radius", DEFAULT_RADIUS)), 1.0)
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		p["pos"] = pos
		_points.append(p)
		# 每个点独立的随机初始相位，否则所有雨棚会在同一秒一起滴水。
		_timers.append(lerpf(float(p["lo"]), float(p["hi"]), _rng.randf()))


func set_enabled(value: bool) -> void:
	_enabled = value


func enabled() -> bool:
	return _enabled


## 给回归探针用：替换掉真正的播放，断言只验调度，不占 3D 池。
## sink 收到 (kind: StringName, pos: Vector3, opts: Dictionary)。
func set_sink(cb: Callable) -> void:
	_sink = cb


## 推进一拍，返回本拍触发的事件数。
func advance(delta: float) -> int:
	if not _enabled or _points.is_empty():
		return 0
	var origin := Vector3.ZERO
	var has_listener := is_instance_valid(_listener)
	if has_listener:
		origin = _listener.global_position
	var fired := 0
	for i in _points.size():
		_timers[i] -= delta
		if _timers[i] > 0.0:
			continue
		var p: Dictionary = _points[i]
		_timers[i] = _next_interval(p)
		var pos: Vector3 = p["pos"]
		if has_listener and origin.distance_to(pos) > float(p["radius"]):
			continue
		_emit(p)
		fired += 1
	_fired += fired
	return fired


func point_count() -> int:
	return _points.size()


func event_count() -> int:
	return _fired


## 均匀间隔会形成可听的节拍，雨不是节拍器：偶尔留一段更长的空白。
func _next_interval(p: Dictionary) -> float:
	var gap := lerpf(float(p["lo"]), float(p["hi"]), _rng.randf())
	if _rng.randf() < 0.12:
		gap *= 1.6 + _rng.randf()
	return gap


func _emit(p: Dictionary) -> void:
	var kind: StringName = p["kind"]
	var stream: AudioStream
	match kind:
		&"gutter":
			stream = Sfx.gutter()
		&"splash":
			stream = Sfx.splash()
		_:
			stream = Sfx.drip()
	var opts := {
		# 走环境总线：进店时这些事件和雨声一起被低通处理，
		# 不会「门关上了、屋外的滴水还一样脆」。
		"bus": AudioBus.BUS_AMBIENCE,
		# Sfx.* 是 static 缓存实例，每次播放都一模一样；靠 pitch / db 抖动打散。
		# 幅度压在 ±8% 以内，再大就成走音而不是「另一滴水」。
		"db": float(p["db"]) + _rng.randf_range(-2.0, 2.0),
		"pitch": 0.92 + _rng.randf() * 0.16,
		"priority": EVENT_PRIORITY,
		"max_distance": SOUND_MAX_DISTANCE,
	}
	if _sink.is_valid():
		_sink.call(kind, p["pos"], opts)
		return
	AudioBus.play_3d(stream, p["pos"], opts)
