#!/bin/bash
# TextFlash Release — 生产发布
# 流程：测试 → release 编译 → 去除符号 → DMG 打包 → 签名
# 用法: ./release.sh [version] [--publish]
#   ./release.sh 0.1.0              # 仅构建 DMG
#   ./release.sh 0.1.0 --publish    # 构建 + 推 tag + 创建 GitHub Release
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TextFlash"
BUILD_DIR="$PROJECT_DIR/.build/release"
STAGING="$PROJECT_DIR/.release_staging"
BUNDLE_ID="com.nekutai.textflash"
VERSION="${1:-0.1.0}"
VERSION="${VERSION#v}"
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-false}"
RUN_TESTS="${RUN_TESTS:-true}"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

# 解析 --publish 标志
PUBLISH=false
for arg in "$@"; do
    [[ "$arg" == "--publish" ]] && PUBLISH=true
done

echo "🏭 Building $APP_NAME $VERSION (release)..."
echo ""

cd "$PROJECT_DIR"

# ── 1. 测试 ──
echo "━━━ 1/6 测试 ━━━"
if [ "$RUN_TESTS" = "true" ]; then
    swift test
else
    echo "   跳过测试（RUN_TESTS=${RUN_TESTS}）"
fi

# ── 2. Release 编译 ──
echo ""
echo "━━━ 2/6 Release 编译 ━━━"
swift build -c release

BIN="$BUILD_DIR/$APP_NAME"
test -f "$BIN" || { echo "❌ 构建失败"; exit 1; }

# ── 3. 去除符号 ──
echo ""
echo "━━━ 3/6 去除调试符号 ━━━"
BIN_SIZE_BEFORE=$(stat -f%z "$BIN")
strip -S "$BIN" 2>/dev/null || true
BIN_SIZE_AFTER=$(stat -f%z "$BIN")
echo "   二进制: $(numfmt --to=iec $BIN_SIZE_BEFORE 2>/dev/null || echo "${BIN_SIZE_BEFORE}") → $(numfmt --to=iec $BIN_SIZE_AFTER 2>/dev/null || echo "${BIN_SIZE_AFTER}")"

# ── 4. 组装 .app ──
echo ""
echo "━━━ 4/6 组装 .app bundle ━━━"
rm -rf "$STAGING"
mkdir -p "$STAGING/$APP_NAME.app/Contents/MacOS"
mkdir -p "$STAGING/$APP_NAME.app/Contents/Resources"

cp "$BIN" "$STAGING/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# 拷贝应用图标
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$STAGING/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    echo "   📱 AppIcon.icns → .app bundle"
fi

cat > "$STAGING/$APP_NAME.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
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
</dict>
</plist>
PLIST

# ── 5. 代码签名 ──
echo ""
echo "━━━ 5/6 代码签名 ━━━"

CERT_OK=true
if [ -n "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "   签名身份: $IDENTITY"
elif [ -n "$IDENTITY" ]; then
    echo "⚠️  未找到 \"$IDENTITY\" 代码签名证书，回退 ad-hoc"
    CERT_OK=false
else
    echo "   未配置签名证书，使用 ad-hoc"
    CERT_OK=false
fi

if $CERT_OK; then
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$STAGING/$APP_NAME.app" 2>&1
else
    codesign --force --deep --sign - "$STAGING/$APP_NAME.app" 2>&1
fi

if $PUBLISH && ! $CERT_OK; then
    echo "❌ --publish 需要有效的 Developer ID 签名证书，不能发布 ad-hoc 签名产物"
    exit 1
fi

if $PUBLISH && [ "$NOTARIZE" != "true" ]; then
    echo "❌ --publish 需要完成 notarization；请设置 NOTARIZE=true 并配置 APPLE_ID、APPLE_TEAM_ID、APP_SPECIFIC_PASSWORD"
    exit 1
fi

# ── 6. DMG 打包 ──
echo ""
echo "━━━ 6/6 DMG 打包 ━━━"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

DMG_SRC="$STAGING/dmg_root"
mkdir -p "$DMG_SRC"
cp -R "$STAGING/$APP_NAME.app" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications" 2>/dev/null || true

APP_SIZE_KB=$(du -sk "$DMG_SRC/$APP_NAME.app" | cut -f1)
DMG_SIZE_MB=$(( (APP_SIZE_KB / 1024) + 2 ))

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_SRC" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1 | tail -1

if $CERT_OK; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH" 2>&1
fi

if [ "$NOTARIZE" = "true" ]; then
    if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${APP_SPECIFIC_PASSWORD:-}" ]; then
        echo "❌ notarization 需要 APPLE_ID、APPLE_TEAM_ID、APP_SPECIFIC_PASSWORD"
        exit 1
    fi

    echo ""
    echo "━━━ Notarization ━━━"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --wait
    xcrun stapler staple "$DMG_PATH"
fi

# ── 发布到 GitHub Releases ──
if $PUBLISH; then
    echo ""
    echo "━━━ 发布到 GitHub Releases ━━━"

    if ! command -v gh &>/dev/null; then
        echo "❌ 未安装 gh CLI"
        exit 1
    fi

    TAG="$VERSION"

    if git rev-parse "$TAG" &>/dev/null 2>&1; then
        echo "   ⚠️  tag $TAG 已存在"
    else
        echo "   🏷  创建 tag $TAG..."
        git tag "$TAG"
    fi

    git push origin main "$TAG" 2>&1 | tail -2

    if gh release view "$TAG" &>/dev/null 2>&1; then
        echo "   ⚠️  Release $TAG 已存在，仅上传资产..."
        gh release upload "$TAG" "$DMG_PATH" --clobber
    else
        echo "   📦 创建 Release $TAG..."
        gh release create "$TAG" \
            --title "$APP_NAME $VERSION" \
            --notes "- $APP_NAME $VERSION 发布" \
            "$DMG_PATH"
    fi

    echo "   ✅ 发布完成"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ Release $VERSION 完成              ║"
echo "╠══════════════════════════════════════╣"
printf "║  📦 %-32s ║\n" "$DMG_NAME"
DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || echo 0)
DMG_MB=$((DMG_SIZE / 1048576))
printf "║  📏 DMG: %d MB                        ║\n" $DMG_MB
echo "╚══════════════════════════════════════╝"
