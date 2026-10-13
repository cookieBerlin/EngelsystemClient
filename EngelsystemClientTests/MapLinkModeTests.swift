import Foundation
import Testing
@testable import EngelsystemClient

struct MapLinkModeTests {
    @Test func storedValueFallsBackToEmbedded() {
        #expect(MapLinkMode.stored(raw: "embedded") == .embedded)
        #expect(MapLinkMode.stored(raw: "linkOnly") == .linkOnly)
        #expect(MapLinkMode.stored(raw: "nonsense") == .embedded)
        #expect(MapLinkMode.stored(raw: "") == .embedded)
    }

    @Test func titlesAreDistinctAndIdentifiable() {
        #expect(MapLinkMode.linkOnly.title == "Link Only")
        #expect(MapLinkMode.embedded.title == "Link and Embedded Map")
        #expect(Set(MapLinkMode.allCases.map(\.id)).count == MapLinkMode.allCases.count)
    }

    @Test func onlyWebAddressesAreEmbeddable() {
        #expect(MapLinkMode.embeddableURL("https://maps.example/venue") != nil)
        #expect(MapLinkMode.embeddableURL("HTTP://maps.example/venue") != nil)
        #expect(MapLinkMode.embeddableURL(nil) == nil)
        #expect(MapLinkMode.embeddableURL("") == nil)
        #expect(MapLinkMode.embeddableURL("file:///etc/passwd") == nil)
        #expect(MapLinkMode.embeddableURL("javascript:alert(1)") == nil)
        #expect(MapLinkMode.embeddableURL("maps://?q=venue") == nil)
        #expect(MapLinkMode.embeddableURL("https://") == nil)
    }

    @Test func navigationIsLimitedToWebAddresses() {
        #expect(MapLinkMode.allowsNavigation(to: URL(string: "https://maps.example/x")))
        #expect(!MapLinkMode.allowsNavigation(to: URL(string: "tel:123")))
        #expect(!MapLinkMode.allowsNavigation(to: nil))
    }

    @Test func onlyWebAddressesStayInTheEmbeddedView() {
        #expect(MapLinkMode.navigationDecision(to: URL(string: "https://maps.google.com/?q=venue")) == .allow)
        #expect(MapLinkMode.navigationDecision(to: URL(string: "comgooglemaps://?q=venue")) == .cancel)
        #expect(MapLinkMode.navigationDecision(to: nil) == .cancel)
    }

    @Test func automaticCleanupIsDueAfterTheChosenNumberOfDays() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let day = 86_400.0
        #expect(!MapWebsiteDataRetention.isDue(lastCleanup: nil, days: 30, now: now))
        #expect(!MapWebsiteDataRetention.isDue(lastCleanup: now.addingTimeInterval(-100 * day), days: 0, now: now))
        #expect(!MapWebsiteDataRetention.isDue(lastCleanup: now.addingTimeInterval(-29 * day), days: 30, now: now))
        #expect(MapWebsiteDataRetention.isDue(lastCleanup: now.addingTimeInterval(-30 * day), days: 30, now: now))
        #expect(MapWebsiteDataRetention.isDue(lastCleanup: now.addingTimeInterval(-8 * day), days: 7, now: now))
        #expect(MapWebsiteDataRetention.title(days: 0) == "Never")
        #expect(MapWebsiteDataRetention.title(days: 30) == "Every 30 Days")
        #expect(MapWebsiteDataRetention.title(days: MapWebsiteDataRetention.untilAppQuits) == "Until the App Quits")
        #expect(MapWebsiteDataRetention.keepsDataOnlyInMemory(days: -1))
        #expect(!MapWebsiteDataRetention.keepsDataOnlyInMemory(days: 30))
        #expect(!MapWebsiteDataRetention.keepsDataOnlyInMemory(days: 0))
        #expect(!MapWebsiteDataRetention.isDue(lastCleanup: Date.distantPast, days: -1, now: Date()))
        #expect(MapWebsiteDataRetention.choices.contains(MapWebsiteDataRetention.defaultDays))
    }
}
