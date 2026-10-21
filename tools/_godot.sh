# 被 run.sh / check.sh source：定位 Godot 可执行文件。
# 不直接执行，所以没有 shebang。
#
# 探测顺序（先到先得）：
#   1. $GODOT_BIN                     —— CI 与"我这台机器装在奇怪地方"用这个
#   2. 项目根的 Godot_v*.x86_64       —— README 一直以来的放法
#   3. $HOME/godot*/Godot_v*.x86_64   —— 集中放在 home 下（godot-spike / godot-4.7 之类）
#   4. $HOME/godot/godot
#   5. PATH 里的 godot4 / godot

godot_bin() {
	if [ -n "${GODOT_BIN:-}" ] && [ -x "${GODOT_BIN}" ]; then
		printf '%s' "$GODOT_BIN"
		return 0
	fi

	local c
	c=$(ls -1 "$ROOT"/Godot_v*-stable_linux.x86_64 2>/dev/null | head -1)
	if [ -n "$c" ] && [ -x "$c" ]; then
		printf '%s' "$c"
		return 0
	fi

	# home 下任意 godot-* 目录里的稳定版引擎
	c=$(ls -1 "$HOME"/godot*/Godot_v*-stable_linux.x86_64 2>/dev/null | head -1)
	if [ -n "$c" ] && [ -x "$c" ]; then
		printf '%s' "$c"
		return 0
	fi

	if [ -x "$HOME/godot/godot" ]; then
		printf '%s' "$HOME/godot/godot"
		return 0
	fi

	if command -v godot4 >/dev/null 2>&1; then
		command -v godot4
		return 0
	fi
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return 0
	fi

	return 1
}

# 找不到引擎时统一给一段能照抄的提示，而不是让脚本静默失败。
godot_bin_or_die() {
	local bin
	if ! bin=$(godot_bin); then
		cat >&2 <<'EOF'
找不到 Godot 4.7.2。任选一种：

  1. 下载到项目根（.gitignore 已经忽略它，不会进仓库）：
     curl -L -o g.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
     unzip g.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64

  2. 已经有的话，直接用环境变量指过来：
     GODOT_BIN=/path/to/godot ./tools/run.sh ...

  3. 走 PATH：
     sudo ln -s /path/to/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot4
EOF
		exit 1
	fi
	printf '%s' "$bin"
}
