extends RefCounted
## 主菜单的配色与字体。单独成文件，是因为背景、按钮、滑条、设置面板四处都要用同一套色 ——
## 散落在各自脚本里的话，调一个绿要翻五个文件，而且很容易调出「五种不同的草绿」。
##
## 色系分三层：
##   INK / DEEP / MOSS  墨绿，只用于面板底、描边、深色文字
##   LEAF / LIME        青草绿，背景坡面与焦点色
##   CREAM / HAZE / GOLD 米白与暖金，只用于文字
##
## LIME 故意偏黄（#bce86e）而不是纯绿：上午的阳光打在草上是这个色，
## 而且纯绿（hue 120）在深绿描边上会糊成一片，黄绿才有「脆」的对比。

const UiFont := preload("res://scripts/ui_font.gd")

const INK := Color("#0b1610")
const DEEP := Color("#13241a")
const MOSS := Color("#2c4c33")

const LEAF := Color("#5f8049")
const LEAF_LIGHT := Color("#93c06b")
const LIME := Color("#bce86e")

const CREAM := Color("#f6f3e4")
const HAZE := Color("#cfe0c4")
const GOLD := Color("#ffd39a")

## 天空三段。地平线附近偏暖白，是为了让远山「溶」进天里，
## 换成同色系的蓝会让山脊线变成一条硬边——那是矢量插画，不是二次元背景。
const SKY_TOP := Color("#4f9bd8")
const SKY_MID := Color("#a3cfe4")
const SKY_LOW := Color("#eaf1d9")

static var _variants: Dictionary = {}


## 基础字体。中文靠它，英文也靠它 —— 本工程零外部素材。
static func font() -> Font:
	return UiFont.get_font()


## 变体字体。key 只有三个：
##   "title" 大标题：加粗 + 微字距，压得住 60px 的白字
##   "wide"  英文小标签：字距拉开到 4px，这是二次元 UI 的「标牌感」
##   "bold"  按钮中文：轻微加粗，悬停反色时笔画不会细到发虚
## 缓存是必须的：FontVariation 每次 new 都要重建字形缓存，四五个按钮各建一次会拖慢首帧。
static func variant(key: String) -> Font:
	if _variants.has(key):
		return _variants[key]
	var f := FontVariation.new()
	f.base_font = UiFont.get_font()
	match key:
		"title":
			f.variation_embolden = 0.55
			f.spacing_glyph = 1
		"wide":
			f.spacing_glyph = 4
		"bold":
			f.variation_embolden = 0.28
		_:
			pass
	_variants[key] = f
	return f


## 统一的标签构造。主菜单里有二十多条文字，每条都写三行 add_theme_* 会很吵。
static func label(text: String, size: int, color: Color, use_variant: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if use_variant != "":
		l.add_theme_font_override("font", variant(use_variant))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 硬边方框。radius 只给 2 —— 这是「清脆」的来源：
## 圆角 8 是对话框，圆角 2 才是一块切出来的塑料牌子。
static func box(bg: Color, border: Color, border_w: int = 2, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


## 在画布上写一行字，返回行宽。pos 给的是「左边中线的下沿基线」，
## 因为 Control 里最常需要的是垂直居中，而不是左上角对齐。
static func draw_text(ci: CanvasItem, text: String, x: float, center_y: float,
		size: int, color: Color, use_variant: String = "",
		align_right_at: float = -1.0) -> float:
	var f := font() if use_variant == "" else variant(use_variant)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var px := x
	if align_right_at >= 0.0:
		px = align_right_at - w
	var baseline := center_y + (f.get_ascent(size) - f.get_descent(size)) * 0.5
	ci.draw_string(f, Vector2(px, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## 纯填充的硬边框：四条矩形。不用 draw_rect(unfilled) 是因为它的描边会走抗锯齿，
## 在 1.5px 宽度下会灰掉一半，反色高亮时边框就不够「脆」。
static func stroke(ci: CanvasItem, r: Rect2, color: Color, w: float = 2.0) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), color, true)
	ci.draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - w), Vector2(r.size.x, w)), color, true)
	ci.draw_rect(Rect2(r.position + Vector2(0.0, w), Vector2(w, r.size.y - w * 2.0)), color, true)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - w, w), Vector2(w, r.size.y - w * 2.0)),
		color, true)
