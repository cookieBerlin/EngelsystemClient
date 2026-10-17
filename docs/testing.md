# Testing

How this project is tested and the practical gotchas of running tests on
this machine. The rule "always add tests for new features" is binding and
also stated in [`CLAUDE.md`](../CLAUDE.md).

- **100 % line coverage gate** ([ADR 0009](adr/0009-full-line-coverage-gate.md)):
  every source file not listed in `Scripts/coverage-exclusions.txt` must
  have 100 % line coverage. Check with `Scripts/check-all-coverage.sh` (all
  three targets; `Scripts/check-coverage.sh` is the fast Kit-only check and
  lists every file below the threshold; `COVERAGE_THRESHOLD` overrides it). Exclusions need a
  justification comment **and owner approval** — never add one on your own.
  Standing exception: thin adapter layers over system APIs (SecItem,
  CKContainer, …) may always be excluded, as long as the logic is tested
  through a seam (ADR 0009).
  Generated code is excluded by construction. The ramp-up is finished (2026-10-12): the gate is blocking, no commit
  may leave a target below 100 %.
  Platform-guarded code (`#if os(iOS)`) is not compiled by `swift test` on
  macOS — it needs an Xcode-based coverage run
  (`xcodebuild test -enableCodeCoverage YES`, then `xcrun xccov view
  --report`) or a justified exclusion. Baseline 2026-10-12: Kit own code
  76 %, iOS app unit tests 15.5 %, Watch app 0 %. **All three targets
  reached 100 % (gates pass) the same day.**
  Seams used to get there: injectable closures/protocols for CloudKit
  (`SystemCloudKitAccount`), the Keychain (`KeychainClient`) and the
  notification center (`NotificationCenterScheduling`), each with a thin,
  excluded `System…` adapter.
  **App targets** (ADR 0010): non-view files (view models, services,
  helpers) must reach 100 % too (`Scripts/check-app-coverage.sh`); pure SwiftUI
  layout files are excluded with a justification, their logic extracted into
  tested view models/helpers, and XCUITest smoke tests cover that they render.
  **iOS app target reached 100 % (gate passes) on 2026-10-12** with 21 measured
  non-view files; the 21 layout files are listed in `Scripts/coverage-exclusions.txt`.
  The stubbed network is shared: it lives in the Kit as `#if DEBUG`-only test
  support (`TestSupport/StubbedNetwork.swift`, public, excluded from the gate, absent
  from Release builds), and each test target has a tiny `StubbedNetworkTests` parent suite. Thin
  adapters here: `BackgroundTaskRegistration.swift` (BGTaskScheduler).
  **Audit of the excluded views (C-07, 2026-10-12)**: the logic they carried was
  extracted — instance scoping/switcher/day headers/conversation sorting into
  `InstanceScope`, lead times, activation and cascade delete into the Kit
  (`InstanceMaintenance.swift`, shared with the Watch), the composer rules into
  `ConversationDetailViewModel`, the start-sync policy into `MainSyncStatus`. What
  remains in the view files is layout, bindings and one-line forwarding.
- **Testing `APIClient`'s real network path** (2026-10-12): the generated
  client is redirected to canned responses via
  `EngelsystemAPIAPI.requestBuilderFactory` — see
  `Sources/.../TestSupport/StubbedNetwork.swift` (a `URLProtocol` stub plus builder
  subclasses overriding `createURLSession()`). Register routes as
  `StubURLProtocol.route("GET /news", data: …)` (bodies are demo data
  encoded with the generator's own encoder). Suites using it must be
  nested in `StubbedNetworkTests` (the serialized parent — the stub state is
  process-wide, so they must never run in parallel with each other), call
  `StubbedNetwork.install()` in `init`, and must not
  mutate the shared `DemoMessageStore` (other tests expect it untouched).
  The test target builds in Swift 5 language mode for this reason (the
  generator's globals are not Swift 6 concurrency-safe).
- **Always add tests for new features** — logic in `EngelsystemClientKit`
  gets unit tests, non-trivial UI flows in the app targets get an XCUITest.
  Don't rely on manual simulator checks alone.
- Unit tests use the **Swift Testing** framework (`import Testing`,
  `@Test`, `#expect`), matching `EngelsystemClientKitTests` — not XCTest.
- Run them with `swift test` from the `EngelsystemClientKit` directory.
  This works directly on the host Mac, no simulator needed, because
  `Package.swift` declares `.macOS(.v14)` alongside `.iOS(.v26)`/
  `.watchOS(.v26)` — **test-tooling only, not a shipping target**.
  SwiftData's `@Model` requires macOS 14; everything else in the package
  (Foundation/Security/URLSession-based) already ran fine on macOS, so
  this platform entry unblocks fast local test runs without touching what
  the app actually ships on.
- UI tests (`EngelsystemClientUITests`) drive the simulator via XCUITest,
  not AppleScript/System Events (no Accessibility permission is granted
  in the dev environment) or `simctl` (no tap/touch support). Run with
  `xcodebuild test -scheme EngelsystemClient -destination 'platform=iOS
  Simulator,name=<device>' -only-testing:EngelsystemClientUITests/<Class>/<method>`.
- **Fresh start is automatic since 2026-10-12:** every UI test that expects the "no instance configured yet" first
  launch passes the Debug-only launch argument `-reset-instances` (`DemoSeeding.resetIfRequested`, a no-op in Release),
  which deletes all saved instances on launch (plus `-mainViewLastSelectedSection none` to forget the last-opened section) — so the whole `EngelsystemClientUITests` class can run in one
  `xcodebuild test` invocation without erasing the simulator in between. The paragraph below describes the old failure
  mode; new UI tests that need a fresh start must pass the argument too.
- **`testDemoModeNavigationFlow` (and any test that assumes a fresh
  "no instance configured yet" first launch) fails at its very first
  assertion — `"Try Demo Mode"` button not found — if the target
  simulator already has `Instance` records from an earlier test run or
  manual `xcrun simctl launch`/install.** `ContentView` shows `MainView`
  directly instead of `InstanceSetupView` once any instance exists
  (demo or real), and this local SwiftData store persists across
  separate `xcodebuild test` invocations on the same simulator — it is
  **not** reset between runs, and `xcrun simctl uninstall` silently does
  nothing if the simulator happens to be shut down at that moment
  (`"Unable to lookup in current state: Shutdown"`, no error surfaced
  otherwise). Root-caused 2026-09-17 after this exact test started
  failing (and, confusingly, also hanging for ~10 minutes on
  `xcodebuild`'s own "collecting diagnostics from simulator" step
  afterward — the same red herring shape as the watchOS Simulator
  ceiling documented in [`docs/history.md`](history.md), but a
  completely different, mundane cause here). Fix:
  `xcrun simctl shutdown <udid> && xcrun simctl erase <udid>` before
  re-running — a full erase, not just an uninstall, and don't trust a
  bare `uninstall` to have actually done anything without checking its
  output.
- **`xcodebuild test` (iOS, this machine) can fail every single attempt
  with `"Simulator device failed to launch ...xctrunner"` /
  `"The request was denied by service delegate (SBMainWorkspace)"`,
  even against a simulator already confirmed booted to its home screen
  (verified via `xcrun simctl io <udid> screenshot`).** Root-caused
  2026-09-17: `xcodebuild test` runs against a throwaway **clone** of
  the target simulator by default (visible in the test log as `Clone 1
  of <device> - <Target>Runner`), not the literal device you booted and
  screenshotted — that clone gets its own independent boot, and can
  still be mid-boot (denying all app-launch requests) even when the
  original device is long since idle at its home screen. Confirmed by
  eliminating it: adding **`-parallel-testing-enabled NO`** to the
  `xcodebuild test` invocation makes it run against the actual target
  simulator directly, and the launch failures stopped immediately across
  every subsequent run. Add this flag by default for this project on
  this machine — don't spend time re-diagnosing `RequestDenied` as an
  app/entitlements/code problem first.
- **A UI-test assertion that a short-lived transient element (e.g. a
  1–2 second splash/toast) appeared is inherently racy against cold
  app-launch time on a slow or loaded machine — don't add one.** Hit
  this validating the launch screen (see
  [`docs/features.md`](features.md)): a `waitForExistence(timeout:
  5)` for its text failed outright because cold launch alone had
  already taken 11+ seconds before XCUITest could even query the
  accessibility hierarchy, by which point a 1.2-second on-screen window
  (timed from first render, not from process launch) had long since
  closed. Prefer a structural check (does the rest of the flow still
  work, proving the transient view didn't crash) over trying to catch
  it existing on screen.
- **If a test result ever looks inexplicable given the actual code**
  (especially "a test I just added doesn't appear to have run" or "this
  passes in isolation but fails in the full suite" with no sensible
  cause), suspect Xcode/Simulator DerivedData corruption before spending
  time debugging the app code — see
  [`docs/history.md`](history.md) for a confirmed incident and how
  it was diagnosed (a quick standalone `swift <file>.swift` reproduction
  of just the suspect logic bypasses the simulator entirely and is the
  fastest way to rule the app code in or out).
- **`#if os(iOS)` code in the Kit** (2026-10-12): `swift test` on macOS doesn't compile it, so
  the decisions were moved to platform-independent types tested there
  (`WatchConnectivityBridge` over `WatchSessionControlling`, `MetricKitReporter` for summaries,
  persistence and retention); what's left is the thin adapters `SystemWatchSession.swift` and
  `MetricKitSubscriber.swift`, which are excluded from the gate.
- **UI smoke tests for excluded views** (`EngelsystemClientUITests`): the demo-mode flow covers
  Shifts, News, Profile, Locations, Messages and Settings; `testNewMessagePickerExportDiagnosticsAndDebugLogOpen`
  covers the new-message picker, the Export Diagnostics sheet and the debug log. Run them on an
  erased simulator (see above); demo mode now lands on the main page, so tests open Shifts from the sidebar.
- **Launch argument `-seed-demo-instance`** (Debug builds only; `DemoSeeding` in the Kit, wired in both
  apps' `WindowGroup`): inserts a Demo Mode instance when none exists. Used by the screenshot script. **Do
  not build the app with `CODE_SIGNING_ALLOWED=NO` to run it** — that strips the iCloud entitlement and the
  app traps in `CKContainer(identifier:)` at launch (seen 2026-10-12); build with the simulator's normal signing.
- **`-skipNotificationPrompt YES`** (Debug builds only, honoured by `NotificationScheduler`): skips the notification permission
  prompt; used for the Watch screenshot. **`ScreenshotTests`** is not a regression test — run it through
  `Scripts/screenshots.sh` (see `app-store.md`).
- **`ManualScreenshotTests`** (2026-10-16) is the second screenshot class: every iPhone screen once for the guide
  (`Scripts/screenshots.sh manual` → `Screenshots/manual/iphone/en/NN-<name>.png`, plus the Watch's Settings pages via the
  Debug-only `-open-settings -open-settings-page <Instances|Notifications|Sync|Diagnostics|About>` arguments into
  `Screenshots/manual/watch/en/`; `Scripts/publish-guide-images.sh` turns them into `docs/assets/guide/screens/`). The iPhone set is run twice, in light
  (`Screenshots/manual/`) and in dark appearance (`Screenshots/manual-dark/`); the dark images are published as `<name>-dark.png`
  and `docs/assets/site.js` swaps them in when the website is switched to dark (a missing dark image falls back to the light one). **A new
  screen needs a new scene in `ManualScreenshotTests` and its image in `guide.md`.** A scene whose screen cannot be reached is
  skipped, so after a run check the count and look at the images. The test passes `-reset-instances` (earlier runs leave a
  second instance behind) and waits for the first sync. The open color menu is shot without waiting for an element (system menus
  may not be in the accessibility tree); not captured: the Watch's instance page.

## Compatibility matrix (ADR 0015)

The app has to work against upstream Engelsystem `main` today, against each of the open PRs (#1709 – #1726) and against all
of them. `ServerFixture` (`TestSupport/ServerFixture.swift`) builds such a server for the stubbed network: the demo data as
real JSON plus the fields and endpoints each PR adds, and the account's `privileges` (403 where the account may not read,
the catch-all 404 `"Not implemented"` for routes an older server lacks). Presets: `.upstreamToday`, `.with(pr:)`,
`.shiftChain` (#1722 → #1723 → #1724), `.allPRs`; `.account(privileges:)` swaps the account.

`ServerCompatibilityMatrixTests` runs the full sync against a fixture and asserts the recorded `FeatureState` per function
and that the sync still succeeds — a missing or forbidden function is hidden, never an error. Not every combination of PRs is
tested. New functions (S tasks) add their expectations to the matrix; removing a PR (R task) deletes its fixture state and
simplifies the tests. Coverage stays at 100 % (`TestSupport` itself is excluded as test infrastructure).
