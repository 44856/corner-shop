extends Node3D
## 异世界平原 —— 穿越后醒来的第一个场景
##
## 和 scenes/main.tscn（雨夜便利店）没有任何关系：独立的天空、光照、地形。
## 本工程不在编辑器里摆节点，所以这里一切都是运行时生成的：
## 天空 / 太阳 / 土路平原 / 城镇地面 / 远山 / 玩家 / 狗。
##
## 地形这一版不再有草：整片大地都是脚下那种压实的土路。
## 一条路从脚下一路铺到 300m 外的城镇入口，再往里渐变成方石铺装和大理石广场。
## 城墙和城镇建筑还没做 —— 这块地只是先把「将来城镇站哪儿」铺出来。
##
## 视觉目标：二次元中世纪晴天 —— 明亮、饱和、干净。
## 和雨夜场景的冷蓝低照度形成强反差，这本身就是「穿越」的信号。
##
## 文件名仍叫 grassland 是因为 scenes/grassland.tscn 与 opening_flow 都引用了它，
## 改名要动协作者的文件，等确认后再一起改。

const K := preload("res://scripts/kit.gd")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const PlayerController := preload("res://scripts/player_controller.gd")
const Dog := preload("res://scripts/dog.gd")
const CityWall := preload("res://scripts/city_wall.gd")
const Guild := preload("res://scripts/guild.gd")
const NpcGuard := preload("res://scripts/npc_guard.gd")
const DialogueRunnerScript := preload("res://scripts/dialogue/dialogue_runner.gd")
## HUD / 交互中枢直接复用便利店可玩场景那一套（feature/store-walk-in）：
## 两个场景共用同一份控件与同一套「谁最近就提示谁」的逻辑，
## 换成自己的颜色和文案即可，不再各写一套。
const Hud := preload("res://scripts/hud.gd")
const Hub := preload("res://scripts/interaction_hub.gd")

## 主角名。剧本里的 {NAME} 占位符就替换成它。
## 将来接「取名系统」时，只要在进入场景前把 dialogue.set_player_name() 调一次，
## 或者改这一个常量 —— 剧本文件不用动
const PLAYER_NAME := "旅人"

const SCENE_ID := &"grassland"

## 地面边长（米）。整片地形都是土路那种平地，所以尺寸只需盖住「路 + 城镇地面」，
## 剩下的交给远景地面。
## 1500（±750）不是随便给的：城镇地面铺到 630，而远景地面那份材质**不算铺装**
## （省 6 次 fbm），如果主地面只到 600，600~630 那截铺装就会突然变回土，
## 而且正好落在 6cm 的接缝台阶上，看起来像被人切了一刀
const GROUND_SIZE := 1500.0
## 远景地面：玩法地面之外还有一层更大的平面，只为了不让人看见「地板边缘」。
## 它比玩法地面低 6cm，两层面片不会在交界上打架。
## 4km（±2000）配 0.0011 的雾：边缘处只剩一成清晰度，看不见断口
const FAR_GROUND_SIZE := 4000.0
const FAR_GROUND_Y := -0.06

## 主路：从脚下一直铺到城镇入口（300m）。
## 上一版是 200m，这次按要求加长一半；路的尽头直接接铺装，不再有「草」这层过渡
const ROAD_LENGTH := 300.0
## 路面半宽（米）。比上一版略宽，因为两侧不再有草，路太细会显得地广人稀
const ROAD_HALF_WIDTH := 3.2
## 路的横向弯度：x = bend·sin(π·z/ROAD_LENGTH)，先弯出去再回到 x=0
const ROAD_BEND := 9.0

## 分区：出生点一侧是草地，往城镇方向过渡成压实的土面（平地）。
## 120m 是按「醒来后往前走大约 28 秒才踩到泥地」定的 ——
## 太短就来不及建立「这是一片草原」的印象，太长则快到城门了还是草地。
const GRASS_Z1 := 120.0
## 草地→平地的过渡带宽度。45m 是让边界看起来是「慢慢没了」而不是「一条线」
const GRASS_FADE := 45.0

## 城镇地面（方石铺装）：以 z 300 为入口，向 +Z 铺 330m，横向 ±150m。
## 进深给到 330 是为了让「城镇地面的尽头」退到 1100m 外，
## 否则站在广场上会看到地平线横着一条土黄带，像铺装被一刀切了。
## 城墙将来立在这块地的边缘，所以先按「将来装得下」的尺寸铺
const PAVED_CENTER := Vector2(0.0, 465.0)
const PAVED_HALF := Vector2(150.0, 165.0)
## 大理石：进镇 50m 后开始渐变，到 130m 处完全是石板。
## 80m 的渐变带是照「走过去能不能感觉到」定的：按 4.2 m/s 是 19 秒，
## 再长就变成「走着走着颜色不知不觉变了」，玩家不会注意到这是一段过渡
const MARBLE_Z0 := 350.0
const MARBLE_Z1 := 430.0
## 大理石广场的横向半宽，比铺装窄 12m，两侧留一圈方石当路缘
const MARBLE_HALF_W := 138.0
## 醒来的补间时长（秒）
const WAKE_SECONDS := 2.0
## 躺下时模型需要抬高多少米，身体背面才刚好贴地（实测值，见 _play_wake_up）
const LIE_LIFT := 0.19
## 躺下的角度。文档写 −80°，但实测这个模型枢轴在脚底，−80° 会留下 10° 倾斜：
## 小腿着地、头和脚各自悬空 0.3m，看起来像在浮空。−90° 才是真正平躺
const LIE_PITCH_DEG := -90.0

var player: CharacterBody3D
var dog: Node3D
## 守卫的交互半径（米）。守卫站在 22m 宽的门洞里，玩家从大路上斜着走过来，
## 3.2m 时常要贴到脸上才出提示；4.0m 才是「站在他跟前」的自然距离
const GUARD_TALK_RADIUS := 4.0

## 城门两个守卫，元素形如 {"node": Node3D, "dialogue": 剧本路径}
var guards: Array = []
## 对话状态机（不是 autoload，由本场景持有）
var dialogue: Node
var hud: CanvasLayer
var hub: Node
## 当前区域文案（只在变化时才写 HUD）
var _zone := ""
## 「城门就在前面」只提示一次
var _gate_tip_shown := false
var _env: Environment
var _sun: DirectionalLight3D
## 醒来补间要两秒，远晚于 SceneRouter 清空到达上下文的时刻；
## 所以在 _ready 里先存一份，后面判断「是不是死过来的」只看它。
var _arrival: Dictionary = {}


func _ready() -> void:
	SceneRouter.bind_scene(SCENE_ID)
	_arrival = SceneRouter.consume_arrival()

	_setup_environment()
	_setup_sun()
	_setup_ground()
	_setup_hills()
	_setup_city_wall()
	_setup_guild()
	_setup_gate_npcs()
	_setup_guild_clerks()
	_setup_player()
	_setup_dog()
	_setup_dialogue()
	_setup_hud()
	_setup_interaction()
	_play_wake_up()


# ---------------------------------------------------------------- 天空与雾

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#7fb8e8")        # 天蓝
	sky_mat.sky_horizon_color = Color("#e6f1f8")    # 地平线接近白
	sky_mat.sky_curve = 0.11                        # 低一点，蓝白过渡更缓
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_horizon_color = Color("#dbe7d2")
	sky_mat.ground_bottom_color = Color("#8aa878")
	sky_mat.ground_curve = 0.06
	sky_mat.sun_angle_max = 5.0
	sky_mat.sun_curve = 0.08
	sky_mat.use_debanding = true

	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128   # 低配友好，草原不需要精确反射

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	# 淡雾：主要目的是掩盖远处地面的硬边缘，不是做气氛。
	# 这一版地面全是土，土黄被雾一漂就变成「盐碱地」，所以比上一版淡得多：
	#   0.0024 时 300m 处只剩五成，大理石广场整个糊进白里（实测过，纯白一片）；
	#   0.0011 时 300m 处仍有七成、600m 处四成，广场和方石能看清，
	#   而 2000m 的远景边缘只剩一成，边缘照样藏得住。
	# 雾色也从接近白压到灰，避免和过曝的石板叠在一起；
	# 别再带绿 —— 地面已经没有草了，绿雾会让远处的石板发青
	env.fog_enabled = true
	env.fog_light_color = Color("#d2d5cb")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	# 二次元要饱和。SSAO / SSR / 体积雾全部关掉 —— “好渲染优先”
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.04
	env.adjustment_brightness = 1.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	_env = env


func _setup_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#fff4e0")     # 暖白，上午的太阳
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-50.0, 42.0, 0.0)   # 角度高
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.03
	sun.light_specular = 0.0
	add_child(sun)
	_sun = sun


# ---------------------------------------------------------------- 地形

func _setup_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	pm.subdivide_width = 0          # 纯平地形，细分只会浪费三角形
	pm.subdivide_depth = 0
	mi.mesh = pm
	mi.material_override = _ground_material(true)
	add_child(mi)

	# 碰撞：和视觉平面同尺寸的薄盒子，顶面正好在 y = 0
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	col.shape = box
	col.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(col)
	add_child(body)

	_setup_far_ground(_ground_material(false))


## 玩法地面之外的一层大平面。
## 1200m 的地面在 ±600m 处有一条硬边，站直了看就是「地到这儿断了」；
## 这里铺一层 3km、低 6cm 的平面接着，远处还有雾，边界就完全藏住了。
## 材质与主地面**同源同参数**，土路直接跨过接缝继续延伸 —— 没有分界线。
## 同时给它碰撞：不然走出 600m 会直接掉下去（城镇将来要往外扩，正好用得上）。
func _setup_far_ground(mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "FarGround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(FAR_GROUND_SIZE, FAR_GROUND_SIZE)
	mi.mesh = pm
	mi.material_override = mat
	mi.position.y = FAR_GROUND_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "FarGroundBody"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FAR_GROUND_SIZE, 2.0, FAR_GROUND_SIZE)
	col.shape = box
	col.position = Vector3(0.0, FAR_GROUND_Y - 1.0, 0.0)
	body.add_child(col)
	add_child(body)


## 土路 / 方石铺装 / 大理石全部由 shader 按世界坐标算（见 shaders/ground.gdshader）。
## 交给 shader 而不是叠面片的原因：铺装要铺到 500m 外，那个距离上深度精度只有几厘米，
## 叠面必然闪面；而且叠出来的边缘是硬切，看不出「土路走进去慢慢变成石板」。
##
## paving 只控制「要不要算铺装」：远景地面永远看不到城镇地面（它在 ±1500 之外），
## 关掉能省掉 6 次 fbm —— 远景地面几乎铺满整个屏幕，这才是帧率的来源。
func _ground_material(paving: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("road_z1", ROAD_LENGTH)
	m.set_shader_parameter("road_half_width", ROAD_HALF_WIDTH)
	m.set_shader_parameter("road_bend", ROAD_BEND)
	m.set_shader_parameter("road_end_z", ROAD_LENGTH)
	m.set_shader_parameter("grass_z1", GRASS_Z1)
	m.set_shader_parameter("grass_fade", GRASS_FADE)
	m.set_shader_parameter("paved_center", PAVED_CENTER)
	m.set_shader_parameter("paved_half", PAVED_HALF)
	m.set_shader_parameter("marble_z0", MARBLE_Z0)
	m.set_shader_parameter("marble_z1", MARBLE_Z1)
	m.set_shader_parameter("marble_half_w", MARBLE_HALF_W)
	m.set_shader_parameter("paving_amount", 1.0 if paving else 0.0)
	return m


## 远景缓丘：几块压扁的大球，只露出顶部，用来收住地平线。
## 没有它们，一大片土色平原会一路平到雾里，看不出空间纵深。
##
## 位置有一个硬约束：**不能压进城镇地面**（x ±150、z 300~560）。
## 这些球是半径几百米、贴地压扁的穹顶，只要足迹碰到那块地，
## 就会从广场中间长出一堵缓坡，把将来要立城墙的地方顶掉。
## 所以 +Z 正前方一排全部放到 700m 以外，两侧和后方也退到 500m 开外。
##
## 顺带一个换算：K.sphere 把球压成高度 h，球心在 y = -1，
## 所以山顶实际高度是 h/2 - 1。想要 90m 的山，h 得给 182。
func _setup_hills() -> void:
	# 山的颜色要压得比「看起来对的绿色」更深一档：
	# 它们全在 300m 以外，隔着雾出现在屏幕上，本来就已经被漂白了一半
	var far := K.toon(Color("#6e8d5b"), {"line": 0.0, "shade": 0.62, "rim": 0.0})
	var near := K.toon(Color("#5f8049"), {"line": 0.0, "shade": 0.60, "rim": 0.0})
	var specs := [
		# 左右近处：从起点看得到的缓丘，压住两侧地平线
		{"pos": Vector3(-330.0, -1.0, 130.0), "r": 110.0, "h": 44.0, "mat": near},
		{"pos": Vector3(345.0, -1.0, 90.0), "r": 115.0, "h": 46.0, "mat": near},
		# 左右远处：更大更淡，和上面的缓丘错开高度，才不会连成一条环
		{"pos": Vector3(-700.0, -1.0, 300.0), "r": 420.0, "h": 155.0, "mat": far},
		{"pos": Vector3(760.0, -1.0, 260.0), "r": 440.0, "h": 175.0, "mat": far},
		# 身后
		{"pos": Vector3(-320.0, -1.0, -210.0), "r": 130.0, "h": 50.0, "mat": near},
		{"pos": Vector3(310.0, -1.0, -300.0), "r": 125.0, "h": 48.0, "mat": near},
		{"pos": Vector3(30.0, -1.0, -430.0), "r": 145.0, "h": 54.0, "mat": near},
		{"pos": Vector3(-560.0, -1.0, -520.0), "r": 400.0, "h": 145.0, "mat": far},
		{"pos": Vector3(520.0, -1.0, -600.0), "r": 380.0, "h": 135.0, "mat": far},
		# 正前方远处：城镇背后的一道山脊。这一层不挡路，
		# 只有在薄雾里的一抹淡影，作用是让 +Z 方向也有个收口
		{"pos": Vector3(-820.0, -1.0, 780.0), "r": 480.0, "h": 205.0, "mat": far},
		{"pos": Vector3(880.0, -1.0, 760.0), "r": 460.0, "h": 195.0, "mat": far},
	]
	for s in specs:
		var r: float = s["r"]
		var h: float = s["h"]
		K.sphere(self, r, s["pos"], s["mat"], Vector3.ZERO, 20, h / (r * 2.0), false)


# ---------------------------------------------------------------- 城墙

## 沿城镇地基的四边围一圈城墙，城门开在道路正对的 z=300、x=0。
## 地基范围（x±150、z 300~630）是硬约束，改了铺装尺寸这里也要跟着改。
func _setup_city_wall() -> void:
	CityWall.build(self)


# ---------------------------------------------------------------- 冒险者公会

## 城镇西南角的冒险者公会。体量、门窗、楼梯全部在 guild.gd 里，
## 这里只负责「把它放到场景里」—— 布局常量在 guild.gd 上是公开的，
## 摆 NPC 和注册交互点直接读，不在这里重复写一遍坐标。
func _setup_guild() -> void:
	Guild.build(self)


# ---------------------------------------------------------------- 公会接待

## 前台后面站两个人。
##
## 复用 npc_guard.gd：同一套 Biped 骨架、同一套站姿与微动，只是换了高度和站位。
## 身高回到 1.8 m 左右而不是城门守卫的 2.3 m —— 前台是文职，
## 比守卫矮一截反而能一眼读出「谁是站岗的、谁在屋里办公」。
##
## 两人一个偏办公（guard_a，站得直）、一个偏松弛（guard_b，重心压一只脚），
## 相位再错开 5.1 秒，免得两个人同步呼吸。
func _setup_guild_clerks() -> void:
	var specs := [
		{"name": "ClerkIsaac", "path": "res://assets/npc/isaac.glb",
			"pos": Guild.CLERK_POS[0], "stance": "guard_a", "phase": 0.0,
			"face": Vector3(0.12, 0.0, -1.0), "h": 1.80},
		{"name": "ClerkSkadi", "path": "res://assets/npc/skadi.glb",
			"pos": Guild.CLERK_POS[1], "stance": "guard_b", "phase": 5.1,
			"face": Vector3(-0.10, 0.0, -1.0), "h": 1.76},
	]
	for s in specs:
		var npc := NpcGuard.new()
		npc.name = s["name"]
		npc.model_path = s["path"]
		npc.position = s["pos"]
		npc.face_dir = s["face"]
		npc.stance = s["stance"]
		npc.phase_offset = s["phase"]
		npc.target_height = s["h"]
		# 前台空间小，注视半径收到 3.5 m：站在大厅另一头也扭头看人，
		# 会像两个监控摄像头
		npc.notice_radius = 3.5
		add_child(npc)
		# 进同一个列表，这样转头逻辑（_update_guard_attention）一并覆盖
		guards.append({"node": npc, "dialogue": "", "clerk": true})


# ---------------------------------------------------------------- 城门 NPC

## 两个守卫站在城门内侧，面朝城外（-Z），等着玩家从大路上走过来。
##
## 素材来自 3Dmodel 那套 Blender 角色，经 Blender 2.92 转成 glb。
## 模型导进来是 A-pose（手臂外张 37°），站姿由 npc_guard.gd 用骨骼掰出来，
## 这里只负责摆位置、朝向和用哪套站姿。
##
## 位置 (±7, 0, ≈303) 是照城门洞（±11）定的：站在洞里、贴着门柱，
## 既不会挡住中间的路，玩家从大路上抬头就能看见。
##
## 三个人为的「不整齐」——刻意的：两个人站得一模一样、连呼吸都同步，
## 比姿势本身更容易被一眼看出是摆件。所以：
##   - 前后错开 1 米（一个略靠前、一个略靠后）
##   - 面朝方向各偏 12° 左右，都略朝路中线（像在留意进出的人）
##   - 用不同站姿预设 + 微动相位错开 3.7 秒
func _setup_gate_npcs() -> void:
	var specs := [
		{"name": "GuardIsaac", "path": "res://assets/npc/isaac.glb",
			"pos": Vector3(-7.0, 0.0, 302.4), "stance": "guard_a", "phase": 0.0,
			"face": Vector3(0.22, 0.0, -1.0),
			"h": 1.946 * 1.2,
			"dialogue": "res://dialogue/guard_isaac_01.txt"},
		{"name": "GuardSkadi", "path": "res://assets/npc/skadi.glb",
			"pos": Vector3(7.0, 0.0, 303.5), "stance": "guard_b", "phase": 3.7,
			"face": Vector3(-0.18, 0.0, -1.0),
			"h": 1.973 * 1.2,
			"dialogue": "res://dialogue/guard_skadi_01.txt"},
	]
	for s in specs:
		var npc := NpcGuard.new()
		npc.name = s["name"]
		npc.model_path = s["path"]
		npc.position = s["pos"]
		npc.face_dir = s["face"]
		npc.stance = s["stance"]
		npc.phase_offset = s["phase"]
		# 目标身高 = 原始身高 × 1.2（等比放大）。
		# 归一化放在 npc_guard.gd 里做：那套模型的单位链路不可靠，
		# 按「这个人应该多高」反推缩放比，比写死一个系数稳妥。
		npc.target_height = s["h"]
		add_child(npc)
		guards.append({"node": npc, "dialogue": s["dialogue"]})


# ---------------------------------------------------------------- 玩家

func _setup_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	player.position = Vector3(0.0, 0.02, 0.0)
	# 角色贴图必须压暗，否则脸上什么都看不见。
	#
	# 这个场景的 ambient 是照「明亮草原」调的：天空 radiance 约 0.7，乘
	# ambient_light_energy 0.85 之后还要再乘 PI，落到着色器里约 1.9 倍 albedo；
	# 再加 1.2 的日光，总光照是三倍左右。而 VRoid 的贴图本身就接近 0.8，
	# 一乘就直接顶到 1.0 以上 —— tonemap 把皮肤、眼白、虹膜全压成同一片白，
	# 远看就是「一张没有五官的脸」。
	#
	# 0.66 是实测出来的：0.8 时眼白仍和皮肤糊在一起；0.5 时整件衣服发灰、
	# 像蒙了层土。0.66 刚好压回线性 0.4 左右，皮肤有明暗、虹膜能分出来。
	player.actor_tint = Color(0.66, 0.67, 0.70)
	# 暗部下限同步降到 0.42：只降 albedo 不降 shade_floor，脸会变成一块平的浅色板，
	# 五官照样读不出来 —— 靠的是「明暗差」，不是「整体亮度」
	player.actor_shade_floor = 0.42
	# 边缘光收一半：白天场景的轮廓本来就是暗的，再加蓝边只会让头显得发光
	player.actor_rim_strength = 0.04
	add_child(player)


# ---------------------------------------------------------------- 醒来

## 没有动画资源，用补间做：
##   模型绕 X 轴 −90°（平躺）+ 抬高让背贴地 → 2 秒内转正、落回 0
##   相机支点同时从 0.4m 升到正常跟随高度
## 补间打在**模型子节点**上，不动 CharacterBody3D —— 后者归物理管，抢 transform 会打架。
##
## 两个数值是实测出来的，不是拍脑袋：
##   - 角度：文档写 −80°，但这个模型的枢轴在脚底（T-pose 包围盒 min_y = 0）。
##     绕脚底转 −80° 等于把身体当一块斜 10° 的木板，只有小腿着地、头悬空 0.3m，
##     看起来像浮空；−90° 才是背贴地。
##   - 高度：文档写「position.y 略低于 0」，但绕脚底转之后身体背面会落到 y = −0.19，
##     反而整个埋进草里。实测 +0.19 正好让背面贴地（min_y = 0）。
func _play_wake_up() -> void:
	var model: Node3D = player.actor
	player.input_locked = true

	model.rotation_degrees.x = LIE_PITCH_DEG
	model.position.y = LIE_LIFT
	player.cam_rig.position.y = 0.4

	# 开场镜头略偏一点角度（绕 Y 轴 +26°），否则正后方只能看到躺着的人的头顶，
	# 看不出「躺」这个事实。醒来过程中镜头同时摆正。
	var base_yaw: float = deg_to_rad(player.start_yaw_deg)
	player.cam_rig.rotation.y = base_yaw + deg_to_rad(26.0)

	var tw := create_tween().set_parallel(true) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", 0.0, WAKE_SECONDS)
	tw.tween_property(model, "position:y", 0.0, WAKE_SECONDS)
	tw.tween_property(player.cam_rig, "position:y", player.cam_height, WAKE_SECONDS)
	tw.tween_property(player.cam_rig, "rotation:y", base_yaw, WAKE_SECONDS)
	tw.chain().tween_callback(_on_wake_finished)


func _on_wake_finished() -> void:
	player.input_locked = false
	# 从加油站「死」过来的那一趟，第一小时不接任务、不解释设定，
	# 只按感官顺序认识这具身体和新世界。正常从商店街进草原则不触发。
	# 判据是路由给的 arrival 上下文，不再是 root 上一个全局 meta ——
	# meta 谁都能写、也谁都会忘删，第二次进草原就会重播这段。
	if _arrival.get("from_scene", &"") == &"gas_station" \
			and _arrival.get("mode", &"") == &"story":
		_story_arrival_echo()


## 嗅觉 → 听觉 → 痛觉 → 视觉，最后才是语言。
## 每一条都留 4 秒多的空白，让玩家自己把「这不是原来的身体」拼出来，
## 而不是由旁白告诉他。最后一句是别人看见他的方式：不是欢迎，是一句侧写。
func _story_arrival_echo() -> void:
	await get_tree().create_timer(1.2).timeout
	hud.toast("先闻到草。湿土、太阳晒过的草梗，还有一点铁锈味。", 4.4)
	await get_tree().create_timer(4.8).timeout
	hud.toast("然后是声音。风、远处的钟、有人在笑。", 4.2)
	await get_tree().create_timer(4.6).timeout
	hud.toast("最后才是疼。肩膀、肋侧，像被从很高的地方放下来。", 4.2)
	await get_tree().create_timer(4.6).timeout
	hud.toast("你低头看自己的手。手指比你记得的长。有人对你说话，词句先是一串噪声，"
		+ "然后忽然拼成意思。", 5.2)
	await get_tree().create_timer(5.4).timeout
	hud.toast("一个路过的人看了你一眼，没有停下：'你偶尔用看怪物的眼神看熟悉的东西。'", 5.6)


# ---------------------------------------------------------------- 狗

## 坐在玩家右侧约 1.5m。玩家初始朝向 +Z，面朝 +Z 时右手边是 −X。
func _setup_dog() -> void:
	dog = Dog.new()
	dog.name = "Dog"
	dog.position = Vector3(-1.5, 0.0, 0.15)
	add_child(dog)
	var to_player := player.global_position - dog.global_position
	to_player.y = 0.0
	dog.rotation.y = atan2(to_player.x, to_player.z)


# ---------------------------------------------------------------- 对话

## 对话状态机挂在本场景下，而不是 autoload：
## 任务书禁止改 project.godot，而 autoload 必须写在那里；
## 退一步换来的是「对话归属哪个场景由场景自己决定」。
##
## 冻结玩家不写在对话系统里：runner 只发信号，由场景决定怎么响应。
## 这样将来别的场景想让 NPC 说话时不冻结玩家，改场景就行，不用改对话系统。
func _setup_dialogue() -> void:
	dialogue = DialogueRunnerScript.new()
	dialogue.name = "Dialogue"
	dialogue.player_name = PLAYER_NAME
	add_child(dialogue)
	dialogue.dialogue_started.connect(_on_dialogue_started)
	dialogue.dialogue_finished.connect(_on_dialogue_finished)

	# 狗只拿到两个引用，不自己去树上找 —— 避免反向依赖
	dog.bind_interaction(player, dialogue)


func _on_dialogue_started() -> void:
	# 复用「醒来」那套冻结：清空水平意图但保留重力与贴地，
	# 不像 set_physics_process(false) 那样把人冻在半空
	player.input_locked = true
	# 对话期间收起交互提示：不然 HUD 底部那条「按 E 和守卫说话」
	# 会和对话框叠在一起，而且这时候按 E 只是在翻页
	if hub != null:
		hub.enabled = false
		hud.hide_prompt()
		hud.hide_toast()


func _on_dialogue_finished() -> void:
	player.input_locked = false
	if hub != null:
		hub.enabled = true


# ---------------------------------------------------------------- HUD

## HUD 复用便利店那套控件，只换文案与配色。
## 必须在 add_child 之前赋值 —— 控件是 HUD 的 _ready() 里建的。
##
## 白天场景用暖金强调色：霓虹绿在正午的日光下会发灰，
## 而且这是异世界不是便利店，颜色不该带过来。
func _setup_hud() -> void:
	hud = Hud.new()
	hud.name = "HUD"
	hud.title_text = "ISEKAI"
	hud.subtitle_text = "异世界 · 草原"
	hud.zone_text = "草原"
	hud.accent_color = Color("#ffd39a")
	hud.controls = [
		["WASD", "移动"],
		["Shift", "快跑"],
		["空格", "跳"],
		["鼠标", "转视角"],
		["E", "交互"],
		["Tab", "释放鼠标"],
	]
	add_child(hud)
	# HUD 自带一层全黑遮罩（Alpha = 1）。不主动淡入的话，整块屏幕就是黑的
	hud.fade_in(WAKE_SECONDS)


# ---------------------------------------------------------------- 交互

## 交互中枢：狗和两个守卫统一注册到这里，谁离得最近就提示谁、按 E 触发谁。
## 判定「能不能说话」仍然留在各自身上（dog.talk()），中枢只管选目标与分发按键。
func _setup_interaction() -> void:
	hub = Hub.new()
	hub.name = "Interaction"
	add_child(hub)
	hub.bind(player, hud)

	# 狗不再自己管按键和头顶提示，改由中枢统一出 —— 否则一次 E 会被两边各处理一次
	dog.self_interaction = false
	hub.add_target(dog.global_position, dog.talk_radius, "跟狗打个招呼", dog.talk)

	for g in guards:
		var npc: Node3D = g["node"]
		# 目标点抬到胸口高度：距离判定只取水平分量，抬高只为将来画 3D 提示时好看
		var pos: Vector3 = npc.global_position + Vector3(0.0, 1.1, 0.0)
		if bool(g.get("clerk", false)):
			# 接待员的台词还没写，先给一句兜底；换成对话只需要改这个回调
			hub.add_target(pos, 3.0, "和接待员说话",
				func() -> void: hud.toast("接待员正忙着整理名册，暂时没空理你。", 3.0))
		else:
			var path: String = g["dialogue"]
			hub.add_target(pos, GUARD_TALK_RADIUS, "和守卫说话",
				func() -> void: _talk_guard(path))

	# 公会的两块任务板。内容是空的，但交互点先接上 ——
	# 以后填任务文案只改回调，不动布局
	for p in Guild.BOARD_POS:
		hub.add_target(p + Vector3(0.0, 1.4, 0.0), Guild.BOARD_RADIUS, "查看任务板",
			func() -> void: hud.toast("任务板还是空的。公会还没正式开张。", 3.0))


func _talk_guard(path: String) -> void:
	if dialogue == null or not is_instance_valid(dialogue):
		return
	if dialogue.is_active():
		return
	dialogue.start(path)


# ---------------------------------------------------------------- 区域提示

## 按玩家所在位置更新 HUD 右上角的区域标签。
## 只在文案变化时写一次 —— set_zone 每次都新建主题覆盖，逐帧调用没必要。
func _process(_delta: float) -> void:
	if hud == null or player == null or not is_instance_valid(player):
		return
	var z: float = player.global_position.z
	var p: Vector3 = player.global_position
	var zone := "草原"
	if p.x >= Guild.X0 - 0.4 and p.x <= Guild.X1 + 0.4 \
			and p.z >= Guild.Z0 and p.z <= Guild.Z1 + 0.4:
		zone = "冒险者公会 · 大厅"
	elif z >= MARBLE_Z1:
		zone = "广场 · 大理石"
	elif z >= ROAD_LENGTH:
		zone = "城门内 · 方石广场"
	elif z >= GRASS_Z1:
		zone = "官道"
	if zone != _zone:
		_zone = zone
		hud.set_zone(zone, z >= GRASS_Z1)

	# 快到城门时提示一次，让玩家知道前面有东西可看
	if not _gate_tip_shown and z >= ROAD_LENGTH - 70.0:
		_gate_tip_shown = true
		hud.toast("前面就是城门。走近守卫可以搭话。", 4.0)

	_update_guard_attention()


## 让离得最近的那个守卫转头看玩家。
##
## 站岗的人不会一直盯着正前方 —— 有人走到跟前会看一眼，这才是「有人」。
## 判定放在这里而不是 npc_guard 里，是因为「谁离玩家最近」只有场景说得清；
## 守卫本身只负责「看向某点」这件事。
func _update_guard_attention() -> void:
	if guards.is_empty():
		return
	var p: Vector3 = player.global_position + Vector3(0.0, 1.0, 0.0)
	var near: Node3D = null
	var best := 1e9
	for g in guards:
		var npc: Node3D = g["node"]
		if not is_instance_valid(npc):
			continue
		var d: float = npc.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			near = npc
	for g in guards:
		var npc: Node3D = g["node"]
		if not is_instance_valid(npc):
			continue
		if npc == near and best <= npc.notice_radius:
			npc.look_at_point(p)
		else:
			npc.look_away()
