import Foundation

/// What the shift detail page shows, derived from the cached shift (ADR 0015, backlog S-02 – S-04).
/// Pure value logic so the page itself stays layout: every text and decision is tested here. Fields
/// a server does not send are simply absent — nothing is guessed except the documented "usually 3
/// hours" sign-out rule, which is marked as an assumption.
public struct ShiftDetail: Equatable {
    public struct Member: Equatable {
        public let name: String
        public let isOwn: Bool
        /// Marked as "did not show up" (`freeloaded`; COMPAT(#1723): `freeloaded_by != null` without it).
        public let didNotShow: Bool
        /// Who marked it, only when the server tells (admins/supporters).
        public let markedBy: String?
        public let comment: String?
    }

    public struct TeamGroup: Equatable {
        public let angelTypeName: String
        public let needs: Int
        public let members: [Member]

        /// "2 of 3", or the plain count for overbooked types and types with only additional entries.
        public var occupancyText: String {
            if needs > 0, members.count <= needs { return "\(members.count) of \(needs)" }
            return needs > 0 ? "\(members.count) (needs \(needs))" : "\(members.count)"
        }
    }

    public struct SignOut: Equatable {
        public let deadline: Date
        /// The deadline is the documented default, not a value from the server (COMPAT(#1722)).
        public let isAssumed: Bool
        public let isOpen: Bool
        /// Where the shift can be left (the app never signs out by itself); nil without a usable URL.
        public let browserURL: URL?
    }

    /// Teams longer than this collapse to the own entry plus a "show all" row.
    public static let collapsedMemberLimit = 10
    /// The default of upstream's `last_unsubscribe` setting, used when the server does not tell.
    public static let assumedSignOutLeadTime: TimeInterval = 3 * 3600

    public let title: String
    public let shiftTypeName: String?
    public let shiftTypeDescription: String?
    public let description: String?
    public let startsAt: Date
    public let endsAt: Date
    public let locationName: String?
    public let tags: [String]
    public let isNightShift: Bool
    public let talkURL: URL?
    /// Only while sign-up has not opened yet.
    public let signupAvailableFrom: Date?
    public let team: [TeamGroup]
    public let signOut: SignOut?
    /// The own entry is signed up for this shift.
    public let isOwnShift: Bool

    public var duration: TimeInterval { endsAt.timeIntervalSince(startsAt) }

    /// "3 h" or "1 h 30 min".
    public var durationText: String {
        let minutes = Int((duration / 60).rounded())
        let (hours, rest) = (minutes / 60, minutes % 60)
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }

    public init(shift: CachedShift, ownUserID: Int?, now: Date = Date()) {
        title = shift.title
        shiftTypeName = Self.nonEmpty(shift.shiftTypeName)
        shiftTypeDescription = Self.nonEmpty(shift.shiftTypeDescription)
        description = Self.nonEmpty(shift.shiftDescription)
        startsAt = shift.startsAt
        endsAt = shift.endsAt
        locationName = Self.nonEmpty(shift.locationName)
        tags = shift.tags
        isNightShift = shift.nightShift == true
        talkURL = Self.webURL(shift.talkURL)
        signupAvailableFrom = shift.signupAvailableFrom.flatMap { $0 > now ? $0 : nil }

        team = shift.team.map { needed in
            TeamGroup(
                angelTypeName: needed.angelType.name ?? "Unknown",
                needs: needed.needs,
                members: needed.entries.map { entry in
                    Member(
                        name: entry.user.name ?? "Unknown",
                        isOwn: entry.user.id == ownUserID,
                        didNotShow: entry.freeloaded ?? (entry.freeloadedBy != nil), // COMPAT(#1723)
                        markedBy: entry.freeloadedBy?.name,
                        comment: Self.nonEmpty(entry.freeloadedComment)
                    )
                }
            )
        }

        let own = ownUserID.flatMap { shift.ownEntry(userID: $0) }
        isOwnShift = own != nil
        if let own {
            let known = shift.signOutUntil
            let deadline = known ?? shift.startsAt.addingTimeInterval(-Self.assumedSignOutLeadTime)
            // COMPAT(#1723): without `can_sign_out` the deadline alone decides.
            let open = (own.entry.canSignOut ?? true) && deadline > now && shift.endsAt > now
            signOut = SignOut(
                deadline: deadline, isAssumed: known == nil, isOpen: open, browserURL: Self.webURL(shift.url))
        } else {
            signOut = nil
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Only `http`/`https` links are ever opened.
    private static func webURL(_ text: String?) -> URL? {
        guard let text = nonEmpty(text), let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }
}
