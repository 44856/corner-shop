extends Node3D
## 便利店自动门：两扇滑动玻璃门（带碰撞）+ 感应开合 + 提示音。
##
## 为什么单独拎出来：
##   store.gd 是静态造型库，门叶一旦要动，就得是「会动的物理体」，
##   而且要在开门时把碰撞一起挪走 —— 只挪网格会变成「门开了但人过不去」。
##
## 门叶几何读 Store.door_leaves()，和静态版本共用同一组数字，
## 所以 auto_door 开关前后，门看起来完全一样。

const K := preload("res://scripts/kit.gd")
const Store := preload("res://scripts/store.gd")
const Sfx := preload("res://scripts/sfx.gd")

## 感应区是一个矩形，不再是以门为圆心的圆：
##   之前半径 2.35m 会覆盖大半个店内，站在货架边、或者沿橱窗走过去都会开门。
##   现在只认「正对门洞」这一条带：左右各 open_half_width，门外 open_depth_out、
##   门内 open_depth_in。门外进深仍留 2.2m —— 角色步行 4.2m/s、开门 0.4s，
##   再短就会走到门前才刚开始滑门。
@export var open_half_width := 0.95
@export var open_depth_out := 2.2
@export var open_depth_in := 1.2
## 关门前多等一会儿，别让人刚迈进去半只脚门就合上
@export var close_grace := 0.45

## 开场演出期间先别开，等镜头交接完再通电
var enabled := false

var _leaves: Array = []
var _open := false
var _player: Node3D
var _tween: Tween
var _led: MeshInstance3D
var _chime: AudioStreamPlayer3D
var _since_clear := 0.0

## 门洞中心，也是感应器的位置
const DOOR_CENTER := Vector3(0.355, 1.2, -1.01)


func _ready() -> void:
	_build_leaves()
	_build_sensor_lamp()
	_build_audio()


func bind_player(p: Node3D) -> void:
	_player = p


# ---------------------------------------------------------------- 造型

func _build_leaves() -> void:
	var frame := K.toon(Color("#242b34"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	var glass := K.glass(Color(0.45, 0.62, 0.8, 0.08), 0.35)

	for leaf in Store.door_leaves():
		var body := AnimatableBody3D.new()
		body.name = "Leaf"
		body.position = Vector3(leaf["x"], 0.0, leaf["z"])
		add_child(body)

		var w: float = leaf["w"]
		var h: float = leaf["h"]
		# 玻璃
		K.box(body, Vector3(w, h, 0.02), Vector3(0.0, 1.32, 0.0), glass, Vector3.ZERO, false)
		# 四边框
		K.box(body, Vector3(w + 0.04, 0.06, 0.05), Vector3(0.0, 2.42, 0.0), frame)
		K.box(body, Vector3(w + 0.04, 0.05, 0.05), Vector3(0.0, 0.23, 0.0), frame)
		K.box(body, Vector3(0.05, h, 0.05), Vector3(-w * 0.5, 1.32, 0.0), frame)
		K.box(body, Vector3(0.05, h, 0.05), Vector3(w * 0.5, 1.32, 0.0), frame)
		# 把手：靠门缝那一侧
		var hx: float = 0.23 if leaf["slide"] < 0.0 else -0.24
		K.box(body, Vector3(0.04, 0.32, 0.03), Vector3(hx, 1.12, -0.05), frame)

		# 碰撞：比门叶略厚，避免高速穿过
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(w + 0.04, h, 0.10)
		cs.shape = sh
		cs.position = Vector3(0.0, 1.32, 0.0)
		body.add_child(cs)

		_leaves.append({
			"body": body,
			"base_x": float(leaf["x"]),
			"slide": float(leaf["slide"]),
		})


## 门楣上的感应指示灯：关着是红的，开了是绿的
func _build_sensor_lamp() -> void:
	_led = K.sphere(self, 0.028, Vector3(DOOR_CENTER.x, 2.505, -0.9),
		K.glow(Color("#ff5a3a"), 1.6), Vector3.ZERO, 8, 1.0, false)
	# 灯罩，免得那颗小球看起来像浮在空中的糖
	K.box(self, Vector3(0.12, 0.05, 0.05), Vector3(DOOR_CENTER.x, 2.505, -0.885),
		K.toon(Color("#1b2028"), {"line": 0.004}))


func _build_audio() -> void:
	_chime = AudioStreamPlayer3D.new()
	_chime.stream = Sfx.chime()
	_chime.position = Vector3(DOOR_CENTER.x, 2.2, -0.9)
	_chime.unit_size = 4.0
	_chime.max_distance = 16.0
	_chime.volume_db = -6.0
	add_child(_chime)


# ---------------------------------------------------------------- 感应

func _process(delta: float) -> void:
	if not enabled or _player == null or not is_instance_valid(_player):
		return
	if bool(_player.get("input_locked")):
		return

	var near := _in_sensor()
	var blocking := _player_in_gap()

	if near or blocking:
		_since_clear = 0.0
		set_open(true)
	else:
		_since_clear += delta
		if _since_clear >= close_grace:
			set_open(false)


## d.z 以门为中心：正数是店外，负数是店内。
func _in_sensor() -> bool:
	var d: Vector3 = _player.global_position - global_position - DOOR_CENTER
	if absf(d.x) > open_half_width:
		return false
	return d.z >= -open_depth_in and d.z <= open_depth_out


## 人正卡在门洞里时不许关门（自动门的基本礼貌）
func _player_in_gap() -> bool:
	var p: Vector3 = _player.global_position
	return absf(p.x - DOOR_CENTER.x) < 0.95 and p.z < -0.55 and p.z > -1.5


# ---------------------------------------------------------------- 开合

func set_open(v: bool, instant: bool = false) -> void:
	if _open == v:
		return
	_open = v

	if _tween != null and _tween.is_valid():
		_tween.kill()

	if instant:
		for leaf in _leaves:
			var b: AnimatableBody3D = leaf["body"]
			b.position.x = leaf["base_x"] + (leaf["slide"] if v else 0.0)
	else:
		_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_OUT if v else Tween.EASE_IN_OUT)
		for leaf in _leaves:
			var b: AnimatableBody3D = leaf["body"]
			var target: float = leaf["base_x"] + (leaf["slide"] if v else 0.0)
			# 开门 0.4s：感应区收窄后，站在门内 0.6m 再转身出门只剩 0.14s，
			# 0.55s 的旧速度会让门叶夹住胶囊、把人挤慢。
			_tween.tween_property(b, "position:x", target, 0.4 if v else 0.75)

	if _led != null:
		_led.material_override = K.glow(
			Color("#4dffa8") if v else Color("#ff5a3a"),
			2.4 if v else 1.6)

	if v and not instant and _chime != null:
		_chime.play()


func is_open() -> bool:
	return _open
