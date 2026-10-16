import Foundation
import SwiftData
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient_Watch_App

private final class RecordingSender: WatchLogSending, @unchecked Sendable {
    var files: [URL] = []
    var reports: [[String: Any]] = []
    func transferFile(_ url: URL, metadata: [String: Any]) { files.append(url) }
    func sendReport(_ report: [String: Any]) throws { reports.append(report) }
}

private func logFile(lines: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("WatchLogTests-\(UUID().uuidString).log")
    let text = (0..<lines).map { "\($0).0\tinfo\tline \($0)" }.joined(separator: "\n")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "WatchLogTests-\(UUID().uuidString)")! }

struct WatchDiagnosticsViewModelTests {
    @Test @MainActor func tappingSendHandsTheLogOverAndRemembersWhen() throws {
        let sender = RecordingSender()
        let defaults = freshDefaults()
        let responder = WatchLogResponder(sender: sender, defaults: defaults, logFile: try logFile(lines: 3))
        let viewModel = WatchDiagnosticsViewModel(responder: responder, defaults: defaults)
        #expect(viewModel.statusText == nil && viewModel.lastSentText() == nil)

        viewModel.sendLog(now: Date())
        #expect(sender.files.count == 1)
        #expect(viewModel.statusText == "Queued. Open the iPhone app to receive it.")
        #expect(viewModel.lastSentText()?.hasPrefix("Last sent") == true)

        // A new model (the page opened again) still knows when the log was last sent.
        #expect(WatchDiagnosticsViewModel(responder: responder, defaults: defaults).lastSentAt != nil)
    }

    @Test @MainActor func withoutALogNothingIsSent() {
        let sender = RecordingSender()
        let responder = WatchLogResponder(
            sender: sender, defaults: freshDefaults(), logFile: FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString).log"))
        let viewModel = WatchDiagnosticsViewModel(responder: responder, defaults: freshDefaults())
        viewModel.sendLog()
        #expect(sender.files.isEmpty)
        #expect(viewModel.statusText == "Nothing logged yet.")
        #expect(viewModel.lastSentAt == nil)
    }

    @Test @MainActor func switchingTheLoggingRemembersTheTimeAndReportsIt() throws {
        let sender = RecordingSender()
        let defaults = freshDefaults()
        let responder = WatchLogResponder(sender: sender, defaults: defaults, logFile: try logFile(lines: 1))
        let viewModel = WatchDiagnosticsViewModel(responder: responder, defaults: defaults)
        viewModel.setLogging(false, now: Date(timeIntervalSince1970: 700))
        #expect(DebugLog.loggingSwitch(in: defaults) == LoggingSwitch(isOn: false, changedAt: 700))
        let report = sender.reports.last.flatMap(WatchLogReport.init(dictionary:))
        #expect(report?.isLoggingOn == false && report?.changedAt == 700)
        _ = WatchDiagnosticsViewModel() // the default responder (real session adapter) can be built
    }
}

struct WatchConnectivityReceiverLogTests {
    @MainActor
    private func makeReceiver(sender: RecordingSender, logFile: URL, defaults: UserDefaults) throws -> (WatchConnectivityReceiver, ModelContainer) {
        let schema = Schema([Instance.self, CachedShift.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        _ = try seedDemoInstance(in: container.mainContext)
        let coordinator = WatchShiftsSyncCoordinator(appSyncCoordinator: makeTestAppSyncCoordinator(), snapshotStore: uniqueTestSnapshotStore())
        let responder = WatchLogResponder(sender: sender, defaults: defaults, logFile: logFile)
        return (WatchConnectivityReceiver(modelContainer: container, syncCoordinator: coordinator, logResponder: responder, defaults: defaults), container)
    }

    @Test @MainActor func aLogRequestInTheContextSendsTheLogOnceAndAppliesTheSwitch() async throws {
        let sender = RecordingSender()
        let defaults = freshDefaults()
        let (receiver, _) = try makeReceiver(sender: sender, logFile: try logFile(lines: 2), defaults: defaults)
        let context: [String: Any] = [
            WatchLogKeys.logRequestID: "REQ", WatchLogKeys.loggingOn: false, WatchLogKeys.loggingChangedAt: 900.0,
            "shiftsChangedAt": 5.0,
        ]
        await receiver.handleApplicationContext(context, handleNotifications: false)
        await receiver.handleApplicationContext(context, handleNotifications: false)
        #expect(sender.files.count == 1)
        #expect(!DebugLog.isEnabled(in: defaults))
    }

    @Test @MainActor func theShiftsResyncRunsOnlyForANewTimestamp() async throws {
        let sender = RecordingSender()
        let defaults = freshDefaults()
        let (receiver, container) = try makeReceiver(sender: sender, logFile: try logFile(lines: 1), defaults: defaults)
        await receiver.handleApplicationContext(["shiftsChangedAt": 1.0], handleNotifications: false)
        #expect(try container.mainContext.fetch(FetchDescriptor<CachedShift>()).count == 7)

        try container.mainContext.delete(model: CachedShift.self)
        await receiver.handleApplicationContext(["shiftsChangedAt": 1.0], handleNotifications: false) // same: no resync
        #expect(try container.mainContext.fetch(FetchDescriptor<CachedShift>()).isEmpty)
        await receiver.handleApplicationContext(["shiftsChangedAt": 2.0], handleNotifications: false)
        #expect(try container.mainContext.fetch(FetchDescriptor<CachedShift>()).count == 7)
    }

    @Test @MainActor func aLiveRequestSendsTheLog() throws {
        let sender = RecordingSender()
        let (receiver, _) = try makeReceiver(sender: sender, logFile: try logFile(lines: 1), defaults: freshDefaults())
        receiver.handleMessage([WatchLogKeys.requestLog: "LIVE"])
        #expect(sender.files.count == 1)
    }
}
