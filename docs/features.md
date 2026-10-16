# Implemented Features

Part of the Engelsystem Client documentation set — see [`CLAUDE.md`](../CLAUDE.md) for the entry point and the rest of the doc map.

Kept up to date as features land, so a fresh session can see what already
exists without reading the whole diff history.

### EngelsystemClientKit (shared package)

- **Persistence (SwiftData)**: `Instance`, `CachedShift`, `CachedNews`,
  `CachedUser`, `CachedWorklog`, `CachedAngelTypeMembership` models exist.
  `Instance` is **CloudKit-backed** (`ModelContainerFactory`, see "CloudKit
  sync for Instance metadata" in [`architecture.md`](architecture.md));
  the five `Cached*` models are
  local-only and have **no relationship to `Instance`** any more (removed
  when the CloudKit split landed, since SwiftData relationships can't
  cross `ModelConfiguration`s) — they're matched to their instance purely
  by the plain `instanceID: UUID` field every one of them already carries.
- **Generated OpenAPI client** (`Generated/`): DTOs and API classes for
  every endpoint in `openapi.yml` (all GET except `/messages*`, see
  [`CLAUDE.md`](../CLAUDE.md)'s API section), produced by
  `Scripts/generate-api.sh`. Regenerate with that script whenever
  `openapi.yml` changes — never hand-edit `Generated/`.
- **APIClient**: async/await wrapper over the generated client —
  `fetchInfo`, `fetchNews`, `fetchAngelTypes`, `fetchLocations`,
  `fetchLocation(id:_:)`, `fetchShiftTypes`, `fetchShifts(for:)`,
  `fetchWorklogs(for:)`, `fetchOwnProfile`, `fetchUsers`, plus the
  Messages methods (`fetchConversations`, `fetchConversation`,
  `sendMessage`, `deleteMessage`, `setMessageRead`,
  `messagesSupported` — see "Messages" below). Internally serializes
  requests (`RequestGate`) so concurrent calls to different instances
  can't clobber the generated client's global base URL/headers. Maps
  404 to an empty list for list endpoints; everything else surfaces as
  `APIError` (unauthorized/forbidden/notFound/server/invalidBaseURL/
  network/decoding) — Messages' capability probe is the one exception,
  going through the lower-level `withLockedCredential` instead so it
  can inspect the raw error body (see "Messages" below).
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
  action (see the iOS app's Settings feature further below in this
  document).
- **`DebugLog`** (`Services/DebugLog.swift`, 2026-09-23, user-requested):
  in-app, on-device debug log — replaces every `print(...)` call in the
  app-target/Kit source (outside `Generated/`) with `DebugLog.log(_:level:)`,
  since a bare `print` is useless once the app isn't tethered to Xcode/lldb
  (e.g. a real background sync on a device in the field). `DebugLog.log`
  itself **always still calls `print`** internally, unconditionally — so
  the existing Xcode-console workflow is completely unaffected — and
  *additionally* stores the entry (in memory + on disk) only when the
  user has turned logging on in Settings. This was an explicit reversal
  mid-planning: the original proposal was "keep `print`, additionally
  call the new log at each site"; the user corrected it to "replace the
  `print`, the new log itself prints" instead, so there's a single call
  site per log point rather than two.
  - `DebugLogEntry` (`id`, `timestamp`, `level: .info/.warning/.error`,
    `message`) has two string representations: `displayText` (human
    fixed-format, `"yyyy-MM-dd HH:mm:ss [LEVEL] message"`, used both by
    the viewer and for the clipboard export) and `persistedLine`
    (tab-separated, `"<epoch>\t<level>\t<escaped message>"`, `\n` within
    a message escaped to `\\n`) — deliberately two different formats, so
    a `DateFormatter`/`[LEVEL]`-bracket round trip parsing `displayText`
    back can't ever be a source of bugs; only `persistedLine` is ever
    parsed back (`DebugLogEntry.parse(persistedLine:)`, `nil` for an
    unparsable line — e.g. a partially-written last line after the app
    was killed mid-write — dropped silently rather than crashing).
  - **Persisted to disk, not just kept in memory** — the user explicitly
    reversed an earlier decision here ("Ich habe mich umentschieden, das
    Log soll doch persistent werden, damit auch Hintergrundsyncs
    protokolliert werden können"): a `BGAppRefreshTask` (see
    `BackgroundSyncScheduler` below) can be killed by the OS the moment
    its time budget runs out, so anything held only in memory could be
    lost before ever being seen. Stored as a plain text file in the
    Caches directory (`debug-log.txt`, excluded from backups —
    appropriate for ephemeral diagnostics), written to on **every**
    `log(...)` call, not batched. Appending is a cheap
    `FileHandle(forWritingTo:)` + `seekToEndOfFile()` + `write(_:)`
    (falling back to a plain `Data.write(to:)` if the file doesn't exist
    yet) — the file is only fully rewritten (from the trimmed in-memory
    buffer) on the rarer occasions the entry count actually exceeds the
    configured max, not on every call.
  - **Max size is user-configurable** (`DebugLog.availableMaxEntryCounts`
    = 100/500/1000/5000, `@AppStorage` key `maxEntriesUserDefaultsKey`,
    default `defaultMaxEntries` = 500) — read fresh via
    `DebugLog.maxEntries(in:)` on every single append, so lowering the
    limit in Settings trims on the very next log call, no separate
    "re-apply" step needed.
  - **`nonisolated static func log(_:level:)` on an otherwise
    `@MainActor @Observable` singleton** (`DebugLog.shared`) — callable
    from anywhere, sync or async, on any actor/thread, with no `await`,
    matching how `print` could always be called at every site this
    replaces. Internally hops via a fire-and-forget
    `Task { @MainActor in shared.append(...) }` to safely mutate the
    actor-isolated `entries`/file state. `isEnabled(in:)` is checked
    *before* spinning up that `Task` at all, so a disabled log doesn't
    pay even that small cost.
  - **Testability**: `fileURL`, `append(_:)`, and `loadFromDisk()` are
    relaxed from `private` to internal (module-visible, not `public`) —
    purely so `EngelsystemClientKitTests` (`@testable import`) can call
    them directly and `await` their effects deterministically, instead
    of racing `log(...)`'s fire-and-forget `Task` hop. `DebugLogTests`
    (9 tests, `@Suite(.serialized)` since they all share the one real
    singleton and on-disk file) cover: persisted-line round-trip
    (including embedded newlines), unparsable-line handling, `isEnabled`/
    `maxEntries` defaults vs. explicit values, append-trims-to-configured-
    max (both in-memory and on-disk), `loadFromDisk()` correctly re-reads
    a manually-seeded file (simulating a relaunch), `clear()`, and
    `exportText` ordering.
  - **No secrets ever logged** — no API keys, tokens, or other sensitive
    values appear at any of the logging points added for this feature
    (reaffirmed explicitly in `SettingsView`'s Diagnostics footer copy).
  - **iOS-only** — the user chose not to add Watch parity for this
    feature (no Settings UI for it there); `DebugLog.log(...)` on the
    Watch is effectively a print-only no-op, since `isEnabled()` there
    can never become `true`. `DebugLog` itself lives in
    `EngelsystemClientKit` regardless (both targets' code paths call
    into it), it's only the toggle/viewer UI that's iOS-only.
  - **Settings integration** (`SettingsView`, new "Diagnostics" section,
    between "Sync" and the version/`CloudSyncStatus` footer): a
    "Debug Logging" `Toggle` (`@AppStorage(DebugLog.isEnabledUserDefaultsKey)`),
    a "Max Log Entries" `Picker` over `availableMaxEntryCounts`
    (`@AppStorage(DebugLog.maxEntriesUserDefaultsKey)`), and a
    `NavigationLink("View Debug Log")` to `DebugLogView`.
  - **`DebugLogView`** (`Features/Debug/DebugLogView.swift`): every entry
    rendered as one monospaced line, color-coded by level (info =
    secondary, warning = orange, error = red), `.textSelection(.enabled)`
    for selecting/copying an individual line or range. Toolbar: "Copy to
    Clipboard" (`UIPasteboard.general.string = debugLog.exportText`) and
    a destructive "Clear" behind a `.confirmationDialog`. Empty state via
    `ContentUnavailableView`.
  - **Logging points added as part of this feature** (beyond the
    migrated `print`s): `AppSyncCoordinator` — previously the single
    biggest gap, since it's the *only* path for app-start sync,
    background sync, and the main-page pull-to-refresh, yet had zero
    logging before this — now logs a start line, per-instance credential
    failures, per-domain (Shifts/News/Profile) success-with-counts and
    failures, and a final "finished (allSucceeded: …)" summary.
    `BackgroundSyncScheduler.handle(_:modelContainer:)` logs at task
    start and end (including the expiration-handler path), and
    `scheduleNext()` logs whether `BGTaskScheduler.shared.submit`
    actually succeeded (previously a silent `try?`) or why it didn't
    schedule at all (manual interval). `NotificationScheduler
    .requestAuthorizationIfNeeded()` logs the prompt outcome and the
    `.denied` case. `NewsNotifier.notify(newItems:instanceName:)` logs
    "skipped — disabled", "posted", or "failed to post". `APIClient`'s
    `withCredential`/`withCredentialList` helpers log every request's
    outcome by path string — success with
    item count for list endpoints, `.notFound` on a list endpoint as
    "treating as empty list" (harmless overlap: a list-endpoint 404
    produces two log lines, the generic failure and this one — accepted
    as a trade-off rather than adding an unverified generic-existential
    type check to suppress it), a generic failure at `.error`, and an
    invalid base URL at `.error`. `ModelContainerFactory` and
    `ICloudAvailability.logCloudKitAccountStatus` also migrated their
    pre-existing `print`s.
  - **Fixed, 2026-09-23, same day, user-reported from the log viewer
    itself**: the four `/users/{id}/...` endpoints
    (`fetchShifts`/`fetchWorklogs`/`fetchOwnAngelTypes`/`fetchOwnProfile`)
    originally passed a literal, unresolved endpoint-template string
    (e.g. `"GET /users/{id}/shifts"`) as the log label — a deliberate
    simplification at the time, to avoid re-deriving the resolved path
    parameter just for the log message. The user noticed `DebugLogView`
    always showed the literal `{id}` text and asked whether this meant
    the app wasn't actually resolving `self`/the numeric ID in the real
    request. **It was — this was purely a log-cosmetics gap, not a
    networking bug**: the real HTTP request, built separately via the
    generated `*API.usersId...Get(id: user.parameter)` calls, has
    correctly resolved `user.parameter` to `"self"` or the real numeric
    ID since the 2026-09-17 `CustomStringConvertible` fix documented
    above (verified by that fix's own regression test, which asserts
    the actual request URL). Fixed anyway, since a log message that
    looks like the ID was never substituted is a reasonable thing to be
    suspicious of: all four call sites now build the log's path string
    with `\(user.parameter)` interpolated in (which dispatches to that
    same `CustomStringConvertible` conformance, so it prints `"self"`/
    the numeric ID, not `"{id}"`) instead of the static template.
    Verified via the full Kit test suite (67/67) after the change.
- **`MetricKitReporter`** (`Services/MetricKitReporter.swift`,
  2026-10-09, user-requested crash/diagnostics reporting via
  Apple's MetricKit — see `docs/roadmap.md`'s "Resolved decisions" for
  the data-handling model that was decided first): subscribes to
  `MXMetricManager` for crash/hang/CPU-exception/disk-write-exception
  diagnostics and performance metrics. Consistent with this app's
  "no analytics, no third-party tracking" stance — everything MetricKit
  delivers stays on-device; nothing is transmitted anywhere
  automatically. **Decided model: local + manual export** — a short
  human-readable summary of each delivery goes through the existing
  `DebugLog` (e.g. `"MetricKitReporter: received 1 crash diagnostic(s)"`),
  and the full raw payload (via each payload's own `jsonRepresentation()`)
  is additionally persisted as JSON Lines to a Caches-directory file, so
  a tester can explicitly export/share it (e.g. to attach to a bug
  report email) rather than it only being visible inside the app.
  - **Retention (2026-10-12)**: each stored line is
    `{"receivedAt": <ISO 8601>, "payload": <MetricKit JSON>}`. Entries
    older than 30 days are dropped (at launch via `prune()` and on every
    delivery), then the oldest are dropped until the file is ≤ 1 MB; the
    newest entry is always kept. Lines without a readable timestamp
    (older builds) are dropped. Pure logic in
    `MetricKitReporter.retained(_:now:maxAge:maxBytes:)`, unit-tested.
  - **Hint before sharing (2026-10-12)**: Settings → Diagnostics →
    "Export Diagnostics" opens `ExportDiagnosticsView` (size, what the
    reports contain, "nothing is sent on its own", retention) with the
    `ShareLink` inside it — `ShareLink` can't be triggered
    programmatically, so it moved into the sheet. The row is always
    tappable; with nothing delivered yet the sheet explains when iOS
    delivers reports (about daily; crashes at the next launch) instead of
    a silently greyed-out button. MetricKit delivers nothing in the
    Simulator; on a device use Xcode's Debug → Simulate MetricKit Payloads.
  - **iOS-only** (`#if os(iOS)`), like Locations/Messages — no
    diagnostics UI on the Watch. The `MXMetricManagerSubscriber`
    conformance itself is also behind `canImport(MetricKit)`, which is
    `false` for this package's `swift test` platform (plain macOS —
    MetricKit isn't available there at all); the rest of the type
    (persist/export/clear, the pure summarizing logic) still compiles
    and is testable there regardless.
  - **Real-platform API-shape bug caught only by the full Xcode build,
    not `swift test`**: `MXMetricPayload`/`MXDiagnosticPayload
    .jsonRepresentation()` return a non-optional `Data` on the real iOS
    SDK — the first version wrote `if let data = payload
    .jsonRepresentation()`, assuming `Data?`, which only failed to
    compile once built for a real iOS destination (the macOS-only Kit
    build had compiled the whole `MXMetricManagerSubscriber` extension
    out entirely via `canImport(MetricKit)`, so `swift test` gave false
    confidence). Fixed by dropping the `if let` around the `Data` itself,
    keeping it only around the `String(data:encoding:)` conversion.
    Reinforces this project's existing "verify with a full Xcode build,
    not just `swift test`, for anything platform-specific" practice.
  - Registered once at app launch (`EngelsystemClientApp.init()`, via
    `MetricKitReporter.shared.activate()`), same pattern as
    `WatchConnectivityBridge.activate()` right above it.
  - **Settings integration**: a new "Export Diagnostics" row in the
    existing "Diagnostics" section (next to "View Debug Log") —
    a `ShareLink` when `MetricKitReporter.shared.exportText()` has
    something to share, otherwise a disabled-looking label (no payloads
    received yet). The footer text was extended to explain what this
    shares and that nothing is sent anywhere automatically.
  - **Tests** (`MetricKitReporterTests`, `@Suite(.serialized)` since
    they share the one real singleton and on-disk file, same reasoning
    as `DebugLogTests`): persist/export/clear round-trip, the pure
    `summarize(crashCount:hangCount:cpuExceptionCount:
    diskWriteExceptionCount:)` logic (every-kind-present, all-zero, and
    exactly-one-kind cases), and that `activate()` doesn't crash on a
    platform without MetricKit (the `#else` no-op branch — the real
    iOS subscription path can't be verified outside a real
    device/simulator run, since `MXDiagnosticPayload` has no public
    initializer for a test to construct one).

### iOS/iPadOS app

- **Launch screen** (`Features/Launch/LaunchScreenView`, wired into
  `ContentView`, 2026-09-17): shows the app icon, name, and
  `AppVersionInfo.displayString` (version/build/git hash — see
  [`app-store.md`](app-store.md)) for a fixed `ContentView.launchScreenDuration`
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
  selected. ~~The sidebar's own navigation title used to reflect the
  count ("No Active Instance" / the one instance's name / "N Active
  Instances").~~ **Changed 2026-09-22, at the user's request: no more
  instance-count text in the title.** `navigationTitle` now shows the
  one active instance's name when there's exactly one, or a static
  "Engelsystem" otherwise (zero or several). `navigationTitle`'s logic
  is a `static func navigationTitle(forActiveInstances:)`, not a
  `private` computed property, specifically so it's unit-testable
  (`EngelsystemClientTests.MainViewNavigationTitleTests`, covering all
  three cases) without needing to construct a full `MainView`/drive its
  `body` — initially missed when this feature landed, added once the
  user asked why. ~~Defaults to Shifts on launch.~~ **Changed
  2026-09-22, at the user's request: resumes on whichever data section
  (Shifts/News/Profile) was last selected**, instead of always starting
  on Shifts. **Changed again 2026-10-12, at the user's request: the
  default is the main page (the sidebar list), not Shifts** — "nothing
  stored yet"/an unrecognized value now yields *no* selection
  (`initialSelection` returns `Section?`; on iPhone the sidebar list is
  shown, in wide layouts the detail column shows a "Select a Section"
  placeholder), and with **no active instance the app always lands on
  the sidebar**, whatever was stored (`hasActiveInstances` parameter,
  evaluated at launch only — not when the last instance is deactivated
  while sitting in Settings). `.settings` itself is deliberately
  never remembered as the resume target, even though it's a real,
  storable `Section` raw value — landing back in Settings on next launch
  just because that's where the 401-triggered `goToSettings()` happened
  to leave things would be surprising, not a deliberate "I was browsing
  Settings" choice. Persisted via `@AppStorage` (`lastSelectedSectionRaw`,
  key `"mainViewLastSelectedSection"`), but the *initial* `@State
  selection` value can't be seeded from another property's `@AppStorage`
  default directly, so `init` reads `UserDefaults.standard` by hand
  instead. The actual decision logic — what to resume on given a raw
  stored value, and whether a given section should be persisted at all —
  is two `static` pure functions (`initialSelection(fromStoredRawValue:hasActiveInstances:)`
  /`shouldPersistAsLastSelectedSection(_:)`), not inlined into `init`/
  `.onChange`, so it's unit-testable
  (`EngelsystemClientTests.MainViewLastSelectedSectionTests`) without
  touching `UserDefaults` — needed relaxing the file's own `Section` enum
  from `private` to internal (module-visible) first, since a `private`
  type can't appear in a signature `@testable import` can see from
  another file, even though `@testable` otherwise relaxes `internal`.

  **Zero active instances: the sidebar's row content changes, but it
  must stay the same `List(selection:)` — this broke real navigation
  when it didn't, same day, user-reported.** The first version replaced
  the sidebar's entire content with a `ContentUnavailableView` (message
  + "Add Instance" button) whenever there were no active instances,
  instead of the normal `List(Section.sidebarCases, selection:
  $selection)`. Both the button and the toolbar Settings gear icon
  looked like they worked (`selection` visibly changed, `detail:`'s
  `switch` re-rendered to `SettingsView`) but **nothing ever became
  visible** on iPhone/compact width. Root cause: `NavigationSplitView`'s
  automatic column push in response to a `selection` change, when
  collapsed to a single visible column, only fires when the sidebar's
  own top-level content *is* the `List` that binding belongs to —
  swapping the sidebar to a non-`List` view for the empty state left
  nothing for that push mechanism to observe, even though the `selection`
  state itself and the `detail:` view both updated correctly underneath.
  Fixed by keeping `List(selection: $selection)` as the sidebar's
  content in *both* branches, unconditionally — only which rows it
  contains differs: the normal `Section.sidebarCases` rows, or (when
  `activeInstances.isEmpty`) a plain informational row plus an "Add
  Instance" row/button (still routes to Settings via the existing
  `goToSettings()`, since that's also where an existing *inactive*
  instance can be reactivated, not only where a new one can be added).
  Needed `SwiftUI.Section` spelled out explicitly inside that branch —
  the file's own `private enum Section` (the sidebar's feature-selection
  cases) shadows it otherwise, a real compile error caught immediately.
  Verified end-to-end via a new dedicated XCUITest,
  `testAddInstanceButtonAppearsAndNavigatesWhenNoActiveInstance`
  (deactivate the only instance, confirm the empty-state row appears,
  confirm tapping "Add Instance" actually reaches Settings) — this gap
  was called out but left open when the feature first landed; the user
  asked why no test existed, and hitting this exact regression while
  writing that test is what surfaced the real bug in the first place.
  That same new test also hit — and had to work around — the documented
  notification-permission-alert-interception class of flakiness (see
  the watchOS UI Testing section below): it reaches the "Demo Active"
  toggle much sooner after the first Shifts sync than
  `testDemoModeNavigationFlow` does, which made it land squarely in that
  alert's async appearance window on a freshly-erased simulator (a tap
  silently not registering, confirmed hands-on) — same
  `addUIInterruptionMonitor` + no-op-tap-to-flush fix, previously only
  documented for the Watch, turns out to apply on iOS too under the
  right timing.
  **Settings is not a sidebar row**
  (changed 2026-09-17, at the user's request) — it's app configuration
  rather than a data section at the same level as Shifts/News/Profile,
  so it's reached via a gear icon in the sidebar's own toolbar corner
  instead. `Section.settings` still exists internally as a `selection`
  value (`Section.sidebarCases` is the subset — `.shifts`/`.news`/
  `.profile` — actually rendered as rows), so `goToSettings()`'s
  401-triggers-navigation behavior (see "Data/code flow" in
  [`architecture.md`](architecture.md)) keeps
  working unchanged; only the visible row disappeared.
- **Shift details** (`Features/Shifts/ShiftDetailView`, 2026-10-16, ADR 0015): reached from a shift row
  (the location keeps its own link; both navigate by state because two `NavigationLink`s in one `List` row
  fire together). Everything it shows comes from `ShiftDetail` (Kit, tested): shift type name and description,
  the shift's own description, tags, night shift, talk link (http/https only), "sign-up opens" while in the
  future, the team grouped by angel type with "n of m" (`TeamGroup.occupancyText`; overbooked types show
  "n (needs m)"), the own entry highlighted (found via the cached profile's user id) and "did not show up"
  from `freeloaded` (COMPAT(#1723): `freeloaded_by != null`), teams above ten collapse to the own entry.
  The sign-out hint uses `sign_out_until`/`can_sign_out` (COMPAT(#1722/#1723): otherwise the usual
  3 hours before the start, marked as assumed); **Sign out in browser** opens the shift's `url` — the app
  never signs out. Pull to refresh uses `GET /shifts/{id}` (COMPAT(#1724): 404/403 ⇒ cached shift, no
  error). The detail fields are display-only cache fields on `CachedShift` (the team as one encoded field)
  and never count as a change for the Watch. The Watch is unchanged.
- **Several demo instances** (2026-10-16): any `demo://<host>` address is a demo instance and the host picks the data
  (`DemoScenario`): `demo://engelsystem.local` is the classic data, `demo://congress.local` a second event with its own
  info, shifts, locations and news. Two demo instances with the same host count as one server (two accounts) and are
  merged where the real server would be; different hosts are different servers. Any other `demo://` host is a server that
  offers only News (`DemoScenario.offersOnlyNews`): one pinned post names the addresses that work, every other function
  answers like a missing route, so the app hides it (Shifts, Locations, Messages, Profile) without errors.
- **Merged locations and edges** (2026-10-16): in the merged mode the locations of instances on the same server collapse to
  one entry (`CachedLocation.mergedAcrossServers`, like news) with a badge per instance. The colored left edge belongs to an
  entry only when exactly one instance owns it (`InstanceEdge`); shared entries show just the badges. The Profile band no
  longer shows a count.

- **Instance colors and sections** (2026-10-16): every instance has a color (`InstancePalette`, eight system colors).
  "Auto" (default) spreads the colors evenly over the instances in the order they were created and skips colors picked
  by hand; a hand-picked color is stored in the CloudKit-synced `Instance.colorKey` and so shows on every device. Settings ›
  Instances › [instance] has a **Color** picker; the instance list shows the color dot. In the "Sectioned" mode all lists
  (Shifts, News, Locations, Messages, Profile) use the same `InstanceSection`: a tinted band across the full width with
  the instance's color, name, count ("3 shifts") and a chevron; tapping it folds the instance away (kept while the screen
  is open). Topics or days inside an instance are `SubheadingRow`s (Profile now shows Profile / Angel Types / Worklogs in
  every mode, and uses the flat list style like the other screens). In the merged mode badges are colored and rows have a
  colored left edge. Colors never carry the information alone: the name is always shown.

- **Shift filter and sort** (2026-10-16): a filter menu in the Shifts toolbar (same pattern as the News filter) with
  "Show" — Upcoming (default: running and not yet started), Today (runs or begins today, also across midnight), Past, All —
  and "Sort" — Earliest First (default) or Latest First, which orders the days and the shifts within a day. Both choices are
  remembered per device (`@AppStorage`); the symbol is filled when either differs from the default. When the filter hides all
  shifts the list says "No Matching Shifts" with a "Show All" button; "Last Synced" ignores the filter. The Past/Today/Upcoming
  split is recomputed every minute (so also across midnight). Logic: `ShiftTimeFilter`, `ShiftSortOrder` (Kit, tested).

- **Collapsible Features list** (2026-10-16): on the instance page the summary line ("11 of 11 features available") is the
  header of a `DisclosureGroup`; the list starts collapsed when every function is available and open, problems first (not
  allowed, not offered, not checked yet), otherwise. A tap on the summary opens/closes it; the choice holds while the page
  is open. Logic: `FeatureListLayout` (Kit).

- **Main list follows the Features list** (2026-10-16, ADR 0015): News, Shifts, Locations, Messages and Profile (needs the work
  logs or the angel types) are listed only when at least one active instance offers them — or nothing has proved the
  opposite yet. A group without any row (e.g. "Event" without Shifts and Locations) is left out with its heading. The demo
  server that offers only News therefore shows just News.

- **Messages in the merged mode** (2026-10-16): conversations of several instances are rows identified by instance *and*
  user (`ConversationEntry`) — user ids repeat across instances, which drew the same row twice — and the badge and colored edge
  show whenever several instances are active, even if only one of them offers Messages.

- **Instance freshness and refresh on activation** (2026-10-16): the footer of the main list
  (`InstanceFreshnessFooter`) shows per active instance how old its cached data is — grey with a check mark below 12 hours,
  orange with a warning triangle from 12 hours on, red with a warning triangle when nothing was ever synced; the instance's name
  leads the text only when several instances are active. Tapping a row refreshes that instance (full sync with the progress
  banner). Switching an instance **on** in Settings refreshes it right away (iOS: full sync; Watch: shifts), because its cache
  may be old; syncs queued this way run one after the other (`InstanceSyncQueue`). Reminders and the complication are planned
  over all active instances' cached shifts (`reminderInstances` / `allActive`), so refreshing one instance never cancels the
  others'. A change made on the other device reaches the Watch through the existing CloudKit remote-change refresh. Logic and
  texts: `InstanceFreshness` and `Instance.setActive` (returns whether it was just switched on) in the Kit.

- **Sync banner per instance** (2026-10-16): a full sync (app start, pull-to-refresh on the main page, an instance switched on,
  a tapped freshness row) shows `SyncRunBanner` — one row per instance with its state (waiting / running / done / failed /
  timed out / skipped), the area it works on and "n/5" steps, and a thin line under the text for the finished steps. The
  instance's name leads the row only when several instances sync. A step that takes 30 s turns the row orange ("not
  responding"); an instance that makes no progress for 60 s is cancelled ("timed out") and the next one still runs
  (`SyncControl`, restarted by every finished step). **Stop sync** asks first (“Data already loaded is kept…”); with several
  instances the dialog also offers **Skip <instance>**. After a run with problems the banner stays 5 s and names the instances
  (“Partially failed: Congress (timed out)”). `AppSyncCoordinator` reports `SyncEvent`s, `SyncRunModel` (Kit, tested) turns
  them into the rows. The single-area pull-to-refresh of Shifts/News/Profile keeps the simple banner (no stop button).
  A cancelled URLSession request counts as a cancellation, never as a network failure.
  **Parallel syncs** (2026-10-16): `AppSyncCoordinator` syncs up to N instances at the same time (`maxConcurrentInstances`,
  default from the per-device `ParallelSyncSetting`: 0 = all at once, 1 = one after the other, 0…10); the next one starts as soon
  as one finishes. iPhone (Settings › Instances) and Watch (Settings) each show the setting as a stepper ("Unlimited", "3 at a
  time"). `SyncControl` keeps a worker and a no-progress timer per instance, so a hanging instance does not hold the others
  back, and the Stop dialog offers "Skip <instance>" for every running or waiting instance.

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
  `List`. **A shift's location name links to that location's detail
  screen** (2026-09-23, user-requested, see "Locations" below) — a
  `NavigationLink` when a matching `CachedLocation` exists (resolved by
  `instanceID` + `locationID`), falling back to the old plain, non-linked
  label when Locations hasn't synced yet or the shift's location was
  since removed server-side.
- **News** (`Features/News`): same pattern via `NewsSyncService`/
  `CachedNews`/`NewsViewModel.refresh(instances:in:)`; pinned items sort
  first, meeting items get a badge, body text renders through
  `AttributedString(markdown:)` since the API docs say news text may
  contain markdown. **Block-level markdown (headers, lists, block quotes)
  needs manual re-rendering, not just `interpretedSyntax: .full`**
  (2026-09-22, user-requested, then user-reported broken): switching the
  parse options to `.full` (from the default
  `.inlineOnlyPreservingWhitespace`, which only understands inline
  emphasis/links/code) does correctly *parse* block structure into
  `PresentationIntent`s — but `Text` silently ignores those; it only
  renders inline attributes. The list/header markers get consumed as
  structure with nothing put back in their place, so bullet lists
  actually got *worse* than before (they'd previously shown at least as
  a literal "-"/"*" character under inline-only parsing; under `.full`
  alone they vanished completely). `NewsMarkdownRenderer` (`Features/
  News`, Kit-independent since it needs `SwiftUI.Font`/`Color`) walks
  the `.full`-parsed `AttributedString`'s runs and manually re-derives
  what `Text` won't: a "•"/"1." prefix for list items, a full blank-line
  paragraph break between anything else (so multi-paragraph text doesn't
  visually run together), bold+larger text for headers, and `.secondary`
  color for block quotes — verified against real `PresentationIntent
  .Kind` API shape/behavior via a standalone `swift <file>.swift` probe
  first (case names, associated values, and per-run `identity`/
  `components` grouping), not guessed from memory, given how easy this
  API is to get subtly wrong.

  **Nested lists (indentation, spacing) fixed same day, user-reported
  again**: the first version only ever inspected the single *innermost*
  list/item via `.first { isListItem(...) }` — correct for that run's
  own bullet/number, since `PresentationIntent.components` is ordered
  innermost-to-outermost, but insufficient on its own: it also
  determined list-vs-not-list purely by comparing that innermost list's
  `identity` against the *previous* run's, so descending into or back
  out of a nested list looked like "a different list entirely" and got
  a blank-line paragraph gap instead of sitting tightly under its parent
  item — and nothing added any indentation in the first place. Fixed by
  (1) counting how many `.listItem` components appear in the chain at
  all (nesting depth — one per level, confirmed via the same probe
  methodology) and indenting two spaces per extra level, and (2)
  simplifying the tight-vs-blank-line decision to "is this run part of
  *any* list, at *any* depth" rather than "does its specific list
  identity match the previous run's" — any list context now stays
  tightly attached regardless of depth changes; only actually leaving
  list context (a plain paragraph/header/block quote) gets the wider
  break. `NewsRow`'s `attributed(_:)` now calls
  `NewsMarkdownRenderer.render(_:)` (used for both the preview and the
  expanded `[more]` text) instead of a bare
  `AttributedString(markdown:)` call. ~~`CachedNews.sanitizedText(from:)` strips the
  `[more]` separator tag the API docs mention before storing — we always
  show the full text, so removing the marker is enough, no truncation
  needed.~~ **Wrong, fixed 2026-09-22 (user-reported): the website
  actually truncates at `[more]` with a "read more" expansion; the app
  was silently dropping that behavior entirely by stripping the tag and
  always showing the full text.** `CachedNews.text` now stores the raw
  text as-is (trimmed, marker kept) instead of pre-stripping it at
  sync/storage time — that decision has to happen at *display* time, not
  storage time, or the split point is lost for good. `CachedNews
  .textParts(from:)` (pure, Kit-tested) splits it into `preview`/`rest`
  (`rest` is `nil` when there's no tag, or nothing follows it — meaning
  no "Read more" control should show). `NewsRow` shows `preview` always,
  collapses `rest` behind a "Read More"/"Show Less" toggle
  (`@State private var isExpanded`) exactly when `rest != nil`, matching
  the website. When expanded, `rest` renders in an indented, tinted
  rounded box (`Color.secondary.opacity(0.1)`) rather than as a plain
  extra paragraph — user-requested the same day, so the expanded part
  reads as "the revealed part," not as if it had been there all along.
  Existing cached rows synced before this fix still have
  the tag already stripped from a previous version of the app — no
  migration needed, since the very next sync overwrites `text` via
  `apply(_:)` with the new raw version anyway.
  **`.merged` display mode deduplicates across same-server instances**
  (2026-09-22, user-reported): two active `Instance`s pointing at the
  same actual server (e.g. two different user accounts for one server)
  each sync and cache their own copy of every news post — `CachedNews
  .uid` includes `instanceID`, so it's a genuinely separate row per
  instance, not a natural duplicate SwiftData would already collapse.
  `CachedNews.mergedAcrossServers(_:instances:)` (pure, Kit-tested)
  collapses these before display, keyed by (the owning `Instance`'s
  `normalizedBaseURL`, the post's server-assigned `serverID`) — not
  `instanceID` alone, since that's what actually identifies "the same
  post" across two instances of the same server. Applied only in
  `.merged` mode (`NewsView`'s only true flat cross-instance list);
  `.switcher` shows one instance at a time already, and `.sectioned`
  groups by instance on purpose, so seeing the same real content once
  per relevant section there is consistent with that mode's design, not
  a bug to fix the same way.

  **Each merged post keeps every contributing instance's name, not just
  one** (fixed same day, same-day user follow-up report: the first
  version returned a plain `[CachedNews]` — one representative row per
  duplicate group — which meant `NewsRow`'s badge showed only *that one*
  instance, silently dropping the fact that the post also exists on the
  other same-server instance). `mergedAcrossServers` now returns
  `[CachedNews.MergedItem]` (`item` + `instanceNames: [String]`,
  collecting every instance in the duplicate group, not just the
  surviving representative's own instance); `NewsRow.instanceNames` is
  now `[String]` (was a single optional `instanceName: String?`) and
  renders one `InstanceBadge` per name via `ForEach`. Which duplicate's
  *content* (`item`) survives to represent the group is still arbitrary
  (harmless — real duplicates share the same content) but the badge row
  no longer loses information regardless.

  **Meeting/non-meeting filter** (2026-09-22, user-requested):
  `NewsMeetingFilter` (`Features/News`, iOS-only — no News screen on the
  Watch, per its minimal scope) is a `.all`/`.meetingsOnly`/
  `.nonMeetingsOnly` enum with a pure `matches(_:)` over `CachedNews
  .isMeeting`, session-scoped `@State` on `NewsView` (not `@AppStorage`
  like `MultiInstanceDisplayMode`) — this is a transient list filter, not
  a standing display preference, so it deliberately resets to `.all` on
  next launch rather than being remembered. Reached via a toolbar `Menu`
  (filter icon, filled when a filter other than `.all` is active,
  matching the Mail/Files app convention) rather than an inline segmented
  control, to avoid competing for space with `InstancePicker` in
  `.switcher` mode. Applied once, in the shared `newsItems` computed
  property, so all three `MultiInstanceDisplayMode`s (including the
  cross-server dedup above, which only ever sees already-filtered items)
  stay consistent automatically. `emptyState` distinguishes "no news at
  all" from "the filter hid everything" (checks `activeInstanceNewsItems`
  — the pre-filter set — so a real empty instance and an active-but-
  zero-matches filter don't look identical).

  **Local notification for genuinely new posts** (2026-09-22,
  user-requested): `NewsSyncService.sync` returns a `NewsSyncResult`
  (`items` — everything synced, matching the previous plain-array shape
  — plus `insertedItems`, the subset that didn't already exist in
  `CachedNews` before this sync) instead of a bare `[CachedNews]`, since
  the insert-vs-update distinction already existed internally but had no
  way out to callers. `NewsNotifier` (`Services/`) turns any non-empty
  `insertedItems` into a **single** local notification per sync pass —
  one bundled "N New Announcements" summary rather than one notification
  per item, so an instance that's been dormant for a while doesn't spam
  the user with a dozen banners the moment it's synced again. For exactly
  one new item, the notification shows that post's own title + preview
  text instead of a generic summary. Gated by a Settings toggle,
  **"Notify on New News"** (`NewsNotifier.enabledUserDefaultsKey`,
  default on — framed as an opt-out) in the Notifications section, next
  to the shift lead-time picker.

  **Only fires from the background/interval sync, not from
  `NewsViewModel.refresh` (pull-to-refresh) — moved there once the
  background-sync feature landed** (see "Background sync" above for the
  full feature). `NewsViewModel.refresh` briefly fired this
  unconditionally on every sync when this feature first shipped (there
  was no background-sync path yet for it to live in), which meant pulling
  to refresh the News screen you were already looking at could trigger a
  notification about content you were about to see anyway — noise, not
  useful. Now lives in `AppSyncCoordinator.syncEverything`'s
  `notifyOnNewNews` parameter, which only the background-sync call site
  ever sets to `true`; `NewsViewModel.refresh` just syncs, nothing more.

  **Comments** (2026-09-22, user-requested, via `/news/{id}` — see "API"
  above): `CachedNews.commentsCount: Int = 0` is synced/cached like the
  rest of the list (the inline `= 0` default on the *property itself*,
  not just the `init` parameter, is required — SwiftData's lightweight
  migration for adding a new attribute to an existing local store reads
  the property's own declared default to backfill old rows; an
  init-only default doesn't help it at all — confirmed hands-on: without
  it, `ModelContainerFactory` crashed on launch against a
  pre-2026-09-22 store with "Cannot migrate store in-place ... missing
  attribute values on mandatory destination attribute" for exactly this
  property). When a row's `commentsCount > 0`, `NewsRow` shows a "N
  Comments" `NavigationLink` — a distinct, explicitly labeled link, not
  the whole row, since the row already has its own "Read More" button
  and stacking two different tap actions on the same row content isn't
  worth the ambiguity. Shown on the same line as the date,
  trailing-aligned (`HStack` with a `Spacer()`), which is a reasonable
  compact layout on its own merits, but **is not what actually fixes tap
  independence from "Read More"** — an earlier version of this entry
  claimed the opposite (moving it there to give the two buttons more
  physical distance) and was wrong; see the real fix below.

  **Real bug, same day, second report**: after the above layout change
  shipped, the user reported tapping "Read More" *also* silently opened
  the Comments detail screen in the same tap, and after returning,
  "Show Less" had become unreachable (same cause, just now hitting the
  Comments `NavigationLink` instead). This proved the "physical
  distance" theory wrong — the two controls were never actually
  overlapping on screen. Root cause: a well-known SwiftUI `List` row
  quirk — once a row contains a `NavigationLink` *anywhere*, an
  unstyled `Button` elsewhere in that same row can have its tap "fall
  through" into also activating the row's `NavigationLink`, regardless
  of where either control visually sits or how far apart they are.
  Fix: `.buttonStyle(.plain)` on the "Read More"/"Show Less" `Button` in
  `NewsRow` — this tells SwiftUI the button owns its own independent
  tap rather than deferring to the row. Verified via a dedicated
  XCUITest (`testReadMoreDoesNotAlsoOpenComments`), which needed
  `DemoData`'s item 1 to gain a `[more]` split alongside its existing
  comments — no other demo news item has both simultaneously, and both
  are required to exercise this bug at all. The test asserts the News
  navigation bar is still present immediately after tapping "Read
  More" (i.e. Comments did *not* also open), that "Show Less" is then
  reachable and toggles back correctly (also without opening Comments),
  and that the Comments link still works when tapped directly.
  Pushes `NewsDetailView` (`Features/News`, new),
  which shows the full post plus its comments via `NewsDetailViewModel`
  — comments are fetched **live, every time this screen opens, not
  cached** (unlike the rest of this app's data): this is a detail-only
  view, never aggregated across instances the way the News *list* is,
  so there's no `CachedNews`-style per-instance duplication to prevent
  in the first place (confirmed with the user before skipping a cache —
  they'd asked whether comments needed the same cross-server dedup as
  `mergedAcrossServers`; they don't, precisely because nothing here
  caches per-instance to begin with). Needs the specific `Instance` a
  given `CachedNews` row actually came from to resolve a credential
  (`NewsView.instance(for:)`, matching `item.instanceID` against the
  active instances array) — `CachedNews` itself only carries a plain ID,
  never a live reference (see "CloudKit sync for Instance metadata" in
  [`architecture.md`](architecture.md) for why relationships across
  `Instance`/`Cached*` don't exist).
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
- **Locations** (`Features/Locations`, 2026-09-23, user-requested):
  browse an instance's locations (rooms), each linking to a detail
  screen — reached via a new sidebar entry, and also what a shift's
  location name now links to (see `ShiftsView` below). Same pattern as
  Shifts/News/Profile via `LocationSyncService`/`LocationsViewModel
  .refresh(instances:in:)`/`CachedLocation`, respecting
  `MultiInstanceDisplayMode` (merged/switcher/sectioned). Locations is a
  4th domain in `AppSyncCoordinator.syncEverything` (in the same
  `!shiftsOnly` block as News/Profile, so the Watch's `shiftsOnly: true`
  app-start sync never touches it, no special case needed) — kept
  proactively synced rather than fetched lazily, since the API has no
  way to fetch a single location by id from *most* servers (only the
  list, `GET /locations` — see below), so the link from a shift needs
  the full list already cached to resolve at all.
  `LocationDetailView` shows the description, an optional map link
  (`map_url`) and an optional DECT contact number. The former "Open on
  Website" link was removed 2026-10-13 (the app deliberately shows no
  angel-type counts or shifts of a location). **Map Links setting**
  (`MapLinkMode`, per-device `@AppStorage`, Settings › Privacy): `embedded`
  (default) or `linkOnly`; `embedded` also renders the map page in an
  `EmbeddedMapView` (`WKWebView`, persistent store of its own via `MapWebsiteData`, http/https only, no
  browser bar, page loaded anew every time; the text info takes exactly the height it needs at the top and the map fills the rest of the
  screen; an automatic cleanup every N days (`MapWebsiteDataRetention`, default 30, 0 = never, or "Until the App Quits" = a shared in-memory store, checked before the map loads);
  Settings › Privacy › Delete Map Website Data deletes everything after a Delete/Cancel confirmation; navigations use WebKit's no-app-link policy so universal links never leave the app) above an "Open Map in Browser" button (opens the default browser; the
  plain link is labelled "Show Map" in link-only mode); both layouts show description, DECT (with its "Internal short number" note), then the map link in this order — see ADR
  0014. iOS only.

  **`LocationDetailView` also gets its own live pull-to-refresh**, via
  the newly added `GET /locations/{id}` (`APIClient.fetchLocation(id:_:)`,
  `LocationSyncService.refreshOne`) — added the same day, after a
  cross-session update reported this endpoint now exists (previously
  only the list did). Deliberately kept as an *additive* enhancement on
  top of the list-based cache, not a replacement: the Locations list
  screen and the shift link both still rely purely on the cached list
  (fewer network calls, works offline, doesn't depend on an unmerged
  endpoint), and only this one detail screen's manual pull-to-refresh
  uses the single-location endpoint, updating the same cached row in
  place. This endpoint is on a server branch not yet merged upstream
  (PR engelsystem/engelsystem#1711) — a server without it just shows a
  normal error banner on that one pull-to-refresh action; nothing else
  in the feature is affected.
- **Messages** (`Features/Messages`, 2026-09-23, user-requested): send
  and receive private messages with other users on an instance, reached
  via a new sidebar entry. See [`CLAUDE.md`](../CLAUDE.md)'s API section
  for the `/messages` endpoint itself and the capability-probe design —
  this entry covers the client-side feature built on top of it.

  **Sidebar visibility is entirely conditional.** `MainView.Section
  .visibleSidebarCases(forActiveInstances:)` only includes `.messages`
  when at least one active instance's `Instance.messagesSupported` is
  `true` — a server that doesn't support Messages yet never shows the
  entry at all (the explicit requirement: "if the instance doesn't
  offer the new interface, don't show the GUI"), rather than showing it
  disabled or erroring when opened.
  `MainView.resolvedSelection(_:visibleSections:)` falls back to
  `.shifts` if a previously-selected `.messages` becomes unavailable
  (e.g. the one supporting instance is deactivated) — `Section
  .sidebarCases` (the persistable set) still includes `.messages`, only
  `visibleSidebarCases` filters by current support, so a stored
  last-selected-section value surviving a temporary "no instance
  supports it" state isn't itself a bug.
  `messagesSupported` is kept current by a lightweight extra step in
  `AppSyncCoordinator.syncEverything` (`stepsPerInstance` 4→5, in the
  same `!shiftsOnly` block as Locations — Watch's `shiftsOnly: true`
  sync never touches it) — no dedicated Setup/Edit-time probe, the
  periodic re-check is enough to pick up a server that gains support
  later.

  **Live-only, no `Cached*`/sync service** — every screen fetches over
  the network each time, unlike every other feature above. This is the
  API's first mutable, bidirectional resource; a local cache would need
  to reconcile offline writes against the server, and avoiding that
  entirely was simpler for a first version. `MessagesViewModel
  .refresh(instances:)` fetches each active+supporting instance's
  conversation list (`APIClient.fetchConversations`) into a
  `[UUID: [Conversation]]` dictionary (keyed by `Instance.id`, since
  there's no `@Query`-backed cache to filter) — a failure on one
  instance doesn't block the others, matching every other multi-instance
  sync. `MultiInstanceDisplayMode` (merged/switcher/sectioned) still
  applies, same as Shifts/News/Locations.

  **`MessagesView`** lists conversations (other user's name, latest
  message preview, unread count badge), each linking to
  **`ConversationDetailView`** — the message thread, backed by
  `ConversationDetailViewModel`:
  - `load(otherUserID:instance:)` fetches the full thread
    (`APIClient.fetchConversation`) and then marks every unread
    *incoming* message read (`APIClient.setMessageRead`). "Incoming" is
    determined structurally — `sender.id == otherUserID` — rather than
    by resolving the signed-in user's own id, which this live-only
    feature has no other reason to know; a two-party thread's
    sender/receiver pair already fully describes direction.
  - `send(text:otherUserID:instance:)` trims whitespace, rejects blank
    text, and appends the server's returned `Message` on success
    (`APIClient.sendMessage`).
  - `delete(_:instance:)` removes a message the signed-in user sent
    (`APIClient.deleteMessage`) — the UI only offers this action via a
    swipe action on the user's own rows (`sender.id != otherUserID`) in
    the first place; the server would reject deleting the other party's
    message with `403`, but that's never actually exercised since the
    option isn't offered.

  **`NewConversationView`** (a sheet, reached via `MessagesView`'s
  "New Message" toolbar button) implements the "start a new
  conversation" flow: with more than one active+supporting instance, it
  first asks which instance to compose from (a message always belongs
  to exactly one server), then shows **`UserPickerView`**
  (`UserPickerViewModel.load(instance:)`, backed by the new
  `APIClient.fetchUsers` → `GET /users`) to pick a recipient. Picking a
  user dismisses the sheet and navigates to `ConversationDetailView` for
  that (instance, user) pair — whether or not a conversation with them
  already exists; the API has no separate "create conversation" step,
  a conversation is just whatever messages exist between two users.

  **Demo mode simulates real mutation, not just fixed data** — a first
  for this app. Every other `DemoData` property/method is a read-only
  fixed snapshot; Messages needed genuine send/delete/mark-read
  behavior for "Try Demo Mode" to actually represent this feature.
  `DemoMessageStore` (`EngelsystemClientKit/Networking/DemoData.swift`,
  `@MainActor`-isolated for safe mutable global state, same reasoning as
  `DebugLog`) is a singleton holding `[Int: [Message]]` keyed by other-
  user-id, seeded with one unread message from "Helper Angel" (id 2) so
  the unread badge and mark-read-on-open behavior have something to
  show immediately. `DemoData.users` adds three sample users (ids 2–4)
  backing the new-conversation picker.

  **Tests**: Kit-level coverage
  (`EngelsystemClientKitTests`) — the pure capability-probe
  interpretation (`APIClient.messagesSupported(afterProbeError:)`,
  covering both 404 body shapes plus unrelated errors/missing/
  unparseable bodies), and a full demo-mode round trip through
  `fetchConversations`/`fetchConversation`/`sendMessage`/
  `setMessageRead`/`deleteMessage`/`fetchUsers`. App-target coverage
  (`EngelsystemClientTests`) — `MessagesViewModel` (loads per instance,
  one failure doesn't block others), `ConversationDetailViewModel`
  (load+auto-mark-read, send trims/rejects blank text, delete),
  `UserPickerViewModel` (sorted by name), and `MainView`'s visibility/
  fallback logic (`MainViewMessagesVisibilityTests`/
  `MainViewResolvedSelectionTests`). `AppSyncCoordinator`'s existing
  progress-count tests were updated for the new 5th step and gained a
  `messagesSupported` assertion. `testDemoModeNavigationFlow` (UI test)
  extended to navigate into the seeded "Helper Angel" conversation and
  send a message end to end.
- **Instance management** (`Features/Settings/SettingsView`): reached via
  the gear icon in the sidebar's toolbar corner (see "Main navigation"
  above). A plain pushed list (not its own
  `NavigationSplitView`, since it's already hosted inside `MainView`'s).
  ~~Originally split into "Active"/"Inactive" sections with a swipe
  action per row to move an instance between them — a per-row `Toggle`
  was explicitly rejected in favor of this at the time.~~ **Superseded
  2026-09-22, at the user's explicit request**: a single flat list, one
  row per instance, with a `Toggle` bound directly to `instance.isActive`
  (CloudKit-synced — see "Multi-instance concept" above). People change
  their minds about UI decisions; this isn't a mistake being corrected.
  The row still navigates to `InstanceDetailView` on tap (for Edit/
  Remove) — a `NavigationLink(value:)` made invisible (`.opacity(0)`)
  and layered *behind* the visible row content via `ZStack`, so the
  `Toggle` can handle its own taps instead of the whole row navigating
  (a standard SwiftUI `List` pattern for "row navigates, but also has
  its own accessory control"; confirmed working end-to-end via
  `testDemoModeNavigationFlow`, which taps the toggle by its explicit
  `.accessibilityLabel("\(instance.name) Active")` — `.labelsHidden()` +
  an `EmptyView()` label otherwise leaves a `Toggle` with no accessible
  name at all, bad for VoiceOver and unfindable by a UI test).

  **"Last Synced" section (2026-09-23, user-requested)**: `InstanceDetailView`
  shows a per-domain last-sync timestamp (Shifts/News/Profile) for that
  one instance, e.g. "2 minutes ago" or "Never". Backed by
  `CacheSyncTimestamp` (`EngelsystemClientKit/Persistence/
  CacheTimestamped.swift`) — every `Cached*` model already carries
  `cachedAt` (set on insert, refreshed by `updateCacheTimestamp()` on
  every update via `apply(_:)`), so it already *means* "last synced from
  the server"; this just picks the freshest one for a given
  `instanceID` out of an unfiltered `@Query`, same fetch-everything-and-
  filter-in-Swift pattern already used by Shifts/News/Profile
  themselves. `CacheTimestamped` is a small protocol (`instanceID` +
  `cachedAt`) all five `Cached*` types conform to, so
  `lastSyncDate(for:in:)` works generically instead of five near-
  identical call sites. "Profile" specifically is the freshest across
  *three* underlying types (`CachedUser`/`CachedWorklog`/
  `CachedAngelTypeMembership`, via `CacheSyncTimestamp.mostRecent`) —
  they're three separate `Cached*` models but always synced together in
  one `ProfileSyncService` pass, matching how the sidebar presents them
  as a single "Profile" screen. Watch's `WatchInstanceDetailView` shows
  only "Shifts" — its schema doesn't include `CachedNews`/`CachedUser`/
  `CachedWorklog`/`CachedAngelTypeMembership` at all, per "Watch app
  scope" in [`CLAUDE.md`](../CLAUDE.md).

  **Extended the same day, further user-requested, onto Shifts/News/
  Profile themselves** (not just Settings' instance-detail screen): a
  small shared `SyncTimestampFooter` (`Features/Shared/`, iOS app
  target) renders a centered "Last Synced: …" row at the bottom of each
  screen's `List`, styled identically to Settings' own version/sync-
  status footer. Unlike Settings' per-instance breakdown, this shows
  **one aggregate timestamp** — the freshest sync across *all*
  currently active instances contributing to that screen, computed the
  same way (`.map(\.cachedAt).max()` over each screen's own already-
  filtered items — `shifts`, `activeInstanceNewsItems` for News
  specifically (not the meeting-filtered `newsItems`, so the filter
  can't make the timestamp look stale by hiding everything), and
  `CacheSyncTimestamp.mostRecent(...)` across Profile's three
  underlying types for Profile). **Same known limitation as Settings'
  version**: `nil`/"Never" can't currently be told apart from "synced
  successfully with zero items returned", since there's no dedicated
  per-domain sync-attempt timestamp independent of the cached rows
  themselves.

  **Also added to the Apple Watch's `NextShiftView`**, replacing its
  previous "Updated HH:mm" line (driven by `NextShiftViewModel
  .lastUpdated`, now removed entirely — it had become genuinely
  redundant, not just stylistically inconsistent): that property was
  only ever set inside this view's own `.refreshable`, so it silently
  stayed `nil` — showing nothing at all — until the user manually
  pulled to refresh at least once, even though `WatchMainView`'s silent
  app-start sync (see "Background sync" above) may already have
  populated `CachedShift` well before that. The new `cachedAt`-based
  `lastSyncedAt` (same `.map(\.cachedAt).max()` pattern, over the
  existing `shifts` computed property) correctly reflects *either*
  trigger, fixing that gap as a side effect of just chasing wording
  consistency with iOS.

  Removing an
  instance cleans up both keychain stores, since which one was used at
  creation time isn't persisted. The combined **"Edit Instance"**
  dialog (`EditInstanceViewModel`) merges what used to be two separate
  actions — "Edit Name / Server" and "Update API Key" — into one form
  (Name, Server URL, API Key); the API Key field is blank by
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
  (see "Data/code flow" in [`architecture.md`](architecture.md)). Also a **Multiple Active Instances**
  picker (`MultiInstanceDisplayMode`, see above) and a **Notifications**
  section — see "Multiple reminders" below for the current shape of
  this (it used to be a single "Notify Before Shift" picker; now a
  addable/removable list). At the very bottom, a plain unheadered
  section shows (2026-09-18)
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

  **`InstancePicker` didn't preselect a tab, 2026-09-22, user-reported**:
  the segmented control's `selection` binding starts `nil`
  (`ShiftsView`/`NewsView`/`ProfileView` each own their own
  `@State private var selectedInstanceID: UUID?`), and rows are only
  ever tagged with a real instance ID — never `nil` — so `nil` never
  matches any row and the control showed no highlighted segment at all.
  Each caller separately falls back to `instances.first` via its own
  `switcherInstance` computed property to decide *which data* to show,
  but that only ever fixed the content, never the picker's own visual
  selection. Fixed inside `InstancePicker` itself (`.onAppear` +
  `.onChange(of: instances.map(\.id))`, comparing IDs rather than
  `instances` directly since relying on `Instance: Equatable` felt like
  an assumption worth not making) calling a new pure
  `static func resolvedSelection(current:instances:)` — falls back to
  the first instance when the current selection doesn't match any (also
  handles the previously-selected instance dropping out of the active
  set, e.g. via deactivation, not just the initial-`nil` case) — kept as
  a `static` function specifically so it's unit-testable
  (`EngelsystemClientTests.InstancePickerSelectionTests`) without
  needing to construct the `View`/drive its `body`, matching this
  session's usual pattern once "why wasn't this tested" got asked about
  a previous fix.
- **Local shift-start notifications** (`Services/NotificationScheduler`):
  after every successful Shifts sync, requests notification authorization
  if not yet determined and schedules a local reminder
  (`CachedShift.notificationDate(minutesBefore:)`) for each upcoming
  shift, keyed by a stable identifier so re-syncing updates in place
  instead of duplicating. Also cancels any previously scheduled shift
  notification that's no longer in the synced/upcoming set. Goes through
  a thin `NotificationCenterScheduling` protocol over
  `UNUserNotificationCenter` so the scheduling logic is unit-testable
  with a fake center — no simulator or real permission prompt needed for
  that. No server push involved, per the "no server-side push"
  constraint.

  **"Multiple reminders" (2026-09-22, user-requested)**: a shift can now
  have more than one lead time configured at once (e.g. a reminder 60
  minutes before *and* another 15 minutes before), not just a single
  value. `identifier(for:minutesBefore:)` now bakes the lead time into
  the notification's identifier (`"shift-notification-<uid>-<minutes>"`)
  so multiple independent reminders can coexist per shift;
  `plan(for:leadTimes:)`/`syncNotifications(for:leadTimes:)` take the
  full list and produce one planned notification per (shift, lead time)
  pair. Removing a lead time from the configured list needs no special
  handling — it just stops appearing in `plan(...)`, and the existing
  "cancel whatever's no longer planned" logic already prunes exactly
  that shift's notification for that specific lead time, not the
  others.

  **Storage: `NotificationLeadTimeSettings`
  (`EngelsystemClientKit/Persistence/`), CloudKit-backed like `Instance`
  — but with one row *per platform*, not a single shared singleton.**
  The user explicitly asked for the list to sync *within* a platform (an
  iPhone and iPad on the same account should agree) but *not* share one
  list *across* iOS and Watch — you might legitimately want fewer/
  different reminders on your wrist than your phone. `platform: String`
  ("ios"/"watch") is the discriminator; `currentPlatform` resolves it at
  compile time via `#if os(watchOS)`. `resolve(in:)` fetches-or-creates
  the row for the calling device's own platform (seeded with
  `defaultLeadTimesMinutes = [15]` on first creation only);
  `resolve(for:in:)` takes the platform explicitly, which is what lets
  iOS's `SettingsView` also read/write the **Watch's** row (see below)
  and lets tests exercise the "watch" row without compiling for
  watchOS. `leadTimesMinutesRaw` is a comma-separated `String`
  (`"15,60"`) — same plain-value storage style as `Instance`'s fields,
  not a `Codable`-encoded blob.

  **Real bug found and fixed while testing, worth remembering**:
  `parseLeadTimes` originally fell back to the default list whenever the
  stored string was empty — reasonable-sounding (handles the
  CloudKit-required `= ""` property default gracefully), but it meant
  removing a user's *last* remaining reminder immediately "bounced back"
  to showing the default again, since "never configured yet" and
  "deliberately cleared to zero" were both stored as the same empty
  string and thus indistinguishable. Confirmed hands-on via a UI test,
  not just reasoned about. Zero reminders is a legitimate, intentional
  end state (a full opt-out) and must stay zero — fixed by only ever
  applying `defaultLeadTimesMinutes` in one place, `resolve(...)`'s
  first-creation path, and letting `parseLeadTimes("")` mean `[]`
  everywhere else. Covered by a regression test
  (`notificationLeadTimeSettingsRemovingTheLastLeadTimeStaysEmpty`).

  **Settings UI**: a list of the currently-configured lead times, each
  with a **visible** remove button (`"minus.circle.fill"`, red — an
  explicit per-row button was requested over relying on swipe-to-delete
  alone) plus an **"Add Reminder"** control offering only the presets
  (5/10/15/30/60 min) not already selected. On iOS this is a `Menu`; on
  watchOS, `Menu` isn't available at all, so `WatchAddReminderView` (a
  small pushed `List` of the remaining presets, each a `Button` that
  adds and pops back via `.dismiss()`) is the substitute. **iOS's
  `SettingsView` shows *both* platforms' lists** (2026-09-22, further
  user-requested: "also show the Watch's settings in the iOS app") — a
  second "Apple Watch Reminders" section, fully editable from the phone,
  with its own distinctly-labeled controls ("Add Watch Reminder",
  "Remove N min Watch reminder") so the two "Add Reminder"-shaped
  buttons stay unambiguous to VoiceOver and UI tests alike. There's no
  reason editing the Watch's list should require physical access to its
  much smaller screen, given both rows already live in the same
  CloudKit-synced model.

  **UI-testing note**: tapping into the `Menu`'s own popup content
  (to actually pick a preset) was tried and consistently failed to find
  the item afterward — the leading suspect is XCUITest's automatic
  "check for interrupting elements" step (run before every subsequent
  interaction) treating the menu's popup as unexpected UI and dismissing
  it before the check could run, though this wasn't conclusively
  isolated. `testDemoModeNavigationFlow` therefore only verifies the
  "Add Reminder" button exists/is hittable (not what happens after
  tapping it) and exercises the **remove** path fully end-to-end (a
  plain button tap, no popup involved, and reliable). The add path's
  actual logic is still covered by `NotificationLeadTimeSettings`'s Kit
  unit tests.

### watchOS app

- **Own local setup** (`Setup/WatchSetupView`): the Watch app's manual
  entry form (name, server URL, API key, plus a "Try Demo Mode" button),
  using the same `InstanceSetupService` as the iOS app. Since CloudKit
  sync (see [`architecture.md`](architecture.md)) landed, this is
  genuinely the **fallback** path now (per "Sync strategy" in
  [`architecture.md`](architecture.md)) rather than the only way to configure
  the Watch — an instance created on iPhone should sync here automatically
  via CloudKit — but that hasn't been end-to-end verified yet (see the
  caveats in "CloudKit sync for Instance metadata" in
  [`architecture.md`](architecture.md)), so treat this
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
  `ContentView` still only decides between "no instance yet" and "at
  least one" (→ `WatchMainView`) — but the "no instance yet" branch
  changed 2026-09-18, at the user's request: it now goes straight to
  **`WatchSettingsView`** instead of the manual-entry `WatchSetupView`.
  Reasoning: since `Instance` syncs via CloudKit unconditionally (see
  the root-cause fix above), an instance created on the iPhone should
  just appear on the Watch on its own — showing Settings first lets the
  user watch the `CloudSyncStatus` footer to confirm that's actually
  happening, rather than being steered straight into manual entry as if
  sync wasn't an option. `WatchSetupView` (manual entry / "Try Demo
  Mode") remains one tap away via Settings' existing "Add Instance"
  button, so the "Fallback" path documented in
  [`architecture.md`](architecture.md) is still fully reachable — this
  is a routing change, not a removal. Reactive via `@Query`, same as
  before: once an instance exists (synced in or manually added),
  `ContentView` automatically switches to `WatchMainView` on its own.
  `WatchSettingsView` mirrors
  iOS's `SettingsView`: a single flat list with a per-row `Toggle` bound
  to `instance.isActive` (2026-09-22, superseded from the original
  two-section/swipe-action design, same as iOS — see "Implemented
  features" → iOS `SettingsView` above for why and how). No
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
  `EditInstanceViewModel` — same merged name/server/API Key form,
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
  the iOS Shifts screen uses, plus a "Last Synced: …" line (2026-09-23,
  matching iOS's Shifts/News/Profile footer) and schedules the same local
  notification for it via `NotificationScheduler`. No full shift catalog,
  no news, per "Watch app scope" in [`CLAUDE.md`](../CLAUDE.md). Since the
  2026-09-17 redesign, `NextShiftViewModel` syncs every active instance
  and shows the chronologically nearest upcoming shift across all of them
  (still exactly one shift) — see "Multi-instance concept" in
  [`architecture.md`](architecture.md). After every sync it writes a
  `NextShiftSnapshot` to the shared App Group and reloads the
  complication (`WatchComplicationUpdater`, see "Keep the Watch fresh" in
  [`architecture.md`](architecture.md) — 2026-09-23, factored out so
  every sync trigger keeps the complication current, not just this
  screen's own pull-to-refresh) — see `EngelsystemComplication` below.
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
  (see [`app-store.md`](app-store.md)) and renders `.accessoryCircular`/
  `.accessoryRectangular`/`.accessoryInline` families; never touches the
  network or Keychain itself (a separate process from the Watch app, no
  access to its Keychain item). Confirmed: builds, installs, and launches
  correctly in the watchOS Simulator. Not verified: actually adding it to
  a watch face and seeing it render there, since that requires the
  Watch Face editing UI (no automation available for that flow here).


See [`architecture.md`](architecture.md) for CloudKit sync of `Instance` metadata.
- **Richer demo data (2026-10-12)**: Demo Mode now shows a livelier demo instance for screenshots and trials — 7 shifts over four
  days at 4 locations (Heaven, Chill Space, Workshop Room A, Foodcourt) with 6 shift types, 5 news posts (a pinned
  welcome, a highlighted one with a comment, a Markdown list, two meetings), 3 worklogs, 3 angel types (own memberships:
  confirmed, supporter, unconfirmed) and 3 conversations (Helper Angel unread, Another Angel with the demo user's own reply
  last, Night Shift Nick unread). The first upcoming shift is still "Info Desk Shift" (the Watch's next shift).
- **App Store screenshot generation (2026-10-12)**: `Scripts/screenshots.sh` produces 13 screenshots (iPhone 6.9" ×6, iPad 13"
  landscape ×6, Apple Watch Ultra ×1) from Demo Mode — see `app-store.md` ("Screenshots") and ADR 0011. Debug-only launch
  arguments `-seed-demo-instance` (`DemoSeeding`) and `-skipNotificationPrompt YES` (`NotificationScheduler`); UI test class
  `ScreenshotTests`.

### Compatibility with servers lacking open Engelsystem PRs (2026-10-12, temporary)

Details and the full register: [`architecture.md`](architecture.md#compatibility-workarounds-temporary), ADR 0013.
- News decode without `comments_count`; comments (link, screen) appear only on servers that support them.
- The Locations area is hidden when no active instance lets the account read locations; shift locations then stay plain text;
  a missing `GET /locations/{id}` is a silent no-op.
- "Test Connection" probes a data endpoint and shows an orange warning on 403 (privilege/group wording, saving still allowed).
- Shift reminders are planned whenever the shift syncs succeeded (permanent change, independent of News/Profile failures).

