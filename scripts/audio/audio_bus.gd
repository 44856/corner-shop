extends Node
## 全局音频入口：所有播放都从这里过一道，才好合并。
##
## 为什么做成 autoload（文档 §4.3 白名单里的 AudioBus）：
##   - 2D 一次性音效不再各建一个 AudioStreamPlayer，而是合并进每条总线一个
##     AudioStreamPolyphonic。十几个门铃同时响也只有一个播放器在跑。
##   - 3D 一次性音效走固定 12 个播放器的池子，满了按优先级抢，避免瞬时
##     生成/销毁节点，也避免几十个 AudioStreamPlayer3D 各自做距离衰减。
##   - 雨、广播、耳鸣这类长音用命名声道管理。声道名是跨场景的接口：
##     新场景用同一个名字重新申请，就会接管还在淡出的旧声道，而不是叠两层。
##
## 边界：这里只持有自己创建的播放器。场景节点一律用 instance_id + WeakRef 引用，
## 不阻止场景卸载 —— autoload 活过场景切换，直接持有节点引用就是泄漏。

const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_MUSIC := &"Music"

## 2D 一次性音效每条总线的复音上限
const POLY_2D := 16
## 同一个 3D 发射器上最多同时叠多少条流
const POLY_EMITTER := 8
## 3D 一次性音效的固定池大小
const POOL_3D := 12

const POOL_UNIT_SIZE := 3.0
const POOL_MAX_DISTANCE := 14.0

const DEFAULT_FADE := 0.25
## 同一个声道被新场景接管时的淡入时长
const TAKEOVER_FADE := 0.2
const MIN_DB := -60.0
## 刚建好的流可能还没进入 playing 状态，回收判定先宽限一会儿
const VOICE_GRACE_MS := 250
## 复音流同理：play_stream() 之后音频线程要过一下才把它标成 playing。
## 不设宽限期的话，同一帧连续塞 17 条会把前几条刚塞进去的当成「已结束」删掉。
const POLY_PRUNE_GRACE_MS := 250
## 复音满了、已抢掉一条但槽位还没真正释放，下一帧再补播
const POLY_RETRY := -2

# ---- 2D 一次性音效：每条总线一个复音播放器
var _poly_players: Dictionary = {}   # bus -> AudioStreamPlayer
var _poly_playbacks: Dictionary = {} # bus -> AudioStreamPlaybackPolyphonic
var _poly_streams: Dictionary = {}   # bus -> Array[{id, priority, started, scope}]
var _poly_pending: Dictionary = {}   # bus -> Array[请求]（播放器还没就绪时排队）

# ---- 3D 一次性音效：固定池
var _pool_players: Array[AudioStreamPlayer3D] = []
var _pool_meta: Dictionary = {}      # instance_id -> {priority, started, scope}

# ---- 3D 发射器：每个节点一个复音播放器
var _emitters: Dictionary = {}       # instance_id -> {ref, player, streams, pending}

# ---- 命名声道
var _channels: Dictionary = {}       # StringName -> AudioVoice
var _channel_meta: Dictionary = {}   # StringName -> {player, source, ...}

var _bus_tweens: Dictionary = {}     # bus -> Tween

var _seq := 0
var _last_scene_id := 0


func _ready() -> void:
	for bus in [BUS_AMBIENCE, BUS_SFX, BUS_MUSIC]:
		if AudioServer.get_bus_index(bus) < 0:
			push_warning("AudioBus：总线「%s」不存在，检查 default_bus_layout.tres" % bus)
	_build_pool_3d()
	_last_scene_id = _scope_id()


func _process(_delta: float) -> void:
	_check_scene_scope()
	_activate_poly_players()
	_activate_emitters()
	_update_followers()
	_prune_channels()


# ---- 一次性音效

## 2D 一次性音效，合并进该总线的复音播放器。
## 返回的句柄可调音量/淡出；返回 null 表示播放器这一帧还没就绪（已排队）。
func play_2d(stream: AudioStream, opts: Dictionary = {}) -> AudioVoice:
	if stream == null:
		return null
	var bus := _resolve_bus(StringName(opts.get("bus", BUS_SFX)))
	_ensure_poly_player(bus)
	var db := float(opts.get("db", 0.0))
	var pitch := float(opts.get("pitch", 1.0))
	var priority := int(opts.get("priority", 0))
	var req := {
		"stream": stream,
		"db": db,
		"pitch": pitch,
		"priority": priority,
		"scope": _scope_id(),
	}
	var playback := _poly_playback(bus)
	if playback == null:
		var pending: Array = _poly_pending[bus]
		pending.append(req)
		return null
	var active: Array = _poly_streams[bus]
	var id := _play_poly_into(playback, active, stream, db, pitch, priority,
			int(req["scope"]), bus)
	if id == POLY_RETRY:
		var pending: Array = _poly_pending[bus]
		req["preempted"] = true
		pending.append(req)
		return null
	if id < 0:
		return null
	return AudioVoice.polyphonic(_poly_players[bus], playback, id, db, pitch)


## 3D 一次性音效，走固定池。故意不返回句柄：
## 池子里的播放器随时可能被更高优先级的音效抢走，拿着句柄去调音量只会调错对象。
## 需要控制的 3D 声音请用 play_on() 或 channel()。
func play_3d(stream: AudioStream, pos: Vector3, opts: Dictionary = {}) -> void:
	if stream == null:
		return
	var priority := int(opts.get("priority", 0))
	var player := _acquire_pool_player(priority)
	if player == null:
		return
	player.bus = _resolve_bus(StringName(opts.get("bus", BUS_SFX)))
	player.stream = stream
	player.volume_db = float(opts.get("db", 0.0))
	player.pitch_scale = float(opts.get("pitch", 1.0))
	player.unit_size = float(opts.get("unit_size", POOL_UNIT_SIZE))
	player.max_distance = float(opts.get("max_distance", POOL_MAX_DISTANCE))
	player.global_position = pos
	player.play()
	_pool_meta[player.get_instance_id()] = {
		"priority": priority,
		"started": _next_seq(),
		"scope": _scope_id(),
	}


## 在一个 3D 节点上播放，同一个发射器的多条流合并进一个复音播放器。
## offset 是相对发射器的局部坐标，只在第一次创建时应用。
## 返回 null 表示播放器这一帧还没就绪（已排队）。
func play_on(emitter: Node3D, stream: AudioStream, opts: Dictionary = {}) -> AudioVoice:
	if stream == null or not is_instance_valid(emitter):
		return null
	if not emitter.is_inside_tree():
		push_warning("AudioBus.play_on：发射器还不在场景树里（%s）" % emitter.name)
		return null
	var bus := _resolve_bus(StringName(opts.get("bus", BUS_SFX)))
	var emitter_id := emitter.get_instance_id()
	var entry: Dictionary = _emitters.get(emitter_id, {})
	if entry.is_empty() or not _emitter_alive(entry):
		entry = _make_emitter(emitter, bus, opts)
		_emitters[emitter_id] = entry
	var player: AudioStreamPlayer3D = entry["player"]
	player.bus = bus
	player.unit_size = float(opts.get("unit_size", POOL_UNIT_SIZE))
	player.max_distance = float(opts.get("max_distance", POOL_MAX_DISTANCE))
	var db := float(opts.get("db", 0.0))
	var pitch := float(opts.get("pitch", 1.0))
	var priority := int(opts.get("priority", 0))
	var req := {
		"stream": stream,
		"db": db,
		"pitch": pitch,
		"priority": priority,
		"scope": _scope_id(),
	}
	var playback := player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if playback == null:
		var pending: Array = entry["pending"]
		pending.append(req)
		return null
	var streams: Array = entry["streams"]
	var id := _play_poly_into(playback, streams, stream, db, pitch, priority,
			int(req["scope"]), bus)
	if id == POLY_RETRY:
		var pending: Array = entry["pending"]
		req["preempted"] = true
		pending.append(req)
		return null
	if id < 0:
		return null
	return AudioVoice.polyphonic(player, playback, id, db, pitch)


# ---- 命名声道

## 申请一个命名声道。同名同流的重复申请是「接管」，不会叠音：
##   - 还在播放：更新音量/归属；
##   - 正在淡出：取消淡出，用 TAKEOVER_FADE 淡回来。
## 不同流或 2D/3D 形态变了，则重建。
##
## opts:
##   bus/db/pitch/fade_in/loop/owner
##   pos: Vector3        —— 3D 固定位置
##   follow: Node3D      —— 3D 跟随某个节点（每帧同步坐标）
##   unit_size/max_distance —— 3D 衰减
func channel(id: StringName, stream: AudioStream, opts: Dictionary = {}) -> AudioVoice:
	if stream == null:
		return null
	var pos = opts.get("pos")
	var follow = opts.get("follow")
	var is_3d: bool = pos != null or follow != null
	var loop := bool(opts.get("loop", true))
	var db := float(opts.get("db", 0.0))
	var pitch := float(opts.get("pitch", 1.0))
	var fade_in := float(opts.get("fade_in", 0.0))
	var bus := _resolve_bus(StringName(opts.get("bus", BUS_SFX)))
	var owner_node: Node = opts.get("owner", get_tree().current_scene)

	var meta: Dictionary = _channel_meta.get(id, {})
	if not meta.is_empty():
		var voice: AudioVoice = _channels.get(id)
		var same: bool = voice != null and is_instance_valid(meta.get("player")) \
				and bool(meta.get("is_3d")) == is_3d \
				and bool(meta.get("loop")) == loop \
				and meta.get("source") == stream
		if same:
			var player: Node = meta["player"]
			player.set("bus", bus)
			meta["db"] = db
			meta["pitch"] = pitch
			meta["bus"] = bus
			_update_channel_pos(meta, pos, follow)
			_bind_owner(meta, owner_node, id)
			if bool(meta.get("releasing")):
				meta["releasing"] = false
				voice.cancel_fade()
				voice.fade_to(db, TAKEOVER_FADE)
			else:
				voice.volume_db = db
				voice.pitch_scale = pitch
			return voice
		_drop_channel(id)

	var played_stream: AudioStream = _make_loop_stream(stream) if loop else stream
	var player: Node
	if is_3d:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Channel3D_" + String(id)
		p3.bus = bus
		p3.stream = played_stream
		p3.volume_db = db if fade_in <= 0.0 else MIN_DB
		p3.pitch_scale = pitch
		p3.unit_size = float(opts.get("unit_size", POOL_UNIT_SIZE))
		p3.max_distance = float(opts.get("max_distance", POOL_MAX_DISTANCE))
		add_child(p3)
		player = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.name = "Channel_" + String(id)
		p2.bus = bus
		p2.stream = played_stream
		p2.volume_db = db if fade_in <= 0.0 else MIN_DB
		p2.pitch_scale = pitch
		add_child(p2)
		player = p2
	player.call("play")

	var new_meta := {
		"player": player,
		"source": stream,
		"loop": loop,
		"is_3d": is_3d,
		"db": db,
		"pitch": pitch,
		"bus": bus,
		"owner_id": 0,
		"owner_ref": null,
		"owner_cb": null,
		"releasing": false,
		"follow_ref": null,
		"created": Time.get_ticks_msec(),
	}
	_update_channel_pos(new_meta, pos, follow)
	_bind_owner(new_meta, owner_node, id)
	var voice := AudioVoice.dedicated(player)
	_channels[id] = voice
	_channel_meta[id] = new_meta
	if fade_in > 0.0:
		voice.fade_to(db, fade_in)
	return voice


func fade_channel(id: StringName, db: float, seconds := DEFAULT_FADE) -> void:
	var voice: AudioVoice = _channels.get(id)
	if voice == null:
		return
	var meta: Dictionary = _channel_meta.get(id, {})
	meta["releasing"] = false
	voice.fade_to(db, seconds)


func stop_channel(id: StringName, seconds := DEFAULT_FADE) -> void:
	var voice: AudioVoice = _channels.get(id)
	if voice == null:
		return
	if seconds <= 0.0:
		_drop_channel(id)
		return
	var meta: Dictionary = _channel_meta.get(id, {})
	meta["releasing"] = true
	voice.stop(seconds)


func channel_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _channels:
		out.append(id)
	return out


func channel_volume_db(id: StringName) -> float:
	var voice: AudioVoice = _channels.get(id)
	return voice.volume_db if voice != null else MIN_DB


func is_channel_playing(id: StringName) -> bool:
	var voice: AudioVoice = _channels.get(id)
	return voice != null and voice.playing


# ---- 总线混音

func has_bus(bus: StringName) -> bool:
	return AudioServer.get_bus_index(bus) >= 0


func bus_db(bus: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0


func set_bus_db(bus: StringName, db: float) -> void:
	var idx := _bus_index(bus)
	if idx < 0:
		return
	_kill_bus_tween(bus)
	AudioServer.set_bus_volume_db(idx, db)


func fade_bus(bus: StringName, db: float, seconds := DEFAULT_FADE) -> void:
	var idx := _bus_index(bus)
	if idx < 0:
		return
	_kill_bus_tween(bus)
	if seconds <= 0.0:
		AudioServer.set_bus_volume_db(idx, db)
		return
	var tw := create_tween()
	_bus_tweens[bus] = tw
	tw.tween_method(
			func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
			AudioServer.get_bus_volume_db(idx), db, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_on_bus_tween_done.bind(bus, tw))


# ---- 调试/探针

func active_2d_voices() -> int:
	var total := 0
	for bus in _poly_streams:
		var playback = _poly_playbacks.get(bus)
		if playback == null:
			continue
		_prune_poly_streams(playback, _poly_streams[bus])
		total += (_poly_streams[bus] as Array).size()
	return total


func polyphony_2d() -> int:
	return POLY_2D


func active_3d_voices() -> int:
	for p in _pool_players:
		var id := p.get_instance_id()
		if _pool_meta.has(id) and not p.playing:
			_pool_meta.erase(id)
	return _pool_meta.size()


func pool_3d_size() -> int:
	return _pool_players.size()


func emitter_player_count() -> int:
	for id in _emitters.keys():
		if not _emitter_alive(_emitters[id]):
			_emitters.erase(id)
	return _emitters.size()


func debug_snapshot() -> Dictionary:
	var channels := {}
	for id in _channel_meta:
		var meta: Dictionary = _channel_meta[id]
		var voice: AudioVoice = _channels.get(id)
		channels[String(id)] = {
			"db": voice.volume_db if voice != null else MIN_DB,
			"playing": voice.playing if voice != null else false,
			"loop": bool(meta.get("loop", false)),
			"3d": bool(meta.get("is_3d", false)),
			"releasing": bool(meta.get("releasing", false)),
		}
	return {
		"buses": {
			String(BUS_AMBIENCE): bus_db(BUS_AMBIENCE),
			String(BUS_SFX): bus_db(BUS_SFX),
			String(BUS_MUSIC): bus_db(BUS_MUSIC),
		},
		"2d_voices": active_2d_voices(),
		"polyphony_2d": POLY_2D,
		"3d_voices": active_3d_voices(),
		"pool_3d": _pool_players.size(),
		"emitters": _emitters.size(),
		"channels": channels,
	}


# ---- 内部：2D 复音

func _ensure_poly_player(bus: StringName) -> void:
	if _poly_players.has(bus):
		return
	var player := AudioStreamPlayer.new()
	player.name = "Poly2D_" + String(bus)
	player.bus = bus
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = POLY_2D
	player.stream = poly
	add_child(player)
	_poly_players[bus] = player
	_poly_streams[bus] = []
	_poly_pending[bus] = []


func _poly_playback(bus: StringName) -> AudioStreamPlaybackPolyphonic:
	var player: AudioStreamPlayer = _poly_players.get(bus)
	if player == null:
		return null
	# 所有流结束后播放器可能自己停了，再 play() 一次拿回复音对象。
	if not player.playing:
		player.play()
	var playback := player.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if playback != null:
		_poly_playbacks[bus] = playback
	return playback


func _activate_poly_players() -> void:
	for bus in _poly_pending:
		var pending: Array = _poly_pending[bus]
		if pending.is_empty():
			continue
		var playback := _poly_playback(bus)
		if playback == null:
			continue
		var active: Array = _poly_streams[bus]
		var retry: Array = []
		while not pending.is_empty():
			var req: Dictionary = pending.pop_front()
			if int(req["scope"]) != _scope_id():
				continue
			var id := _play_poly_into(playback, active, req["stream"], float(req["db"]),
					float(req["pitch"]), int(req["priority"]), int(req["scope"]), bus,
					not bool(req.get("preempted", false)))
			if id == POLY_RETRY:
				req["preempted"] = true
				retry.append(req)
		pending.append_array(retry)


## 往复音播放器里塞一条流。满了只有「严格更高优先级」能抢，
## 同优先级直接丢新的 —— 抢一个同样重要的声音来播另一个，听感上只是无故断一下。
## 返回 -1 表示丢弃；POLY_RETRY 表示已经抢掉一条、等下一帧槽位真正空出来。
func _play_poly_into(playback: AudioStreamPlaybackPolyphonic, active: Array,
		stream: AudioStream, db: float, pitch: float, priority: int,
		scope: int, bus: StringName, may_steal := true) -> int:
	_prune_poly_streams(playback, active)
	var id := playback.play_stream(stream, 0.0, db, pitch,
			AudioServer.PLAYBACK_TYPE_DEFAULT, bus)
	if id < 0:
		if not may_steal:
			return POLY_RETRY
		var victim := _pick_stream_victim(active, priority)
		if victim < 0:
			return -1
		playback.stop_stream(int(active[victim]["id"]))
		active.remove_at(victim)
		# stop_stream 只是标记，音频线程这一帧仍占着槽位，重试多半还是 -1。
		# 不重试，交给调用方下一帧补播；重试时 may_steal=false，避免连锁抢占。
		id = playback.play_stream(stream, 0.0, db, pitch,
				AudioServer.PLAYBACK_TYPE_DEFAULT, bus)
		if id < 0:
			return POLY_RETRY
	active.append({
		"id": id,
		"priority": priority,
		"started": _next_seq(),
		"started_ms": Time.get_ticks_msec(),
		"scope": scope,
	})
	return id


func _prune_poly_streams(playback: AudioStreamPlaybackPolyphonic, active: Array) -> void:
	var now := Time.get_ticks_msec()
	for i in range(active.size() - 1, -1, -1):
		var entry: Dictionary = active[i]
		if now - int(entry.get("started_ms", 0)) < POLY_PRUNE_GRACE_MS:
			continue
		if not playback.is_stream_playing(int(entry["id"])):
			active.remove_at(i)


func _pick_stream_victim(active: Array, priority: int) -> int:
	if active.is_empty():
		return -1
	var victim := 0
	for i in range(1, active.size()):
		var a: Dictionary = active[i]
		var b: Dictionary = active[victim]
		if int(a["priority"]) < int(b["priority"]) \
				or (int(a["priority"]) == int(b["priority"]) \
				and int(a["started"]) < int(b["started"])):
			victim = i
	# 只抢优先级严格更低的；同优先级丢新声音。
	if int(active[victim]["priority"]) >= priority:
		return -1
	return victim


# ---- 内部：3D 池

func _build_pool_3d() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Pool3D_%02d" % i
		p.bus = BUS_SFX
		p.unit_size = POOL_UNIT_SIZE
		p.max_distance = POOL_MAX_DISTANCE
		p.finished.connect(_on_pool_finished.bind(p))
		add_child(p)
		_pool_players.append(p)


func _on_pool_finished(player: AudioStreamPlayer3D) -> void:
	var id := player.get_instance_id()
	# 被抢走的播放器也会发 finished；如果它已经被重新装填，playing 是 true，别误删。
	if _pool_meta.has(id) and not player.playing:
		_pool_meta.erase(id)


func _acquire_pool_player(priority: int) -> AudioStreamPlayer3D:
	for p in _pool_players:
		if not p.playing:
			_pool_meta.erase(p.get_instance_id())
			return p
	var victim: AudioStreamPlayer3D = null
	var victim_meta: Dictionary = {}
	for p in _pool_players:
		var m: Dictionary = _pool_meta.get(p.get_instance_id(), {})
		if victim == null:
			victim = p
			victim_meta = m
			continue
		var m_prio := int(m.get("priority", 0))
		var v_prio := int(victim_meta.get("priority", 0))
		if m_prio < v_prio \
				or (m_prio == v_prio \
				and int(m.get("started", 0)) < int(victim_meta.get("started", 0))):
			victim = p
			victim_meta = m
	if victim == null:
		return null
	# 同优先级不抢：池满时宁可丢新声音，也不要把正在响的同类声音切断。
	if int(victim_meta.get("priority", 0)) >= priority:
		return null
	victim.stop()
	_pool_meta.erase(victim.get_instance_id())
	return victim


# ---- 内部：3D 发射器

func _make_emitter(emitter: Node3D, bus: StringName, opts: Dictionary) -> Dictionary:
	var player := AudioStreamPlayer3D.new()
	player.name = "AudioBusEmitter"
	player.bus = bus
	player.unit_size = float(opts.get("unit_size", POOL_UNIT_SIZE))
	player.max_distance = float(opts.get("max_distance", POOL_MAX_DISTANCE))
	player.position = opts.get("offset", Vector3.ZERO)
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = POLY_EMITTER
	player.stream = poly
	emitter.add_child(player)
	player.play()
	return {
		"ref": weakref(emitter),
		"player": player,
		"streams": [],
		"pending": [],
	}


func _emitter_alive(entry: Dictionary) -> bool:
	var ref: WeakRef = entry.get("ref")
	if ref == null or ref.get_ref() == null:
		return false
	var player = entry.get("player")
	return is_instance_valid(player) and player.is_inside_tree()


func _activate_emitters() -> void:
	for id in _emitters.keys():
		var entry: Dictionary = _emitters[id]
		if not _emitter_alive(entry):
			_emitters.erase(id)
			continue
		var pending: Array = entry["pending"]
		if pending.is_empty():
			continue
		var player: AudioStreamPlayer3D = entry["player"]
		var playback := player.get_stream_playback() as AudioStreamPlaybackPolyphonic
		if playback == null:
			continue
		var streams: Array = entry["streams"]
		var retry: Array = []
		while not pending.is_empty():
			var req: Dictionary = pending.pop_front()
			if int(req["scope"]) != _scope_id():
				continue
			var sid := _play_poly_into(playback, streams, req["stream"], float(req["db"]),
					float(req["pitch"]), int(req["priority"]), int(req["scope"]),
					player.bus, not bool(req.get("preempted", false)))
			if sid == POLY_RETRY:
				req["preempted"] = true
				retry.append(req)
		pending.append_array(retry)


# ---- 内部：声道

func _update_channel_pos(meta: Dictionary, pos, follow) -> void:
	var player = meta.get("player")
	if not is_instance_valid(player) or not (player is Node3D):
		return
	if follow is Node3D:
		meta["follow_ref"] = weakref(follow)
		(player as Node3D).global_position = (follow as Node3D).global_position
	elif pos != null and typeof(pos) == TYPE_VECTOR3:
		meta["follow_ref"] = null
		(player as Node3D).global_position = pos


## 场景根离开时声道跟着淡出。回调里带 channel_id：
## 同一场景往往有好几个声道（雨、广播…），只绑 owner_id 的话回调完全相同，
## 第二个声道 connect 时会报「already connected」，而且没法区分该停哪个。
func _bind_owner(meta: Dictionary, owner_node: Node, channel_id: StringName) -> void:
	var new_id := owner_node.get_instance_id() if owner_node != null else 0
	if int(meta.get("owner_id", 0)) == new_id:
		return
	var old_ref: WeakRef = meta.get("owner_ref")
	var old_owner = old_ref.get_ref() if old_ref != null else null
	var old_cb = meta.get("owner_cb")
	if old_owner != null and old_cb != null and old_owner.tree_exiting.is_connected(old_cb):
		old_owner.tree_exiting.disconnect(old_cb)
	meta["owner_id"] = new_id
	meta["owner_ref"] = weakref(owner_node) if owner_node != null else null
	if owner_node == null:
		meta["owner_cb"] = null
		return
	var cb := _on_owner_exiting.bind(new_id, channel_id)
	meta["owner_cb"] = cb
	owner_node.tree_exiting.connect(cb)


func _on_owner_exiting(owner_id: int, channel_id: StringName) -> void:
	var meta: Dictionary = _channel_meta.get(channel_id, {})
	if meta.is_empty() or int(meta.get("owner_id", 0)) != owner_id:
		return
	if bool(meta.get("releasing")):
		return
	meta["releasing"] = true
	var voice: AudioVoice = _channels.get(channel_id)
	if voice != null:
		voice.stop(DEFAULT_FADE)


func _update_followers() -> void:
	for id in _channel_meta.keys():
		var meta: Dictionary = _channel_meta[id]
		var ref = meta.get("follow_ref")
		if ref == null:
			continue
		var node = (ref as WeakRef).get_ref()
		if node == null:
			# 跟随目标没了（不是场景根，所以没有 tree_exiting 兜底），主动淡出。
			meta["follow_ref"] = null
			if not bool(meta.get("releasing")):
				meta["releasing"] = true
				var voice: AudioVoice = _channels.get(id)
				if voice != null:
					voice.stop(DEFAULT_FADE)
			continue
		if node is Node3D:
			var player = meta.get("player")
			if is_instance_valid(player):
				(player as Node3D).global_position = (node as Node3D).global_position


func _prune_channels() -> void:
	var now := Time.get_ticks_msec()
	for id in _channel_meta.keys():
		var meta: Dictionary = _channel_meta[id]
		if not is_instance_valid(meta.get("player")):
			_drop_channel(id)
			continue
		var voice: AudioVoice = _channels.get(id)
		if voice == null:
			_drop_channel(id)
			continue
		if voice.playing:
			continue
		var aged := now - int(meta.get("created", 0)) > VOICE_GRACE_MS
		if aged and (bool(meta.get("releasing")) or not bool(meta.get("loop"))):
			_drop_channel(id)


func _drop_channel(id: StringName) -> void:
	var meta: Dictionary = _channel_meta.get(id, {})
	# 主动断开 owner 信号。不然同一场景再建同名声道时，
	# 相同 owner_id + 相同频道名会生成完全相同的 Callable，connect 会报重复。
	var owner_ref: WeakRef = meta.get("owner_ref")
	var owner_node = owner_ref.get_ref() if owner_ref != null else null
	var owner_cb = meta.get("owner_cb")
	if owner_node != null and owner_cb != null and owner_node.tree_exiting.is_connected(owner_cb):
		owner_node.tree_exiting.disconnect(owner_cb)
	var voice: AudioVoice = _channels.get(id)
	if voice != null:
		voice.cancel_fade()
		voice.stop(0.0)
	var player = meta.get("player")
	if is_instance_valid(player):
		player.queue_free()
	_channel_meta.erase(id)
	_channels.erase(id)


## 循环必须设在副本上。Sfx.* 返回的是 static 缓存里的同一个实例，
## 直接改 loop_mode 会把「广播」变成所有地方都在循环（现在剧情里就是这么干的）。
func _make_loop_stream(stream: AudioStream) -> AudioStream:
	var wav := stream.duplicate() as AudioStreamWAV
	if wav == null:
		# 非 WAV 流（本工程目前没有）没有统一的循环字段，原样播。
		return stream
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	return wav


# ---- 内部：通用

## 场景切换时清掉旧场景的一次性音效。声道不在这里处理 —— 它们跟 owner 走。
func _check_scene_scope() -> void:
	var now := _scope_id()
	if now == _last_scene_id:
		return
	_last_scene_id = now
	for bus in _poly_streams:
		var playback = _poly_playbacks.get(bus)
		var active: Array = _poly_streams[bus]
		if playback == null:
			active.clear()
			continue
		for i in range(active.size() - 1, -1, -1):
			var entry: Dictionary = active[i]
			if int(entry["scope"]) != now:
				playback.stop_stream(int(entry["id"]))
				active.remove_at(i)
		var pending: Array = _poly_pending[bus]
		for i in range(pending.size() - 1, -1, -1):
			if int(pending[i]["scope"]) != now:
				pending.remove_at(i)
	for p in _pool_players:
		var id := p.get_instance_id()
		if _pool_meta.has(id) and int(_pool_meta[id]["scope"]) != now:
			p.stop()
			_pool_meta.erase(id)


func _resolve_bus(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(bus) >= 0:
		return bus
	push_warning("AudioBus：总线「%s」不存在，回落到 SFX" % bus)
	return BUS_SFX


func _bus_index(bus: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		push_warning("AudioBus：总线「%s」不存在，检查 default_bus_layout.tres" % bus)
	return idx


func _kill_bus_tween(bus: StringName) -> void:
	var tw = _bus_tweens.get(bus)
	if tw != null and tw.is_valid():
		tw.kill()
	_bus_tweens.erase(bus)


func _on_bus_tween_done(bus: StringName, tw: Tween) -> void:
	if _bus_tweens.get(bus) == tw:
		_bus_tweens.erase(bus)


func _next_seq() -> int:
	_seq += 1
	return _seq


func _scope_id() -> int:
	var scene := get_tree().current_scene
	return scene.get_instance_id() if scene != null else 0
