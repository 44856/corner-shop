extends RefCounted

# 通用建模工具：材质缓存、基础体块、拉杆、电线、文字

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const GLOW := preload("res://shaders/glow.gdshader")
const SOFT := preload("res://shaders/soft_glow.gdshader")
const GLASS := preload("res://shaders/glass.gdshader")
const PAVING := preload("res://shaders/paving.gdshader")
const WET := preload("res://shaders/wet_glow.gdshader")
const BEAM := preload("res://shaders/headlamp.gdshader")
const UI_FONT := preload("res://scripts/ui_font.gd")

static var _cache: Dictionary = {}
static var _outline_cache: Dictionary = {}
static var _glow_cache: Dictionary = {}
static var _soft_cache: Dictionary = {}

## 台面（微缩底座顶面）的世界包围盒：x/z ±5.6，高度留足。
## 着色器裁剪用它 —— 超出台面的片元直接 discard，不渲染。
const PLATFORM_CLIP := AABB(Vector3(-5.6, -2.0, -5.6), Vector3(11.2, 10.0, 11.2))

# ---------------------------------------------------------------- 材质

static func outline_mat(w: float) -> ShaderMaterial:
	var key := "%.4f" % w
	if _outline_cache.has(key):
		return _outline_cache[key]
	var m := ShaderMaterial.new()
	m.shader = OUTLINE
	m.set_shader_parameter("thickness", w)
	m.set_shader_parameter("line_color", Color(0.045, 0.05, 0.075))
	_outline_cache[key] = m
	return m


static func toon(color: Color, p: Dictionary = {}) -> ShaderMaterial:
	var shade: float = p.get("shade", 0.45)
	var rim: float = p.get("rim", 0.15)
	var wrap: float = p.get("wrap", 0.22)
	var line: float = p.get("line", 0.011)
	var emit_col: Color = p.get("emit", Color(0, 0, 0))
	var emit_amt: float = p.get("emit_amt", 0.0)
	var edge: float = p.get("edge", 0.02)
	var key := "%s|%.2f|%.2f|%.2f|%.3f|%s|%.2f|%.2f" % [color.to_html(true), shade, rim, wrap, line, emit_col.to_html(true), emit_amt, edge]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("shade_floor", shade)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("light_wrap", wrap)
	m.set_shader_parameter("emit_color", emit_col)
	m.set_shader_parameter("emit_strength", emit_amt)
	m.set_shader_parameter("band_edge", edge)
	if line > 0.0:
		m.next_pass = outline_mat(line)
	_cache[key] = m
	return m


## 带台面裁剪的三渲二材质。
## 和 toon() 长得一样，但**不走缓存**：clip_* 是逐材质的 uniform，
## 共用缓存会让参数串到别的物体上（比如整条街都被裁掉）。
## 描边 pass 也一起复制并打上同一组参数，否则车身裁了、描边壳还在。
static func toon_clipped(color: Color, p: Dictionary = {}, clip: AABB = PLATFORM_CLIP) -> ShaderMaterial:
	var m := toon(color, p).duplicate() as ShaderMaterial
	_apply_clip(m, clip)
	var op := m.next_pass as ShaderMaterial
	if op != null:
		op = op.duplicate() as ShaderMaterial
		_apply_clip(op, clip)
		m.next_pass = op
	return m


static func _apply_clip(m: ShaderMaterial, clip: AABB) -> void:
	m.set_shader_parameter("clip_on", true)
	m.set_shader_parameter("clip_min", clip.position)
	m.set_shader_parameter("clip_max", clip.end)


## 带台面裁剪的自发光材质（灯板 / 尾灯）。不走缓存，理由同 toon_clipped。
static func glow_clipped(color: Color, strength: float = 1.6, scan: float = 0.0,
		clip: AABB = PLATFORM_CLIP) -> ShaderMaterial:
	var m := glow(color, strength, scan).duplicate() as ShaderMaterial
	_apply_clip(m, clip)
	return m


## 车灯光束 / 地面光池。参数直接透传给 headlamp.gdshader，裁剪参数一并打上。
## 光柱也是「从场外开进来的东西」，不裁就会在底座外面亮着。
static func headlamp(p: Dictionary, clip: AABB = PLATFORM_CLIP) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BEAM
	for k in p:
		m.set_shader_parameter(k, p[k])
	_apply_clip(m, clip)
	return m


## 带台面裁剪的柔光球（货车灯头光晕）。理由同 glow_clipped。
static func soft_clipped(color: Color, strength: float = 0.4, power: float = 2.2,
		clip: AABB = PLATFORM_CLIP) -> ShaderMaterial:
	var m := soft(color, strength, power).duplicate() as ShaderMaterial
	_apply_clip(m, clip)
	return m


static func paving(color: Color, line_col: Color, tile: float) -> ShaderMaterial:
	var key := "pav|%s|%s|%.2f" % [color.to_html(true), line_col.to_html(true), tile]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = PAVING
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("line_color", line_col)
	m.set_shader_parameter("tile_size", tile)
	_cache[key] = m
	return m


static func glow(color: Color, strength: float = 1.6, scan: float = 0.0) -> ShaderMaterial:
	var key := "glow|%s|%.2f|%.2f" % [color.to_html(true), strength, scan]
	if _glow_cache.has(key):
		return _glow_cache[key]
	var m := ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_parameter("glow_color", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("band_scan", scan)
	_glow_cache[key] = m
	return m


static func soft(color: Color, strength: float = 0.4, power: float = 2.2) -> ShaderMaterial:
	var key := "soft|%s|%.2f|%.2f" % [color.to_html(true), strength, power]
	if _soft_cache.has(key):
		return _soft_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SOFT
	m.set_shader_parameter("glow_color", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("power", power)
	_soft_cache[key] = m
	return m


static func glass(tint: Color = Color(0.55, 0.7, 0.85, 0.16), edge: float = 0.35) -> ShaderMaterial:
	var key := "glass|%s|%.2f" % [tint.to_html(true), edge]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = GLASS
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("edge_strength", edge)
	_cache[key] = m
	return m


static func wet(color: Color, strength: float = 0.3) -> ShaderMaterial:
	var key := "wet|%s|%.2f" % [color.to_html(true), strength]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = WET
	m.set_shader_parameter("glow_color", color)
	m.set_shader_parameter("strength", strength)
	_cache[key] = m
	return m


static func pbr(color: Color, rough: float, metal: float, extra: Dictionary = {}) -> StandardMaterial3D:
	var key := "pbr|%s|%.2f|%.2f|%s" % [color.to_html(true), rough, metal, str(extra)]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	for k in extra:
		m.set(k, extra[k])
	_cache[key] = m
	return m


# ---------------------------------------------------------------- 体块

static func _finish(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot: Vector3, shadow: bool) -> MeshInstance3D:
	mi.position = pos
	mi.rotation_degrees = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


## 三棱柱：顶点朝上、沿 +Z 挤出，正面（三角形）正好朝 +Z。
## 不用 PrismMesh 是因为它的朝向由引擎定死，而饭团这类包装必须能直接对齐
## 「正面 = +Z」的约定 —— 否则每摆一个都要再猜一次欧拉角。
##
## 两个坑都记在这儿，省得下次再来一遍：
##
## 1. 绕序：Godot 的正面是**顺时针**（从外面看）。按右手定则朝外的顺序直接提交，
##    引擎会当成背面 —— 主 pass（cull_back）把它剔掉，而 next_pass 的描边壳
##    （cull_front）偏偏保留了它，外扩 0.012 后整片盖成描边色。
##    结果不是「看不见」，是「看见一块纯描边色的三角」，很难往绕序上想。
##
## 2. 法线：不能用 generate_normals()。它按**顶点位置**平均，三棱柱的每条棱上
##    三个面共用一个位置，于是三个面被糊成圆角。公会山墙是 25 m 宽的大平板，
##    平均出来的法线偏向斜上方，ndl 掉到暗部阈值以下，整片墙永远发灰紫。
##    这里逐三角形算面法线、显式 set_normal()，硬边实体的样子才对。
static func prism(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var hd := size.z * 0.5
	var apex := Vector3(0, hh, 0)
	var left := Vector3(-hw, -hh, 0)
	var right := Vector3(hw, -hh, 0)
	var fz := Vector3(0, 0, hd)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, apex + fz, left + fz, right + fz)
	_tri(st, apex - fz, right - fz, left - fz)
	# 三个侧面，每个矩形拆两个三角形
	for edge in [[left, apex], [right, left], [apex, right]]:
		var p0: Vector3 = edge[0]
		var p1: Vector3 = edge[1]
		var a := p0 + fz
		var b := p1 + fz
		var c := p1 - fz
		var d := p0 - fz
		_tri(st, a, b, c)
		_tri(st, a, c, d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


## 提交一个三角形。调用方按「右手定则法线朝外」的顺序给 a/b/c，
## 这里负责两件事：算平直面法线（写死，不让引擎平均），
## 发射时把 b/c 换位（右手朝外 → 引擎眼里的正面）。
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b]:
		st.set_normal(n)
		st.add_vertex(v)


static func plane(parent: Node3D, size: Vector2, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = false) -> MeshInstance3D:
	var m := PlaneMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


static func quad(parent: Node3D, size: Vector2, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var m := QuadMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, seg: int = 16, top_radius: float = -1.0, shadow: bool = true) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = seg
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, seg: int = 16, height_scale: float = 1.0, shadow: bool = true) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * height_scale
	m.radial_segments = seg
	m.rings = max(4, seg / 2)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return _finish(parent, mi, pos, rot, shadow)


static func strut(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, seg: int = 8, shadow: bool = true) -> MeshInstance3D:
	var d := b - a
	var h := d.length()
	if h < 0.0001:
		return null
	var mi := cyl(parent, r, h, (a + b) * 0.5, mat, Vector3.ZERO, seg, -1.0, shadow)
	var up := Vector3.UP
	var dir := d / h
	if up.cross(dir).length() > 0.0001:
		mi.quaternion = Quaternion(up.cross(dir).normalized(), up.angle_to(dir))
	return mi


static func tube(parent: Node3D, pts: PackedVector3Array, radius: float, mat: Material, sides: int = 4) -> MeshInstance3D:
	if pts.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in pts.size():
		var p := pts[i]
		var dir: Vector3
		if i == 0:
			dir = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			dir = (pts[i] - pts[i - 1]).normalized()
		else:
			dir = (pts[i + 1] - pts[i - 1]).normalized()
		var ref := Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var n1 := dir.cross(ref).normalized()
		var n2 := dir.cross(n1).normalized()
		var ring: Array = []
		for s in sides:
			var ang := TAU * float(s) / float(sides)
			ring.append(p + n1 * cos(ang) * radius + n2 * sin(ang) * radius)
		rings.append(ring)
	for i in rings.size() - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a: Vector3 = rings[i][s]
			var b: Vector3 = rings[i][s2]
			var c: Vector3 = rings[i + 1][s2]
			var d2: Vector3 = rings[i + 1][s]
			for v in [a, b, c, a, c, d2]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func wire(parent: Node3D, a: Vector3, b: Vector3, sag: float, radius: float = 0.012, mat: Material = null, segs: int = 16) -> MeshInstance3D:
	var pts := PackedVector3Array()
	for i in segs + 1:
		var t := float(i) / float(segs)
		var p := a.lerp(b, t)
		p.y -= sin(PI * t) * sag
		pts.append(p)
	if mat == null:
		mat = toon(Color("#14161c"), {"line": 0.0})
	return tube(parent, pts, radius, mat, 4)


static func label(parent: Node3D, text: String, pos: Vector3, height: float, color: Color, rot: Vector3 = Vector3.ZERO, outline: int = 0, glow_col: Color = Color(0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = height / 96.0
	l.modulate = color
	l.outline_size = outline
	l.outline_modulate = glow_col if outline > 0 else color
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.position = pos
	l.rotation_degrees = rot
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l


## 带中日文字形的标签。Label3D 默认吃引擎内置字体，日文/汉字会变成方块；
## 招牌、暖帘、路牌一律走这个入口。
static func label_cjk(parent: Node3D, text: String, pos: Vector3, height: float,
		color: Color, rot: Vector3 = Vector3.ZERO, outline: int = 0,
		glow_col: Color = Color(0, 0, 0)) -> Label3D:
	var l := label(parent, text, pos, height, color, rot, outline, glow_col)
	l.font = UI_FONT.get_font()
	return l


static func group(parent: Node3D, name: String, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


# ---------------------------------------------------------------- 静态合批

## 把静态分支里的三渲二网格合并成少数几个 ArrayMesh。
##
## 商店街有 2500+ 个 MeshInstance3D，每个都是一次 draw call；更贵的是街灯
## 全是立方体阴影，同一批几何要在 6 个面上各画一遍。这些几何在运行时完全
## 不动，逐节点绘制纯属浪费。
##
## 只合并同时满足这些条件的节点：材质是 toon.gdshader（缓存共享，描边 pass
## 也一致）、无 skin / 子节点 / 脚本，祖先里没有脚本或物理体。最后一条是
## 关键 —— 自动门、会动的剧情道具必须留在原地，不能烘进静态网格。
##
## 世界变换直接烘进顶点：toon.gdshader 用 MODEL_MATRIX * VERTEX 算世界坐标，
## 合并后的节点在场景原点、变换为单位阵，结果与原来逐节点绘制完全一致。
##
## branches 是 root 的直接子节点名；返回被合并掉的 MeshInstance3D 数量。
static func batch_static(root: Node3D, branches: Array) -> int:
	var buckets := {}
	var victims: Array[MeshInstance3D] = []
	for name in branches:
		var branch := root.get_node_or_null(NodePath(String(name)))
		if branch != null:
			_collect_static(branch, root, buckets, victims)
	if victims.is_empty():
		return 0

	var grp := Node3D.new()
	grp.name = "BatchedStatic"
	root.add_child(grp)

	var n := 0
	for key in buckets:
		var b: Dictionary = buckets[key]
		var mesh := (b["st"] as SurfaceTool).commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Batch_%d" % n
		mi.mesh = mesh
		mi.material_override = b["mat"]
		mi.cast_shadow = b["shadow"]
		grp.add_child(mi)
		n += 1

	for mi in victims:
		mi.get_parent().remove_child(mi)
		mi.free()
	return victims.size()


static func _collect_static(n: Node, root: Node3D, buckets: Dictionary, victims: Array) -> void:
	if n is MeshInstance3D and _batchable(n as MeshInstance3D):
		var mi := n as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		var shadow := mi.cast_shadow
		var key := "%d|%d" % [mat.get_instance_id(), shadow]
		if not buckets.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			buckets[key] = {"st": st, "mat": mat, "shadow": shadow}
		var t := root.global_transform.affine_inverse() * mi.global_transform
		for i in mi.mesh.get_surface_count():
			(buckets[key]["st"] as SurfaceTool).append_from(mi.mesh, i, t)
		victims.append(mi)
		return

	for c in n.get_children():
		# 带脚本 / 物理体的子树整体跳过：里面的网格随时可能被移动或旋转。
		if c is CollisionObject3D or c.get_script() != null:
			continue
		_collect_static(c, root, buckets, victims)


static func _batchable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.skin != null or mi.get_script() != null or mi.get_child_count() > 0:
		return false
	var m := mi.material_override
	if not (m is ShaderMaterial) or (m as ShaderMaterial).shader != TOON:
		return false
	# 非三角形 surface（线段等）不能进 SurfaceTool 的三角形批次。
	if mi.mesh is ArrayMesh:
		for i in mi.mesh.get_surface_count():
			if (mi.mesh as ArrayMesh).surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				return false
	return true
