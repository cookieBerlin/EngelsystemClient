# 0011. Native tooling and Debug-only launch arguments for App Store screenshots

- **Status**: Accepted
- **Date**: 2026-10-12

## Context

The App Store needs screenshots for iPhone (6.9"), iPad (13") and — because the app contains a Watch app — Apple Watch.
They should be reproducible with one command from Demo Mode, in English, with a clean status bar. The usual tool is
fastlane `snapshot`; watchOS UI tests are slow and flaky on this machine (see `history.md`), and a fresh simulator's first
launches are slow (system widget renderer compiling shaders).

## Decision

- **No fastlane/Ruby dependency.** `Scripts/screenshots.sh` uses only `xcodebuild`, `simctl`, `xcresulttool` and `sips`.
- **iPhone and iPad** scenes are a UI test class (`ScreenshotTests`) that attaches full-screen captures; the script exports
  them from the `.xcresult`, bakes the EXIF orientation into the pixels (iPad landscape), checks the exact App Store pixel
  size and strips metadata.
- **Apple Watch** is captured with `simctl io screenshot` after launching the Debug build with launch arguments, not via a
  UI test.
- **Debug-only launch arguments**, no-ops in Release builds (so nothing shipped changes): `-seed-demo-instance`
  (`DemoSeeding`, inserts a Demo Mode instance when none exists) and `-skipNotificationPrompt YES`
  (`NotificationScheduler`, skips the permission prompt that would cover the Watch scene). Both decisions live in tested
  Kit code.
- The script uses its own simulators and a fresh app install per run; it must be built with normal simulator signing
  (`CODE_SIGNING_ALLOWED=NO` strips the iCloud entitlement and the app traps in `CKContainer`).

## Consequences

- One command, no extra tooling; the output folder `Screenshots/` is git-ignored.
- The iOS test has to nudge the notification prompt (it only appears after a real interaction, late on a new simulator),
  so a first run takes about 5 minutes per device.
- The Watch gets one scene (Next Shift); more would need UI-test automation or more launch arguments.
- The App Store pixel sizes live in the script and must be re-checked against App Store Connect's specification when a new
  device class appears.
