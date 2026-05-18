#!/bin/bash
# TextFlash Deploy — 开发快速部署
# 流程：debug 编译 → 签名 → 部署到 ~/Applications/TextFlash Dev.app → 启动
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TextFlash"
BUILD_DIR="$PROJECT_DIR/.build/debug"
BUNDLE_ID="com.nekutai.textflash.dev"
IDENTITY="${CODESIGN_IDENTITY:-TextFlash Dev}"

cd "$PROJECT_DIR"

# ── 1. Debug 编译 ──
echo "⚡ Deploying $APP_NAME (debug)..."
echo "Building for debugging..."
swift build 2>&1 | tail -1

BIN="$BUILD_DIR/$APP_NAME"
test -f "$BIN" || { echo "❌ 构建失败"; exit 1; }

# ── 2. 组装 .app ──
STAGING="$PROJECT_DIR/.deploy_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/$APP_NAME Dev.app/Contents/MacOS"
mkdir -p "$STAGING/$APP_NAME Dev.app/Contents/Resources"

cp "$BIN" "$STAGING/$APP_NAME Dev.app/Contents/MacOS/$APP_NAME"

cat > "$STAGING/$APP_NAME Dev.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME Dev</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0-dev</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>TextFlash 需要辅助功能权限以监听键盘事件并展开文本。</string>
</dict>
</plist>
PLIST

# ── 3. 签名 ──
rm -rf "$STAGING/$APP_NAME Dev.app/Contents/_CodeSignature"
if security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$STAGING/$APP_NAME Dev.app" 2>&1
else
    codesign --force --deep --sign - "$STAGING/$APP_NAME Dev.app" 2>&1
fi

# ── 4. 部署 ──
DEST="$HOME/Applications/$APP_NAME Dev.app"
pkill -f "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$STAGING/$APP_NAME Dev.app" "$DEST"
rm -rf "$STAGING"

# ── 5. 启动 ──
echo "🚀 启动 $APP_NAME..."
open "$DEST"

# 等待启动后检查辅助功能权限
sleep 2
if ! osascript -e 'tell application "System Events" to UI elements enabled' 2>/dev/null; then
    echo ""
    echo "⚠️  辅助功能权限未授予"
    echo "   系统设置 → 隐私与安全性 → 辅助功能 → 添加 TextFlash Dev"
fi

echo "✅ Deploy 完成"
