extends Node3D

# 雨夜便利店街角 —— 微缩场景
# 鼠标左键拖拽旋转 / 滚轮缩放 / 右键拖拽平移

const Street := preload("res://scripts/street.gd")
const Store := preload("res://scripts/store.gd")
const Props := preload("res://scripts/props.gd")
const K := preload("res://scripts/kit.gd")
const RAIN_SHADER := preload("res://shaders/rain_particles.gdshader")
const RIPPLE_SHADER := preload("res://shaders/rain_ripple.gdshader")
const Actor := preload("res://scripts/actor.gd")
const Cutscene := preload("res://scripts/cutscene.gd")

var yaw := deg_to_rad(26.0)
var pitch := deg_to_rad(14.5)
var dist := 17.0
var target := Vector3(0.0, 1.2, -0.95)

var _yaw_t := yaw
var _pitch_t := pitch
var _dist_t := dist
var _target_t := target

var cam: Camera3D

## 画面倾斜（弧度）。开场动画在穿越那一段会把它推向一个角度，做出"世界歪了"的感觉。
var roll := 0.0

# 给开场动画留的引用（cutscene.gd 要控制灯光、环境、角色和雨）
var _env: Environment
var _moon: DirectionalLight3D
var _fill: DirectionalLight3D
var _actor: Node3D


func _ready() -> void:
	_setup_environment()
	Street.build(self)
	Store.build(self)
	Props.build(self)
	_setup_lights()
	_setup_camera()
	_setup_rain()
	_setup_rain_ripples()
	_setup_actors()

	if "--shot" in OS.get_cmdline_user_args():
		_take_shots()
	else:
		_start_cutscene()


## 播开场剧情动画
func _start_cutscene() -> void:
	var cs := Cutscene.new()
	add_child(cs)
	cs.setup(self, _actor)
	cs.play()


# ---------------------------------------------------------------- 环境

func _setup_environment() -> void:
	var env := Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.026, 0.038, 0.082)
	sky_mat.sky_horizon_color = Color(0.045, 0.065, 0.115)
	sky_mat.sky_curve = 0.18
	sky_mat.ground_horizon_color = Color(0.035, 0.045, 0.07)
	sky_mat.ground_bottom_color = Color(0.014, 0.018, 0.028)
	sky_mat.sun_angle_max = 0.0
	sky_mat.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.12

	env.ssao_enabled = true
	env.ssao_radius = 0.85
	env.ssao_intensity = 2.2
	env.ssao_power = 1.7
	env.ssao_light_affect = 0.3

	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.2
	env.ssr_depth_tolerance = 0.35

	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.05
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.85
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.12, 0.2)
	env.fog_light_energy = 0.5
	env.fog_density = 0.012
	env.fog_sky_affect = 0.25

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.55, 0.62, 0.8)
	env.volumetric_fog_length = 32.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 1.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env


func _setup_lights() -> void:
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("#9db4ff")
	moon.light_energy = 0.55
	moon.rotation_degrees = Vector3(-46, 38, 0)
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 40.0
	moon.shadow_bias = 0.02
	moon.light_specular = 0.4
	add_child(moon)
	_moon = moon

	# 冷色补光，勾出模型边缘
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#4d6ea8")
	fill.light_energy = 0.14
	fill.rotation_degrees = Vector3(-24, -132, 0)
	fill.light_specular = 0.0
	add_child(fill)
	_fill = fill


# ---------------------------------------------------------------- 相机

func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 120.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 26.0
	attrs.dof_blur_far_transition = 14.0
	attrs.dof_blur_amount = 0.045
	cam.attributes = attrs
	add_child(cam)
	_update_camera(0.0)


func _update_camera(delta: float) -> void:
	var speed := 9.0 if delta <= 0.0 else 9.0
	yaw = lerp(yaw, _yaw_t, clamp(delta * speed, 0.0, 1.0))
	pitch = lerp(pitch, _pitch_t, clamp(delta * speed, 0.0, 1.0))
	dist = lerp(dist, _dist_t, clamp(delta * speed, 0.0, 1.0))
	target = target.lerp(_target_t, clamp(delta * speed, 0.0, 1.0))

	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)
	# look_at 会重置朝向，所以倾斜要放在它之后，绕相机自身视线轴转
	if roll != 0.0:
		cam.rotate_object_local(Vector3(0.0, 0.0, 1.0), roll)


func _process(delta: float) -> void:
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist_t = clamp(_dist_t * 0.92, 7.0, 30.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist_t = clamp(_dist_t * 1.08, 7.0, 30.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw_t -= mm.relative.x * 0.0062
			_pitch_t = clamp(_pitch_t + mm.relative.y * 0.0052, deg_to_rad(-6.0), deg_to_rad(78.0))
		elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT or mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right := Vector3(cos(_yaw_t), 0, -sin(_yaw_t))
			var fwd := Vector3(-sin(_yaw_t), 0, -cos(_yaw_t))
			var k := 0.011 * (_dist_t / 17.0)
			_target_t += (-right * mm.relative.x + fwd * mm.relative.y) * k
			_target_t.x = clamp(_target_t.x, -3.5, 3.5)
			_target_t.z = clamp(_target_t.z, -3.5, 3.5)
			_target_t.y = clamp(_target_t.y, 0.4, 3.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			_yaw_t = deg_to_rad(26.0)
			_pitch_t = deg_to_rad(14.5)
			_dist_t = 17.0
			_target_t = Vector3(0.0, 1.2, -0.95)


# ---------------------------------------------------------------- 角色

func _setup_actors() -> void:
	# 主角站在便利店雨棚下（z=-0.2 在雨棚干燥区里），面朝马路（+Z），
	# 抱头准备了一下就往雨里冲出去。y=0.16 是人行道高度。
	var a := Actor.new()
	a.position = Vector3(0.7, 0.16, -0.2)
	a.face_yaw_deg = 0.0        # 0 = 模型正面朝 +Z，也就是面向马路
	a.pose = "cover_head"
	a.dash_distance = 2.8
	a.dash_delay = -1.0        # 不自跑，由开场动画在正确时机触发
	add_child(a)
	_actor = a


# ---------------------------------------------------------------- 雨

func _setup_rain() -> void:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = 2400
	p.lifetime = 2.4
	p.preprocess = 2.2
	p.fixed_fps = 60
	p.visibility_aabb = AABB(Vector3(-7.5, -9.0, -7.5), Vector3(15.0, 20.0, 15.0))

	# 自定义粒子着色器：按表面高度截断，雨点不会穿过雨棚与屋面
	var pm := ShaderMaterial.new()
	pm.shader = RAIN_SHADER
	pm.set_shader_parameter("area_half", 5.5)
	pm.set_shader_parameter("top_y", 10.4)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.011, 0.3)
	# 把面片整体挂在粒子位置的上方，触面时雨丝不会戳穿地表
	quad.center_offset = Vector3(0.0, 0.15, 0.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.62, 0.74, 0.98, 0.5)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.disable_receive_shadows = true
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)


func _setup_rain_ripples() -> void:
	# 雨滴落在水平面上产生的扩散涟漪：马路 / 门前人行道 / 后巷 / 屋面
	var surfaces := [
		{"pos": Vector3(0.0, 0.007, 0.0), "size": Vector2(11.2, 11.2), "strength": 0.36, "dry": false},
		{"pos": Vector3(1.85, 0.168, 0.5), "size": Vector2(7.5, 2.8), "strength": 0.26, "dry": true},
		{"pos": Vector3(4.28, 0.196, -3.2), "size": Vector2(2.3, 4.5), "strength": 0.24, "dry": false},
		{"pos": Vector3(0.7, 3.712, -3.2), "size": Vector2(4.8, 4.6), "strength": 0.3, "dry": false},
	]

	var grp := Node3D.new()
	grp.name = "RainRipples"
	add_child(grp)

	for s in surfaces:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = s["size"]
		mi.mesh = pm
		mi.position = s["pos"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := ShaderMaterial.new()
		mat.shader = RIPPLE_SHADER
		mat.set_shader_parameter("strength", s["strength"])
		if s["dry"]:
			# 雨棚正下方是干的
			mat.set_shader_parameter("dry_min", Vector2(-1.76, -0.96))
			mat.set_shader_parameter("dry_max", Vector2(3.16, 0.2))
		mi.material_override = mat
		grp.add_child(mi)



# ---------------------------------------------------------------- 截图

func _take_shots() -> void:
	var shots := [
		{"yaw": 26.0, "pitch": 14.5, "dist": 17.0, "name": "a_front"},
		{"yaw": 92.0, "pitch": 16.0, "dist": 14.0, "name": "b_corner"},
		{"yaw": -34.0, "pitch": 26.0, "dist": 14.5, "name": "c_alley"},
		{"yaw": 200.0, "pitch": 24.0, "dist": 16.0, "name": "d_back"},
		{"yaw": 24.0, "pitch": 14.0, "dist": 14.0, "name": "e_low"},
		{"yaw": 46.0, "pitch": 24.0, "dist": 15.4, "name": "f_high"},
		{"yaw": 18.0, "pitch": 10.0, "dist": 7.4, "name": "g_detail"},
	]
	DirAccess.make_dir_recursive_absolute("res://shots")
	for s in shots:
		_yaw_t = deg_to_rad(s["yaw"])
		_pitch_t = deg_to_rad(s["pitch"])
		_dist_t = s["dist"]
		yaw = _yaw_t
		pitch = _pitch_t
		dist = _dist_t
		_update_camera(0.0)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/%s.png" % s["name"])
		print("saved ", s["name"])
	get_tree().quit()
