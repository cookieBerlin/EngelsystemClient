# Backlog

Concrete, ready-to-pick-up development tasks (IDs like `T-01`; reference them as
`Backlog: T-01` in commit bodies) — the tactical counterpart
to [`roadmap.md`](roadmap.md)'s strategic/feature-level planning. An
item moves here once it's broken down enough that someone could
actually start on it; it's removed (not just checked off) once it's
done and reflected in [`features.md`](features.md).

## TestFlight release

- [ ] **T-01** Upload a first build (Xcode Archive → App Store Connect); see
      `release.md`. Export compliance is pre-answered in the Info.plist.
- [ ] **T-02** Set up Internal Testing group and upload a build.
- [ ] **T-03** Prepare for External Testing / Beta App Review (Beta App
      Description, Feedback Email, demo-mode hint for reviewers) once
      Internal Testing is confirmed working.

## Coverage ramp-up (ADR 0009)

Baseline 2026-10-12 (`Scripts/check-coverage.sh`): Kit own code 76 %; **Kit now
at 100 %, gate green** (C-01 to C-03 done).
Take files in this order; remove an item once the file is at 100 %.

- [ ] **C-04** Exclusions so far (all owner-approved): `SystemCloudKitAccount`,
      `ModelContainerFactory`, `SystemKeychainClient`,
      `SystemNotificationCenter`. Standing approval covers further thin
      adapters; the MetricKit delivery callbacks and `WatchConnectivityBridge`'s
      iOS branches are not compiled by `swift test` on macOS and need the
      Xcode coverage run (C-05) or an exclusion.
- [ ] **C-05** iOS app target is at 100 % (gate green, 2026-10-12). Still to do:
      the Watch app and the complication, then an audit of the 21 excluded
      SwiftUI files for logic that should be extracted and tested
      (notably `SettingsView`, `MainView`, `InstanceSetupView`), and XCUITest
      smoke tests for screens that have none yet.
- [ ] **C-06** Make the gate blocking (all Kit files at 100 % or excluded).
