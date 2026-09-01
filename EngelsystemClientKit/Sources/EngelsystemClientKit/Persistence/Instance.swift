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
    }
}

public extension Instance {
    func touch() { updatedAt = Date() }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var apiBasePath: String { "\(normalizedBaseURL)/api/v0-beta" }
}
