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
	_drain_grate(g, 12.15, 13.6)
	_drain_grate(g, 5.85, 13.6)


## 顶棚边缘的线性排水沟。只铺一块黑平面的话，夜里看起来像地面上的一条裂缝；
## 补上外框、纵向栅条和横向拉杆，它才会被读成铸铁篦子。
func _drain_grate(parent: Node3D, cz: float, width: float) -> void:
	var channel := K.toon(Color("#111419"), {"shade": 0.8, "line": 0.0})
	var metal := K.toon(Color("#555b63"), {"shade": 0.5, "rim": 0.35, "line": 0.003})
	var y := WALK_Y + 0.005
	K.plane(parent, Vector2(width, 0.3), Vector3(CENTER_X, y, cz), channel, Vector3.ZERO, false)
	for dz in [-0.13, 0.13]:
		K.box(parent, Vector3(width, 0.016, 0.035), Vector3(CENTER_X, y + 0.004, cz + dz),
			metal, Vector3.ZERO, false)
	for dz in [-0.065, 0.0, 0.065]:
		K.box(parent, Vector3(width - 0.05, 0.01, 0.018), Vector3(CENTER_X, y + 0.006, cz + dz),
			metal, Vector3.ZERO, false)
	var x := CENTER_X - width * 0.5 + 0.55
	while x < CENTER_X + width * 0.5 - 0.3:
		K.box(parent, Vector3(0.05, 0.012, 0.26), Vector3(x, y + 0.007, cz),
			metal, Vector3.ZERO, false)
		x += 1.45


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
	var dark := K.toon(Color("#3b4046"), {"shade": 0.6, "rim": 0.2, "line": 0.004})
	var pipe := K.toon(Color("#2b3330"), {"shade": 0.6, "rim": 0.2, "line": 0.004})
	var red := K.toon(Color("#a83a30"), {"shade": 0.55, "rim": 0.25, "line": 0.005})

	# 四根柱：位置贴着两台加油机的两侧，镜头绕着走时不会一头撞上去。
	# 柱脚补方形底板和上法兰，圆柱直接插进地里会像纸片。
	for cx in [10.2, 21.8]:
		for cz in [7.2, 10.8]:
			K.box(grp, Vector3(0.62, 0.04, 0.62), Vector3(cx, WALK_Y + 0.02, cz), dark)
			K.cyl(grp, 0.22, 4.68, Vector3(cx, 0.16 + 2.34, cz), steel, Vector3.ZERO, 14)
			K.cyl(grp, 0.235, 0.16, Vector3(cx, 0.16 + 0.72, cz), red, Vector3.ZERO, 14)
			K.cyl(grp, 0.238, 0.05, Vector3(cx, 0.16 + 0.84, cz), cream, Vector3.ZERO, 14,
				-1.0, false)
			K.cyl(grp, 0.26, 0.08, Vector3(cx, 4.62, cz), dark, Vector3.ZERO, 14, -1.0, false)
			K.cyl(grp, 0.3, 0.12, Vector3(cx, 0.16 + 0.06, cz),
				K.toon(Color("#7c8188"), {"shade": 0.6, "line": 0.005}), Vector3.ZERO, 14)

	# 两根落水管贴着柱脚，管子落地再折出去。顶棚上的雨必须有去处，
	# 不然「雨被顶棚切开」只是视觉上的。位置贴着柱侧，不另加碰撞。
	for spec in [
			{"x": 10.2, "z": 7.2, "ox": 0.25, "dz": -0.36},
			{"x": 21.8, "z": 10.8, "ox": -0.25, "dz": 0.36}]:
		var px: float = spec["x"] + spec["ox"]
		var pz: float = spec["z"]
		var dz: float = spec["dz"]
		K.cyl(grp, 0.045, 4.5, Vector3(px, 2.55, pz), pipe, Vector3.ZERO, 8)
		K.strut(grp, Vector3(px, 0.34, pz), Vector3(px, 0.2, pz + dz), 0.045, pipe, 8)
		K.box(grp, Vector3(0.3, 0.035, 0.3), Vector3(px, 0.178, pz + dz + 0.05),
			K.toon(Color("#494d53"), {"shade": 0.65, "line": 0.004}), Vector3.ZERO, false)

	# 屋面：顶 5.16，底面 4.84。雨棚高度同时写进 _rain_covers()
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.32, CANOPY_Z1 - CANOPY_Z0),
		Vector3(CENTER_X, 5.0, 9.0), green)
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.56, 0.12), Vector3(CENTER_X, 4.88, CANOPY_Z0 + 0.04), green)
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.56, 0.12), Vector3(CENTER_X, 4.88, CANOPY_Z1 - 0.04), green)
	K.box(grp, Vector3(0.12, 0.56, CANOPY_Z1 - CANOPY_Z0), Vector3(CANOPY_X0 + 0.04, 4.88, 9.0), green)
	K.box(grp, Vector3(0.12, 0.56, CANOPY_Z1 - CANOPY_Z0), Vector3(CANOPY_X1 - 0.04, 4.88, 9.0), green)

	# 檐口：奶油色细线 + 底沿暗槽，给 5m 高的绿檐一条能读的收口。
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.08, 0.02), Vector3(CENTER_X, 4.7, CANOPY_Z0 - 0.012),
		cream, Vector3.ZERO, false)
	K.box(grp, Vector3(CANOPY_X1 - CANOPY_X0, 0.08, 0.02), Vector3(CENTER_X, 4.7, CANOPY_Z1 + 0.012),
		cream, Vector3.ZERO, false)
	K.box(grp, Vector3(0.02, 0.08, CANOPY_Z1 - CANOPY_Z0), Vector3(CANOPY_X0 - 0.012, 4.7, 9.0),
		cream, Vector3.ZERO, false)
	K.box(grp, Vector3(0.02, 0.08, CANOPY_Z1 - CANOPY_Z0), Vector3(CANOPY_X1 + 0.012, 4.7, 9.0),
		cream, Vector3.ZERO, false)
	for spec in [
			{"p": Vector3(CENTER_X, 4.585, CANOPY_Z0 - 0.01), "s": Vector3(CANOPY_X1 - CANOPY_X0, 0.05, 0.05)},
			{"p": Vector3(CENTER_X, 4.585, CANOPY_Z1 + 0.01), "s": Vector3(CANOPY_X1 - CANOPY_X0, 0.05, 0.05)},
			{"p": Vector3(CANOPY_X0 - 0.01, 4.585, 9.0), "s": Vector3(0.05, 0.05, CANOPY_Z1 - CANOPY_Z0)},
			{"p": Vector3(CANOPY_X1 + 0.01, 4.585, 9.0), "s": Vector3(0.05, 0.05, CANOPY_Z1 - CANOPY_Z0)}]:
		K.box(grp, spec["s"], spec["p"], dark, Vector3.ZERO, false)

	# 北面（马路一侧）的灯箱：先做深绿灯箱壳，再把奶油面板凸出来。
	# 原来只有一块发光片贴在檐口上，侧面看出是纸片。
	K.box(grp, Vector3(8.9, 0.6, 0.12), Vector3(16.0, 4.98, CANOPY_Z0 - 0.04), green)
	K.box(grp, Vector3(8.56, 0.46, 0.02), Vector3(16.0, 4.98, CANOPY_Z0 - 0.105),
		K.glow(Color("#fff0d2"), 0.55), Vector3.ZERO, false)
	K.label(grp, "HOSHIMI", Vector3(16.0, 5.06, CANOPY_Z0 - 0.12), 0.26, Color("#1d3a33"),
		Vector3(0, 180, 0), 0)
	K.label(grp, "SERVICE STATION  ·  SELF", Vector3(16.0, 4.86, CANOPY_Z0 - 0.12), 0.085,
		Color("#2d4a41"), Vector3(0, 180, 0), 0)
	K.box(grp, Vector3(13.4, 0.03, 0.04), Vector3(16.0, 4.61, CANOPY_Z0 - 0.01),
		K.glow(Color("#ffcf8a"), 0.95), Vector3.ZERO, false)

	# 南面朝前场深处，写字少一点
	K.box(grp, Vector3(5.7, 0.55, 0.12), Vector3(16.0, 4.97, CANOPY_Z1 + 0.04), green)
	K.box(grp, Vector3(5.36, 0.4, 0.02), Vector3(16.0, 4.97, CANOPY_Z1 + 0.105),
		K.glow(Color("#fff0d2"), 0.45), Vector3.ZERO, false)
	K.label(grp, "SELF  ·  24H", Vector3(16.0, 4.97, CANOPY_Z1 + 0.12), 0.2, Color("#1d3a33"),
		Vector3.ZERO, 0)

	# 东西两侧的小字灯箱。原来标签的中心算在棚体里面（x 朝内偏了 2cm），
	# 从侧面根本看不见字；现在灯箱和字都退到檐口外面。
	for spec in [{"x": CANOPY_X0 - 0.04, "rot": -90, "face": -1.0},
			{"x": CANOPY_X1 + 0.04, "rot": 90, "face": 1.0}]:
		var sx: float = spec["x"]
		var face: float = spec["face"]
		K.box(grp, Vector3(0.12, 0.5, 4.5), Vector3(sx, 4.96, 9.0), green)
		K.box(grp, Vector3(0.02, 0.36, 4.2), Vector3(sx + face * 0.065, 4.96, 9.0),
			K.glow(Color("#fff0d2"), 0.4), Vector3.ZERO, false)
		K.label(grp, "HOSHIMI", Vector3(sx + face * 0.08, 4.96, 9.0),
			0.17, Color("#1d3a33"), Vector3(0, spec["rot"], 0), 0)

	# 底面梁架：两根主梁 + 四根次梁。灯管挂在梁下面，顶棚不再是平的一块板。
	K.box(grp, Vector3(11.6, 0.12, 0.14), Vector3(16.0, 4.76, 7.2), dark, Vector3.ZERO, false)
	K.box(grp, Vector3(11.6, 0.12, 0.14), Vector3(16.0, 4.76, 10.8), dark, Vector3.ZERO, false)
	for bx in [10.2, 21.8]:
		K.box(grp, Vector3(0.14, 0.12, 3.6), Vector3(bx, 4.76, 9.0), dark, Vector3.ZERO, false)
	for bx2 in [12.5, 16.0, 19.5]:
		K.box(grp, Vector3(0.07, 0.09, 5.8), Vector3(bx2, 4.79, 9.0), dark, Vector3.ZERO, false)
	# 沿北梁的走线管，给梁架一点「有设备」的痕迹
	K.cyl(grp, 0.018, 11.4, Vector3(16.0, 4.69, 7.48), pipe, Vector3(0, 0, 90), 6, -1.0, false)

	# 底面六块灯管：深色灯槽 + 冷白发光面。原来的发光片直接贴在屋面上，
	# 从低角度看就像天花板上贴了六张纸。
	for px in [11.8, 16.0, 20.2]:
		for pz in [7.4, 10.6]:
			K.box(grp, Vector3(3.72, 0.07, 1.94), Vector3(px, 4.80, pz), dark,
				Vector3.ZERO, false)
			K.box(grp, Vector3(3.5, 0.02, 1.72), Vector3(px, 4.758, pz),
				K.glow(Color("#eaf4ff"), 1.05), Vector3.ZERO, false)

	# 悬吊的 SELF 牌：奶油外框 + 绿面板，双层才有厚度
	K.box(grp, Vector3(1.58, 0.46, 0.06), Vector3(16.0, 4.15, 9.0), cream)
	K.box(grp, Vector3(1.46, 0.34, 0.075), Vector3(16.0, 4.15, 9.0), green)
	for zsign in [-1, 1]:
		K.label(grp, "SELF", Vector3(16.0, 4.15, 9.0 + zsign * 0.045), 0.16,
			Color("#f2e6cf"), Vector3(0, 0 if zsign > 0 else 180, 0))
	for sx2 in [-0.55, 0.55]:
		K.strut(grp, Vector3(16.0 + sx2, 4.38, 9.0), Vector3(16.0 + sx2, 4.84, 9.0), 0.012,
			dark, 4, false)

	# 檐下的监控：小，但让「无人自助站」有被看着的感觉。
	var cam_grp := K.group(grp, "Camera", Vector3(11.4, 4.62, 6.5))
	K.strut(cam_grp, Vector3(0, 0.22, 0.22), Vector3(0, 0.03, 0), 0.018, dark, 6, false)
	K.box(cam_grp, Vector3(0.14, 0.11, 0.22), Vector3.ZERO, dark, Vector3(-12, 0, 0), false)
	K.cyl(cam_grp, 0.035, 0.03, Vector3(0, -0.01, -0.12),
		K.toon(Color("#0d1014"), {"shade": 0.9, "line": 0.0}), Vector3(90, 0, 0), 10, -1.0, false)
	K.sphere(cam_grp, 0.008, Vector3(0.04, 0.02, -0.02), K.glow(Color("#ff5a4a"), 1.6),
		Vector3.ZERO, 6, 1.0, false)

	# 柱身上的禁煙牌，面朝国道。
	var no_smoke := K.group(grp, "NoSmoking", Vector3(10.2, 1.6, 6.962))
	K.box(no_smoke, Vector3(0.26, 0.34, 0.02), Vector3.ZERO, cream, Vector3.ZERO, false)
	K.box(no_smoke, Vector3(0.22, 0.3, 0.006), Vector3(0, 0, -0.012),
		K.toon(Color("#f2eee4"), {"shade": 0.9, "line": 0.0}), Vector3.ZERO, false)
	K.label_cjk(no_smoke, "禁煙", Vector3(0, 0.035, -0.021), 0.1, Color("#b23a28"),
		Vector3(0, 180, 0), 0)
	K.label(no_smoke, "NO SMOKING", Vector3(0, -0.095, -0.021), 0.032, Color("#3b4440"),
		Vector3(0, 180, 0), 0)

	# 顶棚前场的两个冷白光源。只开西侧那盏的阴影：
	# 立方体阴影很贵，两盏全开等于整个前场多渲染两遍。
	_canopy_light(grp, Vector3(12.6, 4.55, 9.0), 2.0, true)
	_canopy_light(grp, Vector3(19.4, 4.55, 9.0), 1.8, false)

	# 加油机头顶的湿地反光
	for px2 in [12.2, 19.8]:
		K.plane(grp, Vector2(4.4, 3.4), Vector3(px2, WALK_Y + 0.007, 9.0),
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
	var body := K.toon(Color("#e2ddd0"), {"shade": 0.6, "rim": 0.18, "line": 0.006})
	var dark := K.toon(Color("#2a3a35"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	var brand := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.006})
	var hose := K.toon(Color("#15181c"), {"shade": 0.7, "line": 0.004})
	var chrome := K.toon(Color("#a8adb3"), {"shade": 0.5, "rim": 0.4, "line": 0.004})
	var yellow := K.toon(Color("#c2a648"), {"shade": 0.55, "rim": 0.2, "line": 0.004})
	var stain := K.toon(Color("#3a3e45"), {"shade": 0.7, "line": 0.0})
	var screen := K.glow(Color("#d9f2ff"), 0.95)
	var led := K.glow(Color("#ffd59a"), 1.1)

	for spec in [
			{"x": 12.2, "no": "1", "grade": "レギュラー", "grade_col": Color("#b84338"),
				"price": "¥172"},
			{"x": 19.8, "no": "2", "grade": "ハイオク", "grade_col": Color("#c9a640"),
				"price": "¥180"}]:
		var cx: float = spec["x"]
		var grade_col: Color = spec["grade_col"]
		var accent := K.toon(grade_col, {"shade": 0.55, "rim": 0.25, "line": 0.005})
		var grp := K.group(g, "Pump" + String(spec["no"]))

		# 岛台高 18cm：挡住人，也挡镜头，但不会挡住视线。
		# 顶面再压一块深一号的铺装，不然 2.4m 宽的混凝土会是一整片灰。
		K.box(grp, Vector3(2.4, 0.18, 1.15), Vector3(cx, WALK_Y + 0.09, 9.0), concrete)
		K.box(grp, Vector3(1.92, 0.012, 0.8), Vector3(cx, WALK_Y + 0.186, 9.0),
			K.toon(Color("#85898f"), {"shade": 0.55, "line": 0.0}), Vector3.ZERO, false)
		# 四边黄线。原来只画了南北两条，东西两端露着灰边，近看像没画完。
		for z in [8.44, 9.56]:
			K.box(grp, Vector3(2.42, 0.025, 0.05), Vector3(cx, WALK_Y + 0.185, z), yellow,
				Vector3.ZERO, false)
		for sx in [-1.0, 1.0]:
			K.box(grp, Vector3(0.05, 0.025, 1.13), Vector3(cx + sx * 1.18, WALK_Y + 0.185, 9.0),
				yellow, Vector3.ZERO, false)
		# 岛台上的旧油渍。故意不对称，太规整就成图案了。
		for s in [Vector3(-0.62, 0.0, 0.24), Vector3(0.5, 0.0, -0.3), Vector3(0.76, 0.0, 0.32)]:
			K.cyl(grp, 0.07 + absf(s.x) * 0.1, 0.004, Vector3(cx + s.x, WALK_Y + 0.193, 9.0 + s.z),
				stain, Vector3.ZERO, 10, -1.0, false)

		# 机身分三段：深色底座 → 奶油机身 + 品牌绿裙板 → 深绿顶罩。
		# 比例参考实际 dispenser：裙板是会被剐蹭的高度，屏幕落在视线高度。
		K.box(grp, Vector3(0.78, 0.1, 0.62), Vector3(cx, WALK_Y + 0.23, 9.0), dark)
		K.box(grp, Vector3(0.66, 1.18, 0.5), Vector3(cx, WALK_Y + 0.87, 9.0), body)
		K.box(grp, Vector3(0.68, 0.36, 0.52), Vector3(cx, WALK_Y + 0.46, 9.0), brand)
		K.box(grp, Vector3(0.69, 0.025, 0.53), Vector3(cx, WALK_Y + 0.655, 9.0), chrome,
			Vector3.ZERO, false)
		K.box(grp, Vector3(0.72, 0.42, 0.56), Vector3(cx, WALK_Y + 1.63, 9.0), brand)
		K.box(grp, Vector3(0.74, 0.03, 0.58), Vector3(cx, WALK_Y + 1.58, 9.0), led,
			Vector3.ZERO, false)
		K.box(grp, Vector3(0.76, 0.06, 0.6), Vector3(cx, WALK_Y + 1.86, 9.0), body)

		# 两面都要读得懂：冰蓝屏幕 + 深色屏框 + 油品色条 + 大号单价。
		# 玻璃本身不再是一整块过曝的白板 —— 有框、有数字，才有「机器」感。
		for zsign in [-1, 1]:
			var fz: float = 9.0 + zsign * 0.26
			var rot_y := 0.0 if zsign > 0 else 180.0
			K.box(grp, Vector3(0.58, 0.36, 0.04), Vector3(cx, WALK_Y + 1.22, fz), dark,
				Vector3.ZERO, false)
			K.box(grp, Vector3(0.5, 0.27, 0.015), Vector3(cx, WALK_Y + 1.2, fz + zsign * 0.024),
				screen, Vector3.ZERO, false)
			K.box(grp, Vector3(0.5, 0.04, 0.012), Vector3(cx, WALK_Y + 1.37, fz + zsign * 0.025),
				accent, Vector3.ZERO, false)
			K.label(grp, String(spec["price"]), Vector3(cx, WALK_Y + 1.2, fz + zsign * 0.033),
				0.12, Color("#17272c"), Vector3(0, rot_y, 0))
			K.label(grp, "L 00.00", Vector3(cx, WALK_Y + 1.1, fz + zsign * 0.033),
				0.045, Color("#33484e"), Vector3(0, rot_y, 0))
			K.label(grp, "SELF", Vector3(cx + 0.16, WALK_Y + 1.37, fz + zsign * 0.034),
				0.04, Color("#f4e9d4"), Vector3(0, rot_y, 0))
			# 键盘 / 刷卡槽 / 小票口：不追求能按，只要近看有层次。
			K.box(grp, Vector3(0.34, 0.17, 0.02), Vector3(cx, WALK_Y + 0.94, fz), dark,
				Vector3.ZERO, false)
			for kx in [-0.09, 0.09]:
				for ky in [0.9, 0.97]:
					K.box(grp, Vector3(0.05, 0.025, 0.012),
						Vector3(cx + kx, WALK_Y + ky, fz + zsign * 0.014), chrome,
						Vector3.ZERO, false)
			K.box(grp, Vector3(0.13, 0.016, 0.01), Vector3(cx - 0.15, WALK_Y + 0.86, fz + zsign * 0.014),
				chrome, Vector3.ZERO, false)
			# 顶罩上的机号和油品色牌
			K.box(grp, Vector3(0.12, 0.24, 0.012), Vector3(cx + 0.24, WALK_Y + 1.63, fz + zsign * 0.025),
				accent, Vector3.ZERO, false)
			K.label(grp, String(spec["no"]), Vector3(cx - 0.1, WALK_Y + 1.63, fz + zsign * 0.034),
				0.22, Color("#f2e6cf"), Vector3(0, rot_y, 0))
			# 裙板上的圆形站徽
			K.cyl(grp, 0.085, 0.012, Vector3(cx, WALK_Y + 0.46, fz + zsign * 0.008),
				K.toon(Color("#ece4d2"), {"shade": 0.8, "line": 0.0}), Vector3(90, 0, 0), 16, -1.0, false)
			K.label(grp, "H", Vector3(cx, WALK_Y + 0.46, fz + zsign * 0.016),
				0.09, Color("#1d3a33"), Vector3(0, rot_y, 0))

		# 油枪：软管从机身两侧上方出来，绕一小圈落到侧面的枪座。
		# 原来的枪头直接悬在岛台边，看不出「挂在机器上」。
		for sx in [-1.0, 1.0]:
			var side: float = cx + sx * 0.33
			var pts := PackedVector3Array([
				Vector3(side, WALK_Y + 1.12, 9.0),
				Vector3(side + sx * 0.1, WALK_Y + 1.04, 9.03),
				Vector3(side + sx * 0.15, WALK_Y + 0.88, 9.08),
				Vector3(side + sx * 0.12, WALK_Y + 0.73, 9.14),
				Vector3(side + sx * 0.06, WALK_Y + 0.62, 9.17),
			])
			K.tube(grp, pts, 0.024, hose, 6)
			K.box(grp, Vector3(0.13, 0.22, 0.12), Vector3(side + sx * 0.01, WALK_Y + 0.51, 9.17),
				dark)
			K.box(grp, Vector3(0.07, 0.15, 0.08), Vector3(side + sx * 0.02, WALK_Y + 0.62, 9.17),
				chrome)
			K.box(grp, Vector3(0.045, 0.1, 0.05), Vector3(side + sx * 0.02, WALK_Y + 0.55, 9.19),
				hose, Vector3.ZERO, false)
			K.strut(grp, Vector3(side + sx * 0.02, WALK_Y + 0.7, 9.17),
				Vector3(side + sx * 0.02, WALK_Y + 0.76, 9.1), 0.012, chrome, 5, false)

		# 岛四角的防撞柱：在碰撞盒里面，不改变走位，只补上现实里必有的那一圈黄黑。
		for bx in [-1.06, 1.06]:
			for bz in [8.53, 9.47]:
				var bp := Vector3(cx + bx, WALK_Y + 0.18, bz)
				K.cyl(grp, 0.05, 0.62, bp + Vector3(0, 0.31, 0), yellow, Vector3.ZERO, 10)
				for by in [0.2, 0.44]:
					K.cyl(grp, 0.055, 0.055, bp + Vector3(0, by, 0), dark, Vector3.ZERO, 10,
						-1.0, false)

		_island_bin(grp, Vector3(cx + 1.0, WALK_Y + 0.18, 9.0))
		_squeegee_bucket(grp, Vector3(cx - 1.0, WALK_Y + 0.18, 9.0))

		# 前场油渍：岛台旁边两块。比地坪只深一档，太黑会像两个坑。
		for st in [Vector3(cx - 0.62, 0.0, 7.95), Vector3(cx + 0.72, 0.0, 9.98)]:
			K.cyl(g, 0.24, 0.004, st + Vector3(0, WALK_Y + 0.006, 0), stain,
				Vector3.ZERO, 12, -1.0, false)


func _island_bin(parent: Node3D, pos: Vector3) -> void:
	var shell := K.toon(Color("#2f3b37"), {"shade": 0.55, "rim": 0.22, "line": 0.005})
	var lid := K.toon(Color("#1f2825"), {"shade": 0.6, "line": 0.004})
	var slot := K.toon(Color("#0e1114"), {"shade": 0.9, "line": 0.0})
	K.box(parent, Vector3(0.3, 0.56, 0.34), pos + Vector3(0, 0.28, 0), shell)
	K.box(parent, Vector3(0.33, 0.06, 0.37), pos + Vector3(0, 0.59, 0), lid)
	K.box(parent, Vector3(0.18, 0.12, 0.02), pos + Vector3(0, 0.42, 0.175), slot,
		Vector3.ZERO, false)
	K.label(parent, "CANS", pos + Vector3(0, 0.3, 0.181), 0.035, Color("#c7c2b6"))


func _squeegee_bucket(parent: Node3D, pos: Vector3) -> void:
	var blue := K.toon(Color("#3c6f8f"), {"shade": 0.55, "rim": 0.3, "line": 0.005})
	var dark := K.toon(Color("#15181c"), {"shade": 0.7, "line": 0.003})
	var wood := K.toon(Color("#6b4b2e"), {"shade": 0.55, "rim": 0.18, "line": 0.004})
	K.cyl(parent, 0.16, 0.34, pos + Vector3(0, 0.17, 0), blue, Vector3.ZERO, 14)
	K.cyl(parent, 0.145, 0.012, pos + Vector3(0, 0.336, 0), dark, Vector3.ZERO, 14, -1.0, false)
	K.torus(parent, 0.13, 0.155, pos + Vector3(0, 0.345, 0), dark, Vector3.ZERO, false)
	# 刮水板斜插在桶里，手柄伸到桶外，轮廓一眼能认出来。
	K.strut(parent, pos + Vector3(0.04, 0.24, 0.02), pos + Vector3(0.19, 0.92, 0.06),
		0.014, wood, 6)
	K.box(parent, Vector3(0.28, 0.028, 0.04), pos + Vector3(0.2, 0.94, 0.06), dark,
		Vector3(0, 0, -8))


# ---------------------------------------------------------------- 小卖亭

func _build_kiosk(g: Node3D) -> void:
	var grp := K.group(g, "Kiosk")
	var wall := K.toon(Color("#cfc8b8"), {"shade": 0.56, "rim": 0.18, "line": 0.007})
	var dark := K.toon(Color("#2c3338"), {"shade": 0.58, "rim": 0.2, "line": 0.005})
	var green := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.006})
	var cream := K.toon(Color("#e8e0cf"), {"shade": 0.6, "rim": 0.15, "line": 0.005})
	var steel := K.toon(Color("#8e9399"), {"shade": 0.55, "rim": 0.3, "line": 0.005})
	var mat := K.toon(Color("#2b2f36"), {"shade": 0.8, "line": 0.0})

	var cx := (KIOSK_X0 + KIOSK_X1) * 0.5
	var cz := (KIOSK_Z0 + KIOSK_Z1) * 0.5
	K.box(grp, Vector3(KIOSK_X1 - KIOSK_X0, 3.14, KIOSK_Z1 - KIOSK_Z0),
		Vector3(cx, 0.16 + 1.57, cz), wall)
	K.box(grp, Vector3(KIOSK_X1 - KIOSK_X0 + 0.4, 0.22, KIOSK_Z1 - KIOSK_Z0 + 0.4),
		Vector3(cx, 3.41, cz), dark)

	# 墙裙与转角收边：四面都做。奶油墙直接落到地面上，夜里看不出体量。
	for spec in [
			{"p": Vector3(KIOSK_X1 + 0.015, 0.31, cz),
				"s": Vector3(0.03, 0.3, KIOSK_Z1 - KIOSK_Z0)},
			{"p": Vector3(KIOSK_X0 - 0.015, 0.31, cz),
				"s": Vector3(0.03, 0.3, KIOSK_Z1 - KIOSK_Z0)},
			{"p": Vector3(cx, 0.31, KIOSK_Z0 - 0.015),
				"s": Vector3(KIOSK_X1 - KIOSK_X0, 0.3, 0.03)},
			{"p": Vector3(cx, 0.31, KIOSK_Z1 + 0.015),
				"s": Vector3(KIOSK_X1 - KIOSK_X0, 0.3, 0.03)}]:
		K.box(grp, spec["s"], spec["p"], green, Vector3.ZERO, false)
	for spec in [
			Vector3(KIOSK_X1 + 0.005, 1.73, KIOSK_Z0 + 0.03),
			Vector3(KIOSK_X1 + 0.005, 1.73, KIOSK_Z1 - 0.03),
			Vector3(KIOSK_X0 - 0.005, 1.73, KIOSK_Z0 + 0.03),
			Vector3(KIOSK_X0 - 0.005, 1.73, KIOSK_Z1 - 0.03)]:
		K.box(grp, Vector3(0.05, 3.14, 0.06), spec, green, Vector3.ZERO, false)

	# 东面三开间：柜台大窗 / 玻璃门 / 小窗。玩家从加油机那边走过来，先看到这一面。
	var ex := KIOSK_X1
	_kiosk_window(grp, Vector3(ex, 0.0, 10.29), 0.0, 2.94, 1.3, 0.92, true)
	_kiosk_window(grp, Vector3(ex, 0.0, 7.06), 0.0, 0.92, 1.3, 0.92, false)
	_kiosk_window(grp, Vector3(4.6, 0.0, KIOSK_Z0), 90.0, 2.56, 1.2, 1.0, true)

	# 门：暖光玻璃 + 深色框 + 下部踢脚板。仍然只是画上去的，碰撞整块亭子。
	var dz := 8.15
	for z in [7.7, 8.6]:
		K.box(grp, Vector3(0.08, 2.12, 0.07), Vector3(ex + 0.04, 1.23, z), dark)
	K.box(grp, Vector3(0.08, 0.09, 1.0), Vector3(ex + 0.04, 2.26, dz), dark)
	K.box(grp, Vector3(0.06, 0.03, 0.96), Vector3(ex + 0.04, 0.175, dz), dark,
		Vector3.ZERO, false)
	K.box(grp, Vector3(0.03, 1.46, 0.72), Vector3(ex + 0.005, 1.5, dz),
		K.glow(Color("#ffdca6"), 0.38), Vector3.ZERO, false)
	K.box(grp, Vector3(0.05, 0.06, 0.78), Vector3(ex + 0.025, 0.78, dz), dark,
		Vector3.ZERO, false)
	K.box(grp, Vector3(0.05, 0.05, 0.78), Vector3(ex + 0.025, 1.05, dz), dark,
		Vector3.ZERO, false)
	K.box(grp, Vector3(0.06, 0.36, 0.8), Vector3(ex + 0.025, 0.38, dz), green)
	K.strut(grp, Vector3(ex + 0.09, 1.0, 8.43), Vector3(ex + 0.09, 1.34, 8.43),
		0.018, steel, 8)
	for hy in [1.02, 1.32]:
		K.box(grp, Vector3(0.05, 0.03, 0.05), Vector3(ex + 0.065, hy, 8.43), steel,
			Vector3.ZERO, false)
	K.strut(grp, Vector3(ex + 0.01, 2.2, 8.02), Vector3(ex + 0.08, 2.12, 8.24),
		0.012, dark, 5, false)
	# 门垫：加一圈包边和横向胶条，别是一块纯黑地板
	K.box(grp, Vector3(0.82, 0.012, 1.0), Vector3(7.35, WALK_Y + 0.006, dz), mat,
		Vector3.ZERO, false)
	for i in 5:
		K.box(grp, Vector3(0.02, 0.014, 0.96), Vector3(7.0 + i * 0.17, WALK_Y + 0.014, dz),
			K.toon(Color("#3a3f47"), {"line": 0.0}), Vector3.ZERO, false)

	# 门楣：OPEN 24H（深绿底板 + 发光面）
	K.box(grp, Vector3(0.05, 0.34, 1.0), Vector3(ex + 0.025, 2.53, dz), green)
	K.box(grp, Vector3(0.02, 0.26, 0.9), Vector3(ex + 0.06, 2.53, dz),
		K.glow(Color("#ffcf8a"), 1.3), Vector3.ZERO, false)
	K.label(grp, "OPEN 24H", Vector3(ex + 0.075, 2.53, dz), 0.13, Color("#2b2418"),
		Vector3(0, 90, 0), 0)

	# 店招：东面 + 北面（北面朝国道，主要给进站的人看）。
	# 先做灯箱壳，再把奶油面板凸出来，侧面看才不是一块贴纸。
	K.box(grp, Vector3(0.1, 0.56, 3.8), Vector3(ex + 0.05, 3.06, 9.6), green)
	K.box(grp, Vector3(0.02, 0.42, 3.5), Vector3(ex + 0.11, 3.08, 9.6),
		K.glow(Color("#fff0d2"), 0.62), Vector3.ZERO, false)
	K.label(grp, "HOSHIMI", Vector3(ex + 0.125, 3.14, 9.6), 0.24, Color("#1d3a33"),
		Vector3(0, 90, 0), 0)
	K.label(grp, "SERVICE STATION", Vector3(ex + 0.125, 2.99, 9.6), 0.075,
		Color("#2d4a41"), Vector3(0, 90, 0), 0)

	var nz := KIOSK_Z0 - 0.05
	K.box(grp, Vector3(3.5, 0.62, 0.1), Vector3(4.6, 3.02, nz), green)
	K.box(grp, Vector3(3.2, 0.44, 0.02), Vector3(4.6, 3.02, nz - 0.06),
		K.glow(Color("#fff0d2"), 0.55), Vector3.ZERO, false)
	K.label(grp, "HOSHIMI MART", Vector3(4.6, 3.02, nz - 0.075), 0.22, Color("#1d3a33"),
		Vector3(0, 180, 0), 0)

	# 东面雨棚：悬挑 1.3m，雨落在上面，柜台前能站干地方。
	# 补三根斜拉杆和底部肋条，悬挑板才有支撑关系。
	K.box(grp, Vector3(1.35, 0.08, 4.9), Vector3(7.6, 2.86, 9.5), green)
	for z in [7.4, 8.4, 9.5, 10.6, 11.6]:
		K.box(grp, Vector3(1.24, 0.05, 0.06), Vector3(7.58, 2.8, z),
			K.toon(Color("#172d28"), {"shade": 0.6, "line": 0.0}), Vector3.ZERO, false)
	# 只留两端两根斜拉杆。中间那根会从 HOSHIMI 字上穿过去，看着像一根乱棍。
	for z in [7.3, 11.7]:
		K.strut(grp, Vector3(6.93, 2.46, z), Vector3(8.18, 2.82, z), 0.016, dark, 6, false)
	K.box(grp, Vector3(0.04, 0.07, 4.9), Vector3(8.26, 2.84, 9.5),
		K.glow(Color("#ffcf8a"), 0.8), Vector3.ZERO, false)
	# 棚下筒灯
	for z in [8.0, 11.0]:
		K.cyl(grp, 0.07, 0.04, Vector3(7.55, 2.8, z), dark, Vector3.ZERO, 12, -1.0, false)
		K.cyl(grp, 0.055, 0.012, Vector3(7.55, 2.775, z),
			K.glow(Color("#ffe0b0"), 1.15), Vector3.ZERO, 12, -1.0, false)
	# 主壁灯：灯罩 + 灯泡 + 柔光
	K.cyl(grp, 0.09, 0.04, Vector3(7.25, 2.79, 9.5), dark, Vector3.ZERO, 12, -1.0, false)
	K.sphere(grp, 0.07, Vector3(7.25, 2.72, 9.5), K.glow(Color("#ffd9a2"), 2.2),
		Vector3.ZERO, 10, 1.0, false)
	K.sphere(grp, 0.3, Vector3(7.25, 2.7, 9.5), K.soft(Color("#ffbf7a"), 0.36, 1.8),
		Vector3.ZERO, 12, 0.9, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#ffc88e")
	lamp.light_energy = 0.8
	lamp.omni_range = 4.2
	lamp.position = Vector3(7.3, 2.45, 9.5)
	grp.add_child(lamp)

	# 屋面收边 + 检修口
	for spec in [
			{"p": Vector3(cx, 3.545, KIOSK_Z0 + 0.03), "s": Vector3(KIOSK_X1 - KIOSK_X0 + 0.1, 0.05, 0.06)},
			{"p": Vector3(cx, 3.545, KIOSK_Z1 - 0.03), "s": Vector3(KIOSK_X1 - KIOSK_X0 + 0.1, 0.05, 0.06)},
			{"p": Vector3(KIOSK_X0 + 0.03, 3.545, cz), "s": Vector3(0.06, 0.05, KIOSK_Z1 - KIOSK_Z0)},
			{"p": Vector3(KIOSK_X1 - 0.03, 3.545, cz), "s": Vector3(0.06, 0.05, KIOSK_Z1 - KIOSK_Z0)}]:
		K.box(grp, spec["s"], spec["p"], green, Vector3.ZERO, false)
	K.box(grp, Vector3(0.68, 0.1, 0.78), Vector3(5.85, 3.57, 8.7),
		K.toon(Color("#4a5056"), {"shade": 0.55, "rim": 0.2, "line": 0.005}))
	K.box(grp, Vector3(0.5, 0.02, 0.06), Vector3(5.85, 3.63, 8.7), steel,
		Vector3.ZERO, false)

	# 屋顶空调 / 排气管
	for spec in [
			{"p": Vector3(3.6, 3.78, 8.0), "s": Vector3(0.9, 0.5, 0.8)},
			{"p": Vector3(5.6, 3.78, 11.0), "s": Vector3(0.8, 0.45, 0.75)}]:
		K.box(grp, spec["s"], spec["p"], K.toon(Color("#777c82"), {"shade": 0.55, "rim": 0.25, "line": 0.005}))
		K.cyl(grp, 0.18, 0.03, spec["p"] + Vector3(0, 0.26, 0),
			K.toon(Color("#34393f"), {"line": 0.0}), Vector3.ZERO, 12)
		for grille in [-0.18, 0.0, 0.18]:
			K.box(grp, Vector3(0.02, 0.3, float(spec["s"].z) * 0.7),
				spec["p"] + Vector3(float(spec["s"].x) * 0.5 + 0.01, -0.02, grille),
				K.toon(Color("#5f646a"), {"line": 0.0}), Vector3.ZERO, false)
	K.cyl(grp, 0.05, 1.2, Vector3(2.5, 3.8, 7.0), K.toon(Color("#6f747a"), {"line": 0.004}), Vector3.ZERO, 8)
	K.cyl(grp, 0.07, 0.12, Vector3(2.5, 4.45, 7.0), K.toon(Color("#4a4f55"), {"line": 0.0}), Vector3.ZERO, 8)

	# 东墙落水管：从屋面一直落到前场，再折出去。
	var dpx := KIOSK_X1 + 0.055
	var dpz := KIOSK_Z1 - 0.12
	K.cyl(grp, 0.045, 3.1, Vector3(dpx, 1.85, dpz), green, Vector3.ZERO, 8, -1.0, false)
	K.strut(grp, Vector3(dpx, 0.32, dpz), Vector3(dpx + 0.24, 0.2, dpz), 0.045, green, 8, false)
	K.box(grp, Vector3(0.3, 0.035, 0.3), Vector3(dpx + 0.28, 0.178, dpz),
		K.toon(Color("#494d53"), {"shade": 0.65, "line": 0.004}), Vector3.ZERO, false)
	for y in [1.2, 2.4, 3.3]:
		K.box(grp, Vector3(0.1, 0.04, 0.1), Vector3(KIOSK_X1 + 0.02, y, dpz), green,
			Vector3.ZERO, false)

	# 北墙电表箱 + 下引管
	var ub := K.group(grp, "Utility", Vector3(2.75, 1.55, KIOSK_Z0))
	K.box(ub, Vector3(0.42, 0.5, 0.14), Vector3.ZERO, steel)
	K.box(ub, Vector3(0.34, 0.42, 0.02), Vector3(0, 0, -0.08), dark,
		Vector3.ZERO, false)
	K.cyl(ub, 0.045, 0.04, Vector3(0, 0.04, -0.095),
		K.toon(Color("#1b1f24"), {"line": 0.0}), Vector3(90, 0, 0), 10, -1.0, false)
	K.box(ub, Vector3(0.06, 0.9, 0.05), Vector3(0.12, -0.7, -0.03), steel,
		Vector3.ZERO, false)

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


## 小卖亭的一扇窗。局部 +X 是墙外法线，窗户宽度沿局部 Z。
## 所有窗共用同一套框、玻璃、窗台和货架剪影，免得三扇窗各长一套。
func _kiosk_window(parent: Node3D, at: Vector3, rot_y: float, width: float, height: float,
		y0: float, counter: bool) -> void:
	var w := K.group(parent, "Window", at, Vector3(0, rot_y, 0))
	var glow := K.glow(Color("#e8b26f"), 0.5)
	var frame := K.toon(Color("#2c3338"), {"shade": 0.6, "rim": 0.2, "line": 0.004})
	var silhouette := K.toon(Color("#4a3a29"), {"shade": 0.9, "line": 0.003})
	var goods := [Color("#6b5a3f"), Color("#4a5c50"), Color("#6a4b45"), Color("#4c5360")]
	var cy := y0 + height * 0.5

	K.box(w, Vector3(0.035, height, width), Vector3(0.005, cy, 0), glow, Vector3.ZERO, false)
	# 窗框：上下横档 + 两侧竖档 + 中竖梃
	K.box(w, Vector3(0.07, 0.1, width + 0.14), Vector3(0.04, y0 + height + 0.05, 0), frame)
	K.box(w, Vector3(0.07, 0.1, width + 0.14), Vector3(0.04, y0 - 0.05, 0), frame)
	for sz in [-1.0, 1.0]:
		K.box(w, Vector3(0.07, height + 0.2, 0.09),
			Vector3(0.04, cy, sz * (width * 0.5 + 0.045)), frame)
	K.box(w, Vector3(0.065, height, 0.055), Vector3(0.04, cy, 0), frame)
	# 很淡的一层玻璃反射，不能挡住里面的暖光
	K.quad(w, Vector2(width - 0.06, height - 0.06), Vector3(0.075, cy, 0),
		K.glass(Color(0.45, 0.58, 0.68, 0.1), 0.22), Vector3(0, 90, 0), false)
	# 窗台 + 支架
	K.box(w, Vector3(0.18, 0.06, width + 0.18), Vector3(0.09, y0 - 0.13, 0),
		K.toon(Color("#b9b2a2"), {"shade": 0.65, "rim": 0.15, "line": 0.004}))
	for bz in [-width * 0.33, 0.0, width * 0.33]:
		K.box(w, Vector3(0.14, 0.05, 0.05), Vector3(0.07, y0 - 0.18, bz), frame,
			Vector3.ZERO, false)

	# 室内剪影：柜台 / 收银机 / 货架 / 商品。没有这些东西，窗就只是一块亮板。
	if counter:
		K.box(w, Vector3(0.02, 0.16, width - 0.16), Vector3(0.026, y0 + 0.1, 0), silhouette,
			Vector3.ZERO, false)
		K.box(w, Vector3(0.02, 0.26, 0.34), Vector3(0.026, y0 + 0.31, -width * 0.3),
			silhouette, Vector3.ZERO, false)
		K.box(w, Vector3(0.02, 0.15, 0.32), Vector3(0.031, y0 + 0.5, -width * 0.3),
			K.toon(Color("#20262b"), {"line": 0.0}), Vector3.ZERO, false)
		K.box(w, Vector3(0.008, 0.08, 0.18), Vector3(0.035, y0 + 0.5, -width * 0.3),
			K.glow(Color("#9fd8b8"), 0.5), Vector3.ZERO, false)
	for shelf_y in [y0 + height * 0.48, y0 + height * 0.74]:
		K.box(w, Vector3(0.02, 0.025, width - 0.16), Vector3(0.027, shelf_y, 0), silhouette,
			Vector3.ZERO, false)
		var count := maxi(2, int(width / 0.34))
		for i in count:
			var gz := -width * 0.5 + 0.18 + i * (width - 0.36) / float(count - 1)
			var gc: Color = goods[(i + int(shelf_y * 10.0)) % goods.size()]
			K.box(w, Vector3(0.02, 0.1 + 0.03 * (i % 3), 0.09),
				Vector3(0.03, shelf_y + 0.065, gz),
				K.toon(gc, {"shade": 0.85, "line": 0.0}), Vector3.ZERO, false)


# ---------------------------------------------------------------- 价格塔与路牌

func _build_signage(g: Node3D) -> void:
	var grp := K.group(g, "Signage")
	var green := K.toon(Color("#1d3a33"), {"shade": 0.5, "rim": 0.22, "line": 0.007})
	var cream := K.toon(Color("#ddd2b6"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	var steel := K.toon(Color("#8e9399"), {"shade": 0.55, "rim": 0.3, "line": 0.006})
	var dark := K.toon(Color("#2a2f35"), {"shade": 0.6, "line": 0.005})

	# 价格塔：放在前场东北角，从国道和商店街方向都能看见。
	# 底座 / 立柱 / 品牌灯箱 / 价格灯箱分成四段，接缝处留深色线，
	# 老远看也能读成一根「塔」，而不是两块贴在一起的板。
	var px := 26.4
	var pz := 5.2
	var brand_top := WALK_Y + 4.62
	K.box(grp, Vector3(1.24, 0.12, 0.9), Vector3(px, WALK_Y + 0.06, pz),
		K.toon(Color("#5b5f66"), {"shade": 0.6, "rim": 0.18, "line": 0.005}))
	K.box(grp, Vector3(1.0, 0.32, 0.72), Vector3(px, WALK_Y + 0.28, pz), dark)
	K.box(grp, Vector3(0.32, 4.26, 0.32), Vector3(px, WALK_Y + 2.41, pz), steel)
	for bx in [-0.42, 0.42]:
		for bz in [-0.28, 0.28]:
			K.cyl(grp, 0.03, 0.02, Vector3(px + bx, WALK_Y + 0.45, pz + bz),
				K.toon(Color("#c8ccd1"), {"shade": 0.5, "rim": 0.4, "line": 0.0}),
				Vector3.ZERO, 8, -1.0, false)

	# 品牌灯箱
	K.box(grp, Vector3(0.52, 1.4, 2.15), Vector3(px, WALK_Y + 3.92, pz), green)
	K.box(grp, Vector3(0.54, 0.06, 2.2), Vector3(px, brand_top, pz), cream, Vector3.ZERO, false)
	K.box(grp, Vector3(0.54, 0.05, 2.2), Vector3(px, WALK_Y + 3.26, pz), cream, Vector3.ZERO, false)
	K.box(grp, Vector3(0.4, 0.43, 1.24), Vector3(px, WALK_Y + 3.03, pz), green)
	for face in [-1, 1]:
		var fx: float = px + face * 0.265
		var rot := Vector3(0, 90 if face > 0 else -90, 0)
		K.label(grp, "HOSHIMI", Vector3(fx, WALK_Y + 4.26, pz), 0.34, Color("#fff0d2"), rot, 0)
		K.label(grp, "SERVICE STATION", Vector3(fx, WALK_Y + 3.96, pz), 0.13, Color("#d7c8a8"), rot, 0)
		K.label(grp, "SELF  ·  24H", Vector3(fx, WALK_Y + 3.69, pz), 0.13, Color("#ffcf8a"), rot, 0)

	# 价格灯箱：深色壳 + 奶油发光面 + 深绿表头，三行之间加分隔线。
	K.box(grp, Vector3(0.54, 1.34, 2.02), Vector3(px, WALK_Y + 2.02, pz), dark)
	for face in [-1, 1]:
		var fx2: float = px + face * 0.28
		var rot2 := Vector3(0, 90 if face > 0 else -90, 0)
		K.box(grp, Vector3(0.02, 1.14, 1.86), Vector3(fx2, WALK_Y + 2.0, pz),
			K.glow(Color("#f6efdc"), 0.42), Vector3.ZERO, false)
		K.box(grp, Vector3(0.56, 0.22, 1.9), Vector3(px, WALK_Y + 2.88, pz), green)
		K.label(grp, "FUEL PRICE", Vector3(fx2 + face * 0.005, WALK_Y + 2.88, pz),
			0.13, Color("#e8e0cf"), rot2, 0)
		# 油品色点 + 三行价格
		for row in [
				{"y": 2.5, "c": Color("#b84338"), "t": "REGULAR    ¥172"},
				{"y": 2.16, "c": Color("#c9a640"), "t": "HIGH-OCT   ¥180"},
				{"y": 1.82, "c": Color("#42975f"), "t": "DIESEL     ¥168"}]:
			var ry: float = row["y"]
			var rc: Color = row["c"]
			var rt: String = row["t"]
			K.box(grp, Vector3(0.012, 0.07, 0.07), Vector3(fx2 + face * 0.012, WALK_Y + ry, pz - 0.78),
				K.toon(rc, {"shade": 0.55, "rim": 0.2, "line": 0.0}), Vector3.ZERO, false)
			K.label(grp, rt, Vector3(fx2 + face * 0.015, WALK_Y + ry, pz + 0.02),
				0.17, Color("#26332d"), rot2, 0)
			if ry > 1.82:
				K.box(grp, Vector3(0.008, 0.008, 1.72),
					Vector3(fx2 + face * 0.012, WALK_Y + ry - 0.17, pz),
					K.toon(Color("#b9b3a2"), {"line": 0.0}), Vector3.ZERO, false)
		K.label_cjk(grp, "税込  /  1L", Vector3(fx2 + face * 0.015, WALK_Y + 1.67, pz), 0.08,
			Color("#5b6a60"), rot2, 0)
	# 塔顶和品牌箱底部各一条暖光，夜里把轮廓勾出来
	K.box(grp, Vector3(0.58, 0.08, 2.21), Vector3(px, WALK_Y + 4.66, pz), dark)
	K.box(grp, Vector3(0.6, 0.025, 2.23), Vector3(px, WALK_Y + 4.61, pz),
		K.glow(Color("#ffcf8a"), 1.0), Vector3.ZERO, false)
	K.box(grp, Vector3(0.54, 0.025, 2.17), Vector3(px, WALK_Y + 3.24, pz),
		K.glow(Color("#ffcf8a"), 0.8), Vector3.ZERO, false)

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
	# 牌背也要有字：出生点看到的是背面，空白绿板会占掉半个画面。
	var sx := 28.75
	var sz := -0.2
	K.cyl(grp, 0.09, 0.12, Vector3(sx, WALK_Y + 0.06, sz), dark, Vector3.ZERO, 10, -1.0, false)
	K.cyl(grp, 0.045, 2.6, Vector3(sx, WALK_Y + 1.3, sz), steel, Vector3.ZERO, 8)
	K.box(grp, Vector3(0.09, 0.78, 1.55), Vector3(sx, WALK_Y + 2.18, sz), green)
	K.box(grp, Vector3(0.1, 0.05, 1.63), Vector3(sx, WALK_Y + 2.59, sz), dark, Vector3.ZERO, false)
	K.box(grp, Vector3(0.1, 0.05, 1.63), Vector3(sx, WALK_Y + 1.77, sz), dark, Vector3.ZERO, false)
	for pz2 in [-0.98, 0.58]:
		K.box(grp, Vector3(0.1, 0.78, 0.04), Vector3(sx, WALK_Y + 2.18, pz2), dark,
			Vector3.ZERO, false)
	# 正面（朝西）
	K.label_cjk(grp, "星見町商店街", Vector3(sx - 0.05, WALK_Y + 2.3, sz), 0.15,
		Color("#f3dfb4"), Vector3(0, -90, 0))
	K.label(grp, "HOSHIMI SHOTENGAI", Vector3(sx - 0.05, WALK_Y + 2.1, sz), 0.065,
		Color("#d7c8a8"), Vector3(0, -90, 0))
	K.label(grp, "EAST  ·  300m", Vector3(sx - 0.05, WALK_Y + 1.97, sz), 0.055,
		Color("#9fb0a2"), Vector3(0, -90, 0))
	# 背面（朝东，出生点方向）
	K.label(grp, "HOSHIMI SS", Vector3(sx + 0.05, WALK_Y + 2.3, sz), 0.13,
		Color("#f3dfb4"), Vector3(0, 90, 0))
	K.label_cjk(grp, "国道 17 号", Vector3(sx + 0.05, WALK_Y + 2.13, sz), 0.075,
		Color("#d7c8a8"), Vector3(0, 90, 0))
	K.label(grp, "SELF  ·  24H", Vector3(sx + 0.05, WALK_Y + 1.99, sz), 0.055,
		Color("#9fb0a2"), Vector3(0, 90, 0))
	# 柱脚反光贴
	K.box(grp, Vector3(0.06, 0.18, 0.06), Vector3(sx, WALK_Y + 1.15, sz),
		K.toon(Color("#d8b95a"), {"shade": 0.9, "line": 0.0}), Vector3.ZERO, false)
	K.sphere(grp, 0.05, Vector3(sx, WALK_Y + 2.66, sz), K.glow(Color("#ffd9a2"), 2.0),
		Vector3.ZERO, 8, 1.0, false)
	K.strut(grp, Vector3(sx, WALK_Y + 2.56, sz), Vector3(sx, WALK_Y + 2.66, sz), 0.018,
		steel, 6, false)
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
	# 车尾的补货纸箱必须落地。之前只有一只 y=1.62 的箱子吊在半空，
	# 没有尾门托着它，近看就是一个浮着的盒子。
	var box_mat := K.toon(Color("#8a6d22"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	var tape := K.toon(Color("#b9a06a"), {"line": 0.0})
	for spec in [
			{"p": Vector3(1.05, WALK_Y + 0.16, 4.3), "r": -9.0, "s": Vector3(0.44, 0.32, 0.36)},
			{"p": Vector3(1.5, WALK_Y + 0.14, 4.4), "r": 14.0, "s": Vector3(0.38, 0.28, 0.32)},
			{"p": Vector3(1.16, WALK_Y + 0.44, 4.34), "r": 4.0, "s": Vector3(0.36, 0.24, 0.3)}]:
		var p: Vector3 = spec["p"]
		var s: Vector3 = spec["s"]
		var ry: float = spec["r"]
		K.box(grp, s, p, box_mat, Vector3(0, ry, 0))
		K.box(grp, Vector3(s.x * 1.02, 0.012, 0.055), p + Vector3(0, s.y * 0.5, 0),
			tape, Vector3(0, ry, 0), false)

	# 进出车道两边的锥桶
	for p in [Vector3(13.9, WALK_Y, 4.7), Vector3(24.7, WALK_Y, 4.7)]:
		_cone(grp, p)

	# 贩卖机：挂在小卖亭雨棚下，面朝东
	Props.vending(grp, Vector3(7.45, WALK_Y, 11.35), 90.0)
	# 机前的橡胶垫，不然冷光直接摊在水泥上，机器像浮着
	K.plane(grp, Vector2(0.72, 1.18), Vector3(8.1, WALK_Y + 0.006, 11.35),
		K.toon(Color("#20242a"), {"shade": 0.8, "line": 0.0}), Vector3.ZERO, false)
	for i in 4:
		K.box(grp, Vector3(0.64, 0.004, 0.03), Vector3(8.1, WALK_Y + 0.009, 10.95 + i * 0.26),
			K.toon(Color("#343a42"), {"line": 0.0}), Vector3.ZERO, false)

	# 打气机：底座 / 箱体 / 顶盖三段，正面仪表盘，侧面盘管，脚边挂气嘴。
	# 之前只有一个圆环加一根斜杆，远看像一台没画完的售货机。
	var air := K.group(grp, "AirPump", Vector3(7.45, WALK_Y, 6.75), Vector3(0, 90, 0))
	var shell := K.toon(Color("#3f6c8a"), {"shade": 0.55, "rim": 0.25, "line": 0.006})
	var dark := K.toon(Color("#232a31"), {"shade": 0.6, "line": 0.004})
	var chrome := K.toon(Color("#a9b0b7"), {"shade": 0.5, "rim": 0.4, "line": 0.003})
	var rubber := K.toon(Color("#191d22"), {"shade": 0.6, "rim": 0.2, "line": 0.003})
	K.box(air, Vector3(0.7, 0.06, 0.54), Vector3(0, 0.03, 0), dark)
	K.box(air, Vector3(0.62, 0.1, 0.44), Vector3(0, 0.11, 0), dark)
	K.box(air, Vector3(0.6, 0.76, 0.4), Vector3(0, 0.54, 0), shell)
	K.box(air, Vector3(0.64, 0.08, 0.44), Vector3(0, 0.96, 0), dark)
	K.box(air, Vector3(0.54, 0.03, 0.34), Vector3(0, 1.015, 0), shell, Vector3.ZERO, false)
	# 正面：内凹面板 / 表盘 / 指针 / 两颗按钮
	K.box(air, Vector3(0.44, 0.34, 0.02), Vector3(0, 0.5, 0.205), dark, Vector3.ZERO, false)
	K.cyl(air, 0.105, 0.024, Vector3(0, 0.55, 0.22), dark, Vector3(90, 0, 0), 18, -1, false)
	K.cyl(air, 0.09, 0.012, Vector3(0, 0.55, 0.236), K.glow(Color("#e8e3cf"), 0.2),
		Vector3(90, 0, 0), 18, -1, false)
	K.box(air, Vector3(0.008, 0.066, 0.005), Vector3(0.012, 0.575, 0.245),
		K.toon(Color("#a8322c"), {"line": 0.0}), Vector3(0, 0, -32), false)
	K.cyl(air, 0.013, 0.012, Vector3(0, 0.55, 0.245), chrome, Vector3(90, 0, 0), 8, -1, false)
	K.box(air, Vector3(0.006, 0.016, 0.004), Vector3(-0.052, 0.605, 0.244), dark,
		Vector3(0, 0, -28), false)
	K.box(air, Vector3(0.006, 0.016, 0.004), Vector3(0, 0.625, 0.244), dark, Vector3.ZERO, false)
	K.box(air, Vector3(0.006, 0.016, 0.004), Vector3(0.052, 0.605, 0.244), dark,
		Vector3(0, 0, 28), false)
	for bp in [-0.075, 0.0]:
		K.cyl(air, 0.022, 0.02, Vector3(bp, 0.37, 0.225), chrome, Vector3(90, 0, 0), 12, -1, false)
	K.box(air, Vector3(0.12, 0.02, 0.006), Vector3(0.095, 0.37, 0.222),
		K.glow(Color("#8bd7a6"), 0.6), Vector3.ZERO, false)
	# 侧面散热栅
	for vy in [0.26, 0.36, 0.46, 0.56, 0.66]:
		K.box(air, Vector3(0.012, 0.025, 0.28), Vector3(-0.303, vy, 0), dark,
			Vector3.ZERO, false)
	# 顶部灯箱
	K.box(air, Vector3(0.44, 0.2, 0.02), Vector3(0, 0.795, 0.205), dark, Vector3.ZERO, false)
	K.box(air, Vector3(0.38, 0.145, 0.012), Vector3(0, 0.795, 0.217),
		K.glow(Color("#dff5ff"), 1.2), Vector3.ZERO, false)
	K.label(air, "AIR", Vector3(0, 0.795, 0.228), 0.11, Color("#173040"))
	K.label(air, "FREE", Vector3(0, 0.32, 0.228), 0.035, Color("#9fd8b8"))
	# 侧面也要有字：从亭子正门走过来看到的是这一面，只有散热栅会像一台配电箱
	K.box(air, Vector3(0.012, 0.18, 0.5), Vector3(-0.303, 0.78, 0), dark, Vector3.ZERO, false)
	K.label(air, "AIR", Vector3(-0.312, 0.78, 0), 0.09, Color("#dfeef2"), Vector3(0, -90, 0))
	# 侧面软管卷盘 + 垂下来的气嘴
	K.torus(air, 0.13, 0.21, Vector3(0.36, 0.56, 0), rubber, Vector3(0, 0, 90))
	K.torus(air, 0.15, 0.195, Vector3(0.375, 0.56, 0),
		K.toon(Color("#2a3038"), {"line": 0.003}), Vector3(0, 0, 90))
	K.cyl(air, 0.055, 0.09, Vector3(0.36, 0.56, 0), chrome, Vector3(0, 0, 90), 12, -1, false)
	K.tube(air, PackedVector3Array([
		Vector3(0.36, 0.38, 0.02), Vector3(0.41, 0.24, 0.12),
		Vector3(0.34, 0.12, 0.2), Vector3(0.28, 0.1, 0.24)]), 0.022, rubber, 6)
	K.cyl(air, 0.032, 0.1, Vector3(0.27, 0.08, 0.25), chrome, Vector3.ZERO, 10, -1, false)
	K.box(air, Vector3(0.045, 0.05, 0.03), Vector3(0.27, 0.035, 0.25), chrome,
		Vector3.ZERO, false)

	# 打气机脚边摞着的两条旧胎
	var tire := K.toon(Color("#1b1e23"), {"shade": 0.6, "rim": 0.18, "line": 0.004})
	for i in 2:
		K.torus(grp, 0.17, 0.33, Vector3(7.24, WALK_Y + 0.08 + i * 0.15, 7.38), tire)

	# 灰水桶 / 拖把：细节，不挡人
	K.cyl(grp, 0.17, 0.34, Vector3(8.45, WALK_Y + 0.17, 12.55),
		K.toon(Color("#6f7377"), {"shade": 0.55, "rim": 0.25, "line": 0.005}), Vector3.ZERO, 12)
	K.strut(grp, Vector3(8.45, WALK_Y + 0.1, 12.55), Vector3(8.3, WALK_Y + 1.3, 12.6), 0.02,
		K.toon(Color("#4a3a28"), {"line": 0.0}), 6)


func _cone(parent: Node3D, base: Vector3) -> void:
	var orange := K.toon(Color("#c4582a"), {"shade": 0.6, "rim": 0.25, "line": 0.005})
	var white := K.toon(Color("#ddd6c6"), {"shade": 0.7, "line": 0.004})
	var rubber := K.toon(Color("#23262b"), {"shade": 0.7, "rim": 0.12, "line": 0.004})
	K.box(parent, Vector3(0.4, 0.05, 0.4), base + Vector3(0, 0.025, 0), rubber)
	K.box(parent, Vector3(0.34, 0.02, 0.34), base + Vector3(0, 0.06, 0), orange,
		Vector3.ZERO, false)
	K.cyl(parent, 0.145, 0.52, base + Vector3(0, 0.33, 0), orange, Vector3.ZERO, 12, 0.016)
	K.cyl(parent, 0.104, 0.1, base + Vector3(0, 0.32, 0), white, Vector3.ZERO, 12, 0.078)


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
	CollisionLayout.solid(g, Vector3(26.4, WALK_Y + 0.22, 5.2), Vector3(1.24, 0.44, 0.9))
	CollisionLayout.solid(g, Vector3(26.4, WALK_Y + 2.4, 5.2), Vector3(0.36, 4.8, 2.1))
	CollisionLayout.pillar(g, Vector3(28.75, WALK_Y + 1.3, -0.2), 0.06, 2.6)
	CollisionLayout.pillar(g, Vector3(24.6, WALK_Y + 2.05, -1.82), 0.07, 4.1)
	CollisionLayout.pillar(g, Vector3(5.2, WALK_Y + 2.05, -1.82), 0.07, 4.1)
	CollisionLayout.solid(g, Vector3(7.45, WALK_Y + 0.52, 6.75), Vector3(0.48, 1.04, 0.66))
	CollisionLayout.solid(g, Vector3(7.24, WALK_Y + 0.15, 7.38), Vector3(0.64, 0.3, 0.64))
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
		{"name": "gas_c_pumps", "free": Vector3(16.0, 2.7, 13.9),
			"look": Vector3(16.0, 1.85, 8.8), "fov": 62.0},
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
