extends RefCounted
## 程序化音效：不往仓库里塞 wav，直接合成 PCM。
##
## 这一期只需要两个音：自动门的「叮—咚」和服务铃的「叮」。
## 都写成几路正弦 + 指数衰减包络，够用，而且改音色只需要调数字。

const RATE := 22050

static var _cache: Dictionary = {}


## 自动门提示音：两声，先高后低（日式便利店的 pin-pon）
static func chime() -> AudioStreamWAV:
	if _cache.has("chime"):
		return _cache["chime"]
	var buf := _blank(1.15)
	_add_tone(buf, 1046.5, 0.0, 0.62, 5.2, 0.55)   # C6
	_add_tone(buf, 784.0, 0.30, 0.78, 4.4, 0.52)   # G5
	var s := _to_wav(buf)
	_cache["chime"] = s
	return s


## 服务铃：单声高频，衰减快，带一点金属泛音
static func bell() -> AudioStreamWAV:
	if _cache.has("bell"):
		return _cache["bell"]
	var buf := _blank(0.85)
	_add_tone(buf, 1568.0, 0.0, 0.7, 7.5, 0.42)
	_add_tone(buf, 2349.0, 0.0, 0.35, 11.0, 0.16)
	_add_tone(buf, 3136.0, 0.0, 0.22, 15.0, 0.08)
	var s := _to_wav(buf)
	_cache["bell"] = s
	return s


## 轻轻一声「嗒」：冷柜门、货架之类的触感反馈
static func tap() -> AudioStreamWAV:
	if _cache.has("tap"):
		return _cache["tap"]
	var buf := _blank(0.14)
	_add_tone(buf, 320.0, 0.0, 0.10, 55.0, 0.5)
	_add_tone(buf, 880.0, 0.0, 0.05, 80.0, 0.18)
	var s := _to_wav(buf)
	_cache["tap"] = s
	return s


## 货车喇叭：两个音叠一起（约 392 + 466Hz），加一层八度泛音当「金属壳」
static func horn() -> AudioStreamWAV:
	if _cache.has("horn"):
		return _cache["horn"]
	var buf := _blank(1.0)
	_add_tone(buf, 392.0, 0.0, 0.95, 3.4, 0.40)
	_add_tone(buf, 466.0, 0.0, 0.95, 3.4, 0.32)
	_add_tone(buf, 784.0, 0.0, 0.95, 4.2, 0.10)
	var s := _to_wav(buf)
	_cache["horn"] = s
	return s


## 撞击：低频闷响 + 一层短噪声（金属/玻璃碎掉的质感）
static func impact() -> AudioStreamWAV:
	if _cache.has("impact"):
		return _cache["impact"]
	var buf := _blank(1.1)
	_add_tone(buf, 64.0, 0.0, 0.60, 5.5, 0.9)
	_add_tone(buf, 41.0, 0.0, 0.95, 3.2, 0.65)
	_add_noise(buf, 0.0, 0.30, 11.0, 0.55)
	_add_noise(buf, 0.02, 0.18, 26.0, 0.30)
	var s := _to_wav(buf)
	_cache["impact"] = s
	return s


# ---------------------------------------------------------------- 合成

static func _blank(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(RATE * seconds))
	return buf


## 噪声：撞击、摩擦之类不需要音高的部分。
## 用一个一阶低通把白噪声压暗，否则会像收音机里的沙沙声。
static func _add_noise(buf: PackedFloat32Array, start: float, dur: float,
		decay: float, gain: float) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var lp := 0.0
	for i in n:
		var idx := i0 + i
		if idx < 0 or idx >= buf.size():
			break
		var t := float(i) / float(RATE)
		var env := exp(-decay * t) * minf(1.0, t * 300.0)
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.35)
		buf[idx] += lp * env * gain


## 往缓冲里叠一个带衰减包络的正弦。
## attack 用一个极短的线性淡入，避免波形从 0 突跳造成「啪」的爆音。
static func _add_tone(buf: PackedFloat32Array, freq: float, start: float,
		dur: float, decay: float, gain: float) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	for i in n:
		var idx := i0 + i
		if idx < 0 or idx >= buf.size():
			break
		var t := float(i) / float(RATE)
		var env := exp(-decay * t) * minf(1.0, t * 200.0)
		buf[idx] += sin(TAU * freq * t) * env * gain


static func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
