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

    @State private var selection: Section? = .shifts

    private enum Section: String, CaseIterable, Identifiable {
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
        } detail: {
            NavigationStack {
                switch selection ?? .shifts {
                case .shifts:
                    ShiftsView(instances: activeInstances, onUnauthorized: goToSettings)
                case .news:
                    NewsView(instances: activeInstances, onUnauthorized: goToSettings)
                case .profile:
                    ProfileView(instances: activeInstances, onUnauthorized: goToSettings)
                case .settings:
                    SettingsView(instances: instances)
                }
            }
        }
    }

    /// CLAUDE.md's error-handling contract ("401 → back to Instance Setup") realized as
    /// "back to Settings", where "Update API Key" can actually fix an expired/revoked key.
    private func goToSettings() {
        selection = .settings
    }
}
