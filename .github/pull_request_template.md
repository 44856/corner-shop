## 这个 PR 改了什么

<!-- 一句话。如果是修 bug，写清复现路径。 -->

## 检查表

- [ ] `./tools/check.sh` 全绿（贴最后一行输出）
- [ ] 若改了 `kit / store / street / props` 的公开签名：贴出全部调用方的 grep 结果
- [ ] 没有新增第三份输入注册（`_ensure_action` 只应存在于 `player_controller` 与 `interaction_hub` 各一处，中期收口到 `core/`）
- [ ] 新增断言没有读 `_` 开头的私有字段
- [ ] 截图没有直接提交进仓库（`shots/` 是产物，走本地生成）

## 顺手留下的技术债

<!-- 有就写，没有就写"无"。别让下一棒猜。 -->
