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

Baseline 2026-10-12 (`Scripts/check-coverage.sh`, Kit own code 76 %).
Take files in this order; remove an item once the file is at 100 %.

- [ ] **C-01** `Networking/APIClient.swift` (38 %): real-network path via a
      stubbed `URLProtocol`.
- [ ] **C-03** Remaining Kit files below 100 %: `NewsNotifier`,
      `KeychainSyncStore`, `PollingInterval`, `CloudSyncStatus`,
      `WatchConnectivityBridge`, `APIError`, `LocalKeychainStore`,
      `NotificationScheduler`, `AppSyncCoordinator`, the `Cached*` models,
      `ModelContainerFactory`, `NotificationLeadTimeSettings`,
      `InstanceCredentialResolver`, `LocationSyncService`, `DebugLog`,
      `DemoData`.
- [ ] **C-04** Owner approval needed for exclusions of code tests cannot
      drive. Pending proposal: `Services/SystemCloudKitAccount.swift`
      (3-line `CKContainer` adapter; test processes lack CloudKit
      entitlements, logic is tested through an injected closure). Further
      candidates
      (e.g. the MetricKit delivery callbacks, Keychain access-group
      behavior); add them to `Scripts/coverage-exclusions.txt` only after
      approval.
- [ ] **C-05** Bring the iOS app target under the gate (Xcode coverage run,
      unit + UI tests), then the Watch app and the complication.
- [ ] **C-06** Make the gate blocking (all Kit files at 100 % or excluded).
