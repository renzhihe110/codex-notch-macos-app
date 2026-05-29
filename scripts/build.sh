#!/usr/bin/env bash
set -euo pipefail

# 定位脚本所在项目根目录，保证从任意工作目录执行都能编译同一个 SwiftPM 包。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 支持 debug 和 release 两种 SwiftPM 配置，默认使用 debug 便于本地迭代。
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "用法: $0 [debug|release]" >&2
        exit 64
        ;;
esac

# 只执行 SwiftPM 编译，不启动应用、不运行测试。
cd "$APP_DIR"
swift build -c "$CONFIGURATION" --product CodexNotch

# 输出产物位置，方便手动运行或后续打包。
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
echo "编译完成: $BIN_DIR/CodexNotch"
