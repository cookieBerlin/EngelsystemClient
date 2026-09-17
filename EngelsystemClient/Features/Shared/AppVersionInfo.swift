import Foundation

/// Reads the marketing version, build number, and git commit hash from the app's own
/// `Info.plist` for display at the bottom of `SettingsView` — lets a specific installed
/// build be identified at a glance (e.g. when comparing notes about a bug). The build
/// number auto-increments only when archiving (see CLAUDE.md's Entitlements section);
/// `GitCommitHash` is written into every build, Debug included, by the "Embed Git
/// Commit Hash" build phase.
enum AppVersionInfo {
    static var displayString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var text = "Version \(version) (\(build))"
        if let hash = info?["GitCommitHash"] as? String, !hash.isEmpty, hash != "unknown" {
            text += " · \(hash)"
        }
        return text
    }
}
