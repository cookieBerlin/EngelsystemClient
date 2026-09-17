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
struct MainView: View {
    let instances: [Instance]

    @State private var selection: Section? = .shifts

    private enum Section: String, CaseIterable, Identifiable {
        case shifts, news, profile, settings

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

    private var navigationTitle: String {
        switch activeInstances.count {
        case 0: return "No Active Instance"
        case 1: return activeInstances[0].name
        default: return "\(activeInstances.count) Active Instances"
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle(navigationTitle)
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
