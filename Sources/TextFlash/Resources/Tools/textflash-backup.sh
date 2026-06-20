#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  textflash-backup.sh [backup-root]

Creates a TextFlash backup directory containing:
  - textflash.db
  - preferences.plist
  - manifest.txt

If backup-root is omitted, the backup is written to:
  ~/Backups/TextFlash
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
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
INFO_PLIST="$CONTENTS_DIR/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || echo "com.nekutai.textflash")"

DATA_DIR="$HOME/Library/Application Support/TextFlash"
DB_PATH="$DATA_DIR/textflash.db"
PREFS_FALLBACK="$HOME/Library/Preferences/$BUNDLE_ID.plist"
BACKUP_ROOT="${1:-$HOME/Backups/TextFlash}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

if [ ! -f "$DB_PATH" ]; then
    echo "TextFlash database not found: $DB_PATH" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 is required to create a consistent database backup." >&2
    exit 1
fi

sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/textflash.db'"

if ! defaults export "$BUNDLE_ID" "$BACKUP_DIR/preferences.plist" >/dev/null 2>&1; then
    if [ -f "$PREFS_FALLBACK" ]; then
        cp "$PREFS_FALLBACK" "$BACKUP_DIR/preferences.plist"
    else
        : > "$BACKUP_DIR/preferences.plist"
    fi
fi

cat > "$BACKUP_DIR/manifest.txt" <<EOF
app=TextFlash
bundle_id=$BUNDLE_ID
created_at=$STAMP
database=textflash.db
preferences=preferences.plist
EOF

echo "$BACKUP_DIR"
