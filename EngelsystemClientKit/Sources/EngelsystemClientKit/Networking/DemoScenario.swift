import Foundation

/// The data sets of Demo Mode. Any `demo://<host>` address is a demo instance; the host picks the data. Two
/// demo instances with the same host count as one server (two accounts), different hosts as different
/// servers.
public enum DemoScenario: String, CaseIterable, Sendable {
    /// The classic demo data.
    case main = "engelsystem.local"
    /// A second event with its own shifts, locations and news.
    case congress = "congress.local"

    public static let scheme = "demo://"

    /// The scenario an address belongs to; nil for anything that is not a known `demo://` address. Works for
    /// the instance's base URL and for the API base URL (path behind the host).
    public init?(baseURL: String) {
        guard baseURL.hasPrefix(Self.scheme) else { return nil }
        let host = baseURL.dropFirst(Self.scheme.count).prefix { $0 != "/" }.lowercased()
        guard let scenario = DemoScenario(rawValue: host) else { return nil }
        self = scenario
    }

    public var baseURL: String { Self.scheme + rawValue }
}
