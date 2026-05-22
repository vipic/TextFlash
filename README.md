# TextFlash

TextFlash is a macOS menu bar text expansion app built with SwiftUI and SQLite.

## Development

Run tests:

```bash
swift test
```

Build locally:

```bash
swift build
```

Deploy a development app bundle to `~/Applications/TextFlash Dev.app`:

```bash
./deploy.sh
```

Text expansion requires macOS Accessibility permission. If the app cannot expand text, open the menu bar item and use the accessibility permission action.

CI runs shell script syntax checks, `swift test`, and `swift build -c release` on macOS. See `CHANGELOG.md` for notable changes.

## Snippets

Snippets are stored in SQLite under Application Support. The manager window supports JSON import and export. Import validates the backup before replacing existing data and writes an automatic backup first.

Automatic import backups are stored in:

```text
~/Library/Application Support/TextFlash/Backups
```

The app keeps the newest 20 automatic backups.

Use the folder button in the manager toolbar to open the backup directory.

## App Exclusions

Use the menu bar item to pause expansion, exclude the focused app, or manage the exclusion list. Exclusions are stored in `UserDefaults` by bundle identifier.

## Release

Build a DMG:

```bash
./release.sh 0.1.0
```

The release script runs tests by default. To skip tests for a local packaging check:

```bash
RUN_TESTS=false ./release.sh 0.1.0
```

Publishing requires a Developer ID signing identity and notarization:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example" \
NOTARIZE=true \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
./release.sh 0.1.0 --publish
```

`--publish` requires a clean Git working tree. The script pushes the current `HEAD` and the release tag.
