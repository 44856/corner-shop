extends RefCounted
## 中文字体解析（静态缓存）。
##
## Godot 4 内置默认字体（OpenSans）**不含 CJK 字形**，直接写中文会渲染成空白方块。
## 本工程零外部素材，所以不去塞 .ttf 文件，而是用 SystemFont 按名字向操作系统要字体。
##
## 用法：Label.theme_override_fonts/font = FontCJK.get_font()，
## 或者 Label3D.font / RichTextLabel.add_theme_font_override("normal_font", ...)。
##
## 序列照「Windows → macOS → Linux → 通用」排；都找不到时 SystemFont 会退回系统默认，
## 那一步至少不会崩，只是中文可能缺字。

static var _cached: Font

## 按优先级排列的候选字体族。改这里就能换整套 UI 的字形
const CANDIDATES := [
	"Microsoft YaHei UI",      # Windows 10/11 默认中文 UI 字体
	"Microsoft YaHei",         # Windows 7 起
	"PingFang SC",             # macOS
	"Hiragino Sans GB",        # macOS 旧版
	"Noto Sans CJK SC",        # Linux / Android
	"Source Han Sans SC",      # 思源黑体
	"WenQuanYi Micro Hei",     # Linux 常见
	"SimHei",                  # 保底
]


static func get_font() -> Font:
	if _cached != null:
		return _cached
	var f := SystemFont.new()
	f.font_names = PackedStringArray(CANDIDATES)
	# 无头/低分屏下 Auto 会让字发虚，普通灰度抗锯齿在 UI 上更稳
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.multichannel_signed_distance_field = false
	_cached = f
	return f


## 诊断用：返回实际命中的字体名（找不到时会返回 "SystemFont" 之类的占位名）。
static func resolved_name() -> String:
	var f := get_font()
	if f is SystemFont:
		return (f as SystemFont).get_font_name()
	return f.get_font_name()
