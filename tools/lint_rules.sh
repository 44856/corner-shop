#!/usr/bin/env bash
# 把 AGENTS.md 里的「铁律」变成可执行的检查。
#
# 文档里的规则靠自觉，脚本里的规则靠退出码。后者才拦得住人。
# 每一条都对应 AGENTS.md 的编号，改了规则记得两边一起改。
#
#   ./tools/lint_rules.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PASS=0
FAIL=0
FAILED_NAMES=()

ok() {
	PASS=$((PASS + 1))
	printf '  \033[32m[ OK ]\033[0m %s\n' "$1"
}

bad() {
	FAIL=$((FAIL + 1))
	FAILED_NAMES+=("$1")
	printf '  \033[31m[FAIL]\033[0m %s\n' "$1"
	if [ -n "${2:-}" ]; then
		printf '%s\n' "$2" | sed 's/^/         /'
	fi
}

echo "规则检查"

# ---------------------------------------------------------------- R1
# 场景里不许摆节点。这个工程的全部几何都由 GDScript 生成，
# .tscn 只允许「一个根节点 + 一个脚本」——这是它能做文本 diff 的前提。
r1_bad=""
r1_count=0
for f in scenes/*.tscn tools/*.tscn; do
	[ -f "$f" ] || continue
	r1_count=$((r1_count + 1))
	n=$(grep -c '^\[node ' "$f")
	if [ "$n" -ne 1 ]; then
		r1_bad="$r1_bad$f 有 $n 个 node（应为 1）"$'\n'
	fi
done
if [ -z "$r1_bad" ]; then
	ok "R1 场景不摆节点（$r1_count 个 .tscn，各 1 个根节点）"
else
	bad "R1 场景不摆节点" "$r1_bad"
fi

# ---------------------------------------------------------------- R2
# probe 只准读公开接口。读 _ 开头字段会让内部重构静默打断测试，
# 而且断的时候没有任何编译错误。
r2_bad=$(grep -rnE '\.[_][a-zA-Z]' tools/*.gd 2>/dev/null || true)
if [ -z "$r2_bad" ]; then
	ok "R2 probe 不读私有字段"
else
	bad "R2 probe 不读私有字段" "$r2_bad"
fi

# ---------------------------------------------------------------- R3
# 输入注册不许再增加。现在有三份（P2 要收口到一份），
# 但第四份出现就说明有人又复制了一份，而不是复用。
r3_allowed="scripts/dog.gd scripts/interaction_hub.gd scripts/player_controller.gd"
r3_files=$(grep -rl "_ensure_action" --include=*.gd scripts tools 2>/dev/null | sed 's|^\./||' | sort)
r3_extra=""
for f in $r3_files; do
	case " $r3_allowed " in
		*" $f "*) ;;
		*) r3_extra="$r3_extra$f"$'\n' ;;
	esac
done
r3_n=$(printf '%s\n' "$r3_files" | grep -c . || true)
if [ -z "$r3_extra" ]; then
	ok "R3 输入注册没有新增（$r3_n 处，均已登记）"
else
	bad "R3 输入注册没有新增" "白名单之外出现 _ensure_action：
$r3_extra
如果确实需要，先加到本脚本的 r3_allowed；能复用就别新写。"
fi

# ---------------------------------------------------------------- R4
# res:// 路径必须真实存在。改名/搬文件最容易留下的就是断链，
# 而这种错在运行时才炸，且往往只炸一个分支。
r4_bad=""
r4_count=0
r4_tmp=$(mktemp)
grep -rhoE "res://[A-Za-z0-9_./%-]+" --include=*.gd --include=*.tscn scripts tools scenes 2>/dev/null \
	| sort -u > "$r4_tmp"
while IFS= read -r p; do
	case "$p" in
		*%*|*shots/*) continue ;;
	esac
	r4_count=$((r4_count + 1))
	if [ ! -e "${p#res://}" ]; then
		r4_bad="$r4_bad$p 不存在"$'\n'
	fi
done < "$r4_tmp"
rm -f "$r4_tmp"
if [ -z "$r4_bad" ]; then
	ok "R4 资源路径不断链（$r4_count 个 res:// 引用）"
else
	bad "R4 资源路径不断链" "$r4_bad"
fi

# ---------------------------------------------------------------- R5
# 默认入口必须存在。这条曾经真的坏过：
# project.godot 指向 opening_flow，README 说当前入口是 store_walk。
r5_main=$(sed -n 's/^run\/main_scene="\(.*\)"$/\1/p' project.godot | head -1)
if [ -z "$r5_main" ]; then
	bad "R5 默认入口存在" "project.godot 里没有 run/main_scene"
elif [ -e "${r5_main#res://}" ]; then
	ok "R5 默认入口存在（$r5_main）"
else
	bad "R5 默认入口存在" "$r5_main 不存在"
fi

# ---------------------------------------------------------------- R6
# 产物与引擎二进制不许进索引。截图每次重渲都是二进制 diff，
# 引擎有 146MB —— 这两样进历史，clone 和 review 都会变慢。
r6_bad=$(git ls-files 2>/dev/null | grep -E '^shots/.+\.(png|import)$|^Godot_v.*x86_64$|^\.godot/' || true)
if [ -z "$r6_bad" ]; then
	ok "R6 产物与引擎未入库"
else
	bad "R6 产物与引擎未入库" "$r6_bad"
fi

# ---------------------------------------------------------------- 汇总

echo "────────────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
	echo "规则检查通过：$PASS 条"
	exit 0
fi
echo "规则检查失败：$FAIL 条（通过 $PASS 条）"
printf '  · %s\n' "${FAILED_NAMES[@]}"
exit 1
