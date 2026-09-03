import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Root view once at least one instance is configured. A single `NavigationSplitView`
/// with a sidebar of feature sections — not a plain `TabView` on iPad, per CLAUDE.md —
/// that collapses to stack navigation on iPhone automatically.
struct MainView: View {
    @AppStorage("activeInstanceID") private var activeInstanceIDString: String = ""

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

    /// There's always at least one instance while `MainView` is shown (see `ContentView`);
    /// falls back to the first instance if the stored active ID doesn't match any of them.
    private var activeInstance: Instance {
        instances.first(where: { $0.id.uuidString == activeInstanceIDString }) ?? instances[0]
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle(activeInstance.name)
        } detail: {
            NavigationStack {
                switch selection ?? .shifts {
                case .shifts:
                    ShiftsView(instance: activeInstance, onUnauthorized: goToSettings)
                case .news:
                    NewsView(instance: activeInstance, onUnauthorized: goToSettings)
                case .profile:
                    ProfileView(instance: activeInstance, onUnauthorized: goToSettings)
                case .settings:
                    SettingsView(instances: instances)
                }
            }
        }
        .onAppear { activateFirstInstanceIfNeeded() }
    }

    private func activateFirstInstanceIfNeeded() {
        guard activeInstanceIDString.isEmpty, let first = instances.first else { return }
        activeInstanceIDString = first.id.uuidString
    }

    /// CLAUDE.md's error-handling contract ("401 → back to Instance Setup") realized as
    /// "back to Settings", where "Update API Key" can actually fix an expired/revoked key.
    private func goToSettings() {
        selection = .settings
    }
}
