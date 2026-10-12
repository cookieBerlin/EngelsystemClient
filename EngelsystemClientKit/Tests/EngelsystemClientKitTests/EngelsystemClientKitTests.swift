import Foundation
import SwiftData
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

// 2026-09-17 multi-active-instance redesign (CLAUDE.md): any number of instances can be
// active at once, so a freshly created instance must default to active — there's no
// "first instance is auto-activated" special case standing in for this anymore.
@Test func instanceDefaultsToActiveOnCreation() {
    let instance = Instance(name: "Real", baseURL: "https://engelsystem.example.org", apiKeyKeychainRef: "ref")
    #expect(instance.isActive)
}

@Test func instanceCanBeCreatedInactive() {
    let instance = Instance(name: "Real", baseURL: "https://engelsystem.example.org", apiKeyKeychainRef: "ref", isActive: false)
    #expect(!instance.isActive)
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

// MARK: - CachedNews [more] splitting

/// 2026-09-22, user-reported: the app previously just stripped the `[more]` tag and
/// always showed the full text; the website actually truncates at it with a "read
/// more" expansion, and the app should match that.
@Test func cachedNewsTextPartsSplitsAtMoreTagAndTrimsBothSides() {
    let parts = CachedNews.textParts(from: "Intro text.\n[more]\nRest of the story.")
    #expect(parts.preview == "Intro text.")
    #expect(parts.rest == "Rest of the story.")
}

@Test func cachedNewsTextPartsHasNoRestWhenTagIsMissing() {
    let parts = CachedNews.textParts(from: "  No tag here.  ")
    #expect(parts.preview == "No tag here.")
    #expect(parts.rest == nil)
}

@Test func cachedNewsTextPartsHasNoRestWhenNothingFollowsTheTag() {
    #expect(CachedNews.textParts(from: "Intro only.\n[more]").rest == nil)
    #expect(CachedNews.textParts(from: "[more]").rest == nil)
    #expect(CachedNews.textParts(from: "[more]").preview == "")
}

@Test func pollingIntervalMapsRawMinutesToTheClosestKnownPreset() {
    #expect(PollingInterval(minutes: 0) == .manual)
    #expect(PollingInterval(minutes: 15) == .minutes15)
    #expect(PollingInterval(minutes: 360) == .minutes360)
    // An unrecognized stored value (e.g. from a future version offering a preset this
    // one doesn't know) falls back to manual rather than crashing or guessing.
    #expect(PollingInterval(minutes: 999) == .manual)
}

@Test func pollingIntervalTimeIntervalIsNilOnlyForManual() {
    #expect(PollingInterval.manual.timeInterval == nil)
    // Explicit `TimeInterval(...)` on the RHS, not a bare Int literal: `Double? == Int`
    // type-checks (via a looser, dynamically-typed fallback) but always compares
    // false, since the two sides end up boxed as different underlying types.
    #expect(PollingInterval.minutes15.timeInterval == TimeInterval(15 * 60))
    #expect(PollingInterval.minutes360.timeInterval == TimeInterval(360 * 60))
}

@Test func notificationLeadTimeSettingsParsesAndEncodesTheCommaSeparatedList() {
    #expect(NotificationLeadTimeSettings.parseLeadTimes("15,60") == [15, 60])
    #expect(NotificationLeadTimeSettings.parseLeadTimes(" 15 , 60 ") == [15, 60])
    // Empty parses to `[]`, not the default — a real bug, found and fixed
    // 2026-09-22: falling back to the default here made removing a user's *last*
    // reminder immediately reappear as the default, since both "never configured"
    // and "deliberately cleared to zero" were stored as the same empty string.
    #expect(NotificationLeadTimeSettings.parseLeadTimes("").isEmpty)
    #expect(NotificationLeadTimeSettings.parseLeadTimes("not,a,number").isEmpty)
    #expect(NotificationLeadTimeSettings.encodeLeadTimes([15, 60]) == "15,60")
}

/// Regression test for the exact bug above: removing the only configured lead time
/// must result in an empty list, not the default reappearing.
@MainActor
@Test func notificationLeadTimeSettingsRemovingTheLastLeadTimeStaysEmpty() throws {
    let schema = Schema([Instance.self, NotificationLeadTimeSettings.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let context = ModelContext(container)

    let settings = NotificationLeadTimeSettings.resolve(for: "ios", in: context)
    #expect(settings.leadTimesMinutes == NotificationLeadTimeSettings.defaultLeadTimesMinutes)

    settings.leadTimesMinutes.removeAll { $0 == NotificationLeadTimeSettings.defaultLeadTimesMinutes[0] }
    try context.save()

    let reloaded = NotificationLeadTimeSettings.resolve(for: "ios", in: context)
    #expect(reloaded.leadTimesMinutes.isEmpty)
}

/// Backs the "Last Synced" section on the instance detail screens (2026-09-23,
/// user-requested). `cachedAt` already means "last synced" per item — this just
/// verifies picking the right one out of a mixed-instance set.
@Test func cacheSyncTimestampLastSyncDateReturnsTheFreshestItemForThatInstanceOnly() {
    let instanceA = UUID()
    let instanceB = UUID()
    let older = CachedShift(
        serverID: 1, instanceID: instanceA, title: "Old", startsAt: Date(), endsAt: Date(),
        locationID: 1, shiftTypeID: 1, url: ""
    )
    older.cachedAt = Date().addingTimeInterval(-3600)
    let newer = CachedShift(
        serverID: 2, instanceID: instanceA, title: "New", startsAt: Date(), endsAt: Date(),
        locationID: 1, shiftTypeID: 1, url: ""
    )
    newer.cachedAt = Date().addingTimeInterval(-60)
    let otherInstance = CachedShift(
        serverID: 3, instanceID: instanceB, title: "Other", startsAt: Date(), endsAt: Date(),
        locationID: 1, shiftTypeID: 1, url: ""
    )
    otherInstance.cachedAt = Date()

    let result = CacheSyncTimestamp.lastSyncDate(for: instanceA, in: [older, newer, otherInstance])
    #expect(result == newer.cachedAt)

    #expect(CacheSyncTimestamp.lastSyncDate(for: UUID(), in: [older, newer]) == nil)
}

@Test func cacheSyncTimestampMostRecentPicksTheLatestAcrossMultipleDomains() {
    let a = Date().addingTimeInterval(-100)
    let b = Date().addingTimeInterval(-10)
    #expect(CacheSyncTimestamp.mostRecent([a, b, nil]) == b)
    #expect(CacheSyncTimestamp.mostRecent([nil, nil]) == nil)
}

@Test func notificationLeadTimeSettingsAvailableToAddExcludesAlreadySelectedPresets() {
    let available = NotificationLeadTimeSettings.availableToAdd(
        currentlySelected: [15, 60],
        presets: NotificationScheduler.availableLeadTimesInMinutes
    )
    #expect(available == [5, 10, 30])

    // Nothing left once every preset is selected.
    let none = NotificationLeadTimeSettings.availableToAdd(
        currentlySelected: NotificationScheduler.availableLeadTimesInMinutes,
        presets: NotificationScheduler.availableLeadTimesInMinutes
    )
    #expect(none.isEmpty)
}

/// 2026-09-22, user-requested "multiple reminders" feature: the reminder list syncs
/// via CloudKit *within* a platform, but not *across* iOS and Watch — modeled as one
/// row per platform rather than a single shared singleton (see the type's doc
/// comment). `resolve(for:in:)` takes the platform explicitly so this is testable
/// without actually compiling for watchOS.
@MainActor
@Test func notificationLeadTimeSettingsResolvesASeparateRowPerPlatform() throws {
    let schema = Schema([Instance.self, NotificationLeadTimeSettings.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    let context = ModelContext(container)

    let ios = NotificationLeadTimeSettings.resolve(for: "ios", in: context)
    ios.leadTimesMinutes = [15, 60]
    try context.save()

    // Re-resolving "ios" returns the same row, unaffected by "watch" being resolved
    // (and defaulted) independently.
    let watch = NotificationLeadTimeSettings.resolve(for: "watch", in: context)
    #expect(watch.leadTimesMinutes == NotificationLeadTimeSettings.defaultLeadTimesMinutes)

    let iosAgain = NotificationLeadTimeSettings.resolve(for: "ios", in: context)
    #expect(iosAgain.id == ios.id)
    #expect(iosAgain.leadTimesMinutes == [15, 60])
    #expect(try context.fetch(FetchDescriptor<NotificationLeadTimeSettings>()).count == 2)
}

/// The polling interval was originally a CloudKit-synced `SyncSettings` singleton,
/// shared with the Apple Watch — reverted 2026-09-22, the same day, at the user's
/// explicit request: Watch background execution isn't implemented at all, so
/// syncing/showing an interval that does nothing there was pointless. It's a plain
/// per-device `DeviceSyncPreferences` value now, same as `syncOnAppStartEnabled`
/// below.
@Test func deviceSyncPreferencesPollingIntervalDefaultsToManualButRespectsAStoredValue() {
    let defaults = UserDefaults(suiteName: "DeviceSyncPreferencesTests-\(UUID().uuidString)")!
    #expect(DeviceSyncPreferences.pollingInterval(in: defaults) == .manual)

    defaults.set(PollingInterval.minutes30.rawValue, forKey: DeviceSyncPreferences.pollingIntervalUserDefaultsKey)
    #expect(DeviceSyncPreferences.pollingInterval(in: defaults) == .minutes30)
}

@Test func deviceSyncPreferencesSyncOnAppStartDefaultsToTrueButRespectsAnExplicitFalse() {
    let defaults = UserDefaults(suiteName: "DeviceSyncPreferencesTests-\(UUID().uuidString)")!
    #expect(DeviceSyncPreferences.syncOnAppStartEnabled(in: defaults))

    defaults.set(false, forKey: DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    #expect(!DeviceSyncPreferences.syncOnAppStartEnabled(in: defaults))
}

@Test func deviceSyncPreferencesRecordsAndReadsBackTheLastBackgroundSyncDate() {
    let defaults = UserDefaults(suiteName: "DeviceSyncPreferencesTests-\(UUID().uuidString)")!
    #expect(DeviceSyncPreferences.lastBackgroundSyncDate(in: defaults) == nil)

    let date = Date()
    DeviceSyncPreferences.recordBackgroundSync(at: date, in: defaults)
    #expect(DeviceSyncPreferences.lastBackgroundSyncDate(in: defaults) == date)
}

@Test func newsNotifierContentIsNilWhenThereIsNothingNew() {
    #expect(NewsNotifier.content(for: [], instanceName: "Demo") == nil)
}

@Test func newsNotifierContentForASingleItemUsesItsOwnTitleAndPreviewText() {
    let item = CachedNews(
        serverID: 1, instanceID: UUID(), title: "Heaven build-up meeting",
        text: "Bring your own seating. [more] See you there.",
        isMeeting: true, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
    )

    let withoutInstanceName = NewsNotifier.content(for: [item], instanceName: nil)
    #expect(withoutInstanceName == .init(title: "Heaven build-up meeting", body: "Bring your own seating."))

    // Only mentioned when there's more than one active instance (see NewsViewModel) —
    // otherwise it'd just be redundant noise.
    let withInstanceName = NewsNotifier.content(for: [item], instanceName: "Demo Congress")
    #expect(withInstanceName == .init(title: "Heaven build-up meeting", body: "Demo Congress — Bring your own seating."))
}

@Test func newsNotifierContentForMultipleItemsIsASingleBundledSummary() {
    let items = [
        CachedNews(
            serverID: 1, instanceID: UUID(), title: "First post", text: "text",
            isMeeting: false, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
        ),
        CachedNews(
            serverID: 2, instanceID: UUID(), title: "Second post", text: "text",
            isMeeting: false, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
        ),
    ]

    let content = NewsNotifier.content(for: items, instanceName: "Demo Congress")
    #expect(content == .init(title: "2 New Announcements", body: "First post, Second post"))
}

/// 2026-09-22, user-reported: two active `Instance`s pointing at the same actual
/// server (different user accounts for one event) each cache their own copy of the
/// same news post, which then both show up in the merged cross-instance list. A first
/// version collapsed this to a single row but only showed one instance's badge — the
/// user reported that as well, so `mergedAcrossServers` also collects every
/// contributing instance's name, asserted here too.
@Test func cachedNewsMergedAcrossServersCollapsesDuplicatesButKeepsAllInstanceNames() {
    let sharedServerURL = "https://example.org"
    let instanceA = Instance(name: "A", baseURL: sharedServerURL, apiKeyKeychainRef: "a")
    let instanceB = Instance(name: "B", baseURL: sharedServerURL, apiKeyKeychainRef: "b")
    let instanceC = Instance(name: "C", baseURL: "https://other.example.org", apiKeyKeychainRef: "c")

    let newsFromA = CachedNews(
        serverID: 1, instanceID: instanceA.id, title: "Shared post", text: "text",
        isMeeting: false, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
    )
    let sameNewsFromB = CachedNews(
        serverID: 1, instanceID: instanceB.id, title: "Shared post", text: "text",
        isMeeting: false, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
    )
    let differentServerSameID = CachedNews(
        serverID: 1, instanceID: instanceC.id, title: "Unrelated post, same numeric ID", text: "text",
        isMeeting: false, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
    )

    let merged = CachedNews.mergedAcrossServers(
        [newsFromA, sameNewsFromB, differentServerSameID],
        instances: [instanceA, instanceB, instanceC]
    )

    #expect(merged.count == 2) // A+B collapsed into one, C kept separate

    let sharedServerItem = merged.first { $0.item.instanceID == instanceA.id }
    #expect(sharedServerItem?.instanceNames.sorted() == ["A", "B"]) // both contributors named, not just A

    let otherServerItem = merged.first { $0.item.instanceID == instanceC.id }
    #expect(otherServerItem?.instanceNames == ["C"])
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

/// Coverage for `fetchNewsDetail` (`GET /news/{id}`, added 2026-09-22 alongside News
/// comments).
@Test func apiClientFetchNewsDetailReturnsDemoCommentsAndThrowsNotFoundForUnknownID() async throws {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    let client = APIClient.shared

    let detail = try await client.fetchNewsDetail(id: 1, credential)
    #expect(detail.comments.count == 2)
    #expect(detail.commentsCount == 2)

    // Demo item 2 exists but has no comments — the "no comments yet" empty case,
    // distinct from "unknown id" below.
    let emptyDetail = try await client.fetchNewsDetail(id: 2, credential)
    #expect(emptyDetail.comments.isEmpty)

    await #expect(throws: APIError.notFound) {
        _ = try await client.fetchNewsDetail(id: 999, credential)
    }
}

@Test func apiClientRejectsEmptyBaseURLForNonDemoInstance() async throws {
    let credential = EventCredential(baseURL: "", apiKey: "some-key")
    await #expect(throws: APIError.invalidBaseURL) {
        _ = try await APIClient.shared.fetchInfo(credential)
    }
}

@Test func apiClientSelfUserReferenceWorksIsTrueForDemoInstance() async {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    #expect(await APIClient.shared.selfUserReferenceWorks(credential))
}

/// `selfUserReferenceWorks`'s actual `.notFound`-detection can't be exercised offline
/// (no mock HTTP server in this test target — see the file-level note on
/// `apiClientRejectsEmptyBaseURLForNonDemoInstance` above), so the pure interpretation
/// logic behind it is tested directly instead (`APIClient.selfWorks(afterProbeError:)`,
/// `internal`, hence `@testable import`).
@Test func selfWorksInterpretsNotFoundAsServerDoesNotSupportSelf() {
    #expect(APIClient.selfWorks(afterProbeError: APIError.notFound) == false)
}

@Test func selfWorksTreatsSuccessAndUnrelatedErrorsAsSelfWorking() {
    #expect(APIClient.selfWorks(afterProbeError: nil))
    #expect(APIClient.selfWorks(afterProbeError: APIError.invalidBaseURL))
    #expect(APIClient.selfWorks(afterProbeError: APIError.unauthorized))
    #expect(APIClient.selfWorks(afterProbeError: APIError.network("timed out")))
}

@Test func apiClientMessagesSupportedIsTrueForDemoInstance() async {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    #expect(await APIClient.shared.messagesSupported(credential))
}

/// `messagesSupported(_:)`'s real `.notFound`-body-inspection can't be exercised
/// offline either, same reasoning as `selfWorksInterpretsNotFoundAsServerDoesNotSupportSelf`
/// — so the pure interpretation logic is tested directly. Two different 404 bodies
/// (verified against the real server, not guessed — see APIClient.swift's doc comment)
/// must be told apart: a route that doesn't exist at all (`"Not implemented"`, the
/// app's shared catch-all) vs. a 404 for a specific missing resource (`"Not Found"`,
/// which means the route *does* exist).
@Test func messagesSupportedInterpretsNotImplementedBodyAsUnsupported() {
    let body = #"{"message": "Not implemented"}"#.data(using: .utf8)!
    let error = ErrorResponse.error(404, body, nil, APIError.notFound)
    #expect(APIClient.messagesSupported(afterProbeError: error) == false)
}

@Test func messagesSupportedInterpretsGenuineNotFoundBodyAsSupported() {
    let body = #"{"message": "Not Found"}"#.data(using: .utf8)!
    let error = ErrorResponse.error(404, body, nil, APIError.notFound)
    #expect(APIClient.messagesSupported(afterProbeError: error))
}

@Test func messagesSupportedTreatsUnrelatedErrorsAndMissingBodyAsSupported() {
    #expect(APIClient.messagesSupported(afterProbeError: APIError.unauthorized))
    #expect(APIClient.messagesSupported(afterProbeError: APIError.network("timed out")))
    let noBody = ErrorResponse.error(404, nil, nil, APIError.notFound)
    #expect(APIClient.messagesSupported(afterProbeError: noBody))
    let unparseableBody = ErrorResponse.error(404, Data("not json".utf8), nil, APIError.notFound)
    #expect(APIClient.messagesSupported(afterProbeError: unparseableBody))
}

@Test func apiClientFetchUsersReturnsDemoDataForDemoInstance() async throws {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    let users = try await APIClient.shared.fetchUsers(credential)
    #expect(users.count == 3)
}

@Test func apiClientMessagesRoundTripThroughDemoData() async throws {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    let client = APIClient.shared

    let conversations = try await client.fetchConversations(credential)
    #expect(conversations.count == 1)
    #expect(conversations.first?.unreadMessages == 1)

    let thread = try await client.fetchConversation(otherUserID: 2, credential)
    #expect(thread.count == 1)

    let sent = try await client.sendMessage(to: 2, text: "On my way!", credential)
    #expect(sent.text == "On my way!")
    #expect(sent.read)

    let updatedThread = try await client.fetchConversation(otherUserID: 2, credential)
    #expect(updatedThread.count == 2)
    // The latest message is now one the demo user sent, so the "other user" is its receiver.
    let afterSend = try await client.fetchConversations(credential)
    #expect(afterSend.first?.otherUser.id == 2)

    // A brand-new conversation with someone who isn't a known demo user: named by id,
    // sorted first (newest), and an unknown conversation reads as empty.
    let stranger = try await client.sendMessage(to: 999, text: "Hello stranger", credential)
    #expect(stranger.receiver.name == "User 999")
    let twoConversations = try await client.fetchConversations(credential)
    #expect(twoConversations.map(\.otherUser.id) == [999, 2])
    #expect(try await client.fetchConversation(otherUserID: 424_242, credential).isEmpty)
    try await client.deleteMessage(id: stranger.id, credential)
    #expect(try await client.fetchConversations(credential).count == 1) // emptied conversations disappear

    let markedRead = try await client.setMessageRead(id: thread[0].id, read: true, credential)
    #expect(markedRead.read)

    try await client.deleteMessage(id: sent.id, credential)
    let afterDelete = try await client.fetchConversation(otherUserID: 2, credential)
    #expect(afterDelete.count == 1)
}

@Test func apiClientSetMessageReadThrowsNotFoundForUnknownMessageInDemoMode() async {
    let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
    await #expect(throws: APIError.notFound) {
        _ = try await APIClient.shared.setMessageRead(id: 999_999, read: true, credential)
    }
}
