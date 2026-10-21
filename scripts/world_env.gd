extends RefCounted
## 雨夜场景的「底子」：环境 / 月光 / 雨 / 涟漪。
##
## 从 main.gd 抽出来的那一段，逐项照搬参数，视觉必须和原场景一致 ——
## 可玩版只是换了机位和人，天、光、雨不能变。
## 原 main.gd 保持不动（它同时是 scenes/diorama_orbit.tscn 的冻结备份来源）。

const RAIN_SHADER := preload("res://shaders/rain_particles.gdshader")
const RIPPLE_SHADER := preload("res://shaders/rain_ripple.gdshader")


## 返回 {"environment": Environment, "moon": DirectionalLight3D, "fill": DirectionalLight3D}
static func build(root: Node3D) -> Dictionary:
	var env := _environment(root)
	var lights := _lights(root)
	_rain(root)
	_ripples(root)
	return {"environment": env, "moon": lights[0], "fill": lights[1]}


# ---------------------------------------------------------------- 环境

static func _environment(root: Node3D) -> Environment:
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
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)
	return env


static func _lights(root: Node3D) -> Array:
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#9db4ff")
	moon.light_energy = 0.55
	moon.rotation_degrees = Vector3(-46, 38, 0)
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 40.0
	moon.shadow_bias = 0.02
	moon.light_specular = 0.4
	root.add_child(moon)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("#4d6ea8")
	fill.light_energy = 0.14
	fill.rotation_degrees = Vector3(-24, -132, 0)
	fill.light_specular = 0.0
	root.add_child(fill)

	return [moon, fill]


# ---------------------------------------------------------------- 雨

static func _rain(root: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	# 雨量：2400 → 1200，下落频率（= amount / lifetime）减半
	p.amount = 1200
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
	# 雨丝面片：长宽各减半（11mm × 300mm → 5.5mm × 150mm），可见面积是原来的 1/4。
	# 想要「体积」严格 1/4（各边 ×0.63）就改成 0.0069 × 0.19。
	quad.size = Vector2(0.0055, 0.15)
	quad.center_offset = Vector3(0.0, 0.075, 0.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.62, 0.74, 0.98, 0.5)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.disable_receive_shadows = true
	quad.material = m
	p.draw_pass_1 = quad
	root.add_child(p)


static func _ripples(root: Node3D) -> void:
	var surfaces := [
		{"pos": Vector3(0.0, 0.007, 0.0), "size": Vector2(11.2, 11.2), "strength": 0.36, "dry": false},
		{"pos": Vector3(1.85, 0.168, 0.5), "size": Vector2(7.5, 2.8), "strength": 0.26, "dry": true},
		{"pos": Vector3(4.83, 0.196, -3.2), "size": Vector2(1.06, 4.5), "strength": 0.24, "dry": false},
		{"pos": Vector3(1.3, 3.712, -3.2), "size": Vector2(6.0, 4.6), "strength": 0.3, "dry": false},
	]

	var grp := Node3D.new()
	grp.name = "RainRipples"
	root.add_child(grp)

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
			mat.set_shader_parameter("dry_min", Vector2(-1.76, -0.96))
			mat.set_shader_parameter("dry_max", Vector2(4.36, 0.2))
		mi.material_override = mat
		grp.add_child(mi)
