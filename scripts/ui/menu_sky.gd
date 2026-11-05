extends Control
## 主菜单的静态背景：上午的草原空镜，全部 CanvasItem 自绘。
##
## 为什么不用 3D 空镜：主菜单要「打开就有画面」，起一个 3D 场景得等光照 + 合批，
## 而且窗口分辨率变化时相机会裁切。手绘层按尺寸重算脊线，任何比例都不会破。
##
## 为什么单独成一层：天空 / 远山 / 三层草坡加起来五百多个图元，
## 每帧重画纯属浪费。这一层只在 resized 时重绘一次；会动的云和草叶在 menu_drift.gd。
##
## 所有坐标按 w/h 归一化，1500x900 只是设计基准，不是硬约束。

const P := preload("res://scripts/ui/menu_palette.gd")

## 地平线高度。0.56 是试出来的：再高会压住菜单的按钮列，再低草原就只剩一条边，
## 读不出「这是一片原野」。
const HORIZON := 0.56

## 太阳位置与光晕半径（比例）。放在右上是因为菜单在左侧，
## 光源在右上方时左下的面板正好落在暗侧，米白文字不用加底色也读得清。
const SUN := Vector2(0.795, 0.175)
const SUN_HALO := 0.30

## 山脊 / 坡面的采样段数。48 段在 1500 宽下每段 31px，
## 正弦起伏已经读不出折线；再细就是白烧显卡。
const SEGS := 48


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	var horizon := h * HORIZON

	_sky(w, h, horizon)
	_sun_wash(w, h, horizon)
	_ridges(w, h, horizon)
	_hills(w, h, horizon)


# ---------------------------------------------------------------- 天空

func _sky(w: float, h: float, horizon: float) -> void:
	# 两段渐变 + 一段纯色铺到画面底。
	#
	# 最后那段纯色不是冗余：草坡的脊线在 y≈0.60h 上下浮动，如果天空只画到
	# 地平线(0.56h)，脊线的波谷和天空底边之间会留下几十像素的空隙，
	# 露出 viewport 的清屏色 —— 在地平线上表现为一条黑带。
	# 这种 bug 最阴的地方是：改了远山、改了雾带都不消失，因为它根本不是那两层画的。
	_grad_rect(Rect2(0.0, 0.0, w, horizon * 0.62), P.SKY_TOP, P.SKY_MID)
	_grad_rect(Rect2(0.0, horizon * 0.62, w, horizon * 0.38 + 1.0), P.SKY_MID, P.SKY_LOW)
	draw_rect(Rect2(0.0, horizon + 1.0, w, h - horizon + 4.0), P.SKY_LOW, true)


## 太阳附近把天空提亮。直接画同心圆会看到一圈圈边界，
## 所以这里是叠一条「横向渐变 + 纵向渐变」的方片，颜色在上方最亮、下方归零。
func _sun_wash(w: float, h: float, horizon: float) -> void:
	var c := Vector2(w * SUN.x, h * SUN.y)
	var r := h * SUN_HALO
	# 由外到内七层，alpha 很稀，叠起来才是一团雾而不是七个环
	for i in range(7, 0, -1):
		var t := float(i) / 7.0
		var col := Color(1.0, 0.97, 0.86, 0.035 * (1.0 - t) + 0.012)
		draw_circle(c, r * t, col, true, -1.0, true)
	# 日面本身压得很小：这是上午的太阳，不是落日大圆盘
	draw_circle(c, h * 0.021, Color(1.0, 0.99, 0.90, 0.92), true, -1.0, true)
	draw_circle(c, h * 0.013, Color(1.0, 1.0, 0.97, 1.0), true, -1.0, true)
	# 地平线上的一层暖雾，把山脚化掉
	_grad_rect(Rect2(0.0, horizon - h * 0.075, w, h * 0.10),
		Color(0.98, 0.98, 0.90, 0.0), Color(0.99, 0.98, 0.90, 0.55))


# ---------------------------------------------------------------- 山与坡

func _ridges(w: float, h: float, horizon: float) -> void:
	# 远山：压在地平线上一点点，几乎是一层薄雾里的剪影
	_slab(w, _curve(w, horizon + h * 0.004, h * 0.082, Vector3(0.4, 1.9, 3.1), 1.0),
		h + 4.0,
		Color(0.72, 0.80, 0.78), Color(0.60, 0.71, 0.68))
	# 中山：更绿、更高，脊线有明显的双峰
	_slab(w, _curve(w, horizon + h * 0.030, h * 0.052, Vector3(2.2, 0.7, 4.6), 1.0),
		h + 4.0,
		Color(0.60, 0.73, 0.55), Color(0.46, 0.60, 0.42))


func _hills(w: float, h: float, horizon: float) -> void:
	# 三层草坡。越近越深、起伏越大 —— 这是纵深感的全部来源。
	# 「顶亮底暗」违反真实光照，但符合插画习惯：底边必须沉下去，否则
	# 米白的按钮文字压在同一块亮度上会读不清。
	var far := _curve(w, h * 0.622, h * 0.024, Vector3(1.1, 3.4, 0.2), 0.9)
	var mid := _curve(w, h * 0.706, h * 0.031, Vector3(4.7, 1.3, 2.6), 1.0)
	var near := _curve(w, h * 0.836, h * 0.034, Vector3(0.9, 5.2, 3.9), 1.2)

	_slab(w, far, h + 4.0, Color(0.66, 0.80, 0.53), Color(0.53, 0.69, 0.42))
	_slab(w, mid, h + 4.0, Color(0.48, 0.66, 0.35), Color(0.33, 0.51, 0.24))
	_slab(w, near, h + 4.0, Color(0.36, 0.56, 0.27), Color(0.18, 0.32, 0.16))

	# 受光带：沿脊线往下一条半透明的亮绿。
	# 没有它，三个坡就是三块纯色，读不出「坡顶转向了观众」这件事；
	# 有了它，坡脊的位置立刻变成一条高光线，整片草地就有了起伏。
	_rim(far, h * 0.016, Color(0.86, 0.96, 0.62, 0.34))
	_rim(mid, h * 0.018, Color(0.74, 0.90, 0.50, 0.24))
	_rim(near, h * 0.014, Color(0.58, 0.78, 0.38, 0.22))


## 脊线 + 下移副本围成的一条带。倒序回贴是为了闭合多边形，
## 正向正序会自交，三角化会直接失败留下空洞。
func _rim(ridge: PackedVector2Array, depth: float, color: Color) -> void:
	var poly := ridge.duplicate()
	for i in range(ridge.size() - 1, -1, -1):
		poly.append(ridge[i] + Vector2(0.0, depth))
	draw_colored_polygon(poly, color)


## 三个不同周期的正弦叠加。单个正弦的坡一眼假 —— 它是「波」不是「地」。
## amp_mul 用来给不同层做微调，phase 换一组相位就换一片地形。
func _curve(w: float, y: float, amp: float, phase: Vector3, amp_mul: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in SEGS + 1:
		var u := float(i) / float(SEGS)
		var n := sin(u * TAU * 1.3 + phase.x) * 0.50 \
			+ sin(u * TAU * 2.9 + phase.y) * 0.26 \
			+ sin(u * TAU * 0.7 + phase.z) * 0.62
		pts.append(Vector2(u * w, y - n * amp * amp_mul))
	return pts


## 把一条脊线拉成带纵向渐变的实心块。
##
## 整条多边形一次画完，不要逐段画四边形。
## 逐段版本在脊线波谷处会留下一块三角形空洞 —— 四边形又细又长时
## (31px 宽 / 300px 高)，三角化会退化，那块区域什么都不画，
## 露出 viewport 的清屏色，看起来就是地平线上浮着一块黑三角。
## 整条多边形是简单多边形，triangulate 稳定，而且 48 次调用变 1 次。
func _slab(w: float, ridge: PackedVector2Array, base_y: float,
		top: Color, bottom: Color) -> void:
	var poly := ridge.duplicate()
	# 底边往画面外多探 2px：正好贴边时抗锯齿会在最底行留一条亮缝
	poly.append(Vector2(w + 2.0, base_y))
	poly.append(Vector2(-2.0, base_y))

	var cols := PackedColorArray()
	for p in ridge:
		# 脊线越高的地方越亮一点（空气透视）。整条同色会让山看起来是一块贴片，
		# 加了这层微弱差异，眼睛才会读出「远处有雾」
		var lift: float = clampf((base_y - p.y) / maxf(base_y * 0.35, 1.0), 0.0, 1.0)
		cols.append(top.lerp(bottom, 1.0 - lift * 0.35))
	cols.append(bottom)
	cols.append(bottom)
	draw_polygon(poly, cols)


func _grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([
			r.position,
			r.position + Vector2(r.size.x, 0.0),
			r.position + r.size,
			r.position + Vector2(0.0, r.size.y),
		]),
		PackedColorArray([top, top, bottom, bottom]))
