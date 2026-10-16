import Foundation
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

@MainActor
struct WatchLogsViewModelTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WatchLogsVM-\(UUID().uuidString)")
    }

    private func logFile(in directory: URL, lines: Int) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString)
        try (0..<lines).map { "\($0).0\tinfo\tline \($0)" }.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeModel(
        logs: ReceivedWatchLogs, defaults: UserDefaults? = nil,
        outcome: WatchLogRequestOutcome = .queued, desired: LoggingSwitch? = nil,
        sentSwitches: @escaping (Bool) -> Void = { _ in }
    ) -> WatchLogsViewModel {
        let suite = defaults ?? UserDefaults(suiteName: "WatchLogsVM-\(UUID().uuidString)")!
        var wish = desired
        return WatchLogsViewModel(
            logs: logs, inbox: WatchLogInbox(logs: logs, defaults: suite),
            requestLog: { outcome },
            setLogging: { isOn in
                sentSwitches(isOn)
                wish = LoggingSwitch(isOn: isOn, changedAt: 100)
                return true
            },
            desired: { wish })
    }

    @Test func receivedLogsAreListedSharedAndDeleted() throws {
        let base = directory()
        let logs = ReceivedWatchLogs(directory: base.appendingPathComponent("stored"))
        try logs.store(try logFile(in: base, lines: 2), receivedAt: Date(timeIntervalSince1970: 10))
        try logs.store(try logFile(in: base, lines: 3), receivedAt: Date(timeIntervalSince1970: 20))
        let model = makeModel(logs: logs)
        #expect(model.items.count == 2)
        #expect(model.shareURLs == model.items.map(\.url)) // all of them go to one share sheet
        #expect(model.entries(of: model.items[0]).count == 3)

        model.delete(model.items[0])
        #expect(model.items.count == 1)
        model.deleteAll()
        #expect(model.items.isEmpty && model.shareURLs.isEmpty)
    }

    @Test func theRequestStatusTellsWhatHappened() {
        let logs = ReceivedWatchLogs(directory: directory())
        let live = makeModel(logs: logs, outcome: .sentLive)
        #expect(live.requestStatus == nil)
        live.request()
        #expect(live.requestStatus == "Requested. Waiting for the Apple Watch to answer.")
        let queued = makeModel(logs: logs, outcome: .queued)
        queued.request()
        #expect(queued.requestStatus == "Requested. The Apple Watch answers when its app runs.")
        let unavailable = makeModel(logs: logs, outcome: .unavailable)
        unavailable.request()
        #expect(unavailable.requestStatus == "No paired Apple Watch with the app installed.")
    }

    @Test func theRemoteSwitchShowsWaitingUntilTheWatchReports() {
        let logs = ReceivedWatchLogs(directory: directory())
        let defaults = UserDefaults(suiteName: "WatchLogsVM-\(UUID().uuidString)")!
        var switched: [Bool] = []
        let model = makeModel(logs: logs, defaults: defaults, sentSwitches: { switched.append($0) })
        #expect(model.loggingStatusText() == "The Apple Watch has not reported yet.")

        model.setWatchLogging(false)
        #expect(switched == [false])
        #expect(!model.loggingStatus.isOn)
        #expect(model.loggingStatusText() == "Waiting for Apple Watch")

        // The Watch confirms with its report.
        WatchLogInbox(logs: logs, defaults: defaults).receiveReport(
            WatchLogReport(isLoggingOn: false, changedAt: 100, entryCount: 4, reportedAt: Date().timeIntervalSince1970).dictionary)
        model.refresh()
        #expect(model.loggingStatusText().hasPrefix("Off · reported"))
        let on = makeModel(logs: logs, defaults: defaults)
        WatchLogInbox(logs: logs, defaults: defaults).receiveReport(
            WatchLogReport(isLoggingOn: true, changedAt: 200, entryCount: 4, reportedAt: Date().timeIntervalSince1970).dictionary)
        on.refresh()
        #expect(on.loggingStatusText().hasPrefix("On · reported"))
        // The defaults point at the real session adapter: with no paired Apple Watch (simulator) nothing is available.
        let real = WatchLogsViewModel()
        real.request()
        real.setWatchLogging(true)
        #expect(real.requestStatus != nil)
    }
}
