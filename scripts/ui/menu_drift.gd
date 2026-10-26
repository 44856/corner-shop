extends Control
## 主菜单的动态装饰层：云、近景草叶、空气里的花粉。
##
## 这一层每帧重绘，所以图元数要克制：云 5 朵（每朵约 10 个圆）、
## 草叶 7 排 x 34 根 = 238 条线、花粉 26 个点。合计约 330 个绘制命令，
## 在 1500x900 下不会掉帧。再往上加就必须拆帧更新了。
##
## 位置用固定 seed 生成：每次打开菜单，草叶和花粉都在同一个位置。
## 这不只是强迫症 —— 截图回归要靠它，否则每张图都不可比。

const P := preload("res://scripts/ui/menu_palette.gd")

## 固定种子。改这个数就是换一片草。
const SEED := 20261026
const CLOUD_COUNT := 8
## 草叶排数。从远景坡（y≈0.735h）一直铺到画面底部外，越近越高越深。
## 8 排 x 96 簇 = 768 簇、每簇 3 根。绘制时按排合批，一次 draw_multiline 画完一排，
## 所以密度翻五倍反而比逐根绘制更快。
const TUFT_ROWS := 8
const TUFT_PER_ROW := 96
const MOTE_COUNT := 30
## 天上的鸟。3 只就够，多了像蚊子
const BIRD_COUNT := 3

## 草叶摆动的角频率。1.3 大约 4.8 秒一个来回 —— 再快就像被风吹的塑料草，
## 再慢就看不出在动。
const SWAY_HZ := 1.3

var _t := 0.0
var _clouds: Array = []
var _rows: Array = []
var _motes: Array = []
var _birds: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_rebuild)
	# 根节点进树那一帧 size 还是 0，锚点要等一次布局才生效
	call_deferred("_rebuild")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _rebuild() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	_rng.seed = SEED
	_build_clouds(w, h)
	_build_tufts(w, h)
	_build_motes(w, h)
	_build_birds(w, h)
	queue_redraw()


# ---------------------------------------------------------------- 生成

func _build_clouds(w: float, h: float) -> void:
	_clouds.clear()
	for i in CLOUD_COUNT:
		_clouds.append({
			# x 用 0..1 的比例存，绘制时再乘宽度：窗口拉宽时云跟着铺开，不会挤在左边
			"x": _rng.randf_range(-0.05, 1.05),
			# y 收到 0.07~0.33：再低就压到按钮列上，云的白和按钮的米白会互相干扰
			"y": _rng.randf_range(0.07, 0.33),
			"s": _rng.randf_range(0.048, 0.125),
			# 速度 0.002~0.006 屏宽/秒：1500 宽下约 3~9 分钟横穿一次
			"v": _rng.randf_range(0.0020, 0.0056),
			"a": _rng.randf_range(0.62, 0.95),
		})


func _build_tufts(w: float, h: float) -> void:
	_rows.clear()
	for row in TUFT_ROWS:
		var depth := float(row) / float(TUFT_ROWS - 1)
		# 根部从 0.735h 排到 1.02h：最后一排的根在屏幕外，
		# 这样画面底边不会出现一排「草被剪断」的整齐根部
		var y0 := lerpf(h * 0.735, h * 1.02, depth)
		var hgt := lerpf(h * 0.020, h * 0.068, depth)
		# 亮的黄绿 → 深的墨绿。近处更深是对的：逆光看近处的草是暗的，
		# 而远处那层被阳光穿透，反而发白 —— 这条反直觉的规则是草坪感的来源
		var col := Color(0.46, 0.66, 0.32).lerp(Color(0.14, 0.31, 0.14), depth)
		var band: Array = []
		# 远处稀疏、近处密集：真实草原也是这样，远处的草在画面里只占几个像素，
		# 铺满反而变成一层噪点。三分之一到全部之间线性过渡。
		var count := int(lerpf(float(TUFT_PER_ROW) * 0.30, float(TUFT_PER_ROW), depth))
		for i in count:
			band.append({
				"x": (_rng.randf_range(-0.02, 1.02)) * w,
				"y": y0 + _rng.randf_range(-0.014, 0.014) * h,
				"h": hgt * _rng.randf_range(0.60, 1.40),
				"p": _rng.randf_range(0.0, TAU),
			})
		_rows.append({"tufts": band, "c": col, "w": lerpf(1.3, 2.9, depth)})


func _build_motes(w: float, h: float) -> void:
	_motes.clear()
	for i in MOTE_COUNT:
		_motes.append({
			"x": _rng.randf_range(0.0, 1.0),
			"y": _rng.randf_range(0.30, 0.95),
			"r": _rng.randf_range(0.9, 2.6),
			"v": _rng.randf_range(0.006, 0.020),
			"p": _rng.randf_range(0.0, TAU),
			"a": _rng.randf_range(0.18, 0.55),
		})


func _build_birds(w: float, h: float) -> void:
	_birds.clear()
	for i in BIRD_COUNT:
		_birds.append({
			"x": _rng.randf_range(0.0, 1.0),
			"y": _rng.randf_range(0.10, 0.20),
			# 尺寸按 h 缩放：鸟在画面上是 6~11px 的 V，太大就成风筝
			"s": _rng.randf_range(0.006, 0.011),
			"v": _rng.randf_range(0.0012, 0.0026),
			"p": _rng.randf_range(0.0, TAU),
		})


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	_paint_birds(w, h)
	_paint_clouds(w, h)
	_paint_motes(w, h)
	_paint_tufts()


func _paint_birds(w: float, h: float) -> void:
	for b in _birds:
		var span := w + h * 0.2
		var x: float = fposmod(float(b["x"]) * w + _t * float(b["v"]) * w, span) - h * 0.1
		var y: float = float(b["y"]) * h + sin(_t * 0.7 + float(b["p"])) * h * 0.006
		var s: float = float(b["s"]) * h
		# 翅膀一拍一收：sweep 在 0.55~1.0 之间呼吸，鸟就不是贴纸
		var sweep: float = 0.72 + sin(_t * 2.6 + float(b["p"])) * 0.28
		var col := Color(0.15, 0.24, 0.20, 0.42)
		draw_polyline(PackedVector2Array([
			Vector2(x - s, y - s * sweep),
			Vector2(x, y),
			Vector2(x + s, y - s * sweep * 0.86),
		]), col, 1.6, true)


func _paint_clouds(w: float, h: float) -> void:
	for c in _clouds:
		var span := w + h * 0.6
		# 显式标 float：字典取出来的是 Variant，用 := 推断会被编译器拒绝
		var x: float = fposmod(float(c["x"]) * w + _t * float(c["v"]) * w, span) - h * 0.3
		var y: float = float(c["y"]) * h
		var s: float = float(c["s"]) * h
		var a: float = c["a"]
		# 整朵云在垂直方向压到 0.74。二次元的云是「上圆下平」的一坨，
		# 正圆一个个叠出来的永远像一串棉花糖；压扁之后底部自然拉平，才有云的重量。
		# 用 draw_set_transform 而不是自己算椭圆点：这是唯一的批量缩放手段，
		# 画完必须复位，否则后面同一次 _draw 里的草和光斑会一起被压。
		draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, 0.74))
		# 云底：三个略扁的暗圆，制造体积。全是白圆的话云会像一团棉花糖贴在天上
		for i in 3:
			var dx: float = (float(i) - 1.0) * s * 0.72
			draw_circle(Vector2(dx, s * 0.34), s * 0.56,
				Color(0.74, 0.83, 0.91, a * 0.34), true, -1.0, true)
		# 云体：五团不等高的白圆。最高的那团偏右，云才有「迎风面」
		var puffs: Array[Vector3] = [
			Vector3(-0.90, 0.16, 0.58),
			Vector3(-0.38, -0.02, 0.78),
			Vector3(0.20, -0.16, 0.96),
			Vector3(0.78, 0.02, 0.74),
			Vector3(1.22, 0.18, 0.50),
		]
		for v: Vector3 in puffs:
			draw_circle(Vector2(v.x * s, v.y * s), s * v.z,
				Color(1.0, 1.0, 0.99, a), true, -1.0, true)
		# 受光面：左上偏一点的高光。太阳在右上，所以亮边朝左上是反的 ——
		# 但二次元云的惯例就是「迎光面永远朝观众」，照着画更好看，也更像画
		var glints: Array[Vector3] = [
			Vector3(-0.30, -0.24, 0.56), Vector3(0.26, -0.34, 0.62),
		]
		for v: Vector3 in glints:
			draw_circle(Vector2(v.x * s, v.y * s), s * v.z,
				Color(1.0, 1.0, 1.0, a * 0.75), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_tufts() -> void:
	# 每排攒成一个大顶点数组，用一次 draw_multiline 画完。
	# 逐根 draw_polyline 的话，384 根就是 384 次绘制调用 —— 密度一提高直接掉帧；
	# 攒起来之后每排 3 次调用，密度翻五倍反而更快。
	for band in _rows:
		var pts := PackedVector2Array()
		for t in band["tufts"]:
			var bx: float = t["x"]
			var by: float = t["y"]
			var th: float = t["h"]
			var sway: float = sin(_t * SWAY_HZ + float(t["p"]) + bx * 0.012)
			# 一簇三根：中间最高，左右两根矮一点、歪得多一点。
			# 单根草排成一排永远是「插了一地竹签」，成簇才读得出草丛
			for k in 3:
				var off: float = (float(k) - 1.0) * th * 0.11
				var hh: float = th * (1.0 - absf(float(k) - 1.0) * 0.26)
				var lean: float = sway * (0.55 + 0.45 * float(k))
				var p0 := Vector2(bx + off, by)
				var p1 := Vector2(bx + off + lean * hh * 0.16, by - hh * 0.56)
				var p2 := Vector2(bx + off + lean * hh * 0.46, by - hh)
				pts.append(p0)
				pts.append(p1)
				pts.append(p1)
				pts.append(p2)
		draw_multiline(pts, band["c"] as Color, float(band["w"]))


func _paint_motes(w: float, h: float) -> void:
	for m in _motes:
		# 慢慢往上飘，飘出画面上沿就从底部重新进来
		var y: float = fposmod(float(m["y"]) * h - _t * float(m["v"]) * h, h)
		var x: float = float(m["x"]) * w + sin(_t * 0.6 + float(m["p"])) * h * 0.012
		draw_circle(Vector2(x, y), float(m["r"]),
			Color(1.0, 1.0, 0.92, float(m["a"])), true, -1.0, true)
