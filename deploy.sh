#!/bin/bash
# TextFlash Deploy — 快速开发部署
# 每次修改代码后执行：编译 → 打包 → 重启应用
# 用法: ./deploy.sh
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
    echo "❌ TextFlash 需要稳定代码签名以保留辅助功能授权，不能使用 ad-hoc 签名。"
    echo "   请创建自签名代码签名证书，或设置 CODESIGN_IDENTITY 为开发者账号证书。"
    exit 1
fi
echo "🔐 签名身份: $IDENTITY"

cd "$PROJECT_DIR"

# 1. 编译
rm -rf "$RESOURCE_BUNDLE"
swift build -Xswiftc -DDISABLE_PREVIEWS 2>&1 | tail -3

test -f "$BUILD_DIR/$APP_NAME" || { echo "❌ 构建失败"; exit 1; }
echo "✅ Debug 编译完成"

# 2. 杀 dev 进程 + 等待退出（只杀 dev，不影响正式版）
pkill -f "TextFlash Dev.app" 2>/dev/null || true
for i in $(seq 1 10); do
    if ! pgrep -f "TextFlash Dev.app" > /dev/null 2>&1; then break; fi
    sleep 0.2
done
echo "✅ 旧开发版进程已停止"

# 3. 确保 bundle 结构存在（保留 inode → TCC 权限不丢）
if [ ! -d "$MACOS_DIR" ]; then
    echo "📦 首次创建 .app bundle..."
    mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
fi

# 4. 替换二进制（原地覆盖，不删 bundle）
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# 5. 复制资源
if [ -f "$RESOURCE_DIR/Assets/AppIcon.icns" ]; then
    cp "$RESOURCE_DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -d "$RESOURCE_BUNDLE" ]; then
    rm -rf "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi
if [ -d "$RESOURCE_DIR/Tools" ]; then
    rm -rf "$RESOURCES_DIR/Tools"
    cp -R "$RESOURCE_DIR/Tools" "$RESOURCES_DIR/Tools"
    chmod +x "$RESOURCES_DIR/Tools/"*.sh
fi
echo "✅ .app bundle 已更新: $APP_DIR"

# 6. 版本号（semver: tag-dev+hash）和 git hash
DEPLOY_HASH=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD)
LATEST_TAG=$(cd "$PROJECT_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0")
LATEST_TAG="${LATEST_TAG#v}"
DEV_VERSION="${LATEST_TAG}-dev+${DEPLOY_HASH}"

# Info.plist — 首次创建模板，之后每次用 PlistBuddy 更新版本字段（不改变 inode → TCC 不丢）
if [ ! -f "$CONTENTS/Info.plist" ]; then
    cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nekutai.textflash.dev" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleName '$APP_NAME Dev'" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$APP_NAME Dev'" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${DEPLOY_HASH}" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${DEV_VERSION}" "$CONTENTS/Info.plist" 2>/dev/null
fi
echo "✅ 版本号已注入: $DEV_VERSION"

# 7. 清除残留签名（二进制替换后签名失效）并深签整个 bundle
rm -rf "$APP_DIR/_CodeSignature" 2>/dev/null || true
if ! codesign --force --deep --sign "$IDENTITY" "$APP_DIR"; then
    echo "❌ \"$IDENTITY\" 签名失败。TextFlash 不会改用 ad-hoc，因为这会破坏辅助功能授权体验。"
    echo "   请检查钥匙串中是否存在该代码签名证书，或通过 CODESIGN_IDENTITY 指定稳定证书。"
    exit 1
fi
echo "✅ 代码签名完成"

# 8. 启动
echo "🚀 启动 $APP_NAME..."
open "$APP_DIR"

echo "✅ Deploy 完成"
