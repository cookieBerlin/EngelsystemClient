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

**Redesigned and implemented 2026-09-17:** originally exactly one
`Instance` could be "active" at a time (a single `@AppStorage` ID picked
which instance's data Shifts/News/Profile showed). The user asked for
**multiple instances to be active simultaneously** (e.g. helping at more
than one event at once) plus a simpler per-instance settings dialog.
Binding design, now shipped:

- `Instance` SwiftData model: `id`, `name`, `baseURL`,
  `apiKeyKeychainRef`, `userID`, **`isActive: Bool` (new)**.
- **`isActive` replaces the single `@AppStorage("activeInstanceID")`
  entirely** — any number of instances can be active at once. New
  instances default to `isActive = true` on creation (so "the first
  instance created is activated automatically" no longer needs
  special-case code — every newly created instance already shows up).
  **No migration path for existing data** — the app isn't released yet,
  so there's no installed base whose single `activeInstanceID` needs
  translating into the new field; `@AppStorage("activeInstanceID")` is
  simply deleted outright, not read or ported.
- **Settings UI: two sections, "Active"/"Inactive", not a per-row
  toggle** (the user explicitly rejected a `Toggle` as the interaction).
  `SettingsView`/`WatchSettingsView`'s instance list splits into an
  "Active" and an "Inactive" section (filtering the same `instances`
  array/`@Query` by `isActive`); each row gets a swipe action ("Activate"
  moves an Inactive row to the Active section; "Deactivate" moves an
  Active row to Inactive) that flips `instance.isActive` and saves
  immediately (`try? modelContext.save()`) — no connection test, no
  sheet. Swipe actions were chosen over drag-and-drop between sections
  specifically because they work identically on iOS and watchOS (a drag
  gesture between `List` sections isn't a good fit for watchOS, and
  Watch Settings otherwise mirrors iOS's).
- **`isActive` is CloudKit-synced** (it's just another field on the
  already CloudKit-backed `Instance` model) — activating/deactivating an
  instance on the iPhone does the same on the Watch, consistent with how
  name/server/`userID` already sync.
- **Combined per-instance settings dialog**: the previous two separate
  actions/sheets ("Edit Name / Server" and "Update API Key") merge into
  **one** form — Name, Server URL, User ID (optional), API Key (optional).
  The API Key field is **left blank by default and blank means "keep the
  existing key"** — only fill it in to actually change it. Saving always
  re-tests the connection (with whichever key is in play: the freshly
  typed one, or the existing one resolved via
  `InstanceCredentialResolver` when left blank), same "test then save"
  shape as today, and on success updates name/baseURL/userID and (only if
  a new key was entered) overwrites the keychain entry. The `isActive`
  toggle is *not* part of this dialog — it's independent and instant, per
  above.
- **Shifts/News/Profile now aggregate across every active instance**,
  not just one. Each item (shift, news post, worklog entry) is tied to
  whichever instance it came from via the existing `instanceID` field —
  nothing new needed there, only the `@Query`/fetch predicates change
  from "== the one active instance" to "IN the active instance set".
  **How that aggregate is *displayed* is a user preference** (the user
  explicitly asked for all three, selectable in Settings, not a single
  fixed choice) — a new `multiInstanceDisplayMode` setting, iOS-only
  (see below), one of:
  - **Merged**: one flat list per screen, sorted as today, each row
    carries a small instance name/badge label.
  - **Switcher**: exactly one active instance's data shown at a time
    (closest to today's behavior), with a segmented control/picker at
    the top of each screen to switch between the currently-active
    instances.
  - **Sectioned**: one list per screen, but grouped into a section per
    active instance instead of a flat merge.

  This setting is **iOS-only**, not mirrored to the Watch's Settings
  (breaking `WatchSettingsView`'s usual "full parity with iOS" pattern
  deliberately) — the Watch has no Shifts/News/Profile catalog screens
  for it to apply to (see below).
- **Watch's "next shift" now looks across every active instance**, not
  just one — still shows exactly one shift (per the Watch's deliberately
  minimal scope), but it's the chronologically nearest upcoming shift
  across *all* active instances rather than a single pre-selected one.
  `NextShiftViewModel` syncs each active instance's shifts (looping the
  existing per-instance `ShiftSyncService.sync` call) and picks the
  earliest via `CachedShift.nextShift(from:)` over the combined result.
- All cache models (`CachedShift`, `CachedNews`, `CachedUser`,
  `CachedWorklog`, `CachedAngelTypeMembership`) still reference an
  `Instance` purely via the plain `instanceID: UUID` field (no relationship
  — see "CloudKit sync for Instance metadata" below for why).

### Multi-active-instance redesign — implementation notes (2026-09-17)

How the design above landed in code, for a fresh session that needs the
file-level detail without re-deriving it:

- `Instance.isActive: Bool = true` (`EngelsystemClientKit/Persistence/
  Instance.swift`) — no migration step was needed (the app wasn't
  released yet, so there was no installed base to migrate).
- `@AppStorage("activeInstanceID")` is gone from `SettingsView`/
  `WatchSettingsView`/`MainView`/`WatchMainView`, along with the
  first-instance-auto-activation code it needed (redundant now that
  every new `Instance` defaults to active) — replaced everywhere by
  `instances.filter(\.isActive)`.
- `SettingsView`/`WatchSettingsView` list instances in two sections
  ("Active"/"Inactive"); each row has a swipe action ("Activate"/
  "Deactivate") that flips `instance.isActive`, calls `.touch()`, and
  saves immediately (`try? modelContext.save()`) — no connection test,
  no sheet. The instance detail screen shows a read-only
  `LabeledContent("Status", …)` rather than duplicating the toggle.
- `EditInstanceViewModel`/`WatchEditInstanceViewModel` gained an `apiKey`
  field (blank by default) and now call
  `InstanceSetupService.updateInstance(for:name:baseURL:apiKey:
  newAPIKeyToStore:userID:store:)` — the single method that replaced the
  old separate `updateServerDetails`/`updateAPIKey`. Blank field → the
  caller resolves the existing key via `InstanceCredentialResolver` to
  test with, and passes `newAPIKeyToStore: nil` so the Keychain is never
  touched; a typed value is used to test *and* passed as
  `newAPIKeyToStore` so it overwrites the entry (mirrored into both
  Keychain stores on iOS, same reasoning as the old
  `UpdateAPIKeyViewModel`). `UpdateAPIKeyViewModel`/
  `WatchUpdateAPIKeyViewModel` and their standalone sheets are deleted —
  fully absorbed into the combined "Edit Instance" dialog.
- `MultiInstanceDisplayMode` (`EngelsystemClient/Features/Shared/
  MultiInstanceDisplayMode.swift`, iOS app target only) backs an
  `@AppStorage` picker on `SettingsView`. `ShiftsView`/`NewsView`/
  `ProfileView` each read every active instance's cached data (still
  matched by the existing plain `instanceID` field, no relationship) and
  branch on the mode: `.merged` shows one flat list with a small
  `InstanceBadge` per row, `.switcher` shows one instance at a time via
  the shared `InstancePicker` segmented control, `.sectioned` groups into
  one `Section` per instance. A single active instance always renders as
  `.merged` regardless of the stored preference (no pointless
  picker/sections for one instance). Profile's identity fields (name/
  pronoun/T-shirt/arrived) are inherently per-instance, so `.merged`/
  `.sectioned` show one compact identity row per instance rather than
  merging them into one card — only `.switcher` shows the full
  single-instance identity layout from before this redesign.
- `ShiftsViewModel`/`NewsViewModel`/`ProfileViewModel`/`NextShiftViewModel`
  (Watch) all changed from `refresh(instance:in:)` to
  `refresh(instances:in:)`, looping the existing per-instance sync calls
  and aggregating the results; a failure on one instance doesn't block
  the others from syncing. For Shifts/NextShift specifically,
  `NotificationScheduler.syncNotifications` is only called once, with
  the *combined* shift set, and **only when every instance in the batch
  synced cleanly** that pass — if one instance fails, the others'
  previously scheduled notifications are deliberately left untouched
  rather than risk the "cancel whatever's no longer in the synced set"
  logic dropping a still-valid notification for the instance that didn't
  get a chance to re-sync.
- Watch's `NextShiftView`/`NextShiftViewModel` take every active instance
  and pick the single nearest upcoming shift across all of them via the
  existing `CachedShift.nextShift(from:)` — still one shift shown, per
  the Watch's minimal scope.
- Tests: `EngelsystemClientKitTests` covers `Instance.isActive`'s default
  and the new `InstanceSetupService.updateInstance` (both the
  keychain-untouched-on-blank-key and overwrite-on-new-key paths, plus
  the connection-test-failure path), and re-verifies the generated
  `usersIdShiftsGetWithRequestBuilder` URL fix from the same day still
  holds. `EngelsystemClientTests` (app target) adds
  `EditInstanceViewModelAPIKeyTests` (blank vs. typed key, seeding both
  Keychain stores identically so the assertions hold regardless of
  `ICloudAvailability.isAvailable` in the test environment).
  `EngelsystemClientUITests.testDemoModeNavigationFlow` was updated for
  the renamed "Edit Instance" button and extended to cover the
  swipe-to-activate/deactivate flow end to end. The watchOS UI test's
  source was updated to match (renamed button, dropped "Update API Key"/
  "Active Instance" assertions) but — per the Simulator performance
  ceiling documented below — wasn't run; verify Watch changes via a
  manual simulator check instead.

## Sync strategy (iOS ↔ Watch), binding

Do **not** use WatchConnectivity as the primary mechanism — it only works
when devices are nearby, which conflicts with the "Watch runs independently"
requirement.

- **API keys:** Keychain access group + `kSecAttrSynchronizable = true`
  (iCloud Keychain sync)
- **Instance metadata (name, server URL, `userID`, active/inactive state
  per instance):** CloudKit-backed SwiftData, same CloudKit container in
  both targets — see "Multi-instance concept" above for `isActive`
  (2026-09-17: any number of instances can now be active simultaneously,
  each toggle syncs like the rest of `Instance`'s fields)
- **Fallback:** if iCloud is disabled on the device → allow manual
  key/server entry directly on the Watch (its own local keychain entry,
  independent of sync)
- ~~Startup check: `FileManager.default.ubiquityIdentityToken != nil` to
  check iCloud availability and show fallback UI if needed~~ **Removed
  2026-09-18 — this was wrong from the start.** `ubiquityIdentityToken`
  belongs to the iCloud Documents/Ubiquity-container API family, a
  *different* Apple iCloud subsystem from CloudKit (what `Instance`
  actually syncs through). Confirmed on a real Watch:
  `ubiquityIdentityToken != nil` reported `false` while
  `CKContainer.accountStatus()` correctly reported `.available` for the
  very same signed-in iCloud account — meaning this check had been
  silently forcing `Instance` into a local-only, unsynced
  `ModelConfiguration` on every device (very likely the iPhone too, just
  never noticed since a single-device install behaves identically
  whether or not sync is actually happening) since CloudKit sync was
  first implemented on 2026-09-16. **`Instance` is now unconditionally
  CloudKit-backed in production** — no pre-check at all — since
  CloudKit's own mirroring already degrades gracefully with no iCloud
  account (local reads/writes keep working; sync merely pauses until an
  account becomes available). See `ModelContainerFactory` below for the
  full writeup. `ICloudAvailability.isAvailable`
  (`ubiquityIdentityToken`-based) is still used, unchanged, for choosing
  `KeychainSyncStore` vs. `LocalKeychainStore` when saving an API key —
  that's a genuinely different iCloud feature (iCloud Keychain sync,
  `kSecAttrSynchronizable`) from both CloudKit and Ubiquity/Documents,
  and hasn't been shown to have the same problem.

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
- **Background Modes, both targets: `remote-notification` only** — required
  for CloudKit's silent-push-triggered sync (SwiftData's CloudKit mirroring
  needs this to receive remote-change notifications in the background;
  without it, CloudKit itself raises a hard runtime error, `"BUG IN CLIENT
  OF CLOUDKIT: CloudKit push notifications require the 'remote-notification'
  background mode in your info plist"`, the first time it tries to register).
  This entry previously (incorrectly) said "Background fetch, Background
  processing" — those were **never actually implemented**: no
  `BGTaskScheduler`/`BGAppRefreshTask`/`BGProcessingTask` code exists
  anywhere in this codebase, so that line was aspirational documentation
  that had drifted from reality, not a real capability. Corrected
  2026-09-17 when the CloudKit runtime error above surfaced during Simulator
  sync testing and this project.pbxproj gap was found (`grep
  UIBackgroundModes project.pbxproj` returned nothing at all beforehand).
- **No** push-notification entitlement needed (local notifications only) —
  the CloudKit-driven silent push above is handled entirely by the system/
  CloudKit framework via the Background Mode capability, not by this app
  requesting `UNAuthorizationOptions` push permission or handling APNs
  device tokens itself.

**`INFOPLIST_KEY_UIBackgroundModes`/`INFOPLIST_KEY_WKBackgroundModes` do
not work as build settings on this Xcode version — a real Info.plist
fragment file is required instead.** Both targets use
`GENERATE_INFOPLIST_FILE = YES` (no checked-in Info.plist), and most
Info.plist keys *are* successfully synthesized this way from
`INFOPLIST_KEY_<Key>` build settings (confirmed working:
`UISupportedInterfaceOrientations`, `UIApplicationSceneManifest`,
`WKCompanionAppBundleIdentifier`, etc.) — but `UIBackgroundModes`
specifically is not on whatever internal list of keys Xcode's
Info.plist-generation step recognizes for this synthesis: setting
`INFOPLIST_KEY_UIBackgroundModes` (tried both as a plain string and as a
proper pbxproj array) resolved correctly per `xcodebuild
-showBuildSettings`, but never appeared in the built `Info.plist` no
matter how many times the build was cleaned — confirmed by inspecting
the built bundle directly with `plutil -p`, not just trusting a
successful build. **Fix**: add back a real, minimal Info.plist file
containing just the one key, and reference it via `INFOPLIST_FILE`
*alongside* keeping `GENERATE_INFOPLIST_FILE = YES` — Xcode merges the
two (confirmed: every other synthesized key was still present in the
built plist afterward). The fragment files
(`EngelsystemClient-Info.plist`, `EngelsystemClientWatchApp-Info.plist`)
live at the **project root**, sibling to `EngelsystemClient.xcodeproj`,
**not** inside either target's own folder — both `EngelsystemClient/`
and `EngelsystemClient Watch App Watch App/` are
`PBXFileSystemSynchronizedRootGroup`s (see "Project/target structure"
below), so a loose file dropped inside one gets automatically added to
that target's "Copy Bundle Resources" build phase, which then collides
with the same file also being used as `INFOPLIST_FILE` (`"duplicate
output file ... Info.plist"` — hit this exact error before moving the
files out). If you ever need to add another Info.plist key that doesn't
synthesize via `INFOPLIST_KEY_*`, add it to these existing fragment
files rather than creating new ones.

**`GitCommitHash` Info.plist key + build-number-on-archive (2026-09-17),
both added via the `xcodeproj` Ruby gem, not by hand-editing
`project.pbxproj`/`.xcscheme` directly** (same tool already used for
`EngelsystemComplication` — see "Complication" below):
- **Every build** (`EngelsystemClient`, `EngelsystemClient Watch App Watch
  App`, both Debug and Release) runs a `PBXShellScriptBuildPhase` named
  "Embed Git Commit Hash" — the last build phase, after Copy Bundle
  Resources — that shells out to `git rev-parse --short HEAD` and writes
  the result into a `GitCommitHash` key in the already-built
  `Info.plist` via `PlistBuddy`, so any build (including a plain
  Simulator debug run) can be traced back to the exact commit it came
  from. It's marked `always_out_of_date` so the new build system runs it
  on every build rather than caching it as "up to date".
  - **This required disabling `ENABLE_USER_SCRIPT_SANDBOXING` for both
    targets** (`= NO`, overriding the project-level `= YES` default).
    Xcode 15+'s Run Script sandboxing silently blocks a script's writes
    to any file not declared in its `outputPaths` — the write appeared
    to succeed (exit code 0, no logged error) but the built `Info.plist`
    never actually changed. Declaring the real `Info.plist` path as this
    phase's `outputPaths` (the obvious fix) doesn't work either: it then
    collides with Xcode's own `ProcessInfoPlistFile` task, which also
    claims that path as its output (`"duplicate output file"` build
    error) — confirmed both failure modes hands-on before landing on
    disabling sandboxing for these two targets as the practical fix.
- **Build number (`CURRENT_PROJECT_VERSION`/`CFBundleVersion`) only
  auto-increments when archiving**, not on every build — deliberately
  *not* done via a per-target Run Script Build Phase gated on
  `${ACTION}`, because the iOS app target depends on (and builds after)
  the Watch app target, so a phase living on the iOS target would bump
  the version too late for the already-built Watch app's own Info.plist.
  Instead: `VERSIONING_SYSTEM = apple-generic` on both targets (enables
  `agvtool`), plus an **Archive-action pre-action** on the
  `EngelsystemClient.xcscheme` scheme (`<PreActions>` under
  `<ArchiveAction>`) running `xcrun agvtool next-version -all`, which
  runs once, before *any* target starts building, and bumps
  `CURRENT_PROJECT_VERSION` across every target in the project
  consistently (confirmed hands-on: 1 → 2 across all 14 build configs in
  one invocation, iOS + Watch + both test targets + Complication).
  **Scheme pre-actions/post-actions only run when archiving through
  Xcode's own UI (Product → Archive) — `xcodebuild archive` from the
  command line does not execute them at all.** This project's testing
  this session has been almost entirely `xcodebuild` CLI, so this
  specific behavior could not be (and was not) verified end-to-end the
  same way as everything else — verify manually via Xcode's Organizer
  the first time this matters for a real archive. `agvtool` also prints
  `Cannot find "NO"`/`Cannot find "YES"` noise while doing this (it
  appears to misinterpret some unrelated `GENERATE_INFOPLIST_FILE`
  build-setting values elsewhere in the project as candidate Info.plist
  paths) — harmless, the actual version bump still lands correctly
  despite the noise.
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
  was hand-written entitlements-file editing, **not** the same as adding the
  capability through Xcode's Signing & Capabilities UI — that UI step is
  what actually registers the CloudKit container and provisions the
  Keychain Sharing group against the paid developer account on Apple's
  servers.

  **Confirmed done, 2026-09-16, same day**: the user opened Xcode and
  completed this. Verified from the CLI side (not just taken on faith) by
  inspecting the freshly regenerated local provisioning profiles under
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision`
  (`security cms -D -i <profile> | plutil -extract Entitlements ...`) —
  both the iOS app's and the Watch app's profiles now list
  `com.apple.developer.icloud-container-identifiers = [iCloud.net.cuccato.engelsystem.de]`,
  which Apple only issues once a container by that identifier actually
  exists on their backend, plus `keychain-access-groups` via the
  automatic-signing wildcard group. The CloudKit container and Keychain
  Sharing group are real and provisioned for both targets now — this is no
  longer a manual next step.

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

**Xcode upgraded to 27.0 (build 27A266a) on 2026-09-16**, superseding the
26.6 install referenced throughout this doc — likely resolves the
watchOS 26.6 SDK gap above, since 27.0 brings its own newer simulator
runtimes (confirmed: iOS 27.0 and watchOS 27.0 simulators now exist
alongside the previous 26.5 ones). Opening the project in it bumped
`LastUpgradeCheck`/`LastUpgradeVersion` from 2660 to 2700 across
`project.pbxproj` and all three shared schemes, synced the *project*-level
`DEVELOPMENT_TEAM` (previously stale at the old `TYG73A374P`, unlike the
per-target settings which were already `8A5FNU94BM`) and added
`STRING_CATALOG_GENERATE_SYMBOLS = YES` to the project-level Debug/Release
settings — all routine, harmless auto-upgrade artifacts, committed as-is.
One practical fallout: `xcodebuild -destination 'platform=iOS
Simulator,name=iPhone 17 Pro'` (by device *name*) started emitting a huge
spurious "no matching destination" dump listing every paired/simulator
device on the machine, even though the named simulator exists and the
build still ultimately succeeds — switching to `-destination
'platform=iOS Simulator,id=<UDID>'` (look the UDID up via `xcrun simctl
list devices available`) avoids the noise entirely. Not root-caused
(possibly duplicate/ambiguous device names across the old and new
simulator runtime sets now installed side by side) — just use `id:`
instead of `name:` going forward rather than re-investigating this each
time.

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

~~**Fix: `Instance.userID: Int?`**, an optional numeric fallback (nil =
use `self`, the default/common case).~~ **This diagnosis was itself
wrong — see the 2026-09-17 root-cause entry below.** The `userID`
fallback is kept (a real server could still reject `self` in principle,
and having it costs nothing), but it was not what was actually broken.
`Instance.userReference` resolves to `.id(userID)` when set, else `.me`;
`ShiftSyncService` and `ProfileSyncService`'s three sync calls all read
`instance.userReference` instead of hardcoding `.me`, and
`APIClient.fetchOwnProfile`/`fetchOwnAngelTypes` now take a
`UserReference` parameter (matching `fetchShifts`/`fetchWorklogs`'s
existing shape) instead of hardcoding it internally. Exposed as an
optional "User ID" field on every setup/edit form (`InstanceSetupView`,
`SettingsView`'s `EditInstanceView`, `WatchSetupView`,
`WatchSettingsView`'s `WatchEditInstanceView`) with footer text
explaining it's only needed if Shifts/Profile show up empty — the user
finds their numeric ID in their Engelsystem profile URL. Not validated
against the server during setup/edit (no `/users/{id}`-shaped call
happens during the connection test) — it's just saved alongside
name/baseURL and used on the next sync.

**Actually root-caused, 2026-09-17: the real bug was a broken `{id}`
path parameter in the generated API client, unrelated to the server at
all.** After the `userID` persistence bug above was fixed, the user
still saw `instance.userID = Optional(2), userReference = id(2)`
followed by a 404 and 0 shifts synced — so the numeric fallback was
correctly configured and used, and Shifts *still* failed. Traced to
`UsersIdGetIdParameter` (`Generated/Models/UsersIdGetIdParameter.swift`,
openapi-generator's wrapper for a path parameter that can be an `Int`
*or* a `String`): it's a plain `enum` with associated values, **not**
`RawRepresentable`. The generated `APIHelper.mapValueToPathItem` (used
to stringify every path parameter before building the request URL)
special-cases `RawRepresentable` values via `.rawValue`, but falls
through to returning the value completely unchanged for anything else —
which then gets string-interpolated as-is into the URL. For a Swift enum
with associated values, that interpolation produces the case name plus
its associated value, not the value alone: `.typeInt(2)` became the
literal path segment `"typeInt(2)"`, and `.typeString("self")` became
`"typeString(\"self\")"` (percent-encoded to
`typeString(%22self%22)`). **Every single user-scoped request this app
has ever made — `/users/{id}/shifts`, `/users/{id}`,
`/users/{id}/worklogs`, `/users/{id}/angeltypes`, whether `{id}` was
`self` or a numeric `userID` — was actually requesting a malformed URL
like `/api/v0-beta/users/typeInt(2)/shifts`, not the URL it looked like
from the call site.** This means the 2026-09-05 diagnosis above was
wrong: the server was never actually sent `self` (or a numeric ID) at
all, on any of these endpoints, so there's no evidence any real
Engelsystem server has ever actually rejected `self` — the `userID`
fallback field is being kept anyway (harmless, and this bug could in
principle have been masking a real server incompatibility for some
deployment), but the *reported* 404s were 100% this client bug.

  Fix, entirely in the non-generated mapping layer (`APIEndpoint.swift`,
  not `Generated/` — per this file's standing constraint against
  hand-editing codegen output): added
  `extension UsersIdGetIdParameter: CustomStringConvertible`, mapping
  `.typeInt(v)` → `"\(v)"` and `.typeString(v)` → `v`. String
  interpolation of an `Any`-typed value *does* dispatch to a
  `CustomStringConvertible` conformance even when that conformance is
  added outside the type's own declaration, so this fixes
  `mapValueToPathItem`'s fallthrough without touching generated code —
  confirmed both by an isolated `swift -e` snippet and by the regression
  test below.

  Regression test:
  `EngelsystemClientKitTests
  .usersIdShiftsGetRequestBuilderProducesACorrectlyFormattedIDPathSegment`
  — calls the actual generated `ShiftAPI.usersIdShiftsGetWithRequestBuilder`
  (not just the conformance in isolation) and asserts `URLString` ends in
  `/users/2/shifts` and `/users/self/shifts` respectively, so a future
  `openapi.yml`/codegen regeneration that reintroduces this interaction
  bug gets caught. Verified it actually catches the regression by
  temporarily commenting out the `CustomStringConvertible` conformance
  and re-running: it failed with `URLString` literally reading
  `/api/v0-beta/users/typeInt(2)/shifts`, confirming both the diagnosis
  and the fix.

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

- **Launch screen** (`Features/Launch/LaunchScreenView`, wired into
  `ContentView`, 2026-09-17): shows the app icon, name, and
  `AppVersionInfo.displayString` (version/build/git hash — see
  Entitlements above) for a fixed `ContentView.launchScreenDuration`
  (1.2s) while `ContentView` renders, so there's a branding moment
  instead of jumping straight from the system launch screen into
  `InstanceSetupView`/`MainView`. The icon is read from `Info.plist`'s
  `CFBundleIcons` (the standard way to show the real running app icon
  inside SwiftUI, since an appicon asset set isn't otherwise
  referenceable as a plain `Image`). Not a gate on real async work —
  `ModelContainerFactory.makeContainer` already runs synchronously
  before `ContentView` even appears (see `EngelsystemClientApp`), so
  this is a deliberate minimum-duration splash, not a loading indicator.
  **Not asserted directly in `EngelsystemClientUITests`**: on a
  slow/loaded test machine, cold-launch overhead before XCUITest can
  even query the accessibility hierarchy can exceed the whole 1.2s
  window on its own, so an existence check for the splash text is a
  race against test-harness startup, not a check of real behavior —
  confirmed hands-on (failed at a 5s timeout after an 11s+ cold launch).
  Verified structurally instead (it's what `ContentView` renders first,
  so a crash there would break every later assertion in that test) —
  see the equivalent workaround already needed for the "Try Demo Mode"
  button below.
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
  sidebar of data sections (Shifts/News/Profile) — not a plain
  `TabView`, per the iPad requirement above; collapses to stack
  navigation on iPhone automatically. Since the 2026-09-17 multi-active-
  instance redesign, resolves every `instance.isActive` instance (not a
  single `@AppStorage` ID) and passes that array to whichever section is
  selected; the sidebar's own navigation title reflects the count ("No
  Active Instance" / the one instance's name / "N Active Instances").
  Defaults to Shifts on launch. **Settings is not a sidebar row**
  (changed 2026-09-17, at the user's request) — it's app configuration
  rather than a data section at the same level as Shifts/News/Profile,
  so it's reached via a gear icon in the sidebar's own toolbar corner
  instead. `Section.settings` still exists internally as a `selection`
  value (`Section.sidebarCases` is the subset — `.shifts`/`.news`/
  `.profile` — actually rendered as rows), so `goToSettings()`'s
  401-triggers-navigation behavior (see Data/code flow below) keeps
  working unchanged; only the visible row disappeared.
- **Shifts** (`Features/Shifts`): lists the signed-in user's shifts
  aggregated across every active instance (see "Multi-instance concept"
  above for `MultiInstanceDisplayMode`). `ShiftsViewModel.refresh(instances:
  in:)` loops each active instance's credential resolution + sync; the
  view reads from `CachedShift` via a `@Query` over all instances,
  filtered client-side to the active instance IDs (not a SwiftData
  predicate — simpler, and record counts here are small enough that
  filtering in Swift after the fetch isn't a real cost). Pull-to-refresh
  and an initial `.task` both trigger a sync. Shows a
  `ContentUnavailableView` instead of a list when there are zero active
  instances. **Grouped by calendar day** (2026-09-17, user-reported: a
  shift row only ever showed a time, no date, at all) via
  `CachedShift.groupedByDay` (`EngelsystemClientKit/Persistence/
  CachedShift.swift` — day-sorted, each day's shifts start-time-sorted)
  — `.merged`/`.switcher` render one real `Section` per day (header
  "Today"/"Tomorrow"/weekday+month+day, via `ShiftsView.dateHeaderText`);
  `.sectioned` (already grouped into one `Section` per instance) uses a
  plain styled text row per day instead of a nested real `Section`,
  since a `Section` can't nest inside another `Section` in a plain
  `List`.
- **News** (`Features/News`): same pattern via `NewsSyncService`/
  `CachedNews`/`NewsViewModel.refresh(instances:in:)`; pinned items sort
  first, meeting items get a badge, body text renders through
  `AttributedString(markdown:)` since the API docs say news text may
  contain markdown. `CachedNews.sanitizedText(from:)` strips the `[more]`
  separator tag the API docs mention (and trims the whitespace it
  typically sits between) before storing — we always show the full text,
  so removing the marker is enough, no truncation needed.
- **Profile** (`Features/Profile`): same pattern via
  `ProfileSyncService`/`ProfileViewModel.refresh(instances:in:)` (profile
  + worklogs + angel type memberships, once per active instance)/
  `CachedUser`+`CachedWorklog`+`CachedAngelTypeMembership`; shows profile
  fields (pronoun, T-shirt size, arrived), the user's own angel types
  (`GET /users/{id}/angeltypes` — distinct from `APIClient.fetchAngelTypes`,
  which is the instance-wide catalog) with a supporter/unconfirmed badge,
  and a worklog list with a summed total. Angel types were the one part
  of Phase 1's "profile, angel types, worklogs" scope missed when this
  screen was first built — added afterward once noticed. Unlike
  Shifts/News, the identity fields are inherently per-instance (see
  "Multi-instance concept" above) — `.merged`/`.sectioned` show one
  compact row per instance rather than merging them into one card.
- **Instance management** (`Features/Settings/SettingsView`): reached via
  the gear icon in the sidebar's toolbar corner (see "Main navigation"
  above). A plain pushed list (not its own
  `NavigationSplitView`, since it's already hosted inside `MainView`'s),
  split into "Active"/"Inactive" sections with a swipe action per row to
  move an instance between them (`instance.isActive`, CloudKit-synced —
  see "Multi-instance concept" above; this replaced a single
  `@AppStorage`-backed active instance and a `Toggle` was explicitly
  rejected in favor of this two-section-plus-swipe layout). Removing an
  instance cleans up both keychain stores, since which one was used at
  creation time isn't persisted. The combined **"Edit Instance"**
  dialog (`EditInstanceViewModel`) merges what used to be two separate
  actions — "Edit Name / Server" and "Update API Key" — into one form
  (Name, Server URL, User ID, API Key); the API Key field is blank by
  default and blank means "keep the existing key" (resolved via
  `InstanceCredentialResolver`), only fill it in to actually change it.
  Saving calls `InstanceSetupService.updateInstance` (the single method
  that replaced `updateServerDetails`/`updateAPIKey`), which re-tests the
  connection with whichever key is in play and, on success, updates
  `instance` in place and (only if a new key was typed) overwrites the
  Keychain entry in *both* stores (not just the iCloud-vs-local one
  currently preferred) so a stale value in whichever store
  `InstanceCredentialResolver` happens to check first can't shadow the
  fresh one. If Shifts/News/Profile hits a 401, `MainView` auto-switches
  to this screen so the key can actually be fixed via that same dialog
  (see Data/code flow above). Also a **Multiple Active Instances**
  picker (`MultiInstanceDisplayMode`, see above) and a **Notifications**
  section: a "Notify Before Shift" picker (5/10/15/30/60 min) backed by
  `@AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)`, applying
  to all instances (it's a single app-wide preference, not per-instance).
  At the very bottom, a plain unheadered section shows (2026-09-18)
  `CloudSyncStatus.current(containerIdentifier:)`'s `displayText`
  (`EngelsystemClientKit/Services/CloudSyncStatus.swift`, queried via
  `.task` on appear) above `AppVersionInfo.displayString`
  (`Features/Shared`) — e.g. "iCloud Sync: Active" over
  "Version 1.0 (3) · a1b2c3d" — so a real, on-device sync problem (no
  iCloud account, restricted, temporarily down) and a specific installed
  build are both visible at a glance, without digging through console
  logs. Added directly off the back of the `Instance`-sync root-cause
  fix above — this is the first time sync status was surfaced anywhere
  in the UI rather than only via `print` diagnostics.
  `WatchSettingsView` has the same two-line footer, reusing
  `CloudSyncStatus` from the Kit but its own duplicate `AppVersionInfo`
  (`Settings/`, watch target — duplicated rather than shared since
  `Bundle.main` resolves per-target).
- **Shared feature helpers** (`Features/Shared`): `ErrorBanner` (inline
  red banner for sync errors), `SyncErrorMapper` (maps `APIError`/
  `InstanceCredentialError`/`KeychainError` to the same user-facing
  English message across Shifts/News/Profile/Settings, plus
  `isUnauthorized(_:)` for the 401-triggers-navigation behavior above, so
  the nearly-identical view models don't each re-implement the same
  error-message switch statement), `InstancePicker` (the segmented
  control backing `MultiInstanceDisplayMode.switcher` on Shifts/News/
  Profile), and `MultiInstanceDisplayMode` itself.
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
  Since the 2026-09-17 multi-active-instance redesign, `WatchMainView`
  passes every `instance.isActive` instance to `NextShiftView` rather
  than resolving a single `@AppStorage`-backed active instance —
  `ContentView` still only decides between "no instance yet" (→
  `WatchSetupView`) and "at least one" (→ `WatchMainView`), matching the
  iOS app's `ContentView`/`MainView` split. `WatchSettingsView` mirrors
  iOS's `SettingsView`: two sections ("Active"/"Inactive") with a swipe
  action per row to move an instance between them, no
  `MultiInstanceDisplayMode` picker here (that setting only affects
  iOS's Shifts/News/Profile catalog screens, which the Watch doesn't
  have), and the notification lead-time picker — reached from
  `NextShiftView` via a plain in-content `NavigationLink` row below the
  sync status, **not** a toolbar item: testing showed watchOS's compact
  navigation bar doesn't reliably render a bare `ToolbarItem` here
  (confirmed via the accessibility hierarchy — no element for it existed
  at all), so an ordinary row is used instead. The instance rows in
  `WatchSettingsView` also had to use the destination-closure
  `NavigationLink { destination } label: { }` form rather than
  `NavigationLink(value:)` + `.navigationDestination(for:)`: the
  value-based flavor is what iOS's `SettingsView` uses successfully, but
  on watchOS in this project the tap visibly registered (the row
  highlighted as "Selected" in the accessibility hierarchy) without ever
  performing the actual push — swapping to the closure-based form fixed
  it immediately. Treat this as a watchOS-specific quirk to remember, not
  something to "fix" by reverting to the value-based form.
  Instance-detail's combined **"Edit Instance"** action
  (`WatchEditInstanceViewModel`, the Watch-target twin of iOS's
  `EditInstanceViewModel` — same merged name/server/User ID/API Key form,
  API Key blank-means-unchanged) resolves the existing key via
  `InstanceCredentialResolver` rather than assuming `LocalKeychainStore`,
  since it needs to *read* a key that could in principle live in either
  store, but always uses `LocalKeychainStore` to *write* a freshly typed
  one (no primary/secondary mirroring, same simplification
  `WatchSetupViewModel` already makes). `WatchUpdateAPIKeyViewModel` and
  its standalone sheet are deleted, fully absorbed into this dialog.
  Presenting the edit form as a `.sheet` surfaced another watchOS
  default: an automatic "Close" (`xmark`) button appears in the sheet's
  navigation bar with no code needed for it — `app.swipeDown()` does
  *not* dismiss a watchOS sheet in UI tests, tapping that button does
  (and its nested elements share the same accessibility label, so query
  with `.firstMatch` to avoid an ambiguous-match error).
- **Next Shift** (`Views/NextShiftView`): shows only the next upcoming
  shift (title, time range, location) via the same `ShiftSyncService`
  the iOS Shifts screen uses, plus a sync-status line ("Updated HH:mm")
  and schedules the same local notification for it via
  `NotificationScheduler`. No full shift catalog, no news, per the Watch
  App Scope above. Since the 2026-09-17 redesign, `NextShiftViewModel`
  syncs every active instance and shows the chronologically nearest
  upcoming shift across all of them (still exactly one shift) — see
  "Multi-instance concept" above. After every sync it also writes a
  `NextShiftSnapshot` to the shared App Group (see
  `EngelsystemComplication` below) and calls
  `WidgetCenter.shared.reloadAllTimelines()`.
- watchOS UI Testing needs generous timeouts and a scroll-until-visible
  loop to be reliable — the simulator's cold launch is slow, and a
  `Form`'s (or `List`'s) later sections/rows aren't materialized in the
  accessibility tree until scrolled into view — this applies just as much
  to `WatchSettingsView`'s instance-detail screen (the "Remove Instance"
  section sits below the fold) as it does to the Setup form.
  `EngelsystemClient_Watch_App_Watch_AppUITests` accounts for both;
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
  `ModelContainer(for: fullSchema, configurations: [cloud, local])`.
  `Instance` is **unconditionally** CloudKit-backed in production
  (`forceLocalOnly` is test-only — see below); the manual entry forms
  (`InstanceSetupView`, `WatchSetupView`) remain the real fallback for a
  device genuinely without an iCloud account, since CloudKit's own
  mirroring degrades gracefully in that case rather than needing a
  pre-check. **This used to instead gate on
  `ICloudAvailability.isAvailable`
  (`FileManager.ubiquityIdentityToken != nil`) — root-caused wrong,
  2026-09-18**: that API is part of the iCloud Documents/Ubiquity-
  container family, not CloudKit, and reported `false` on a real Watch
  even while `CKContainer.accountStatus()` correctly reported
  `.available` for the same signed-in account. This had been silently
  forcing `Instance` local-only on every device since CloudKit sync was
  first implemented — see the "Actually root-caused" CloudKit-account
  entry further below for the full story and how it was found. Takes
  `isStoredInMemoryOnly`/`forceLocalOnly` parameters so tests get a fully
  deterministic, side-effect-free container regardless of this machine's
  iCloud state (CloudKit mirroring also isn't supported on an in-memory
  store at all, so `forceLocalOnly` must be set whenever
  `isStoredInMemoryOnly` is).
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
- **Capability registration confirmed done, 2026-09-16** (see the
  Entitlements section above for how this was verified from the CLI side
  via the regenerated provisioning profiles) — the CloudKit container and
  Keychain Sharing group are real and provisioned for both targets now.
- **Root-caused, 2026-09-16: `EngelsystemClient_Watch_App_Watch_AppUITests
  .testDemoModeShowsNextShift` is not CloudKit-related at all — it's an
  Xcode 27.0 / watchOS 27.0 Simulator performance ceiling on this specific
  (M2, non-Pro) Mac.** Confirmed via three separate `xcodebuild test` runs,
  the last one deliberately clean (single simulator pair, verified zero
  stray processes and a calm system beforehand): every run fails at the
  exact same spot — `EngelsystemClient_Watch_App_Watch_AppUITests.swift:114`
  (`app.navigationBars["Demo"].waitForExistence(timeout: 15)`, right after
  tapping the "Demo" row in Settings) — with the same error, `"Failed to
  get matching snapshots: Timed out while evaluating UI query."` This is a
  hard internal XCUITest ceiling on how long a single accessibility-tree
  snapshot may take, separate from and not fixable by raising
  `waitForExistence`'s own `timeout:` parameter. The test process itself
  isn't infinite — it fails after ~4–4.5 minutes, then `xcodebuild` spends
  up to another 10 minutes on its own "collecting diagnostics from
  simulator" step before finally exiting (its own internal 600s ceiling),
  making the whole command take **up to ~15–17 minutes** even though it
  is bounded, not hung.

  First diagnosed (wrongly) as an infinite hang tied to the missing
  CloudKit registration; two premature `pkill -9`s against the
  `xcodebuild` client left their **simulator devices running in the
  background** (killing the client does not shut down the simulator,
  which is owned by the separate long-lived `CoreSimulatorService`) and,
  compounded by booting yet more simulators for each retry without
  shutting the previous ones down, stacked multiple full watchOS
  Simulator instances concurrently — confirmed via `ps aux` showing
  duplicate `ClockFace.app`/`Carousel.app`/`homed`/`navd` processes,
  driving the 1-minute load average to **777** on this machine. That
  pile-up was real and is now cleaned up (`xcrun simctl shutdown all`
  after every attempt from here on), but it was a confound, not the root
  cause: the clean, single-simulator retry failed identically. Even a
  single booted watchOS 27.0 Simulator pair alone was enough to drive
  this Mac to ~100% CPU / 0% idle during the test — the newer Xcode 27
  simulator runtimes (watchOS 27.0 spins up noticeably more system
  daemons — HomeKit, Maps support, nanoprefsync, etc. — than 26.5 did)
  are apparently too heavy for this hardware to service an accessibility
  query fast enough within XCUITest's internal ceiling.

  **Practical takeaway**: don't re-run this specific test as a matter of
  routine on this machine — it will very likely fail the same way every
  time regardless of app-code correctness, and each attempt costs up to
  ~15 minutes. If you need to verify this Watch flow, do it via a manual
  simulator/on-device check instead, or run the test once with real
  patience (let it run the full ~15 minutes to a definitive result rather
  than killing it early) only when you specifically need CI-style
  confirmation. **Always run `xcrun simctl shutdown all` after killing or
  finishing any `xcodebuild test` invocation** — never assume killing the
  client process also tears down the simulator.

  This does **not** implicate the CloudKit sync work above: the iOS UI
  test (`testDemoModeNavigationFlow`) passed fine multiple times in the
  same sessions, the Kit unit tests (including
  `modelContainerFactorySupportsBothInstanceAndLocalModels`) all pass, and
  both platforms' plain (non-test) builds are fine. This caveat is
  entirely about the watchOS Simulator's performance on this machine
  under Xcode 27.0, not about the app or the CloudKit container/Keychain
  Sharing registration (which is separately confirmed working, see
  above).

- **Root-caused and fixed, 2026-09-16: a manually re-entered
  `Instance.userID` (or any other Settings edit) could silently revert
  after rebuilding the app from Xcode.** Reported by the user against a
  real (non-demo) server: they set the `userID` fallback (see the
  "Resolved bug"/"Fix" entries below) via "Edit Name / Server", rebuilt
  the app from Xcode, and the very next sync logged
  `instance.userID = nil, userReference = me` again — the edit had been
  lost. Root cause: **no production code path anywhere ever called
  `modelContext.save()` explicitly** — every mutation (`EditInstanceViewModel`/
  `WatchEditInstanceViewModel`'s `save`, `InstanceSetupViewModel`/
  `WatchSetupViewModel`'s `testAndSave`, `SettingsView`/`WatchSettingsView`'s
  `delete`) relied entirely on SwiftData's autosave. Autosave only flushes on
  certain app-lifecycle events (e.g. the scene resigning active) — a debug
  "Run" from Xcode that replaces an already-running build does **not** go
  through that lifecycle at all, it kills the old process directly, so any
  edit made shortly before the next rebuild had no chance to ever reach
  disk. This wasn't a CloudKit-merge issue (the CloudKit sync work landed
  the same day and was the first suspect) — it reproduces identically with
  CloudKit unreachable, since the loss happens before anything gets a
  chance to sync at all.

  Fix: added explicit `try? modelContext.save()` right after every one of
  the mutations above (`EditInstanceViewModel.save`/
  `WatchEditInstanceViewModel.save` — both gained a `modelContext:` parameter
  they didn't have before, threaded in from `EditInstanceView`/
  `WatchEditInstanceView`'s `@Environment(\.modelContext)` — plus
  `InstanceSetupViewModel`/`WatchSetupViewModel`'s `testAndSave` after
  `modelContext.insert(instance)`, and `SettingsView`/`WatchSettingsView`'s
  `delete` after `modelContext.delete(instance)`). `UpdateAPIKeyViewModel`/
  `WatchUpdateAPIKeyViewModel` needed no change — they only write to the
  Keychain, never mutate the SwiftData `Instance`.

  Regression test:
  `EngelsystemClientTests.EditInstanceViewModelPersistenceTests
  .saveExplicitlyPersistsUserIDAcrossAFreshModelContainerLoad` — deliberately
  reloads from a **second, brand-new** `ModelContainer` pointed at the same
  on-disk store rather than re-reading the original `ModelContext`, since
  the latter would pass even without an explicit save (the edit is visible
  in-memory regardless of whether it was ever flushed) and wouldn't have
  caught this bug. Confirmed it actually catches the regression by
  temporarily removing the `try? modelContext.save()` call and re-running —
  the test failed as expected, then passed again once restored.

- **Actually root-caused, 2026-09-18: `Instance` sync between iOS and
  Watch had never actually worked, on either platform, since CloudKit
  sync was first implemented (2026-09-16) — the CLAUDE.md-specified
  startup check itself used the wrong Apple API.** Reported by the user
  from a real Watch: `WatchSetupView` (the "no instance configured yet"
  fallback) kept showing even though an `Instance` was already active on
  the paired iPhone. `ModelContainerFactory` diagnostic logging (added
  during this investigation, see below) showed
  `ICloudAvailability.isAvailable = false` on the Watch — meaning
  `Instance` had silently fallen back to a local-only `ModelConfiguration`
  there, never even attempting CloudKit. The user confirmed the correct
  Apple ID was signed in on the Watch and iCloud Drive was enabled on the
  paired iPhone, ruling out an actual account problem — which pointed at
  the check itself rather than the device's iCloud state.

  `ICloudAvailability.isAvailable` is `FileManager.default
  .ubiquityIdentityToken != nil` — this is exactly what CLAUDE.md's
  "Sync strategy" originally specified as the binding startup check
  (written before any CloudKit code existed). The problem:
  **`ubiquityIdentityToken` belongs to Apple's iCloud Documents/
  Ubiquity-container API family — a different iCloud subsystem from
  CloudKit entirely**, historically used for detecting iCloud account
  changes for document-based storage (the same family as
  `url(forUbiquityContainerIdentifier:)`, and the reason this app never
  appears in Settings' "apps using iCloud Drive" list — it correctly
  doesn't, since the app never requested that capability, only
  `CloudKit`). Confirmed by adding a parallel diagnostic
  (`ICloudAvailability.logCloudKitAccountStatus`, logs
  `CKContainer.accountStatus()` — CloudKit's own, documented-correct
  availability API) alongside the existing check: on the same real
  Watch, in the same launch, `ubiquityIdentityToken != nil` reported
  `false` while `CKContainer.accountStatus()` reported
  `CKAccountStatus.available` (`rawValue: 1`) for the identical
  signed-in account. The wrong API had been used the entire time —
  first specified in CLAUDE.md itself, before the 2026-09-16 CloudKit
  implementation ever wrote a line of code against it, so this was never
  a coding mistake introduced later, it was baked into the original
  binding design.

  This explains why the 2026-09-16 entitlement verification (provisioning
  profile inspection, confirming the CloudKit container and Keychain
  Sharing group were correctly provisioned) never caught it: that check
  only confirmed the *capability was provisioned*, never that the app
  actually *used* it at runtime — `isAvailable` gated the decision, and
  its always-`false` result meant `Instance` used the CloudKit-configured
  container's identifier as a label only, with `cloudKitDatabase: .none`
  underneath. It also explains why nothing looked broken on the iPhone
  side before this: a single-device install behaves identically whether
  or not CloudKit sync is actually active, so there was nothing to
  visibly contradict.

  Fix: **removed the availability pre-check from `ModelContainerFactory`
  entirely** — `Instance` is now unconditionally CloudKit-backed in
  production (`forceLocalOnly` remains, test-only, for a fully
  deterministic offline container). This is also the more correct
  design regardless of the API mixup: `NSPersistentCloudKitContainer`-
  style CloudKit mirroring is built to degrade gracefully with no iCloud
  account present (local reads/writes keep working; sync merely pauses
  until an account becomes available), so gating the *configuration
  itself* on a point-in-time availability check was never necessary —
  doubly so since `CKContainer.accountStatus()`, the theoretically
  "correct" replacement check, is async and container creation happens
  synchronously at app launch, which would have required a much larger
  restructure to use correctly anyway. `ICloudAvailability.isAvailable`
  itself is untouched and still used exactly as before for choosing
  `KeychainSyncStore` vs. `LocalKeychainStore` — iCloud Keychain sync
  (`kSecAttrSynchronizable`) is a third, genuinely distinct iCloud
  subsystem from both CloudKit and Ubiquity/Documents, and hasn't been
  shown to have this problem.

  `ICloudAvailability.logCloudKitAccountStatus(containerIdentifier:)`
  (`Services/APIKeyStore.swift`) is kept as a standing diagnostic —
  fire-and-forget, logs `CKContainer.accountStatus()` on every
  `ModelContainerFactory.makeContainer` call in production — since it's
  the only place that would surface a *genuine* future CloudKit account
  problem (as opposed to the app-side bug this entry describes).

  **Confirmed fixed on real hardware, same day**: after rebuilding and
  reinstalling on the same physical Watch, the user confirmed `Instance`
  sync from the iPhone now actually arrives — this is the first time
  cross-device `Instance` sync has ever been confirmed working in
  practice, not just via entitlement/provisioning inspection. The new
  `CloudSyncStatus` footer on both Settings screens (see Implemented
  Features below) exists specifically so this stays visible going
  forward without needing a console attached.

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
  ceiling below, but a completely different, mundane cause here). Fix:
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
  this validating the launch screen above: a `waitForExistence(timeout:
  5)` for its text failed outright because cold launch alone had
  already taken 11+ seconds before XCUITest could even query the
  accessibility hierarchy, by which point a 1.2-second on-screen window
  (timed from first render, not from process launch) had long since
  closed. Prefer a structural check (does the rest of the flow still
  work, proving the transient view didn't crash) over trying to catch
  it existing on screen.

## Important constraints that apply to every implementation step

- No disabled/hidden buttons for backend features that don't exist yet
  (Phase 2)
- Push notifications exclusively local, never assume server-side push
- Do not hand-modify OpenAPI codegen output — changes belong in
  `openapi.yml` or in a mapping layer outside of `Generated/`
- Sync mechanism is iCloud-based, not WatchConnectivity-based
