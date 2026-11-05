extends RefCounted
## 冒险者公会（城镇西南角，x −140~−112、z 316~341）。
##
## 体量 28 × 25 m，一层 4.2 m，二层 3.6 m，屋脊 10.6 m。全木构 —— 没有石基座，
## 因为这是「小城镇的公会」而不是城堡的附属建筑；石材在城里已经由城墙和方石地面
## 占满了，公会再用石头会读成第二座城门。
##
## 内部按用户口述复现：
##   - 南墙正中开 4 m 双开木门，左右各留 14 m
##   - 进门左手一列 4 根木柱（不是 2×2 柱网）撑起二层主梁
##   - 北墙横置 12 m 长前台，两名接待站台后
##   - 门右侧两块独立的立式任务板
##   - 东墙中段 U 型折返楼梯，第一跑面朝大门
##
## 二楼**不做**：只铺楼梯口那一小块平台。抬头看到的是梁架 + 屋顶，
## 没有地板 —— 一眼就能看出「这里还没装修」，而不是「地板做丢了」。
##
## 做法沿用本工程风格：全部 GDScript 生成，不摆节点。和 city_wall 一样，
## kit 只给视觉，挡人的部分由 _solid 补 StaticBody3D。

const K := preload("res://scripts/kit.gd")

# ---------------------------------------------------------------- 摆放
#
# 内部所有坐标都是「局部坐标」（原来那坨 x −140~−112、z 316~341）。
# 城镇分区之后，公会应该在冒险者区、大门朝主街，和这套局部坐标差 90°。
#
# 与其把上百个绝对坐标手改一遍（必错），不如给整栋楼套一个父节点变换：
# build() 挂在带变换的节点下，_solid 的碰撞体也跟着走；
# 只有对外暴露的站位（CLERK_POS / BOARD_POS）要过一次 world() 换算。

static var _place := Transform3D.IDENTITY


## 把公会摆到世界坐标 center、绕 Y 轴转 yaw_rad。返回承载它的节点（作为 build 的 parent）。
static func place(parent: Node3D, center: Vector3, yaw_rad: float) -> Node3D:
	var local_center := Vector3((X0 + X1) * 0.5, 0.0, (Z0 + Z1) * 0.5)
	var basis := Basis(Vector3.UP, yaw_rad)
	var node := K.group(parent, "GuildPlacement")
	node.transform = Transform3D(basis, center - basis * local_center)
	_place = node.transform
	return node


## 公会局部坐标 → 世界坐标。
## 摆 NPC、注册交互点、判断「玩家是不是在大厅里」都必须走这里，
## 否则搬了公会，人还站在原地。
static func world(p: Vector3) -> Vector3:
	return _place * p


## 方向同样要过一遍变换：NPC 的朝向是局部方向（比如都朝 −Z），
## 公会转了 90°，人也得跟着转。
static func world_dir(d: Vector3) -> Vector3:
	var r := _place.basis * d
	return r.normalized()

# ---------------------------------------------------------------- 尺寸
#
# 这些常量同时是 grassland.gd 摆 NPC / 注册交互点的依据，
# 所以必须公开（无下划线），改尺寸时那边的站位会跟着走。

## 外墙外皮范围。和城镇地基对齐（x ±150、z 300~630）
const X0 := -140.0
const X1 := -112.0
const Z0 := 316.0
const Z1 := 341.0
const CX := -126.0
const CZ := 328.5
const W := 28.0
const D := 25.0
const WALL_T := 0.3

## 一层楼板面标高。楼梯 24 级 × 0.175 正好落在 4.2
const FL1 := 4.2
## 檐口高（二层墙顶）
const EAVE := 7.8
## 屋脊高。坡度 (10.6−7.8)/12.5 ≈ 12.6°，缓坡压檐，是水乡民居的比例，
## 不是哥特式教堂 —— 太高会压过 12 m 的城墙，破坏「城比屋大」的层级
const RIDGE := 10.6

const DOOR_W := 4.0
const DOOR_H := 3.0

## 柱列：进门左手一列 4 根
const COL_X := -132.0
const COL_R := 0.19
const COL_SPAN := 6.0
const COL_Z0 := 318.0

## 前台
const COUNTER_X0 := -137.0
const COUNTER_X1 := -125.0
const COUNTER_Z := 338.6
const COUNTER_H := 1.05
const COUNTER_DEPTH := 0.8

## 前台两位接待的站位（台后，面朝大门）
const CLERK_POS: Array[Vector3] = [
	Vector3(-134.6, 0.0, 339.6),
	Vector3(-128.4, 0.0, 339.6),
]

## 任务板：门右侧两块立架
const BOARD_POS: Array[Vector3] = [
	Vector3(-122.2, 0.0, 318.6),
	Vector3(-118.8, 0.0, 318.6),
]
const BOARD_RADIUS := 2.2

## 楼梯井。东墙内皮 x=−112.15，井壁留 0.15 贴住
const STAIR_X := -113.975
const STAIR_W := 3.35
const STAIR_Z0 := 324.8
const STAIR_Z1 := 329.6
## 每跑 12 级、级高 0.175、踏步 0.3
const STEP_N := 12
const STEP_H := 0.175
const STEP_T := 0.3
## 两跑之间的缝
const STAIR_GAP := 0.15

## 玩家可交互的门口位置（交互点注册用，不含在里面是因为门口在墙外）
const DOOR_POS := Vector3(CX, 0.0, Z0 - 1.0)

# ---------------------------------------------------------------- 前庭
#
# 门口这块地从「贴在广场上的一栋楼」变成「一栋有院子的楼」，全靠这三样：
# 一条越走越宽的梯形石板路、两侧带石砌围边的花池、门前两级石阶。
#
# 为什么是梯形（靠门窄、靠外宽）：玩家是从广场往回走、正对大门走过来的。
# 窄端收在门口，视线会被「收」进门里；宽端铺开在广场上，远远看就是一栋
# 有前庭的房子。反过来（门宽外窄）会读成「一条排水沟」。

## 前庭远端（离门最远的一端）
const COURT_Z0 := 307.4
## 石板路在门端的宽度。3.8 是被雨棚柱子夹住的：柱子站在 CX ± 2.6，
## 路在中段必须比 5.2 窄一点，柱子才落在池边而不是路面上
const PATH_NEAR_W := 3.8
## 石板路在远端的宽度
const PATH_FAR_W := 10.0
## 花池进深。2.2 m 是一个人站在池边、伸手够不到对面灌木的距离
const BED_DEPTH := 2.2
## 石砌基座高度。0.55 是「看得见的一道石脚」而不是「半层楼」——
## 再高就变成石砌一楼，和全木构的设定打架
const PLINTH_H := 0.55


static func build(parent: Node3D) -> void:
	# 木色分档：外墙旧木、柱梁深褐、地板中褐、内衬再暗一档。
	#
	# ---- 关于亮度的实测 ----
	#
	# 这个场景的 ambient 是照「明亮草原」调的：天空 radiance 约 0.7，乘
	# ambient_light_energy 0.85 之后还要再乘 PI，落到着色器里约 1.9 倍 albedo。
	# 也就是说 albedo 0.59 的木头上墙就是 1.1，直接过曝，tonemap 一压就成米白。
	#
	# ---- 关于色相（第二次调，2026-10-21）----
	#
	# 上一版是暖黄 #7a5c3c，压得住亮度但**饱和度太高**：一整面 28×7.8 m 的
	# 橙黄色平板，怎么看都是铁皮仓库。旧木的颜色不是「黄」，是「褪了色的灰褐」——
	# 木头里的木质素见光只会往灰里走，不会往黄里走。
	# 所以这次把色相往灰里拉（#6d5b47，饱和度从 0.51 降到 0.21），
	# 亮度基本不变。仓库感来自「饱和度 + 平整」，两个都得治，光调暗没用。
	var wood := K.toon(Color("#6f5643"), {"line": 0.010, "shade": 0.56})
	# 深色木件把 rim 从默认 0.15 收到 0.04。默认值在掠射角（台面、底座、
	# 地板的水平面）会把整片染成蓝紫 —— 那是边缘光在按几何角度算，不按轮廓。
	var wood_dark := K.toon(Color("#3d3125"), {"line": 0.012, "shade": 0.50, "rim": 0.04})
	var floor_mat := K.toon(Color("#57452f"), {"line": 0.010, "shade": 0.60, "rim": 0.0})
	# 屋顶暗部抬到 0.68：檐下从室内看是一大片纯黑三角，
	# 抬一档之后能看到是「木板的背面」而不是一个洞。
	# 屋顶比墙更灰更冷 —— 屋面经历风吹雨打，是最先褪成灰的地方
	var roof_mat := K.toon(Color("#5b5145"), {"line": 0.012, "shade": 0.68, "rim": 0.0})
	var counter_mat := K.toon(Color("#6f5636"), {"line": 0.010, "shade": 0.58, "rim": 0.04})
	# 石头：墙面用石和地面铺装是同一套灰，只差明度
	var stone := K.toon(Color("#7f7a6d"), {"line": 0.012, "shade": 0.50, "rim": 0.0})
	# 基座石更暗：贴地那一圈常年溅泥、淋雨，比上面的墙更脏更冷
	var plinth_mat := K.toon(Color("#5e5950"), {"line": 0.012, "shade": 0.48, "rim": 0.0})
	# 窗芯：不是玻璃，是「屋里没点灯」的黑。用近黑的暖灰，纯黑会像破洞
	var shade := K.toon(Color("#1a140e"), {"line": 0.0})
	# 内衬板：室内侧那层薄木板。室内没有直射光，只有 ambient + 暖灯，
	# 所以它比外墙再暗一档就够，不需要压到外墙那么狠
	var lining := K.toon(Color("#5b4329"), {"line": 0.008, "shade": 0.55, "rim": 0.0})
	# 室内看到的窗：外面亮、里面暗，所以这块是**亮**的（透进来的天光），
	# 和外墙上那块近黑的窗芯正好相反。同一扇窗两个面两个亮度，这才是对的
	var lining_win := K.toon(Color("#9fb8cc"), {"line": 0.0, "shade": 0.92, "rim": 0.0})

	var g := K.group(parent, "Guild")
	_floor(g, floor_mat, wood_dark)
	_plinth(g, plinth_mat, stone)
	_columns(g, wood_dark, stone)
	_frame(g, wood_dark)
	_walls(g, wood, wood_dark, shade, lining, lining_win)
	_steps(g, stone, plinth_mat)
	_door(g, wood_dark, wood)
	_roof(g, roof_mat, wood_dark, wood)
	_chimney(g, stone, wood_dark)
	_counter(g, counter_mat, wood_dark)
	_stairs(g, wood, wood_dark)
	_boards(g, wood, wood_dark)
	_court(g)
	_lights(g)


# ---------------------------------------------------------------- 地面

## 室内地板比外面的方石高 4 cm。差 4 cm 是为了避免 z-fighting，
## 不是为了台阶 —— 玩家走过去几乎无感，不需要额外做门槛。
static func _floor(g: Node3D, mat: Material, dark: Material) -> void:
	K.box(g, Vector3(W - WALL_T * 2.0, 0.04, D - WALL_T * 2.0 + 0.4),
		Vector3(CX, 0.02, CZ - 0.2), mat)
	# 地板缝：沿 Z 每 2 m 一道，比着色器便宜也更像实木铺装
	var n := 12
	for i in range(1, n):
		var x := X0 + WALL_T + (W - WALL_T * 2.0) * float(i) / float(n)
		K.box(g, Vector3(0.03, 0.012, D - WALL_T * 2.0 + 0.4),
			Vector3(x, 0.041, CZ - 0.2), dark, Vector3.ZERO, false)


# ---------------------------------------------------------------- 石砌墙脚

## 石砌墙脚。沿四面外墙贴一圈 0.55 m 高的石带，比墙面凸出 9 cm。
##
## 这是「仓库 → 老房子」最省事也最有效的一笔：铁皮仓库是墙直接落到水泥地坪上的，
## 而任何一座住过人的老木楼，墙脚都有一道石头护脚（防潮、防车马磕碰）。
## 有了这道暗色的横向石带，立面就从「一整块 7.8 m 高的板」变成
## 「0.55 m 石 + 7.25 m 木」，比例一分开，仓库感立刻没了。
##
## 南墙要和门洞错开，所以拆成左右两段。
static func _plinth(g: Node3D, mat: Material, cap: Material) -> void:
	var out := 0.09
	var t := WALL_T + out * 2.0
	var y := PLINTH_H * 0.5
	var front_len := W * 0.5 - DOOR_W * 0.5      # 12
	var front_cx := CX - (DOOR_W * 0.5 + front_len * 0.5)

	# 南墙：门洞两侧
	K.box(g, Vector3(front_len, PLINTH_H, t), Vector3(front_cx, y, Z0), mat)
	K.box(g, Vector3(front_len, PLINTH_H, t),
		Vector3(CX * 2.0 - front_cx, y, Z0), mat)
	# 北墙
	K.box(g, Vector3(W + out * 2.0, PLINTH_H, t), Vector3(CX, y, Z1), mat)
	# 东西墙：长度要扣掉已经铺过的南北两角，否则石带会在角上叠成一坨
	K.box(g, Vector3(t, PLINTH_H, D), Vector3(X0, y, CZ), mat)
	K.box(g, Vector3(t, PLINTH_H, D), Vector3(X1, y, CZ), mat)

	# 压顶：比石带再凸 3 cm 的一道窄檐，给墙脚一道水平阴影线
	var cw := 0.14
	K.box(g, Vector3(front_len, 0.07, t + cw), Vector3(front_cx, PLINTH_H + 0.035, Z0), cap)
	K.box(g, Vector3(front_len, 0.07, t + cw), Vector3(CX * 2.0 - front_cx, PLINTH_H + 0.035, Z0), cap)
	K.box(g, Vector3(W + out * 2.0 + cw, 0.07, t + cw), Vector3(CX, PLINTH_H + 0.035, Z1), cap)
	K.box(g, Vector3(t + cw, 0.07, D + cw), Vector3(X0, PLINTH_H + 0.035, CZ), cap)
	K.box(g, Vector3(t + cw, 0.07, D + cw), Vector3(X1, PLINTH_H + 0.035, CZ), cap)


# ---------------------------------------------------------------- 柱与梁架

## 4 根柱子 + 柱础 + 柱头托木。
## 一根柱子卖相好不好，八成看上下两头：光杆圆柱像钢管，
## 有收分（柱础宽、柱头托）才读得出「这是木头」。
static func _columns(g: Node3D, dark: Material, stone: Material) -> void:
	for i in 4:
		var z := COL_Z0 + COL_SPAN * float(i)
		K.box(g, Vector3(0.62, 0.22, 0.62), Vector3(COL_X, 0.11, z), stone)
		K.cyl(g, COL_R, FL1 - 0.04 - 0.22, Vector3(COL_X, 0.22 + (FL1 - 0.26) * 0.5, z),
			dark, Vector3.ZERO, 12)
		# 柱头托木：撑在梁底，比柱身宽一圈
		K.box(g, Vector3(0.5, 0.16, 0.5), Vector3(COL_X, FL1 - 0.12, z), dark)


## 梁架。二层不做楼板，所以这套梁是「唯一证明二楼存在」的东西，
## 尺寸要够粗、看得到，不然抬头只剩一片屋顶。
static func _frame(g: Node3D, dark: Material) -> void:
	var inner_w := W - WALL_T * 2.0
	var inner_d := D - WALL_T * 2.0

	# 主梁：沿 Z 一根，压在 4 根柱子上
	K.box(g, Vector3(0.36, 0.36, inner_d), Vector3(COL_X, FL1 - 0.18, CZ), dark)

	# 次梁：沿 X 横跨到两侧墙，间距与柱距一致
	for i in 4:
		var z := COL_Z0 + COL_SPAN * float(i)
		K.box(g, Vector3(inner_w, 0.3, 0.28), Vector3(CX, FL1 + 0.15, z), dark)

	# 圈梁：沿四面墙顶一圈，把次梁的端头收住
	K.box(g, Vector3(inner_w, 0.3, 0.26), Vector3(CX, FL1 + 0.15, Z0 + WALL_T * 0.5), dark)
	K.box(g, Vector3(inner_w, 0.3, 0.26), Vector3(CX, FL1 + 0.15, Z1 - WALL_T * 0.5), dark)
	K.box(g, Vector3(0.26, 0.3, inner_d), Vector3(X0 + WALL_T * 0.5, FL1 + 0.15, CZ), dark)
	K.box(g, Vector3(0.26, 0.3, inner_d), Vector3(X1 - WALL_T * 0.5, FL1 + 0.15, CZ), dark)

	# 二层檐枋：贴着檐口再收一道，让二层立面不空
	K.box(g, Vector3(inner_w, 0.24, 0.22), Vector3(CX, EAVE - 0.5, Z0 + WALL_T * 0.5), dark)
	K.box(g, Vector3(inner_w, 0.24, 0.22), Vector3(CX, EAVE - 0.5, Z1 - WALL_T * 0.5), dark)
	K.box(g, Vector3(0.22, 0.24, inner_d), Vector3(X0 + WALL_T * 0.5, EAVE - 0.5, CZ), dark)
	K.box(g, Vector3(0.22, 0.24, inner_d), Vector3(X1 - WALL_T * 0.5, EAVE - 0.5, CZ), dark)


# ---------------------------------------------------------------- 墙

## 四面木板墙，通高到檐口（7.8 m）。
##
## 南墙要留 4 m 门洞，所以拆成「左段 + 右段 + 门楣」三块；
## 其余三面整块铺，再贴壁柱和腰线把 25 m 长的白板子切开 ——
## 一面 25 m 没有任何竖线，中间那段在镜头里会糊成一片墙纸。
static func _walls(g: Node3D, mat: Material, dark: Material, shade: Material,
		lining: Material, lining_win: Material) -> void:
	var side_len := W - WALL_T * 2.0
	var front_len := (W * 0.5 - DOOR_W * 0.5)          # 12
	var front_cx := CX - (DOOR_W * 0.5 + front_len * 0.5)   # −134

	# ---- 南墙（拆三段）
	K.box(g, Vector3(front_len, EAVE, WALL_T), Vector3(front_cx, EAVE * 0.5, Z0 + WALL_T * 0.5), mat)
	K.box(g, Vector3(front_len, EAVE, WALL_T), Vector3(CX + (DOOR_W * 0.5 + front_len * 0.5), EAVE * 0.5, Z0 + WALL_T * 0.5), mat)
	K.box(g, Vector3(DOOR_W, EAVE - DOOR_H, WALL_T), Vector3(CX, DOOR_H + (EAVE - DOOR_H) * 0.5, Z0 + WALL_T * 0.5), mat)

	# ---- 北墙
	K.box(g, Vector3(side_len, EAVE, WALL_T), Vector3(CX, EAVE * 0.5, Z1 - WALL_T * 0.5), mat)

	# ---- 东西墙
	K.box(g, Vector3(WALL_T, EAVE, D - WALL_T * 2.0), Vector3(X0 + WALL_T * 0.5, EAVE * 0.5, CZ), mat)
	K.box(g, Vector3(WALL_T, EAVE, D - WALL_T * 2.0), Vector3(X1 - WALL_T * 0.5, EAVE * 0.5, CZ), mat)

	# ---- 壁柱与腰线
	_pilasters(g, mat, dark)

	# ---- 板缝与修补板（旧木的质感全在这两样上）
	_plank_seams(g, dark)
	_patches(g)

	# ---- 内衬板 + 窗（外墙窗朝外、内衬窗朝内）
	_lining(g, lining)
	_windows(g, dark, shade)
	_inner_windows(g, dark, lining_win)


## 竖向板缝。四面外墙每 1.1 m 一道，从石脚上沿直通檐口。
##
## 没有这道缝，一面 28 × 7.25 m 的墙就是一块钢板上漆 —— 这是「仓库」最根本的来源。
## 木板房是由一块块竖板拼的，板缝是最便宜、也最不会看错的「木构」信号。
##
## 缝用 0.028 m 宽、比墙面深一点的条子，**不描边**（line = 0）：
## 1.1 m 一道 × 四面的密度下，每条都带描边会糊成一片黑栅栏。
static func _plank_seams(g: Node3D, seam: Material) -> void:
	var step := 1.1
	var h := EAVE - PLINTH_H
	var y := PLINTH_H + h * 0.5
	var t := 0.02

	# 南 / 北墙：沿 X 排。南墙跳过门洞
	var x := X0 + 0.6
	while x < X1 - 0.4:
		if absf(x - CX) > DOOR_W * 0.5 + 0.35:
			K.box(g, Vector3(0.028, h, t), Vector3(x, y, Z0 - 0.008), seam, Vector3.ZERO, false)
			K.box(g, Vector3(0.028, h, t), Vector3(x, y, Z1 + 0.008), seam, Vector3.ZERO, false)
		x += step

	# 东 / 西墙：沿 Z 排
	var z := Z0 + 0.6
	while z < Z1 - 0.4:
		K.box(g, Vector3(t, h, 0.028), Vector3(X0 - 0.008, y, z), seam, Vector3.ZERO, false)
		K.box(g, Vector3(t, h, 0.028), Vector3(X1 + 0.008, y, z), seam, Vector3.ZERO, false)
		z += step


## 补钉的旧木板。几块颜色深浅不一、微微歪着的板子钉在立面上。
##
## 这是「用了很多年」的直接证据：新盖的房子立面是齐的，
## 只有修过、补过、换过板的房子才会有一块块对不上的板子。
## 位置全部避开门窗（南墙窗在 x −137/−131/−121/−115，y 1.6~3.4 与 5.3~7.1）。
static func _patches(g: Node3D) -> void:
	# 比墙浅、比墙灰：换上去的新板还没来得及晒旧，色相也不同
	var light := K.toon(Color("#7d7059"), {"line": 0.008, "shade": 0.54, "rim": 0.0})
	var mid := K.toon(Color("#5e4d38"), {"line": 0.008, "shade": 0.52, "rim": 0.0})

	# 南墙：(x, y, 宽, 高, 倾斜角, 材质)
	for s in [
		[-135.7, 1.12, 1.70, 0.44, 2.5, 0],   # 石脚与一层窗之间那一条空墙
		[-124.4, 4.35, 2.30, 0.52, -1.8, 1],  # 腰线以下
		[-118.4, 1.02, 1.30, 0.38, 4.0, 1],
		[-139.1, 4.60, 0.95, 1.05, 0.0, 0],   # 西角一块竖补丁
		[-128.9, 6.95, 1.40, 0.40, 1.2, 0],   # 二层窗顶
	]:
		var px: float = s[0]
		var py: float = s[1]
		var pw: float = s[2]
		var ph: float = s[3]
		var ang: float = s[4]
		var m: Material = light if int(s[5]) == 0 else mid
		K.box(g, Vector3(pw, ph, 0.06), Vector3(px, py, Z0 - 0.012), m,
			Vector3(0.0, 0.0, ang), false)

	# 东墙：朝城镇中心那面，进城的路上先看到的就是它
	for s in [
		[320.2, 1.25, 1.55, 0.46, -2.0, 0],
		[334.6, 4.50, 2.10, 0.48, 1.5, 1],
		[337.8, 6.80, 1.20, 0.90, 0.0, 0],
	]:
		var pz: float = s[0]
		var py: float = s[1]
		var pw: float = s[2]
		var ph: float = s[3]
		var ang: float = s[4]
		var m: Material = light if int(s[5]) == 0 else mid
		K.box(g, Vector3(0.06, ph, pw), Vector3(X1 + 0.012, py, pz), m,
			Vector3(ang, 0.0, 0.0), false)


## 内衬板：贴在四面墙的内表面，厚 4 cm。
##
## 两个作用：一是把室内亮度压下来（见 build 里的注释），
## 二是木板房本来就有内衬 —— 从室内看到的是板材，不是墙体结构面。
##
## 南墙必须在门洞处断开（左右两段 + 门楣），否则内衬会把门糊死。
static func _lining(g: Node3D, mat: Material) -> void:
	var t := 0.04
	var ix0 := X0 + WALL_T
	var ix1 := X1 - WALL_T
	var iz0 := Z0 + WALL_T
	var iz1 := Z1 - WALL_T
	var seg_w := (ix1 - ix0) * 0.5 - DOOR_W * 0.5      # 11.7
	var seg_cx := (ix0 + ix1) * 0.5 - (DOOR_W * 0.5 + seg_w * 0.5)

	# 南墙（门洞两侧 + 门楣）
	K.box(g, Vector3(seg_w, EAVE, t), Vector3(seg_cx, EAVE * 0.5, iz0 + t * 0.5), mat, Vector3.ZERO, false)
	K.box(g, Vector3(seg_w, EAVE, t), Vector3(CX * 2.0 - seg_cx, EAVE * 0.5, iz0 + t * 0.5), mat, Vector3.ZERO, false)
	K.box(g, Vector3(DOOR_W, EAVE - DOOR_H, t),
		Vector3(CX, DOOR_H + (EAVE - DOOR_H) * 0.5, iz0 + t * 0.5), mat, Vector3.ZERO, false)

	# 北墙
	K.box(g, Vector3(ix1 - ix0, EAVE, t), Vector3(CX, EAVE * 0.5, iz1 - t * 0.5), mat, Vector3.ZERO, false)

	# 东西墙
	K.box(g, Vector3(t, EAVE, iz1 - iz0), Vector3(ix0 + t * 0.5, EAVE * 0.5, CZ), mat, Vector3.ZERO, false)
	K.box(g, Vector3(t, EAVE, iz1 - iz0), Vector3(ix1 - t * 0.5, EAVE * 0.5, CZ), mat, Vector3.ZERO, false)


## 沿四面墙等距贴竖向壁柱，把长立面切碎。
static func _pilasters(g: Node3D, mat: Material, dark: Material) -> void:
	var step := 3.5
	# 南/北墙：避开中间门洞
	for side in [Z0 + 0.02, Z1 - 0.02]:
		var x := X0 + 1.2
		while x < X1 - 0.5:
			if absf(x - CX) > DOOR_W * 0.5 + 0.6:
				K.box(g, Vector3(0.26, EAVE, 0.12), Vector3(x, EAVE * 0.5, side), dark, Vector3.ZERO, false)
			x += step
	# 东西墙
	for side in [X0 + 0.02, X1 - 0.02]:
		var z := Z0 + 1.4
		while z < Z1 - 0.8:
			K.box(g, Vector3(0.12, EAVE, 0.26), Vector3(side, EAVE * 0.5, z), dark, Vector3.ZERO, false)
			z += step

	# 腰线：一层与二层之间一道，沿四面
	K.box(g, Vector3(W - WALL_T * 2.0, 0.14, 0.1), Vector3(CX, FL1 + 0.55, Z0 + 0.03), dark, Vector3.ZERO, false)
	K.box(g, Vector3(W - WALL_T * 2.0, 0.14, 0.1), Vector3(CX, FL1 + 0.55, Z1 - 0.03), dark, Vector3.ZERO, false)
	K.box(g, Vector3(0.1, 0.14, D - WALL_T * 2.0), Vector3(X0 + 0.03, FL1 + 0.55, CZ), dark, Vector3.ZERO, false)
	K.box(g, Vector3(0.1, 0.14, D - WALL_T * 2.0), Vector3(X1 - 0.03, FL1 + 0.55, CZ), dark, Vector3.ZERO, false)


## 外墙窗。位置必须落在墙的**外表面**上。
##
## 之前把窗放在「内皮 + 0.01」，整个窗组（含近黑窗芯）都埋进了 0.3 m 厚的墙体里 ——
## 从外面看只剩一圈框，从里面看的是一块和墙同色的空洞。
## 窗是贴面构件，贴哪一面就得站在那一面的外侧。
static func _windows(g: Node3D, dark: Material, shade: Material) -> void:
	# 南墙：门两侧各 2 扇
	for x in [-137.0, -131.0, -121.0, -115.0]:
		_window(g, Vector3(x, 2.5, Z0 - 0.01), 180.0, dark, shade)
		_window(g, Vector3(x, 6.2, Z0 - 0.01), 180.0, dark, shade)

	# 北墙 2 扇
	for x in [-134.0, -118.0]:
		_window(g, Vector3(x, 2.5, Z1 + 0.01), 0.0, dark, shade)
		_window(g, Vector3(x, 6.2, Z1 + 0.01), 0.0, dark, shade)

	# 东西墙各 3 扇
	for z in [321.0, 328.5, 336.0]:
		_window(g, Vector3(X0 - 0.01, 2.5, z), -90.0, dark, shade)
		_window(g, Vector3(X0 - 0.01, 6.2, z), -90.0, dark, shade)
		_window(g, Vector3(X1 + 0.01, 2.5, z), 90.0, dark, shade)
		_window(g, Vector3(X1 + 0.01, 6.2, z), 90.0, dark, shade)


## 室内看的窗：贴在内衬板上，用**亮**色表示透进来的天光。
##
## 同一扇窗两个面两个亮度 —— 外面看是暗的（屋里没点灯），
## 里面看是亮的（外面是白天）。两块贴片各自贴在自己那一侧，互不可见。
static func _inner_windows(g: Node3D, dark: Material, glow: Material) -> void:
	var t := 0.04
	var iz0 := Z0 + WALL_T + t
	var iz1 := Z1 - WALL_T - t
	var ix0 := X0 + WALL_T + t
	var ix1 := X1 - WALL_T - t

	for x in [-137.0, -131.0, -121.0, -115.0]:
		_inner_window(g, Vector3(x, 2.5, iz0), 0.0, dark, glow)
		_inner_window(g, Vector3(x, 6.2, iz0), 0.0, dark, glow)
	for x in [-134.0, -118.0]:
		_inner_window(g, Vector3(x, 2.5, iz1), 180.0, dark, glow)
		_inner_window(g, Vector3(x, 6.2, iz1), 180.0, dark, glow)
	for z in [321.0, 328.5, 336.0]:
		_inner_window(g, Vector3(ix0, 2.5, z), 90.0, dark, glow)
		_inner_window(g, Vector3(ix0, 6.2, z), 90.0, dark, glow)
		_inner_window(g, Vector3(ix1, 2.5, z), -90.0, dark, glow)
		_inner_window(g, Vector3(ix1, 6.2, z), -90.0, dark, glow)


## 一扇窗：近黑窗芯 + 四边框 + 十字窗棂 + 窗台。局部 +Z 朝屋外。
## 所有部件都在局部 z ≥ 0，往墙外凸，不穿进墙体。
static func _window(g: Node3D, pos: Vector3, yaw: float, dark: Material, shade: Material) -> void:
	var w := K.group(g, "Window", pos, Vector3(0.0, yaw, 0.0))
	K.box(w, Vector3(1.4, 1.8, 0.04), Vector3(0.0, 0.0, 0.02), shade, Vector3.ZERO, false)
	K.box(w, Vector3(1.64, 0.13, 0.14), Vector3(0.0, 0.965, 0.07), dark)
	K.box(w, Vector3(1.64, 0.13, 0.14), Vector3(0.0, -0.965, 0.07), dark)
	K.box(w, Vector3(0.13, 1.93, 0.14), Vector3(-0.755, 0.0, 0.07), dark)
	K.box(w, Vector3(0.13, 1.93, 0.14), Vector3(0.755, 0.0, 0.07), dark)
	K.box(w, Vector3(0.08, 1.8, 0.1), Vector3(0.0, 0.0, 0.07), dark)
	K.box(w, Vector3(1.4, 0.08, 0.1), Vector3(0.0, 0.25, 0.07), dark)
	# 窗台，出墙一点，给立面加一道水平阴影
	K.box(w, Vector3(1.7, 0.1, 0.26), Vector3(0.0, -1.03, 0.13), dark)


## 室内侧那扇窗：亮片 + 细木框，朝室内凸 3 cm。
static func _inner_window(g: Node3D, pos: Vector3, yaw: float, dark: Material, glow: Material) -> void:
	var w := K.group(g, "InnerWindow", pos, Vector3(0.0, yaw, 0.0))
	K.box(w, Vector3(1.34, 1.74, 0.03), Vector3(0.0, 0.0, 0.008), glow, Vector3.ZERO, false)
	K.box(w, Vector3(1.52, 0.1, 0.08), Vector3(0.0, 0.9, 0.03), dark)
	K.box(w, Vector3(1.52, 0.1, 0.08), Vector3(0.0, -0.9, 0.03), dark)
	K.box(w, Vector3(0.1, 1.8, 0.08), Vector3(-0.72, 0.0, 0.03), dark)
	K.box(w, Vector3(0.1, 1.8, 0.08), Vector3(0.72, 0.0, 0.03), dark)
	K.box(w, Vector3(0.07, 1.74, 0.06), Vector3(0.0, 0.0, 0.03), dark)


# ---------------------------------------------------------------- 门

## 4 m 双开木门 + 门前雨棚。
## 两扇各开 62°，不关死 —— 关着的门在截图里是「一栋房子」，
## 开着一条缝的门才是「可以进去的地方」。
static func _door(g: Node3D, dark: Material, wood: Material) -> void:
	var half := DOOR_W * 0.5
	# 门框：两侧立柱 + 上槛
	K.box(g, Vector3(0.28, DOOR_H + 0.3, 0.42), Vector3(CX - half - 0.14, (DOOR_H + 0.3) * 0.5, Z0 + WALL_T * 0.5), dark)
	K.box(g, Vector3(0.28, DOOR_H + 0.3, 0.42), Vector3(CX + half + 0.14, (DOOR_H + 0.3) * 0.5, Z0 + WALL_T * 0.5), dark)
	K.box(g, Vector3(DOOR_W + 0.56, 0.34, 0.44), Vector3(CX, DOOR_H + 0.17, Z0 + WALL_T * 0.5), dark)

	# 门扇：绕合页转，合页在门框两侧
	for sign_ in [-1.0, 1.0]:
		var hinge := K.group(g, "DoorLeaf",
			Vector3(CX + sign_ * half, 0.0, Z0 + WALL_T * 0.5))
		# 本地 +X 是「从合页指向门洞中心」的方向
		hinge.rotation_degrees.y = sign_ * 62.0
		var local_x: float = half * sign_ * -1.0
		K.box(hinge, Vector3(half - 0.04, DOOR_H - 0.06, 0.1),
			Vector3(local_x * 0.5, (DOOR_H - 0.06) * 0.5, 0.0), wood)
		# 门板压条：每扇两道横带 + 一道斜撑，木门的气质全在这些条上
		for y in [0.75, 2.05]:
			K.box(hinge, Vector3(half - 0.1, 0.16, 0.14),
				Vector3(local_x * 0.5, y, 0.02), dark)
		K.box(hinge, Vector3(0.1, 0.1, 0.14),
			Vector3(local_x * 0.82, 1.42, 0.03), dark)
		# 门环
		K.torus(hinge, 0.055, 0.085, Vector3(local_x * 0.86, 1.4, 0.03), dark,
			Vector3(90.0, 0.0, 0.0))

	# 雨棚：两根柱子 + 一块小坡顶
	var porch_z := Z0 - 2.2
	for sign_ in [-1.0, 1.0]:
		K.box(g, Vector3(0.24, 3.1, 0.24), Vector3(CX + sign_ * 2.6, 1.55, porch_z), dark)
		solid_col(g, Vector3(0.24, 3.1, 0.24), Vector3(CX + sign_ * 2.6, 1.55, porch_z))
	K.box(g, Vector3(6.4, 0.16, 2.6), Vector3(CX, 3.18, porch_z + 0.4), dark, Vector3(-8.0, 0.0, 0.0))
	K.box(g, Vector3(6.6, 0.1, 0.18), Vector3(CX, 3.02, porch_z - 0.86), dark)


# ---------------------------------------------------------------- 台阶

## 门前石阶：一块门槛石 + 一级矮踏步，比外墙宽出近一米。
##
## 不加碰撞：这级只有 6~12 cm，CharacterBody3D 会直接踩过去，
## 加了碰撞反而会在门口卡一下（这个控制器没有自动上台阶）。
## 12 cm 的视觉误差在第三人称镜头下几乎看不出来。
static func _steps(g: Node3D, stone: Material, dark: Material) -> void:
	var y_top := 0.12
	# 门槛石：从门洞里一直铺到门外 0.5 m，压住门框底
	K.box(g, Vector3(DOOR_W + 0.9, y_top, 0.95), Vector3(CX, y_top * 0.5, Z0 - 0.15), stone)
	# 矮踏步
	K.box(g, Vector3(DOOR_W + 1.5, 0.06, 0.55), Vector3(CX, 0.03, Z0 - 0.88), stone)
	K.box(g, Vector3(DOOR_W + 1.5, 0.03, 0.06), Vector3(CX, 0.015, Z0 - 1.15), dark, Vector3.ZERO, false)


# ---------------------------------------------------------------- 屋顶

## 双坡屋顶，屋脊沿 X（东西向）。
##
## 为什么是东西向：玩家从南门进城，正对的是公会的南立面。
## 屋脊沿 X 时南立面是一个完整的梯形坡面 + 两条檐线，读起来是「一栋大房子」；
## 屋脊沿 Z 的话南立面变成山尖，会读成「一座仓库」。
static func _roof(g: Node3D, roof_mat: Material, dark: Material, wood: Material) -> void:
	var half := D * 0.5
	var rise := RIDGE - EAVE                        # 2.8
	var overhang := 0.9
	var run := half + overhang                      # 13.4
	var slope_len := sqrt(run * run + rise * rise)
	var angle := rad_to_deg(atan2(rise, run))       # 11.8°

	# 两块坡面。南坡 z 减小、y 减小 → 绕 X 转负角
	#
	# 东西向只出檐 0.2 m：这两个方向是**山墙**，不是檐口。
	# 原来给到 W+1.2（两侧各 0.6），屋顶把 25 m 宽的三角山墙整个盖住了 ——
	# 从东侧看过去只剩屋顶的下表面，一块黑三角，读成「没有山墙的棚子」。
	var south_cz := CZ - run * 0.5
	var north_cz := CZ + run * 0.5
	K.box(g, Vector3(W + 0.4, 0.26, slope_len), Vector3(CX, (EAVE + RIDGE) * 0.5, south_cz),
		roof_mat, Vector3(-angle, 0.0, 0.0))
	K.box(g, Vector3(W + 0.4, 0.26, slope_len), Vector3(CX, (EAVE + RIDGE) * 0.5, north_cz),
		roof_mat, Vector3(angle, 0.0, 0.0))

	# 屋脊压顶
	K.box(g, Vector3(W + 0.6, 0.22, 0.5), Vector3(CX, RIDGE + 0.06, CZ), dark)

	# 山墙三角：prism 顶点朝上、正面朝 +Z，转 ±90° 让三角形朝东西。
	#
	# 一片就够 —— kit.prism 是一个封闭实体，正反两片三角形都在，不需要画两次。
	var gable_h := RIDGE - EAVE
	for sign_x in [-1.0, 1.0]:
		var gx: float = (X0 + WALL_T * 0.5) if sign_x < 0.0 else (X1 - WALL_T * 0.5)
		var yaw: float = -90.0 if sign_x < 0.0 else 90.0
		K.prism(g, Vector3(D, gable_h, WALL_T),
			Vector3(gx, EAVE + gable_h * 0.5, CZ), wood, Vector3(0.0, yaw, 0.0))

	# 山墙上的木质博风板：沿两条斜边各贴一根，遮住三角与坡面的接缝。
	# 必须贴在外皮之外（X0 − 0.05），压在墙里会被墙吞掉，只剩一段看不见的杆
	for sign_x in [-1.0, 1.0]:
		var bx: float = X0 - 0.05 if sign_x < 0.0 else X1 + 0.05
		for sign_z in [-1.0, 1.0]:
			K.strut(g, Vector3(bx, EAVE, CZ + sign_z * (half + overhang)),
				Vector3(bx, RIDGE, CZ), 0.09, dark, 6)

	# 山墙木桁架：系梁 + 中柱 + 两根斜撑。
	#
	# 没有这套东西，25 m 宽的山墙就是一块空木板，从侧面看像「没盖完的棚子」。
	# 而「内外全是木头」是这栋楼的设定，山墙上本来就该看到构架。
	# 全部贴在博风板那一层（X0 − 0.05 / X1 + 0.05），压进墙里会被墙吞掉。
	for sign_x in [-1.0, 1.0]:
		var bx: float = X0 - 0.05 if sign_x < 0.0 else X1 + 0.05
		var tie_y := EAVE + 0.55
		K.box(g, Vector3(0.10, 0.20, D - 1.0), Vector3(bx, tie_y, CZ), dark)
		var post_h := RIDGE - 0.20 - tie_y
		K.box(g, Vector3(0.10, post_h, 0.22), Vector3(bx, tie_y + post_h * 0.5, CZ), dark)
		for sign_z in [-1.0, 1.0]:
			K.strut(g, Vector3(bx, tie_y + 0.10, CZ + sign_z * 4.6),
				Vector3(bx, tie_y + 1.75, CZ + sign_z * 0.13), 0.07, dark, 6)

	# 檐口封板：把屋顶和墙顶之间的缝隙收掉
	K.box(g, Vector3(W + 0.4, 0.3, 0.16), Vector3(CX, EAVE - 0.08, Z0 - overhang + 0.05), dark)
	K.box(g, Vector3(W + 0.4, 0.3, 0.16), Vector3(CX, EAVE - 0.08, Z1 + overhang - 0.05), dark)


# ---------------------------------------------------------------- 烟囱

## 石砌烟囱：从北坡穿出屋面，顶高出屋脊 1.5 m。
##
## 位置放在北坡（z = 333.6）、偏西，有两个理由：
##   1. 北坡是背光面，烟囱在背光坡上会形成一条竖向剪影，正好打破
##      「南立面全是横线（腰线 + 檐口 + 石脚）」的平衡 —— 一眼看去屋顶不再是空的；
##   2. 偏西是为了不挡屋脊中段，同时让它从正面（南）看能露出一截在屋脊之上。
##
## 高度算式写在这里，改 RIDGE / D 时不用重新猜：
##   北坡上任意 z 处的屋面标高 y(z) = RIDGE − (z − CZ) · (RIDGE − EAVE) / (D/2 + 0.9)
static func _chimney(g: Node3D, stone: Material, dark: Material) -> void:
	var z := 333.6
	var run := D * 0.5 + 0.9
	var roof_y := RIDGE - (z - CZ) * (RIDGE - EAVE) / run
	# 顶比屋脊高 2.1 m。第一版只高 1.5 m，从南面看过去只露一个方块，
	# 读成「屋顶上的检修口」；要成为剪影的一部分，就得明显高过屋脊
	var top := RIDGE + 2.1
	var cx := -132.6

	# 烟道主体：下口沉进屋面 0.9 m
	var y0 := roof_y - 0.9
	K.box(g, Vector3(1.35, top - y0, 1.35), Vector3(cx, (y0 + top) * 0.5, z), stone)
	# 收颈：石烟囱都要有这么一道，光杆方柱会读成通风管
	K.box(g, Vector3(1.62, 0.18, 1.62), Vector3(cx, top + 0.09, z), dark)
	# 顶帽：比收颈再宽一圈，出檐 8 cm，形成一圈投影
	K.box(g, Vector3(1.86, 0.24, 1.86), Vector3(cx, top + 0.30, z), stone)
	# 烟口：顶帽上开一个近黑的口，否则从高处俯视是一块实心石头
	K.box(g, Vector3(0.74, 0.12, 0.74), Vector3(cx, top + 0.46, z),
		K.toon(Color("#15110c"), {"line": 0.0}))
	# 屋面泛水：贴着屋面的一圈薄石，遮住烟囱和坡面的接缝
	K.box(g, Vector3(1.85, 0.10, 1.85), Vector3(cx, roof_y + 0.02, z), dark, Vector3.ZERO, false)


# ---------------------------------------------------------------- 前台

## 12 m 长前台，贴北墙。
## 台面比台身宽出一圈（0.95 vs 0.8），这样从正面看有一道悬挑的阴影，
## 否则 12 m 的方盒子会读成一段隔墙。
static func _counter(g: Node3D, mat: Material, dark: Material) -> void:
	var len_ := COUNTER_X1 - COUNTER_X0
	var cx := (COUNTER_X0 + COUNTER_X1) * 0.5

	K.box(g, Vector3(len_, COUNTER_H, COUNTER_DEPTH),
		Vector3(cx, COUNTER_H * 0.5, COUNTER_Z), mat)
	K.box(g, Vector3(len_ + 0.3, 0.1, COUNTER_DEPTH + 0.18),
		Vector3(cx, COUNTER_H + 0.05, COUNTER_Z), dark)
	# 踢脚
	K.box(g, Vector3(len_ + 0.1, 0.14, COUNTER_DEPTH + 0.08),
		Vector3(cx, 0.07, COUNTER_Z), dark)
	# 竖向包边：每 2 m 一道，12 m 的板子中间什么都没有会显得像水泥
	for i in range(1, 6):
		var x := COUNTER_X0 + len_ * float(i) / 6.0
		K.box(g, Vector3(0.12, COUNTER_H - 0.1, COUNTER_DEPTH + 0.06),
			Vector3(x, COUNTER_H * 0.5, COUNTER_Z), dark, Vector3.ZERO, false)
	solid_col(g, Vector3(len_, COUNTER_H, COUNTER_DEPTH), Vector3(cx, COUNTER_H * 0.5, COUNTER_Z))

	# 台面上的东西：账本 + 墨水瓶 + 一盏灯座，给 12 m 的台面一个视觉落点
	K.box(g, Vector3(0.9, 0.16, 0.6), Vector3(-133.0, COUNTER_H + 0.18, COUNTER_Z), dark,
		Vector3(0.0, 12.0, 0.0))
	K.cyl(g, 0.09, 0.18, Vector3(-130.6, COUNTER_H + 0.19, COUNTER_Z), dark, Vector3.ZERO, 8)
	K.strut(g, Vector3(-127.0, COUNTER_H + 0.1, COUNTER_Z),
		Vector3(-127.0, COUNTER_H + 0.75, COUNTER_Z), 0.05, dark, 6)
	K.sphere(g, 0.17, Vector3(-127.0, COUNTER_H + 0.88, COUNTER_Z),
		K.toon(Color("#ffdca8"), {"line": 0.0, "shade": 0.9}), Vector3.ZERO, 12)


# ---------------------------------------------------------------- 楼梯

## U 型折返楼梯：第一跑面朝大门（朝南）升到 2.1 m 平台，第二跑折返到 4.2 m。
##
## 视觉是台阶，碰撞是斜面 —— CharacterBody3D 没有自动上台阶，
## 0.175 m 的台阶会让玩家卡在第一级。斜面碰撞 + 台阶视觉是这种场合的标准解法，
## 两层各一个 BoxShape3D 转 30°。
static func _stairs(g: Node3D, mat: Material, dark: Material) -> void:
	var run_w := (STAIR_W - STAIR_GAP) * 0.5             # 1.6
	var west_cx := STAIR_X - STAIR_W * 0.5 + run_w * 0.5          # 靠大厅那跑
	var east_cx := STAIR_X + STAIR_W * 0.5 - run_w * 0.5          # 贴墙那跑

	# 第一跑：从北端（z 大）往南（z 小）逐级升高，第一级最靠北
	for i in STEP_N:
		var h := STEP_H * float(i + 1)
		var z := STAIR_Z1 - STEP_T * (float(i) + 0.5)
		K.box(g, Vector3(run_w, h, STEP_T), Vector3(west_cx, h * 0.5, z), mat, Vector3.ZERO, false)
		# 踏板前缘，一深一浅让台阶在强光下还能数得清
		K.box(g, Vector3(run_w + 0.06, 0.05, 0.08), Vector3(west_cx, h - 0.02, z - STEP_T * 0.5 + 0.04), dark, Vector3.ZERO, false)

	# 平台
	var plat_z := STAIR_Z0 + 0.6
	K.box(g, Vector3(STAIR_W, FL1 * 0.5, 1.2), Vector3(STAIR_X, FL1 * 0.25, plat_z), mat, Vector3.ZERO, false)
	K.box(g, Vector3(STAIR_W + 0.1, 0.08, 1.26), Vector3(STAIR_X, FL1 * 0.5 + 0.02, plat_z), dark, Vector3.ZERO, false)

	# 平台南立面：从大厅看过去是一整块 3.35 × 2.1 的实心面，不加东西会被
	# 读成「一个大柜台」而不是楼梯。两道腰线 + 两根楼梯柱就能把它读回楼梯间 ——
	# 楼梯柱（newel post）是楼梯最标志性的构件，一根球头柱胜过十级台阶。
	for y in [0.55, 1.45]:
		K.box(g, Vector3(STAIR_W + 0.06, 0.1, 0.08),
			Vector3(STAIR_X, y, STAIR_Z0 - 0.03), dark, Vector3.ZERO, false)
	for sign_ in [-1.0, 1.0]:
		var nx: float = STAIR_X + sign_ * (STAIR_W * 0.5 - 0.15)
		K.box(g, Vector3(0.16, 1.15, 0.16),
			Vector3(nx, FL1 * 0.5 + 0.575, STAIR_Z0 + 0.02), dark)
		K.sphere(g, 0.11, Vector3(nx, FL1 * 0.5 + 1.2, STAIR_Z0 + 0.02), dark, Vector3.ZERO, 10)

	# 第二跑：从平台往北升到 4.2
	for i in STEP_N:
		var h := FL1 * 0.5 + STEP_H * float(i + 1)
		var z := STAIR_Z0 + 1.2 + STEP_T * (float(i) + 0.5)
		K.box(g, Vector3(run_w, h, STEP_T), Vector3(east_cx, h * 0.5, z), mat, Vector3.ZERO, false)
		K.box(g, Vector3(run_w + 0.06, 0.05, 0.08), Vector3(east_cx, h - 0.02, z + STEP_T * 0.5 - 0.04), dark, Vector3.ZERO, false)

	# 两跑之间的缝（0.15 m）两跑都是实心，从侧面看本来就不透光，不用再封板
	# 扶手：外跑外侧一根斜梁 + 立柱
	var rail_x := STAIR_X - STAIR_W * 0.5 - 0.02
	K.strut(g, Vector3(rail_x, 1.05, STAIR_Z1 - 0.1), Vector3(rail_x, 3.15, STAIR_Z0 + 0.75), 0.06, dark, 6)
	for i in [1, 4, 7, 10]:
		var h := STEP_H * float(i + 1)
		var z := STAIR_Z1 - STEP_T * (float(i) + 0.5)
		K.strut(g, Vector3(rail_x, h, z), Vector3(rail_x, h + 0.95, z), 0.05, dark, 6)

	# 二层楼梯口的一小块楼板 + 护栏。二楼不做，但这一块必须有，
	# 否则第二跑直接通向空中，玩家会以为楼梯断了
	K.box(g, Vector3(STAIR_W + 0.4, 0.2, 2.4), Vector3(STAIR_X, FL1 + 0.1, STAIR_Z1 + 1.0), dark)
	for i in 4:
		var x := STAIR_X - STAIR_W * 0.5 - 0.1 + STAIR_W * float(i) / 3.0
		K.strut(g, Vector3(x, FL1 + 0.2, STAIR_Z1 - 0.2), Vector3(x, FL1 + 1.25, STAIR_Z1 - 0.2), 0.05, dark, 6)
	K.box(g, Vector3(STAIR_W + 0.3, 0.09, 0.12), Vector3(STAIR_X, FL1 + 1.28, STAIR_Z1 - 0.2), dark)

	# 碰撞：两跑各一个斜面。
	# 参数是「低端 → 高端」，_ramp_collider 内部按这个方向算倾角。
	# 第一跑：地面（北端）→ 平台（南端）
	_ramp_collider(g, Vector3(west_cx, 0.0, STAIR_Z1),
		Vector3(west_cx, FL1 * 0.5, STAIR_Z0 + 1.2), run_w)
	# 第二跑：平台（南端）→ 二层（北端）
	_ramp_collider(g, Vector3(east_cx, FL1 * 0.5, STAIR_Z0 + 1.2),
		Vector3(east_cx, FL1, STAIR_Z1), run_w)
	solid_col(g, Vector3(STAIR_W, 0.24, 1.3), Vector3(STAIR_X, FL1 * 0.5, plat_z))
	solid_col(g, Vector3(STAIR_W + 0.4, 0.24, 2.4), Vector3(STAIR_X, FL1 + 0.1, STAIR_Z1 + 1.0))


## 斜坡碰撞：从 a（低端）到 b（高端）一块斜板。
##
## 为什么不直接给每级台阶加碰撞：CharacterBody3D 没有自动上台阶（和 dev 工程那个
## 角色控制器不同，这里没有 _try_step_up），0.175 m 的踢面会让玩家在第一级卡住，
## 表现为「楼梯走不上去」，而且不报任何错。
##
## 旋转推导：box 的局部 +Z 是长度方向。绕 X 转 θ 后 +Z = (0, −sinθ, cosθ)，
## 要对齐 d = (0, dy, dz)，解出 θ = atan2(−dy, dz)。只在 y/z 平面内，
## 所以只需要一个绕 X 的角度，不用管四元数。
static func _ramp_collider(g: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var span := d.length()
	if span < 0.01:
		return
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.2, span)
	col.shape = shape
	body.add_child(col)
	body.position = (a + b) * 0.5
	body.rotation.x = atan2(-d.y, d.z)
	g.add_child(body)


# ---------------------------------------------------------------- 任务板

## 两块立式任务板，门右侧。
##
## 立架而不是挂墙 —— 挂墙的板子玩家要贴着墙看，立架可以绕着走一圈，
## 而且能放在离门 2.6 m 的位置，进门第一眼就撞上。
static func _boards(g: Node3D, _mat: Material, dark: Material) -> void:
	# 麻布压到 0.56 —— 原来的浅麻色在室内暖灯下会过曝成一块发光的灯箱，
	# 板面比墙亮太多，反而看不出「这是一块布」
	var cloth := K.toon(Color("#8a7448"), {"line": 0.010, "shade": 0.60, "rim": 0.0})
	var paper := K.toon(Color("#cbbfa2"), {"line": 0.0, "shade": 0.85, "rim": 0.0})

	for p in BOARD_POS:
		var b := K.group(g, "QuestBoard", p)
		# 立柱 + 底座
		for sign_ in [-1.0, 1.0]:
			K.box(b, Vector3(0.12, 2.5, 0.12), Vector3(sign_ * 0.75, 1.25, 0.0), dark)
		K.box(b, Vector3(1.9, 0.12, 0.62), Vector3(0.0, 0.06, 0.0), dark)
		# 板面（麻布）与边框
		K.box(b, Vector3(1.5, 1.8, 0.1), Vector3(0.0, 1.42, 0.0), cloth)
		K.box(b, Vector3(1.66, 0.12, 0.14), Vector3(0.0, 2.36, 0.0), dark)
		K.box(b, Vector3(1.66, 0.12, 0.14), Vector3(0.0, 0.48, 0.0), dark)
		K.box(b, Vector3(0.12, 1.98, 0.14), Vector3(-0.77, 1.42, 0.0), dark)
		K.box(b, Vector3(0.12, 1.98, 0.14), Vector3(0.77, 1.42, 0.0), dark)
		# 小顶檐：下雨不至于把布浇透，也把这两块的轮廓跟柱列区分开
		K.box(b, Vector3(1.9, 0.1, 0.5), Vector3(0.0, 2.52, 0.06), dark, Vector3(-12.0, 0.0, 0.0))
		# 几张空纸条 —— 内容是空的，但板上完全空白会像没加载。
		# 数组解包成显式 float：typed GDScript 里 Vector3(Variant, Variant, float)
		# 不会隐式转换，会在运行时才炸
		for s in [[-0.36, 1.72, 6.0, 0.40, 0.30], [0.28, 1.56, -4.0, 0.34, 0.26],
				[-0.12, 1.14, 3.0, 0.42, 0.22], [0.32, 1.05, 5.0, 0.26, 0.20]]:
			var sx: float = s[0]
			var sy: float = s[1]
			var ang: float = s[2]
			var sw: float = s[3]
			var sh: float = s[4]
			K.box(b, Vector3(sw, sh, 0.012), Vector3(sx, sy, 0.06), paper,
				Vector3(0.0, 0.0, ang), false)
		solid_col(b, Vector3(1.9, 2.5, 0.5), Vector3(0.0, 1.25, 0.0))


# ---------------------------------------------------------------- 前庭

## 门前那片地：一条越走越宽的梯形石板路 + 两侧抬高的花池。
##
## 几何全部用「四边形板」而不是方块：路和花池的两条边都是斜的，
## 拿轴对齐的方块去拼，边缘会走成一级一级的台阶（第一版就是这样，
## 近看像梯田）。这里直接按斜边插值出四个角，边缘是一根干净的斜线。
##
## 花池**不铺满整个前庭**。铺满 28 m 宽的结果是整片变成一块泥地，
## 石板路被挤成中间一条缝 —— 前庭的主角是路，花池是镶边。
## 所以花池固定 2.2 m 进深，跟着路的斜边往外挪，两侧各留一截方石广场。
##
## 随机数用固定种子：每次进场景石块位置都一样，截图能对上、也能回归。
static func _court(g: Node3D) -> void:
	# 砂浆底：比石板暗、比土灰，石板之间的缝露出来的就是它
	var mortar := K.toon(Color("#463d31"), {"line": 0.0, "shade": 0.45})
	# 三档石板。必须比广场方石更暖（偏黄褐）：
	# 水平面在这个场景里只吃天空 ambient（冷蓝），纯灰的石头会被染成游泳池蓝 ——
	# 第一版 #7e796e 铺出来整条路是蓝的，就是没算这一笔
	var slabs := [
		K.toon(Color("#9c8763"), {"line": 0.0, "shade": 0.52, "rim": 0.0}),
		K.toon(Color("#8d7a58"), {"line": 0.0, "shade": 0.50, "rim": 0.0}),
		K.toon(Color("#a8926c"), {"line": 0.0, "shade": 0.54, "rim": 0.0}),
	]
	# 花池土：接近黑的深褐，只在花草之间露一点点
	var soil := K.toon(Color("#382c1c"), {"line": 0.0, "shade": 0.42, "rim": 0.0})
	# 池边石：比路面暗，压住整块花池的轮廓
	var kerb := K.toon(Color("#57514a"), {"line": 0.0, "shade": 0.48, "rim": 0.0})
	# 池面草皮：深绿偏黄。这个院子整天在公会自己的影子里，只吃天空的冷蓝 ambient，
	# 绿给亮一点就会被染成青蓝（第一版整片像游泳池）
	var turf_top := K.toon(Color("#4a5a30"), {"line": 0.0, "shade": 0.48, "rim": 0.0})

	var z_far := COURT_Z0
	var z_near := Z0 - 0.55          # 收在门槛石前面，别和石阶打架
	# 18 排 × 0.45 m：一块石板大约 0.9 × 0.45，接近真正的手工铺石。
	# 13 排（0.62 m 深）铺出来是 1.4 × 0.6 的大板，像机切的地砖
	var rows := 18
	var row_d := (z_near - z_far) / float(rows)
	var bed_h := 0.22                # 花池比广场高 22 cm，是一道看得见的边

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021

	for i in rows:
		var za := z_far + row_d * float(i)
		var zb := za + row_d
		# t = 0 在门口，1 在最远端 —— 半宽按 t 线性插值就是梯形
		var ha := lerpf(PATH_NEAR_W, PATH_FAR_W, (z_near - za) / (z_near - z_far)) * 0.5
		var hb := lerpf(PATH_NEAR_W, PATH_FAR_W, (z_near - zb) / (z_near - z_far)) * 0.5

		# 砂浆底：比路面宽 8 cm，把石板的斜边压住
		_poly(g, _quad_xz(CX - ha - 0.08, CX + ha + 0.08, za, CX - hb - 0.08, CX + hb + 0.08, zb),
			0.0, 0.045, mortar)

		# 石板：横向切几块，每块是一个跟着斜边走的四边形，中间留 4 cm 灰缝
		var cells := maxi(3, int(round(ha * 2.0 / 0.95)))
		for j in cells:
			var f0 := float(j) / float(cells)
			var f1 := float(j + 1) / float(cells)
			var g0 := 0.035 / maxf(ha * 2.0, 0.01)
			var g1 := 0.035 / maxf(hb * 2.0, 0.01)
			var h := rng.randf_range(0.055, 0.075)
			_poly(g, _quad_xz(
				CX - ha + ha * 2.0 * (f0 + g0), CX - ha + ha * 2.0 * (f1 - g0), za,
				CX - hb + hb * 2.0 * (f0 + g1), CX - hb + hb * 2.0 * (f1 - g1), zb),
				0.0, h, slabs[rng.randi_range(0, 2)])

		# 两侧花池：一条和路平行的斜带，土从地面一直砌到 bed_h
		for sign_ in [-1.0, 1.0]:
			var ia: float = CX + sign_ * (ha + 0.14)
			var ib: float = CX + sign_ * (hb + 0.14)
			_poly(g, _quad_xz(ia, ia + sign_ * BED_DEPTH, za, ib, ib + sign_ * BED_DEPTH, zb),
				0.0, bed_h - 0.02, soil)
			# 池面：比土高 2 cm 的一层草皮。整片铺成一块，而不是一格一格的方块 ——
			# 方块会在池面上留下几十条硬边，远看像拼图
			var ia2: float = ia + sign_ * 0.05
			var ib2: float = ib + sign_ * 0.05
			_poly(g, _quad_xz(ia2, ia2 + sign_ * (BED_DEPTH - 0.10), za + 0.05,
				ib2, ib2 + sign_ * (BED_DEPTH - 0.10), zb - 0.05),
				bed_h - 0.02, bed_h + 0.02, turf_top)

	# 池边：内外两根斜石棱，两端再横一根，把花池围成一个整块
	for sign_ in [-1.0, 1.0]:
		var ni: float = CX + sign_ * (PATH_NEAR_W * 0.5 + 0.07)
		var fi: float = CX + sign_ * (PATH_FAR_W * 0.5 + 0.07)
		K.strut(g, Vector3(ni, bed_h * 0.5, z_near), Vector3(fi, bed_h * 0.5, z_far), 0.085, kerb, 8)
		K.strut(g, Vector3(ni + sign_ * BED_DEPTH, bed_h * 0.5, z_near),
			Vector3(fi + sign_ * BED_DEPTH, bed_h * 0.5, z_far), 0.085, kerb, 8)
		K.strut(g, Vector3(ni, bed_h * 0.5, z_near),
			Vector3(ni + sign_ * BED_DEPTH, bed_h * 0.5, z_near), 0.085, kerb, 8)
		K.strut(g, Vector3(fi, bed_h * 0.5, z_far),
			Vector3(fi + sign_ * BED_DEPTH, bed_h * 0.5, z_far), 0.085, kerb, 8)

	_plant_beds(g, rng, z_far, z_near, bed_h)


## 一个梯形单元的四个角（XZ），顺序是左下→右下→右上→左上（俯视逆时针）。
static func _quad_xz(xa0: float, xa1: float, za: float,
		xb0: float, xb1: float, zb: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(xa0, 0.0, za), Vector3(xa1, 0.0, za),
		Vector3(xb1, 0.0, zb), Vector3(xb0, 0.0, zb),
	])


## 一块平顶多边形板：四个 XZ 角 + 底标高 + 顶标高，生成一个封闭棱柱。
##
## 为什么不用 K.box：路和花池的边是斜的，方块拼出来是梯田。
## 为什么不用 K.quad：那是单面片，从侧面看是一条纸 —— 花池需要有厚度。
static func _poly(g: Node3D, corners: PackedVector3Array, y0: float, y1: float,
		mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := corners.size()
	var centroid := Vector3.ZERO
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for p in corners:
		centroid += p
		top.append(Vector3(p.x, y1, p.z))
		bot.append(Vector3(p.x, y0, p.z))
	centroid /= float(n)

	# 顶面 / 底面：扇形三角化（四边形 = 两个三角）
	for i in range(1, n - 1):
		_face(st, top[0], top[i], top[i + 1], Vector3.UP)
		_face(st, bot[0], bot[i + 1], bot[i], Vector3.DOWN)
	# 侧面：外法线用「边中点 − 形心」判断，不靠绕序猜
	for i in n:
		var j := (i + 1) % n
		var mid := (corners[i] + corners[j]) * 0.5
		var hint := Vector3(mid.x - centroid.x, 0.0, mid.z - centroid.z)
		_face(st, bot[i], bot[j], top[j], hint)
		_face(st, bot[i], top[j], top[i], hint)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	# 铺地不投影：一块 5 cm 的板投出来的阴影只是一圈脏边
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)


## 提交一个三角形。hint 是希望法线朝的方向；绕序由它决定，法线写死为平直面法线
## （不用 generate_normals —— 那会把相邻面糊成圆角，山墙就是这么被坑过的）。
##
## 这里没有调 kit._tri：那是共享库的下划线函数，属于内部约定；
## 地图代码不该依赖它，所以这 10 行在自己文件里重写一遍。
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot(hint) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	for v in [a, c, b]:
		st.set_normal(n)
		st.add_vertex(v)


## 花池里的花草。
##
## 池面不能铺一块整绿板：一整片平的草绿在斜视角下就是一块人造草坪
## （第一版就是这样）。这里拆成两层：
##   1. 苔草斑 —— 几十块深浅不一的小薄片，随机角度、随机高低，把平地打碎；
##   2. 草丛和花 —— 才是「花草」本身。
static func _plant_beds(g: Node3D, rng: RandomNumberGenerator,
		z_far: float, z_near: float, top: float) -> void:
	var turf := [
		K.toon(Color("#3d4c26"), {"line": 0.0, "shade": 0.46, "rim": 0.0}),
		K.toon(Color("#54683a"), {"line": 0.0, "shade": 0.50, "rim": 0.0}),
	]
	var grass_a := K.toon(Color("#5d7a3f"), {"line": 0.0, "shade": 0.54, "rim": 0.0})
	var grass_b := K.toon(Color("#4d6635"), {"line": 0.0, "shade": 0.52, "rim": 0.0})
	var leaf := K.toon(Color("#4f6b38"), {"line": 0.0, "shade": 0.54, "rim": 0.0})

	var z := z_far + 0.30
	while z < z_near - 0.26:
		var t := (z_near - z) / (z_near - z_far)
		var half := lerpf(PATH_NEAR_W, PATH_FAR_W, t) * 0.5
		for sign_ in [-1.0, 1.0]:
			var inner: float = CX + sign_ * (half + 0.18)
			# 苔草斑：每排 2 块，薄薄一层贴在草皮上，只做颜色深浅的变化。
			# 厚度压到 1.5 cm 以内 —— 再厚就变成一块块浮在池面上的绿砖
			for k in 2:
				var f := (float(k) + 0.5) / 2.0 + rng.randf_range(-0.12, 0.12)
				var bx: float = inner + sign_ * (BED_DEPTH * f)
				var bz := z + rng.randf_range(-0.10, 0.10)
				var w := rng.randf_range(0.40, 0.70)
				K.box(g, Vector3(w, 0.014, w * rng.randf_range(0.6, 1.0)),
					Vector3(bx, top + 0.028, bz), turf[rng.randi_range(0, 1)],
					Vector3(0.0, rng.randf_range(0.0, 90.0), 0.0), false)
			# 草丛 / 花
			for k in 2:
				var f := float(k) * 0.55 + rng.randf_range(0.0, 0.25)
				var x: float = inner + sign_ * (BED_DEPTH * (0.18 + 0.64 * f))
				var zz := z + rng.randf_range(-0.14, 0.14)
				var foot := Vector3(x, top + 0.02, zz)
				if rng.randf() < 0.62:
					_grass_tuft(g, foot, rng, grass_a, grass_b)
				else:
					_flower(g, foot, rng, leaf)
		z += 0.52

	# 花池四角各一丛矮灌木：给整片花池一个收口，
	# 没有它，草丛在斜视角下会顺着一个方向倒，看不出这是一块围起来的池子
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			var zz: float = z_far + 0.35 if sign_z < 0.0 else z_near - 0.32
			var t := (z_near - zz) / (z_near - z_far)
			var half := lerpf(PATH_NEAR_W, PATH_FAR_W, t) * 0.5
			var x: float = CX + sign_x * (half + 0.30 + BED_DEPTH * 0.55)
			_bush(g, Vector3(x, top, zz), rng, grass_b, leaf)


## 一丛草：三片细长的三棱叶，各歪一个角度。
## 单片用一个 prism —— 一丛三片就是 3 个 mesh，比堆十几个方盒子便宜得多。
## 高度压到 22~34 cm：35~52 cm 的丛在 1 m 外看是一排小金字塔。
static func _grass_tuft(g: Node3D, base: Vector3, rng: RandomNumberGenerator,
		a: Material, b: Material) -> void:
	for i in 3:
		var h := rng.randf_range(0.22, 0.34)
		var yaw := rng.randf_range(0.0, 360.0)
		var lean := rng.randf_range(-20.0, 20.0)
		var off := Vector3(rng.randf_range(-0.07, 0.07), 0.0, rng.randf_range(-0.07, 0.07))
		K.prism(g, Vector3(0.07, h, 0.018),
			base + off + Vector3(0.0, h * 0.5, 0.0), a if i % 2 == 0 else b,
			Vector3(lean, yaw, 0.0), false)


## 一株花：细茎 + 一片叶 + 一颗小花头。
## 花头压到 4~5 cm：第一版 6~7.5 cm，远看像插了一地的棒棒糖。
static func _flower(g: Node3D, base: Vector3, rng: RandomNumberGenerator,
		leaf: Material) -> void:
	var hues := ["#a85b40", "#b8913f", "#bfb7a0", "#7d6f96", "#b06d78"]
	var head := K.toon(Color(hues[rng.randi_range(0, hues.size() - 1)]),
		{"line": 0.0, "shade": 0.64, "rim": 0.0})
	var h := rng.randf_range(0.24, 0.36)
	K.cyl(g, 0.013, h, base + Vector3(0.0, h * 0.5, 0.0), leaf, Vector3.ZERO, 5, -1.0, false)
	K.sphere(g, rng.randf_range(0.038, 0.050), base + Vector3(0.0, h + 0.02, 0.0),
		head, Vector3.ZERO, 7, 0.8, false)
	K.box(g, Vector3(0.12, 0.016, 0.055), base + Vector3(0.05, h * 0.42, 0.0), leaf,
		Vector3(0.0, rng.randf_range(0.0, 180.0), 16.0), false)


## 一丛矮灌木：压扁的球 + 三片叶。花池四角的「收口」用。
static func _bush(g: Node3D, base: Vector3, rng: RandomNumberGenerator,
		body: Material, leaf: Material) -> void:
	K.sphere(g, 0.30, base + Vector3(0.0, 0.20, 0.0), body, Vector3.ZERO, 10, 0.72, false)
	for i in 3:
		var yaw := 60.0 * float(i) + rng.randf_range(-18.0, 18.0)
		K.prism(g, Vector3(0.09, 0.30, 0.018), base + Vector3(0.0, 0.30, 0.0), leaf,
			Vector3(rng.randf_range(-14.0, 14.0), yaw, 0.0), false)


# ---------------------------------------------------------------- 灯光

## 室内单独打灯。屋顶是实心木板，把日光全挡住了；
## 不打灯从门口看进去是一块黑板，第一眼就会以为这是空模型。
##
## 能量压到 0.5~0.8：室内还有 ambient（天空的冷蓝，energy 0.85）在垫底，
## 灯开到 1.5 时墙会叠到 0.9 以上，被 filmic + 饱和 1.22 一推就成荧光黄绿。
## 灯的作用是**加暖**，不是加亮 —— 亮度已经够了，缺的是色温。
static func _lights(g: Node3D) -> void:
	_omni(g, Vector3(CX, 3.7, 327.0), Color("#ffd8a6"), 0.80, 18.0, true)
	_omni(g, Vector3(-131.0, 3.2, 336.2), Color("#ffcf98"), 0.60, 10.0, false)
	_omni(g, Vector3(-115.8, 5.0, 327.5), Color("#ffd8a6"), 0.50, 9.0, false)
	# 门口补一盏：玩家从亮处走进来，门内侧是最先看到的一块墙，
	# 这里偏暗的话第一印象就是「屋里没开灯」
	_omni(g, Vector3(CX, 3.4, 319.6), Color("#ffd8a6"), 0.55, 12.0, false)


static func _omni(g: Node3D, pos: Vector3, col: Color, energy: float, rng: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	# 室内三盏灯，阴影只开一盏 —— 全部开阴影会让这块区域的阴影像脏水
	l.omni_attenuation = 1.2
	g.add_child(l)


# ---------------------------------------------------------------- 碰撞

## 视觉 + 碰撞一体。和 city_wall 的 _solid 同义：
## 只接受轴对齐的盒子，转过的墙自己算碰撞朝向不划算。
static func _solid(g: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	K.box(g, size, pos, mat)
	solid_col(g, size, pos)


## 只加碰撞，不加视觉。给「外面已经画好了、但需要挡住玩家」的部件用。
static func solid_col(g: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)
	g.add_child(body)
