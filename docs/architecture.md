# Architecture

Part of the Engelsystem Client documentation set — see [`CLAUDE.md`](../CLAUDE.md) for the entry point and the rest of the doc map. For the story behind these decisions (bugs found, wrong turns, root causes), see [`history.md`](history.md).

## Tech stack (final, binding)

| Area | Decision |
|---|---|
| Deployment target | iOS 26.5, watchOS 26.5 |
| UI | SwiftUI, `@Observable` view models |
| iPad | `NavigationSplitView` (no plain TabView) |
| Persistence | SwiftData, CloudKit-backed (see the sections below) |
| DTOs | generated via OpenAPI Generator (`swift5`, `library=urlsession`,
  `responseAs=AsyncAwait`) from `openapi.yml` — **do not hand-write** |
| Networking | `URLSession` + `async/await`, custom `APIClient` uses the
  generated DTOs |
| Auth storage | Keychain, iCloud-synced |
| Notifications | local only (`UNUserNotificationCenter`), no APNs |
| Organization identifier | `net.cuccato.engelsystem.de` |


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
[`features.md`](features.md)) rather
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

**Local divergence, `COMPAT(#1710)` (2026-10-12):** this project's `openapi.yml` marks `comments_count` as *optional*
(upstream: required), so a server without PR #1710 — whose `/news` items lack the field — still decodes; a missing
value is cached as 0. Removed again by backlog R-03. Note: `Scripts/generate-api.sh` overwrites the hand-patched
macOS-compatibility edits in `Generated/URLSessionImplementations.swift`; restore that one file afterwards with
`git checkout`.

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
not-yet-merged server branch (`feat/api-messages`, now PR [engelsystem/engelsystem#1720](https://github.com/engelsystem/engelsystem/pull/1720), open) via the same
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
  returns nil (the main page) if a previously-selected Messages screen becomes
  unavailable (e.g. the one supporting instance gets deactivated).
- iOS-only, like Locations — no Messages screen on the Watch, per its
  minimal scope.


## Compatibility workarounds (temporary)

Register of everything that exists only because Engelsystem pull requests are not merged yet (decision: ADR 0013, planned
2026-10-12, built by backlog K-01 – K-06). Every spot is tagged `COMPAT(#<PR>)` — `git grep "COMPAT("` lists them all. The
removal tasks R-02 (#1709), R-03 (#1710), R-04 (#1711), R-06 (#1720) and R-13 (final cleanup; formerly R-05) delete them once the PRs are merged, after
which a missing endpoint or a 403 is a real error again. The app **hides what a server lacks** instead of showing errors.

| PR | What the workaround does | Where |
|---|---|---|
| #1710 (news comments) | `comments_count` optional in our `openapi.yml`; missing value cached as 0 | `openapi.yml`, `CachedNews` |
| #1710 | comments supported ⇔ `/news` items carry `comments_count`; recorded per instance | `NewsSyncService`, `ServerCapabilities.newsCommentsSupported` |
| #1710 | "N Comments" link only on supported servers; 404/403 from `GET /news/{id}` hides the comments section silently | `NewsDetailViewModel`, `NewsView`, `NewsDetailView` |
| #1711 (locations) | `GET /locations` forbidden ⇒ Locations hidden for that instance (no error); `GET /locations/{id}` 404/403 ⇒ silent no-op | `LocationSyncService`, `LocationDetailViewModel` |
| #1711 | Locations sidebar row needs one active instance that can list locations; shift location is plain text otherwise | `MainView.Section.visibleSidebarCases`, `ShiftRow` |
| #1709 (no `api` privilege for own data) | "Test Connection" probes `GET /users/self`; a 403 shows a neutral warning (privilege + groups, no PR mention) and still allows Save | `APIClient.accessDeniedWarning`, `APIError.missingPrivilegeMessage`, the four connection-test view models and views |
| #1720 (messages API; requires `user_messages`, not `api`) | Messages capability probe: `GET /messages` decides `Instance.messagesSupported`; the Messages area is hidden unless an active instance supports it | `APIClient.messagesSupported`, `Instance.messagesSupported`, `AppSyncCoordinator`, `MainView` |
| all | device-local `ServerCapabilities` store (`UserDefaults`, `@Observable`), unknown ⇒ available | `ServerCapabilities` (reshaped by K-10 – K-12, ADR 0015; the leftovers are deleted by R-13) |

### Planned matrix (ADR 0015, not built yet)

Per PR the app feature, how its availability is detected, the fallback without the PR and the removing task. Every
fallback is tagged `COMPAT(#<PR>)` when it is built; the feature list per instance (K-10 – K-12) stays permanently.

| PR | App feature | Detection | Fallback without the PR | R task |
|---|---|---|---|---|
| #1709 | rights from `GET /users/self` (`groups`, `privileges`), no 403 warning | `privileges` present | 403 probing, hide on 403 | R-02 |
| #1710 | news comments | `comments_count`, 404 | hidden | R-03 |
| #1711 | locations (list, detail) | 403, 404 | hidden | R-04 |
| #1720 | messages | 403/404 on `GET /messages` | hidden | R-06 |
| #1721 | shift types | 403/404 on `GET /shifttypes` | type name without description | R-07 |
| #1722 | shift fields (`shift_type.description`, `sign_out_until`, `tags`, `talk_url`, `night_shift`, `signup_available_from`) | field present | fields hidden, "usually 3 hours" | R-08 |
| #1723 | `freeloaded`, `can_sign_out`, `user_comment` | field present | `freeloaded_by != null`, button by assumption | R-09 |
| #1724 | `GET /shifts/{id}` | 404 | cached shift, no refresh | R-10 |
| #1725 | angel type fields, `GET /angeltypes/{id}` | field/404 | hidden | R-11 |
| #1726 | profile `goodie_score`, `vouchers`, `arrived`, `next_shift`, `groups` | field present | hidden | R-12 |

Not part of this register: K-06, which stays: shift reminders are planned whenever the *shift* syncs succeeded, independent of News,
Profile, Locations or Messages failing.

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


## Multi-instance concept

**Redesigned and implemented 2026-09-17:** originally exactly one
`Instance` could be "active" at a time (a single `@AppStorage` ID picked
which instance's data Shifts/News/Profile showed). The user asked for
**multiple instances to be active simultaneously** (e.g. helping at more
than one event at once) plus a simpler per-instance settings dialog.
Binding design, now shipped:

- `Instance` SwiftData model: `id`, `name`, `baseURL`,
  `apiKeyKeychainRef`, **`isActive: Bool` (new)**.
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
  name/server already sync.
- **Combined per-instance settings dialog**: the previous two separate
  actions/sheets ("Edit Name / Server" and "Update API Key") merge into
  **one** form — Name, Server URL, API Key (optional).
  The API Key field is **left blank by default and blank means "keep the
  existing key"** — only fill it in to actually change it. Saving always
  re-tests the connection (with whichever key is in play: the freshly
  typed one, or the existing one resolved via
  `InstanceCredentialResolver` when left blank), same "test then save"
  shape as today, and on success updates name/baseURL and (only if
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
  newAPIKeyToStore:store:)` — the single method that replaced the
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
  ceiling documented in [`history.md`](history.md) — wasn't run; verify
  Watch changes via a manual simulator check instead.

## Sync strategy (iOS ↔ Watch), binding

Do **not** use WatchConnectivity as the *primary* mechanism — it only works
when devices are nearby, which conflicts with the "Watch runs independently"
requirement. **Updated 2026-09-23, at the user's explicit request: WatchConnectivity
is now used as an optional, explicit fast-path *supplement*** — see "Keep the
Watch fresh" below. The Watch's own independent sync (its own API call, no
relay) remains what makes it work correctly with no iPhone nearby at all;
WatchConnectivity is never load-bearing for that baseline, only for making an
already-working Watch notice a change sooner while actually paired/reachable.

- **API keys:** Keychain access group + `kSecAttrSynchronizable = true`
  (iCloud Keychain sync)
- **Instance metadata (name, server URL, active/inactive state
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
- **Sync preferences (the background-sync polling interval, "Sync on App
  Start", "Last Background Sync"): plain per-device `@AppStorage`, not
  CloudKit-synced at all** (`DeviceSyncPreferences`, 2026-09-22). ~~The
  polling interval was originally a CloudKit-synced `SyncSettings`
  singleton, shared with the Apple Watch.~~ **Reverted the same day, at
  the user's explicit request**: since Watch background execution isn't
  implemented at all (see "Background sync" below), syncing and
  displaying an interval that does nothing on that platform was
  pointless — `WatchSettingsView` doesn't show it any more either. A
  device only knows about its own background runs anyway, so this isn't
  a loss of a genuinely useful cross-device feature, just the removal of
  one that never had a payoff on the receiving end.

### Keep the Watch fresh (2026-09-23, user-requested)

The user asked whether the iOS app could tell the Watch when shifts change,
to trigger a resync — with an explicit requirement: it must work "im
Verbund" (paired/nearby) when possible, but the Watch must keep working
completely standalone when no connection is possible. Implemented as a
**combo of three layers**, each covering the others' gap:

1. **Standalone baseline (unchanged)**: the Watch's own app-start sync via
   `WatchShiftsSyncCoordinator` (see below) — always runs, independent of
   any connection to the iPhone. This alone already satisfies "must work
   with no Verbund at all."
2. **CloudKit signal** (`Instance.shiftsChangedAt: Date`, a new field on the
   already-CloudKit-backed `Instance` model — deliberately not a new model,
   to reuse the proven CloudKit-sync/`refreshesOnRemoteCloudKitChange`
   machinery instead of adding a parallel one). `ShiftSyncService.sync`
   returns a `ShiftSyncResult { shifts, didChange }` (mirroring
   `NewsSyncResult`'s shape) — `CachedShift.apply(_:)` now reports whether
   it actually changed a field, so a routine sync that found nothing
   different doesn't spuriously bump the signal. Every call site
   (`AppSyncCoordinator`, iOS's `ShiftsViewModel.refresh`, the Watch's
   `NextShiftViewModel.refresh`) bumps `instance.shiftsChangedAt` +
   `touch()` + an explicit `modelContext.save()` on a real change — the
   explicit save matters here for the same reason documented under
   "Explicitly call `modelContext.save()`" further below (CloudKit sync for
   Instance metadata): this field lives on the
   CloudKit-backed `Instance`, so an unflushed change could be silently
   lost the same way a Settings edit once was. On the Watch, this reaches
   app code via the same `refreshesOnRemoteCloudKitChange` `View`
   extension already used for `Instance`'s CloudKit merges — extended to
   also call `WatchShiftsSyncCoordinator.shared.refreshActiveInstances(in:)`
   after its existing `modelContext.save()`, rather than trying to inspect
   which field changed (any remote `Instance` change is treated as "maybe
   shifts changed, resync just in case" — cheap enough not to bother
   distinguishing). **Only reacts while the Watch app process is alive**
   (foreground or still-resident background) — whether this fires reliably
   from a fully suspended/terminated Watch app is unverified, consistent
   with this project's other unverified watchOS background-execution
   assumptions (see `docs/history.md`).
3. **WatchConnectivity nudge** (`WatchConnectivityBridge`,
   `EngelsystemClientKit/Services/`): the explicit, user-requested "Verbund"
   fast path — faster than waiting on CloudKit's server round-trip, but
   only works when the two devices are actually paired/reachable. No
   payload beyond a timestamp: receiving it just means "resync everything
   active," the same thing the Watch's own app-start sync already does, so
   there's no need for per-instance/per-shift detail. Uses
   `updateApplicationContext` (only the *latest* signal matters, no
   history to replay) rather than `transferUserInfo`. Lives in Kit (not
   the iOS app target) specifically so `AppSyncCoordinator` — shared,
   platform-agnostic code — can call `notifyShiftsChanged()` directly and
   unconditionally; it's a safe no-op on watchOS and on macOS (this
   package's `swift test` platform, where `WatchConnectivity` isn't even
   `canImport`-able), guarded by `#if os(iOS) && canImport(WatchConnectivity)`
   internally so callers never need a platform check of their own. The
   *receiving* side (`WatchConnectivityReceiver`,
   `EngelsystemClient Watch App/Services/`) lives in the Watch app target
   instead, since it needs to react by calling into
   `WatchShiftsSyncCoordinator` — a Watch-app-specific type (WidgetKit/
   complication concerns don't belong in the platform-agnostic Kit
   package). Both sides need *some* `WCSessionDelegate` assigned before
   `activate()`; iOS's (`IOSSessionDelegate`, private, inside
   `WatchConnectivityBridge.swift`) exists purely to satisfy that
   requirement, since this feature is send-only from iOS's side.

**`WatchShiftsSyncCoordinator`** (`EngelsystemClient Watch App/Services/`,
`@MainActor` singleton) is the single entry point all three Watch-side
triggers above funnel through — `WatchMainView`'s app-start sync, the
CloudKit-signal handler, and the WatchConnectivity nudge handler all call
either `refresh(instances:in:)` or the convenience
`refreshActiveInstances(in:)` (for callers outside any View's body, which
have no `@Query`-backed instance list to pass in). A simple re-entrancy
guard (`isRefreshing`) coalesces overlapping triggers into one in-flight
sync instead of racing several concurrent ones — if two of these fire close
together for the same underlying change (expected, since the CloudKit
signal and the WatchConnectivity nudge are both triggered by the same
iOS-side event), the later one is simply dropped; the baseline app-start
sync and the user's own pull-to-refresh still guarantee eventual
consistency either way. Internally calls `AppSyncCoordinator().syncEverything(
shiftsOnly: true)`, then `WatchComplicationUpdater.refresh(shifts:)`.

**`WatchComplicationUpdater`** (`EngelsystemClient Watch App/Services/`)
factors out the "write `NextShiftSnapshot` to the App Group + call
`WidgetCenter.shared.reloadAllTimelines()`" step that used to live only
inside `NextShiftViewModel.refresh`. **This fixes a pre-existing gap found
while building this feature**: `WatchMainView`'s app-start sync called
`AppSyncCoordinator` directly and never touched the complication at all —
only a manual pull-to-refresh via `NextShiftView`/`NextShiftViewModel` did.
Now every trigger that can update shifts keeps the complication current,
not just that one.

## Background sync (polling interval), 2026-09-22, user-requested

Added to reduce server load: previously, Shifts/News/Profile each
synced every single time their screen was opened (a `.task` on
appear), on top of pull-to-refresh. Replaced with three distinct,
separately controllable triggers:

1. **Pull-to-refresh** — still available on every screen (Shifts/News/
   Profile), still shows that screen's own loading/error state via its
   existing ViewModel. **2026-09-22, further user-requested**: the main
   page (`MainView`'s sidebar `List`) now supports pull-to-refresh too
   — runs the same full multi-domain sync as the app-start sync (below),
   regardless of the "Sync on App Start" toggle, since pull-to-refresh
   is always an explicit user action. And — the other half of that same
   request — **every** pull-to-refresh (main page, Shifts, News,
   Profile) now shows the same `SyncProgressBanner` the app-start sync
   does, not just the app-start sync: `ShiftsView`/`NewsView`/
   `ProfileView` each take a shared `syncStatus: MainSyncStatus`
   (passed down from `MainView`, the only place all four screens are
   constructed) and wrap their own `viewModel.refresh(...)` call in
   `MainSyncStatus.run(statusText:_:)` — an *indeterminate* banner (no
   step count, since these only ever sync their own single domain, not
   `AppSyncCoordinator`'s three), just a status text ("Shifts"/"News"/
   "Profile") and success/failure. The main page's own pull-to-refresh
   and the app-start sync both go through `AppSyncCoordinator` instead,
   via the sibling `MainSyncStatus.runCoordinated(_:)` (determinate,
   step-counted, same as before). Both helpers share a private
   `showBrieflyThenHide()` (the ~1.2s success/failure flash before
   hiding) so that timing lives in exactly one place.

   **Testing note, worth remembering for this class of problem**: tried
   to verify the banner's on-screen appearance via a real XCUITest
   pull-to-refresh gesture first — both `.swipeDown()` (too fast to
   cross `.refreshable`'s pull threshold at all, confirmed: the gesture
   completed but nothing visibly refreshed) and a manual, slower
   `press(forDuration:thenDragTo:)` drag (crossed the threshold, but
   gesture *synthesis itself* took ~60 real seconds to settle in this
   Simulator — "App animations complete notification not received, will
   attempt to continue" — by which point the actual sync, plus its 1.2s
   success flash, had already finished and hidden long before the test
   could even start checking for it). This is the same fundamental class
   of problem already documented for the launch screen ("a UI-test
   assertion that a short-lived transient element appeared is inherently
   racy... don't add one"), just triggered by a much slower root cause
   here. **Each failed attempt also cost 15–100+ minutes of real
   wall-clock time**, because `xcodebuild`'s own post-test "collecting
   diagnostics from simulator" step hangs after *any* UI test failure on
   this machine (documented elsewhere in this file for a different
   trigger) — don't attempt to re-verify this specific transient banner
   via a real gesture without budgeting for that. Verified instead via:
   the fast, reliable `EngelsystemClientTests.MainSyncStatusTests`
   (`run`/`runCoordinated`'s actual state-machine logic — the part that
   was genuinely new), code review (the `.refreshable` wiring on
   Shifts/News/Profile is structurally identical to their pre-existing,
   already-proven pull-to-refresh, just wrapped), and a fast, non-flaky
   UI test (`testPullToRefreshOnMainPageDoesNotBreakNavigation`) that
   confirms pulling to refresh — via the fast default `swipeDown()`,
   regardless of whether it actually crosses the refresh threshold —
   doesn't break navigation on either the sidebar or a pushed detail
   screen.
2. **App-start sync** — one-shot per app launch, triggered from
   `MainView`'s `.task` (not from any individual screen), togglable via
   Settings' **"Sync on App Start"** (`DeviceSyncPreferences`,
   per-device). Runs the same headless sync as background (below) —
   Shifts, News, and Profile for every active instance — via
   `AppSyncCoordinator.syncEverything`, and shows a compact, non-blocking
   overlay (`SyncProgressBanner`, driven by the `@Observable`
   `MainSyncStatus`) with a determinate progress bar and per-step status
   text (e.g. "News – Demo Congress"), so it doesn't look like the
   screen has frozen — the rest of the app (including navigating into
   Shifts/News/Profile while it's still running) stays fully usable
   underneath, since it's an `.overlay`, not a sheet. Deliberately
   **silent about errors** otherwise (no red banner, no `goToSettings()`
   redirect on a 401) — there's no screen the user is actively looking
   at for that to make sense on; a real 401 still surfaces normally the
   next time the user pulls to refresh the affected screen. Does **not**
   post a "new news" notification (`notifyOnNewNews: false`) — the user
   is already in the app when this runs.
3. **Background/interval sync** — the actual "even when the app is
   closed" mechanism, iOS only (see the Watch caveat below). Configured
   via Settings' **"Background Sync"** picker
   (`PollingInterval`: Manual / 15 / 30 / 60 / 180 / 360 minutes, no
   preset below 15 — see that type's doc comment for why), stored as a
   plain per-device `@AppStorage` value on **`DeviceSyncPreferences`**
   (`EngelsystemClientKit/Services/`) — **not** synced to the Apple
   Watch (see the "Sync strategy" bullet above for the same-day reversal
   of an earlier CloudKit-synced version of this; not shown in
   `WatchSettingsView` at all any more, either). Labeled in the UI as
   **"at least every X"**, not "every X", with an explicit
   footer explaining why: `BGAppRefreshTask`'s `earliestBeginDate` is
   only a lower bound — iOS decides the real cadence based on app usage,
   battery, and system load, and in practice essentially never honors
   anything below ~15 minutes regardless of what's requested. This is a
   documented platform characteristic, not a bug in this feature, and is
   the reason there's no preset shorter than 15 minutes at all: offering
   one would promise a precision the platform can't deliver. Settings
   also shows a per-device **"Last Background Sync"** timestamp
   (`DeviceSyncPreferences`, plain `@AppStorage`, not CloudKit-synced —
   each device's own background runs happen independently) next to the
   existing `CloudSyncStatus` line.

  **`AppSyncCoordinator`** (`EngelsystemClientKit/Services/`) is the
  shared sync logic behind both app-start and background/interval sync —
  loops every active instance, resolves a credential, syncs Shifts (+
  shift notifications, same rule as `ShiftsViewModel`: only rescheduled
  when every instance's *shift* sync succeeded — News/Profile/Locations/Messages failures don't matter), and — unless `shiftsOnly` (the
  Watch's app-start sync, which has no News/Profile catalog to sync at
  all) — News and Profile too. Reports one `Progress` update per
  completed unit of work (including failed ones, so `completed` always
  reaches `total`), and returns whether every instance synced cleanly.
  `notifyOnNewNews` (see the News comments feature in
  [`features.md`](features.md) for
  `NewsNotifier`) is the one place that flag is ever `true` — background
  sync is the only trigger where a "new post found" push notification
  actually makes sense, since the user isn't already looking at the app.
  Deliberately headless: no `isLoading`/`errorMessage`/`isUnauthorized`
  state like the per-screen ViewModels — a 401 here just leaves that
  instance's data as-is, there's no screen to navigate away from.

  **iOS scheduling** (`EngelsystemClient/Services/
  BackgroundSyncScheduler.swift`, app target only — see the Watch caveat
  below for why this can't live in `EngelsystemClientKit`): the classic
  imperative `BGTaskScheduler.register`/`submit` API
  (`BGAppRefreshTaskRequest`), not the newer SwiftUI
  `.backgroundTask(.appRefresh(_:))` scene modifier — deliberately: this
  project has no practical way to verify a background task's real
  execution end-to-end (no always-on physical test rig; the Simulator
  needs a manual LLDB "simulate launch" command per attempt), so the
  priority was picking the API this session could be most confident
  about the exact documented shape of, over the newest one.
  `BGTaskScheduler.shared.register` is called from
  `EngelsystemClientApp.init()` (must happen before the app finishes
  launching — `init()` is the earliest hook available without an
  `AppDelegate`; a struct's property defaults, like
  `sharedModelContainer`, are already applied by the time a custom
  `init()`'s body runs, confirmed safe to read there).
  `BackgroundSyncScheduler.scheduleNext()` submits the next
  `BGAppRefreshTaskRequest` (or cancels any pending one for `.manual`) —
  called after every background run and whenever the interval Picker
  changes in `SettingsView`. ~~Also called on every foreground
  transition, to catch up with an interval change CloudKit-merged in
  from the Watch.~~ Removed the same day the interval stopped being
  CloudKit-synced (see "Sync strategy" above) — it's a plain per-device
  value now, so there's no other-device change to ever catch up with;
  cold launch and the Picker's own `set` are the only times this needs
  to run. `task.expirationHandler` cancels the in-flight sync `Task`
  cooperatively if the OS's time budget is about to run out, rather than
  risking the process being killed mid-write.
  **Entitlements**: `UIBackgroundModes` gained `fetch` alongside the
  existing `remote-notification` (CloudKit push), and a new
  `BGTaskSchedulerPermittedIdentifiers` key lists the one task
  identifier (`net.cuccato.engelsystem.de.backgroundrefresh`) — both in
  `EngelsystemClient-Info.plist`, the existing Info.plist-fragment
  mechanism (see [`app-store.md`](app-store.md)). **Not verified end-to-end this
  session** (same caveat as the Archive scheme pre-action elsewhere in
  this file): confirmed the app builds, launches, and doesn't crash with
  registration/scheduling wired in, but actually observing a real
  background execution needs either patient real-device testing or the
  LLDB simulate-launch command — treat as unverified until one of those
  happens.

  **Watch: background *execution* isn't implemented at all, by
  deliberate scope decision, not an oversight — and, since the same
  day, the interval setting isn't shown or shared there either.**
  Confirmed via research before starting this: the `BackgroundTasks`
  framework (`BGTaskScheduler`, what iOS uses above) **isn't available
  on watchOS at all** — watchOS has a separate, older
  `WKApplicationRefreshBackgroundTask`/`WKExtension
  .scheduleBackgroundRefresh` API instead, and as of watchOS 26 there
  are user reports on Apple's own developer forums of that API no longer
  reliably firing at all. Given that combination — a materially
  different, more awkward API, on top of a currently-reported reliability
  problem on the exact watchOS version this project targets — actually
  implementing Watch background execution was scoped out of this pass
  rather than built on a foundation already reported broken.
  ~~`WatchSettingsView` originally still showed and could set the
  interval, shared via CloudKit with iOS.~~ **Reverted the same day, at
  the user's explicit request**: since Watch never actually runs a
  background sync at all, showing (or syncing) a setting that does
  nothing there was pointless, not just unused — `WatchSettingsView` now
  has no interval picker whatsoever, only a footer note explaining that
  background-by-interval sync isn't available on this platform. The
  Watch's own app-start sync (`WatchMainView`, still per-device, still
  togglable via the same, now-also-per-device "Sync on App Start"
  preference) covers the "don't sync on every screen open" half of this
  feature there; the "even when fully closed" half simply doesn't exist
  on Watch at all, not even as a dormant, unused setting.

  **`NextShiftView`/`ShiftsView`/`NewsView`/`ProfileView` all lost their
  `.task`-on-appear sync trigger** as part of this change — they now
  only sync via `.refreshable` (pull-to-refresh); the app-start/
  background sync above is what populates their `@Query`-backed data
  before the screen is ever opened. `WatchMainView` now owns the Watch's
  app-start sync itself (previously `NextShiftView`'s own `.task`) and
  passes a plain `isAppStartSyncing: Bool` down so `NextShiftView` can
  show a one-line "Syncing…" indicator — no `SyncProgressBanner`-style
  overlay there, the watch screen is too small for it; the shift *data*
  itself still updates reactively via `@Query` regardless of which code
  path wrote it.

  **Testing note: `NotificationScheduler.requestAuthorizationIfNeeded()`
  can't be exercised with a fake center at all** — it calls
  `UNUserNotificationCenter.notificationSettings()`, which returns
  `UNNotificationSettings`, a type with no public initializer, so no
  fake can honestly stand in for it (the existing `FakeNotificationCenter`
  in `NotificationSchedulerTests` already `fatalError`s on that one
  method for the same reason — this was a pre-existing, not newly
  discovered, gap). `AppSyncCoordinator.syncEverything` therefore has a
  `handleNotifications: Bool = true` parameter, always `true` in
  production, only ever passed `false` from
  `EngelsystemClientKitTests.SyncServiceTests`'s `AppSyncCoordinator`
  tests — those construct it with an explicit `NotificationScheduler`/
  `NewsNotifier` whose center `fatalError`s on every method, relying on
  `handleNotifications: false` to guarantee none of them are ever
  actually called. Also worth remembering: `AppSyncCoordinator()`'s
  *default* parameters construct the real `NotificationScheduler()`
  (→ the real `UNUserNotificationCenter.current()`), which crashes
  immediately (`bundleProxyForCurrentProcess is nil`) under `swift
  test`'s bare CLI harness — hit this exact crash once while writing
  these tests; the fix is always constructing `AppSyncCoordinator`
  explicitly with the dummy center in tests, never relying on its
  defaults.


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
instance management is its own screen — see
[`features.md`](features.md) for the "Update API
Key" action that closes the loop once there.

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

~~**Debug logging via `print` in `Shifts`/`News`/`ProfileViewModel` and the
Watch app's `NextShiftViewModel`**~~ **Superseded 2026-09-23 by the
in-app `DebugLog` feature — see
[`features.md`](features.md).** Every one of
these `print` call sites (and every other `print` in the app-target/Kit
source, outside `Generated/`) now routes through `DebugLog.log(...)`
instead.


**User-scoped endpoints are always addressed as `self`** (since 2026-10-12, backlog R-01). The earlier numeric-user-ID
fallback (`Instance.userID`, `selfReferenceWorks`, the "User ID" fields and the `self` probe) was removed once Engelsystem PR
#1708 (`self` for worklogs) was merged — servers without it are not supported. Its history, including the 2026-09-17
root cause (a malformed `{id}` path segment from the generated client, not a server problem), is kept in
[`history.md`](history.md). What stays: `extension UsersIdGetIdParameter: CustomStringConvertible` in `APIEndpoint.swift`
(generated `APIHelper.mapValueToPathItem` would otherwise interpolate the enum case name, e.g. `typeString("self")`, into the
URL), guarded by `EngelsystemClientKitTests.usersIdShiftsGetRequestBuilderProducesACorrectlyFormattedIDPathSegment`, and the
`.me` parameter used by `fetchShifts`/`fetchWorklogs`/`fetchOwnProfile`/`fetchOwnAngelTypes`.

**Edit Instance's Save is gated on Test Connection** (2026-09-21): `EditInstanceViewModel`/`WatchEditInstanceViewModel
.canSubmit` requires `connectionTested`, which starts `true` for an existing instance and is reset by editing `baseURL`/`apiKey`
(`didSet`), so a changed server or key cannot be saved before "Test Connection" succeeded again. The button sits at the very
bottom of the form (above the toolbar Save on iOS, above the in-form Save section on the Watch). Pressing "Test Connection"
never mutates the store; only Save commits.

## CloudKit sync for Instance metadata

Implemented once the user joined the paid Apple Developer Program (see
[`app-store.md`](app-store.md) for the entitlements themselves).
Per this file's binding "Sync strategy" above: only `Instance` (name,
server URL) syncs between iOS and Watch — the `Cached*` models
(shifts, news, profile, worklogs, angel type memberships) stay
local-only per device, since they're just a cache of API data each
platform re-fetches on its own sync schedule anyway, and there's no
reason to sync them.

- **`ModelContainerFactory`** (`EngelsystemClientKit/Persistence/`): the
  single place both app targets build their `ModelContainer` from.
  Splits the full schema into two `ModelConfiguration`s — `Instance`
  alone (CloudKit-backed, container `iCloud.net.cuccato.engelsystem.de`)
  and whatever `Cached*` types the caller passes in (`localSchemaTypes:`,
  always local-only, `cloudKitDatabase: .none`) — combined into one
  `ModelContainer` via `ModelContainer(for: fullSchema, configurations:
  [cloud, local])`. `Instance` is **unconditionally** CloudKit-backed in
  production — no availability pre-check of any kind — since CloudKit's
  own mirroring already degrades gracefully with no iCloud account
  present (local reads/writes keep working; sync merely pauses until an
  account becomes available); the manual entry forms (`InstanceSetupView`,
  `WatchSetupView`) remain the real fallback for a device genuinely
  without an iCloud account. **This used to instead gate on
  `ICloudAvailability.isAvailable`
  (`FileManager.ubiquityIdentityToken != nil`) — root-caused wrong,
  2026-09-18: that check silently forced `Instance` local-only on every
  device the entire time CloudKit sync existed, since
  `ubiquityIdentityToken` belongs to a different iCloud subsystem
  (Documents/Ubiquity) than CloudKit and reported `false` even when
  CloudKit itself was genuinely available.** See
  [`history.md`](history.md) for the full investigation. `forceLocalOnly`/
  `isStoredInMemoryOnly` parameters exist purely so tests get a fully
  deterministic, side-effect-free container regardless of this machine's
  iCloud state (CloudKit mirroring isn't supported on an in-memory store
  at all, so `forceLocalOnly` must be set whenever `isStoredInMemoryOnly`
  is).
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

- **Explicitly call `modelContext.save()` after every SwiftData mutation
  that matters** — `EditInstanceViewModel`/`WatchEditInstanceViewModel
  .save`, `InstanceSetupViewModel`/`WatchSetupViewModel.testAndSave`, and
  `SettingsView`/`WatchSettingsView.delete` all do this explicitly,
  rather than relying on SwiftData's autosave: autosave only flushes on
  certain app-lifecycle events, and a debug "Run" from Xcode that
  replaces an already-running build kills the old process directly
  without ever hitting one of those events — an edit made shortly before
  the next rebuild can otherwise be silently lost. See
  [`history.md`](history.md) for the incident that surfaced this.
- **An already-open `@Query` view doesn't refresh promptly on its own
  when a CloudKit merge lands in the background** —
  `NSPersistentCloudKitContainer`-style merges write directly into the
  store without going through the local `ModelContext`'s own save, and
  `@Query`'s observers are wired to the context's "did save"
  notification, not the underlying store change itself. Fixed via
  `refreshesOnRemoteCloudKitChange(modelContext:)` (a `View` extension,
  duplicated per target — `EngelsystemClient/Features/Shared/
  RemoteChangeRefresh.swift` and `EngelsystemClient Watch App/
  Settings/RemoteChangeRefresh.swift`, kept out of `EngelsystemClientKit`
  since it's SwiftUI view-layer code) that observes Core Data's
  `NSPersistentStoreRemoteChange` notification (SwiftData is built on
  Core Data, so this still fires) and forces a `modelContext.save()` — a
  no-op write, but it's exactly the signal `@Query` needs. Applied once
  at the app root (`.refreshesOnRemoteCloudKitChange(modelContext:
  sharedModelContainer.mainContext)` in both `EngelsystemClientApp`/
  `EngelsystemClient_Watch_App_Watch_AppApp`), not per-screen, so every
  `@Query` bound to the shared context benefits. **Gotcha**:
  `NSPersistentStoreRemoteChange` fires on a background queue, but
  `ModelContext` is main-actor-bound — the handler must add
  `.receive(on: DispatchQueue.main)` to the publisher chain before
  calling `modelContext.save()`, or SwiftUI logs "Publishing changes
  from background threads is not allowed" (hit this exact regression
  while building the fix — see [`history.md`](history.md)). This
  project's `MemberImportVisibility` upcoming-feature flag also means
  `.receive(on:)` needs an explicit `import Combine` in both files
  (normally implicit via SwiftUI).
