extends RefCounted

## 便利店内商品：包装造型 + 价签。
##
## 约定：**正面 = 本地 +Z，底面在 y = 0，原点在底面中心**。和角色「脸朝 +Z」
## 是同一套约定，调用方只要给一个绕 Y 的旋转决定朝向，不要再补 180°。
##
## 尺寸都是真实尺寸（米），不是随手缩放的：500ml 瓶 0.22 高、易拉罐 0.12、
## 杯面 0.13、饭团 0.105、便当 0.05。货架层间净空只有 0.34，改高度前先量。
##
## 造型原则：这个距离（店里 1–2m）看不清印刷，能读出来的是**轮廓 + 色块**。
## 所以瓶要有颈、罐要有顶圈、杯面要上宽下窄、饭团要是三角 + 海苔。
## 别往上面堆贴图或更细的倒角，加了也看不见，只会多几百个 draw call。

const K := preload("res://scripts/kit.gd")

## 包装主色。固定表、按索引取，不随机 —— 截图和文本 diff 都要可比。
const TINTS := [
	Color("#d9483f"), Color("#3f7fd9"), Color("#e8c34a"), Color("#4aa86a"),
	Color("#e08a3c"), Color("#8e5bc4"), Color("#2fa8a0"), Color("#c9553f"),
]

const PAPER := Color("#ded6c2")
const METAL := Color("#c9ced2")
const NORI := Color("#1e2a24")


static func tint(i: int) -> Color:
	return TINTS[posmod(i, TINTS.size())]


## 商品一律不带描边：几百个小物件各挂一个 outline pass，代价比收益大。
static func _mat(c: Color, shade: float = 0.82) -> ShaderMaterial:
	return K.toon(c, {"shade": shade, "rim": 0.0, "line": 0.0})


# ---------------------------------------------------------------- 入口

## kind: bottle / can / cup / bowl / bag / onigiri / bento / bread / tissue / cigarette / carton
## rot 只在需要非 Y 轴旋转时传（例如倒下的盒子）；传了会多套一个 Node3D。
static func make(parent: Node3D, kind: String, pos: Vector3, c: Color,
		rot: Vector3 = Vector3.ZERO) -> void:
	if rot != Vector3.ZERO:
		var g := K.group(parent, "Goods", pos, rot)
		_draw(g, kind, Vector3.ZERO, c)
		return
	_draw(parent, kind, pos, c)


static func _draw(parent: Node3D, kind: String, pos: Vector3, c: Color) -> void:
	match kind:
		"bottle": bottle(parent, pos, c)
		"can": can(parent, pos, c)
		"cup": cup_noodle(parent, pos, c)
		"bowl": bowl_noodle(parent, pos, c)
		"bag": snack_bag(parent, pos, c)
		"onigiri": onigiri(parent, pos)
		"bento": bento(parent, pos, c)
		"bread": bread(parent, pos, c)
		"tissue": tissue(parent, pos, c)
		"cigarette": cigarette(parent, pos, c)
		_: carton(parent, pos, c)


# ---------------------------------------------------------------- 包装

## PET 瓶：直筒瓶身 / 收口肩 / 颈 / 盖 / 标签圈。
## 颈和肩是「这是瓶子」的全部信息量，省掉它们就只剩一根彩色柱子。
static func bottle(parent: Node3D, pos: Vector3, c: Color) -> void:
	var h := 0.22
	var r := 0.030
	var body := h * 0.58
	var shoulder := h * 0.16
	var neck := h * 0.14
	var cap := h * 0.12
	K.cyl(parent, r, body, pos + Vector3(0, body * 0.5, 0), _mat(c), Vector3.ZERO, 10, -1.0, false)
	K.cyl(parent, r, shoulder, pos + Vector3(0, body + shoulder * 0.5, 0),
		_mat(c), Vector3.ZERO, 10, r * 0.55, false)
	K.cyl(parent, r * 0.55, neck, pos + Vector3(0, body + shoulder + neck * 0.5, 0),
		_mat(c), Vector3.ZERO, 8, -1.0, false)
	K.cyl(parent, r * 0.64, cap, pos + Vector3(0, h - cap * 0.5, 0),
		_mat(PAPER, 0.98), Vector3.ZERO, 8, -1.0, false)
	# 标签圈：比瓶身粗 1mm，才不会和瓶身 z-fighting
	K.cyl(parent, r * 1.03, h * 0.22, pos + Vector3(0, body * 0.52, 0),
		_mat(PAPER, 0.98), Vector3.ZERO, 10, -1.0, false)


## 铝罐：罐身 / 银色顶圈 / 浅色标签带。顶圈那一道亮边是罐子的辨识点。
static func can(parent: Node3D, pos: Vector3, c: Color) -> void:
	var h := 0.12
	var r := 0.032
	K.cyl(parent, r, h * 0.86, pos + Vector3(0, h * 0.43, 0), _mat(c), Vector3.ZERO, 10, -1.0, false)
	K.cyl(parent, r * 0.9, h * 0.10, pos + Vector3(0, h * 0.91, 0), _mat(METAL, 0.85), Vector3.ZERO, 10, -1.0, false)
	K.cyl(parent, r * 1.02, h * 0.26, pos + Vector3(0, h * 0.46, 0),
		_mat(PAPER, 0.98), Vector3.ZERO, 10, -1.0, false)


## 杯面：上宽下窄的锥台 + 盖 + 腰封。锥度是它和易拉罐的区别。
static func cup_noodle(parent: Node3D, pos: Vector3, c: Color) -> void:
	var h := 0.13
	K.cyl(parent, 0.037, h, pos + Vector3(0, h * 0.5, 0), _mat(c), Vector3.ZERO, 10, 0.049, false)
	K.cyl(parent, 0.052, 0.010, pos + Vector3(0, h + 0.005, 0), _mat(PAPER, 0.98), Vector3.ZERO, 10, -1.0, false)
	# 腰封跟着锥度走：底 0.041、顶 0.045，比杯身大 4mm 才包得住。
	# 别做太高 —— 白腰封一高，整个杯面就变成「白罐子」，色块全丢了。
	K.cyl(parent, 0.0432, 0.034, pos + Vector3(0, h * 0.44, 0), _mat(PAPER, 0.98), Vector3.ZERO, 10, 0.0465, false)


## 碗面（大杯）：比杯面矮胖，盖更宽。
static func bowl_noodle(parent: Node3D, pos: Vector3, c: Color) -> void:
	var h := 0.155
	K.cyl(parent, 0.052, h, pos + Vector3(0, h * 0.5, 0), _mat(c), Vector3.ZERO, 12, 0.068, false)
	K.cyl(parent, 0.072, 0.012, pos + Vector3(0, h + 0.006, 0), _mat(PAPER, 0.98), Vector3.ZERO, 12, -1.0, false)
	K.cyl(parent, 0.056, 0.058, pos + Vector3(0, h * 0.38, 0), _mat(PAPER, 0.98), Vector3.ZERO, 12, 0.062, false)


## 膨化食品袋：枕形袋 + 上下封边 + 正面标贴。
static func snack_bag(parent: Node3D, pos: Vector3, c: Color) -> void:
	var w := 0.115
	var h := 0.185
	var d := 0.045
	K.box(parent, Vector3(w, h, d), pos + Vector3(0, h * 0.5, 0), _mat(c), Vector3.ZERO, false)
	# 封边比袋身宽 8mm：袋口收窄是「袋子」而不是「盒子」的关键
	K.box(parent, Vector3(w * 1.08, 0.012, d * 0.45), pos + Vector3(0, h - 0.006, 0),
		_mat(c, 0.75), Vector3.ZERO, false)
	K.quad(parent, Vector2(w * 0.74, h * 0.30), pos + Vector3(0, h * 0.60, d * 0.5 + 0.0015),
		_mat(PAPER, 0.99), Vector3.ZERO, false)
	K.quad(parent, Vector2(w * 0.74, h * 0.05), pos + Vector3(0, h * 0.40, d * 0.5 + 0.002),
		_mat(c, 0.6), Vector3.ZERO, false)


## 饭团：三棱柱 + 海苔。便利店最容易被认出来的一样东西。
static func onigiri(parent: Node3D, pos: Vector3) -> void:
	K.prism(parent, Vector3(0.095, 0.105, 0.048), pos + Vector3(0, 0.0525, 0),
		_mat(Color("#f5f1e6"), 0.99), Vector3.ZERO, false)
	# 海苔只包下面 1/3。包到一半就变成「黑底白尖的锥子」，认不出是饭团了。
	K.box(parent, Vector3(0.062, 0.034, 0.052), pos + Vector3(0, 0.017, 0),
		_mat(NORI, 0.8), Vector3.ZERO, false)
	K.quad(parent, Vector2(0.026, 0.013), pos + Vector3(0, 0.062, 0.025),
		_mat(Color("#d9483f"), 0.9), Vector3.ZERO, false)


## 便当：黑盘 + 透明盖 + 腰封。
static func bento(parent: Node3D, pos: Vector3, c: Color) -> void:
	K.box(parent, Vector3(0.150, 0.032, 0.105), pos + Vector3(0, 0.016, 0),
		_mat(Color("#2b3037"), 0.9), Vector3.ZERO, false)
	K.box(parent, Vector3(0.152, 0.014, 0.107), pos + Vector3(0, 0.039, 0),
		K.glass(Color(0.86, 0.91, 0.95, 0.16), 0.18), Vector3.ZERO, false)
	K.box(parent, Vector3(0.154, 0.020, 0.026), pos + Vector3(0, 0.038, 0),
		_mat(c), Vector3.ZERO, false)
	# 顶面标签：冷柜是俯视的，看不到顶面就等于没上色
	K.quad(parent, Vector2(0.10, 0.06), pos + Vector3(0, 0.0465, 0),
		_mat(c, 0.95), Vector3(-90, 0, 0), false)


## 袋装面包：扁球当袋身，封口夹一条。
static func bread(parent: Node3D, pos: Vector3, c: Color) -> void:
	K.sphere(parent, 0.070, pos + Vector3(0, 0.039, 0), _mat(c, 0.92), Vector3.ZERO, 12, 0.55, false)
	K.box(parent, Vector3(0.020, 0.070, 0.020), pos + Vector3(0.058, 0.040, 0),
		_mat(PAPER, 0.95), Vector3.ZERO, false)


## 纸巾软包：盒子 + 顶面抽口。
static func tissue(parent: Node3D, pos: Vector3, c: Color) -> void:
	K.box(parent, Vector3(0.120, 0.065, 0.055), pos + Vector3(0, 0.0325, 0),
		_mat(c, 0.85), Vector3.ZERO, false)
	K.quad(parent, Vector2(0.070, 0.022), pos + Vector3(0, 0.066, 0),
		_mat(PAPER, 0.99), Vector3(-90, 0, 0), false)


## 香烟：白盒 + 品牌色块 + 底部警示条。
static func cigarette(parent: Node3D, pos: Vector3, c: Color) -> void:
	K.box(parent, Vector3(0.058, 0.085, 0.022), pos + Vector3(0, 0.0425, 0),
		_mat(PAPER, 0.96), Vector3.ZERO, false)
	K.quad(parent, Vector2(0.058, 0.026), pos + Vector3(0, 0.064, 0.0115),
		_mat(c, 0.9), Vector3.ZERO, false)
	K.quad(parent, Vector2(0.058, 0.010), pos + Vector3(0, 0.014, 0.0115),
		_mat(Color("#3a3f46"), 0.9), Vector3.ZERO, false)


## 通用小盒（巧克力 / 饼干 / 泡芙）。默认尺寸就是便利店最常见的立式小盒。
static func carton(parent: Node3D, pos: Vector3, c: Color,
		size: Vector3 = Vector3(0.075, 0.110, 0.045)) -> void:
	K.box(parent, size, pos + Vector3(0, size.y * 0.5, 0), _mat(c), Vector3.ZERO, false)
	K.quad(parent, Vector2(size.x * 0.80, size.y * 0.24),
		pos + Vector3(0, size.y * 0.64, size.z * 0.5 + 0.0015),
		_mat(PAPER, 0.99), Vector3.ZERO, false)


# ---------------------------------------------------------------- 陈列

## 杂志：封面 + 主视觉色块 + 刊名。rot 传 Vector3(-12, 90, 0) 就是
## 「面朝 +X、向后靠 12°」—— 货架上的杂志都是斜靠着的，立正反而假。
static func magazine(parent: Node3D, pos: Vector3, c: Color, title: String,
		rot: Vector3 = Vector3.ZERO) -> void:
	var w := 0.205
	var h := 0.270
	var g := K.group(parent, "Magazine", pos, rot)
	K.box(g, Vector3(w, h, 0.008), Vector3(0, h * 0.5, 0), _mat(PAPER, 0.99), Vector3.ZERO, false)
	K.quad(g, Vector2(w * 0.88, h * 0.60), Vector3(0, h * 0.60, 0.005), _mat(c, 0.92), Vector3.ZERO, false)
	K.label(g, title, Vector3(0, h * 0.80, 0.0065), 0.036, Color("#fffaf0"), Vector3.ZERO)


## 价签：白底 + 红字。高度 0.026 是货架价签轨的净高，改大就盖住层板。
static func price_tag(parent: Node3D, pos: Vector3, text: String, rot_y: float = 0.0,
		w: float = 0.044) -> void:
	var g := K.group(parent, "Tag", pos, Vector3(0, rot_y, 0))
	K.quad(g, Vector2(w, 0.024), Vector3.ZERO, _mat(Color("#efe9d8"), 1.0), Vector3.ZERO, false)
	K.label(g, text, Vector3(0, 0, 0.0012), 0.014, Color("#b8352a"), Vector3.ZERO)
