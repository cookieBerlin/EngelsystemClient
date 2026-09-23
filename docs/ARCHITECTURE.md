# Architecture

Part of the Engelsystem Client documentation set — see [`CLAUDE.md`](../CLAUDE.md) for the entry point and the rest of the doc map. For the story behind these decisions (bugs found, wrong turns, root causes), see [`HISTORY.md`](HISTORY.md).

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
  ceiling documented in [`HISTORY.md`](HISTORY.md) — wasn't run; verify
  Watch changes via a manual simulator check instead.

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
  when every instance synced cleanly), and — unless `shiftsOnly` (the
  Watch's app-start sync, which has no News/Profile catalog to sync at
  all) — News and Profile too. Reports one `Progress` update per
  completed unit of work (including failed ones, so `completed` always
  reaches `total`), and returns whether every instance synced cleanly.
  `notifyOnNewNews` (see the News comments feature in
  [`IMPLEMENTED_FEATURES.md`](IMPLEMENTED_FEATURES.md) for
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
  mechanism (see [`ENTITLEMENTS.md`](ENTITLEMENTS.md)). **Not verified end-to-end this
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
[`IMPLEMENTED_FEATURES.md`](IMPLEMENTED_FEATURES.md) for the "Update API
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
[`IMPLEMENTED_FEATURES.md`](IMPLEMENTED_FEATURES.md).** Every one of
these `print` call sites (and every other `print` in the app-target/Kit
source, outside `Generated/`) now routes through `DebugLog.log(...)`
instead.


An early (2026-09-05) investigation of a real-server bug (Shifts/Profile
showed empty with no error) concluded the server didn't support the
`self` user-reference alias — see [`HISTORY.md`](HISTORY.md) for that
original diagnosis. ~~**Fix: `Instance.userID: Int?`**, an optional
numeric fallback (nil = use `self`, the default/common case).~~ **This
diagnosis was itself wrong — see the 2026-09-17 root-cause entry
below.** The `userID`
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


**Client-side "does `self` actually work here" check, added the same day**
so the manual "User ID" fallback field only appears when it's actually
needed, instead of being a permanently-visible workaround for a bug that
may no longer exist on a given server:
- `Instance.selfReferenceWorks: Bool = true` (new field, CloudKit-synced
  like the rest of `Instance`) — sync between iOS/Watch means a check
  performed on one device is picked up on the other automatically.
- `APIClient.selfUserReferenceWorks(_:)` probes `GET /users/self/worklogs`
  specifically (not `/users/self`) — deliberately picking the one endpoint
  that's actually shown to be broken on unpatched servers (see above); the
  other three `self`-capable endpoints never distinguish an old server from
  a fixed one. A `404` there means "self broken" regardless of whether the
  user has any worklogs at all (a genuine empty list is a `200`); any other
  outcome (success, or an unrelated error) is treated as "works", so a
  single transient network hiccup during the probe can't wrongly reveal the
  fallback field. The pure interpretation logic is split into
  `APIClient.selfWorks(afterProbeError:)` specifically so it's unit-testable
  without a mock HTTP server (there isn't one in this project — the
  `.notFound` path can't be exercised end-to-end offline, only this pure
  mapping can).
- `InstanceSetupService.createInstance`/`updateInstance` run this probe
  right after the existing `/info` connection test and store the result on
  `Instance` — always testing the literal `self` value, independent of
  whatever `userID` is currently configured, so a server that's since been
  fixed is detected even for an instance that already has a manual
  override set.
- **iOS/Watch Setup forms** (`InstanceSetupView`/`InstanceSetupViewModel`,
  `WatchSetupView`/`WatchSetupViewModel`): Save no longer happens directly
  off the form. A new **"Test Connection"** button (separate from Save)
  runs the `/info` + self-probe checks without creating or saving anything;
  `canSubmit`/Save stays disabled until a test has succeeded
  (`connectionTested`). The manual User ID field is hidden entirely until
  that test determines it's actually needed
  (`connectionTested && !selfReferenceWorks`); editing `baseURL`/`apiKey`
  afterward invalidates the test (`didSet` resets `connectionTested`),
  forcing a fresh Test before Save re-enables. If a test finds `self` does
  work, any previously typed User ID is cleared so it can't be silently
  saved as a stale, unnecessary override.
- **iOS/Watch Settings' "Edit Instance" dialogs** (`EditInstanceViewModel`/
  `WatchEditInstanceViewModel`): same "Test Connection" button added, but
  unlike Setup it does **not** gate Save — an existing instance already has
  a last-known-good `selfReferenceWorks` value (from creation or the
  previous save), and `save()`/`updateInstance` already silently re-probes
  on every save regardless (unchanged behavior from before this feature).
  The view model's `connectionTested` here purely drives the Test button's
  own display (progress/checkmark/label, reset on edit); `selfReferenceWorks`
  is initialized from `instance.selfReferenceWorks` and only updates when
  Test is explicitly pressed. The User ID field is shown whenever the
  latest known result says it's needed, **or** a value is already
  configured — so an active override is never silently hidden out from
  under the user just because a fresh check hasn't been run yet.

  **Deleting a now-unnecessary `userID` happens at Save, not at Test
  Connection** (clarified 2026-09-21, at the user's explicit correction —
  an earlier version of this persisted the deletion immediately when
  Test Connection determined `self` works, which is wrong: Verify should
  only preview, Save should be what commits). `testConnection(for:)`
  only clears the *form field* (`userIDText = ""`, which also hides the
  Section) when it finds `self` works — it never touches `instance`
  itself or calls `modelContext.save()`. The actual deletion happens
  inside `InstanceSetupService.updateInstance`: whenever the freshly
  re-probed `selfReferenceWorks` is `true`, it stores `nil` instead of
  whatever `userID` the caller passed in — so a stale value gets cleared
  the moment Save is pressed, *even if the user never pressed Test
  Connection first* (Save always re-probes internally regardless, same
  as before this feature). Only `updateInstance` (Edit) enforces this;
  `createInstance` (Setup) stores whatever `userID` it's given as-is,
  since Setup's own mandatory Test-before-Save gating means it never
  gets a non-nil `userID` once `self` is known to work in the first
  place — there's no equivalent "stale leftover value" case there.
- Tests: `EngelsystemClientKitTests` covers `selfWorks(afterProbeError:)`'s
  interpretation logic (`.notFound` → false, everything else → true) and
  that `selfUserReferenceWorks` short-circuits to `true` for the demo
  credential; `EngelsystemClientTests` adds
  `EditInstanceViewModelSelfCheckTests`/`InstanceSetupViewModelSelfCheckTests`
  covering the gating/invalidation/field-clearing behavior above (all
  against the demo credential, since there's no mock server to exercise a
  real `.notFound` end-to-end). `testDemoModeNavigationFlow` (which edits
  and saves an instance via the Settings dialog, without ever pressing
  "Test Connection" first) re-verified passing unchanged even after Save
  became gated on `connectionTested` (see below) — it never changes
  `baseURL`/`apiKey`, only `name`, so `connectionTested` (which starts
  `true`) is never invalidated in that flow.

**Edit Instance's Save gated on Test Connection too, and the button moved
to the bottom of the form (2026-09-21, at the user's explicit request)**:
originally Edit's Save deliberately stayed enabled regardless of
`connectionTested`, reasoning that `save()` already silently re-verifies
internally on every call anyway (see above) — but that meant Save stayed
clickable immediately after editing the server URL or API key, before
anything had actually confirmed the new value works. Fixed to match
Setup's behavior: `EditInstanceViewModel`/`WatchEditInstanceViewModel
.canSubmit` now also requires `connectionTested`, so editing `baseURL`/
`apiKey` (which already reset `connectionTested` to `false` via their
`didSet`) disables Save until "Test Connection" succeeds again. The User
ID field's visibility is unaffected — still driven by `selfReferenceWorks`
alone, so it keeps showing/hiding from the last-known result even
mid-edit, before a fresh test has been run. The "Test Connection" section
itself moved to the very bottom of both `EditInstanceView`/
`WatchEditInstanceView`'s form (still above the toolbar's Save on iOS,
directly above the in-form Save section on Watch), after the User ID and
error sections — previously it sat right after the API Key field, above
User ID.

## CloudKit sync for Instance metadata

Implemented once the user joined the paid Apple Developer Program (see
[`ENTITLEMENTS.md`](ENTITLEMENTS.md) for the entitlements themselves).
Per this file's binding "Sync strategy" above: only `Instance` (name,
server URL, `userID`) syncs between iOS and Watch — the `Cached*` models
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
  [`HISTORY.md`](HISTORY.md) for the full investigation. `forceLocalOnly`/
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
  [`HISTORY.md`](HISTORY.md) for the incident that surfaced this.
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
  while building the fix — see [`HISTORY.md`](HISTORY.md)). This
  project's `MemberImportVisibility` upcoming-feature flag also means
  `.receive(on:)` needs an explicit `import Combine` in both files
  (normally implicit via SwiftUI).
