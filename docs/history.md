# History

Part of the Engelsystem Client documentation set — see [`CLAUDE.md`](../CLAUDE.md) for the entry point and the rest of the doc map.

This file collects investigations, bugs, and decisions that are no longer load-bearing for understanding today's code — the current design lives in [`architecture.md`](architecture.md), [`app-store.md`](app-store.md), and [`features.md`](features.md), each of which link back here where the story matters. Kept mostly for the lessons learned (about this Mac's tooling, about which Apple APIs to trust, about workflow mistakes worth not repeating) rather than as a day-to-day reference.

## API / data-flow bugs

**Resolved bug: on a real (non-demo) server, Shifts and Profile showed
empty with no error, while News loaded fine.** Reported and root-caused
2026-09-05, confirmed via the user's Xcode console with debug logging
(the predecessor to today's `DebugLog`, see
[`features.md`](features.md)): `/users/self/shifts`
and `/users/self` both returned a
genuine 404 on this server (`[APIClient] 404 for a list endpoint —
treating as empty list` fired, then `[ProfileViewModel] refresh failed:
notFound`) — so `self` really isn't supported as the `{id}` path
parameter on at least this Engelsystem deployment, despite `openapi.yml`
documenting it as valid (the *spec* allowing a value doesn't guarantee
every real server implements it — this server apparently predates that
alias, or never implemented it). Confirmed present *before* the
`CancellationError` fix (see [`architecture.md`](architecture.md)) too,
so it was never a side effect of
that fix — it's App/server API-compatibility, not a client concurrency
bug.


**Real server-side `self` bug found and fixed upstream, 2026-09-21**: after the
client-side path-parameter bug (see [`architecture.md`](architecture.md), "Actually
root-caused, 2026-09-17") was fixed, the user found and fixed a
*genuine* server-side bug in their own Engelsystem test deployment (upstream
`engelsystem/engelsystem`, `src/Controllers/Api/UsersController.php`,
`worklogs()`): unlike the sibling `user()`/`entriesByUser()`/`ofUser()`
methods, `worklogs()` didn't use the shared `UsesAuth::getUser()` helper —
it cast the path parameter straight to `(int)`, so `self` became `0` and
`User::findOrFail(0)` threw, even though the router's own regex
(`{user_id:(?:\d+|self)}`) explicitly allows `self` there. Confirmed via
this session fetching the live `main` branch of the upstream repo directly
(not guessed) — `/users/{id}`, `/shifts`, and `/angeltypes` never had this
bug, only `/worklogs`. A handoff briefing for an agent to apply this fix
against a fresh checkout of the server repo was written to
`engelsystem-server-api-fixes.md` at the project root (this client repo)
before the user applied the fix directly to their own test server.


## CloudKit sync for Instance metadata

- **Capability registration confirmed done, 2026-09-16** (see
  [`app-store.md`](app-store.md) for how this was verified from the
  CLI side via the regenerated provisioning profiles) — the CloudKit
  container and Keychain Sharing group are real and provisioned for both
  targets now.

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

  This does **not** implicate the CloudKit sync work described in
  [`architecture.md`](architecture.md): the iOS UI
  test (`testDemoModeNavigationFlow`) passed fine multiple times in the
  same sessions, the Kit unit tests (including
  `modelContainerFactorySupportsBothInstanceAndLocalModels`) all pass, and
  both platforms' plain (non-test) builds are fine. This caveat is
  entirely about the watchOS Simulator's performance on this machine
  under Xcode 27.0, not about the app or the CloudKit container/Keychain
  Sharing registration (which is separately confirmed working, see
  [`app-store.md`](app-store.md)).

- **Root-caused and fixed, 2026-09-16: a manually re-entered
  `Instance.userID` (or any other Settings edit) could silently revert
  after rebuilding the app from Xcode.** Reported by the user against a
  real (non-demo) server: they set the `userID` fallback (see the
  "Resolved bug"/"Fix" entries elsewhere in this file and in
  [`architecture.md`](architecture.md)) via "Edit Name / Server", rebuilt
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
  .ubiquityIdentityToken != nil` — this is exactly what the project's
  "Sync strategy" (now in [`architecture.md`](architecture.md))
  originally specified as the binding startup check
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
  `CloudSyncStatus` footer on both Settings screens (see
  [`features.md`](features.md)) exists
  specifically so this stays visible going forward without needing a
  console attached.

## Entitlements & signing

**Investigated, 2026-09-18: `Error Domain=BGSystemTaskSchedulerErrorDomain
Code=3` around `com.apple.coredata.cloudkit.activity.export.<uuid>` on
the real Watch — benign, no fix needed; a first attempt at "fixing" it
was based on a misread and was reverted the same day.** Full log line:
`updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.
<uuid> / Error updating background task request: Error
Domain=BGSystemTaskSchedulerErrorDomain Code=3 "(null)"`, immediately
followed by `updateTaskRequest called for a pre-running task ...` /
`... called for an already running/updated task ...` for the same
identifier.

  **First attempt (wrong, reverted): added `BGTaskSchedulerPermittedIdentifiers`
  (`com.apple.coredata.cloudkit.activity.export`/`.import`) to both
  Info.plist fragments**, reasoning that `Code=3` matches the
  *public*, documented `BGTaskScheduler.Error.Code.notPermitted` (the
  identifier missing from that Info.plist key). This missed that the
  error domain in the actual log is `BGSystemTaskSchedulerErrorDomain`,
  not `BGTaskSchedulerErrorDomain` — a different, private/internal
  system domain (`com.apple.BackgroundSystemTasks`/`BGSTFramework`,
  visible in the fuller log capture) that `NSPersistentCloudKitContainer`
  talks to directly for its own housekeeping, not the public API surface
  `BGTaskSchedulerPermittedIdentifiers` governs. Confirmed wrong hands-on,
  not just in theory: rebuilt and reinstalled on the real Watch with the
  key in place, and the exact same error recurred with the *same* task
  UUID (`05C75F0C-F61C-4388-99D6-CEF50391B051`) — proof the change had
  zero effect. Reverted both Info.plist fragments back to
  `UIBackgroundModes` only.

  **Actual finding, via web research** (Apple Developer Forums threads on
  `NSCloudKitMirroringExportRequest`/`BGSystemTaskScheduler`): this
  specific error is `NSPersistentCloudKitContainer` trying to schedule a
  new background export activity while a previous one for the same
  identifier is still pending or in progress — the system-level scheduler
  rejects the redundant *new* request with `Code=3`, but this is expected
  and self-healing, not a failure of sync itself: the immediately-following
  "pre-running task"/"already running/updated task" log lines are the
  system confirming it's just continuing to use the existing scheduled
  activity instead. `NSPersistentCloudKitContainer` re-schedules on its
  own the next time there's actually new data to export, with no
  app-code involvement either way (nothing here calls `BGTaskScheduler`
  directly, still true per [`app-store.md`](app-store.md)). Consistent
  with everything else observed this session: real shift/`Instance` sync
  keeps working (confirmed both by explicit user confirmation and by
  `[NextShiftViewModel] synced N shift(s)` in the same log captures this
  error appears in) — this is console noise from CloudKit's internal
  scheduling machinery, not a symptom of anything broken in this app.
  **No Info.plist change needed for this; not planning to revisit unless
  it's ever shown to correlate with an actual sync failure.**

  Also present in the same real-Watch log, not yet investigated (lower
  priority, since it hasn't been shown to affect anything observable):
  `Couldn't read values in CFPrefsPlistSource<...> (Domain:
  group.net.cuccato.engelsystem.de.shared, ...): Using kCFPreferencesAnyUser
  with a container is only allowed for System Containers, detaching from
  cfprefsd` — App Group UserDefaults access, likely from
  `NextShiftSnapshotStore`.


**2026-09-16: iCloud/CloudKit + Keychain Sharing entitlements added to both
targets**, now that the user has joined the paid Apple Developer Program —
this was the one remaining blocker.
`EngelsystemClient/EngelsystemClient.entitlements`
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


## Tooling & environment quirks (this machine)

**Real Xcode/Simulator DerivedData corruption hit and root-caused while
verifying this, worth remembering for this machine specifically**: a
newly added Swift Testing test method silently didn't run at all
(`xcodebuild test` reported one fewer test than actually exists in the
source, with no error) even after deleting the compiled `.xctest`
bundle and re-running — only fully deleting that target's
`Intermediates.noindex/.../EngelsystemClientTests.build` folder made it
show up at all, and even then it then reported a *spurious failure*
that didn't reproduce when re-verified against a completely separate,
fresh `-derivedDataPath`. Confirmed via an isolated `swift
<script>.swift` snippet (no Xcode/Simulator involved, matching the
`@Observable`/`didSet` pattern used here exactly) that the actual
Swift/Observation semantics were correct the whole time — the failure
was 100% a stale/corrupted primary DerivedData artifact for this
project (`EngelsystemClient-fdkasijsafofufdlimelqdnwevqx`), not a code
bug. Deleted that DerivedData folder entirely and rebuilt clean to
resolve it. **If a test result here ever looks inexplicable given the
actual code** (especially "a test I just added doesn't appear to have
run" or "this passes in isolation but fails in the full suite" with no
sensible cause), suspect DerivedData corruption before spending time
debugging the app code — verify with a quick standalone `swift
<file>.swift` reproduction of just the suspect logic (fast, bypasses
the simulator entirely) and/or a one-off `-derivedDataPath` pointed at
a fresh temp directory before concluding it's a real bug.

## 2026-10-09: Pre-public security audit

Ahead of switching the GitHub repo from private to public (part of
TestFlight release planning, see
[`roadmap.md`](roadmap.md#testflight-release-started-2026-10-09)),
user-requested audit of the entire repository **and its full commit
history** (83 commits at the time) for anything that shouldn't go
public — API keys, private keys/certificates, personal data, internal
infrastructure details.

**Method**: `git log --all --name-only` for suspicious filenames
(`.pem`/`.p12`/`.mobileprovision`/`.env`/etc. — none ever committed);
`git log --all -p` grepped for private-key PEM headers (none),
generic `key=`/`secret=`/`token=`/`password=` assignment patterns
(every hit was a test fixture like `"demo-key"`/`"some-key"`, never a
real credential), IP addresses, and email addresses in file *content*
(as opposed to commit metadata).

**Findings**:
- **No real secrets, credentials, private keys, or certificates have
  ever been committed.** Every "secret-shaped" string found in history
  is a test fixture (`DemoData`, unit test literals like
  `"old-demo-key"`/`"replacement-key"`) or a placeholder domain
  (`*.example.com`, `*.demo.engelsystem.local`).
- **A private LAN IP** (`a private LAN host`, a dev test server mentioned
  in the News-comments feature's API provenance writeup) was present in
  `CLAUDE.md`. Low risk (not internet-routable) but redacted immediately
  to a generic description — see `CLAUDE.md`'s `/news/{id}` entry.
- **An early commit hardcoded a local absolute path**
  (`/Users/cookie/Documents/Projekte/...`) inside what later became
  `Scripts/generate-api.sh`. The *current* script already resolves its
  own location at runtime (`SCRIPT_DIR="$(cd "$(dirname
  "${BASH_SOURCE[0]}")" && pwd)"`) — not a live bug — but the old value
  would otherwise have remained visible in history forever. Reveals a
  local macOS username and folder name, not a credential.
  **User-approved fix, same day**: scrubbed via
  `git filter-repo --replace-text` (installed via `brew install
  git-filter-repo` for this). Before rewriting: stashed the in-flight
  docs changes (`git stash push -u`) and took a full backup
  (`git bundle create ... --all`) so the rewrite had a rollback path.
  The rewrite itself (a plain `--replace-text` rule swapping the real
  path for a placeholder) changed all 83 commit hashes — same scope as
  the 2026-09 German-content rewrite. `git filter-repo` also removes
  the `origin` remote as a safety measure; re-added it afterward.
  Verified: `git log --all -p | grep /Users/cookie` found zero real
  occurrences afterward (the only hit left was this very paragraph's
  own description of the issue, in an unrelated stashed doc change,
  not a leak), and `EngelsystemClientKit` still built clean.
- **The git author email** (`cookie@cuccato.net`, used on all 83
  commits) will be publicly visible once the repo is public — standard
  GitHub behavior, not a bug; noted for the user's awareness since it
  matches their own domain and was presumably intentional, not flagged
  for any fix.
- **No `.DS_Store`/`xcuserdata`/`.xcuserstate` ever committed** — the
  `.gitignore` has correctly excluded these from the start.
- Apple Developer Team ID (`8A5FNU94BM`) appears in `project.pbxproj` —
  not a secret by itself (can't be used without the matching private
  signing key/certificate, neither of which is in this repo); commonly
  left public in open-source Xcode projects. No action taken.
- No LICENSE file existed at audit time. **User-approved fix, same
  day**: GPL-2.0 (the user's explicit choice, not suggested by Claude —
  see `roadmap.md`'s "Resolved decisions"), canonical text fetched
  verbatim via `curl` from `gnu.org` rather than reconstructed from
  memory, inserted into the very first commit (`git rebase --root`,
  combined with the history-scrub rewrite above in one pass) so the
  license covers the whole project history, not just new commits.

**Outcome**: cleared for going public from a secrets-leak perspective.
The two low-risk informational items (old local path in history; no
LICENSE) were both resolved the same day with explicit user approval —
see `roadmap.md`'s "Resolved decisions" for the final record.

