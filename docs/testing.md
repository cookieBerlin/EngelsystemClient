# Testing

How this project is tested and the practical gotchas of running tests on
this machine. The rule "always add tests for new features" is binding and
also stated in [`CLAUDE.md`](../CLAUDE.md).

- **100 % line coverage gate** ([ADR 0009](adr/0009-full-line-coverage-gate.md)):
  every source file not listed in `scripts/coverage-exclusions.txt` must
  have 100 % line coverage. Check with `scripts/check-coverage.sh` (runs
  the `EngelsystemClientKit` tests with coverage and lists every file below
  the threshold; `COVERAGE_THRESHOLD` overrides it). Exclusions need a
  justification comment **and owner approval** — never add one on your own.
  Generated code is excluded by construction. During the ramp-up, new or
  changed code must reach 100 % in its own commit and files at 100 % must
  not regress; the remaining files are tracked in `docs/backlog.md`.
  Platform-guarded code (`#if os(iOS)`) is not compiled by `swift test` on
  macOS — it needs an Xcode-based coverage run
  (`xcodebuild test -enableCodeCoverage YES`, then `xcrun xccov view
  --report`) or a justified exclusion. Baseline 2026-10-12: Kit own code
  76 %, iOS app unit tests 15.5 %, Watch app 0 %.
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
