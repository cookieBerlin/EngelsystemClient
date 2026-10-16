import Foundation

/// How the instance page lays out its "Features" list: collapsed while everything works, open (problems
/// first) as soon as something is missing, not allowed or not checked yet.
public enum FeatureListLayout {
    /// The list starts open unless every function is available.
    public static func startsExpanded(_ states: [FeatureState]) -> Bool {
        states.contains { $0 != .available }
    }

    /// Problems first (not allowed, not offered, not checked yet), then the available ones; the given
    /// order is kept within each group.
    public static func ordered(_ features: [ServerFeature], state: (ServerFeature) -> FeatureState) -> [ServerFeature] {
        func rank(_ state: FeatureState) -> Int {
            switch state {
            case .notAllowed: return 0
            case .notOffered: return 1
            case .unknown: return 2
            case .available: return 3
            }
        }
        return features.enumerated()
            .sorted { (rank(state($0.element)), $0.offset) < (rank(state($1.element)), $1.offset) }
            .map(\.element)
    }
}
