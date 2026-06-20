import Foundation

enum UpdateInstallScriptBuilder {
    static func script() -> String {
        """
        #!/bin/bash
        set -e
        if [ "$#" -ne 4 ]; then
            echo "Usage: $0 dmg-path target-app expected-version current-pid" >&2
            exit 2
        fi

        DMG="$1"
        TARGET="$2"
        EXPECTED_VERSION="$3"
        CURRENT_PID="$4"
        LOG="/tmp/textflash_update.log"
        exec >> "$LOG" 2>&1
        echo "TextFlash update started at $(date)"
        echo "Target: $TARGET"
        echo "Expected version: $EXPECTED_VERSION"
        echo "Waiting for current process to exit: $CURRENT_PID"
        for _ in $(seq 1 100); do
            if ! kill -0 "$CURRENT_PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "$CURRENT_PID" 2>/dev/null; then
            echo "旧进程仍未退出，继续尝试安装"
        fi
        TARGET_PARENT=$(dirname "$TARGET")
        TARGET_NAME=$(basename "$TARGET")
        BACKUP="$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)"

        echo "Mounting DMG..."
        MOUNT_OUTPUT=$(hdiutil attach -noverify -noautoopen -nobrowse "$DMG" 2>&1)
        VOLUME=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | tail -1 | awk -F'\\t' '{print $NF}')

        if [ ! -d "$VOLUME/TextFlash.app" ]; then
            echo "更新包缺少 TextFlash.app" >&2
            open "$TARGET"
            exit 1
        fi

        CANDIDATE="$VOLUME/TextFlash.app"
        CANDIDATE_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        CANDIDATE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        if [ "$CANDIDATE_BUNDLE" != "com.nekutai.textflash" ]; then
            echo "更新包 Bundle ID 不匹配: $CANDIDATE_BUNDLE" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi
        if [ "$CANDIDATE_VERSION" != "$EXPECTED_VERSION" ]; then
            echo "更新包版本不匹配: $CANDIDATE_VERSION，期望 $EXPECTED_VERSION" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        if ! /usr/bin/codesign --verify --deep --strict "$CANDIDATE" 2>/dev/null; then
            echo "更新包签名校验失败" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi
        CANDIDATE_SIGNATURE=$(/usr/bin/codesign -dv "$CANDIDATE" 2>&1 || true)
        if echo "$CANDIDATE_SIGNATURE" | grep -q "Signature=adhoc"; then
            echo "更新包使用 ad-hoc 签名，拒绝自动更新" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        CURRENT_REQ=$(/usr/bin/codesign -dr - "$TARGET" 2>&1 | sed -n 's/^.*designated => //p')
        if [ -n "$CURRENT_REQ" ] && ! /usr/bin/codesign --verify --deep --strict -R="designated => $CURRENT_REQ" "$CANDIDATE" 2>/dev/null; then
            echo "更新包签名身份与当前 App 不匹配，拒绝自动更新" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        echo "Replacing app..."
        mv "$TARGET" "$BACKUP"
        if ! cp -R "$CANDIDATE" "$TARGET"; then
            echo "更新包复制失败，已恢复旧版本" >&2
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist" 2>/dev/null || true)
        if [ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]; then
            echo "安装后版本仍为 $INSTALLED_VERSION，期望 $EXPECTED_VERSION，已恢复旧版本" >&2
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi
        rm -rf "$BACKUP"

        echo "Detaching DMG..."
        hdiutil detach "$VOLUME" -quiet
        rm -f "$DMG" "$0"
        echo "Launching updated app..."
        open "$TARGET"
        echo "TextFlash update finished at $(date)"
        """
    }
}
