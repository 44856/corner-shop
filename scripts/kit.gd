extends RefCounted

# 通用建模工具：材质缓存、基础体块、拉杆、电线、文字

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const GLOW := preload("res://shaders/glow.gdshader")
const SOFT := preload("res://shaders/soft_glow.gdshader")
const GLASS := preload("res://shaders/glass.gdshader")
const PAVING := preload("res://shaders/paving.gdshader")
const WET := preload("res://shaders/wet_glow.gdshader")

static var _cache: Dictionary = {}
static var _outline_cache: Dictionary = {}
static var _glow_cache: Dictionary = {}
static var _soft_cache: Dictionary = {}

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


static func group(parent: Node3D, name: String, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n
