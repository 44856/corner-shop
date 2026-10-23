#!/usr/bin/env bash
# 启用 git-lfs，并把历史里的二进制资产迁移过去。
#
# 为什么做成脚本、而不是我直接改仓库：
#   `git lfs migrate import` 会**重写历史**。不可逆（除非有备份），
#   而且所有协作者必须重新 clone。这种事必须由人按下确认键。
#
# 用法：
#   ./tools/setup_lfs.sh --check       只检查环境，不动任何东西
#   ./tools/setup_lfs.sh --rules-only  只确认 .gitattributes 已就位
#   ./tools/setup_lfs.sh               检查 → 二次确认 → 迁移历史
#
# 迁移完成后所有协作者都要重新 clone（旧的本地仓库里还是普通 blob）。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

MODE="${1:---run}"
# 与 .gitattributes 里的规则保持一致
PATTERNS="assets/**/*.glb,assets/**/*.png,audio/**/*.wav"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '  \033[2m·\033[0m %s\n' "$1"; }

install_hint() {
	cat <<'EOF'

先装 git-lfs，然后回来重跑：

  Arch / EndeavourOS   sudo pacman -S git-lfs
  Debian / Ubuntu      sudo apt install git-lfs
  Fedora               sudo dnf install git-lfs
  macOS                brew install git-lfs

装完执行一次（每个用户一次，不是每个仓库一次）：

  git lfs install

EOF
}

check_env() {
	local fail=0

	echo "环境检查"

	if git lfs version >/dev/null 2>&1; then
		ok "git-lfs $(git lfs version | sed 's/^git-lfs\///; s/ .*//')"
	else
		bad "没有 git-lfs"
		fail=1
	fi

	if git config --get filter.lfs.clean >/dev/null 2>&1; then
		ok "git lfs install 已执行"
	else
		bad "还没执行 git lfs install"
		fail=1
	fi

	if grep -q "filter=lfs" .gitattributes 2>/dev/null; then
		ok ".gitattributes 有 lfs 规则"
	else
		bad ".gitattributes 缺 lfs 规则"
		fail=1
	fi

	if [ "$fail" -ne 0 ]; then
		install_hint
		return 1
	fi
	return 0
}

echo "仓库：$ROOT"
echo ""

if [ "$MODE" = "--rules-only" ]; then
	if grep -q "filter=lfs" .gitattributes 2>/dev/null; then
		echo "规则已就位："
		grep -E "filter=lfs" .gitattributes | sed 's/^/  /'
		echo ""
		echo "注意：规则只影响**今后**的提交。历史里的旧 blob 仍然是普通对象，"
		echo "要压缩体积必须跑 ./tools/setup_lfs.sh 做历史迁移。"
		exit 0
	fi
	bad ".gitattributes 里没有 lfs 规则"
	exit 1
fi

check_env || exit 1
echo ""

if [ "$MODE" = "--check" ]; then
	echo "检查通过。要真正迁移历史，直接运行：./tools/setup_lfs.sh"
	exit 0
fi

# ---------------------------------------------------------------- 迁移历史

# 在 worktree 里跑是危险的：migrate 重写的是**整个仓库**的 refs，
# 会波及主仓库和其它 worktree 正在检出的分支。必须在主仓库做。
if [ -f "$ROOT/.git" ]; then
	bad "当前目录是 git worktree，不是主仓库"
	cat <<'EOF'

`git lfs migrate --everything` 会重写整个仓库的 refs，包括其它 worktree
正在检出的分支。在 worktree 里跑，会把主仓库的工作副本搞成一半新一半旧。

请到主仓库执行（git worktree list 的第一行）：

  cd /path/to/main-repo && ./tools/setup_lfs.sh

EOF
	exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
	echo "工作区不干净，migrate 会拒绝执行，也容易丢改动。"
	echo "先 commit 或 stash，再回来："
	git status --short | sed 's/^/  /' | head -15
	exit 1
fi

# 先做完整备份。bundle 包含所有 refs（分支、标签），可以整棵恢复。
BACKUP_DIR="$(dirname "$ROOT")"
BACKUP="$BACKUP_DIR/$(basename "$ROOT")-backup-$(date +%Y%m%d-%H%M%S).bundle"
echo "备份全部 refs 到："
echo "  $BACKUP"
if git bundle create "$BACKUP" --all >/dev/null 2>&1; then
	ok "备份完成（$(du -h "$BACKUP" | cut -f1)）"
else
	bad "备份失败，中止"
	exit 1
fi
echo ""

cat <<EOF
即将执行：

  git lfs migrate import --include="$PATTERNS" --everything

影响：
  · 重写本仓库全部历史（所有分支、标签、以及 origin/* 追踪引用的 commit hash 都会变）
  · 迁移后 develop 等分支会与远端分叉，必须 git push --force --all 与 --force --tags
  · 所有协作者必须重新 clone，否则本地是普通 blob、远端是指针，会互相打架
  · **所有其它 worktree 都要进各自的目录执行 git reset --hard**

回滚方式（如果结果不对）：
  git fetch "$BACKUP" 'refs/*:refs/*'   # 会覆盖 refs，谨慎

EOF

printf '确认执行？输入 yes 继续：'
read -r answer
if [ "$answer" != "yes" ]; then
	echo "已取消，什么都没改。"
	exit 1
fi

echo ""
git lfs migrate import --include="$PATTERNS" --everything

echo ""
echo "迁移完成。接下来按顺序："
echo "  1. git lfs ls-files | head        确认有指针文件"
echo "  2. git worktree list              每个 worktree 进去 git reset --hard"
echo "     （refs 被重写后，它们的工作副本还是旧内容）"
echo "  3. git push --force --all"
echo "  4. git push --force --tags"
echo "  5. 通知所有协作者：删掉本地仓库重新 clone"
echo ""
echo "备份留在：$BACKUP"
