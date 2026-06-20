#!/bin/bash
# TextFlash Release — 生产发布
# 流程：测试 → release 编译 → 组装 .app → 去除符号 → 签名 → DMG 打包
# 用法: ./release.sh [version] [--publish]
#   ./release.sh 0.1.0              # 仅构建 DMG
#   ./release.sh 0.1.0 --publish    # 构建 + 推 tag + 创建 GitHub Release
#   ./release.sh                    # 自动取 git tag，没有则用 0.1.0
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TextFlash"
BUILD_DIR="$PROJECT_DIR/.build/release"
STAGING="$PROJECT_DIR/.release_staging"
RESOURCE_DIR="$PROJECT_DIR/Sources/TextFlash/Resources"
DIST_DIR="$PROJECT_DIR/dist"
BUNDLE_ID="com.nekutai.textflash"
IDENTITY="${CODESIGN_IDENTITY:-Nekutai}"
NOTARIZE="${NOTARIZE:-false}"

PUBLISH=false
FORCE=false
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=true ;;
        --force) FORCE=true ;;
        --*) ;;
        *) VERSION="$arg" ;;
    esac
done
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo '0.1.0')}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
# 自动检测：无 Xcode 则跳过测试（XCTest/Testing 框架需要完整 Xcode）
if [ "${RUN_TESTS:-}" = "" ]; then
    if xcode-select -p 2>/dev/null | grep -q "/Xcode.app/"; then
        RUN_TESTS=true
    else
        RUN_TESTS=false
        echo "⚠️  未检测到 Xcode，自动跳过测试（XCTest/Testing 框架需要完整 Xcode）"
    fi
fi

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

echo "🏭 Building $APP_NAME $VERSION (release)..."
echo ""

cd "$PROJECT_DIR"

if [ -n "$(git status --porcelain)" ] && ! $FORCE; then
    echo "❌ 工作区有未提交改动。请先提交，或使用 --force 明确跳过。"
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)
if $PUBLISH && [ "$CURRENT_BRANCH" != "main" ] && ! $FORCE; then
    echo "❌ 当前分支是 \"$CURRENT_BRANCH\"，发布必须在 main 分支执行。"
    exit 1
fi

# ── 1. 测试 ──
echo "━━━ 1/6 测试 ━━━"
if [ "$RUN_TESTS" = "true" ]; then
    swift test -Xswiftc -DDISABLE_PREVIEWS
else
    echo "   跳过测试（RUN_TESTS=${RUN_TESTS}）"
fi

# ── 2. Release 编译 ──
echo ""
echo "━━━ 2/6 Release 编译 ━━━"
rm -rf "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
swift build -c release -Xswiftc -DDISABLE_PREVIEWS

BIN="$BUILD_DIR/$APP_NAME"
test -f "$BIN" || { echo "❌ 构建失败"; exit 1; }
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

# ── 3. 组装 .app ──
echo ""
echo "━━━ 3/6 组装 .app bundle ━━━"
rm -rf "$STAGING"
mkdir -p "$STAGING/$APP_NAME.app/Contents/MacOS"
mkdir -p "$STAGING/$APP_NAME.app/Contents/Resources"
mkdir -p "$DIST_DIR"

STAGED_BIN="$STAGING/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "$BIN" "$STAGED_BIN"

# 拷贝应用图标
if [ -f "$RESOURCE_DIR/Assets/AppIcon.icns" ]; then
    cp "$RESOURCE_DIR/Assets/AppIcon.icns" "$STAGING/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    echo "   📱 AppIcon.icns → .app bundle"
fi
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$STAGING/$APP_NAME.app/Contents/Resources/"
    echo "   🌐 $(basename "$RESOURCE_BUNDLE") → .app bundle"
fi
if [ -d "$RESOURCE_DIR/Tools" ]; then
    cp -R "$RESOURCE_DIR/Tools" "$STAGING/$APP_NAME.app/Contents/Resources/Tools"
    chmod +x "$STAGING/$APP_NAME.app/Contents/Resources/Tools/"*.sh
    echo "   🧰 Tools → .app bundle"
fi

# ── 4. 去除符号 ──
echo ""
echo "━━━ 4/6 去除调试符号 ━━━"
BIN_SIZE_BEFORE=$(stat -f%z "$STAGED_BIN")
strip -S "$STAGED_BIN" 2>/dev/null || true
BIN_SIZE_AFTER=$(stat -f%z "$STAGED_BIN")
echo "   二进制: $(numfmt --to=iec $BIN_SIZE_BEFORE 2>/dev/null || echo "${BIN_SIZE_BEFORE}") → $(numfmt --to=iec $BIN_SIZE_AFTER 2>/dev/null || echo "${BIN_SIZE_AFTER}")"

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
    <key>NSAccessibilityUsageDescription</key>
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
    codesign --force --deep --sign "$IDENTITY" "$STAGING/$APP_NAME.app" 2>&1
else
    codesign --force --deep --sign - "$STAGING/$APP_NAME.app" 2>&1
fi

if $PUBLISH && ! $CERT_OK; then
    echo "❌ --publish 需要有效的 Developer ID 签名证书，不能发布 ad-hoc 签名产物"
    exit 1
fi

# ── 6. DMG 打包 ──
echo ""
echo "━━━ 6/6 DMG 打包 ━━━"
DMG_PATH="$DIST_DIR/$DMG_NAME"
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
    codesign --force --sign "$IDENTITY" "$DMG_PATH" 2>&1
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

    if git rev-parse "$TAG" &>/dev/null 2>&1; then
        echo "   ⚠️  tag $TAG 已存在"
    else
        echo "   🏷  创建 tag $TAG..."
        git tag "$TAG"
    fi

    git push origin HEAD "$TAG"

    if gh release view "$TAG" &>/dev/null 2>&1; then
        echo "   ⚠️  Release $TAG 已存在，仅上传资产..."
        gh release upload "$TAG" "$DMG_PATH" --clobber
    else
        echo "   📦 创建 Release $TAG..."
        last_tag=$(git describe --tags --abbrev=0 HEAD~ 2>/dev/null || echo "")
        if [[ -n "$last_tag" ]]; then
            changelog=$(git log "${last_tag}..HEAD" --pretty=format:"- %s" --no-merges 2>/dev/null)
            if [[ -z "$changelog" ]]; then
                changelog="- $APP_NAME $VERSION 发布"
            fi
        else
            changelog="- $APP_NAME $VERSION 发布"
        fi

        gh release create "$TAG" \
            --title "$APP_NAME $VERSION" \
            --notes "$changelog" \
            "$DMG_PATH"
    fi

    echo "   ✅ 发布完成"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ Release $VERSION 完成              ║"
echo "╠══════════════════════════════════════╣"
printf "║  📦 %-32s ║\n" "$DMG_NAME"
printf "║  📁 %-32s ║\n" "dist/"
DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || echo 0)
DMG_MB=$((DMG_SIZE / 1048576))
printf "║  📏 DMG: %d MB                        ║\n" $DMG_MB
echo "╚══════════════════════════════════════╝"
