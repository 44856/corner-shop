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
const DialogueRunnerScript := preload("res://scripts/dialogue/dialogue_runner.gd")

## 主角名。剧本里的 {NAME} 占位符就替换成它。
## 将来接「取名系统」时，只要在进入场景前把 dialogue.set_player_name() 调一次，
## 或者改这一个常量 —— 剧本文件不用动
const PLAYER_NAME := "旅人"

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
## 对话状态机（不是 autoload，由本场景持有）
var dialogue: Node
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	_setup_environment()
	_setup_sun()
	_setup_ground()
	_setup_hills()
	_setup_player()
	_setup_dog()
	_setup_dialogue()
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


# ---------------------------------------------------------------- 玩家

func _setup_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	player.position = Vector3(0.0, 0.02, 0.0)
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


func _on_dialogue_finished() -> void:
	player.input_locked = false
