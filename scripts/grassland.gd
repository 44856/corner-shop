extends Node3D
## 异世界草原 —— 穿越后醒来的第一个场景
##
## 和 scenes/main.tscn（雨夜便利店）没有任何关系：独立的天空、光照、地形。
## 本工程不在编辑器里摆节点，所以这里一切都是运行时生成的：
## 天空 / 太阳 / 400m 草原 / 远景缓丘 / 玩家 / 狗。
##
## 视觉目标：二次元中世纪晴天 —— 明亮、饱和、干净。
## 和雨夜场景的冷蓝低照度形成强反差，这本身就是「穿越」的信号。

const K := preload("res://scripts/kit.gd")
const PlayerController := preload("res://scripts/player_controller.gd")
const Dog := preload("res://scripts/dog.gd")
const DialogueRunnerScript := preload("res://scripts/dialogue/dialogue_runner.gd")

## 主角名。剧本里的 {NAME} 占位符就替换成它。
## 将来接「取名系统」时，只要在进入场景前把 dialogue.set_player_name() 调一次，
## 或者改这一个常量 —— 剧本文件不用动
const PLAYER_NAME := "旅人"

## 地面边长（米）。文档要求 400 × 400，足够走，且配合淡雾藏住边缘
const GROUND_SIZE := 400.0
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

	# 淡雾：主要目的是掩盖 400m 平面的硬边缘，不是做气氛。
	# 颜色带一点绿，远处草地才不会褪成一片白
	env.fog_enabled = true
	env.fog_light_color = Color("#d6e6de")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
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
	mi.material_override = _ground_material()
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


## 绿色草地材质。整块纯色会像塑料，所以用 NoiseTexture2D 做 albedo：
## 噪声通过 Gradient 映射到「偏暗的绿 ↔ 偏亮的绿」，只做明暗起伏，不压暗整体。
func _ground_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 3

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.80, 0.90, 0.72))
	ramp.set_color(1, Color(1.00, 1.00, 0.94))

	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	tex.color_ramp = ramp

	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#6f9a4e")
	m.albedo_texture = tex
	# 400m 的平面上铺约 25 个循环，每块 16m，配合噪声频率形成大块色差
	m.uv1_scale = Vector3(25.0, 25.0, 25.0)
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## 远景缓丘：几块压扁的大球，只露出顶部，用来收住地平线。
## 没有它们，400m 平面看起来就是一块悬浮的板子。
func _setup_hills() -> void:
	var far := K.toon(Color("#8cad74"), {"line": 0.0, "shade": 0.62, "rim": 0.0})
	var near := K.toon(Color("#7ea265"), {"line": 0.0, "shade": 0.60, "rim": 0.0})
	var specs := [
		{"pos": Vector3(-150.0, -1.0, 120.0), "r": 95.0, "h": 17.0, "mat": far},
		{"pos": Vector3(60.0, -1.0, 175.0), "r": 120.0, "h": 21.0, "mat": far},
		{"pos": Vector3(180.0, -1.0, 40.0), "r": 105.0, "h": 15.0, "mat": far},
		{"pos": Vector3(-170.0, -1.0, -90.0), "r": 110.0, "h": 19.0, "mat": near},
		{"pos": Vector3(30.0, -1.0, -185.0), "r": 130.0, "h": 23.0, "mat": far},
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
