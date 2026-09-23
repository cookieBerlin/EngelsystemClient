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
- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — the current
  design: multi-instance concept, iOS↔Watch sync strategy, background
  sync, the data/code flow and its error-handling rules, and CloudKit
  sync for `Instance` metadata.
- **[`docs/IMPLEMENTED_FEATURES.md`](docs/IMPLEMENTED_FEATURES.md)** —
  feature-by-feature current state of `EngelsystemClientKit`, the iOS
  app, and the watchOS app. The single biggest, fastest-growing
  document — append here as features land.
- **[`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md)** — current
  entitlements/signing configuration and actionable Xcode/Info.plist
  gotchas.
- **[`docs/HISTORY.md`](docs/HISTORY.md)** — investigations, bugs, and
  decisions that are no longer needed to understand today's code, kept
  for the lessons learned. Add here rather than letting closed
  investigations bloat the current-state docs above.

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
  `docs/ARCHITECTURE.md`'s "Sync strategy"), shows only the next shift +
  complication
- Demo mode: try the app without a real Engelsystem server or API key
  (see "Demo Mode" below)

## Phase 2 (later, requires backend extension — DO NOT implement now)

- Shift sign-up
- Create/edit shifts
- Send/receive private messages
- Do **not** prepare these features as disabled/hidden UI — build them only
  once the backend endpoint exists.

## API

- Source: `Resources/openapi.yml` (kept in the project, original from
  `https://github.com/engelsystem/engelsystem/blob/main/resources/api/openapi.yml`)
- OpenAPI 3.0.3, base path `/api/v0-beta`, status: beta
- Auth: bearer token **or** `x-api-key` header (API key from the
  Engelsystem user settings). User needs the `API` or `Bureaucrat` group
  on the instance.
- **Only GET endpoints exist** (no POST/PUT/PATCH):
  - `/users/{id}/shifts`, `/angeltypes/{id}/shifts`, `/locations/{id}/shifts`,
    `/shifttypes/{id}/shifts`
  - `/shifttypes`, `/locations`, `/angeltypes`, `/angeltypes/{id}/users`
  - `/users`, `/users/{id}`, `/users/{id}/angeltypes`
  - `/news`, `/news/{id}` (added 2026-09-22, see below)
  - `/users/{id}/worklogs`
  - `/info` (event metadata)
  - `/openapi`
- `{id}` can also be the string `self` on user endpoints (own account)
- No server-side push/webhook mechanism exists

**`/news/{id}` added 2026-09-22**, sourced from a fork of the server
project (`github.com/cookieBerlin/engelsystem`, branch
`feat/api-news-comments`) via a cross-session message from a separate
Claude session working on that server — **not merged to that fork's own
main yet**, only combined into a local-only `develop` branch and
deployed live on the shared dev test server (`a private LAN host`) at the
time this was added. Returns a `NewsDetail` (the existing `News` shape
plus a `comments: [NewsComment]` array, each `{id, text, user:
Reference, created_at, updated_at}`); the existing `News`/`/news` list
also gained a new required `comments_count` field. Applied to this
project's `openapi.yml` by diffing against that branch's copy directly
(fetched via `raw.githubusercontent.com`) rather than hand-writing the
schema, then regenerating via `Scripts/generate-api.sh` as usual. Two
other branches mentioned in the same cross-session conversation
(`/locations/{id}`, and relaxing the `api` privilege group requirement
for `/users/self/*`/`/news`/`/locations` down to "just authenticated")
are **not yet implemented client-side** — only the comments endpoint was
requested so far. If picking those up later, re-fetch each branch's
current `openapi.yml` the same way rather than trusting the
cross-session message's field descriptions verbatim, in case the branch
has moved on since.

## Demo mode (for testing without a real server)

- **Purpose:** let the app (and reviewers/testers without an Engelsystem
  account) be tried out end-to-end without a live server or API key.
- **Approach:** a sentinel base URL (e.g. `demo://engelsystem.local`)
  recognized by `Instance`/`EventCredential`. When active, `APIClient`
  returns static, realistic mock data (a `DemoData` provider inside
  `EngelsystemClientKit`) instead of making real HTTP requests — **no**
  mock server process, no extra networking stack, no separate code path
  in views/view models.
- **Entry point:** a "Try Demo" action on the `InstanceSetup` screen
  creates a normal `Instance` with the demo sentinel URL. From then on it
  behaves exactly like any other instance (shows up in `InstanceListView`,
  can be switched to/removed, etc.) — no demo-specific UI anywhere else.
- **Constraint:** demo data lives only in `EngelsystemClientKit`'s
  networking layer (`APIClient`/`DemoData`) — never as hardcoded fallbacks
  inside views or view models, so the demo and real code paths stay
  identical except for where `APIClient` gets its data from.

## Tech stack (final, binding)

| Area | Decision |
|---|---|
| Deployment target | iOS 26.5, watchOS 26.5 |
| UI | SwiftUI, `@Observable` view models |
| iPad | `NavigationSplitView` (no plain TabView) |
| Persistence | SwiftData, CloudKit-backed (see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)) |
| DTOs | generated via OpenAPI Generator (`swift5`, `library=urlsession`,
  `responseAs=AsyncAwait`) from `openapi.yml` — **do not hand-write** |
| Networking | `URLSession` + `async/await`, custom `APIClient` uses the
  generated DTOs |
| Auth storage | Keychain, iCloud-synced |
| Notifications | local only (`UNUserNotificationCenter`), no APNs |
| Organization identifier | `net.cuccato.engelsystem.de` |

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
  [`docs/IMPLEMENTED_FEATURES.md`](docs/IMPLEMENTED_FEATURES.md) for how
  it's reached and built.

## Project/target structure

```
Engelsystem.xcodeproj
├── EngelsystemClientKit/          ← SPM package (shared, iOS + watchOS)
│   ├── Sources/EngelsystemClientKit/
│   │   ├── DTO/                   ← generated, do not hand-edit
│   │   ├── Generated/             ← OpenAPI Generator output
│   │   ├── Persistence/           ← Instance, CachedShift, CachedNews, ...
│   │   ├── Networking/            ← APIClient, APIEndpoint, APIError
│   │   └── Services/              ← ShiftSyncService, NewsSyncService,
│   │                                 ProfileSyncService, NotificationScheduler,
│   │                                 InstanceSetupService, InstanceCredentialResolver,
│   │                                 NextShiftSnapshotStore, KeychainSyncStore,
│   │                                 LocalKeychainStore
│   └── Resources/openapi.yml
├── EngelsystemClient/             ← iOS/iPadOS target
│   └── Features/
│       ├── InstanceSetup/
│       ├── Shifts/
│       ├── News/
│       ├── Profile/
│       └── Settings/
├── EngelsystemClient Watch App/   ← watchOS target
│   ├── Views/NextShiftView.swift, NextShiftViewModel.swift, WatchMainView.swift
│   ├── Setup/WatchSetupView.swift, WatchSetupViewModel.swift (fallback entry UI,
│   │                                also reused as the "Add Instance" sheet)
│   └── Settings/WatchSettingsView.swift, WatchUpdateAPIKeyViewModel.swift,
│                                 WatchEditInstanceViewModel.swift
└── EngelsystemComplication/       ← watchOS Widget Extension (embedded in the
                                      Watch app target above), the complication
```

`Package.swift` note: `platforms` must come directly after `name`, before
`products`/`dependencies`/`targets`, otherwise it's a compiler error.

**2026-09-23, renamed: the Watch app's folder/target/product names were
doubled** (`EngelsystemClient Watch App Watch App`, plus matching
`...Watch App Watch AppTests`/`...UITests`) — an artifact of how Xcode
originally created the target (the product's own display name,
`INFOPLIST_KEY_CFBundleDisplayName`, was already correctly
"EngelsystemClient Watch App" the whole time, so this never showed up
to an actual user; it was purely an internal Xcode/project-file
naming glitch). Fixed via the `xcodeproj` Ruby gem (same tool this
project already uses for structural `project.pbxproj` changes — see
"Complication" in
[`docs/IMPLEMENTED_FEATURES.md`](docs/IMPLEMENTED_FEATURES.md)) rather
than hand-editing the pbxproj text: renamed
the three targets' `name`/`productName`, the three
`PBXFileSystemSynchronizedRootGroup` paths, the `Products` group's
`.app`/`.xctest` file references, `CODE_SIGN_ENTITLEMENTS`/`TEST_HOST`/
`TEST_TARGET_NAME` build settings, and the `PBXContainerItemProxy.
remoteInfo` fields (cosmetic Xcode-UI hints, easy to miss — grep for
the old name again afterward if you ever touch this area, rather than
trusting the gem's higher-level rename helpers alone caught everything).
Also renamed the actual directories/files on disk (`git mv`, preserving
history) — the entitlements file, the two doubled-scheme `.xcscheme`
files (the Watch app's own, and `EngelsystemComplication.xcscheme`,
which references the Watch app target as its host), and three Swift
files whose *filenames* were doubled too
(`EngelsystemClient_Watch_App_Watch_App{Tests,UITests,UITestsLaunchTests}.swift`).
**The generated Swift module name changed as a side effect** (Xcode
derives it from `PRODUCT_NAME`, which was `$(TARGET_NAME)`): the Watch
unit test target's `@testable import EngelsystemClient_Watch_App_Watch_App`
had to become `@testable import EngelsystemClient_Watch_App` — easy to
miss since nothing else about that line looks related to the rename at
a glance.

## Implementation order

1. ✅ Finish `EngelsystemClientKit` package + codegen setup
2. ✅ SwiftData models (`Instance`, `CachedShift`, `CachedNews`, `CachedUser`,
   `CachedWorklog`) incl. CloudKit configuration — models done, CloudKit
   wiring still open (see [`docs/IMPLEMENTED_FEATURES.md`](docs/IMPLEMENTED_FEATURES.md))
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
  ceiling documented in [`docs/HISTORY.md`](docs/HISTORY.md), but a
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
  [`docs/IMPLEMENTED_FEATURES.md`](docs/IMPLEMENTED_FEATURES.md)): a `waitForExistence(timeout:
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
  [`docs/HISTORY.md`](docs/HISTORY.md) for a confirmed incident and how
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
