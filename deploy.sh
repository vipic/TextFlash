#!/bin/bash
# TextFlash Deploy — 快速开发部署
# 流程：debug 编译 → 原地更新 .app → 注入开发版版本号 → 签名 → 启动
set -e
set -o pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TextFlash"
BUILD_DIR="$PROJECT_DIR/.build/debug"
RESOURCE_DIR="$PROJECT_DIR/Sources/TextFlash/Resources"
APP_DIR="$HOME/Applications/${APP_NAME} Dev.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
IDENTITY="${CODESIGN_IDENTITY:-Nekutai}"

echo "⚡ Deploying $APP_NAME (debug)..."
if [ "$IDENTITY" = "-" ]; then
    echo "🔐 签名身份: ad-hoc"
else
    echo "🔐 签名身份: $IDENTITY"
fi

cd "$PROJECT_DIR"

rm -rf "$RESOURCE_BUNDLE"
swift build -Xswiftc -DDISABLE_PREVIEWS
test -f "$BUILD_DIR/$APP_NAME" || { echo "❌ 构建失败"; exit 1; }
echo "✅ Debug 编译完成"

pkill -f "$APP_DIR" 2>/dev/null || true
for _ in $(seq 1 10); do
    if ! pgrep -f "$APP_DIR" > /dev/null 2>&1; then break; fi
    sleep 0.2
done

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

if [ -f "$RESOURCE_DIR/Assets/AppIcon.icns" ]; then
    cp "$RESOURCE_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -d "$RESOURCE_BUNDLE" ]; then
    rm -rf "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi
echo "✅ .app bundle 已更新: $APP_DIR"

DEPLOY_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0")
LATEST_TAG="${LATEST_TAG#v}"
DEV_VERSION="${LATEST_TAG}-dev+${DEPLOY_HASH}"

if [ ! -f "$CONTENTS/Info.plist" ]; then
    cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.nekutai.textflash.dev</string>
    <key>CFBundleName</key>
    <string>$APP_NAME Dev</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME Dev</string>
    <key>CFBundleVersion</key>
    <string>$DEPLOY_HASH</string>
    <key>CFBundleShortVersionString</key>
    <string>$DEV_VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>TextFlash 需要辅助功能权限以监听键盘事件并展开文本。</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>TextFlash 需要辅助功能权限以监听键盘事件并展开文本。</string>
</dict>
</plist>
PLIST
else
    set_plist_string() {
        local key="$1"
        local value="$2"
        /usr/libexec/PlistBuddy -c "Set :$key $value" "$CONTENTS/Info.plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$CONTENTS/Info.plist"
    }

    set_plist_string "CFBundleIdentifier" "com.nekutai.textflash.dev"
    set_plist_string "CFBundleName" "$APP_NAME Dev"
    set_plist_string "CFBundleDisplayName" "$APP_NAME Dev"
    set_plist_string "CFBundleVersion" "$DEPLOY_HASH"
    set_plist_string "CFBundleShortVersionString" "$DEV_VERSION"
fi
echo "✅ 版本号已注入: $DEV_VERSION"

rm -rf "$APP_DIR/_CodeSignature" 2>/dev/null || true
if [ "$IDENTITY" != "-" ]; then
    if codesign --force --sign "$IDENTITY" "$APP_DIR"; then
        :
    else
        echo "⚠️  \"$IDENTITY\" 签名失败，回退 ad-hoc"
        codesign --force --sign - "$APP_DIR" 2>/dev/null || true
        echo "⚠️  已用 ad-hoc 签名（TCC 授权不持久）"
    fi
else
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
    echo "⚠️  已用 ad-hoc 签名（TCC 授权不持久）"
fi
echo "✅ 代码签名完成"

echo "🚀 启动 $APP_NAME..."
open "$APP_DIR"
echo "✅ Deploy 完成"
