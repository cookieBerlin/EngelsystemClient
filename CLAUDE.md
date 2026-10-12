# Project: Engelsystem Client (iOS/iPadOS/watchOS)

This document is the binding core of the project's architecture and
constraints. Read it in full before generating code or making
suggestions.

## Documentation map

This documentation is split across several files, split out
2026-09-23 once this file alone had grown past 2500 lines. Keep **all**
of them up to date as work lands — not just this file:

- **`CLAUDE.md`** (this file) — purpose, scope, API summary, tech
  stack, project/target structure, Watch app scope, implementation
  status, testing practices, and hard constraints. The compact core
  every session needs.
- **[`README.md`](README.md)** — short, human-facing overview for
  GitHub visitors (what this is, how to build/run it). Update it
  whenever the project's purpose, scope, or build/run steps change.
- **[`docs/architecture.md`](docs/architecture.md)** — the current
  design: multi-instance concept, iOS↔Watch sync strategy, background
  sync, the data/code flow and its error-handling rules, and CloudKit
  sync for `Instance` metadata.
- **[`docs/features.md`](docs/features.md)** —
  feature-by-feature current state of `EngelsystemClientKit`, the iOS
  app, and the watchOS app. The single biggest, fastest-growing
  document — append here as features land.
- **[`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md)** — current
  entitlements/signing configuration and actionable Xcode/Info.plist
  gotchas.
- **[`docs/history.md`](docs/history.md)** — investigations, bugs, and
  decisions that are no longer needed to understand today's code, kept
  for the lessons learned. Add here rather than letting closed
  investigations bloat the current-state docs above.
- **[`docs/roadmap.md`](docs/roadmap.md)** — forward-looking planning:
  not-yet-implemented features, release planning (e.g. TestFlight), and
  open decisions awaiting the user's input. All planning discussion
  belongs here, not just in chat — move it here as soon as it firms up
  past "just an idea," and move an item out (into
  `docs/features.md`, with a dated note) once it actually
  ships.
- **[`docs/adr/`](docs/adr/)** — Architecture Decision Records, one file
  per significant architectural decision going forward (started
  2026-10-09; existing decisions made before this date live in their
  original narrative form in `docs/architecture.md`/`docs/history.md`
  and are **not** being retroactively converted, unless asked). See
  [`docs/adr/README.md`](docs/adr/README.md) for the index and template.
  Write a new ADR whenever a decision has real trade-offs worth
  recording for a future session — not for routine implementation
  choices that `docs/features.md` already captures fine.
- **[`docs/backlog.md`](docs/backlog.md)** — concrete, ready-to-pick-up
  development tasks for the next work sessions — the tactical
  counterpart to `docs/roadmap.md`'s strategic/feature-level planning.
  A Roadmap item moves to the Backlog once it's broken down into actual
  tasks someone could start on; a Backlog item is removed (not just
  checked off) once it's done and reflected in
  `docs/features.md`.

## Purpose of the app

Native Apple client app for [Engelsystem](https://github.com/engelsystem/engelsystem/)
(volunteer-management system for events, e.g. congresses). The app uses the
official REST API of the respective Engelsystem instance.

## Current scope (Phase 1 — read-only)

- View your own shifts
- Read news/announcements
- View profile, angel types, worklogs
- Local reminders (UserNotifications) before shift start, generated from the
  loaded shift data — **no** server push, since the API doesn't support that
- Multi-instance capable (multiple events/servers manageable at the same
  time, switching in Settings)
- Watch app: standalone (its own network call — WatchConnectivity, added
  2026-09-23, is only an optional fast-path nudge, never a data relay; see
  `docs/architecture.md`'s "Sync strategy"), shows only the next shift +
  complication
- Demo mode: try the app without a real Engelsystem server or API key
  (see "Demo Mode" below)

## Phase 2 (later, requires backend extension — DO NOT implement now)

- Shift sign-up
- Create/edit shifts
- Do **not** prepare these features as disabled/hidden UI — build them only
  once the backend endpoint exists.

~~Send/receive private messages~~ **Implemented 2026-09-23** — see the
Messages feature in `docs/features.md` and the `/messages`
entry under API below. The backend endpoint this used to be blocked on
now exists (on a not-yet-merged server branch); the client-side GUI is
gated entirely behind a runtime capability probe
(`Instance.messagesSupported`) rather than the usual "wait for the
backend, then build" rule, since the feature had to work correctly
against instances that don't support it yet too — see "if the instance
doesn't offer the new interface, don't show the GUI" in the Messages
writeup.

## API, demo mode, tech stack, project structure

Moved to [`docs/architecture.md`](docs/architecture.md) (D-03, 2026-10-12):

- **Tech stack (binding)** — SwiftUI/`@Observable`, SwiftData + CloudKit,
  generated DTOs (never hand-written), `URLSession` + async/await,
  Keychain, local-only notifications.
- **Project/target structure** and the Watch app target rename note.
- **API** — OpenAPI source, auth, endpoint list and the provenance of
  not-yet-merged server branches (`/news/{id}`, `/locations/{id}`,
  `/messages`).
- **Demo mode** — sentinel-URL approach in `APIClient`/`DemoData`.

## Watch app scope (deliberately minimal)

- Shows **only**: next shift (name, start, location) + complication
- No full shift catalog, no news on the Watch
- Its own API call (`GET /users/self/shifts`, filtered to the next
  upcoming shift)
- Local notification scheduling on the Watch too, for the next shift
- **Exception to "minimal": Settings has full parity with iOS** — at the
  user's explicit request, the Watch app supports the same instance
  management (switch/add/remove, update API key) and notification
  lead-time picker as the iOS Settings screen, including multi-instance
  switching (previously iOS-only). This was a deliberate scope decision,
  not scope creep: "minimal" governs which *data views* the Watch shows
  (still just the next shift, no catalog/news), not configuration. See
  [`docs/features.md`](docs/features.md) for how
  it's reached and built.


## Implementation order

1. ✅ Finish `EngelsystemClientKit` package + codegen setup
2. ✅ SwiftData models (`Instance`, `CachedShift`, `CachedNews`, `CachedUser`,
   `CachedWorklog`) incl. CloudKit configuration — models done, CloudKit
   wiring still open (see [`docs/features.md`](docs/features.md))
3. ✅ `APIClient` + `KeychainSyncStore`/`LocalKeychainStore`
4. ✅ iOS app: `InstanceSetup` feature (first runnable feature)
5. ✅ iOS app: Shifts / News / Profile / Settings
6. ✅ Watch app: `NextShiftView`, sync status display, fallback form
7. ✅ Watch complication
8. ✅ Demo mode (`DemoData` provider in `APIClient` + "Try Demo" entry
   point on `InstanceSetup`)

## Testing

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
  ceiling documented in [`docs/history.md`](docs/history.md), but a
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
  [`docs/features.md`](docs/features.md)): a `waitForExistence(timeout:
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
  [`docs/history.md`](docs/history.md) for a confirmed incident and how
  it was diagnosed (a quick standalone `swift <file>.swift` reproduction
  of just the suspect logic bypasses the simulator entirely and is the
  fastest way to rule the app code in or out).

## Important constraints that apply to every implementation step

- No disabled/hidden buttons for backend features that don't exist yet
  (Phase 2)
- Push notifications exclusively local, never assume server-side push
- Do not hand-modify OpenAPI codegen output — changes belong in
  `openapi.yml` or in a mapping layer outside of `Generated/`
- Sync mechanism is iCloud-based, not WatchConnectivity-based
