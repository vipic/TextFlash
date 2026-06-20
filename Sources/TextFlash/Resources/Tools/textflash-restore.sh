#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  textflash-restore.sh [--launch] backup-dir

Restores a TextFlash backup created by textflash-backup.sh.
Use --launch to reopen TextFlash after restoring.
USAGE
}

LAUNCH_AFTER_RESTORE=false
if [ "${1:-}" = "--launch" ]; then
    LAUNCH_AFTER_RESTORE=true
    shift
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -ne 1 ]; then
    usage
    exit 0
fi

BACKUP_DIR="$1"
DB_BACKUP="$BACKUP_DIR/textflash.db"
PREFS_BACKUP="$BACKUP_DIR/preferences.plist"

if [ ! -f "$DB_BACKUP" ]; then
    echo "Backup database not found: $DB_BACKUP" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
find_app_contents_dir() {
    local dir="$SCRIPT_DIR"
    while [ "$dir" != "/" ]; do
        if [ "$(basename "$dir")" = "Contents" ] && [ -f "$dir/Info.plist" ] && [[ "$(dirname "$dir")" == *.app ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    cd "$SCRIPT_DIR/../.." && pwd
}

CONTENTS_DIR="$(find_app_contents_dir)"
APP_DIR="$(cd "$CONTENTS_DIR/.." && pwd)"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || echo "com.nekutai.textflash")"

DATA_DIR="$HOME/Library/Application Support/TextFlash"
DB_PATH="$DATA_DIR/textflash.db"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1

mkdir -p "$DATA_DIR"
cp "$DB_BACKUP" "$DB_PATH"
rm -f "$DATA_DIR/textflash.db-wal" "$DATA_DIR/textflash.db-shm"

if [ -f "$PREFS_BACKUP" ] && [ -s "$PREFS_BACKUP" ]; then
    defaults import "$BUNDLE_ID" "$PREFS_BACKUP" >/dev/null 2>&1 || true
    killall cfprefsd >/dev/null 2>&1 || true
fi

if $LAUNCH_AFTER_RESTORE; then
    open "$APP_DIR"
fi

echo "Restored TextFlash backup: $BACKUP_DIR"
