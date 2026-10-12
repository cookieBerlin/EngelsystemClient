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

## API

- Source: `Resources/openapi.yml` (kept in the project, original from
  `https://github.com/engelsystem/engelsystem/blob/main/resources/api/openapi.yml`)
- OpenAPI 3.0.3, base path `/api/v0-beta`, status: beta
- Auth: bearer token **or** `x-api-key` header (API key from the
  Engelsystem user settings). User needs the `API` or `Bureaucrat` group
  on the instance.
- **Every endpoint except `/messages*` is GET-only.** `/messages` (added
  2026-09-23, see below) is this API's first read/write resource —
  `POST`/`PATCH`/`DELETE` alongside its `GET`s:
  - `/users/{id}/shifts`, `/angeltypes/{id}/shifts`, `/locations/{id}/shifts`,
    `/shifttypes/{id}/shifts`
  - `/shifttypes`, `/locations`, `/locations/{id}` (added 2026-09-23, see below),
    `/angeltypes`, `/angeltypes/{id}/users`
  - `/users`, `/users/{id}`, `/users/{id}/angeltypes`
  - `/news`, `/news/{id}` (added 2026-09-22, see below)
  - `/users/{id}/worklogs`
  - `/messages` (GET), `/messages/{id}` (GET, POST), `/messages/{msgId}`
    (DELETE, PATCH) — added 2026-09-23, see below
  - `/info` (event metadata)
  - `/openapi`
- `{id}` can also be the string `self` on user endpoints (own account)
- No server-side push/webhook mechanism exists

**`/news/{id}` added 2026-09-22**, sourced from a fork of the server
project (`github.com/cookieBerlin/engelsystem`, branch
`feat/api-news-comments`) via a cross-session message from a separate
Claude session working on that server — **not merged to that fork's own
main yet**, only combined into a local-only `develop` branch and
deployed live on a private LAN dev test server at the time this was
added. Returns a `NewsDetail` (the existing `News` shape
plus a `comments: [NewsComment]` array, each `{id, text, user:
Reference, created_at, updated_at}`); the existing `News`/`/news` list
also gained a new required `comments_count` field. Applied to this
project's `openapi.yml` by diffing against that branch's copy directly
(fetched via `raw.githubusercontent.com`) rather than hand-writing the
schema, then regenerating via `Scripts/generate-api.sh` as usual.

**`/locations/{id}` added 2026-09-23** (the Locations feature — see
`docs/features.md`), same cross-session-branch workflow:
fetched directly from the pushed branch
(`raw.githubusercontent.com/cookieBerlin/engelsystem/feat/api-locations-detail/resources/api/openapi.yml`,
PR [engelsystem/engelsystem#1711](https://github.com/engelsystem/engelsystem/pull/1711),
**open, not merged upstream yet**) rather than hand-writing the schema.
Reuses the existing `Location` schema as-is (no new fields); 404 for an
unknown id. The same cross-session update reported `/locations` and
`/locations/{id}` no longer require the `api` privilege group, just a
valid authenticated user (same relaxation already in place for
`/users/self/*`/`/news`) — a server-side change only, nothing for this
client to implement. A third branch mentioned in earlier cross-session
messages (full read/write private messages) remains **not implemented
client-side** — Phase 2 scope; see the reference memory saved for it.
If picking up work against any not-yet-merged branch like this later,
re-fetch its current `openapi.yml` the same way rather than trusting an
older cross-session message's field descriptions verbatim, in case the
branch has moved on since.

**`/messages` added 2026-09-23** (the Messages feature — full read/write
private messaging, see `docs/features.md`), sourced from a
not-yet-merged server branch (`feat/api-messages`) via the same
cross-session-branch workflow as `/news/{id}`/`/locations/{id}` above —
fetched directly from the branch's `openapi.yml`, not hand-written, then
regenerated. New schemas: `Message` (`id`, `text`, `sender`/`receiver`:
`Reference`, `read`, `created_at`, `updated_at`), `Conversation`
(`other_user`, `latest_message`, `unread_messages`), `MessageSend`
(`text`, request body for `POST /messages/{id}`), `MessageSetRead`
(`read`, request body for `PATCH /messages/{msgId}`). Also added
`ApiValidationError` (a 422 response schema for the new write
endpoints) — named with an `Api` prefix, not the more obvious
`ValidationError`, because that exact name collides with
openapi-generator's own internal `Validation.swift` boilerplate type;
discovered via a genuine "invalid redeclaration" build error after the
first regeneration attempt, not anticipated in advance.

**This is the API's first read/write resource, and the client
deliberately treats it differently from every read-only feature above**:
- **No `Cached*`/SwiftData model, no sync service — live-only.**
  `APIClient.fetchConversations`/`fetchConversation`/`sendMessage`/
  `deleteMessage`/`setMessageRead` all hit the network every call, same
  shape as `fetchNewsDetail`'s comments. Deliberate: this is the app's
  first mutable, bidirectional data, and a local cache would need to
  reconcile offline writes against a live server — avoiding that
  entirely was judged simpler for a first version than solving it.
- **Gated behind a runtime capability probe, not a "wait for the merge"
  rule.** Since not every Engelsystem deployment will support this
  right away, `Instance.messagesSupported: Bool` (default `false`,
  CloudKit-synced) controls whether the whole Messages sidebar entry
  shows up at all — "if the instance doesn't offer the new interface,
  don't show the GUI" (explicit user requirement). Checked by
  `APIClient.messagesSupported(_:)` as a lightweight extra step in
  `AppSyncCoordinator.syncEverything` (a single `GET /messages`, no
  persistence beyond the one `Bool`) — there's no dedicated Setup/Edit-
  time probe; the periodic re-check via the coordinator is enough to
  pick up a server that gains support later. A plain 404 is ambiguous
  on its own (route missing vs. some other 404), so the probe inspects
  the response *body*: a route that doesn't exist falls through to the
  server's shared catch-all (`{"message": "Not implemented"}`), while a
  genuine "not found" for a specific resource reads `{"message": "Not
  Found"}` — verified against the real server implementation via a
  cross-session message, not guessed. `APIClient.withCredential` was
  refactored to expose a lower-level `withLockedCredential` (gate-lock/
  credential-set/run/gate-unlock only, no `APIError`-wrapping) so this
  probe can see the raw `ErrorResponse` and its body — every other
  caller's behavior is unchanged.
- **`MainView.Section.visibleSidebarCases(forActiveInstances:)`** filters
  the Messages row out unless at least one active instance reports
  `messagesSupported`; `MainView.resolvedSelection(_:visibleSections:)`
  falls back to Shifts if a previously-selected Messages screen becomes
  unavailable (e.g. the one supporting instance gets deactivated).
- iOS-only, like Locations — no Messages screen on the Watch, per its
  minimal scope.

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
| Persistence | SwiftData, CloudKit-backed (see [`docs/architecture.md`](docs/architecture.md)) |
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
  [`docs/features.md`](docs/features.md) for how
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
[`docs/features.md`](docs/features.md)) rather
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
