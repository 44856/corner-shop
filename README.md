# 雨夜便利店街角 / Rainy Corner Mart

一个用 Godot 4.7 程序化搭建的「雨夜日式便利店街角」微缩场景。全部几何体、材质、灯光与雨效均由 GDScript 在运行时生成，没有外部模型或贴图依赖。

![preview](preview.png)

## 运行

```bash
# 用 Godot 4.7.2 打开本目录（选中 project.godot），按 F5
# 或直接命令行启动：
./Godot_v4.7.2-stable_linux.x86_64 --path .
```

渲染器为 **Forward+**（湿地面 SSR 反射、SSAO、体积雾、景深需要 Forward+）。
若机器只有 OpenGL，场景仍可正常显示，只是会失去屏幕空间反射与体积雾。

## 操作（无任何 UI）

| 操作 | 效果 |
| --- | --- |
| 鼠标左键拖拽 | 环绕旋转 |
| 鼠标滚轮 | 拉近 / 拉远（7–30 m） |
| 鼠标右键 / 中键拖拽 | 平移观察点 |
| `R` | 复位视角 |

## 场景构成

```
scenes/main.tscn        场景入口（仅挂载 main.gd）
scripts/main.gd         环境、灯光、轨道相机、雨、截图调试
scripts/kit.gd          建模工具库：体块、圆柱、管线、拉杆、文字、材质缓存
scripts/street.gd       底座 / 人行道 / 马路 / 标线 / 电线杆 / 路灯 / 街角设施 / 湿地面光池
scripts/store.gd        便利店：外壳 / 玻璃立面 / 自动门 / 雨棚 / 招牌 / 屋顶 / 店内
scripts/props.gd        道具：贩卖机 / 自行车 / 伞架 / 垃圾桶 / 后巷 / 猫
shaders/toon.gdshader   三渲二主材质（硬边分层 + 冷色边缘光）
shaders/outline.gdshader 反向外壳描边（next_pass）
shaders/paving.gdshader 人行道砖（世界坐标缝隙 + 斑驳）
shaders/glass.gdshader  玻璃（染色 + 边缘反光）
shaders/glow.gdshader   自发光面板（招牌 / 灯箱 / 霓虹）
shaders/wet_glow.gdshader 湿地面柔光池
shaders/soft_glow.gdshader 灯头光晕
shaders/rain_particles.gdshader 雨滴粒子（按表面高度截断）
shaders/rain_ripple.gdshader 雨滴落点涟漪
```

## 美术要点

- **三渲二**：`toon.gdshader` 用自定义 `light()` 把 N·L 量化成两档硬边，暗部保留 35%–55% 亮度，再叠一层菲涅尔冷色边缘光；所有物体通过 `next_pass` 做反向外壳描边。
- **夜景层次**：冷蓝月光 + 店内暖光 + 招牌/灯箱自发光 + 粉紫霓虹（后巷 BAR），配合泛光（glow）与湿地面光池，形成冷—暖—霓虹三层色彩关系。
- **微缩模型感**：11.2 × 11.2 正方形底座，深色石材台座 + 黄铜腰线 + 正面铭牌；相机 40° 长焦、低俯角，Forward+ 下附带轻微景深（移轴感）。
- **雨**：`rain_particles.gdshader` 自己算雨滴下落，每帧按 xz 采样「该列最高的可接雨表面」（马路 0.0 / 人行道 0.16 / 后巷 0.19 / 雨棚 2.66 / 屋面 3.71），落到面上就回收重发——雨丝不会穿过雨棚和屋顶继续往下掉。面片挂在粒子位置上方，触面时刚好收在地表。
- **涟漪**：`rain_ripple.gdshader` 按世界坐标切网格、每格随机相位画扩散圆环，铺在马路、门前人行道、后巷与屋面上；加色混合 + 关闭深度写入，不和标线、光池打架；雨棚正下方用 `dry_min/dry_max` 裁掉，保持干燥。

## 常用调节点

- 配色：各 builder 里的 `Color("#...")`；全局明暗在 `kit.gd` 的 `toon()` 默认参数（`shade` / `rim` / `line`）。
- 灯光：`main.gd` 的 `_setup_lights()`（月光/补光）、`store.gd` 的 `_interior()`（店内暖光）、`street.gd` 的 `_lamp()`（路灯）。
- 曝光与调色：`main.gd` 的 `_setup_environment()`（`tonemap_exposure`、`adjustment_*`、`glow_*`）。
- 初始机位：`main.gd` 顶部的 `yaw` / `pitch` / `dist` / `target`。

## 调试截图

以 `--shot` 启动会在 `shots/` 下输出 7 个机位的 PNG 后自动退出：

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path . -- --shot
```
