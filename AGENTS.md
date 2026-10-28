# AGENTS.md

> 给在这个仓库里写代码的 AI。人类入口是 `README.md`，架构决策是 `docs/架构与协作规范.md`。
>
> **规则不是建议。** 能自动检查的部分都有对应脚本：`./tools/lint_rules.sh` 的 R1–R6
> 就是本文第 3 节的编号。文档与脚本对不上时，以脚本为准，并且把文档改过来。

---

## 1. 这是什么

Godot 4.7.2 / Forward+ 的「雨夜便利店街角 + 商店街 + 国道加油站 + 异世界草原」多场景 Demo。
**全部几何、材质、灯光、雨效由 GDScript 运行时生成**，除 VRoid 角色模型外零外部资产。
约 1.6 万行 GDScript / 43 个脚本、7 个场景、10 组回归 probe（329 条断言）。

雨夜线（便利店 / 商店街 / 加油站）与草原在视觉上刻意对立：冷蓝低照度、湿地面反射 ↔ 明亮饱和。
二者的反差本身就是「穿越」的叙事信号，改配色时别把这条抹平。

---

## 2. 下笔前先读

| 顺序 | 读什么 | 什么时候需要 |
| --- | --- | --- |
| 1 | `docs/架构与协作规范.md` | 不知道新代码该放哪、要不要改共享库时 |
| 2 | `README.md` | 要跑、要截图、要改某个具体效果时 |
| 3 | `docs/任务0X-*.md` | 手上有明确任务时（里面有实测参数，直接用，别重测） |
| 4 | 同目录下已有的实现 | **永远**。见下面这条 |

### 先 grep，再动手

这个工程里很多「看起来该新写」的东西已经有了：`kit.gd` 有 20 个建模原语、`sfx.gd` 有程序化音效、
`hud.gd` 有完整的提示/区域/淡入淡出、`interaction_hub.gd` 有「谁最近就提示谁」。
2026-10-23 之后又多三个入口：`AudioBus` 管所有播放、`SceneRouter` 管所有跨场景切换、
`kit.batch_static()` 管静态街景合批。新写一份的代价不是多写几百行，是**从此有两份会各自漂移的实现**。

```bash
grep -rn "关键词" --include=*.gd scripts
```

---

## 3. 铁律

| # | 规则 | 为什么 | 检查 |
| --- | --- | --- | --- |
| R1 | `.tscn` 只允许 1 个根节点 + 1 个脚本，几何全部 `_ready()` 生成 | 这是本工程能做**文本 diff** 的前提。摆节点会产生无法人工合并的 `Transform3D` 冲突 | 自动 |
| R2 | probe 只读公开接口，不碰 `_` 开头字段 | 读私有字段会让内部重构静默打断测试，并且没有编译错误提醒 | 自动 |
| R3 | 不要新增第四份输入注册 | 现在有 3 份（`dog` / `interaction_hub` / `player_controller`），键位仍不统一（dog 注册 F、其余场景 hub 注册 E）。第四份出现说明有人在复制而不是复用 | 自动 |
| R4 | `res://` 路径必须真实存在 | 改名/搬文件最容易留断链，而且只在运行时炸 | 自动 |
| R5 | `project.godot` 的 `run/main_scene` 必须存在 | 这条真的坏过：指向 `opening_flow`，README 说入口是 `store_walk` | 自动 |
| R6 | 截图、`Godot_v*` 二进制、`.godot/` 不进索引 | 截图每次重渲都是二进制 diff；引擎 146MB | 自动 |
| R7 | 改完必须跑 `./tools/check.sh`，全绿才算完成 | 「看起来正常」不是证据。probe 会告诉你门是不是真的能过 | 人工 |
| R8 | 改 `kit / store / street / props` 的公开签名 = 改契约 | 它们分别被 20 / 7 / 3 / 8 个文件引用，改签名是隐形破坏。`core/` 与 `audio/` 的公开方法同样是契约 | 人工 |
| R9 | 不引第三方框架、不引 ECS、不把程序化改成编辑器摆场景 | 实体只有几十个，框架成本大于收益；摆场景会失去 diff 能力 | 人工 |

### R8 的正确做法

改共享库签名时，同一个 PR 里：

```bash
# 1. 先看谁在用
grep -rn "Store.build\|Store.layout" --include=*.gd scripts tools
# 2. 全部改完
# 3. 把上面的 grep 结果贴进 PR 描述
```

新增参数必须**默认为旧行为**，否则就是破坏性变更。

---

## 4. 这个工程反直觉的地方

这一节全是踩过的坑，每条都有代价。**别凭 Godot 常识推断，先看这里。**

### 角色模型

- **脸朝 +Z。** `visual.rotation.y = atan2(dir.x, dir.z)` 的含义就是「让 +Z 指向移动方向」，
  正好匹配。**不要再加 180°**，加了就是倒着走。
- **枢轴在脚底**（T-pose 包围盒 `min_y = 0`）。所以「躺下」不能转 −80°——那是把身体当一块斜 10° 的
  木板，只有小腿着地、头悬空 0.3m。**要 −90°**。转完之后背面会落到 `y = −0.19`，
  `position.y` 必须 **+0.19** 才贴地，否则整个人埋在草里。
- **前臂只能绕 Z 轴弯。** 绕 X 轴是沿骨骼自身扭转，手不会动。已验证，别再试。

### 输入

- **`Input.action_press()` 不产生事件**，只改动作状态。走 `_unhandled_input` 的交互收不到，
  用它测会得到「怎么按都没反应」的假故障。测交互必须 `parse_input_event`。
  测移动可以用 `action_press`（移动读的是 `_physics_process` 里的动作状态）——
  `walk_probe` 和 `grassland_probe` 的差异就在这里，不是随手写的。

### 场景路由

- **切场景只有一条路：`SceneRouter.goto()`。** 直调 `change_scene_to_file()` 会绕过抵达上下文、
  转场锁和剧情节点推进，新场景拿不到 arrival。`letter_transition.gd` 是唯一的执行层例外。
- **arrival 只能消费一次，而且必须在 `_ready()` 顶部取。** 先搭 UI、再取 arrival，读到的就是 `{}`。
  取到后把 `mode` 交给场景自己的开场逻辑，别再让转场和场景各淡一次黑。
- **反向出口不改 story 节点。** 从 ep2 走回 ep1 只换可见场景，不回滚叙事进度；
  剧情节点只由正向首次抵达推进。把回程也写成 `goto(..., "story")` 会让读档退回上一章。
- **`WorldLinks.resolve()` 是纯函数。** 不读 `GameState`、不 `await`、不加副作用；
  `router_probe` 的 79 条断言靠的就是「输入相同、输出一定相同」。要新状态就显式传参。

### 音频

- **所有播放走 `AudioBus`，不要 `new AudioStreamPlayer`。** 自己建播放器会绕开总线、
  场景切换清理、优先级抢占和 `AudioVoice` 句柄，音量也漏掉 `Music` / `Ambience` 总线。
- **循环只能播副本。** `Sfx.*` 返回的是 static 缓存实例，直接改 `loop_mode` 会让所有使用者一起循环。
  `AudioBus.channel()` 内部已经 `duplicate()`，别绕开它自己改流。
- **循环声道要用 `stop_channel()` 停。** 循环流永远不发 `finished`，`AudioVoice.stop()` 之后
  声道元数据仍在；只有 `stop_channel()` / owner 释放会回收它。
- **跨场景长音才挂 `owner`。** `AudioBus` 切场景时只清一次性 2D/3D 音效，不清声道；
  一次性氛围音忘了绑 owner，就会在下一个场景继续响。
- **转场切声归 `SceneRouter`。** `goto()` 进转场时调 `AudioBus.cut_for_transition()`，
  旧场景的声道 / 一次性音效 / 3D 池一起收，切场景之前保持静音；新场景在 `_ready` 里重新申请。
  别在场景里自己停雨声来模拟转场。

### 渲染与材质

- **`kit.toon()` 有全局材质缓存**（`static var _cache`，key 由全部参数拼成）。
  同参数调用返回**同一个 `ShaderMaterial` 实例**，跨场景共享。
  改一个物体的材质参数，会改到所有用同参数建出来的物体。
  需要独立材质时：`mat.duplicate()`，或者让参数有区分度。
- **门叶是 `AnimatableBody3D` 本身。** 玻璃、门框、把手、碰撞盒都是它的子节点，
  开合补间挪的是物理体。所以「门开了」和「人能过」是同一件事——
  **不要单独去挪碰撞盒**，否则会出现门开着但人被隐形墙挡住。
- 店内只有 4.2 × 4.2m。第三人称弹簧臂**超过 1.6m 就会永远贴在货架或柜台上**，
  所以 `CAM_IN` 是 1.6m + FOV 70° + 右肩偏移，不是随便调的。
- 雨是按 xz 采样「该列最高的可接雨表面」再决定回收的。加新的遮雨结构（雨棚、屋檐）
  必须同步更新那份表面表，否则雨会穿过去继续下。
- **`kit.batch_static()` 要在静态几何建完、动态节点加入之前调用。** 它合的是调用那一刻已存在的网格，
  后加的节点合不进去。脚本子树、碰撞体、非 toon 材质、蒙皮网格会被跳过——所以别把会动的门 /
  角色挂在被合批的分支下，也别指望合批后还能按节点改材质或显隐（原 `MeshInstance3D` 已被移除，
  只剩按「材质 + 阴影模式」分桶的合并网格）。

### 性能与启动

- `.godot/` 不入库。换机器第一次启动会自动导入（约 1 分钟）。
  缺了导入，音频和 `gaia.glb` 会加载失败，场景看起来像「少了东西」——不是代码 bug。

### 工具链

- **Godot 打包脚本错误时经常仍然 exit 0。** 所以 `check.sh` 的失败判定有三条：
  退出码、输出里的 `SCRIPT ERROR`/`Parse Error`、probe 自己打印的 failed 计数。
  只信退出码会漏。
- **新增 `class_name` 可能只在 CI 炸。** 本地 `.godot/global_script_class_cache.cfg` 是热的；
  CI 缓存的 `.godot` 不含 `scripts/` 的哈希，Godot 不会重建全局类表，于是报 `Could not find type`。
  `check.sh` 现在按 `.gd` 内容哈希刷新缓存；绕开它直接跑引擎时，先删掉那个 cfg。

---

## 5. 命令

```bash
./tools/run.sh                      # 默认入口
./tools/run.sh store_walk           # 单场景（简写，自动补路径）
./tools/run.sh list                 # 有哪些场景
./tools/run.sh --headless walk_probe
./tools/run.sh --headless router_probe  # 路由规则（纯函数，79 条）
./tools/run.sh --headless audio_probe   # 音频合并 / 生命周期（42 条）
./tools/run.sh store_walk -- --shot # 透传参数
./tools/run.sh -n store_wal         # dry run，只看命令

./tools/check.sh                    # 全量回归（先跑这个）
./tools/lint_rules.sh               # 规则检查（R1–R6）
./tools/setup_lfs.sh --check        # 大文件环境检查
```

**永远不要为了看某个场景去改 `project.godot` 的 `main_scene`。** 用 `run.sh`，改主文件的代价是
diff 噪声 + 和别人的分支打架。

引擎由 `tools/_godot.sh` 自动探测（`GODOT_BIN` → 项目根 → `~/godot*/` → PATH）。

---

## 6. 代码风格

跟随现有代码，不要引入第二套风格：

- **静态类型标注**。`func build(root: Node3D) -> void`，不是 `func build(root)`。
- **中文注释，解释「为什么」不是「是什么」。** 现有代码的注释密度很高，且大量记录
  「试过什么、为什么不行」（例如 `-80°` 为什么改成 `-90°`）。新增代码保持这个标准——
  这不是冗余，是这个仓库最值钱的部分。
- 常量 `UPPER_SNAKE`，私有成员 `_` 前缀，公开 API 才允许无前缀。
- 一个函数只做一件事。`store_walk.gd` 的 `_setup_*` 系列是样板。
- 不要写 `#region`、不要写多行分隔线装饰（现有代码用 `# ---- 标题` 单行，跟随它）。

---

## 7. 提交与分支

- **trunk-based**：`develop` 是主干，`feature/<集号>-<模块>` 寿命 ≤ 3 天。
- 禁止直接提交到 `develop`，所有改动走 PR（哪怕只有两个人）。
- `backup/*` 只读，用于对照与回滚。
- 提交信息用 Conventional Commits：`feat:` / `fix:` / `docs:` / `chore:` / `merge:`。
- PR 走 `.github/pull_request_template.md` 的检查表。

---

## 8. 卡住的时候

1. **先 grep 有没有先例。** 这个工程的注释密度意味着答案大概率已经在某处写着。
2. **不要猜 Godot API。** 版本是 4.7.2，和网上多数 4.x 教程有差异（例如 `AnimatableBody3D` 的行为、
   `static var` 的支持）。不确定就查官方文档或写 10 行最小验证。
3. **拿不准就问，不要静默选一个方向写 500 行。** 返工 500 行的成本远高于问一句。
4. **改完自问：这个改动会不会让另一个场景坏掉？** 共享库（`kit / store / street / props / hud /
   interaction_hub / player_controller`）都同时服务多个场景。
5. **不确定要不要动某段代码时，先看它的注释。** 里面经常写着「为什么不能改」。
