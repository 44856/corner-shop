#!/usr/bin/env bash
# 回归检查：跑 tools/ 下全部 *_probe.tscn，一条命令给总结果。
#
# 这是给 CI 和"改完想确认没弄坏别人"用的：
#   ./tools/check.sh
#
# 判定失败的条件有三条（缺一不可，只靠退出码会漏）：
#   1. probe 退出码非 0；
#   2. 输出里有 SCRIPT ERROR / Parse Error（Godot 有时照样退出 0）；
#   3. probe 自己打印的 failed 计数非 0。
#
# 新增 probe 只要命名成 tools/xxx_probe.tscn 就会被自动纳入，不用改这个脚本。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=tools/_godot.sh
. "$ROOT/tools/_godot.sh"

GODOT="$(godot_bin_or_die)"

# .godot 存在不等于可用：class_name 的注册表（global_script_class_cache.cfg）
# 只在 --editor 启动时重建，而 CI 会整包还原旧的 .godot（缓存 key 不含 scripts/）。
# 新增一个 class_name 之后，缓存里没有这条，probe 就会报
# 「Could not find type XXX in the current scope」—— 本地因为刚开过编辑器永远复现不了。
# 用 .gd 内容哈希做标记：对不上就重新导入，让导入自己刷新类缓存。
SCRIPTS_HASH="$(find "$ROOT/scripts" "$ROOT/tools" -name '*.gd' -type f -print0 \
	| sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
STAMP="$ROOT/.godot/gd_scripts_hash"

if [ ! -d "$ROOT/.godot" ] || [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$SCRIPTS_HASH" ]; then
	echo "导入资源 / 刷新全局类缓存"
	"$GODOT" --headless --path "$ROOT" --editor --quit >/tmp/godot_import.log 2>&1
	if [ $? -ne 0 ]; then
		echo "导入失败，日志：/tmp/godot_import.log" >&2
		exit 1
	fi
	echo "$SCRIPTS_HASH" >"$STAMP"
fi

PROBES=()
for p in tools/*_probe.tscn; do
	[ -f "$p" ] && PROBES+=("$p")
done

if [ ${#PROBES[@]} -eq 0 ]; then
	echo "tools/ 下没有 *_probe.tscn，无事可做。" >&2
	exit 1
fi

PASSED=0
FAILED=0
FAILED_LIST=()

for p in "${PROBES[@]}"; do
	echo ""
	echo "── $p"
	out=$("$GODOT" --headless --path "$ROOT" "res://$p" 2>&1)
	rc=$?
	echo "$out" | grep -E "^\s*\[ OK \]|^\s*\[FAIL\]|==== |SCRIPT ERROR|Parse Error" || true

	bad=0
	if [ "$rc" -ne 0 ]; then
		echo "  !! 退出码 $rc"
		bad=1
	fi
	if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error"; then
		echo "  !! 输出里有脚本错误"
		bad=1
	fi
	if echo "$out" | grep -qE "==== .* [1-9][0-9]* failed"; then
		bad=1
	fi

	if [ "$bad" -eq 0 ]; then
		PASSED=$((PASSED + 1))
	else
		FAILED=$((FAILED + 1))
		FAILED_LIST+=("$p")
	fi
done

echo ""
echo "────────────────────────────────────────"
if [ "$FAILED" -eq 0 ]; then
	echo "全部通过：$PASSED 个探针"
	exit 0
fi
echo "失败 $FAILED 个，通过 $PASSED 个"
printf '  %s\n' "${FAILED_LIST[@]}"
exit 1
