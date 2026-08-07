#!/usr/bin/env bash
set -euo pipefail

# 定位脚本目录与项目根目录，保证从任意工作目录执行时路径一致。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="${1:-debug}"

# 复用现有打包脚本生成完整 App Bundle，避免裸可执行文件缺少系统 Bundle 上下文。
"$SCRIPT_DIR/package_app.sh" "$CONFIGURATION"
APP_BUNDLE="$APP_DIR/dist/Codex Notch.app"
TERMINAL_DEVICE="$(tty 2>/dev/null || printf '/dev/null\n')"

# 通过 LaunchServices 前台启动 App，并把运行日志转回当前终端。
stop_started_app() {
    pkill -TERM -n -x CodexNotch >/dev/null 2>&1 || true
}
trap stop_started_app INT TERM
set +e
echo "启动: $APP_BUNDLE"
/usr/bin/open -W -n --stdout "$TERMINAL_DEVICE" --stderr "$TERMINAL_DEVICE" "$APP_BUNDLE"
OPEN_EXIT=$?
set -e
trap - INT TERM
exit "$OPEN_EXIT"
