# 雨夜便利店街角 / Rainy Corner Mart

一个用 Godot 4.7 程序化搭建的「雨夜日式便利店街角」微缩场景，以及从它延伸出去的 35.6m 日式商店街和国道旁的加油站。全部几何体、材质、灯光与雨效均由 GDScript 在运行时生成，没有外部模型或贴图依赖。

场景有几种看法：

| 版本 | 场景 | 玩法 |
| --- | --- | --- |
| **可玩版**（默认入口） | `scenes/store_walk.tscn` | 第三人称走进便利店：自动门、店内交互、跟随镜头；进过店再下马路会被货车撞 |
| **商店街可玩版**（扩展） | `scenes/hoshi_street.tscn` | 35.6m 日式商店街：出生在东口牌楼内侧、面朝西；两排店面 / 候车亭 / 斑马线，沿街走到西端进同一家便利店 |
| **加油站剧情版**（扩展） | `scenes/gas_station.tscn` | 雨夜服务区：收音机 / 司机 / 擦身车三件小事之后进入逢魔时，国道车祸 → 死亡演出 → 异世界草原 |
| 微缩展示版 | `scenes/main.tscn` | 轨道相机俯瞰整个 11.2m 底座，原版编排 |
| 编排备份 | `scenes/diorama_orbit.tscn` | 改造前编排的冻结副本（见「备份」一节） |

三个可玩场景共用 `kit / store / props / hud / interaction_hub / player_controller`。
`hoshi_street` 只新增街道层，`gas_station` 只新增服务区与剧情层，`store_walk` 的编排与探针不受影响。

![preview](preview.png)

## 运行

```bash
./tools/run.sh              # 默认入口：store_walk（微缩全景推镜 → 第三人称）
./tools/run.sh list         # 看有哪些场景能跑
```

`tools/run.sh` 会自动找引擎（项目根 → `~/godot*` → PATH），也可以用 `GODOT_BIN` 指定：

```bash
GODOT_BIN=/path/to/godot ./tools/run.sh
```

**单独看某个场景时不要去改 `project.godot` 的 `main_scene`。** 改来改去 diff 里全是噪声，
还会和别人的分支打架 —— 命令行指定场景就够了：

```bash
./tools/run.sh grassland                    # 简写，自动补 res://scenes/ 与 .tscn
./tools/run.sh hoshi_street                 # 日式商店街（新街区）
./tools/run.sh gas_station                  # 国道 17 号加油站（剧情版）
./tools/run.sh opening_flow                 # 原来的开场流程（雨夜三幕 → 草原）
./tools/run.sh --editor store_walk          # 在编辑器里打开该场景
./tools/run.sh --headless walk_probe        # 无窗口跑回归
./tools/run.sh store_walk -- --shot         # -- 之后的参数原样传给场景
./tools/run.sh -n store_wal                 # 只打印将要执行的命令（dry run）
```

名字支持唯一前缀：`store_wal` 会命中 `store_walk`；匹配到多个时会拒绝执行并列出候选。

不用脚本也行，原始命令仍然可用：

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path .
./Godot_v4.7.2-stable_linux.x86_64 --path . res://scenes/grassland.tscn
```

渲染器为 **Forward+**（湿地面 SSR 反射、SSAO、体积雾、景深需要 Forward+）。
若机器只有 OpenGL，场景仍可正常显示，只是会失去屏幕空间反射与体积雾。

> 换了机器或拉了大文件之后，第一次启动会自动导入（约 1 分钟）。
> `.godot/` 不进仓库，缺了这一步音频和 `gaia.glb` 会加载失败，场景看起来就像「少了东西」。

## 操作（可玩版）

| 操作 | 效果 |
| --- | --- |
| `W A S D` / 方向键 | 移动（相对镜头方向） |
| `Shift` | 快跑 |
| `空格` | 跳 |
| 鼠标移动 | 转视角（第三人称弹簧臂） |
| 鼠标滚轮 | —— 预留，当前固定机位距离 |
| `E` / `F` | 与附近目标互动（冷柜 / 货架 / 服务铃 / 猫；街区的暖帘 / 菜牌 / 候车亭 / 店面；加油站的收音机 / 司机 / 油枪） |
| `Esc` | 释放鼠标（点回窗口重新锁定） |

**自动门**不需要按键：走到门前 2.35m 自动滑开，离开 0.45 秒后自动关闭；
人卡在门洞里时不会关。门楣上的感应灯关着是红的、开了是绿的。

进店之后镜头会自动换成短焦段（1.6m / FOV 70° / 右肩偏移），
曝光从 1.12 收到 0.92 —— 否则店内三盏暖光正对着天花板，会直接烧白。

**车祸事件**：先进店，再走出门、下到马路上（南侧车行道），右侧会驶来一辆
大货车。这是一次性的演出，撞完人会回到出生点，之后在马路上走就安全了。

**商店街**（`hoshi_street`）：出生在东口牌楼内侧的北人行道上，面朝西。街区
35.6 × 15.2m：北侧从西到东是便利店 / 拉面 / 居酒屋 / 投币洗衣 / 烟店 / 公寓 / 交番，
南侧是住宅 / 钱汤 / 喫茶店 / 洗衣店 / 诊所 / 口袋公园；中间是 2.9m 车道，带斑马线和
候车亭。沿街可以掀暖帘、买罐装咖啡、看洗衣机、查末班车；一直往西走，尽头还是
同一家 HOSHI MART。东口外只做了视觉背景楼，没有可走区域，边界围栏把人留在街上。

**加油站剧情**（`gas_station`）：雨夜 00:06 的服务区里没有任务列表，只有三件小事情：

1. 柜台窗台的收音机在播「国道 17 号深夜货运高峰，一辆白色厢式货车刚从星见町服务区驶出」；
2. 第一次踏上国道，一辆轻自动车贴着肩膀过去 —— 你躲开了，于是相信自己反应够快；
3. 东侧停着一辆厢式货车，司机打着哈欠说「最后一趟，跑完这趟就收车」。

三件都做过之后，天光跳到「逢魔时 18:42」，货车与司机消失，西边路面亮起两点车灯。
再踏上国道，白色货车从同一个方向驶来：操作瞬间锁死，人钉在原地，
只能看着车灯在慢镜头里逼近 —— 车头贴住身体的一瞬把人撞飞。之后是三层死亡：
画面去色撕裂 → 听觉只剩耳鸣、可以伸手但雨不会停 → 几件普通的闪回。
最后字母转场到草原，落地只按嗅觉 / 听觉 / 痛觉 / 视觉认识这具身体和新世界。

三颗子弹可以任意顺序完成，只有全部完成才会变天；逢魔时之后回商店街的路牌失效，
旧世界线不再可回。关键参数在 `gas_station_story.gd` 顶部：`DUSK_GRACE` 是变天后
留给玩家反应的缓冲，`STATION_CLIP` 是货车在 30×18m 场地上不被裁剪的盒子。

## 备份：改造前的编排

改造前先做了两层备份，任何一层都能回到原样：

1. **标签** `backup/orbit-diorama` —— 指向改造前的提交（可 `git checkout` 完整还原）。
2. **可运行副本** `scenes/diorama_orbit.tscn` + `scripts/backup/diorama_orbit.gd`
   —— `main.gd` 当时的逐字副本，随时随地能跑一遍旧版做对照，不需要切分支。

```bash
./tools/run.sh diorama_orbit
```

注意副本引用的是「当前」的 `street.gd / store.gd / props.gd`，冻结的是编排
（机位、灯光、开场、角色站位），不是整棵依赖树。

## 场景构成

```
scenes/store_walk.tscn  可玩版入口（第三人称 + 交互）
scenes/hoshi_street.tscn 商店街可玩版（35.6m 双排街区）
scenes/gas_station.tscn 加油站剧情版（雨夜服务区 → 逢魔时 → 车祸 → 草原）
scenes/main.tscn        微缩展示版（只挂 main.gd）
scenes/diorama_orbit.tscn 编排备份（冻结副本）
scenes/opening_flow.tscn  原开场流程（雨夜三幕 → 字母屏 → 草原，走 SceneRouter）
scenes/grassland.tscn   异世界草原

scripts/store_walk.gd   可玩版编排：装配世界 / 玩家 / 门 / HUD / 交互 / 开场推镜 / 截图模式
scripts/hoshi_street.gd 商店街编排：世界装配 / 出生点 / 开场推镜 / 区域判定 / 交互 / 截图
scripts/gas_station.gd  加油站编排：世界装配 / 油机与小卖亭 / 区域判定 / 交互 / 截图
scripts/gas_station_story.gd 加油站剧情状态机：三颗子弹 / 逢魔时 / 撞击 / 死亡 / 转场
scripts/story_veil.gd   死亡面纱与告别字幕（去色 / 撕裂 / 噪点 / 伸手提示）
scripts/town.gd         街道层：底座 / 地面 / 标线 / 排水 / 电线杆 / 路灯 / 东口牌楼 / 街具 / 背景楼
scripts/shop_row.gd     两排日式店面：拉面 / 居酒屋 / 洗衣 / 烟店 / 公寓 / 交番 / 住宅 / 钱汤 / 喫茶…
scripts/town_collision.gd 街区碰撞层：地面 / 路缘斜面 / 店面 / 巷道 / 街具 / 边界
scripts/truck.gd        大货车造型（6.2m 厢式，底盘/厢体/驾驶室/车轮四层细节 + 车灯光柱）
scripts/truck_event.gd  车祸事件：触发条件 / 冲刺 / 命中 / 收黑 / 复位
scripts/world_env.gd    环境、月光、雨、涟漪（从 main.gd 抽出，参数逐项照搬）
scripts/collision_layout.gd 简化碰撞层：地面 / 墙 / 货架 / 台阶斜面 / 街道设施 / 边界
scripts/autodoor.gd     自动门：两片带碰撞的滑动门叶 + 感应 + 叮咚音
scripts/interaction_hub.gd 交互中枢：最近目标出提示，按 E 触发
scripts/hud.gd          HUD：标题 / 区域 / 交互提示 / 物件反馈 / 操作说明
scripts/sfx.gd          程序化音效（门铃 ping-pon、服务铃、轻触）
scripts/player_controller.gd 第三人称控制器（移动 / 跳跃 / 弹簧臂 / 相机档位）
scripts/actor.gd        VRoid 主角模型加载、掰姿势、平色材质、描边
scripts/store.gd        便利店：外壳 / 玻璃立面 / 自动门位 / 雨棚 / 招牌 / 屋顶 / 店内
scripts/street.gd       底座 / 人行道 / 马路 / 标线 / 电线杆 / 路灯 / 街角设施 / 湿地面光池
scripts/props.gd        道具：贩卖机 / 自行车 / 伞架 / 垃圾桶 / 后巷 / 猫
scripts/kit.gd          建模工具库：体块、圆柱、管线、拉杆、文字、材质缓存
scripts/core/game_state.gd  跨场景剧情节点与 flag（纯数据，不持有节点）
scripts/core/world_links.gd 场景登记与出口路由表（纯数据：哪个出口在哪个剧情节点通向哪）
scripts/core/scene_router.gd 场景切换唯一入口：查路由 / 到达上下文 / 转场生命周期
scripts/core/portal_host.gd 场景本地出口：走路触发盒 + E 提示，按路由启停
scripts/audio/audio_bus.gd  全局音频入口：一次性音效合并 / 3D 池 / 命名声道 / 总线淡变
scripts/audio/audio_voice.gd 统一播放句柄：专用播放器与复音流 id 的同一套接口
scripts/backup/diorama_orbit.gd 改造前编排的冻结副本
scripts/dialogue/       对话解析与播放（草原用）
shaders/                三渲二 / 描边 / 砖缝 / 玻璃 / 自发光 / 湿光 / 车灯光束 / 雨 / 涟漪 / 死亡面纱

tools/run.sh            单场景运行（不改 project.godot）
tools/check.sh          全量回归：自动发现并跑 tools/*_probe.tscn
tools/_godot.sh         引擎探测（被上面两个脚本 source）
tools/setup_lfs.sh      git-lfs 环境检查与历史迁移
tools/walk_probe.tscn   便利店行走回归（14 条断言，见「自测」）
tools/truck_probe.tscn  车祸事件回归（17 条断言，见「自测」）
tools/street_probe.tscn 商店街回归（17 条断言，见「自测」）
tools/grassland_probe.tscn 草原交互回归（41 条断言）
tools/gas_station_probe.tscn 加油站场景回归（13 条断言）
tools/gas_station_story_probe.tscn 加油站剧情回归（30 条断言）
```

## 交互实现要点

- **能走进去，而不是「看着能进去」**：原场景的踢脚墙横跨整个立面（含门洞），
  店内三排货架间距只有 0.53m。`Store.build(root, {"walkable": true, ...})` 会把
  踢脚墙按门洞断开，货架改成两块、留出 0.80m 过道，收银台挪到东墙。
  `Store.layout(walkable)` 是视觉与碰撞的唯一真源，改一处两边一起动。
- **店是往里长的，不是往两边摊**：东墙从 3.1 推到 4.30，让出
  「柜台 0.6 + 收银员站位 0.67 + 隔墙 0.12 + 休息室 1.38」这条 3.5m 的进深。
  柜台 1.1×0.6 → 2.2×0.6（面积正好翻倍），休息室 1.38×4.16 = 5.74m²，
  约等于原卖场地面（18.14m²）的 1/3。代价是后巷从 2.35m 收窄到 1.06m，
  贩卖机挪到巷尾面朝巷口。
- **休息室进不去，是设计不是 bug**：门画成关着的，碰撞上隔墙是**整面实心**、
  不留门洞 —— 0.9m 的门洞对 0.64m 的胶囊来说一挤就过，留个洞迟早有人钻进去。
  想看里面就隔着对内的小窗（窗台 1.00 / 窗顶 1.90）看：灯亮着、桌椅在、杯面还热着。
- **门是真的门**：门叶是 `AnimatableBody3D`，玻璃 / 门框 / 把手都是它的子节点，
  开合补间挪的是物理体本身，所以「门开了」和「人能过」是同一件事。
- **提示不能隔着墙弹**：`interaction_hub.gd` 除了水平距离，还会从胸口往提示点打一条
  射线（`_has_sight`），中间有东西就不提示。容差 0.9m —— 提示点常常就落在物体内部
  （货架、冷柜），射线会先打到它自己，不能把这当成「隔着墙」。
  另外每个交互点可以带一个 `gate` 回调，服务铃的 gate 是「人在店里」：
  之前站在店外空调外机那儿、穿模卡进墙里，水平距离够了铃就亮了，现在两道都过不去。
- **看不见的坡**：路缘 16cm、店门槛 9cm，人物没有自动上台阶逻辑。这两处用
  `ConvexPolygonShape3D` 楔形补了隐形斜面 —— 比给控制器加 step-up 安全，
  不会顺带改变草原场景的手感。路缘石的顶面和人行道齐平（0.16），
  隐形坡整条铺在路缘石外侧（`x < −2.07` / `z > 2.07`）：石头是实心的可见几何，
  碰撞足迹不跟上的话，人站在路边脚会埋进石头里。
- **接触阴影**：夜景主光只有 0.55 能量，脚底几乎没有影子。脚下挂一张
  Alpha 径向渐变面片，每帧向下打一条射线贴地，跳起来时缩小变淡。
- **声音**：所有播放都经 `AudioBus`（autoload）。一次性音效合并进每条总线一个复音播放器，
  3D 音效走固定池，雨 / 低频用命名声道（`rain` / `hum`）——跨场景同名申请是接管，不会叠两层。
  门铃 / 服务铃是运行时合成的 PCM（`sfx.gd`）；进店时雨声压到 −26dB、低频抬到 −24dB，
  玻璃把雨关在了外面。
- **车祸事件**：进过店（区域判定 `"in"`）之后走到南侧车行道中间（`z > 3.7`）触发，
  锁输入 → 0.42s 预警喇叭 → 货车从台面外 9m 处以 13m/s 冲进来。
  车头距人 4.5m 时 `Engine.time_scale` 收到 0.35（慢镜头），命中后击飞 + 白闪 +
  镜头抖 + 闷响，0.22s 收黑，黑场里复位到出生点。详见 `docs/任务03-马路车祸事件.md`。
- **车灯是真的会打光**：两盏前照灯各挂一个 SpotLight（照亮路面）+ 一个无盖锥体
  （空气里的光柱）+ 一块地面光池（湿地上那块亮斑）+ 一盏柔光球（灯头光晕）。
  光柱和光池共用 `headlamp.gdshader`，同样带台面裁剪；尾灯 / 侧标志灯 / 示廓灯
  是自发光面板，刹车时尾灯从 2.2 提到 5.0。
- **超出台面的部分不渲染**：`toon / outline / glow` 三个 shader 都加了
  `clip_on / clip_min / clip_max`，片元世界坐标越界就 `discard`。
  货车一律用 `kit.toon_clipped()` / `glow_clipped()` 生成材质 ——
  `kit.toon()` 是按参数缓存的，裁剪参数写进缓存会顺带把整条街裁掉。
  裁剪盒就是 `kit.PLATFORM_CLIP`（x/z ±5.6），切口和底座边缘严丝合缝。

## 自测

```bash
./tools/check.sh
```

跑 `tools/` 下全部 `*_probe.tscn`，一个场景一行结果，最后给总判定。现在有十组：

| probe | 断言 | 测什么 |
| --- | --- | --- |
| `walk_probe` | 14 | 走进店门 → 东侧过道 → 冷柜 → 退出门 → 爬回路缘；门是否打开、是否跨过门槛、是否踩上 0.25m 地板、提示文案、服务铃店内亮 / 隔墙不亮、挤不进休息室、离开后关门 |
| `truck_probe` | 17 | 车祸事件：触发条件、冲刺速度、命中判定、慢镜头、收黑复位、不重复触发、车出台面后回收 |
| `street_probe` | 17 | 商店街：出生点在东口、沿街往西可走、两排店面挡得住、上下 16cm 路缘、斑马线过街、拉面店 / 候车亭交互、从新街区走进同一家便利店 |
| `grassland_probe` | 41 | 狗与两个守卫的交互、提示出/收、区域标签、对话全流程、守卫站姿与脚底贴地 |
| `gas_station_probe` | 16 | 加油机岛台与小卖亭挡人、16cm 路缘、顶棚区域、柜台隔窗提示、到达上下文清空、转场锁（含出口停用） |
| `gas_station_story_probe` | 31 | 收音机 / 司机 / 擦身车三颗子弹、逢魔时、道具撤场、路牌提示消失、撞车锁输入且无侧向位移、驾驶室贴近角色（约 0.1m）、死亡段保持锁输入、撞击后不倒地、死亡接管环境声、终态 DONE |
| `prop_collision_probe` | 12 | 商店街街具与便利店门前道具的碰撞足迹 |
| `transition_probe` | 7 | 字母转场：层级、字母拆分、进度、自毁 |
| `router_probe` | 79 | 场景路由纯数据：默认路由 / 剧情节点覆盖 / 禁用理由、同一出口改指向、`*` 通配、`set_story_node` 合法性、本地 PORTALS 与中央 ROUTES 一一对应、GameState 与 SceneRouter 到达上下文 |
| `audio_probe` | 42 | 音频合并层：2D 复音上限与优先级抢占、3D 固定池、发射器复音、命名声道接管 / 淡变 / 循环、owner 生命周期、总线淡变 |

判定失败的条件有三条：probe 退出码非 0、输出里有 `SCRIPT ERROR` / `Parse Error`、
probe 自己打印的 `failed` 计数非 0。**只靠退出码会漏**，因为 Godot 打包脚本错误时经常照样返回 0。

只跑一组：

```bash
./tools/run.sh --headless walk_probe
./tools/run.sh --headless truck_probe   # 无渲染，只走车祸事件状态机
./tools/run.sh --headless street_probe  # 无渲染，只走商店街移动 / 碰撞 / 交互
./tools/run.sh --headless gas_station_story_probe  # 三颗子弹 → 逢魔时 → 撞车 → 死亡
```

新增 probe 只要命名成 `tools/xxx_probe.tscn` 就会被自动纳入，不用改脚本，也不用改 CI。

## 美术要点

- **三渲二**：`toon.gdshader` 用自定义 `light()` 把 N·L 量化成两档硬边，暗部保留 35%–55% 亮度，再叠一层菲涅尔冷色边缘光；所有物体通过 `next_pass` 做反向外壳描边。
- **夜景层次**：冷蓝月光 + 店内暖光 + 招牌/灯箱自发光 + 粉紫霓虹（后巷 BAR），配合泛光（glow）与湿地面光池，形成冷—暖—霓虹三层色彩关系。
- **微缩模型感**：11.2 × 11.2 正方形底座，深色石材台座 + 黄铜腰线 + 正面铭牌；展示版相机 40° 长焦、低俯角，Forward+ 下附带轻微景深（移轴感）。
- **雨**：`rain_particles.gdshader` 自己算雨滴下落，每帧按 xz 采样「该列最高的可接雨表面」（马路 0.0 / 人行道 0.16 / 后巷 0.19 / 雨棚 2.66 / 屋面 3.71），落到面上就回收重发——雨丝不会穿过雨棚和屋顶继续往下掉。面片挂在粒子位置上方，触面时刚好收在地表。面片尺寸 5.5mm × 150mm —— 长宽各减半，可见面积是初版的 1/4；粒子数 1200（初版 2400），下落频率同步减半。
  商店街 35.6m 长，粒子范围改成矩形（`center` + `half`），遮雨面从「写死的表面表」换成最多 32 个 `vec4(x0,z0,x1,z1)+h` 槽位，由 `Town.rain_covers()` 与 `ShopRow.rain_covers()` 填。旧场景不传矩形参数时仍走原来的表面表，行为不变。
- **涟漪**：`rain_ripple.gdshader` 按世界坐标切网格、每格随机相位画扩散圆环，铺在马路、门前人行道、后巷与屋面上；加色混合 + 关闭深度写入，不和标线、光池打架；雨棚正下方用 `dry_min/dry_max` 裁掉，保持干燥。
- **车灯光柱**：`headlamp.gdshader` 用一个无盖锥筒 + 加色混合假装体积光。锥壳上每个片元都贴着锥面，用「离轴距离」算衰减会恒等于 0，所以改用 `|N·V|`：视线正对着的那一侧最厚、轮廓边缘最薄，看起来才像一束光而不是一块半透明的三角板。锥筒不带端盖 —— 带盖的话正对车头时远端那张圆盘会像一块悬空的发光板。地面上的亮斑是另一块椭圆面片（同一个着色器，`pool = true`），光柱只负责空气里的部分。

## 常用调节点

- 配色：各 builder 里的 `Color("#...")`；全局明暗在 `kit.gd` 的 `toon()` 默认参数（`shade` / `rim` / `line`）。
- 灯光：`world_env.gd` 的月光/补光、`store.gd` 的 `_interior()`（店内暖光）、`street.gd` 的 `_lamp()`（路灯）。
- 曝光与调色：`world_env.gd` 的 `_environment()`；店内曝光在 `store_walk.gd` 的 `EXPOSE_IN`。
  商店街的街外 / 店内曝光在 `hoshi_street.gd` 的 `EXPOSE_OUT` / `EXPOSE_IN`。
- 机位：`store_walk.gd` 的 `CAM_OUT` / `CAM_IN`（距离 / 支点高度 / FOV / 肩部偏移）；
  展示版的初始机位在 `main.gd` 顶部的 `yaw` / `pitch` / `dist` / `target`。
- 商店街：`hoshi_street.gd` 的 `SPAWN` / `CAM_OUT` / `CAM_IN` / `INTRO_FROM_POS` / `INTRO_LOOK`；
  街道尺寸、路缘和牌楼在 `town.gd` 顶部常量（`town_collision.gd` 直接引用），
  两排店面的位置与高度在 `shop_row.gd` 的 `NORTH` / `SOUTH` / `AWNINGS`。
- 商店街的雨棚：新增或挪动雨棚要同步 `shop_row.gd` 的 `rain_covers()` / `ripples()`，
  否则雨会穿过雨棚继续下，涟漪也会出现在干燥的棚下。
- 门的感应范围与关门迟疑：`autodoor.gd` 的 `open_radius` / `close_grace`。
- 店内布局：`store.gd` 的 `layout(walkable)`（改完记得跑一遍 `walk_probe`）。
- 交互点与文案：`store_walk.gd` 的 `_setup_interactions()` 与 `_on_*` 回调。
  按 E 时 `interaction_hub.gd` 会先让角色转向目标点（`player.look_at_point()`，
  锁定 0.55s），四个交互点共用这一套，不用各写一遍。
  `add_target()` 的第 6 个参数 `priority` 用于剧情目标：默认 0 时只比距离，
  收音机用 1 压过旁边的售货机，听过之后 gate 关闭、自动让位。
- 加油站剧情：`gas_station_story.gd` 顶部的 `DUSK_GRACE`（变天后反应缓冲）、
  `STATION_CLIP`（货车裁剪盒）、`RADIO_TARGET` / `DRIVER_TARGET`（交互点）；
  三颗子弹的文案与回调查 `_on_radio()` / `_on_driver()` / `_launch_near_van()`；
  死亡演出时长在 `_death_sequence()`，面纱参数在 `_start_veil()`。
- 车祸事件：`truck_event.gd` 顶部的 `SIDE`（从哪一侧驶入，改符号换边）/ `SPEED` /
  `SPAWN_GAP` / `TRIGGER_Z`（走到路中间才触发）/ `LANE_MIN..MAX` / `SLOWMO_GAP` / `SLOWMO_SCALE` / `RESPAWN`；
  车的尺寸与轮位在 `truck.gd` 的 `L` / `W` / `AXLES`。
- 车灯：`truck.gd` 的 `LAMP_Y` / `LAMP_Z`（灯面位置）、`BEAM_LEN` / `BEAM_FAR` /
  `BEAM_PITCH`（光柱长度、张口、下压角）、`POOL_CENTER_X` / `POOL_HALF`（地面光斑）；
  亮度在 `_beam()` / `_pool()` 的 `strength`，SpotLight 本身在 `_build_lights()`。
  光柱变长之前先看一眼台面边缘 —— 超出 ±5.6 的部分会被裁掉，切口落在半空中很难看。
- 台面裁剪范围：`kit.gd` 的 `PLATFORM_CLIP`（和 `street.gd` 的 `B` 必须一致）。

## 调试截图

```bash
# 可玩版：13 张（全景 + 街道 + 门口 + 店内 + 货架过道 + 货架特写 ×2 + 冷柜 + 杂志架 + 休息室 + 货车裁剪 + 货车压脸 + 车头特写）→ shots/walk_*.png
./tools/run.sh store_walk -- --shot

# 只拍一张（调机位时用，省得全套跑一遍）：
./tools/run.sh store_walk -- --shot --only=walk_h_breakroom

# 商店街：7 张（出生点 / 东口牌楼 / 北排店面 / 南排住宅 / 便利店全景 / 牌楼西望 / 店内）→ shots/street_*.png
./tools/run.sh hoshi_street -- --shot
./tools/run.sh hoshi_street -- --shot --only=street_b_gate

# 加油站：6 张（到达 / 顶棚 / 油机 / 小卖亭 / 价格塔 / 全景）→ shots/gas_*.png
# 截图模式不建剧情道具，机位是给「空加油站」构图的
./tools/run.sh gas_station -- --shot

# 微缩展示版：7 个轨道机位 → shots/a_front.png 等
./tools/run.sh main -- --shot
```

`shots/` 是产物，**不进仓库**（见 `.gitignore`）。目录本身用 `.gitkeep` 保留，
否则 `--shot` 会因为目录不存在而静默失败。要归档某张图，单独拷出来当文档素材。

## 协作

分层、契约、CI、分支模型、迁移路线都在 [`docs/架构与协作规范.md`](docs/架构与协作规范.md)。

两个横切子系统的说明：

- [`docs/场景路由.md`](docs/场景路由.md)：出口本地化、目的地集中化，怎么新增场景 / 出口，剧情节点怎么推进；
- [`docs/音频总线.md`](docs/音频总线.md)：总线布局、四种播放形态、命名声道接管与 `owner` 生命周期。

日常只有四条：

- 改完跑 `./tools/check.sh`（回归）与 `./tools/lint_rules.sh`（规则），全绿再开 PR；
- 改了 `kit / store / street / props` 的公开签名，PR 里贴出全部调用方的 grep 结果；
- 不要为了看单个场景去改 `project.godot` 的 `main_scene`，用 `./tools/run.sh <场景>`；
- 新代码先 grep 有没有先例——这个工程很多东西已经有了（20 个建模原语、程序化音效、
  完整的 HUD 与交互中枢）。

### 用 AI 写代码

仓库根有 [`AGENTS.md`](AGENTS.md)：铁律 R1–R9、反直觉清单（角色朝向、骨骼枢轴、材质缓存、
输入事件）、命令速查。`CLAUDE.md` 与 `.github/copilot-instructions.md` 都只指向它——
**规则只维护一份**，多份必然漂移。

其中 R1–R6 不是纸面约定，`./tools/lint_rules.sh` 会真的检查：

| # | 检查什么 |
| --- | --- |
| R1 | `.tscn` 有没有被摆进第二个节点 |
| R2 | probe 有没有读 `_` 开头的私有字段 |
| R3 | 输入注册有没有新增第四份 |
| R4 | `res://` 路径有没有断链 |
| R5 | `project.godot` 的默认入口是否存在 |
| R6 | 截图 / 引擎二进制有没有混进索引 |

CI 里这两步都会跑，规则检查先跑（几秒），坏了不必等 20 秒的 probe。

### 大文件与 git-lfs

`assets/` 下的 `.glb` / `.png` 与 `audio/` 下的 `.wav` 走 git-lfs（规则见 `.gitattributes`）。
clone 之前先装：

```bash
# Arch / EndeavourOS  sudo pacman -S git-lfs
# Debian / Ubuntu    sudo apt install git-lfs
# macOS              brew install git-lfs
git lfs install
```

没装 lfs 时 `git add assets/...` 会直接报错——这是故意的：安全失败，好过把 15MB 的模型
塞进普通对象、再等半年才发现仓库有 500MB。

**历史已于 2026-10-21 迁移完成**（28 个 commit 重写，47 个指针文件）。所以现在
clone 之前必须装 lfs，否则 `assets/` 下拿到的是 130 字节的指针文本，
Godot 会报资源加载失败——看起来像「少了东西」，其实是没装 lfs。

检查环境（对新的 clone 或新机器有用）：

```bash
./tools/setup_lfs.sh --check     # 只检查，不动任何东西
```

`setup_lfs.sh` 的迁移功能已经用过一次。它拒绝在 worktree 里执行——`migrate --everything`
重写的是整个仓库的 refs，在 worktree 里跑会把主仓库的工作副本搞成一半新一半旧。
