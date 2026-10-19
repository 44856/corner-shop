extends RefCounted

const K := preload("res://scripts/kit.gd")

# 街角道具：贩卖机 / 自行车 / 伞架 / 垃圾桶 / 空调外机 / 后巷什物 / 猫


static func build(root: Node3D) -> void:
	var g := K.group(root, "Props")
	_doormat(g)
	_umbrella_stand(g)
	_bins(g)
	_aframe(g)
	_bicycle(g, Vector3(-1.02, 0.16, 0.5), 62.0)
	_store_lamp(g)
	_cat(g)
	_alley(g)


static func _doormat(g: Node3D) -> void:
	var mat := K.toon(Color("#2a303a"), {"shade": 0.7, "line": 0.004})
	K.box(g, Vector3(1.2, 0.03, 0.58), Vector3(0.35, 0.175, -0.44), mat)
	for i in 4:
		K.box(g, Vector3(1.1, 0.004, 0.03), Vector3(0.35, 0.192, -0.6 + i * 0.11), K.toon(Color("#3f4653"), {"line": 0.0}), Vector3.ZERO, false)


# ---------------------------------------------------------------- 自动贩卖机

static func _vending(g: Node3D, pos: Vector3, rot_y: float) -> void:
	var v := K.group(g, "Vending", pos, Vector3(0, rot_y, 0))
	var shell := K.toon(Color("#a03a32"), {"shade": 0.52, "rim": 0.28, "line": 0.008})
	K.box(v, Vector3(1.0, 1.84, 0.72), Vector3(0, 0.92, 0), shell)
	K.box(v, Vector3(1.02, 0.08, 0.74), Vector3(0, 1.86, 0), K.toon(Color("#b3aea3"), {"line": 0.006, "rim": 0.2}))
	K.box(v, Vector3(0.96, 0.06, 0.66), Vector3(0, 0.05, 0), K.toon(Color("#2c3037"), {"line": 0.004}))

	# 上方灯箱
	K.box(v, Vector3(0.9, 0.26, 0.02), Vector3(0, 1.66, 0.365), K.glow(Color("#f4fbff"), 1.5))
	K.label(v, "DRINK", Vector3(0, 1.66, 0.378), 0.15, Color("#c93a2e"))

	# 展示窗
	K.box(v, Vector3(0.88, 0.92, 0.03), Vector3(0, 1.18, 0.36), K.glow(Color("#e6f4ff"), 1.25))
	for row in 3:
		for col in 5:
			var y := 0.88 + row * 0.28
			var x := -0.34 + col * 0.17
			var c: Color = [Color("#e0453a"), Color("#3f7fd9"), Color("#f0c93f"), Color("#5cbf7a"), Color("#f2efe6")][(row + col) % 5]
			K.box(v, Vector3(0.11, 0.17, 0.08), Vector3(x, y, 0.385), K.toon(c, {"shade": 0.9, "line": 0.0}), Vector3.ZERO, false)
			K.box(v, Vector3(0.11, 0.018, 0.085), Vector3(x, y + 0.1, 0.386), K.toon(Color("#ffffff"), {"shade": 1.0, "line": 0.0}), Vector3.ZERO, false)

	# 操作面板
	var dark := K.toon(Color("#262b33"), {"shade": 0.7, "line": 0.005})
	K.box(v, Vector3(0.9, 0.22, 0.03), Vector3(0, 0.56, 0.36), dark)
	K.box(v, Vector3(0.32, 0.05, 0.02), Vector3(-0.2, 0.62, 0.375), K.glow(Color("#7fe0ff"), 1.1))
	K.box(v, Vector3(0.1, 0.03, 0.02), Vector3(0.22, 0.62, 0.375), K.glow(Color("#ffb347"), 1.1))
	K.box(v, Vector3(0.12, 0.2, 0.02), Vector3(0.28, 0.4, 0.37), K.toon(Color("#121419"), {"line": 0.0}))
	# 取物口
	K.box(v, Vector3(0.62, 0.26, 0.05), Vector3(-0.05, 0.22, 0.35), K.toon(Color("#15181d"), {"shade": 0.9, "line": 0.004}))
	K.box(v, Vector3(0.56, 0.05, 0.02), Vector3(-0.05, 0.33, 0.375), K.toon(Color("#363c44"), {"line": 0.0}))

	# 溢光
	K.sphere(v, 0.38, Vector3(0, 1.1, 0.42), K.soft(Color("#bfe8ff"), 0.14, 2.2), Vector3.ZERO, 12, 0.9, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#cfe9ff")
	l.light_energy = 0.9
	l.omni_range = 2.4
	l.position = Vector3(0, 1.2, 0.55)
	v.add_child(l)
	var fwd := Vector3(sin(deg_to_rad(rot_y)), 0, cos(deg_to_rad(rot_y)))
	K.plane(g, Vector2(1.8, 2.0), Vector3(pos.x + fwd.x * 0.95, 0.166, pos.z + fwd.z * 0.95), K.wet(Color("#a9d8ff"), 0.07), Vector3.ZERO, false)


static func _umbrella_stand(g: Node3D) -> void:
	var p := Vector3(1.22, 0.16, -0.42)
	var steel := K.toon(Color("#7e848b"), {"shade": 0.5, "rim": 0.35, "line": 0.005})
	K.cyl(g, 0.19, 0.46, p + Vector3(0, 0.23, 0), steel, Vector3.ZERO, 14)
	K.cyl(g, 0.175, 0.02, p + Vector3(0, 0.02, 0), K.toon(Color("#7d848c"), {"line": 0.0}), Vector3.ZERO, 14)
	var cols := [Color("#243a4a"), Color("#553037"), Color("#2f4034")]
	for i in 3:
		var off := Vector3(-0.055 + i * 0.055, 0, 0.02 - i * 0.03)
		K.cyl(g, 0.012, 0.85, p + off + Vector3(0, 0.48, 0), K.toon(Color("#33383f"), {"line": 0.0}), Vector3(0, 0, 12 - i * 6), 6)
		K.cyl(g, 0.035, 0.55, p + off * 1.5 + Vector3(0.02, 0.66, 0), K.toon(cols[i], {"shade": 0.5, "rim": 0.2, "line": 0.005}), Vector3(0, 0, 12 - i * 6), 8, 0.055)


static func _bins(g: Node3D) -> void:
	var cols := [Color("#3a74c4"), Color("#42975f"), Color("#b84e39")]
	for i in 3:
		var p := Vector3(1.52 + i * 0.25, 0.16, -0.52)
		K.box(g, Vector3(0.23, 0.48, 0.27), p + Vector3(0, 0.24, 0), K.toon(cols[i], {"shade": 0.55, "rim": 0.2, "line": 0.005}))
		K.box(g, Vector3(0.25, 0.04, 0.29), p + Vector3(0, 0.5, 0), K.toon(Color("#a8a69f"), {"shade": 0.7, "line": 0.004}))
		K.box(g, Vector3(0.12, 0.09, 0.02), p + Vector3(0, 0.34, 0.145), K.toon(Color("#1b1f25"), {"line": 0.0}))


# ---------------------------------------------------------------- 自行车

static func _bicycle(g: Node3D, pos: Vector3, rot_y: float) -> void:
	var b := K.group(g, "Bicycle", pos, Vector3(0, rot_y, 0))
	var frame := K.toon(Color("#274247"), {"shade": 0.5, "rim": 0.3, "line": 0.005})
	var dark := K.toon(Color("#1d2127"), {"shade": 0.6, "line": 0.004})
	var chrome := K.toon(Color("#a8adb3"), {"shade": 0.5, "rim": 0.45, "line": 0.004})

	var rear := Vector3(0, 0.32, -0.52)
	var front := Vector3(0, 0.32, 0.52)
	var bb := Vector3(0, 0.3, 0.0)
	var seat_top := Vector3(0, 0.78, -0.12)
	var head_top := Vector3(0, 0.8, 0.34)

	for hub_v in [rear, front]:
		var hub: Vector3 = hub_v
		# 轮圈立在 YZ 平面（绕 Z 转 90°），绕 Y 转会留在水平面
		K.torus(b, 0.235, 0.315, hub, dark, Vector3(0, 0, 90), false)
		K.sphere(b, 0.035, hub, chrome, Vector3.ZERO, 8, 1.0, false)
		for s in 3:
			var ang := TAU * float(s) / 3.0 + 0.4
			var p2: Vector3 = hub + Vector3(0, cos(ang) * 0.27, sin(ang) * 0.27)
			K.strut(b, hub, p2, 0.006, chrome, 4, false)

	K.strut(b, rear, seat_top, 0.022, frame, 6)
	K.strut(b, seat_top, bb, 0.024, frame, 6)
	K.strut(b, bb, head_top, 0.024, frame, 6)
	K.strut(b, seat_top, head_top, 0.022, frame, 6)
	K.strut(b, bb, rear, 0.02, frame, 6)
	K.strut(b, head_top, front, 0.02, frame, 6)
	K.strut(b, rear, Vector3(0, 0.34, -0.34), 0.014, chrome, 4, false)

	K.strut(b, head_top, Vector3(0, 0.88, 0.4), 0.018, chrome, 6)
	K.strut(b, Vector3(0, 0.88, 0.4), Vector3(0.24, 0.9, 0.36), 0.016, chrome, 6)
	K.strut(b, Vector3(0, 0.88, 0.4), Vector3(-0.24, 0.9, 0.36), 0.016, chrome, 6)
	K.box(b, Vector3(0.1, 0.05, 0.26), Vector3(0, 0.81, -0.14), dark)
	# 车筐架在前轮上方，不压轮胎；下面加一块托板免得悬空
	K.box(b, Vector3(0.28, 0.025, 0.28), Vector3(0, 0.652, 0.56), dark)
	K.box(b, Vector3(0.3, 0.22, 0.3), Vector3(0, 0.76, 0.56), K.toon(Color("#646a71"), {"shade": 0.55, "rim": 0.3, "line": 0.004}))
	K.box(b, Vector3(0.22, 0.15, 0.2), Vector3(0, 0.77, 0.56), K.toon(Color("#3b4149"), {"line": 0.0}))
	K.cyl(b, 0.05, 0.04, bb, chrome, Vector3(0, 0, 90), 8)
	# 撑脚落到地面
	K.strut(b, bb + Vector3(0.06, -0.02, 0.06), Vector3(0.17, 0.0, 0.22), 0.011, dark, 6)
	K.box(b, Vector3(0.03, 0.02, 0.42), Vector3(0, 0.3, -0.3), dark, Vector3.ZERO, false)
	# 挡泥板压在轮胎上方
	K.box(b, Vector3(0.06, 0.02, 0.34), rear + Vector3(0, 0.345, 0.02), dark)
	K.box(b, Vector3(0.06, 0.02, 0.34), front + Vector3(0, 0.345, -0.02), dark)
	K.sphere(b, 0.035, Vector3(0, 0.62, 0.72), K.glow(Color("#ffe9b8"), 1.2), Vector3.ZERO, 8, 1.0, false)


# ---------------------------------------------------------------- 立式招牌 / 地灯 / 猫

static func _aframe(g: Node3D) -> void:
	var p := Vector3(1.85, 0.16, 0.6)
	var a := K.group(g, "AFrame", p, Vector3(0, -26, 0))
	var wood := K.toon(Color("#3f3322"), {"shade": 0.5, "rim": 0.2, "line": 0.005})
	K.box(a, Vector3(0.5, 0.84, 0.05), Vector3(0, 0.43, 0.08), wood, Vector3(-12, 0, 0))
	K.box(a, Vector3(0.5, 0.84, 0.05), Vector3(0, 0.43, -0.08), wood, Vector3(12, 0, 0))
	K.quad(a, Vector2(0.42, 0.7), Vector3(0, 0.45, 0.115), K.toon(Color("#e6e1d2"), {"shade": 0.85, "line": 0.0}), Vector3(-12, 0, 0))
	K.label(a, "OPEN", Vector3(0, 0.58, 0.125), 0.12, Color("#b23a28"), Vector3(-12, 0, 0))
	K.label(a, "24H", Vector3(0, 0.4, 0.13), 0.095, Color("#2b3b4a"), Vector3(-12, 0, 0))


static func _store_lamp(g: Node3D) -> void:
	var p := Vector3(-0.55, 0.16, -0.6)
	K.cyl(g, 0.07, 0.48, p + Vector3(0, 0.24, 0), K.toon(Color("#33383f"), {"shade": 0.6, "line": 0.005}), Vector3.ZERO, 10)
	K.sphere(g, 0.06, p + Vector3(0, 0.5, 0), K.glow(Color("#ffd9a0"), 1.5), Vector3.ZERO, 10, 1.0, false)
	K.sphere(g, 0.22, p + Vector3(0, 0.5, 0), K.soft(Color("#ffc27a"), 0.22, 2.0), Vector3.ZERO, 12, 0.9, false)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffcf96")
	l.light_energy = 0.4
	l.omni_range = 2.2
	l.position = p + Vector3(0, 0.4, 0)
	g.add_child(l)


static func _cat(g: Node3D) -> void:
	var c := K.group(g, "Cat", Vector3(0.98, 0.16, -0.52), Vector3(0, 205, 0))
	var fur := K.toon(Color("#43434c"), {"shade": 0.55, "rim": 0.25, "line": 0.004})
	var light_fur := K.toon(Color("#cbc7bf"), {"shade": 0.7, "line": 0.004})
	var body := K.sphere(c, 0.09, Vector3(0, 0.14, 0), fur, Vector3.ZERO, 12, 1.5)
	body.scale = Vector3(1.0, 1.0, 0.9)
	K.sphere(c, 0.072, Vector3(0, 0.28, 0.02), fur, Vector3.ZERO, 12, 1.0)
	K.sphere(c, 0.03, Vector3(0, 0.25, 0.075), light_fur, Vector3.ZERO, 8, 1.0, false)
	for sx in [-1, 1]:
		K.cyl(c, 0.028, 0.06, Vector3(sx * 0.042, 0.34, 0.01), fur, Vector3(0, 0, sx * 18), 4, 0.0)
	var tail := PackedVector3Array()
	for i in 8:
		var t := float(i) / 7.0
		tail.append(Vector3(0.02, 0.12 - t * 0.06, -0.09 - t * 0.1 + sin(t * 3.0) * 0.03))
	K.tube(c, tail, 0.014, fur, 4)
	for sx2 in [-1, 1]:
		K.sphere(c, 0.012, Vector3(sx2 * 0.032, 0.29, 0.062), K.glow(Color("#cfe86a"), 1.4), Vector3.ZERO, 6, 1.0, false)


# ---------------------------------------------------------------- 后巷

static func _alley(g: Node3D) -> void:
	var a := K.group(g, "Alley")

	# 后巷地面
	K.box(a, Vector3(2.35, 0.03, 4.6), Vector3(4.28, 0.175, -3.2), K.paving(Color("#3d4047"), Color("#3a3d45"), 0.7), Vector3.ZERO, false)
	K.plane(a, Vector2(0.14, 4.5), Vector3(4.02, 0.191, -3.2), K.toon(Color("#1c1f24"), {"shade": 0.9, "line": 0.0}), Vector3.ZERO, false)

	# 后巷矮墙 + 通透铁栏
	var wall := K.toon(Color("#33363d"), {"shade": 0.45, "rim": 0.15, "line": 0.008})
	K.box(a, Vector3(0.22, 0.8, 4.95), Vector3(5.36, 0.16 + 0.4, -3.02), wall)
	K.box(a, Vector3(0.32, 0.09, 5.0), Vector3(5.36, 1.005, -3.02), K.toon(Color("#63656a"), {"line": 0.006}))
	for i in 4:
		K.box(a, Vector3(0.01, 0.012, 4.9), Vector3(5.24, 0.45 + i * 0.2, -3.02), K.toon(Color("#45474e"), {"line": 0.0}), Vector3.ZERO, false)
	var fence := K.toon(Color("#3c424a"), {"shade": 0.55, "rim": 0.25, "line": 0.004})
	var fx := 5.3
	while fx > 3.2:
		K.box(a, Vector3(0.035, 0.75, 0.035), Vector3(5.3, 1.55, fx), fence)
		fx -= 0.55
	K.strut(a, Vector3(5.3, 1.9, -0.55), Vector3(5.3, 1.9, -5.5), 0.022, fence, 6)
	K.strut(a, Vector3(5.3, 1.22, -0.55), Vector3(5.3, 1.22, -5.5), 0.02, fence, 6)

	# 巷子尽头的木门
	var wood := K.toon(Color("#5c422e"), {"shade": 0.5, "rim": 0.2, "line": 0.005})
	K.box(a, Vector3(1.85, 1.95, 0.1), Vector3(4.3, 1.14, -5.38), wood)
	for i in 5:
		K.box(a, Vector3(0.03, 1.95, 0.12), Vector3(3.55 + i * 0.38, 1.14, -5.37), K.toon(Color("#42301f"), {"line": 0.0}), Vector3.ZERO, false)
	K.box(a, Vector3(2.05, 0.12, 0.16), Vector3(4.3, 2.16, -5.37), K.toon(Color("#42301f"), {"line": 0.005}))

	# 服务门
	K.box(a, Vector3(0.05, 1.9, 0.86), Vector3(3.12, 1.13, -4.5), K.toon(Color("#4c535a"), {"shade": 0.55, "rim": 0.25, "line": 0.006}))
	K.box(a, Vector3(0.06, 0.03, 0.8), Vector3(3.11, 0.57, -4.5), K.toon(Color("#343a41"), {"line": 0.0}), Vector3.ZERO, false)
	K.cyl(a, 0.014, 0.13, Vector3(3.09, 1.05, -4.18), K.toon(Color("#a8abaf"), {"line": 0.0}), Vector3(0, 0, 90), 6)

	# 墙上管道
	var pipe := K.toon(Color("#767b82"), {"shade": 0.5, "rim": 0.3, "line": 0.004})
	K.cyl(a, 0.033, 2.1, Vector3(3.08, 1.2, -3.8), pipe, Vector3.ZERO, 8)
	K.cyl(a, 0.024, 2.1, Vector3(3.08, 1.2, -3.62), pipe, Vector3.ZERO, 8)
	K.cyl(a, 0.033, 2.1, Vector3(3.08, 1.2, -1.75), pipe, Vector3.ZERO, 8)
	for i in 3:
		K.cyl(a, 0.05, 0.05, Vector3(3.08, 0.65 + i * 0.55, -3.71), pipe, Vector3.ZERO, 8)

	# 挂墙空调外机
	for z in [-3.15, -2.35]:
		var ac := K.group(a, "AC", Vector3(3.27, 2.1, z))
		K.box(ac, Vector3(0.36, 0.48, 0.7), Vector3.ZERO, K.toon(Color("#6f706c"), {"shade": 0.5, "rim": 0.25, "line": 0.006}))
		K.cyl(ac, 0.18, 0.03, Vector3(0.19, 0, 0), K.toon(Color("#33383e"), {"line": 0.0}), Vector3(0, 0, 90), 14)
		K.cyl(ac, 0.13, 0.01, Vector3(0.205, 0, 0), K.toon(Color("#6d737b"), {"line": 0.0}), Vector3(0, 0, 90), 14)
		for i in 3:
			K.box(ac, Vector3(0.02, 0.42, 0.02), Vector3(0.19, 0, -0.2 + i * 0.2), K.toon(Color("#5c626a"), {"line": 0.0}), Vector3.ZERO, false)
		K.box(ac, Vector3(0.4, 0.04, 0.06), Vector3(0, -0.26, 0.26), K.toon(Color("#3e434a"), {"line": 0.0}))
		K.box(ac, Vector3(0.4, 0.04, 0.06), Vector3(0, -0.26, -0.26), K.toon(Color("#3e434a"), {"line": 0.0}))

	# 墙上壁灯
	var lamp_p := Vector3(3.16, 2.55, -1.95)
	K.box(a, Vector3(0.2, 0.06, 0.1), lamp_p + Vector3(0.06, 0, 0), K.toon(Color("#33383e"), {"line": 0.004}))
	K.sphere(a, 0.065, lamp_p + Vector3(0.16, -0.05, 0), K.glow(Color("#ffcb8a"), 2.4), Vector3.ZERO, 10, 1.0, false)
	K.sphere(a, 0.28, lamp_p + Vector3(0.17, -0.05, 0), K.soft(Color("#ffb877"), 0.4, 1.8), Vector3.ZERO, 12, 1.0, false)
	var al := OmniLight3D.new()
	al.light_color = Color("#ffc286")
	al.light_energy = 0.9
	al.omni_range = 3.2
	al.position = lamp_p + Vector3(0.22, -0.1, 0)
	a.add_child(al)

	# 巷内贩卖机
	_vending(a, Vector3(3.6, 0.16, -3.5), 90.0)

	# 啤酒箱
	var crate := K.toon(Color("#8a6d22"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	for i in 3:
		K.box(a, Vector3(0.5, 0.28, 0.34), Vector3(5.02, 0.3 + i * 0.29, -4.6), crate)
		if i < 2:
			K.box(a, Vector3(0.5, 0.28, 0.34), Vector3(5.02, 0.3 + i * 0.29, -4.2), crate)
	# 垃圾袋
	var bag := K.toon(Color("#24282f"), {"shade": 0.45, "rim": 0.4, "line": 0.005})
	for d in [[Vector3(4.85, 0.33, -5.05), 0.18], [Vector3(5.08, 0.31, -4.92), 0.15], [Vector3(4.95, 0.29, -4.75), 0.13]]:
		var s := K.sphere(a, d[1], d[0], bag, Vector3.ZERO, 10, 1.15)
		s.scale = Vector3(1.0, 1.0, 0.95)

	var back := OmniLight3D.new()
	back.light_color = Color("#9cbaff")
	back.light_energy = 0.4
	back.omni_range = 2.8
	back.position = Vector3(4.6, 2.0, -5.0)
	a.add_child(back)

	# 巷口红灯笼
	var lan := K.group(a, "Lantern", Vector3(3.12, 2.32, -1.62))
	K.box(lan, Vector3(0.3, 0.04, 0.04), Vector3(0.13, 0.16, 0), K.toon(Color("#2e333a"), {"line": 0.0}))
	K.cyl(lan, 0.105, 0.28, Vector3(0.27, -0.01, 0), K.glow(Color("#d8462f"), 1.4), Vector3.ZERO, 12)
	K.cyl(lan, 0.07, 0.02, Vector3(0.27, -0.16, 0), K.toon(Color("#262a31"), {"line": 0.0}), Vector3.ZERO, 12)
	K.cyl(lan, 0.07, 0.02, Vector3(0.27, 0.14, 0), K.toon(Color("#262a31"), {"line": 0.0}), Vector3.ZERO, 12)
	var ll := OmniLight3D.new()
	ll.light_color = Color("#ff6448")
	ll.light_energy = 0.6
	ll.omni_range = 2.4
	ll.position = Vector3(3.38, 2.3, -1.62)
	a.add_child(ll)

	# 粉色霓虹
	K.box(a, Vector3(0.03, 0.3, 0.9), Vector3(5.23, 1.5, -2.4), K.toon(Color("#1c1524"), {"shade": 0.8, "line": 0.004}))
	K.label(a, "BAR", Vector3(5.213, 1.5, -2.4), 0.2, Color("#ff6fb0"), Vector3(0, -90, 0), 10, Color("#ff6fb0"))
	var nl := OmniLight3D.new()
	nl.light_color = Color("#ff5fa8")
	nl.light_energy = 0.45
	nl.omni_range = 2.2
	nl.position = Vector3(5.1, 1.45, -2.4)
	a.add_child(nl)

	# 公告栏（便利店侧墙）
	var board := K.group(a, "Board", Vector3(3.13, 1.5, -1.72), Vector3(0, 90, 0))
	K.box(board, Vector3(0.85, 0.62, 0.04), Vector3.ZERO, K.toon(Color("#4e3c2a"), {"shade": 0.5, "rim": 0.2, "line": 0.005}))
	K.box(board, Vector3(0.78, 0.53, 0.02), Vector3(0, 0, 0.025), K.toon(Color("#3f382e"), {"line": 0.0}))
	var papers := [Vector2(-0.22, 0.1), Vector2(0.02, -0.04), Vector2(0.24, 0.11)]
	for i in papers.size():
		K.quad(board, Vector2(0.2, 0.28), Vector3(papers[i].x, papers[i].y, 0.04), K.toon(Color("#ddd7c8"), {"shade": 0.85, "line": 0.003}), Vector3(0, 0, -4 + i * 4))


# ---------------------------------------------------------------- 轻自动车

static func _kei_van(g: Node3D, pos: Vector3, rot_y: float) -> void:
	var v := K.group(g, "KeiVan", pos, Vector3(0, rot_y, 0))
	var body := K.toon(Color("#cfcdc3"), {"shade": 0.48, "rim": 0.3, "line": 0.008})
	var trim := K.toon(Color("#3b3f46"), {"shade": 0.55, "rim": 0.2, "line": 0.005})
	var glass := K.glass(Color(0.24, 0.34, 0.46, 0.55), 0.25)
	var chrome := K.toon(Color("#9aa0a6"), {"shade": 0.5, "rim": 0.4, "line": 0.004})

	# 车身
	K.box(v, Vector3(1.5, 0.62, 2.92), Vector3(0, 0.6, 0), body)
	K.box(v, Vector3(1.44, 0.62, 2.5), Vector3(0, 1.18, -0.04), body)
	K.box(v, Vector3(1.5, 0.1, 2.56), Vector3(0, 1.53, -0.06), body)
	# 前脸
	K.box(v, Vector3(1.46, 0.34, 0.1), Vector3(0, 0.42, 1.47), trim)
	K.box(v, Vector3(1.3, 0.13, 0.06), Vector3(0, 0.58, 1.5), trim)
	for sx in [-1, 1]:
		K.box(v, Vector3(0.3, 0.14, 0.06), Vector3(sx * 0.46, 0.78, 1.49), K.glow(Color("#ffe6bb"), 1.2), Vector3.ZERO, false)
		K.box(v, Vector3(0.14, 0.22, 0.06), Vector3(sx * 0.6, 0.8, -1.46), K.glow(Color("#d8452f"), 0.9), Vector3.ZERO, false)
	K.box(v, Vector3(1.46, 0.3, 0.1), Vector3(0, 0.4, -1.47), trim)
	# 车牌
	K.box(v, Vector3(0.36, 0.14, 0.02), Vector3(0, 0.5, 1.53), K.toon(Color("#e8e6dc"), {"line": 0.0}), Vector3.ZERO, false)
	K.label(v, "SAKURA", Vector3(0, 0.5, 1.545), 0.05, Color("#2b3440"))

	# 玻璃
	K.quad(v, Vector2(1.28, 0.5), Vector3(0, 1.16, 1.19), glass, Vector3(-12, 0, 0), false)
	K.quad(v, Vector2(1.16, 0.42), Vector3(0, 1.16, -1.26), glass, Vector3(12, 0, 0), false)
	for sx2 in [-1, 1]:
		K.quad(v, Vector2(1.9, 0.44), Vector3(sx2 * 0.723, 1.18, -0.02), glass, Vector3(0, 90 * sx2, 0), false)
		# 后视镜
		K.box(v, Vector3(0.16, 0.1, 0.06), Vector3(sx2 * 0.78, 1.1, 1.06), trim)
	# 车门缝
	for sx3 in [-1, 1]:
		K.box(v, Vector3(0.01, 0.56, 0.012), Vector3(sx3 * 0.752, 0.72, 0.1), K.toon(Color("#8e8c83"), {"line": 0.0}), Vector3.ZERO, false)

	# 车轮
	for wz in [1.0, -1.0]:
		for wx in [-1, 1]:
			var p := Vector3(wx * 0.68, 0.31, wz)
			K.cyl(v, 0.3, 0.2, p, K.toon(Color("#1c1f25"), {"shade": 0.6, "line": 0.004}), Vector3(0, 0, 90), 16)
			K.cyl(v, 0.17, 0.21, p, K.toon(Color("#8b9096"), {"shade": 0.5, "rim": 0.35, "line": 0.004}), Vector3(0, 0, 90), 12)
			K.cyl(v, 0.06, 0.22, p, chrome, Vector3(0, 0, 90), 8)
	# 尾气 / 底部阴影
	K.box(v, Vector3(1.3, 0.06, 2.4), Vector3(0, 0.24, 0), K.toon(Color("#262a30"), {"line": 0.0}), Vector3.ZERO, false)
