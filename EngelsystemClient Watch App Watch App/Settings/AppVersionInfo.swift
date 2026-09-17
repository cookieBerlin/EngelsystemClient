import Foundation

/// Watch equivalent of the iOS app's `AppVersionInfo` (`Features/Shared`) — duplicated
/// rather than shared because `Bundle.main` resolves to each target's own bundle, and
/// this type lives in the app target, not `EngelsystemClientKit`.
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
