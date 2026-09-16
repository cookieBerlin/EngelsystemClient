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
| Organization identifier | `net.cuccato.engelsystem.de` |

## Multi-instance concept

- `Instance` SwiftData model: `id`, `name`, `baseURL`,
  `apiKeyKeychainRef`
- Active instance ID in `@AppStorage`/UserDefaults, not the key itself
- All cache models (`CachedShift`, `CachedNews`, `CachedUser`,
  `CachedWorklog`, `CachedAngelTypeMembership`) reference an `Instance`

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
- **Exception to "minimal": Settings has full parity with iOS** — at the
  user's explicit request, the Watch app supports the same instance
  management (switch/add/remove, update API key) and notification
  lead-time picker as the iOS Settings screen, including multi-instance
  switching (previously iOS-only). This was a deliberate scope decision,
  not scope creep: "minimal" governs which *data views* the Watch shows
  (still just the next shift, no catalog/news), not configuration. See
  Implemented Features below for how it's reached and built.

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

## Entitlements (both targets: iOS app + Watch app)

- iCloud → CloudKit, same container: `iCloud.net.cuccato.engelsystem.de`
- Keychain Sharing, same access group:
  `$(AppIdentifierPrefix)net.cuccato.engelsystem.de.shared`
- Background Modes (iOS target only): Background fetch, Background processing
- **No** push-notification entitlement needed (local notifications only)
- **App Group** `group.net.cuccato.engelsystem.de.shared` (Watch app + `EngelsystemComplication`
  extension only, not iOS): shares the next-shift snapshot with the complication
  process (see Watch App Scope / Implemented Features below). Confirmed working
  for local simulator builds with the free/personal team already configured in
  this project (`DEVELOPMENT_TEAM = 8A5FNU94BM` — changed from the original
  `TYG73A374P` after the user switched the Apple ID signed in to Xcode for
  this project; Xcode's automatic signing picked up the new team ID on the
  next build) — **unlike CloudKit containers,
  App Groups and Keychain Sharing don't require a paid Apple Developer Program
  membership**, only automatic signing with any team.

**2026-09-16: iCloud/CloudKit + Keychain Sharing entitlements added to both
targets**, now that the user has joined the paid Apple Developer Program —
this was the one remaining blocker (see the note above and "Not yet
implemented" history below). `EngelsystemClient/EngelsystemClient.entitlements`
is a **new file** (the iOS app target had no entitlements file at all before
this — `CODE_SIGN_ENTITLEMENTS` had to be added to its Debug/Release build
settings in `project.pbxproj`, not just the plist itself); the Watch app's
existing entitlements file gained the same two keys alongside its existing
App Group. Both now declare:
  - `com.apple.developer.icloud-services` = `["CloudKit"]`
  - `com.apple.developer.icloud-container-identifiers` = `["iCloud.net.cuccato.engelsystem.de"]`
  - `keychain-access-groups` = `["$(AppIdentifierPrefix)net.cuccato.engelsystem.de.shared"]`
    (this entitlement key has no `com.apple.` prefix at all, unlike most
    others here — confirmed against `Security/SecItem.h`)

  Verified the entitlements compile and embed correctly (inspected the built
  `.xcent` via `plutil -p`, `$(AppIdentifierPrefix)` resolved to the real
  team ID) and that both the iOS and watchOS schemes still build clean. This
  is hand-written entitlements-file editing, **not** the same as adding the
  capability through Xcode's Signing & Capabilities UI — that UI step is
  what actually registers the CloudKit container and provisions the
  Keychain Sharing group against the paid developer account on Apple's
  servers. **The user still needs to open Xcode once** and confirm/add the
  iCloud (CloudKit checked, container `iCloud.net.cuccato.engelsystem.de`)
  and Keychain Sharing capabilities via Signing & Capabilities for both the
  iOS and Watch targets before real sync will work on-device — simulator
  and CLI builds compile fine either way since they don't enforce real
  provisioning, but that doesn't mean the container/group actually exist on
  Apple's backend yet.

**Bundle identifiers are unique across *all* Apple developer accounts, not just
this project or team.** `EngelsystemComplication`'s original bundle ID
(`de.engelsystem.EngelsystemClient.watchkitapp.complication`) failed to
register on a real device with "cannot be registered ... because it is not
available" — some other account already holds that exact string. Simulator
builds never surface this, since they don't register real App IDs; it only
shows up the first time someone actually runs on a physical device. Renamed
to `...watchkitapp.nextshiftcomplication`, which worked. If you add
another extension/target later and hit the same error on-device, just
pick a more distinctive suffix and retry — it's not something wrong with
the project's signing setup. (The base namespace shown here has since
moved to `net.cuccato.engelsystem.de.*` — see the note below.)

**Namespace base changed from `de.engelsystem.*` to
`net.cuccato.engelsystem.*`** across every bundle identifier, the App
Group, and the (still undeployed) Keychain Sharing/CloudKit identifiers
documented above — at the user's request, moving off the literal domain
of the real upstream Engelsystem project (probably related to the
bundle-ID collision above) onto the user's own domain instead
(`cuccato.net` reversed). `KeychainSyncStore`/`LocalKeychainStore`'s
`kSecAttrService` strings were updated too for consistency, even though
those aren't Apple-registered identifiers and didn't strictly need to
change — note that this means any previously saved API key in a local
simulator/device install becomes unreachable under the old service
string and must be re-entered once.

**Free/personal Apple Developer accounts can only register 10 new App IDs
per rolling 7-day window** — real-device signing hit "Your maximum App ID
limit has been reached" after the bundle-ID collision fix and the
namespace-base change above, since *every* target (app, Watch app,
complication, both test targets, ×2 renames) needs its own freshly
registered App ID each time its bundle identifier changes. This is an
Apple-side quota, not something fixable by clearing caches or
provisioning profiles locally. **Avoid further bundle-identifier churn
in this project for a while** — treat `net.cuccato.engelsystem.*` as
settled unless there's a strong reason to change it again, since each
change burns through the quota across every target at once. If you hit
this again: the iOS app target's own App ID is typically already
registered and unaffected, so the iPhone app can still be built/run
independently even while a newer target (like the complication) is
blocked — only targets whose bundle ID changed *after* the quota was hit
are stuck until the 7-day window rolls over.

**Namespace base changed again, same day, from `net.cuccato.engelsystem.*`
to `net.cuccato.engelsystem.de.*`** — across every bundle identifier, the
App Group, and the Keychain Sharing/CloudKit identifiers, same scope as
the rename above. This one came right after the App ID quota above was
hit and documented, which would normally mean staying put — but the user
switched to a different Apple ID/team in Xcode for this project, so the
rename targets a separate quota pool rather than the one that was just
exhausted. If real-device signing still hits "maximum App ID limit"
after this change, the *new* account's own quota is what's being hit,
not a carryover from the old one. `KeychainSyncStore`/`LocalKeychainStore`'s
`kSecAttrService` strings changed again too, for the same reason as
last time — any previously saved API key becomes unreachable under the
old service string and must be re-entered.

**Benign build warning: `Assets.xcassets: Could not get trait set for
device Watch7,14 with version 26.6`** — confirmed harmless, build still
succeeds and the app installs/runs fine on the watch. Root cause: the
physical Apple Watch (a Watch7,14 = Apple Watch SE 3) updated itself
over the air to watchOS 26.6, but the installed Xcode (26.6, build
17F113 — confirmed to be the latest available at the time) still only
bundles the watchOS 26.5 SDK; Apple hasn't shipped a matching SDK update
yet. `actool`'s device-trait database
(`WatchOS.platform/usr/standalone/device_traits.db`) has no entry for
OS version 26.6 yet, so asset catalog compilation logs this warning for
that specific connected device. Not fixable locally (no newer Xcode
exists yet to install) — will resolve itself once Apple ships an Xcode
update with a matching watchOS 26.6 SDK. Don't mistake this for an
actual asset catalog problem if it recurs.

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
404 → show empty list instead of an error. "Back to Instance Setup" is
realized as "back to Settings" (`MainView.goToSettings`, triggered by
each feature view model's `isUnauthorized` flag) now that Settings/
instance management is its own screen — see Implemented Features below
for the "Update API Key" action that closes the loop once there.

**`CancellationError` is never surfaced as a user-facing error.** Bug
report: opening News sometimes showed a red "Connection failed: The
operation couldn't be completed. (Swift.CancellationError error 1.)"
banner. Root cause: `APIClient.withCredential`'s generic `catch` wrapped
*any* thrown error — including `CancellationError`, thrown when a
SwiftUI `.task` is cancelled because the view it's attached to
disappeared before the fetch finished — into `APIError.network(...)`,
which then rendered as a "Connection failed" message even though nothing
had actually failed. Fixed at two layers: `APIClient.withCredential`
rethrows a `CancellationError` as-is instead of wrapping it, and
`Shifts`/`News`/`ProfileViewModel` (via a new
`SyncErrorMapper.isCancellation(_:)`) and the Watch app's
`NextShiftViewModel` all early-return from their sync `catch` block
without touching `errorMessage`/`isUnauthorized` when the error is a
cancellation. If you add another view model that syncs via one of the
`EngelsystemClientKit` sync services, give its `catch` block the same
guard — this class of bug will otherwise reappear on that screen too.

**Debug logging via `print` in `Shifts`/`News`/`ProfileViewModel` and the
Watch app's `NextShiftViewModel`** (each `refresh()`'s success path logs
the synced item count + server base URL, the catch block logs the raw
error before any mapping/cancellation check) — added while investigating
an open bug (see below) and worth keeping permanently for the same
reason: these are the only points where a sync silently succeeding with
zero items vs. actually failing can be told apart, and the UI alone
can't show that distinction. No sensitive data logged (no API keys).

**Resolved bug: on a real (non-demo) server, Shifts and Profile showed
empty with no error, while News loaded fine.** Reported and root-caused
2026-09-05, confirmed via the user's Xcode console with the debug
logging above: `/users/self/shifts` and `/users/self` both returned a
genuine 404 on this server (`[APIClient] 404 for a list endpoint —
treating as empty list` fired, then `[ProfileViewModel] refresh failed:
notFound`) — so `self` really isn't supported as the `{id}` path
parameter on at least this Engelsystem deployment, despite `openapi.yml`
documenting it as valid (the *spec* allowing a value doesn't guarantee
every real server implements it — this server apparently predates that
alias, or never implemented it). Confirmed present *before* the
`CancellationError` fix above too, so it was never a side effect of
that fix — it's App/server API-compatibility, not a client concurrency
bug.

**Fix: `Instance.userID: Int?`**, an optional numeric fallback (nil =
use `self`, the default/common case). `Instance.userReference` resolves
to `.id(userID)` when set, else `.me`; `ShiftSyncService` and
`ProfileSyncService`'s three sync calls all read `instance.userReference`
instead of hardcoding `.me`, and `APIClient.fetchOwnProfile`/
`fetchOwnAngelTypes` now take a `UserReference` parameter (matching
`fetchShifts`/`fetchWorklogs`'s existing shape) instead of hardcoding it
internally. Exposed as an optional "User ID" field on every setup/edit
form (`InstanceSetupView`, `SettingsView`'s `EditInstanceView`,
`WatchSetupView`, `WatchSettingsView`'s `WatchEditInstanceView`) with
footer text explaining it's only needed if Shifts/Profile show up empty
— the user finds their numeric ID in their Engelsystem profile URL.
Not validated against the server during setup/edit (no `/users/{id}`-
shaped call happens during the connection test) — it's just saved
alongside name/baseURL and used on the next sync.

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
  `CachedUser`, `CachedWorklog`, `CachedAngelTypeMembership` models exist.
  `Instance` is **CloudKit-backed** (`ModelContainerFactory`, see "CloudKit
  sync for Instance metadata" below); the five `Cached*` models are
  local-only and have **no relationship to `Instance`** any more (removed
  when the CloudKit split landed, since SwiftData relationships can't
  cross `ModelConfiguration`s) — they're matched to their instance purely
  by the plain `instanceID: UUID` field every one of them already carries.
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
  neither target re-implements it. Also `updateAPIKey(for:apiKey:store:)`
  for an *existing* `Instance` — same connection test, but overwrites the
  key under the instance's existing `apiKeyKeychainRef` instead of
  creating a new one. Used by the iOS app's "Update API Key" Settings
  action (see Implemented Features below).

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
  say news text may contain markdown. `CachedNews.sanitizedText(from:)`
  strips the `[more]` separator tag the API docs mention (and trims the
  whitespace it typically sits between) before storing — we always show
  the full text, so removing the marker is enough, no truncation needed.
- **Profile** (`Features/Profile`): same pattern via `ProfileSyncService`
  (profile + worklogs + angel type memberships in one refresh)/
  `CachedUser`+`CachedWorklog`+`CachedAngelTypeMembership`; shows profile
  fields (pronoun, T-shirt size, arrived), the user's own angel types
  (`GET /users/{id}/angeltypes` — distinct from `APIClient.fetchAngelTypes`,
  which is the instance-wide catalog) with a supporter/unconfirmed badge,
  and a worklog list with a summed total. Angel types were the one part
  of Phase 1's "profile, angel types, worklogs" scope missed when this
  screen was first built — added afterward once noticed.
- **Instance management** (`Features/Settings/SettingsView`): reached via
  the sidebar's Settings section. A plain pushed list (not its own
  `NavigationSplitView`, since it's already hosted inside `MainView`'s)
  of configured instances; switch the active instance (its ID stored in
  `@AppStorage`, not the key itself), view an instance's name/server/
  active status, remove an instance (cleans up both keychain stores,
  since which one was used at creation time isn't persisted). The first
  instance created is activated automatically. Also **"Update API Key"**
  (`UpdateAPIKeyViewModel`): tests a new key against the instance's
  existing server via `InstanceSetupService.updateAPIKey`, then writes it
  into *both* keychain stores (not just the iCloud-vs-local one currently
  preferred) so a stale value in whichever store `InstanceCredentialResolver`
  happens to check first can't shadow the fresh one. If Shifts/News/Profile
  hits a 401, `MainView` auto-switches to this screen so the key can
  actually be fixed (see Data/code flow above). Also **"Edit Name /
  Server"** (`EditInstanceViewModel`): the name/server were originally
  read-only `LabeledContent` on this screen — the user later asked for
  them to be editable, same as everything else here. Resolves the
  instance's *existing* API key via `InstanceCredentialResolver` (so
  editing the name/server doesn't also demand re-entering the key — that
  stays a separate "Update API Key" action) and re-tests the
  name/server/key combination via the new
  `InstanceSetupService.updateServerDetails`, which mutates the
  `Instance` model in place on success (same "test then save" shape as
  `createInstance`/`updateAPIKey`, always re-testing even for a
  pure-rename since it's cheap and doubles as a health check). Also a
  **Notifications**
  section: a "Notify Before Shift" picker (5/10/15/30/60 min) backed by
  `@AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)`, applying
  to all instances (it's a single app-wide preference, not per-instance).
- **Shared feature helpers** (`Features/Shared`): `ErrorBanner` (inline
  red banner for sync errors) and `SyncErrorMapper` (maps `APIError`/
  `InstanceCredentialError`/`KeychainError` to the same user-facing
  English message across Shifts/News/Profile/Settings, plus
  `isUnauthorized(_:)` for the 401-triggers-navigation behavior above), so
  the nearly-identical view models don't each re-implement the same
  error-message switch statement.
- **Local shift-start notifications** (`Services/NotificationScheduler`):
  after every successful Shifts sync, requests notification authorization
  if not yet determined and schedules a local reminder
  (`CachedShift.notificationDate(minutesBefore:)`) for each upcoming
  shift, keyed by a stable identifier (`shift-notification-<uid>`) so
  re-syncing updates in place instead of duplicating. Also cancels any
  previously scheduled shift notification that's no longer in the
  synced/upcoming set. Goes through a thin `NotificationCenterScheduling`
  protocol over `UNUserNotificationCenter` so the scheduling logic is
  unit-testable with a fake center — no simulator or real permission
  prompt needed for that. No server push involved, per the "no
  server-side push" constraint. **The lead time is user-configurable**:
  `minutesBefore` is a per-call parameter of `syncNotifications(for:
  minutesBefore:)` (not fixed at init) so a change to the Settings picker
  takes effect on the very next sync without recreating the scheduler;
  `NotificationScheduler.configuredMinutesBefore()` reads the value
  whichever platform's Settings screen last wrote via `@AppStorage`,
  falling back to `defaultMinutesBefore` (15) if unset — **both** iOS and
  the Watch app now have this picker (see watchOS app below), each
  reading/writing its own local `UserDefaults` (no CloudKit sync between
  the two yet, so the two platforms' choices are independent, same as
  every other per-device setting until sync is wired up).

### watchOS app

- **Own local setup** (`Setup/WatchSetupView`): the Watch app's manual
  entry form (name, server URL, API key, plus a "Try Demo Mode" button),
  using the same `InstanceSetupService` as the iOS app. Since the CloudKit
  sync described above landed, this is genuinely the **fallback** path now
  (per CLAUDE.md's Sync strategy) rather than the only way to configure
  the Watch — an instance created on iPhone should sync here automatically
  via CloudKit — but that hasn't been end-to-end verified yet (see the
  caveats in "CloudKit sync for Instance metadata" above), so treat this
  form as still load-bearing until that's confirmed. Always saves the API
  key to its own `LocalKeychainStore` regardless (a deliberate
  simplification, not a bug: an instance entered here manually is meant to
  be usable even without iCloud, and this form is also reused as the "Add
  Instance" sheet from `WatchSettingsView` below, not just first-run
  setup). `CachedShift` is the Watch's only local `Cached*` model (schema
  deliberately excludes `CachedNews`/`CachedUser`/`CachedWorklog`/
  `CachedAngelTypeMembership` — the Watch never needs them per its minimal
  scope); `Instance` itself is shared with iOS via `ModelContainerFactory`.
- **Multi-instance + Settings** (`Settings/WatchSettingsView`, `Views/
  WatchMainView`): the Watch app supports the same instance switching
  and Settings screen as iOS, per the "Exception to minimal" note above.
  `WatchMainView` resolves the active instance from
  `@AppStorage("activeInstanceID")` exactly like iOS's `MainView`
  (falling back to the first instance, activating it on first run) —
  `ContentView` now only decides between "no instance yet" (→
  `WatchSetupView`) and "at least one" (→ `WatchMainView`), matching the
  iOS app's `ContentView`/`MainView` split. `WatchSettingsView` mirrors
  iOS's `SettingsView` (instance list with switch/add/remove, "Update API
  Key" via its own `WatchUpdateAPIKeyViewModel` — a Watch-target
  duplicate of iOS's `UpdateAPIKeyViewModel` since that type lives in the
  iOS app target, simplified to always use `LocalKeychainStore` like
  `WatchSetupViewModel` already does — and the notification lead-time
  picker) reached from `NextShiftView` via a plain in-content
  `NavigationLink` row below the sync status, **not** a toolbar item:
  testing showed watchOS's compact navigation bar doesn't reliably render
  a bare `ToolbarItem` here (confirmed via the accessibility hierarchy —
  no element for it existed at all), so an ordinary row is used instead.
  The instance rows in `WatchSettingsView` also had to use the
  destination-closure `NavigationLink { destination } label: { }` form
  rather than `NavigationLink(value:)` + `.navigationDestination(for:)`:
  the value-based flavor is what iOS's `SettingsView` uses successfully,
  but on watchOS in this project the tap visibly registered (the row
  highlighted as "Selected" in the accessibility hierarchy) without ever
  performing the actual push — swapping to the closure-based form fixed
  it immediately. Treat this as a watchOS-specific quirk to remember, not
  something to "fix" by reverting to the value-based form.
  Instance-detail also has an **"Edit Name / Server"** action
  (`WatchEditInstanceViewModel`, the Watch-target twin of iOS's
  `EditInstanceViewModel`, added when the user pointed out neither
  platform could edit these after creation) — unlike
  `WatchUpdateAPIKeyViewModel`, this one resolves the existing key via
  `InstanceCredentialResolver` rather than assuming `LocalKeychainStore`,
  since it needs to *read* a key that could in principle live in either
  store. Presenting this as a `.sheet` surfaced another watchOS default:
  an automatic "Close" (`xmark`) button appears in the sheet's navigation
  bar with no code needed for it — `app.swipeDown()` does *not* dismiss a
  watchOS sheet in UI tests, tapping that button does (and its nested
  elements share the same accessibility label, so query with
  `.firstMatch` to avoid an ambiguous-match error).
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
  `Form`'s (or `List`'s) later sections/rows aren't materialized in the
  accessibility tree until scrolled into view — this applies just as much
  to `WatchSettingsView`'s instance-detail screen (the "Update API Key"/
  "Remove Instance" sections sit below the fold) as it does to the Setup
  form. `EngelsystemClient_Watch_App_Watch_AppUITests` accounts for both;
  if a run there fails anyway, cross-check against a manual simulator
  screenshot and EngelsystemClientKit's unit tests before assuming an app
  regression. **Also watch for the real system notification-permission
  alert**: a fresh install's first sync triggers
  `NotificationScheduler.requestAuthorizationIfNeeded()`'s actual
  authorization prompt, which is a separate springboard-hosted process
  (`com.apple.Carousel` on watchOS) that can silently swallow a tap meant
  for the app if left undismissed — a UI test needs an
  `addUIInterruptionMonitor` for it (plus a no-op `app.tap()` afterward,
  since interruption monitors only fire on a subsequent interaction, not
  proactively), and the button label is locale-dependent (this
  environment's simulator shows German "Erlauben"/"Nicht erlauben", not
  English "Allow"/"Don't Allow" — match both rather than assuming one).
- **Complication** (`EngelsystemComplication/`, step 7): a WidgetKit
  extension target embedded in the Watch app, added via the `xcodeproj`
  Ruby gem (`gem install xcodeproj`) since new Xcode targets can't be
  created through the file-system-synchronized-group mechanism the rest
  of this project relies on — only added to *existing* targets. Reads a
  `NextShiftSnapshot` from the `group.net.cuccato.engelsystem.de.shared` App Group
  (see Entitlements above) and renders `.accessoryCircular`/
  `.accessoryRectangular`/`.accessoryInline` families; never touches the
  network or Keychain itself (a separate process from the Watch app, no
  access to its Keychain item). Confirmed: builds, installs, and launches
  correctly in the watchOS Simulator. Not verified: actually adding it to
  a watch face and seeing it render there, since that requires the
  Watch Face editing UI (no automation available for that flow here).

### CloudKit sync for Instance metadata (2026-09-16)

Implemented once the user joined the paid Apple Developer Program (see
Entitlements above for the entitlements themselves). Per this file's
binding "Sync strategy": only `Instance` (name, server URL, `userID`)
syncs between iOS and Watch — the `Cached*` models (shifts, news, profile,
worklogs, angel type memberships) stay local-only per device, since
they're just a cache of API data each platform re-fetches on its own sync
schedule anyway, and there's no reason to sync them.

- **`ModelContainerFactory`** (new, `EngelsystemClientKit/Persistence/`):
  the single place both app targets build their `ModelContainer` from now,
  replacing the inline schema/container setup that used to live directly
  in each target's `...App.swift`. Splits the full schema into two
  `ModelConfiguration`s — `Instance` alone (CloudKit-backed, container
  `iCloud.net.cuccato.engelsystem.de`) and whatever `Cached*` types the
  caller passes in (`localSchemaTypes:`, always local-only,
  `cloudKitDatabase: .none`) — combined into one `ModelContainer` via
  `ModelContainer(for: fullSchema, configurations: [cloud, local])`. Falls
  back to a local-only configuration for `Instance` too when
  `ICloudAvailability.isAvailable` is false, so the existing manual entry
  forms (`InstanceSetupView`, `WatchSetupView`) remain a real fallback
  rather than a dead code path. Takes `isStoredInMemoryOnly`/
  `forceLocalOnly` parameters so tests get a fully deterministic,
  side-effect-free container regardless of whether the machine running
  them happens to be signed into iCloud (CloudKit mirroring also isn't
  supported on an in-memory store at all, so `forceLocalOnly` must be set
  whenever `isStoredInMemoryOnly` is).
- **`Instance` lost its relationships to the `Cached*` models.** SwiftData
  relationships can't cross `ModelConfiguration`s, and `Instance` now
  lives in a different one than `Cached*`. Two knock-on changes:
  - Every stored property on `Instance` needed a default value (`id: UUID
    = UUID()`, `name: String = ""`, etc.) and `id` lost its `@Attribute(.unique)`
    — both are hard CloudKit/SwiftData requirements for any model in a
    CloudKit-backed configuration, unrelated to this app's own logic. The
    `Cached*` models keep their `.unique` `uid` since they stay local-only.
  - The automatic cascade-delete relationship (`Instance` → `Cached*`,
    `deleteRule: .cascade`) no longer exists, so deleting an instance no
    longer deletes its cached data for free. `SettingsView`/
    `WatchSettingsView`'s `delete(_:)` now do this manually via
    `ModelContext.delete(model:where:)` for each locally-scoped `Cached*`
    type, filtered by `instanceID` (iOS: all five types; Watch: just
    `CachedShift`, matching its narrower schema).
  - The three sync services (`ShiftSyncService`, `NewsSyncService`,
    `ProfileSyncService`) no longer set `existing.instance = instance` /
    `cached.instance = instance` after upserting — that property is gone;
    they already keyed everything off `instanceID` anyway, never the
    relationship.
- **Not yet verified end-to-end on-device or in the Watch simulator.**
  Adding these entitlements by hand-editing the `.entitlements` files
  (necessary since I can't drive Xcode's GUI) is not the same as actually
  registering the CloudKit container/Keychain Sharing group against the
  paid account — that registration normally happens automatically when
  Xcode's Signing & Capabilities UI adds the capability, which needs the
  user's own Xcode session. **The user still needs to open Xcode once**
  and add/confirm iCloud (CloudKit, container
  `iCloud.net.cuccato.engelsystem.de`) + Keychain Sharing via Signing &
  Capabilities for both targets before real sync can be tested.
  Additionally: `EngelsystemClient_Watch_App_Watch_AppUITests
  .testDemoModeShowsNextShift` **hung indefinitely** (killed after ~13+ and
  ~4 minutes on two separate attempts, both well past its normal
  60–120 second runtime) when run via `xcodebuild test` after these
  entitlement changes, while the equivalent iOS UI test
  (`testDemoModeNavigationFlow`) ran fine in the same session with the
  same kind of entitlement additions. Not root-caused — the watchOS
  Simulator's iCloud/CloudKit account-status support is known to be
  weaker than the iOS Simulator's (no real Watch pairing to source an
  iCloud session from), so this may be a simulator-only limitation
  (`ICloudAvailability.isAvailable` resolving `true` on-device/host but
  the actual CloudKit container handshake never completing in that
  environment) rather than an app defect — but this is a guess, not a
  confirmed diagnosis. If you hit this again: don't wait it out past ~2
  minutes, kill the process (low CPU time while "running" is the tell —
  it's hung, not slow) and treat the Watch app's CloudKit path as
  unverified by that test until it can be checked on a real paired
  Watch+iPhone or the hang is root-caused. The iOS side, the Kit unit
  tests (including a new `modelContainerFactorySupportsBothInstanceAndLocalModels`
  test), and both platforms' plain builds are all confirmed fine — this
  caveat is specifically about the Watch *UI test*, not the app code.

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
