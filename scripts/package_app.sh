#!/usr/bin/env bash
set -euo pipefail

# 定位 SwiftPM 项目根目录，保证从任意目录执行都能产出同一个 app bundle。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 默认打 release 包，也支持传 debug 方便本地排查。
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "用法: $0 [debug|release]" >&2
        exit 64
        ;;
esac

# 定义 bundle 名称和目录结构，保持产物集中在 dist 下。
APP_NAME="Codex Notch"
EXECUTABLE_NAME="CodexNotch"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-local.codex.notch}"
APP_VERSION="${APP_VERSION:-0.1.2}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
DIST_DIR="$APP_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP_BUNDLE="/Applications/$APP_NAME.app"
STAGED_APP_BUNDLE="/Applications/.$APP_NAME.app.staging"
PREVIOUS_APP_BUNDLE="/Applications/.$APP_NAME.app.previous"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 先通过 SwiftPM 编译可执行文件，再复制进 macOS app bundle。
cd "$APP_DIR"
swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/CodexNotch_CodexNotch.bundle"
THIRD_PARTY_NOTICE="$APP_DIR/THIRD_PARTY_NOTICES.md"

# DockCat 图片、许可证和归属说明必须同时进入 app，缺失时停止生成不完整产物。
if [[ ! -d "$RESOURCE_BUNDLE" || ! -f "$THIRD_PARTY_NOTICE" ]]; then
    echo "缺少 DockCat 资源 bundle 或第三方归属说明" >&2
    exit 66
fi

# 重建 bundle，避免旧产物残留影响本次 app 内容。
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
cp "$THIRD_PARTY_NOTICE" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"

# 写入最小 Info.plist，让 Finder 能把产物识别为 macOS 应用。
/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS_DIR/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
# 发布到 GitHub Releases 时从环境变量写入版本，确保应用内比较使用真实版本号。
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS_DIR/Info.plist"

# PkgInfo 是老式但无害的 app bundle 标记，方便部分工具识别 APPL bundle。
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# 先暂存新 bundle，再替换应用程序目录中的旧版本；替换失败会自动恢复旧副本。
rm -rf "$STAGED_APP_BUNDLE" "$PREVIOUS_APP_BUNDLE"
/usr/bin/ditto "$APP_BUNDLE" "$STAGED_APP_BUNDLE"
if [[ -e "$INSTALLED_APP_BUNDLE" ]]; then mv "$INSTALLED_APP_BUNDLE" "$PREVIOUS_APP_BUNDLE"; fi
if ! mv "$STAGED_APP_BUNDLE" "$INSTALLED_APP_BUNDLE"; then
    if [[ -e "$PREVIOUS_APP_BUNDLE" ]]; then mv "$PREVIOUS_APP_BUNDLE" "$INSTALLED_APP_BUNDLE"; fi
    echo "无法安装到: $INSTALLED_APP_BUNDLE" >&2
    exit 67
fi
rm -rf "$PREVIOUS_APP_BUNDLE"
echo "App 已生成: $APP_BUNDLE"
echo "App 已安装: $INSTALLED_APP_BUNDLE"
