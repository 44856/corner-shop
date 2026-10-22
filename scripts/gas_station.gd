extends Node3D
## 雨夜 · 星见町服务区（国道 17 号）
##
## 商店街西口出去就是这里。视觉上要和商店街同源（同一套三渲二材质、同一套雨效），
## 但气质要换一档：商店街是窄街暖灯，这里是开阔的白色顶棚 + 冷白灯管，
## 雨直接被顶棚切成两半，站底下能听见雨在铁皮上敲。
##
## 动线：
##   从东侧人行道进来 → 沿国道往西 → 穿马路进前场 → 顶棚下两台加油机 →
##   西侧小卖亭 / 打气机 / 贩卖机 → 东侧价格塔和回商店街的路牌。
##
## 所有几何照旧运行时生成；碰撞单独一层，尺寸从本文件的公开常量读。

const K := preload("res://scripts/kit.gd")
const Props := preload("res://scripts/props.gd")
const WorldEnv := preload("res://scripts/world_env.gd")
const CollisionLayout := preload("res://scripts/collision_layout.gd")
const PlayerController := preload("res://scripts/player_controller.gd")
const Hud := preload("res://scripts/hud.gd")
const Hub := preload("res://scripts/interaction_hub.gd")
const Sfx := preload("res://scripts/sfx.gd")
const LetterTransition := preload("res://scripts/letter_transition.gd")
const GasStationStory := preload("res://scripts/gas_station_story.gd")

## 场地范围。0 是西缘，30 是东缘；国道沿 X 穿过，z 0..4 是车行道。
const X0 := 0.0
const X1 := 30.0
const Z0 := -4.0
const Z1 := 14.0
const CENTER_X := 15.0
const CENTER_Z := 5.0
const WALK_Y := 0.16
const ROAD_Z0 := 0.0
const ROAD_Z1 := 4.0
const SIDEWALK_Z0 := -2.0

## 顶棚与前场。数字同时给几何、雨棚和碰撞用，别在别处再抄一份。
const CANOPY_X0 := 9.25
const CANOPY_X1 := 22.75
const CANOPY_Z0 := 6.1
const CANOPY_Z1 := 11.9
const CANOPY_TOP := 5.16

## 小卖亭
const KIOSK_X0 := 2.3
const KIOSK_X1 := 6.9
const KIOSK_Z0 := 6.5
const KIOSK_Z1 := 12.5
const KIOSK_TOP := 3.52

## 从商店街走过来，落在东侧人行道上，面朝西。
## 离回程触发线 1.5m —— 出生即触发的话，转场会来回弹。
const SPAWN := Vector3(27.0, WALK_Y + 0.01, -1.05)
const RETURN_X := 28.55
const TOWN_SCENE := "res://scenes/hoshi_street.tscn"

## 开阔地没有墙替你把镜头顶近：5.4m 的远景会让人物缩在画面中央。
## 收到 4.4m、支点降到胸口，保留街道的肩后视角，人物占比接近商店街。
const CAM := {"dist": 4.4, "height": 1.45, "fov": 52.0, "shoulder": 0.30}

var player: CharacterBody3D
var hud
var hub
var env: Environment
var moon: DirectionalLight3D
var fill: DirectionalLight3D
var story

var _zone := "walk"
var _transitioning := false
var _arriving := false
var _shooting := false
var _seen_forecourt := false
var _audio_override := false
var _rain: AudioStreamPlayer
var _hum: AudioStreamPlayer


func _ready() -> void:
	# 转场层还挂在 root 上 = 我们是被转场送过来的，开场黑幕由它负责淡出。
	_arriving = get_tree().root.has_node("LetterTransition")

	var world := WorldEnv.build(self, {
		"fog_length": 58.0,
		"rain": {
			"center": Vector2(CENTER_X, CENTER_Z),
			"half": Vector2((X1 - X0) * 0.5, (Z1 - Z0) * 0.5),
			# 和商店街同面积（540㎡），4600 保持同样的雨密度
			"amount": 4600,
			"top_y": 12.5,
			"covers": _rain_covers(),
		},
		"ripples": _ripples(),
	})
	env = world["environment"]
	moon = world["moon"]
	fill = world["fill"]

	var g := K.group(self, "Station")
	_build_ground(g)
	_build_backdrop(g)
	_build_canopy(g)
	_build_pumps(g)
	_build_kiosk(g)
	_build_signage(g)
	_build_props(g)
	_build_lights(g)
	_build_collision()

	_setup_player()
	_setup_hud()
	_setup_interactions()
	_setup_audio()

	if "--shot" in OS.get_cmdline_user_args():
		# 截图模式不建剧情道具：旧机位是给「空加油站」构图的，
		# 多一台货车会挡住 gas_c/gas_f 的视线。
		_take_shots()
		return

	_setup_story()
	if _arriving:
		_on_arrival()
	else:
		_show_first_frame()


# ---------------------------------------------------------------- 地面

func _build_ground(g: Node3D) -> void:
	# 底座比地面大一圈，边缘不会露黑
	var stone := K.toon(Color("#23272e"), {"shade": 0.5, "rim": 0.12, "line": 0.012})
	K.box(g, Vector3(X1 - X0 + 0.5, 0.6, Z1 - Z0 + 0.5), Vector3(CENTER_X, -0.36, CENTER_Z), stone)
	var foot := K.toon(Color("#14161b"), {"shade": 0.5, "rim": 0.08, "line": 0.01})
	K.box(g, Vector3(X1 - X0 + 0.72, 0.09, Z1 - Z0 + 0.72), Vector3(CENTER_X, -0.69, CENTER_Z), foot)
	K.box(g, Vector3(X1 - X0 + 0.2, 0.03, Z1 - Z0 + 0.2), Vector3(CENTER_X, -0.745, CENTER_Z), foot)

	# 路面本身比商店街宽：国道 17 号是双向两车道 + 路肩
	var asphalt := K.pbr(Color("#12151b"), 0.28, 0.35, {"metallic_specular": 0.65})
	K.box(g, Vector3(X1 - X0, 0.06, ROAD_Z1 - ROAD_Z0), Vector3(CENTER_X, -0.03, 2.0),
		asphalt, Vector3.ZERO, false)

	var walk_mat := K.paving(Color("#484c55"), Color("#2d3037"), 0.9)
	K.box(g, Vector3(X1 - X0, WALK_Y, -SIDEWALK_Z0), Vector3(CENTER_X, WALK_Y * 0.5, SIDEWALK_Z0 * 0.5),
		walk_mat, Vector3.ZERO, false)

	# 前场是浅一号的混凝土：加油站的地坪通常比马路亮，灯打上去才有「岛」的感觉
	var apron := K.paving(Color("#585c64"), Color("#3b3e44"), 1.4)
	K.box(g, Vector3(X1 - X0, WALK_Y, Z1 - ROAD_Z1),
		Vector3(CENTER_X, WALK_Y * 0.5, (ROAD_Z1 + Z1) * 0.5), apron, Vector3.ZERO, false)
	K.plane(g, Vector2(29.4, 9.4), Vector3(CENTER_X, WALK_Y + 0.006, 9.0),
		K.wet(Color("#a9c8ff"), 0.05), Vector3.ZERO, false)

	# 路缘。前场只在进出车道（x 14..24.5）留缺口，其他地方是石缘。
	var curb := K.toon(Color("#63666c"), {"shade": 0.5, "rim": 0.28, "line": 0.007})
	K.box(g, Vector3(X1 - X0, WALK_Y, 0.17), Vector3(CENTER_X, WALK_Y * 0.5, -0.085), curb)
	K.box(g, Vector3(14.0, WALK_Y, 0.17), Vector3(7.0, WALK_Y * 0.5, 4.085), curb)
	K.box(g, Vector3(5.5, WALK_Y, 0.17), Vector3(27.25, WALK_Y * 0.5, 4.085), curb)

	# 进出车道的橡胶坡板：视觉上是个缓坡，真正的贴合由碰撞楔形负责
	K.box(g, Vector3(10.5, 0.02, 0.55), Vector3(19.25, 0.075, 4.0),
		K.toon(Color("#2c3037"), {"line": 0.004}), Vector3(-18, 0, 0), false)

	# 标线：中央虚线 + 两侧边线 + 东口斑马线（对着回商店街的路牌）
	var paint := K.toon(Color("#464c55"), {"shade": 0.45, "rim": 0.1, "line": 0.0})
	var x := 0.8
	while x < 28.4:
		K.plane(g, Vector2(1.7, 0.07), Vector3(x + 0.85, 0.004, 2.0), paint, Vector3.ZERO, false)
		x += 3.4
	for z in [0.27, 3.73]:
		K.plane(g, Vector2(29.6, 0.07), Vector3(CENTER_X, 0.003, z), paint, Vector3.ZERO, false)
	var cz := 0.3
	while cz < 3.8:
		K.plane(g, Vector2(2.4, 0.3), Vector3(26.7, 0.005, cz), paint, Vector3.ZERO, false)
		cz += 0.48

	# 排水沟：顶棚边缘一条暗色槽，雨从铁皮上下来先砸进这里
	var gutter := K.toon(Color("#15181d"), {"shade": 0.7, "line": 0.0})
	K.plane(g, Vector2(13.6, 0.28), Vector3(16.0, WALK_Y + 0.004, 12.15), gutter, Vector3.ZERO, false)
	K.plane(g, Vector2(13.6, 0.28), Vector3(16.0, WALK_Y + 0.004, 5.85), gutter, Vector3.ZERO, false)


# ---------------------------------------------------------------- 背景

func _build_backdrop(g: Node3D) -> void:
	var bg := K.group(g, "Backdrop")

	# 北侧：窄人行道后面是草坡 + 绿篱 + 树，挡住底座外的黑
	var grass := K.toon(Color("#1d2a21"), {"shade": 0.7, "rim": 0.1, "line": 0.006})
	K.box(bg, Vector3(X1 - X0, 0.2, 1.9), Vector3(CENTER_X, 0.16, -3.05), grass, Vector3.ZERO, false)
	var hedge := K.toon(Color("#26382a"), {"shade": 0.55, "rim": 0.2, "line": 0.006})
	for i in 15:
		K.box(bg, Vector3(1.96, 0.85, 0.5), Vector3(1.0 + i * 2.0, 0.16 + 0.425, -2.25), hedge)

	# 草坡 / 绿篱后面的树。树干细、树冠压暗，只做天际线。
	for tx in [3.0, 11.0, 20.0, 28.0]:
		_tree(bg, Vector3(tx, 0.36, -3.35), 0.9 + fmod(tx, 3.0) * 0.08)

	# 北侧电线杆：和商店街同一条 17 号线，杆距比街里大，远看是黑竖线
	var concrete := K.toon(Color("#4e5158"), {"shade": 0.55, "rim": 0.18, "line": 0.007})
	var dark := K.toon(Color("#31343a"), {"shade": 0.6, "line": 0.005})
	for px in [6.0, 16.0, 26.0]:
		var p := Vector3(px, 0.16, -3.55)
		K.cyl(bg, 0.14, 6.4, p + Vector3(0, 3.2, 0), concrete, Vector3.ZERO, 10)
		K.box(bg, Vector3(1.5, 0.08, 0.08), p + Vector3(0, 5.9, 0), dark)
		K.box(bg, Vector3(1.0, 0.06, 0.07), p + Vector3(0, 5.4, 0), dark)
	var wire_mat := K.toon(Color("#111318"), {"line": 0.0, "shade": 0.9})
	for i in 2:
		var a := Vector3(6.0 + i * 10.0, 6.06, -3.55)
		var b := Vector3(16.0 + i * 10.0, 6.06, -3.55)
		for k in 2:
			var ox := -0.45 + k * 0.9
			K.wire(bg, a + Vector3(ox, 0, 0), b + Vector3(ox, 0, 0), 0.42, 0.011, wire_mat)
	K.wire(bg, Vector3(6.0, 6.06, -3.55), Vector3(-0.5, 5.7, -3.55), 0.5, 0.011, wire_mat)
	K.wire(bg, Vector3(26.0, 6.06, -3.55), Vector3(32.0, 5.9, -3.55), 0.35, 0.011, wire_mat)

	# 远处民居剪影：窗只亮三四扇，太整齐会像写字楼
	var house := K.toon(Color("#1b1f26"), {"shade": 0.5, "rim": 0.08, "line": 0.008})
	for spec in [
			{"p": Vector3(8.0, 0.0, -7.5), "s": Vector3(6.0, 3.6, 4.0)},
			{"p": Vector3(21.0, 0.0, -8.5), "s": Vector3(7.0, 4.2, 4.5)}]:
		var hp: Vector3 = spec["p"]
		K.box(bg, spec["s"], hp + Vector3(0, float(spec["s"].y) * 0.5, 0), house)
		K.box(bg, Vector3(float(spec["s"].x) + 0.4, 0.22, float(spec["s"].z) + 0.4),
			hp + Vector3(0, float(spec["s"].y) + 0.1, 0), K.toon(Color("#161a20"), {"line": 0.004}))
		for i in 2:
			if (int(hp.x) + i) % 2 == 0:
				K.box(bg, Vector3(0.8, 0.6, 0.04),
					hp + Vector3(-1.4 + i * 2.6, 2.0, float(spec["s"].z) * 0.5 + 0.02),
					K.glow(Color("#ffcf8a"), 0.45), Vector3.ZERO, false)

	# 南侧：矮仓库的波纹铁皮围墙。看不到头的场外不能直接露黑。
	var fence := K.toon(Color("#2f333a"), {"shade": 0.5, "rim": 0.12, "line": 0.008})
	K.box(bg, Vector3(X1 - X0, 2.2, 0.16), Vector3(CENTER_X, 0.16 + 1.1, Z1 + 0.1), fence)
	var seam := K.toon(Color("#23272d"), {"line": 0.0})
	for i in 8:
		K.box(bg, Vector3(0.03, 2.1, 0.18), Vector3(1.8 + i * 3.7, 0.16 + 1.1, Z1 + 0.09),
			seam, Vector3.ZERO, false)
	K.box(bg, Vector3(X1 - X0, 0.09, 0.24), Vector3(CENTER_X, 2.35, Z1 + 0.1),
		K.toon(Color("#676b72"), {"line": 0.005}))

	# 东西两侧的道路延伸：让国道看起来是穿过去的，而不是在底座边断掉
	var ext := K.pbr(Color("#101319"), 0.3, 0.3, {"metallic_specular": 0.55})
	K.box(bg, Vector3(18.0, 0.04, ROAD_Z1 - ROAD_Z0), Vector3(-9.0, -0.02, 2.0), ext, Vector3.ZERO, false)
	K.box(bg, Vector3(18.0, 0.04, ROAD_Z1 - ROAD_Z0), Vector3(39.0, -0.02, 2.0), ext, Vector3.ZERO, false)

	# 东边是商店街方向：几扇暖窗透出雾里的镇子光。
	# x 必须留在 35 以外：出生点在西侧 5.4m 处，弹簧臂会退到 x ≈ 32.4，
	# 房子再近一点镜头就落在墙体内部 —— 一开场是一整屏黑。
	for spec in [
			{"p": Vector3(38.0, 0.0, -3.0), "s": Vector3(5.0, 4.0, 5.0)},
			{"p": Vector3(38.5, 0.0, 3.5), "s": Vector3(4.0, 2.8, 4.0)}]:
		var bp: Vector3 = spec["p"]
		K.box(bg, spec["s"], bp + Vector3(0, float(spec["s"].y) * 0.5, 0), house)
		K.box(bg, Vector3(0.04, 0.55, 0.9), bp + Vector3(-float(spec["s"].x) * 0.5 - 0.02, 1.9, 0.6),
			K.glow(Color("#ffcf9a"), 0.5), Vector3.ZERO, false)


func _tree(parent: Node3D, base: Vector3, scale_f: float) -> void:
	var trunk := K.toon(Color("#2a2420"), {"shade": 0.55, "rim": 0.15, "line": 0.005})
	var leaf := K.toon(Color("#1e3024"), {"shade": 0.5, "rim": 0.18, "line": 0.005})
	K.cyl(parent, 0.15 * scale_f, 2.6 * scale_f, base + Vector3(0, 1.3 * scale_f, 0), trunk, Vector3.ZERO, 8)
	K.sphere(parent, 1.15 * scale_f, base + Vector3(0, 3.0 * scale_f, 0), leaf,
		Vector3.ZERO, 10, 0.78, false)
	K.sphere(parent, 0.8 * scale_f, base + Vector3(0.7 * scale_f, 2.6 * scale_f, 0.2), leaf,
		Vector3.ZERO, 10, 0.8, false)
	K.sphere(parent, 0.72 * scale_f, base + Vector3(-0.6 * scale_f, 3.35 * scale_f, -0.1), leaf,
		Vector3.ZERO, 10, 0.8, false)


# ---------------------------------------------------------------- 顶棚

func _build_canopy(g: Node3D) -> void:
	var grp := K.group(g, "Canopy")
	var green := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.007})
	var cream := K.toon(Color("#e8e0cf"), {"shade": 0.6, "rim": 0.15, "line": 0.005})
	var steel := K.toon(Color("#c9ced3"), {"shade": 0.52, "rim": 0.3, "line": 0.006})

	# 四根柱：位置贴着两台加油机的两侧，镜头绕着走时不会一头撞上去
	for cx in [10.2, 21.8]:
		for cz in [7.2, 10.8]:
			K.cyl(grp, 0.22, 4.68, Vector3(cx, 0.16 + 2.34, cz), steel, Vector3.ZERO, 14)
			K.cyl(grp, 0.235, 0.16, Vector3(cx, 0.16 + 0.72, cz),
				K.toon(Color("#a83a30"), {"shade": 0.55, "rim": 0.25, "line": 0.005}), Vector3.ZERO, 14)
			K.cyl(grp, 0.3, 0.12, Vector3(cx, 0.16 + 0.06, cz),
				K.toon(Color("#7c8188"), {"shade": 0.6, "line": 0.005}), Vector3.ZERO, 14)

	# 屋面：顶 5.16，底面 4.84。雨棚高度同时写进 _rain_covers()
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.32, CANOPY_Z1 - CANOPY_Z0),
		Vector3(CENTER_X, 5.0, 9.0), green)
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.56, 0.12), Vector3(CENTER_X, 4.88, CANOPY_Z0 + 0.04), green)
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.56, 0.12), Vector3(CENTER_X, 4.88, CANOPY_Z1 - 0.04), green)
	K.box(grp, Vector3(0.12, 0.56, CANOPY_Z1 - CANOPY_Z0), Vector3(CANOPY_X0 + 0.04, 4.88, 9.0), green)
	K.box(grp, Vector3(0.12, 0.56, CANOPY_Z1 - CANOPY_Z0), Vector3(CANOPY_X1 - 0.04, 4.88, 9.0), green)

	# 北面（马路一侧）的灯箱：奶油底板 + 深绿字，雨夜里最显眼的一块
	K.box(grp, Vector3(8.6, 0.46, 0.03), Vector3(16.0, 4.98, CANOPY_Z0 + 0.005),
		K.glow(Color("#fff0d2"), 0.55), Vector3.ZERO, false)
	K.label(grp, "HOSHIMI", Vector3(16.0, 5.05, CANOPY_Z0 - 0.02), 0.27, Color("#1d3a33"),
		Vector3(0, 180, 0), 0)
	K.label(grp, "SERVICE STATION  ·  SELF", Vector3(16.0, 4.84, CANOPY_Z0 - 0.02), 0.085,
		Color("#2d4a41"), Vector3(0, 180, 0), 0)
	K.box(grp, Vector3(13.4, 0.03, 0.04), Vector3(16.0, 4.61, CANOPY_Z0 - 0.01),
		K.glow(Color("#ffcf8a"), 1.1), Vector3.ZERO, false)

	# 南面朝前场深处，写字少一点
	K.box(grp, Vector3(5.4, 0.4, 0.03), Vector3(16.0, 4.97, CANOPY_Z1 - 0.005),
		K.glow(Color("#fff0d2"), 0.45), Vector3.ZERO, false)
	K.label(grp, "SELF  ·  24H", Vector3(16.0, 4.97, CANOPY_Z1 + 0.02), 0.2, Color("#1d3a33"),
		Vector3.ZERO, 0)
	# 东西两侧各一块小字灯箱，绕到侧面时顶棚不至于是一片黑
	for spec in [{"x": CANOPY_X0 + 0.02, "rot": -90}, {"x": CANOPY_X1 - 0.02, "rot": 90}]:
		K.box(grp, Vector3(0.03, 0.36, 4.2), Vector3(spec["x"], 4.96, 9.0),
			K.glow(Color("#fff0d2"), 0.4), Vector3.ZERO, false)
		K.label(grp, "HOSHIMI", Vector3(spec["x"] + (0.02 if spec["rot"] > 0 else -0.02), 4.96, 9.0),
			0.18, Color("#1d3a33"), Vector3(0, spec["rot"], 0), 0)

	# 底面六块灯管：冷白，和商店街的暖黄拉开
	for px in [11.8, 16.0, 20.2]:
		for pz in [7.4, 10.6]:
			K.box(grp, Vector3(3.6, 0.02, 2.0), Vector3(px, 4.83, pz),
				K.glow(Color("#eaf4ff"), 1.15), Vector3.ZERO, false)

	# 悬吊的 SELF 牌
	K.box(grp, Vector3(1.5, 0.38, 0.07), Vector3(16.0, 4.15, 9.0), green)
	for zsign in [-1, 1]:
		K.label(grp, "SELF", Vector3(16.0, 4.15, 9.0 + zsign * 0.045), 0.16,
			Color("#f2e6cf"), Vector3(0, 0 if zsign > 0 else 180, 0))
	for sx in [-0.55, 0.55]:
		K.strut(grp, Vector3(16.0 + sx, 4.34, 9.0), Vector3(16.0 + sx, 4.84, 9.0), 0.012,
			K.toon(Color("#3b4046"), {"line": 0.0}), 4, false)

	# 顶棚前场的两个冷白光源。只开西侧那盏的阴影：
	# 立方体阴影很贵，两盏全开等于整个前场多渲染两遍。
	_canopy_light(grp, Vector3(12.6, 4.55, 9.0), 2.0, true)
	_canopy_light(grp, Vector3(19.4, 4.55, 9.0), 1.8, false)

	# 加油机头顶的湿地反光
	for px in [12.2, 19.8]:
		K.plane(grp, Vector2(4.4, 3.4), Vector3(px, WALK_Y + 0.007, 9.0),
			K.wet(Color("#bcd8ff"), 0.07), Vector3.ZERO, false)


func _canopy_light(parent: Node3D, pos: Vector3, energy: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color("#d9e9ff")
	l.light_energy = energy
	l.omni_range = 11.0
	l.omni_attenuation = 1.35
	l.shadow_enabled = shadow
	l.position = pos
	parent.add_child(l)


# ---------------------------------------------------------------- 加油机

func _build_pumps(g: Node3D) -> void:
	var concrete := K.toon(Color("#9a9ea4"), {"shade": 0.5, "rim": 0.22, "line": 0.006})
	var body := K.toon(Color("#d8d3c6"), {"shade": 0.58, "rim": 0.2, "line": 0.006})
	var dark := K.toon(Color("#2a3a35"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	var hose := K.toon(Color("#15181c"), {"shade": 0.7, "line": 0.004})
	var chrome := K.toon(Color("#a8adb3"), {"shade": 0.5, "rim": 0.4, "line": 0.004})
	var yellow := K.toon(Color("#d8b95a"), {"shade": 0.6, "rim": 0.2, "line": 0.004})

	for spec in [{"x": 12.2, "no": "1"}, {"x": 19.8, "no": "2"}]:
		var cx: float = spec["x"]
		var grp := K.group(g, "Pump" + String(spec["no"]))

		# 岛台高 18cm：挡住人，也挡镜头，但不会挡住视线
		K.box(grp, Vector3(2.4, 0.18, 1.15), Vector3(cx, WALK_Y + 0.09, 9.0), concrete)
		for z in [8.44, 9.56]:
			K.box(grp, Vector3(2.42, 0.025, 0.05), Vector3(cx, WALK_Y + 0.185, z), yellow,
				Vector3.ZERO, false)
		K.box(grp, Vector3(0.7, 0.18, 0.54), Vector3(cx, WALK_Y + 0.27, 9.0), dark)

		# 机身 / 顶灯 / 两面显示屏
		K.box(grp, Vector3(0.62, 1.35, 0.46), Vector3(cx, WALK_Y + 0.83, 9.0), body)
		K.box(grp, Vector3(0.68, 0.4, 0.52), Vector3(cx, WALK_Y + 1.72, 9.0), dark)
		for zsign in [-1, 1]:
			K.box(grp, Vector3(0.5, 0.28, 0.02), Vector3(cx, WALK_Y + 1.28, 9.0 + zsign * 0.235),
				K.glow(Color("#dff5ff"), 1.25), Vector3.ZERO, false)
			K.box(grp, Vector3(0.52, 0.06, 0.022), Vector3(cx, WALK_Y + 0.58, 9.0 + zsign * 0.235),
				chrome, Vector3.ZERO, false)
			K.label(grp, String(spec["no"]), Vector3(cx, WALK_Y + 1.72, 9.0 + zsign * 0.265),
				0.16, Color("#f2e6cf"), Vector3(0, 0 if zsign > 0 else 180, 0))
		K.box(grp, Vector3(0.03, 1.1, 0.48), Vector3(cx - 0.325, WALK_Y + 0.82, 9.0), dark,
			Vector3.ZERO, false)

		# 两根油枪：软管从机身两侧垂下来，枪头挂在岛台边
		for sx in [-1.0, 1.0]:
			var side: float = cx + sx * 0.33
			var tip := Vector3(cx + sx * 0.55, WALK_Y + 0.55, 9.18)
			var pts := PackedVector3Array([
				Vector3(side, WALK_Y + 1.18, 9.0),
				Vector3(side + sx * 0.2, WALK_Y + 1.02, 9.04),
				Vector3(side + sx * 0.23, WALK_Y + 0.7, 9.14),
				tip,
			])
			K.tube(grp, pts, 0.022, hose, 5)
			K.box(grp, Vector3(0.08, 0.16, 0.1), tip + Vector3(0, 0.03, 0.02), chrome)
			K.box(grp, Vector3(0.04, 0.05, 0.16), tip + Vector3(0, 0.09, 0.08), hose)

		# 岛台两端的垃圾桶 / 刮水桶，给"有人用过"的痕迹
		K.box(grp, Vector3(0.3, 0.6, 0.34), Vector3(cx + 1.0, WALK_Y + 0.48, 9.0), dark)
		K.cyl(grp, 0.16, 0.3, Vector3(cx - 1.0, WALK_Y + 0.33, 9.0),
			K.toon(Color("#3c6f8f"), {"shade": 0.55, "rim": 0.3, "line": 0.005}), Vector3.ZERO, 12)


# ---------------------------------------------------------------- 小卖亭

func _build_kiosk(g: Node3D) -> void:
	var grp := K.group(g, "Kiosk")
	var wall := K.toon(Color("#cfc8b8"), {"shade": 0.56, "rim": 0.18, "line": 0.007})
	var dark := K.toon(Color("#2c3338"), {"shade": 0.58, "rim": 0.2, "line": 0.005})
	var green := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.006})
	var cream := K.toon(Color("#e8e0cf"), {"shade": 0.6, "rim": 0.15, "line": 0.005})

	K.box(grp, Vector3(KIOSK_X1 - KIOSK_X0, 3.14, KIOSK_Z1 - KIOSK_Z0),
		Vector3((KIOSK_X0 + KIOSK_X1) * 0.5, 0.16 + 1.57, (KIOSK_Z0 + KIOSK_Z1) * 0.5), wall)
	K.box(grp, Vector3(KIOSK_X1 - KIOSK_X0 + 0.4, 0.22, KIOSK_Z1 - KIOSK_Z0 + 0.4),
		Vector3((KIOSK_X0 + KIOSK_X1) * 0.5, 3.41, (KIOSK_Z0 + KIOSK_Z1) * 0.5), dark)

	# 东面：柜台窗 + 门。玩家从加油机那边走过来，先看到这一面。
	var ex := KIOSK_X1 + 0.02
	K.box(grp, Vector3(0.04, 1.28, 2.9), Vector3(ex, 1.56, 10.3),
		K.glow(Color("#ffe6bd"), 0.55), Vector3.ZERO, false)
	K.box(grp, Vector3(0.04, 1.24, 0.9), Vector3(ex, 1.54, 7.05),
		K.glow(Color("#ffe6bd"), 0.5), Vector3.ZERO, false)
	for z in [8.82, 11.76]:
		K.box(grp, Vector3(0.08, 1.4, 0.06), Vector3(ex + 0.01, 1.56, z), dark)
	K.box(grp, Vector3(0.08, 0.08, 2.96), Vector3(ex + 0.01, 2.22, 10.3), dark)
	K.box(grp, Vector3(0.08, 0.1, 2.96), Vector3(ex + 0.01, 0.92, 10.3), dark)
	for z in [6.6, 7.52]:
		K.box(grp, Vector3(0.08, 1.4, 0.06), Vector3(ex + 0.01, 1.56, z), dark)
	K.box(grp, Vector3(0.08, 0.08, 0.98), Vector3(ex + 0.01, 2.22, 7.05), dark)
	K.box(grp, Vector3(0.08, 0.1, 0.98), Vector3(ex + 0.01, 0.92, 7.05), dark)

	# 门（做成亮着暖光的玻璃门，不真的能进；柜台交互在窗外）
	K.box(grp, Vector3(0.05, 2.0, 0.86), Vector3(ex, 1.19, 8.15),
		K.glow(Color("#ffdca6"), 0.42), Vector3.ZERO, false)
	for z in [7.7, 8.6]:
		K.box(grp, Vector3(0.08, 2.12, 0.07), Vector3(ex + 0.01, 1.23, z), dark)
	K.box(grp, Vector3(0.08, 0.09, 1.0), Vector3(ex + 0.01, 2.26, 8.15), dark)
	K.box(grp, Vector3(0.06, 0.03, 0.18), Vector3(ex + 0.06, 1.05, 8.43), cream)
	K.box(grp, Vector3(0.8, 0.012, 1.15), Vector3(7.35, WALK_Y + 0.006, 8.15),
		K.toon(Color("#2b2f36"), {"shade": 0.8, "line": 0.0}), Vector3.ZERO, false)

	# 门楣：OPEN 24H
	K.box(grp, Vector3(0.04, 0.26, 0.9), Vector3(ex + 0.01, 2.53, 8.15),
		K.glow(Color("#ffcf8a"), 1.5), Vector3.ZERO, false)
	K.label(grp, "OPEN 24H", Vector3(ex + 0.04, 2.53, 8.15), 0.13, Color("#2b2418"),
		Vector3(0, 90, 0), 0)

	# 店招：东面 + 北面（北面朝国道，主要给进站的人看）
	K.box(grp, Vector3(0.04, 0.52, 3.6), Vector3(ex + 0.01, 3.02, 9.6),
		K.glow(Color("#fff0d2"), 0.7), Vector3.ZERO, false)
	K.label(grp, "HOSHIMI", Vector3(ex + 0.04, 3.1, 9.6), 0.25, Color("#1d3a33"),
		Vector3(0, 90, 0), 0)
	K.label(grp, "SERVICE STATION", Vector3(ex + 0.04, 2.9, 9.6), 0.075, Color("#2d4a41"),
		Vector3(0, 90, 0), 0)

	var nz := KIOSK_Z0 - 0.02
	K.box(grp, Vector3(3.2, 0.5, 0.04), Vector3(4.6, 3.02, nz),
		K.glow(Color("#fff0d2"), 0.6), Vector3.ZERO, false)
	K.label(grp, "HOSHIMI MART", Vector3(4.6, 3.02, nz - 0.03), 0.24, Color("#1d3a33"),
		Vector3(0, 180, 0), 0)
	K.box(grp, Vector3(2.6, 1.2, 0.04), Vector3(4.6, 1.6, nz),
		K.glow(Color("#ffe6bd"), 0.5), Vector3.ZERO, false)
	for x in [3.32, 5.88]:
		K.box(grp, Vector3(0.07, 1.32, 0.08), Vector3(x, 1.6, nz), dark)
	K.box(grp, Vector3(2.7, 0.08, 0.08), Vector3(4.6, 2.2, nz), dark)
	K.box(grp, Vector3(2.7, 0.1, 0.08), Vector3(4.6, 1.0, nz), dark)

	# 东面雨棚：悬挑 1.3m，雨落在上面，柜台前能站干地方
	K.box(grp, Vector3(1.35, 0.08, 4.9), Vector3(7.6, 2.86, 9.5), green)
	K.box(grp, Vector3(0.04, 0.07, 4.9), Vector3(8.26, 2.84, 9.5),
		K.glow(Color("#ffcf8a"), 0.8), Vector3.ZERO, false)
	# 棚下壁灯
	K.sphere(grp, 0.07, Vector3(7.25, 2.66, 9.5), K.glow(Color("#ffd9a2"), 2.2),
		Vector3.ZERO, 10, 1.0, false)
	K.sphere(grp, 0.3, Vector3(7.25, 2.64, 9.5), K.soft(Color("#ffbf7a"), 0.36, 1.8),
		Vector3.ZERO, 12, 0.9, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffc88e")
	lamp.light_energy = 0.8
	lamp.omni_range = 4.2
	lamp.position = Vector3(7.3, 2.45, 9.5)
	grp.add_child(lamp)

	# 屋顶空调 / 排气管
	for spec in [
			{"p": Vector3(3.6, 3.78, 8.0), "s": Vector3(0.9, 0.5, 0.8)},
			{"p": Vector3(5.6, 3.78, 11.0), "s": Vector3(0.8, 0.45, 0.75)}]:
		K.box(grp, spec["s"], spec["p"], K.toon(Color("#777c82"), {"shade": 0.55, "rim": 0.25, "line": 0.005}))
		K.cyl(grp, 0.18, 0.03, spec["p"] + Vector3(0, 0.26, 0),
			K.toon(Color("#34393f"), {"line": 0.0}), Vector3.ZERO, 12)
	K.cyl(grp, 0.05, 1.2, Vector3(2.5, 3.8, 7.0), K.toon(Color("#6f747a"), {"line": 0.004}), Vector3.ZERO, 8)
	K.cyl(grp, 0.07, 0.12, Vector3(2.5, 4.45, 7.0), K.toon(Color("#4a4f55"), {"line": 0.0}), Vector3.ZERO, 8)

	# 店内暖光：照亮窗台，但不要从窗缝里漏成一片
	var inl := OmniLight3D.new()
	inl.light_color = Color("#ffcf96")
	inl.light_energy = 0.9
	inl.omni_range = 5.5
	inl.omni_attenuation = 1.6
	inl.position = Vector3(5.6, 2.3, 9.5)
	grp.add_child(inl)

	# 柜台前的湿地反光
	K.plane(g, Vector2(3.4, 4.2), Vector3(7.35, WALK_Y + 0.007, 9.5),
		K.wet(Color("#ffd39a"), 0.07), Vector3.ZERO, false)


# ---------------------------------------------------------------- 价格塔与路牌

func _build_signage(g: Node3D) -> void:
	var grp := K.group(g, "Signage")
	var green := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.007})
	var steel := K.toon(Color("#8e9399"), {"shade": 0.55, "rim": 0.3, "line": 0.006})
	var dark := K.toon(Color("#2a2f35"), {"shade": 0.6, "line": 0.005})

	# 价格塔：放在前场东北角，从国道和商店街方向都能看见
	var px := 26.4
	var pz := 5.2
	K.box(grp, Vector3(1.1, 0.36, 0.75), Vector3(px, WALK_Y + 0.18, pz), dark)
	K.box(grp, Vector3(0.32, 4.4, 0.32), Vector3(px, WALK_Y + 2.2, pz), steel)

	# 品牌板。灯箱比柱子厚一截：柱子 0.32m 宽，板面必须退到 0.24m 之外，
	# 否则从斜角看，立柱会从字中间穿出来，把 "HOSHIMI" 切成两半。
	K.box(grp, Vector3(0.48, 2.0, 2.15), Vector3(px, WALK_Y + 3.62, pz), green)
	for face in [-1, 1]:
		var fx: float = px + face * 0.245
		var rot := Vector3(0, 90 if face > 0 else -90, 0)
		K.label(grp, "HOSHIMI", Vector3(fx, WALK_Y + 4.35, pz), 0.34, Color("#fff0d2"), rot, 0)
		K.label(grp, "SERVICE STATION", Vector3(fx, WALK_Y + 4.05, pz), 0.1, Color("#d7c8a8"), rot, 0)
		K.label(grp, "SELF  ·  24H", Vector3(fx, WALK_Y + 3.78, pz), 0.11, Color("#ffcf8a"), rot, 0)

	# 价格板：白底黑字，夜里像一块灯箱
	K.box(grp, Vector3(0.46, 1.35, 2.0), Vector3(px, WALK_Y + 2.15, pz),
		K.glow(Color("#f6efdc"), 0.38), Vector3.ZERO, false)
	for face in [-1, 1]:
		var fx2: float = px + face * 0.235
		var rot2 := Vector3(0, 90 if face > 0 else -90, 0)
		K.label(grp, "REGULAR    ¥172", Vector3(fx2, WALK_Y + 2.55, pz), 0.16, Color("#26332d"), rot2, 0)
		K.label(grp, "HIGH-OCT   ¥180", Vector3(fx2, WALK_Y + 2.24, pz), 0.16, Color("#26332d"), rot2, 0)
		K.label(grp, "DIESEL     ¥168", Vector3(fx2, WALK_Y + 1.93, pz), 0.16, Color("#26332d"), rot2, 0)
		K.label(grp, "L  /  軽油", Vector3(fx2, WALK_Y + 1.7, pz), 0.09, Color("#5b6a60"), rot2, 0)
	K.box(grp, Vector3(0.5, 0.03, 2.05), Vector3(px, WALK_Y + 4.66, pz),
		K.glow(Color("#ffcf8a"), 1.2), Vector3.ZERO, false)

	var pl := OmniLight3D.new()
	pl.light_color = Color("#ffd9a2")
	pl.light_energy = 0.85
	pl.omni_range = 4.8
	pl.position = Vector3(px, WALK_Y + 4.0, pz - 0.9)
	grp.add_child(pl)
	K.plane(g, Vector2(3.4, 3.0), Vector3(px, WALK_Y + 0.007, pz - 0.5),
		K.wet(Color("#ffcf9a"), 0.06), Vector3.ZERO, false)

	# 回商店街的路牌：立在东侧人行道的路缘边。字面朝西，玩家往东走时正好读到。
	# z 不能放在人行道中间：出生点相机在玩家背后 5.4m、正好从牌子旁边看过去，
	# 牌子立在 z≈−1.7 时会挡住整个角色。挪到路缘边，它只在画面左侧。
	var sx := 28.75
	var sz := -0.2
	K.cyl(grp, 0.045, 2.6, Vector3(sx, WALK_Y + 1.3, sz), steel, Vector3.ZERO, 8)
	K.box(grp, Vector3(0.07, 0.78, 1.55), Vector3(sx, WALK_Y + 2.18, sz), green)
	K.label_cjk(grp, "星見町商店街", Vector3(sx - 0.045, WALK_Y + 2.3, sz), 0.15,
		Color("#f3dfb4"), Vector3(0, -90, 0))
	K.label(grp, "HOSHIMI SHOTENGAI", Vector3(sx - 0.045, WALK_Y + 2.1, sz), 0.065,
		Color("#d7c8a8"), Vector3(0, -90, 0))
	K.label(grp, "EAST  ·  300m", Vector3(sx - 0.045, WALK_Y + 1.97, sz), 0.055,
		Color("#9fb0a2"), Vector3(0, -90, 0))
	K.sphere(grp, 0.05, Vector3(sx, WALK_Y + 2.62, sz), K.glow(Color("#ffd9a2"), 2.0),
		Vector3.ZERO, 8, 1.0, false)
	var sl := OmniLight3D.new()
	sl.light_color = Color("#ffd0a0")
	sl.light_energy = 0.45
	sl.omni_range = 3.2
	sl.position = Vector3(sx, WALK_Y + 2.3, sz)
	grp.add_child(sl)
	K.plane(g, Vector2(2.0, 1.8), Vector3(sx, WALK_Y + 0.007, sz),
		K.wet(Color("#ffcf9a"), 0.05), Vector3.ZERO, false)

	# 人行道上的两盏路灯，给出生点与西端一点导向光
	_street_lamp(grp, Vector3(24.6, WALK_Y, -1.82))
	_street_lamp(grp, Vector3(5.2, WALK_Y, -1.82))


func _street_lamp(parent: Node3D, base: Vector3) -> void:
	var steel := K.toon(Color("#4e535b"), {"shade": 0.55, "rim": 0.28, "line": 0.006})
	K.cyl(parent, 0.07, 4.1, base + Vector3(0, 2.05, 0), steel, Vector3.ZERO, 10)
	K.cyl(parent, 0.13, 0.18, base + Vector3(0, 0.09, 0), steel, Vector3.ZERO, 10)
	K.strut(parent, base + Vector3(0, 4.04, 0), base + Vector3(0, 4.2, 0.55), 0.05, steel, 8)
	K.strut(parent, base + Vector3(0, 4.2, 0.55), base + Vector3(0, 4.14, 1.05), 0.045, steel, 8)
	var head := base + Vector3(0, 4.08, 1.05)
	K.box(parent, Vector3(0.28, 0.11, 0.5), head, K.toon(Color("#43474e"), {"shade": 0.6, "line": 0.005}))
	K.box(parent, Vector3(0.24, 0.025, 0.42), head + Vector3(0, -0.06, 0),
		K.glow(Color("#ffd9a2"), 2.6), Vector3.ZERO, false)
	K.sphere(parent, 0.2, head + Vector3(0, -0.05, 0), K.soft(Color("#ffb972"), 0.28, 1.8),
		Vector3.ZERO, 12, 0.6, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffc07a")
	l.light_energy = 1.4
	l.omni_range = 8.0
	l.omni_attenuation = 1.5
	l.position = head + Vector3(0, -0.2, 0)
	parent.add_child(l)
	K.plane(parent, Vector2(4.2, 4.2), base + Vector3(0, 0.008, 1.5),
		K.wet(Color("#ffb46a"), 0.07), Vector3.ZERO, false)


# ---------------------------------------------------------------- 道具与灯

func _build_props(g: Node3D) -> void:
	var grp := K.group(g, "Props")

	# 轻自动车停在亭子西侧，车头朝北，像是来补货的
	Props.kei_van(grp, Vector3(1.25, WALK_Y, 5.6), 8.0)
	# 半开的后备箱里堆着纸箱
	var box_mat := K.toon(Color("#8a6d22"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	K.box(grp, Vector3(0.4, 0.28, 0.34), Vector3(1.05, WALK_Y + 1.62, 4.5), box_mat,
		Vector3(0, 12, 0))

	# 进出车道两边的锥桶
	for p in [Vector3(13.9, WALK_Y, 4.7), Vector3(24.7, WALK_Y, 4.7)]:
		_cone(grp, p)

	# 贩卖机：挂在小卖亭雨棚下，面朝东
	Props.vending(grp, Vector3(7.45, WALK_Y, 11.35), 90.0)

	# 打气机：矮箱 + 盘起来的软管
	var air := K.group(grp, "AirPump", Vector3(7.45, WALK_Y, 6.75), Vector3(0, 90, 0))
	var shell := K.toon(Color("#3f6c8a"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	K.box(air, Vector3(0.62, 0.95, 0.45), Vector3(0, 0.48, 0), shell)
	K.box(air, Vector3(0.44, 0.24, 0.04), Vector3(0, 0.74, 0.24),
		K.glow(Color("#dff5ff"), 1.0), Vector3.ZERO, false)
	K.label(air, "AIR", Vector3(0, 0.74, 0.27), 0.12, Color("#173040"))
	K.torus(air, 0.15, 0.22, Vector3(0.34, 0.48, 0), K.toon(Color("#1b1e22"), {"line": 0.004}),
		Vector3(0, 0, 90))
	K.strut(air, Vector3(0.28, 0.62, 0), Vector3(0.48, 0.92, 0), 0.022,
		K.toon(Color("#15181c"), {"line": 0.0}), 6)

	# 灰水桶 / 拖把：细节，不挡人
	K.cyl(grp, 0.17, 0.34, Vector3(8.45, WALK_Y + 0.17, 12.55),
		K.toon(Color("#6f7377"), {"shade": 0.55, "rim": 0.25, "line": 0.005}), Vector3.ZERO, 12)
	K.strut(grp, Vector3(8.45, WALK_Y + 0.1, 12.55), Vector3(8.3, WALK_Y + 1.3, 12.6), 0.02,
		K.toon(Color("#4a3a28"), {"line": 0.0}), 6)


func _cone(parent: Node3D, base: Vector3) -> void:
	var orange := K.toon(Color("#c4582a"), {"shade": 0.6, "rim": 0.25, "line": 0.005})
	var white := K.toon(Color("#ddd6c6"), {"shade": 0.7, "line": 0.004})
	K.box(parent, Vector3(0.36, 0.04, 0.36), base + Vector3(0, 0.02, 0), orange)
	K.cyl(parent, 0.15, 0.56, base + Vector3(0, 0.3, 0), orange, Vector3.ZERO, 12, 0.015)
	K.cyl(parent, 0.105, 0.1, base + Vector3(0, 0.3, 0), white, Vector3.ZERO, 12, 0.075)


func _build_lights(g: Node3D) -> void:
	# 东边镇子的暖光：让回程方向不是一片死黑
	var town := OmniLight3D.new()
	town.light_color = Color("#ffbb7d")
	town.light_energy = 0.55
	town.omni_range = 9.0
	town.omni_attenuation = 1.8
	town.position = Vector3(31.5, 2.4, -0.5)
	g.add_child(town)


# ---------------------------------------------------------------- 碰撞

func _build_collision() -> void:
	var g := Node3D.new()
	g.name = "StationCollision"
	add_child(g)

	# 地面。前场与人行道都比马路高 16cm。
	CollisionLayout.solid(g, Vector3(CENTER_X, -1.0, 2.0), Vector3(X1 - X0, 2.0, ROAD_Z1 - ROAD_Z0))
	CollisionLayout.solid(g, Vector3(CENTER_X, WALK_Y - 1.0, (Z0 + ROAD_Z0) * 0.5),
		Vector3(X1 - X0, 2.0, ROAD_Z0 - Z0))
	CollisionLayout.solid(g, Vector3(CENTER_X, WALK_Y - 1.0, (ROAD_Z1 + Z1) * 0.5),
		Vector3(X1 - X0, 2.0, Z1 - ROAD_Z1))

	# 16cm 路缘的隐形坡。铺在马路一侧，别铺到路缘石底下；
	# 前场那条整段铺过去，正好把进出车道做成缓坡。
	CollisionLayout.slope(g, Vector3(CENTER_X, 0.0, 0.125), (X1 - X0) * 0.5, 0.125,
		0.0, WALK_Y, 180.0)
	CollisionLayout.slope(g, Vector3(CENTER_X, 0.0, 3.875), (X1 - X0) * 0.5, 0.125,
		0.0, WALK_Y, 0.0)

	# 顶棚柱
	for cx in [10.2, 21.8]:
		for cz in [7.2, 10.8]:
			CollisionLayout.pillar(g, Vector3(cx, 0.16 + 2.34, cz), 0.24, 4.68)

	# 两台加油机：岛台整块挡住，机身再补一层（相机贴近时不会穿进加油机）
	for cx in [12.2, 19.8]:
		CollisionLayout.solid(g, Vector3(cx, WALK_Y + 0.09, 9.0), Vector3(2.4, 0.18, 1.15))
		CollisionLayout.solid(g, Vector3(cx, WALK_Y + 1.0, 9.0), Vector3(0.74, 1.7, 0.58))

	# 小卖亭是整块的：设定上进不去，门只是画上去的。
	# 门洞留碰撞的话，0.32 半径的胶囊一挤就进去了，里面却没有任何内容。
	CollisionLayout.solid(g,
		Vector3((KIOSK_X0 + KIOSK_X1) * 0.5, 0.16 + 1.57, (KIOSK_Z0 + KIOSK_Z1) * 0.5),
		Vector3(KIOSK_X1 - KIOSK_X0, 3.14, KIOSK_Z1 - KIOSK_Z0))

	# 价格塔 / 回程路牌 / 路灯 / 打气机 / 贩卖机 / 轻自动车
	CollisionLayout.solid(g, Vector3(26.4, WALK_Y + 0.18, 5.2), Vector3(1.1, 0.4, 0.75))
	CollisionLayout.solid(g, Vector3(26.4, WALK_Y + 2.4, 5.2), Vector3(0.36, 4.8, 2.1))
	CollisionLayout.pillar(g, Vector3(28.75, WALK_Y + 1.3, -0.2), 0.06, 2.6)
	CollisionLayout.pillar(g, Vector3(24.6, WALK_Y + 2.05, -1.82), 0.07, 4.1)
	CollisionLayout.pillar(g, Vector3(5.2, WALK_Y + 2.05, -1.82), 0.07, 4.1)
	CollisionLayout.solid(g, Vector3(7.45, WALK_Y + 0.48, 6.75), Vector3(0.62, 0.95, 0.45))
	CollisionLayout.solid(g, Vector3(7.45, WALK_Y + 0.92, 11.35), Vector3(0.76, 1.84, 1.04))
	CollisionLayout.solid(g, Vector3(1.25, WALK_Y + 0.9, 5.6), Vector3(1.5, 1.8, 2.96), 8.0)

	# 绿篱不是装饰，是北侧边界。
	CollisionLayout.solid(g, Vector3(CENTER_X, 0.16 + 0.7, -2.25), Vector3(X1 - X0, 1.4, 0.5))

	# 场地边界。只做 1.5m 高：胶囊过不去（跳起来也只有 1.3m），
	# 但第三人称弹簧臂在 2.5m 左右，能直接从上面越过去。
	# 做成 4m 的话，出生点背后那堵墙会把镜头顶到 2.9m 处，一开场就是大脸。
	_camera_friendly_bound(g)
	# 南侧铁皮围墙 / 前场尽头
	CollisionLayout.solid(g, Vector3(CENTER_X, 0.16 + 1.1, Z1 - 0.05), Vector3(X1 - X0, 2.2, 0.2))


func _camera_friendly_bound(g: Node3D) -> void:
	var h := 1.5
	var t := 0.12
	for spec in [
			{"p": Vector3(X0, h * 0.5, CENTER_Z), "s": Vector3(t, h, Z1 - Z0)},
			{"p": Vector3(X1, h * 0.5, CENTER_Z), "s": Vector3(t, h, Z1 - Z0)},
			{"p": Vector3(CENTER_X, h * 0.5, Z1), "s": Vector3(X1 - X0, h, t)}]:
		CollisionLayout.solid(g, spec["p"], spec["s"])


# ---------------------------------------------------------------- 雨 / 涟漪

## 最多 32 块。顶棚 / 小卖亭 / 雨棚必须在这里，否则雨会穿过去继续下。
func _rain_covers() -> Array:
	return [
		# 北侧人行道 + 草坡
		{"x0": X0, "z0": SIDEWALK_Z0, "x1": X1, "z1": ROAD_Z0, "h": WALK_Y},
		{"x0": X0, "z0": Z0, "x1": X1, "z1": SIDEWALK_Z0, "h": 0.26},
		# 前场
		{"x0": X0, "z0": ROAD_Z1, "x1": X1, "z1": Z1, "h": WALK_Y},
		# 加油顶棚
		{"x0": CANOPY_X0, "z0": CANOPY_Z0, "x1": CANOPY_X1, "z1": CANOPY_Z1, "h": CANOPY_TOP},
		# 小卖亭屋面
		{"x0": KIOSK_X0, "z0": KIOSK_Z0, "x1": KIOSK_X1, "z1": KIOSK_Z1, "h": KIOSK_TOP},
		# 柜台雨棚
		{"x0": 6.9, "z0": 7.1, "x1": 8.3, "z1": 11.9, "h": 2.91},
	]


func _ripples() -> Array:
	return [
		{"pos": Vector3(CENTER_X, 0.007, 2.0), "size": Vector2(30.0, 3.9),
			"strength": 0.36, "dry": false},
		{"pos": Vector3(CENTER_X, 0.168, -1.0), "size": Vector2(30.0, 2.0),
			"strength": 0.26, "dry": false},
		# 前场：顶棚下方应保持干燥，dry 矩形和顶棚同尺寸
		{"pos": Vector3(CENTER_X, 0.168, 9.0), "size": Vector2(30.0, 10.0),
			"strength": 0.22, "dry": true,
			"dry_min": Vector2(CANOPY_X0, CANOPY_Z0), "dry_max": Vector2(CANOPY_X1, CANOPY_Z1)},
		{"pos": Vector3(CENTER_X, CANOPY_TOP + 0.01, 9.0),
			"size": Vector2(CANOPY_X1 - CANOPY_X0, CANOPY_Z1 - CANOPY_Z0),
			"strength": 0.3, "dry": false},
		{"pos": Vector3((KIOSK_X0 + KIOSK_X1) * 0.5, KIOSK_TOP + 0.01, (KIOSK_Z0 + KIOSK_Z1) * 0.5),
			"size": Vector2(KIOSK_X1 - KIOSK_X0, KIOSK_Z1 - KIOSK_Z0),
			"strength": 0.3, "dry": false},
		{"pos": Vector3(7.6, 2.92, 9.5), "size": Vector2(1.4, 4.9),
			"strength": 0.2, "dry": false},
	]


# ---------------------------------------------------------------- 装配

func _setup_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	player.position = SPAWN
	# 相机在 +X 侧、看向 −X：从商店街出来继续往西
	player.start_yaw_deg = 90.0
	player.capture_mouse_on_start = false
	player.actor_tint = Color(0.54, 0.57, 0.68)
	player.actor_shade_floor = 0.35
	player.actor_rim_strength = 0.07
	player.actor_outline_width = 0.006
	player.cam_distance = CAM["dist"]
	player.cam_height = CAM["height"]
	add_child(player)
	player.input_locked = true
	player.face(-PI * 0.5)
	player.set_camera_profile(CAM["dist"], CAM["height"], CAM["fov"],
		CAM["shoulder"], 6.0)


func _setup_hud() -> void:
	hud = Hud.new()
	hud.name = "HUD"
	hud.title_text = "HOSHIMI SERVICE STATION"
	hud.subtitle_text = "雨夜 00:06　国道 17 号"
	hud.zone_text = "加油站 · 人行道"
	hud.accent_color = Color("#ffcf8a")
	add_child(hud)
	hud.set_zone("加油站 · 人行道", false)


func _setup_interactions() -> void:
	hub = Hub.new()
	hub.name = "InteractionHub"
	add_child(hub)
	hub.bind(player, hud)

	hub.add_target(Vector3(12.2, 1.1, 9.0), 1.7, "拿起油枪", _on_pump)
	hub.add_target(Vector3(19.8, 1.1, 9.0), 1.7, "拿起油枪", _on_pump)
	hub.add_target(Vector3(7.02, 1.2, 9.6), 1.9, "敲敲柜台", _on_counter)
	hub.add_target(Vector3(7.65, 0.9, 6.75), 1.4, "给轮胎打气", _on_air)
	hub.add_target(Vector3(26.4, 1.5, 5.2), 2.0, "看看油价", _on_price)
	hub.add_target(Vector3(7.9, 1.1, 11.35), 1.5, "买一罐热咖啡", _on_vending)
	# 逢魔时之后旧世界线已经收束，路牌上的「回商店街」不再生效。
	hub.add_target(Vector3(28.75, 1.2, -0.2), 1.7, "回星见町商店街", _on_back, _can_return)


func _can_return() -> bool:
	return story == null or story.return_allowed()


func _setup_story() -> void:
	story = GasStationStory.new()
	story.name = "Story"
	# 先 bind 再 add_child：剧情节点的 _ready() 会直接开始搭货车 / 收音机，
	# 那时它必须已经拿得到 player / hud / hub / env。
	story.bind(self)
	add_child(story)


func _setup_audio() -> void:
	_rain = _looping_player("res://audio/rain_loop.wav", -14.0)
	_hum = _looping_player("res://audio/drone_loop.wav", -38.0)


## 剧情死亡时把环境声一起收掉。只暴露这一个入口，不让剧情去读 _rain / _hum：
## 那两个节点是私有的，换个命名、加一层容器就会静默失效。
func fade_station_audio(seconds: float) -> void:
	_audio_override = true
	var tw := create_tween().set_parallel(true)
	if _rain != null:
		tw.tween_property(_rain, "volume_db", -60.0, seconds)
	if _hum != null:
		tw.tween_property(_hum, "volume_db", -60.0, seconds)


func _looping_player(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s := load(path) as AudioStreamWAV
	if s != null:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * float(s.mix_rate))
		p.stream = s
	p.volume_db = db
	add_child(p)
	p.play()
	return p


# ---------------------------------------------------------------- 开场 / 转场

func _show_first_frame() -> void:
	hud.fade_in(1.6)
	player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("WASD 移动 · 穿过国道就是 HOSHIMI SS", 4.0)


## 被转场送到这里：黑幕由转场层负责淡出，这里只负责解锁和点灯。
func _on_arrival() -> void:
	hud.fade_in(0.0)
	player.camera.current = true
	player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_zone("加油站 · 人行道", true)
	hud.toast("国道 17 号。雨被顶棚切开，加油站还亮着。", 4.5)

	# 转场层还要 1s 才淡完 / 自毁。这段时间忽略回程触发，
	# 否则「落地 → 转身往东跑」会撞上一个尚未消失的转场层。
	_transitioning = true
	await get_tree().create_timer(1.2).timeout
	_transitioning = false


## 探针 / 调试用：跳过开场淡入。
func skip_intro() -> void:
	_arriving = false
	hud.fade_in(0.0)
	player.camera.current = true
	player.input_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 转场开始后锁住当前场景。LetterTransition 也会调一次，重复调用无害。
func lock_for_transition() -> void:
	player.input_locked = true
	if hub != null:
		hub.enabled = false
	if hud != null:
		hud.hide_prompt()
		hud.hide_toast()
	if story != null and story.has_method("on_transition_lock"):
		story.on_transition_lock()


func _process(delta: float) -> void:
	if player == null:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var p: Vector3 = player.global_position
	var zone := _zone_at(p)
	if zone != _zone:
		_on_zone_changed(zone)

	# 顶棚下只剩铁皮上的闷响，雨声要明显收一档。
	# 死亡段由剧情接管音量，这里再往回拉会把「听觉熄灭」拉回去。
	if not _audio_override:
		var rain_db := -20.0 if zone == "canopy" else -14.0
		if _rain != null:
			_rain.volume_db = lerpf(_rain.volume_db, rain_db, 1.0 - exp(-1.6 * delta))
		if _hum != null:
			_hum.volume_db = lerpf(_hum.volume_db, -38.0, 1.0 - exp(-1.6 * delta))

	# 往东走过路牌就回商店街。只认北侧人行道：前场东缘也在 x > RETURN_X，
	# 不加 z 条件的话，人在油站里绕到东边就会被莫名其妙地送走。
	# 出生点在触发线以西 1.55m，落地不会立刻反弹。
	if not _transitioning and not _shooting and not player.input_locked \
			and p.x > RETURN_X and p.z < ROAD_Z0 \
			and (story == null or not story.blocks_return()):
		_go_shotengai()


func zone() -> String:
	return _zone


func _zone_at(p: Vector3) -> String:
	if p.z >= CANOPY_Z0 and p.z <= CANOPY_Z1 and p.x > CANOPY_X0 and p.x < CANOPY_X1:
		return "canopy"
	if p.z >= ROAD_Z1:
		return "forecourt"
	if p.z >= ROAD_Z0:
		return "road"
	return "walk"


func _on_zone_changed(zone: String) -> void:
	_zone = zone
	match zone:
		"canopy":
			hud.set_zone("加油站 · 顶棚下", true)
		"forecourt":
			hud.set_zone("加油站 · 前场", true)
		"road":
			hud.set_zone("国道 17 号", false)
		_:
			hud.set_zone("加油站 · 人行道", false)

	if zone == "forecourt" and not _seen_forecourt and not _shooting:
		_seen_forecourt = true
		hud.toast("汽油、湿沥青和铁皮上的雨。顶棚下面比外面安静一半。", 4.5)


func _go_shotengai() -> void:
	if _transitioning:
		return
	if story != null and story.blocks_return():
		return
	# 先看层在不在，再锁人：层还在时锁了再返回，会把人卡在输入锁里。
	if get_tree().root.has_node("LetterTransition"):
		return

	_transitioning = true
	lock_for_transition()

	var tr := LetterTransition.new()
	tr.name = "LetterTransition"
	tr.title_text = "HOSHIMI"
	tr.subtitle_text = "SHOTENGAI"
	tr.footer_text = "WEST GATE · 00:07"
	get_tree().root.add_child(tr)
	tr.play(TOWN_SCENE)


# ---------------------------------------------------------------- 交互回调

func _on_pump() -> void:
	_play_at(Vector3(12.2, 1.1, 9.0), Sfx.tap(), -5.0)
	hud.toast("油枪比想象中沉。计数器归零，汽油味一下子盖过了雨。", 4.2)


func _on_counter() -> void:
	_play_at(Vector3(7.0, 1.2, 8.6), Sfx.bell(), -4.0)
	hud.toast("窗里的店员抬起头，隔着玻璃朝你点了点头，又低头去整理收据。", 4.2)


func _on_air() -> void:
	_play_at(Vector3(7.45, 0.9, 6.75), Sfx.tap(), -8.0)
	hud.toast("气泵嗡了两声，软管在手里轻轻抖。轮胎早就不缺气了。", 4.2)


func _on_price() -> void:
	hud.toast("REGULAR ¥172 / HIGH-OCT ¥180。比市区便宜两块钱。", 4.2)


func _on_vending() -> void:
	_play_at(Vector3(7.45, 1.0, 11.35), Sfx.tap(), -7.0)
	hud.toast("热咖啡落进取物口，罐身烫手。自动门里飘出一点关东煮的味道。", 4.2)


func _on_back() -> void:
	_go_shotengai()


func _play_at(pos: Vector3, stream: AudioStream, db: float = -6.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.volume_db = db
	p.unit_size = 3.0
	p.max_distance = 14.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ---------------------------------------------------------------- 截图

func _only_shot() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(7)
	return ""


func _take_shots() -> void:
	_shooting = true
	player.input_locked = false
	hub.enabled = false
	hud.fade_in(0.0)
	hud.hide_prompt()
	DirAccess.make_dir_recursive_absolute("res://shots")
	env.tonemap_exposure = 1.14

	var specs := [
		{"name": "gas_a_arrive", "player": true, "pos": SPAWN, "face": -PI * 0.5,
			"yaw": 90.0, "pitch": -0.10, "dist": 4.4, "height": 1.45, "fov": 52.0, "shoulder": 0.30},
		{"name": "gas_b_canopy", "free": Vector3(26.5, 4.2, 2.6),
			"look": Vector3(16.0, 2.0, 9.0), "fov": 60.0},
		{"name": "gas_c_pumps", "free": Vector3(16.0, 2.2, 13.4),
			"look": Vector3(16.0, 1.4, 8.4), "fov": 56.0},
		{"name": "gas_d_kiosk", "free": Vector3(10.6, 2.6, 13.0),
			"look": Vector3(4.8, 1.7, 9.2), "fov": 55.0},
		{"name": "gas_e_pylon", "free": Vector3(22.5, 2.2, -2.6),
			"look": Vector3(26.4, 2.9, 5.2), "fov": 50.0},
		{"name": "gas_f_wide", "free": Vector3(31.8, 6.6, -3.6),
			"look": Vector3(13.0, 2.2, 8.6), "fov": 62.0},
	]
	var only := _only_shot()

	for s in specs:
		if only != "" and s["name"] != only:
			continue
		if s.has("free"):
			await _shot_free(s["name"], s["free"], s["look"], s["fov"])
			continue
		player.global_position = s["pos"]
		player.face(s["face"])
		player.set_view(s["yaw"], s["pitch"])
		player.snap_camera(s["dist"], s["height"], s["fov"], s["shoulder"])
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])

	get_tree().quit()


func _shot_free(shot_name: String, pos: Vector3, look: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.current = true
	player.camera.current = false
	player.visible = false
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % shot_name)
	print("saved ", shot_name)
	cam.queue_free()
	player.visible = true
	player.camera.current = true
