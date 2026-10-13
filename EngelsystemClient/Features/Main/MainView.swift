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
        _selection = State(initialValue: Self.initialSelection(
            fromStoredRawValue: storedRawValue,
            hasActiveInstances: instances.contains(where: \.isActive),
            visibleSections: Section.visibleSidebarCases(forActiveInstances: instances.filter(\.isActive))
        ))
    }

    /// Resolves the section to start on from a raw stored value — `nil` (never
    /// stored yet) or anything unrecognized (a raw value from a future version, say)
    /// yields no selection at all (2026-10-12, user-requested: the default is the main
    /// page — the sidebar list — not the Shifts screen). A `static` pure function, not inlined into `init`, so
    /// it's unit-testable (`EngelsystemClientTests.MainViewLastSelectedSectionTests`)
    /// without touching `UserDefaults` at all.
    /// Also yields no selection when no instance is active (2026-10-12, user-requested):
    /// without data to show, the sidebar (with its empty state) is always the landing
    /// page, whatever was open last.
    ///
    /// A stored section that is not available any more (Messages or Locations on a server that
    /// does not offer them) also yields no selection — the main page, never another section
    /// (2026-10-13, user-requested).
    static func initialSelection(
        fromStoredRawValue rawValue: String?, hasActiveInstances: Bool, visibleSections: [Section]
    ) -> Section? {
        guard hasActiveInstances else { return nil }
        return resolvedSelection(rawValue.flatMap(Section.init(rawValue:)), visibleSections: visibleSections)
    }

    /// Whether a given selection should actually be persisted as "the last selected
    /// section" — only the sidebar's own data sections, never `.settings` (see the
    /// type-level doc comment above for why). Same testability rationale as
    /// `initialSelection`.
    static func shouldPersistAsLastSelectedSection(_ section: Section) -> Bool {
        Section.sidebarCases.contains(section)
    }

    enum Section: String, CaseIterable, Identifiable {
        case shifts, news, profile, locations, messages, settings

        /// Every row that can be persisted as "the last selected section" — excludes
        /// `.settings` (see the type-level doc comment above). `.messages` is included
        /// here even though it's only ever *rendered* conditionally (see
        /// `visibleSidebarCases(forActiveInstances:)` below) — a previously-selected
        /// `.messages` is still a legitimate value to have persisted, it just may not
        /// currently be visible (handled by `resolvedSelection(_:visibleSections:)`).
        static let sidebarCases: [Section] = [.news, .messages, .shifts, .locations, .profile]

        /// The sidebar's groups (2026-10-13, user-requested): News and Messages under
        /// "Communication", Shifts and Locations under "Event", Profile under "Account".
        enum SidebarGroup: CaseIterable, Identifiable {
            case communication, event, account

            var id: Self { self }

            var title: String {
                switch self {
                case .communication: return "Communication"
                case .event: return "Event"
                case .account: return "Account"
                }
            }

            var sections: [Section] {
                switch self {
                case .communication: return [.news, .messages]
                case .event: return [.shifts, .locations]
                case .account: return [.profile]
                }
            }
        }

        struct SidebarGroupContent: Identifiable, Equatable {
            let group: SidebarGroup
            let sections: [Section]

            var id: SidebarGroup { group }
        }

        /// The visible sections split into their groups, in sidebar order; a group without any
        /// visible section is left out (so its heading disappears too).
        static func groupedForSidebar(_ visible: [Section]) -> [SidebarGroupContent] {
            SidebarGroup.allCases.compactMap { group in
                let sections = group.sections.filter { visible.contains($0) }
                return sections.isEmpty ? nil : SidebarGroupContent(group: group, sections: sections)
            }
        }

        /// The subset of `sidebarCases` actually rendered as rows, given which
        /// instances are active — `.messages` only shows up once at least one active
        /// instance's server actually supports it (2026-09-23, Messages feature:
        /// "if the instance doesn't offer the new interface, don't show the GUI").
        static func visibleSidebarCases(
            forActiveInstances activeInstances: [Instance],
            capabilities: ServerCapabilities = .shared
        ) -> [Section] {
            // COMPAT(#1711): `.locations` additionally needs at least one active instance whose
            // server lets this account read the locations list (no instances: nothing to hide).
            let locationsVisible = activeInstances.isEmpty
                || capabilities.isAvailable(.locationsList, forAnyOf: activeInstances.map(\.id))
            return sidebarCases.filter { section in
                switch section {
                // COMPAT(#1720): Messages only where the server offers the messages API.
                case .messages: return activeInstances.contains(where: \.messagesSupported)
                case .locations: return locationsVisible
                default: return true
                }
            }
        }

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shifts: return "Shifts"
            case .news: return "News"
            case .profile: return "Profile"
            case .locations: return "Locations"
            case .messages: return "Messages"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .shifts: return "calendar"
            case .news: return "newspaper"
            case .profile: return "person.crop.circle"
            case .locations: return "mappin.and.ellipse"
            case .messages: return "message"
            case .settings: return "gearshape"
            }
        }
    }

    /// What to actually show given the current `selection` and which sections are
    /// currently visible — nil (the main page) when nothing is selected or the selected
    /// section has become unavailable (e.g. `.messages` selected, then the one instance that
    /// supported it was deactivated); never another section (2026-10-13, user-requested).
    /// `.settings` is always reachable via the toolbar gear regardless of active instances.
    /// A `static` pure function, not inlined into `body`, for the same testability reasoning
    /// as `initialSelection`/`navigationTitle` above.
    static func resolvedSelection(_ selection: Section?, visibleSections: [Section]) -> Section? {
        guard let selection else { return nil }
        return selection == .settings || visibleSections.contains(selection) ? selection : nil
    }

    private var activeInstances: [Instance] { instances.filter(\.isActive) }
    private var visibleSidebarSections: [Section] { Section.visibleSidebarCases(forActiveInstances: activeInstances) }

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
                    ForEach(Section.groupedForSidebar(visibleSidebarSections)) { content in
                        SwiftUI.Section(content.group.title) {
                            ForEach(content.sections) { section in
                                Label(section.title, systemImage: section.systemImage).tag(section)
                            }
                        }
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
                if let resolved = Self.resolvedSelection(selection, visibleSections: visibleSidebarSections) {
                    switch resolved {
                    case .shifts:
                        ShiftsView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                    case .news:
                        NewsView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                    case .profile:
                        ProfileView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                    case .locations:
                        LocationsView(instances: activeInstances, syncStatus: syncStatus, onUnauthorized: goToSettings)
                    case .messages:
                        // COMPAT(#1720)
                        MessagesView(instances: activeInstances.filter(\.messagesSupported), syncStatus: syncStatus, onUnauthorized: goToSettings)
                    case .settings:
                        SettingsView(instances: instances)
                    }
                } else {
                    // Nothing chosen, or the chosen section is not available (iPad/Mac-style wide
                    // layouts; on iPhone the sidebar list itself is the visible main page).
                    ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
                }
            }
        }
        .onChange(of: visibleSidebarSections) { _, visible in
            // A section that disappears (its server stopped offering it) sends the app back to the
            // main page instead of leaving an empty detail screen.
            if Self.resolvedSelection(selection, visibleSections: visible) == nil { selection = nil }
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
        guard MainSyncStatus.shouldRunStartSync(
            syncOnAppStartEnabled: DeviceSyncPreferences.syncOnAppStartEnabled(),
            activeInstanceCount: activeInstances.count
        ) else { return }
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
