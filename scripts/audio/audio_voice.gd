class_name AudioVoice
extends RefCounted
## 一次「能控制」的播放句柄，遮住两种播放形态的差异。
##
## AudioBus 里同时存在这两种形态：
##   - 声道（雨、广播、耳鸣）各占一个 AudioStreamPlayer，要能独立调音量、淡出；
##   - 一次性音效合并进 AudioStreamPolyphonic，只拿得到一个 int 流 id。
## 调用方不该关心自己拿到的是哪一种，所以统一包成 AudioVoice。
##
## 这是 RefCounted 而不是 Node：句柄本身不进场景树，扔掉它声音照播。
## 反过来说，句柄不负责保活播放器 —— 播放器归 AudioBus 管。

enum Kind { DEDICATED, POLYPHONIC }

const MIN_DB := -60.0

var _kind: int
var _player: Node
var _playback: AudioStreamPlaybackPolyphonic
var _stream_id := -1
var _db := 0.0
var _pitch := 1.0
var _tween: Tween
var _stopped := false


## 独占播放器：声道用。音量/音高直接读写 AudioStreamPlayer(3D)。
static func dedicated(player: Node) -> AudioVoice:
	var voice := AudioVoice.new()
	voice._kind = Kind.DEDICATED
	voice._player = player
	voice._db = float(player.get("volume_db"))
	voice._pitch = float(player.get("pitch_scale"))
	return voice


## 复音播放器里的一条流：一次性音效用。同一个播放器上的其他流不受影响。
static func polyphonic(player: Node, playback: AudioStreamPlaybackPolyphonic,
		stream_id: int, db: float, pitch: float) -> AudioVoice:
	var voice := AudioVoice.new()
	voice._kind = Kind.POLYPHONIC
	voice._player = player
	voice._playback = playback
	voice._stream_id = stream_id
	voice._db = db
	voice._pitch = pitch
	return voice


var volume_db: float:
	get:
		if _kind == Kind.DEDICATED and is_instance_valid(_player):
			return float(_player.get("volume_db"))
		return _db
	set(value):
		_db = value
		if _kind == Kind.DEDICATED:
			if is_instance_valid(_player):
				_player.set("volume_db", value)
		elif _alive_playback() and _playback.is_stream_playing(_stream_id):
			_playback.set_stream_volume(_stream_id, value)


var pitch_scale: float:
	get:
		if _kind == Kind.DEDICATED and is_instance_valid(_player):
			return float(_player.get("pitch_scale"))
		return _pitch
	set(value):
		_pitch = value
		if _kind == Kind.DEDICATED:
			if is_instance_valid(_player):
				_player.set("pitch_scale", value)
		elif _alive_playback() and _playback.is_stream_playing(_stream_id):
			_playback.set_stream_pitch_scale(_stream_id, value)


var playing: bool:
	get:
		# stop_stream 的音符槽位要等音频线程处理，同帧 is_stream_playing 仍可能是 true。
		# 句柄自己记住「已经停过」，调用方 stop() 之后读到的状态才是即时的。
		if _stopped:
			return false
		if _kind == Kind.DEDICATED:
			return is_instance_valid(_player) and bool(_player.get("playing"))
		return _alive_playback() and _playback.is_stream_playing(_stream_id)


## 只对 3D 独占播放器有意义。复音流的位置由所属播放器决定。
func set_position(pos: Vector3) -> void:
	if _kind == Kind.DEDICATED and is_instance_valid(_player) and _player is Node3D:
		(_player as Node3D).global_position = pos


## 淡到目标音量。seconds <= 0 时立即生效。
func fade_to(db: float, seconds: float) -> void:
	_kill_tween()
	if seconds <= 0.0 or not _can_tween():
		volume_db = db
		return
	_tween = _player.create_tween()
	_tween.tween_property(self, "volume_db", db, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 淡出后停止。音频播放器自己不会「优雅退场」，这里替它做。
func stop(seconds := 0.0) -> void:
	_kill_tween()
	if seconds <= 0.0 or not _can_tween():
		_hard_stop()
		return
	_tween = _player.create_tween()
	_tween.tween_property(self, "volume_db", MIN_DB, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_on_stop_fade_done)


## 取消淡入淡出，停在当前音量。声道被新场景接管时用：
## 此时它正在淡出，直接取消会停在很小的音量，调用方随后要再 fade_to 回去。
func cancel_fade() -> void:
	_kill_tween()


func _on_stop_fade_done() -> void:
	_tween = null
	_hard_stop()


func _hard_stop() -> void:
	_stopped = true
	if _kind == Kind.DEDICATED:
		if is_instance_valid(_player):
			_player.call("stop")
	elif _alive_playback() and _playback.is_stream_playing(_stream_id):
		# 只停这一条流。整条复音播放器还要继续服务其他音效。
		_playback.stop_stream(_stream_id)


func _alive_playback() -> bool:
	return _kind == Kind.POLYPHONIC and _playback != null \
			and is_instance_valid(_playback) and is_instance_valid(_player)


## Tween 绑在播放器上，播放器不在树里时创建会失败。
func _can_tween() -> bool:
	return is_instance_valid(_player) and _player.is_inside_tree()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
