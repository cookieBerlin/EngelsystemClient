import CloudKit
import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

struct APIErrorTests {
    private struct Other: Error {}

    @Test func equalityComparesCaseAndPayload() {
        #expect(APIError.network("a") == .network("a"))
        #expect(APIError.network("a") != .network("b"))
        #expect(APIError.decoding("a") == .decoding("a"))
        #expect(APIError.decoding("a") != .decoding("b"))
        #expect(APIError.server(statusCode: 500) == .server(statusCode: 500))
        #expect(APIError.server(statusCode: 500) != .server(statusCode: 502))
        #expect(APIError.unauthorized != .forbidden)
        #expect(APIError.notFound == .notFound)
        #expect(APIError.invalidBaseURL == .invalidBaseURL)
    }

    @Test func everyCaseHasAUserMessage() {
        #expect(APIError.unauthorized.userMessage.contains("API key"))
        #expect(APIError.forbidden.userMessage.contains("privilege"))
        #expect(APIError.notFound.userMessage.contains("404"))
        #expect(APIError.invalidBaseURL.userMessage.contains("URL"))
        #expect(APIError.server(statusCode: 503).userMessage.contains("503"))
        #expect(APIError.network("offline").userMessage.contains("offline"))
        #expect(APIError.decoding("bad").userMessage.contains("bad"))
    }

    @Test func initializerMapsErrorResponsesAndOtherErrors() {
        func response(_ code: Int, underlying: Error = Other()) -> Error {
            ErrorResponse.error(code, nil, nil, underlying)
        }
        #expect(APIError(APIError.forbidden) == .forbidden)
        #expect(APIError(Other()) != .forbidden)
        #expect(APIError(response(401)) == .unauthorized)
        #expect(APIError(response(403)) == .forbidden)
        #expect(APIError(response(404)) == .notFound)
        #expect(APIError(response(500)) == .server(statusCode: 500))
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))
        #expect(APIError(response(200, underlying: decoding)) == .decoding(decoding.localizedDescription))
        if case .network = APIError(Other()) {} else { Issue.record("expected .network") }
    }
}

struct PollingIntervalTests {
    @Test func everyIntervalHasATitleAnIDAndATimeInterval() {
        for interval in PollingInterval.allCases {
            #expect(interval.id == interval.rawValue)
            #expect(!interval.title.isEmpty)
        }
        #expect(PollingInterval.manual.title == "Manual")
        #expect(PollingInterval.minutes15.title.contains("15"))
        #expect(PollingInterval.minutes30.title.contains("30"))
        #expect(PollingInterval.minutes60.title.contains("hour"))
        #expect(PollingInterval.minutes180.title.contains("3 hours"))
        #expect(PollingInterval.minutes360.title.contains("6 hours"))
        #expect(PollingInterval.manual.timeInterval == nil)
        #expect(PollingInterval.minutes30.timeInterval == 1800)
        #expect(PollingInterval(minutes: 60) == .minutes60)
        #expect(PollingInterval(minutes: 7) == .manual)
    }
}

struct CloudSyncStatusStateTests {
    private struct Failure: Error, LocalizedError { var errorDescription: String? { "boom" } }

    @Test func displayTextCoversEveryState() {
        let states: [CloudSyncStatus] = [.checking, .active, .noAccount, .restricted, .temporarilyUnavailable, .unknown, .error("x")]
        #expect(Set(states.map(\.displayText)).count == states.count)
    }

    @Test func accountStatusesMapToSyncStatuses() async {
        let mapping: [(CKAccountStatus, CloudSyncStatus)] = [
            (.available, .active), (.noAccount, .noAccount), (.restricted, .restricted),
            (.temporarilyUnavailable, .temporarilyUnavailable), (.couldNotDetermine, .unknown),
        ]
        for (account, expected) in mapping {
            #expect(await CloudSyncStatus.current(containerIdentifier: "c") { _ in account } == expected)
        }
    }

    @Test func aThrowingAccountCheckBecomesAnErrorStatus() async {
        let status = await CloudSyncStatus.current(containerIdentifier: "c") { _ in throw Failure() }
        #expect(status == .error("boom"))
    }

    @Test func unknownFutureAccountStatusesAreUnknown() {
        #expect(CloudSyncStatus.status(for: CKAccountStatus(rawValue: 99) ?? .couldNotDetermine) == .unknown)
    }
}

struct WatchConnectivityBridgeTests {
    @Test func activateAndNotifyAreSafeNoOpsOutsideiOS() {
        WatchConnectivityBridge.activate()
        WatchConnectivityBridge.notifyShiftsChanged()
    }
}

// Part of `DebugLogTests` (same serialized suite): both use the process-wide `DebugLog.shared`.
extension DebugLogTests {
    @Test func loadingWithoutAFileLeavesTheEntriesAlone() {
        DebugLog.shared.clear()
        DebugLog.shared.loadFromDisk()
        #expect(DebugLog.shared.entries.isEmpty)
    }

    @Test func loggingStoresAnEntryOnlyWhenEnabled() async {
        let key = DebugLog.isEnabledUserDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        DebugLog.shared.clear()

        UserDefaults.standard.set(false, forKey: key)
        DebugLog.log("disabled-message")
        await Task.yield()
        #expect(!DebugLog.shared.entries.contains { $0.message == "disabled-message" })

        UserDefaults.standard.set(true, forKey: key)
        DebugLog.log("enabled-message")
        for _ in 0..<200 where !DebugLog.shared.entries.contains(where: { $0.message == "enabled-message" }) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(DebugLog.shared.entries.contains { $0.message == "enabled-message" })
        DebugLog.shared.clear()
    }
}

struct LocationSyncRefreshTests {
    @MainActor
    @Test func refreshOneInsertsTheRowWhenItIsNotCachedYet() async throws {
        let schema = Schema([CachedLocation.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "r")
        let credential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
        let id = try #require(DemoData.locations.first?.id)

        let service = LocationSyncService()
        let inserted = try await service.refreshOne(serverID: id, instance: instance, credential: credential, in: context)
        #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == 1)
        let again = try await service.refreshOne(serverID: id, instance: instance, credential: credential, in: context)
        #expect(again.uid == inserted.uid)
        #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == 1)
    }
}
