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
}
