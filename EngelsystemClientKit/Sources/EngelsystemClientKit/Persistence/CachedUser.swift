import Foundation
import SwiftData

@Model
public final class CachedUser {
    // Composite unique key prevents collision across instances with the same server-assigned ID
    @Attribute(.unique) public var uid: String
    public var serverID: Int
    public var instanceID: UUID

    public var name: String
    public var firstName: String?
    public var lastName: String?
    public var pronoun: String?
    public var dect: String?
    public var mobile: String?
    public var url: String

    // Only present for the own account (UserDetail), nil for other users
    public var email: String?
    public var tshirtSize: String?
    public var language: String?
    public var arrived: Bool?
    public var plannedArrival: Date?
    public var plannedDeparture: Date?
    public var arrivalDate: Date?

    public var cachedAt: Date

    @Relationship public var instance: Instance?

    public init(
        serverID: Int,
        instanceID: UUID,
        name: String,
        firstName: String? = nil,
        lastName: String? = nil,
        pronoun: String? = nil,
        dect: String? = nil,
        mobile: String? = nil,
        url: String,
        email: String? = nil,
        tshirtSize: String? = nil,
        language: String? = nil,
        arrived: Bool? = nil,
        plannedArrival: Date? = nil,
        plannedDeparture: Date? = nil,
        arrivalDate: Date? = nil
    ) {
        self.uid = "\(instanceID.uuidString):\(serverID)"
        self.serverID = serverID
        self.instanceID = instanceID
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.pronoun = pronoun
        self.dect = dect
        self.mobile = mobile
        self.url = url
        self.email = email
        self.tshirtSize = tshirtSize
        self.language = language
        self.arrived = arrived
        self.plannedArrival = plannedArrival
        self.plannedDeparture = plannedDeparture
        self.arrivalDate = arrivalDate
        self.cachedAt = Date()
    }
}

public extension CachedUser {
    var displayName: String {
        guard let firstName, let lastName else { return name }
        return "\(firstName) \(lastName)"
    }

    func updateCacheTimestamp() { cachedAt = Date() }
}

// MARK: - Mapping from the generated `UsersIdGet200ResponseData` DTO (own profile)

public extension CachedUser {
    convenience init(profile: UsersIdGet200ResponseData, instanceID: UUID) {
        self.init(
            serverID: profile.id,
            instanceID: instanceID,
            name: profile.name,
            firstName: profile.firstName,
            lastName: profile.lastName,
            pronoun: profile.pronoun,
            dect: profile.contact.dect,
            mobile: profile.contact.mobile,
            url: profile.url,
            email: profile.email,
            tshirtSize: profile.tshirtSize,
            language: profile.language,
            arrived: profile.arrived,
            plannedArrival: profile.dates.plannedArrival,
            plannedDeparture: profile.dates.plannedDeparture,
            arrivalDate: profile.dates.arrival
        )
    }

    /// Updates all fields from a freshly fetched profile DTO (used by `ProfileSyncService`
    /// when a cached row already exists for this user).
    func apply(_ profile: UsersIdGet200ResponseData) {
        name = profile.name
        firstName = profile.firstName
        lastName = profile.lastName
        pronoun = profile.pronoun
        dect = profile.contact.dect
        mobile = profile.contact.mobile
        url = profile.url
        email = profile.email
        tshirtSize = profile.tshirtSize
        language = profile.language
        arrived = profile.arrived
        plannedArrival = profile.dates.plannedArrival
        plannedDeparture = profile.dates.plannedDeparture
        arrivalDate = profile.dates.arrival
        updateCacheTimestamp()
    }

    static func uid(instanceID: UUID, serverID: Int) -> String {
        "\(instanceID.uuidString):\(serverID)"
    }
}
