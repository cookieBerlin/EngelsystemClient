# Project: Engelsystem Client (iOS/iPadOS/watchOS)

This document summarizes all architecture decisions made so far.
Read it in full before generating code or making suggestions.

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
- Watch app: standalone (its own network call, no WatchConnectivity relay),
  shows only the next shift + complication
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
  - `/news`
  - `/users/{id}/worklogs`
  - `/info` (event metadata)
  - `/openapi`
- `{id}` can also be the string `self` on user endpoints (own account)
- No server-side push/webhook mechanism exists

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
| Persistence | SwiftData, CloudKit-backed (see sync below) |
| DTOs | generated via OpenAPI Generator (`swift5`, `library=urlsession`,
  `responseAs=AsyncAwait`) from `openapi.yml` — **do not hand-write** |
| Networking | `URLSession` + `async/await`, custom `APIClient` uses the
  generated DTOs |
| Auth storage | Keychain, iCloud-synced |
| Notifications | local only (`UNUserNotificationCenter`), no APNs |
| Organization identifier | `de.engelsystem` |

## Multi-instance concept

- `Instance` SwiftData model: `id`, `name`, `baseURL`,
  `apiKeyKeychainRef`
- Active instance ID in `@AppStorage`/UserDefaults, not the key itself
- All cache models (`CachedShift`, `CachedNews`, `CachedUser`,
  `CachedWorklog`) reference an `Instance`

## Sync strategy (iOS ↔ Watch), binding

Do **not** use WatchConnectivity as the primary mechanism — it only works
when devices are nearby, which conflicts with the "Watch runs independently"
requirement.

- **API keys:** Keychain access group + `kSecAttrSynchronizable = true`
  (iCloud Keychain sync)
- **Instance metadata (name, server URL, active instance):** CloudKit-backed
  SwiftData, same CloudKit container in both targets
- **Fallback:** if iCloud is disabled on the device → allow manual
  key/server entry directly on the Watch (its own local keychain entry,
  independent of sync)
- Startup check: `FileManager.default.ubiquityIdentityToken != nil` to
  check iCloud availability and show fallback UI if needed

## Watch app scope (deliberately minimal)

- Shows **only**: next shift (name, start, location) + complication
- No full shift catalog, no news on the Watch
- Its own API call (`GET /users/self/shifts`, filtered to the next
  upcoming shift)
- Local notification scheduling on the Watch too, for the next shift

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
│   ├── Views/NextShiftView.swift, NextShiftViewModel.swift
│   └── Setup/WatchSetupView.swift, WatchSetupViewModel.swift (fallback entry UI)
└── EngelsystemComplication/       ← watchOS Widget Extension (embedded in the
                                      Watch app target above), the complication
```

`Package.swift` note: `platforms` must come directly after `name`, before
`products`/`dependencies`/`targets`, otherwise it's a compiler error.

## Entitlements (both targets: iOS app + Watch app)

- iCloud → CloudKit, same container: `iCloud.de.engelsystem`
- Keychain Sharing, same access group:
  `$(AppIdentifierPrefix)de.engelsystem.shared`
- Background Modes (iOS target only): Background fetch, Background processing
- **No** push-notification entitlement needed (local notifications only)
- **App Group** `group.de.engelsystem.shared` (Watch app + `EngelsystemComplication`
  extension only, not iOS): shares the next-shift snapshot with the complication
  process (see Watch App Scope / Implemented Features below). Confirmed working
  for local simulator builds with the free/personal team already configured in
  this project (`DEVELOPMENT_TEAM = TYG73A374P`) — **unlike CloudKit containers,
  App Groups and Keychain Sharing don't require a paid Apple Developer Program
  membership**, only automatic signing with any team. Update the earlier
  assumption in this doc accordingly if you're revisiting the CloudKit/Keychain
  Sharing gap: CloudKit specifically is the one blocked on a paid account, not
  entitlements in general.

## Data/code flow

```
View (SwiftUI)
   ↓ observes
ViewModel (@Observable)
   ↓ calls
APIClient (async/await)
   ↓ uses
Generated DTOs (OpenAPI)
   ↓ mapped to
SwiftData models (persistence + CloudKit sync)
```

Error handling centralized in `APIClient`: 401 → back to Instance Setup,
403 → show "No API access (group `API`/`Bureaucrat` required)",
404 → show empty list instead of an error.

## Implementation order

1. ✅ Finish `EngelsystemClientKit` package + codegen setup
2. ✅ SwiftData models (`Instance`, `CachedShift`, `CachedNews`, `CachedUser`,
   `CachedWorklog`) incl. CloudKit configuration — models done, CloudKit
   wiring still open (see Implemented Features below)
3. ✅ `APIClient` + `KeychainSyncStore`/`LocalKeychainStore`
4. ✅ iOS app: `InstanceSetup` feature (first runnable feature)
5. ✅ iOS app: Shifts / News / Profile / Settings
6. ✅ Watch app: `NextShiftView`, sync status display, fallback form
7. ✅ Watch complication
8. ✅ Demo mode (`DemoData` provider in `APIClient` + "Try Demo" entry
   point on `InstanceSetup`)

## Implemented features (current state)

Kept up to date as features land, so a fresh session can see what already
exists without reading the whole diff history.

### EngelsystemClientKit (shared package)

- **Persistence (SwiftData)**: `Instance`, `CachedShift`, `CachedNews`,
  `CachedUser`, `CachedWorklog` models exist, with cascade-delete
  relationships from `Instance` to all four cache models. **Not yet
  CloudKit-backed** — the app's `ModelConfiguration` is local-only for
  now; CloudKit needs to be wired up once the entitlements below are
  configured.
- **Generated OpenAPI client** (`Generated/`): DTOs and API classes for
  every GET endpoint in `openapi.yml`, produced by
  `Scripts/generate-api.sh`. Regenerate with that script whenever
  `openapi.yml` changes — never hand-edit `Generated/`.
- **APIClient**: async/await wrapper over the generated client —
  `fetchInfo`, `fetchNews`, `fetchAngelTypes`, `fetchLocations`,
  `fetchShiftTypes`, `fetchShifts(for:)`, `fetchWorklogs(for:)`,
  `fetchOwnProfile`. Internally serializes requests (`RequestGate`) so
  concurrent calls to different instances can't clobber the generated
  client's global base URL/headers. Maps 404 to an empty list for list
  endpoints; everything else surfaces as `APIError`
  (unauthorized/forbidden/notFound/server/invalidBaseURL/network/decoding).
- **Keychain storage**: `KeychainSyncStore` (iCloud-synced, shared
  Keychain access group) and `LocalKeychainStore` (device-local fallback)
  behind the shared `APIKeyStore` protocol; `ICloudAvailability` checks
  whether iCloud is available on the device.
- **Demo mode**: `Instance.demoBaseURL` is the sentinel URL; `APIClient`
  checks `EventCredential.isDemo` at the top of every `fetchX` method and
  returns static data from `DemoData` instead of touching the network.
  `DemoData` is `internal`, not `public` — it must stay contained to this
  package.
- **Sync services**: `ShiftSyncService`, `NewsSyncService`,
  `ProfileSyncService` (profile + worklogs) fetch via `APIClient` and
  upsert into the matching `Cached*` SwiftData model, keyed by each
  model's `uid(instanceID:serverID:)`. They take an already-resolved
  `EventCredential` rather than resolving one themselves, so they stay
  free of Keychain side effects and are easy to unit test with the demo
  credential. `InstanceCredentialResolver` does the actual keychain
  lookup (tries `KeychainSyncStore` then `LocalKeychainStore`) and is
  used by the app-target view models, not by the sync services directly.
  Each `Cached*` model has a `DTO`-mapping `init(dto:instanceID:)` and an
  `apply(_ dto:)` updater (e.g. `CachedShift.init(shift:instanceID:)` /
  `CachedShift.apply(_:)`) so the "insert new" and "update existing"
  paths in the sync services share field-mapping code.
- **InstanceSetupService**: the "test the connection, then save the API
  key and return a new `Instance`" logic shared by the iOS app's
  InstanceSetup feature and the Watch app's fallback entry form, so
  neither target re-implements it.

### iOS/iPadOS app

- **Instance Setup** (`Features/InstanceSetup`): form to add an
  Engelsystem instance (name, server URL, API key). Tests the connection
  against `GET /info` before saving; only creates the `Instance` and
  stores the API key in the keychain on success. Shown automatically as
  the app's entry point whenever no instance is configured yet.
- **Demo mode entry point**: a "Try Demo Mode" button on `InstanceSetup`
  creates an `Instance` with `Instance.demoBaseURL` and goes through the
  normal save flow — no separate demo UI anywhere else.
- **Main navigation** (`Features/Main/MainView`): the root view once at
  least one instance exists. A single `NavigationSplitView` with a
  sidebar of four sections (Shifts/News/Profile/Settings) — not a plain
  `TabView`, per the iPad requirement above; collapses to stack
  navigation on iPhone automatically. Resolves the active instance from
  `@AppStorage` (falling back to the first instance) and passes it to
  whichever section is selected; defaults to Shifts on launch.
- **Shifts** (`Features/Shifts`): lists the signed-in user's shifts for
  the active instance. `ShiftsViewModel` resolves the instance's
  credential and calls `ShiftSyncService`; the view itself reads from
  `CachedShift` via `@Query` filtered on `instanceID`, so it's populated
  from whatever was last synced even before a refresh completes.
  Pull-to-refresh and an initial `.task` both trigger a sync.
- **News** (`Features/News`): same pattern via `NewsSyncService`/
  `CachedNews`; pinned items sort first, meeting items get a badge, body
  text renders through `AttributedString(markdown:)` since the API docs
  say news text may contain markdown.
- **Profile** (`Features/Profile`): same pattern via `ProfileSyncService`
  (profile + worklogs in one refresh)/`CachedUser`+`CachedWorklog`; shows
  profile fields (pronoun, T-shirt size, arrived) and a worklog list with
  a summed total.
- **Instance management** (`Features/Settings/SettingsView`): reached via
  the sidebar's Settings section. A plain pushed list (not its own
  `NavigationSplitView`, since it's already hosted inside `MainView`'s)
  of configured instances; switch the active instance (its ID stored in
  `@AppStorage`, not the key itself), view an instance's name/server/
  active status, remove an instance (cleans up both keychain stores,
  since which one was used at creation time isn't persisted). The first
  instance created is activated automatically.
- **Shared feature helpers** (`Features/Shared`): `ErrorBanner` (inline
  red banner for sync errors) and `SyncErrorMapper` (maps `APIError`/
  `InstanceCredentialError` to the same user-facing English message
  across Shifts/News/Profile), so the three nearly-identical view models
  don't each re-implement error-message switch statements.
- **Local shift-start notifications** (`Services/NotificationScheduler`):
  after every successful Shifts sync, requests notification authorization
  if not yet determined and schedules a local reminder
  (`CachedShift.notificationDate(minutesBefore:)`, default 15 minutes
  before start) for each upcoming shift, keyed by a stable identifier
  (`shift-notification-<uid>`) so re-syncing updates in place instead of
  duplicating. Also cancels any previously scheduled shift notification
  that's no longer in the synced/upcoming set. Goes through a thin
  `NotificationCenterScheduling` protocol over `UNUserNotificationCenter`
  so the scheduling logic is unit-testable with a fake center — no
  simulator or real permission prompt needed for that. No server push
  involved, per the "no server-side push" constraint.

### watchOS app

- **Own local setup** (`Setup/WatchSetupView`): the Watch app's fallback
  entry form (name, server URL, API key, plus a "Try Demo Mode" button),
  using the same `InstanceSetupService` as the iOS app. Currently this is
  the *only* way to configure the Watch app, not just the iCloud-
  unavailable fallback — CloudKit sync between the two targets isn't
  wired up yet (see Entitlements above), so the Watch always saves to its
  own `LocalKeychainStore` and its own local-only `Instance`/`CachedShift`
  SwiftData container (schema deliberately excludes `CachedNews`/
  `CachedUser`/`CachedWorklog` — the Watch never needs them per its
  minimal scope). No instance switcher, unlike the iOS app: `ContentView`
  just uses the first (only) `Instance` it finds.
- **Next Shift** (`Views/NextShiftView`): shows only the next upcoming
  shift (title, time range, location) via the same `ShiftSyncService`
  the iOS Shifts screen uses, plus a sync-status line ("Updated HH:mm")
  and schedules the same local notification for it via
  `NotificationScheduler`. No full shift catalog, no news, per the Watch
  App Scope above. After every sync it also writes a `NextShiftSnapshot`
  to the shared App Group (see `EngelsystemComplication` below) and calls
  `WidgetCenter.shared.reloadAllTimelines()`.
- watchOS UI Testing needs generous timeouts and a scroll-until-visible
  loop to be reliable — the simulator's cold launch is slow, and a
  `Form`'s later sections aren't materialized in the accessibility tree
  until scrolled into view. `EngelsystemClient_Watch_App_Watch_AppUITests`
  accounts for both; if a run there fails anyway, cross-check against a
  manual simulator screenshot and EngelsystemClientKit's unit tests
  before assuming an app regression.
- **Complication** (`EngelsystemComplication/`, step 7): a WidgetKit
  extension target embedded in the Watch app, added via the `xcodeproj`
  Ruby gem (`gem install xcodeproj`) since new Xcode targets can't be
  created through the file-system-synchronized-group mechanism the rest
  of this project relies on — only added to *existing* targets. Reads a
  `NextShiftSnapshot` from the `group.de.engelsystem.shared` App Group
  (see Entitlements above) and renders `.accessoryCircular`/
  `.accessoryRectangular`/`.accessoryInline` families; never touches the
  network or Keychain itself (a separate process from the Watch app, no
  access to its Keychain item). Confirmed: builds, installs, and launches
  correctly in the watchOS Simulator. Not verified: actually adding it to
  a watch face and seeing it render there, since that requires the
  Watch Face editing UI (no automation available for that flow here).

### Not yet implemented

- CloudKit sync (iOS + Watch entitlements not configured yet — requires
  a **paid** Apple Developer Program membership, see Entitlements above;
  App Groups/Keychain Sharing are not affected by this and already work).

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

## Important constraints that apply to every implementation step

- No disabled/hidden buttons for backend features that don't exist yet
  (Phase 2)
- Push notifications exclusively local, never assume server-side push
- Do not hand-modify OpenAPI codegen output — changes belong in
  `openapi.yml` or in a mapping layer outside of `Generated/`
- Sync mechanism is iCloud-based, not WatchConnectivity-based
