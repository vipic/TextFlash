#!/bin/bash
# TextFlash Deploy — 开发快速部署
# 流程：debug 编译 → 签名 → 部署到 ~/Applications/TextFlash Dev.app → 启动
# TCC 保留：只替换二进制，不变更 bundle 结构/签名，避免辅助功能权限失效
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TextFlash"
BUILD_DIR="$PROJECT_DIR/.build/debug"
BUNDLE_ID="com.nekutai.textflash.dev"
# 签名身份从环境变量 CODESIGN_IDENTITY 读取，未配置则 ad-hoc
IDENTITY="${CODESIGN_IDENTITY:-}"

cd "$PROJECT_DIR"

# ── 1. Debug 编译 ──
echo "⚡ Deploying $APP_NAME (debug)..."
echo "Building for debugging..."
swift build 2>&1 | tail -1

BIN="$BUILD_DIR/$APP_NAME"
test -f "$BIN" || { echo "❌ 构建失败"; exit 1; }

DEST="$HOME/Applications/$APP_NAME Dev.app"
DEST_BIN="$DEST/Contents/MacOS/$APP_NAME"

# ── 2. 判断是否需要组装新 bundle ──
NEED_BUNDLE=false
if [ ! -d "$DEST" ]; then
    NEED_BUNDLE=true
elif [ ! -f "$DEST/Contents/Info.plist" ]; then
    NEED_BUNDLE=true
fi

STAGING="$PROJECT_DIR/.deploy_staging"

if $NEED_BUNDLE; then
    echo "📦 创建新 bundle..."
    rm -rf "$STAGING"
    mkdir -p "$STAGING/$APP_NAME Dev.app/Contents/MacOS"
    mkdir -p "$STAGING/$APP_NAME Dev.app/Contents/Resources"

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
fi

# ── 3. 检查二进制是否变化（避免无谓重签导致 TCC 失效）──
BIN_CHANGED=true
if [ -f "$DEST_BIN" ]; then
    if cmp -s "$BIN" "$DEST_BIN"; then
        BIN_CHANGED=false
        echo "📎 二进制未变化，跳过部署"
    fi
fi

if $BIN_CHANGED || $NEED_BUNDLE; then
    # ── 4. 签名（仅在二进制变化时，保留 TCC）──
    if $NEED_BUNDLE; then
        cp "$BIN" "$STAGING/$APP_NAME Dev.app/Contents/MacOS/$APP_NAME"
        TARGET_TO_SIGN="$STAGING/$APP_NAME Dev.app"
    else
        # 直接替换目标 app 内二进制
        pkill -f "$DEST_BIN" 2>/dev/null || true
        sleep 0.3
        TARGET_TO_SIGN="$DEST"
    fi

    # 选签名身份：配置了且在钥匙串中存在则用，否则 ad-hoc
    if [ -n "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
        echo "🔐 签名: $IDENTITY"
        codesign --force --deep --sign "$IDENTITY" "$TARGET_TO_SIGN" 2>&1
        SIGNED_WITH="$IDENTITY"
    else
        [ -n "$IDENTITY" ] && echo "⚠️  未找到 '$IDENTITY' 证书，使用 ad-hoc 签名（TCC 权限不会保留）"
        codesign --force --deep --sign - "$TARGET_TO_SIGN" 2>&1
        SIGNED_WITH="ad-hoc"
    fi

    # ── 5. 部署 ──
    if $NEED_BUNDLE; then
        pkill -f "$DEST_BIN" 2>/dev/null || true
        rm -rf "$DEST"
        cp -R "$STAGING/$APP_NAME Dev.app" "$DEST"
        rm -rf "$STAGING"
    else
        # 已有 bundle，只替换二进制
        cp "$BIN" "$DEST_BIN"
        # 强制更新签名（二进制变了所以必须重签）
        if [ "$SIGNED_WITH" != "ad-hoc" ]; then
            codesign --force --deep --sign "$IDENTITY" "$DEST" 2>&1
        else
            codesign --force --deep --sign - "$DEST" 2>&1
        fi
    fi

    echo "✅ 部署完成"

    # 检查 TCC：如果是 ad-hoc 签名，提示用户
    if [ "$SIGNED_WITH" = "ad-hoc" ]; then
        echo ""
        echo "⚠️  ad-hoc 签名：每次部署后需重新授权辅助功能"
        echo "   系统设置 → 隐私与安全性 → 辅助功能 → 先移除旧条目再添加 TextFlash Dev"
    fi
else
    echo "✅ 无需部署（二进制与当前版本相同）"
fi

# ── 6. 启动（如果未运行）──
if ! pgrep -f "$DEST_BIN" > /dev/null 2>&1; then
    echo "🚀 启动 $APP_NAME..."
    open "$DEST"
else
    echo "🔄 $APP_NAME 已在运行中"
fi
