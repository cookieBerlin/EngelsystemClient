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

// `Instance.userID` is a fallback for user-scoped endpoints — see
// `usersIdShiftsGetRequestBuilderProducesACorrectlyFormattedIDPathSegment` below for what
// this was actually working around (not a server-side "self" incompatibility, as first
// suspected on 2026-09-05 — that diagnosis was itself wrong, root-caused 2026-09-17).
@Test func instanceUserReferenceDefaultsToMeWhenUserIDIsUnset() {
    let instance = Instance(name: "Real", baseURL: "https://engelsystem.example.org", apiKeyKeychainRef: "ref")
    guard case .me = instance.userReference else {
        Issue.record("Expected .me, got \(instance.userReference)")
        return
    }
}

@Test func instanceUserReferenceUsesNumericFallbackWhenUserIDIsSet() {
    let instance = Instance(
        name: "Real",
        baseURL: "https://engelsystem.example.org",
        apiKeyKeychainRef: "ref",
        userID: 42
    )
    guard case let .id(id) = instance.userReference else {
        Issue.record("Expected .id, got \(instance.userReference)")
        return
    }
    #expect(id == 42)
}

/// Regression test, root-caused 2026-09-17: `UsersIdGetIdParameter` (generated) isn't
/// `RawRepresentable`, so the generated `APIHelper.mapValueToPathItem` used to build every
/// `/users/{id}/...` request path fell through to interpolating the raw enum value — producing
/// literal `{id}` path segments like `"typeInt(2)"` or `"typeString(\"self\")"` instead of
/// `"2"`/`"self"`, a malformed URL that 404s no matter what `Instance.userID` is set to. Fixed
/// by giving `UsersIdGetIdParameter` a `CustomStringConvertible` conformance in
/// `APIEndpoint.swift` (not `Generated/`) — this test exercises the real generated request
/// builder end-to-end (not just the conformance in isolation) so a future regenerate/change
/// that breaks this interaction again gets caught.
@Test func usersIdShiftsGetRequestBuilderProducesACorrectlyFormattedIDPathSegment() {
    let numericBuilder = ShiftAPI.usersIdShiftsGetWithRequestBuilder(id: UserReference.id(2).parameter)
    #expect(numericBuilder.URLString.hasSuffix("/users/2/shifts"))

    let selfBuilder = ShiftAPI.usersIdShiftsGetWithRequestBuilder(id: UserReference.me.parameter)
    #expect(selfBuilder.URLString.hasSuffix("/users/self/shifts"))
}

// MARK: - CachedNews text sanitization

@Test func cachedNewsSanitizedTextRemovesMoreTagAndTrims() {
    #expect(CachedNews.sanitizedText(from: "Intro text.\n[more]\nRest of the story.") == "Intro text.\n\nRest of the story.")
    #expect(CachedNews.sanitizedText(from: "  No tag here.  ") == "No tag here.")
    #expect(CachedNews.sanitizedText(from: "[more]") == "")
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
    #expect(try await client.fetchOwnAngelTypes(for: .me, credential).count == 1)
    #expect(try await client.fetchShifts(for: .me, credential).count == 2)
    #expect(try await client.fetchWorklogs(for: .me, credential).count == 1)

    let profile = try await client.fetchOwnProfile(for: .me, credential)
    #expect(profile.name == "demo")
}

@Test func apiClientRejectsEmptyBaseURLForNonDemoInstance() async throws {
    let credential = EventCredential(baseURL: "", apiKey: "some-key")
    await #expect(throws: APIError.invalidBaseURL) {
        _ = try await APIClient.shared.fetchInfo(credential)
    }
}
