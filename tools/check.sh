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

if [ ! -d "$ROOT/.godot" ]; then
	echo "首次运行：先导入资源（约 1 分钟，之后会走缓存）"
	"$GODOT" --headless --path "$ROOT" --editor --quit >/tmp/godot_import.log 2>&1
	if [ $? -ne 0 ]; then
		echo "导入失败，日志：/tmp/godot_import.log" >&2
		exit 1
	fi
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
