# CLAUDE.md

本仓库的 AI 协作规则**只有一份**，在 [`AGENTS.md`](AGENTS.md)。
要改规则请改那里 —— 不要在这里复制一份，否则两份会漂移，而漂移的规范比没有规范更糟。

@AGENTS.md

---

## 三件最容易忘的事

1. 改完跑 `./tools/check.sh`（全量回归）和 `./tools/lint_rules.sh`（规则检查），全绿才算完成。
2. 为了看单个场景，用 `./tools/run.sh <场景>`，**不要改 `project.godot` 的 `main_scene`**。
3. `.tscn` 只允许 1 个根节点 + 1 个脚本，几何全部在 `_ready()` 里生成 —— 不要摆节点。

## 两条最容易踩的坑

- 角色模型**脸朝 +Z**，`atan2(dir.x, dir.z)` 正好，不要加 180°。
- `kit.toon()` 有全局材质缓存：同参数返回**同一个实例**，改一个会改到全部。
