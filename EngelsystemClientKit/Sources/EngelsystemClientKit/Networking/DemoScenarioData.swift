import Foundation

/// The parts of the demo data that differ per `DemoScenario`: event info, news, locations and shifts. The
/// classic scenario returns the original data unchanged.
extension DemoData {
    static let congressLocations: [Location] = [
        Location(id: 1, name: "Hall A", description: "Main stage and keynotes", mapUrl: nil,
                 contact: ContactDect(dect: "2001"), url: "https://congress.demo.engelsystem.local/locations/1"),
        Location(id: 2, name: "Hall B", description: "Talks and panels", mapUrl: nil,
                 contact: ContactDect(dect: nil), url: "https://congress.demo.engelsystem.local/locations/2"),
        Location(id: 3, name: "Lounge", description: "Quiet corner with power outlets", mapUrl: nil,
                 contact: ContactDect(dect: "2003"), url: "https://congress.demo.engelsystem.local/locations/3"),
        Location(id: 4, name: "Kitchen", description: "Helper catering", mapUrl: nil,
                 contact: ContactDect(dect: "2004"), url: "https://congress.demo.engelsystem.local/locations/4"),
    ]

    /// What an unknown demo address shows: one news post naming the addresses that work.
    static var unknownAddressText: String {
        "This demo address is not known. Use one of these instead: "
            + DemoScenario.supportedAddresses.joined(separator: ", ") + "."
    }

    private static var unknownAddressNews: NewsDetail {
        let now = Date()
        return NewsDetail(
            id: 1, name: "Unknown demo address", text: unknownAddressText, isMeeting: false, isPinned: true,
            isHighlighted: true, createdAt: now, updatedAt: nil,
            url: "https://demo.engelsystem.local/news/1", commentsCount: nil, comments: [])
    }

    static func info(for scenario: DemoScenario) -> EventInfo {
        var result = info
        switch scenario {
        case .main: break
        case .congress:
            result.name = "Demo Congress 2"
            result.url = "https://congress.demo.engelsystem.local"
        case .unknown:
            result.name = "Unknown demo address"
        }
        return result
    }

    static func news(for scenario: DemoScenario) -> [News] {
        switch scenario {
        case .main:
            return news
        case .congress:
            return news.map { item in
                var copy = item
                copy.name = "Congress: " + item.name
                return copy
            }
        case .unknown:
            let post = unknownAddressNews
            return [News(
                id: post.id, name: post.name, text: post.text, isMeeting: post.isMeeting, isPinned: post.isPinned,
                isHighlighted: post.isHighlighted, createdAt: post.createdAt, updatedAt: post.updatedAt,
                url: post.url, commentsCount: post.commentsCount)]
        }
    }

    static func newsDetail(id: Int, for scenario: DemoScenario) -> NewsDetail? {
        if scenario == .unknown { return id == unknownAddressNews.id ? unknownAddressNews : nil }
        guard var detail = newsDetail(id: id) else { return nil }
        if scenario == .congress { detail.name = "Congress: " + detail.name }
        return detail
    }

    static func locations(for scenario: DemoScenario) -> [Location] {
        switch scenario {
        case .main: return locations
        case .congress: return congressLocations
        case .unknown: return []
        }
    }

    static func location(id: Int, for scenario: DemoScenario) -> Location? {
        locations(for: scenario).first { $0.id == id }
    }

    static func shifts(for scenario: DemoScenario) -> [Shift] {
        if scenario == .unknown { return [] }
        guard scenario == .congress else { return shifts }
        return shifts.map { shift in
            var copy = shift
            copy.name = "Congress: " + shift.name
            // Keep the location's id, show the congress room of that id.
            copy.location = Reference(id: shift.location.id, name: congressLocations.first { $0.id == shift.location.id }?.name)
            return copy
        }
    }
}
