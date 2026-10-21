#!/usr/bin/env bash
# 单场景运行入口：不改 project.godot，就能跑任意一个场景。
#
# 为什么需要它：Godot 本来支持命令行指定场景
# （godot --path . res://scenes/x.tscn），但每次手打完整路径容易错。
# 更关键的是 —— 想单独看某个场景时，**不要去改 project.godot 的 main_scene**。
# 主文件改来改去，diff 里全是噪声，还会和别人的分支打架。
#
# 用法：
#   ./tools/run.sh                        跑默认入口（project.godot 的 main_scene）
#   ./tools/run.sh store_walk             跑 res://scenes/store_walk.tscn
#   ./tools/run.sh walk_probe             跑 res://tools/walk_probe.tscn
#   ./tools/run.sh list                   列出所有可跑的场景
#   ./tools/run.sh --headless walk_probe  无窗口
#   ./tools/run.sh store_walk -- --shot   透传参数给场景（-- 之后原样传给引擎）
#   ./tools/run.sh --editor store_walk    打开编辑器并定位到该场景
#   ./tools/run.sh -n store_wal           只打印要执行的命令，不真的跑（--dry-run）
#
# 引擎探测见 tools/_godot.sh；也可以用 GODOT_BIN 指定。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck source=tools/_godot.sh
. "$ROOT/tools/_godot.sh"

HEADLESS=0
EDITOR=0
DRY_RUN=0
TARGET=""
USER_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		--headless) HEADLESS=1; shift ;;
		--editor)   EDITOR=1; shift ;;
		-n|--dry-run) DRY_RUN=1; shift ;;
		--)
			shift
			USER_ARGS=("$@")
			break
			;;
		-*)
			echo "未知选项：$1（用 --help 看用法）" >&2
			exit 2
			;;
		*)
			if [ -n "$TARGET" ]; then
				echo "只接受一个场景名，多出来的「$1」不认识。" >&2
				echo "要透传给场景的参数请放在 -- 之后。" >&2
				exit 2
			fi
			TARGET="$1"
			shift
			;;
	esac
done

list_scenes() {
	local p name
	echo "scenes/"
	for p in scenes/*.tscn; do
		[ -f "$p" ] || continue
		name="$(basename "$p" .tscn)"
		printf '  %-18s res://%s\n' "$name" "$p"
	done
	echo "tools/（回归测试与截图）"
	for p in tools/*.tscn; do
		[ -f "$p" ] || continue
		name="$(basename "$p" .tscn)"
		printf '  %-18s res://%s\n' "$name" "$p"
	done
}

SCENE_PATH=""

resolve_scene() {
	local q="$1"
	case "$q" in
		res://*) SCENE_PATH="$q"; return 0 ;;
	esac
	if [ -f "$q" ]; then
		SCENE_PATH="res://$q"
		return 0
	fi
	q="${q%.tscn}"
	local p name
	for p in "scenes/$q.tscn" "tools/$q.tscn"; do
		if [ -f "$p" ]; then
			SCENE_PATH="res://$p"
			return 0
		fi
	done

	local hits=()
	for p in scenes/*.tscn tools/*.tscn; do
		[ -f "$p" ] || continue
		name="$(basename "$p" .tscn)"
		case "$name" in
			"$q"*) hits+=("$p") ;;
		esac
	done
	if [ ${#hits[@]} -eq 1 ]; then
		SCENE_PATH="res://${hits[0]}"
		return 0
	fi
	if [ ${#hits[@]} -gt 1 ]; then
		echo "「$q」匹配到多个场景，说不清要跑哪个：" >&2
		printf '  %s\n' "${hits[@]}" >&2
		return 2
	fi
	return 1
}

if [ "$TARGET" = "list" ]; then
	list_scenes
	exit 0
fi

if [ -n "$TARGET" ]; then
	rc=0
	resolve_scene "$TARGET" || rc=$?
	if [ "$rc" -eq 1 ]; then
		echo "找不到场景「$TARGET」。用 ./tools/run.sh list 看有哪些。" >&2
		exit 2
	fi
	[ "$rc" -ne 0 ] && exit 2
fi

GODOT="$(godot_bin_or_die)"

CMD=("$GODOT")
[ "$HEADLESS" -eq 1 ] && CMD+=(--headless)
CMD+=(--path "$ROOT")
[ "$EDITOR" -eq 1 ] && CMD+=(-e)
[ -n "$SCENE_PATH" ] && CMD+=("$SCENE_PATH")
if [ ${#USER_ARGS[@]} -gt 0 ]; then
	CMD+=(--)
	CMD+=("${USER_ARGS[@]}")
fi

printf '\033[2m$ %s\033[0m\n' "${CMD[*]}"
if [ "$DRY_RUN" -eq 1 ]; then
	exit 0
fi
exec "${CMD[@]}"
