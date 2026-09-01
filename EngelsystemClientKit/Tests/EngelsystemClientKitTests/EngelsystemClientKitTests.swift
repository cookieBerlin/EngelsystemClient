import Foundation
import Testing
@testable import EngelsystemClientKit

// MARK: - Instance / demo sentinel

@Test func instanceIsDemoDetectsSentinelBaseURL() {
    let demo = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    #expect(demo.isDemo)

    let real = Instance(name: "Real", baseURL: "https://engelsystem.example.org", apiKeyKeychainRef: "ref")
    #expect(!real.isDemo)
}

@Test func instanceNormalizesTrailingSlashesInBaseURL() {
    let instance = Instance(name: "Real", baseURL: "https://engelsystem.example.org/", apiKeyKeychainRef: "ref")
    #expect(instance.normalizedBaseURL == "https://engelsystem.example.org")
    #expect(instance.apiBasePath == "https://engelsystem.example.org/api/v0-beta")
}

@Test func eventCredentialDetectsDemoBaseURL() {
    let demo = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    #expect(demo.isDemo)

    let real = EventCredential(baseURL: "https://engelsystem.example.org/api/v0-beta", apiKey: "key")
    #expect(!real.isDemo)
}

// MARK: - APIError mapping

@Test func apiErrorMapsKnownStatusCodes() {
    #expect(APIError(ErrorResponse.error(401, nil, nil, URLError(.badServerResponse))) == .unauthorized)
    #expect(APIError(ErrorResponse.error(403, nil, nil, URLError(.badServerResponse))) == .forbidden)
    #expect(APIError(ErrorResponse.error(404, nil, nil, URLError(.badServerResponse))) == .notFound)
    #expect(APIError(ErrorResponse.error(500, nil, nil, URLError(.badServerResponse))) == .server(statusCode: 500))
}

@Test func apiErrorPassesThroughExistingAPIError() {
    let error: Error = APIError.forbidden
    #expect(APIError(error) == .forbidden)
}

// MARK: - APIClient demo mode

@Test func apiClientFetchInfoReturnsDemoDataForDemoInstance() async throws {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    let info = try await APIClient.shared.fetchInfo(credential)
    #expect(info.name == "Demo Congress")
}

@Test func apiClientFetchListsReturnDemoDataForDemoInstance() async throws {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    let client = APIClient.shared

    #expect(try await client.fetchNews(credential).count == 2)
    #expect(try await client.fetchLocations(credential).count == 2)
    #expect(try await client.fetchShiftTypes(credential).count == 3)
    #expect(try await client.fetchAngelTypes(credential).count == 1)
    #expect(try await client.fetchShifts(for: .me, credential).count == 2)
    #expect(try await client.fetchWorklogs(for: .me, credential).count == 1)

    let profile = try await client.fetchOwnProfile(credential)
    #expect(profile.name == "demo")
}

@Test func apiClientRejectsEmptyBaseURLForNonDemoInstance() async throws {
    let credential = EventCredential(baseURL: "", apiKey: "some-key")
    await #expect(throws: APIError.invalidBaseURL) {
        _ = try await APIClient.shared.fetchInfo(credential)
    }
}
