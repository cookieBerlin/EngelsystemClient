import Foundation
import EngelsystemClientKit

/// The wording and symbols of the instance's "Features" list (ADR 0015) as tested functions.
enum FeaturePresentation {
    static func statusText(_ status: FeatureStatus) -> String {
        switch status.state {
        case .available: return "Available"
        case .notAllowed:
            if let privilege = status.privilege { return "Not allowed for this account (needs “\(privilege)”)" }
            return "Not allowed for this account"
        case .notOffered: return "Not offered by this server"
        case .unknown: return "Not checked yet"
        }
    }

    static func systemImage(_ status: FeatureStatus) -> String {
        switch status.state {
        case .available: return "checkmark.circle.fill"
        case .notAllowed: return "lock.circle"
        case .notOffered: return "minus.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    static func summaryText(available: Int, total: Int) -> String {
        "\(available) of \(total) features available"
    }

    /// "Checked: 5 minutes ago", or nil when nothing was recorded yet.
    static func checkedText(_ status: FeatureStatus, now: Date = Date()) -> String? {
        guard let checkedAt = status.checkedAt else { return nil }
        return "Checked " + checkedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
