import SwiftUI
import EngelsystemClientKit

/// Settings page "About": version and build, plus the project's published pages.
struct AboutSettingsView: View {
    static let siteURL = URL(string: "https://cookieberlin.github.io/EngelsystemClient/")!
    static let privacyPolicyURL = URL(string: "https://cookieberlin.github.io/EngelsystemClient/privacy")!
    static let supportURL = URL(string: "https://cookieberlin.github.io/EngelsystemClient/support")!
    static let guideURL = URL(string: "https://cookieberlin.github.io/EngelsystemClient/guide")!
    static let sourceURL = URL(string: "https://github.com/cookieBerlin/EngelsystemClient")!

    var body: some View {
        List {
            Section {
                Text(AppVersionInfo.displayString)
            }
            Section("Links") {
                Link(destination: Self.guideURL) { Label("User Guide", systemImage: "book") }
                Link(destination: Self.supportURL) { Label("Support", systemImage: "questionmark.circle") }
                Link(destination: Self.privacyPolicyURL) { Label("Privacy Policy", systemImage: "hand.raised") }
                Link(destination: Self.sourceURL) { Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
        }
        .navigationTitle("About")
    }
}
