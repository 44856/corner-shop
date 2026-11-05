extends RefCounted
## 异世界城镇的规划：分区边界、街道走向、主要建筑的落位。
##
## 所有坐标都是世界坐标（米），y = 0 是地面。
## 城镇地基的范围和 grassland.gd 的 PAVED_CENTER / PAVED_HALF 必须一致：
##   x ∈ [-150, 150]，z ∈ [300, 630]
##
## 方位约定（俯视地图，城门在下方）：
##   左 = −X，右 = +X；下 = 靠城门（z 小），上 = 靠后墙（z 大）
##
## 规划：
##   ┌─────────────────┬─────────────────┐
##   │ 教堂 + 富人区    │     领主府      │   z 465~630
##   ├─────────────────┼─────────────────┤
##   │     贫民区       │  冒险者区(商店)  │   z 300~465
##   └─────────────────┴─────────────────┘
##              ↑ 城门（z=300，x=0）
##   中间那条竖线是主街，横线是十字路（z=465）

# ---------------------------------------------------------------- 地基

const X0 := -150.0
const X1 := 150.0
const Z_GATE := 300.0
const Z_BACK := 630.0
const CX := 0.0
const CZ := (Z_GATE + Z_BACK) * 0.5      # 465

# ---------------------------------------------------------------- 街道

## 十字路的位置：从城门直道走到一半
const CROSS_Z := CZ
## 街道半宽。9m ≈ 两车道 + 两侧人行道，比城外的土路（半宽 3.2）宽，
## 因为城里要过马车和摊位
const STREET_HALF := 9.0
## 主街：沿 x = 0，从城门一直穿到后墙
const MAIN_STREET_HALF := 9.0
## 十字路：沿 z = CROSS_Z，从东墙穿到西墙
const CROSS_STREET_HALF := 9.0

# ---------------------------------------------------------------- 四个分区

## 四个象限的矩形（min 角 + 尺寸），都避开了街道。
static func district_slums() -> Rect2:
	return Rect2(Vector2(X0, Z_GATE), Vector2(-STREET_HALF - X0, CROSS_Z - STREET_HALF - Z_GATE))


static func district_adventurer() -> Rect2:
	return Rect2(Vector2(STREET_HALF, Z_GATE),
		Vector2(X1 - STREET_HALF, CROSS_Z - STREET_HALF - Z_GATE))


static func district_church_and_rich() -> Rect2:
	return Rect2(Vector2(X0, CROSS_Z + STREET_HALF),
		Vector2(-STREET_HALF - X0, Z_BACK - CROSS_Z - STREET_HALF))


static func district_lord_manor() -> Rect2:
	return Rect2(Vector2(STREET_HALF, CROSS_Z + STREET_HALF),
		Vector2(X1 - STREET_HALF, Z_BACK - CROSS_Z - STREET_HALF))


## 按世界坐标判断属于哪个区。给 HUD 的区域标签和以后的刷怪规则用。
static func zone_at(p: Vector3) -> String:
	if p.z < Z_GATE or p.z > Z_BACK or p.x < X0 or p.x > X1:
		return "城外"
	if absf(p.x) <= STREET_HALF:
		return "贯城大街"
	if absf(p.z - CROSS_Z) <= CROSS_STREET_HALF:
		return "十字路口"
	if p.z < CROSS_Z:
		return "贫民区" if p.x < 0.0 else "冒险者区"
	return "教堂 · 富人区" if p.x < 0.0 else "领主府"


# ---------------------------------------------------------------- 建筑落位

## 冒险者公会。放在「右下 / 冒险者区」，大门正对主街（朝 −X）。
##
## 公会本身是 28（局部 X）× 25（局部 Z），门开在局部南墙。
## 绕 Y 轴转 +90° 后：局部 −Z（门的朝向）变成世界 −X，局部 X 变成世界 Z，
## 所以在世界里它变成 25 宽（X）× 28 深（Z），门朝西对着大街。
const GUILD_CENTER := Vector3(32.5, 0.0, 400.0)
const GUILD_YAW_DEG := 90.0

## 教堂（左上，暂未建）
const CHURCH_CENTER := Vector3(-80.0, 0.0, 545.0)
## 领主府（右上，暂未建）
const MANOR_CENTER := Vector3(85.0, 0.0, 545.0)
