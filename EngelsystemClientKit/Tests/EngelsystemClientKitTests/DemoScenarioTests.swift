import Foundation
import Testing
@testable import EngelsystemClientKit

struct DemoScenarioTests {
    @Test func theHostPicksTheScenarioForInstanceAndAPIAddresses() {
        #expect(DemoScenario(baseURL: "demo://engelsystem.local") == .main)
        #expect(DemoScenario(baseURL: "demo://congress.local/api/v0-beta") == .congress)
        #expect(DemoScenario(baseURL: "demo://CONGRESS.local") == .congress)
        #expect(DemoScenario(baseURL: "demo://unknown.local") == nil)
        #expect(DemoScenario(baseURL: "https://congress.local") == nil)
        #expect(DemoScenario.congress.baseURL == "demo://congress.local")
        #expect(Instance.demoBaseURL == "demo://engelsystem.local")
    }

    @Test func everyDemoAddressIsADemoInstance() {
        let congress = Instance(name: "C", baseURL: "demo://congress.local/", apiKeyKeychainRef: "c")
        let real = Instance(name: "R", baseURL: "https://real.test", apiKeyKeychainRef: "r")
        #expect(congress.isDemo)
        #expect(!real.isDemo)
        let credential = EventCredential(baseURL: "demo://nowhere.local/api/v0-beta", apiKey: "demo")
        #expect(credential.isDemo)
        #expect(credential.demoScenario == nil)
        #expect(credential.scenario == .unknown)
        #expect(EventCredential(baseURL: "demo://congress.local/api/v0-beta", apiKey: "k").scenario == .congress)
    }

    @Test func eachScenarioHasItsOwnData() async throws {
        let main = EventCredential(baseURL: "demo://engelsystem.local/api/v0-beta", apiKey: "demo")
        let congress = EventCredential(baseURL: "demo://congress.local/api/v0-beta", apiKey: "demo")
        let client = APIClient.shared

        #expect(try await client.fetchInfo(main).name == "Demo Congress")
        #expect(try await client.fetchInfo(congress).name == "Demo Congress 2")

        let mainLocations = try await client.fetchLocations(main).map(\.name)
        let congressLocations = try await client.fetchLocations(congress).map(\.name)
        #expect(mainLocations.contains("Heaven"))
        #expect(congressLocations == ["Hall A", "Hall B", "Lounge", "Kitchen"])
        #expect(try await client.fetchLocation(id: 1, congress).name == "Hall A")
        await #expect(throws: APIError.notFound) { _ = try await client.fetchLocation(id: 99, congress) }

        let mainShifts = try await client.fetchShifts(main)
        let congressShifts = try await client.fetchShifts(congress)
        #expect(congressShifts.count == mainShifts.count)
        #expect(congressShifts.allSatisfy { $0.name.hasPrefix("Congress: ") })
        #expect(congressShifts[0].location.name == "Hall A")
        #expect(try await client.fetchShift(id: congressShifts[0].id, congress).name.hasPrefix("Congress: "))

        let mainNews = try await client.fetchNews(main)
        let congressNews = try await client.fetchNews(congress)
        #expect(congressNews.map(\.name) == mainNews.map { "Congress: " + $0.name })
        #expect(try await client.fetchNewsDetail(id: mainNews[0].id, congress).name.hasPrefix("Congress: "))
        #expect(try await client.fetchNewsDetail(id: mainNews[0].id, main).name == mainNews[0].name)
        await #expect(throws: APIError.notFound) { _ = try await client.fetchNewsDetail(id: 9999, congress) }
    }

    @Test func anUnknownDemoAddressIsAnInstanceThatNamesTheAddressesThatWork() async throws {
        let unknown = EventCredential(baseURL: "demo://unknown.local/api/v0-beta", apiKey: "demo")
        let client = APIClient.shared
        #expect(try await client.fetchInfo(unknown).name == "Unknown demo address")
        await #expect(throws: APIError.notFound) { _ = try await client.fetchLocations(unknown) }
        await #expect(throws: APIError.notFound) { _ = try await client.fetchShifts(unknown) }

        let news = try await client.fetchNews(unknown)
        #expect(news.count == 1)
        #expect(news[0].text.contains("demo://engelsystem.local"))
        #expect(news[0].text.contains("demo://congress.local"))
        #expect(!news[0].text.contains("unknown"))
        #expect(news[0].commentsCount == nil)
        let detail = try await client.fetchNewsDetail(id: news[0].id, unknown)
        #expect(detail.text == news[0].text)
        await #expect(throws: APIError.notFound) { _ = try await client.fetchNewsDetail(id: 2, unknown) }
        #expect(DemoScenario.supportedAddresses == ["demo://engelsystem.local", "demo://congress.local"])
        // Everything but News answers like a missing route.
        await #expect(throws: APIError.notFound) { _ = try await client.fetchWorklogs(unknown) }
        await #expect(throws: APIError.notFound) { _ = try await client.fetchOwnAngelTypes(unknown) }
        await #expect(throws: APIError.notFound) { _ = try await client.fetchShift(id: 1, unknown) }
        await #expect(throws: APIError.notFound) { _ = try await client.fetchLocation(id: 1, unknown) }
        await #expect(throws: APIError.notFound) { _ = try await client.fetchConversations(unknown) }
        #expect(await client.messagesState(unknown) == .notOffered)
        #expect(await client.messagesState(EventCredential(baseURL: "demo://engelsystem.local/api/v0-beta", apiKey: "k")) == .available)
        #expect(DemoScenario.unknown.offersOnlyNews && !DemoScenario.main.offersOnlyNews)
        // The literal host "unknown" is not a way to the placeholder data set either.
        #expect(DemoScenario(baseURL: "demo://unknown") == nil)
    }
}
