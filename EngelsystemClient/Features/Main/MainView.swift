import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Root view once at least one instance is configured. A single `NavigationSplitView`
/// with a sidebar of feature sections — not a plain `TabView` on iPad, per CLAUDE.md —
/// that collapses to stack navigation on iPhone automatically.
///
/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): any number of instances can
/// be active at once (`Instance.isActive`), so there's no single `activeInstanceID`
/// anymore — Shifts/News/Profile each receive every active instance and aggregate
/// across them (see `MultiInstanceDisplayMode`).
///
/// Settings is deliberately **not** one of the sidebar rows (2026-09-17) — it's reached
/// via a gear icon in the sidebar's own toolbar corner instead, since it's app
/// configuration rather than a data section on the same level as Shifts/News/Profile.
/// `Section.settings` still exists as a `selection` value (so `goToSettings()`'s
/// 401-triggers-navigation behavior keeps working unchanged), it's just excluded from
/// `Section.sidebarCases`, the list of rows the sidebar actually renders.
struct MainView: View {
    let instances: [Instance]

    /// Resumes on whichever *data* section (Shifts/News/Profile) was last selected,
    /// instead of always starting on Shifts (2026-09-22, user-requested). Deliberately
    /// never remembers `.settings` itself — it's reached via a one-off gear tap or the
    /// 401-triggered `goToSettings()`, not something to relaunch straight into (that
    /// would be surprising after an auto-redirect that had nothing to do with a
    /// deliberate choice to browse Settings). `@AppStorage` can't seed another
    /// property's `@State` default value directly, so the initial value is read from
    /// `UserDefaults` by hand in `init` instead — `@AppStorage`'s own default (`.shifts`)
    /// only applies once something actually writes to the key for the first time.
    private static let lastSelectedSectionKey = "mainViewLastSelectedSection"

    @AppStorage(Self.lastSelectedSectionKey) private var lastSelectedSectionRaw: String = Section.shifts.rawValue
    @State private var selection: Section?
    @Environment(\.modelContext) private var modelContext
    @State private var syncStatus = MainSyncStatus()

    init(instances: [Instance]) {
        self.instances = instances
        let storedRawValue = UserDefaults.standard.string(forKey: Self.lastSelectedSectionKey)
        _selection = State(initialValue: Self.initialSelection(fromStoredRawValue: storedRawValue))
    }

    /// Resolves the section to start on from a raw stored value — `nil` (never
    /// stored yet) or anything unrecognized (a raw value from a future version, say)
    /// falls back to `.shifts`. A `static` pure function, not inlined into `init`, so
    /// it's unit-testable (`EngelsystemClientTests.MainViewLastSelectedSectionTests`)
    /// without touching `UserDefaults` at all.
    static func initialSelection(fromStoredRawValue rawValue: String?) -> Section {
        rawValue.flatMap(Section.init(rawValue:)) ?? .shifts
    }

    /// Whether a given selection should actually be persisted as "the last selected
    /// section" — only the sidebar's own data sections, never `.settings` (see the
    /// type-level doc comment above for why). Same testability rationale as
    /// `initialSelection`.
    static func shouldPersistAsLastSelectedSection(_ section: Section) -> Bool {
        Section.sidebarCases.contains(section)
    }

    enum Section: String, CaseIterable, Identifiable {
        case shifts, news, profile, settings

        /// Rows shown in the sidebar list — excludes `.settings`, reached via the gear
        /// toolbar button instead.
        static let sidebarCases: [Section] = [.shifts, .news, .profile]

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shifts: return "Shifts"
            case .news: return "News"
            case .profile: return "Profile"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .shifts: return "calendar"
            case .news: return "newspaper"
            case .profile: return "person.crop.circle"
            case .settings: return "gearshape"
            }
        }
    }

    private var activeInstances: [Instance] { instances.filter(\.isActive) }

    /// Only shows the one active instance's own name — no instance-count text
    /// (2026-09-22, user-requested: a plural "N Active Instances" title was removed;
    /// the zero-active case no longer needs a title of its own either, since the
    /// sidebar shows a dedicated empty state instead of the section list then, see
    /// `body` below). A `static` pure function, not a `private` computed property, so
    /// it's unit-testable via `@testable import EngelsystemClient` without needing to
    /// construct a full `MainView` and drive its `body` — `EngelsystemClientTests
    /// .MainViewNavigationTitleTests` covers all three cases (zero/one/many).
    static func navigationTitle(forActiveInstances activeInstances: [Instance]) -> String {
        activeInstances.count == 1 ? activeInstances[0].name : "Engelsystem"
    }

    var body: some View {
        NavigationSplitView {
            // The sidebar's top-level content must stay an actual `List(selection:)`
            // at all times — 2026-09-22, user-reported: an earlier version replaced it
            // entirely with a `ContentUnavailableView` whenever there were no active
            // instances, which broke navigation to Settings from *both* the "Add
            // Instance" button and the toolbar gear icon. Root cause:
            // `NavigationSplitView`'s automatic column push on compact width (iPhone)
            // in response to a `selection` change only fires when the sidebar's own
            // content is the `List` that binding belongs to — swapping the sidebar to
            // a non-`List` view for the empty state meant nothing was left to make
            // that push happen, even though `selection` itself still updated
            // correctly and `detail:` below re-rendered (just never became visible).
            // Fixed by always keeping the same `List(selection: $selection)`, only
            // changing which rows it shows.
            List(selection: $selection) {
                if activeInstances.isEmpty {
                    // `SwiftUI.Section` spelled out: the file's own `Section` enum
                    // (feature-selection cases) would otherwise shadow it here.
                    SwiftUI.Section {
                        Label("No Active Instance", systemImage: "tray")
                            .foregroundStyle(.secondary)
                        Button("Add Instance") { goToSettings() }
                    }
                } else {
                    ForEach(Section.sidebarCases) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                }
            }
            .navigationTitle(Self.navigationTitle(forActiveInstances: activeInstances))
            .toolbar {
                ToolbarItem {
                    Button {
                        selection = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            // Pull-to-refresh on the main page itself (2026-09-22, user-requested),
            // separate from each screen's own — runs the same full multi-domain sync
            // as the app-start sync, regardless of the "Sync on App Start" toggle
            // (pull-to-refresh is always an explicit user action, per CLAUDE.md's
            // "pull-to-refresh keeps working regardless" rule for this feature).
            .refreshable { await runFullSync() }
        } detail: {
            NavigationStack {
                switch selection ?? .shifts {
                case .shifts:
                    ShiftsView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                case .news:
                    NewsView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                case .profile:
                    ProfileView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                case .settings:
                    SettingsView(instances: instances)
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue, Self.shouldPersistAsLastSelectedSection(newValue) else { return }
            lastSelectedSectionRaw = newValue.rawValue
        }
        .overlay(alignment: .top) {
            if syncStatus.isSyncing {
                SyncProgressBanner(
                    statusText: syncStatus.statusText,
                    fraction: syncStatus.fraction,
                    total: syncStatus.total,
                    didFail: syncStatus.didFail
                )
            }
        }
        .task { await runAppStartSyncIfNeeded() }
    }

    /// One-shot per app launch (2026-09-22, user-requested, to reduce server load —
    /// see CLAUDE.md's polling-interval/background-sync feature): replaces the old
    /// per-screen "sync every time you open Shifts/News/Profile" behavior. Togglable
    /// in Settings (`DeviceSyncPreferences`, per-device, not CloudKit-synced — this is
    /// a "do it on *this* device" convenience, unlike the polling interval itself).
    private func runAppStartSyncIfNeeded() async {
        guard DeviceSyncPreferences.syncOnAppStartEnabled() else { return }
        await runFullSync()
    }

    /// The actual multi-domain sync + progress reporting, shared by the app-start
    /// sync above and the main page's own pull-to-refresh (2026-09-22,
    /// user-requested). Deliberately headless about errors (no banner, no
    /// `goToSettings()` on 401) — there's no *specific* screen the user is looking at
    /// to react to here (unlike Shifts/News/Profile's own pull-to-refresh, which still
    /// surfaces those normally); `SyncProgressBanner` is purely a "something is
    /// happening" indicator, not an error-reporting UI.
    private func runFullSync() async {
        guard !activeInstances.isEmpty else { return }
        await syncStatus.runCoordinated { onProgress in
            await AppSyncCoordinator().syncEverything(
                instances: activeInstances,
                in: modelContext,
                onProgress: onProgress
            )
        }
    }

    /// CLAUDE.md's error-handling contract ("401 → back to Instance Setup") realized as
    /// "back to Settings", where "Update API Key" can actually fix an expired/revoked key.
    private func goToSettings() {
        selection = .settings
    }
}
