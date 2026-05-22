# Changelog

## Unreleased

- Fixed trigger-character expansion so TextFlash no longer leaves partial abbreviations or duplicates trigger characters.
- Added conservative secure-field handling and application exclusion controls.
- Show accessibility permission status in the manager and debug windows.
- Added pause/resume controls with menu bar status feedback.
- Re-enable the keyboard event tap automatically when macOS disables it.
- Added JSON import/export, import validation, overwrite confirmation, and automatic pre-import backups.
- Added transaction-backed database updates and surfaced write failures in the manager UI.
- Added exclusion-list management, including add current app, remove, and clear actions.
- Use the last non-TextFlash foreground app as the exclusion target so TextFlash windows do not exclude themselves.
- Extracted snippet matching into a testable matcher with unit coverage.
- Hardened release packaging with tests, signing/notarization checks, cleanup, and DMG signing.
- Prevented release packaging from stripping SwiftPM build artifacts and added clean-tree checks for publishing.
- Added CI for shell syntax checks, Swift tests, and release builds.
- Added project README with development, backup, exclusion, and release workflows.
