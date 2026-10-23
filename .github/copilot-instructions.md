本仓库的 AI 协作规则统一维护在 `AGENTS.md`，请以它为唯一依据（不要另外维护一份）。

摘要：

- `.tscn` 只允许 1 个根节点 + 1 个脚本，几何由 GDScript 在 `_ready()` 里生成。
  不要在编辑器里摆节点、不要手写大段 `Transform3D`。
- 共享库 `kit / store / street / props` 的公开签名是契约。改签名必须同一个改动里更新全部调用方。
- 改完跑 `./tools/check.sh` 与 `./tools/lint_rules.sh`，全绿才算完成。
- 单场景运行用 `./tools/run.sh <场景>`，不要改 `project.godot` 的 `main_scene`。
- probe 只读公开接口，不碰 `_` 开头的字段。

反直觉清单（角色朝向、骨骼枢轴、材质缓存全局共享、输入事件与动作状态的区别）
与完整规则见 `AGENTS.md` 第 4 节。架构分层见 `docs/架构与协作规范.md`。
