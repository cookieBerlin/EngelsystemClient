import Foundation
import SwiftData

@Model
public final class Instance {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var baseURL: String
    // Stores only the Keychain reference key, never the API key itself
    public var apiKeyKeychainRef: String
    // Fallback for servers that 404 on the documented `self` path parameter alias
    // (confirmed to happen on at least one real, older Engelsystem deployment) —
    // nil means "use `self`", the default and normal case. See `userReference` below.
    public var userID: Int?
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

    @Relationship(deleteRule: .cascade, inverse: \CachedAngelTypeMembership.instance)
    public var cachedAngelTypeMemberships: [CachedAngelTypeMembership]?

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKeyKeychainRef: String,
        userID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.userID = userID
        self.createdAt = Date()
        self.updatedAt = Date()
        self.cachedShifts = []
        self.cachedNews = []
        self.cachedUsers = []
        self.cachedWorklogs = []
        self.cachedAngelTypeMemberships = []
    }
}

public extension Instance {
    func touch() { updatedAt = Date() }

    static func normalizedBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func apiBasePath(for baseURL: String) -> String {
        "\(normalizedBaseURL(baseURL))/api/v0-beta"
    }

    var normalizedBaseURL: String { Instance.normalizedBaseURL(baseURL) }

    var apiBasePath: String { Instance.apiBasePath(for: baseURL) }

    /// Sentinel base URL recognized by `APIClient` — an instance using this URL never
    /// makes real network requests; `APIClient` returns static mock data instead
    /// (see `DemoData`). Lets the app be tried out without a real server or API key.
    static let demoBaseURL = "demo://engelsystem.local"

    var isDemo: Bool { normalizedBaseURL == Instance.demoBaseURL }

    /// How to address "myself" in `/users/{id}/...` API calls — `self` unless a
    /// numeric fallback `userID` has been set for a server that doesn't support that
    /// alias (see `userID` above).
    var userReference: UserReference {
        userID.map { .id($0) } ?? .me
    }
}
