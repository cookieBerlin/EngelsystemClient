import Foundation
import SwiftData

@Model
public final class Instance {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var baseURL: String
    // Stores only the Keychain reference key, never the API key itself
    public var apiKeyKeychainRef: String
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CachedShift.instance)
    public var cachedShifts: [CachedShift]?

    @Relationship(deleteRule: .cascade, inverse: \CachedNews.instance)
    public var cachedNews: [CachedNews]?

    @Relationship(deleteRule: .cascade, inverse: \CachedUser.instance)
    public var cachedUsers: [CachedUser]?

    @Relationship(deleteRule: .cascade, inverse: \CachedWorklog.instance)
    public var cachedWorklogs: [CachedWorklog]?

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKeyKeychainRef: String
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.createdAt = Date()
        self.updatedAt = Date()
        self.cachedShifts = []
        self.cachedNews = []
        self.cachedUsers = []
        self.cachedWorklogs = []
    }
}

public extension Instance {
    func touch() { updatedAt = Date() }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var apiBasePath: String { "\(normalizedBaseURL)/api/v0-beta" }

    /// Sentinel base URL recognized by `APIClient` — an instance using this URL never
    /// makes real network requests; `APIClient` returns static mock data instead
    /// (see `DemoData`). Lets the app be tried out without a real server or API key.
    static let demoBaseURL = "demo://engelsystem.local"

    var isDemo: Bool { normalizedBaseURL == Instance.demoBaseURL }
}
