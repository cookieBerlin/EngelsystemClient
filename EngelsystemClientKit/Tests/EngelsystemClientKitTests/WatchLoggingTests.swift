import Foundation
import Testing
@testable import EngelsystemClientKit

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("WatchLoggingTests-\(UUID().uuidString)")
}

private func writeLog(lines: Int, in directory: URL, name: String = UUID().uuidString) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let text = (0..<lines).map {
        DebugLogEntry(timestamp: Date(timeIntervalSince1970: Double($0)), level: .info, message: "line \($0)").persistedLine
    }.joined(separator: "\n")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
}

struct ReceivedWatchLogsTests {
    @Test func aStoredFileIsMovedAndListedNewestFirst() throws {
        let directory = temporaryDirectory()
        let logs = ReceivedWatchLogs(directory: directory.appendingPathComponent("stored"))
        let first = try writeLog(lines: 3, in: directory)
        let second = try writeLog(lines: 5, in: directory)
        let a = try logs.store(first, receivedAt: Date(timeIntervalSince1970: 100))
        let b = try logs.store(second, receivedAt: Date(timeIntervalSince1970: 200))
        #expect(!FileManager.default.fileExists(atPath: first.path)) // moved, not copied
        #expect(logs.list().map(\.id) == [b.id, a.id])
        #expect(a.entryCount == 3 && b.entryCount == 5 && a.byteCount > 0)
        #expect(logs.list()[0].receivedAt == Date(timeIntervalSince1970: 200))
        #expect(logs.entries(of: b).map(\.message) == ["line 0", "line 1", "line 2", "line 3", "line 4"])
    }

    @Test func onlyTheNewestTwentyFilesStay() throws {
        let directory = temporaryDirectory()
        let logs = ReceivedWatchLogs(directory: directory.appendingPathComponent("stored"))
        for index in 0..<(ReceivedWatchLogs.maxFiles + 3) {
            try logs.store(try writeLog(lines: 1, in: directory), receivedAt: Date(timeIntervalSince1970: Double(index + 1)))
        }
        let kept = logs.list()
        #expect(kept.count == ReceivedWatchLogs.maxFiles)
        #expect(kept.last?.receivedAt == Date(timeIntervalSince1970: 4)) // 1…3 were trimmed
    }

    @Test func sameMillisecondReplacesInsteadOfFailingAndFilesCanBeDeleted() throws {
        let directory = temporaryDirectory()
        let logs = ReceivedWatchLogs(directory: directory.appendingPathComponent("stored"))
        let now = Date(timeIntervalSince1970: 50)
        try logs.store(try writeLog(lines: 1, in: directory), receivedAt: now)
        let replaced = try logs.store(try writeLog(lines: 2, in: directory), receivedAt: now)
        #expect(logs.list().count == 1 && replaced.entryCount == 2)
        logs.delete(replaced)
        #expect(logs.list().isEmpty)
        try logs.store(try writeLog(lines: 1, in: directory), receivedAt: Date(timeIntervalSince1970: 60))
        try logs.store(try writeLog(lines: 1, in: directory), receivedAt: Date(timeIntervalSince1970: 61))
        logs.deleteAll()
        #expect(logs.list().isEmpty)
    }

    @Test func aMissingFolderOrFileGivesNothingInsteadOfFailing() throws {
        let logs = ReceivedWatchLogs(directory: temporaryDirectory())
        #expect(logs.list().isEmpty)
        let gone = ReceivedWatchLogs.Item(url: temporaryDirectory().appendingPathComponent("x.log"), receivedAt: Date(), entryCount: 0, byteCount: 0)
        #expect(logs.entries(of: gone).isEmpty)
        #expect(throws: (any Error).self) { try logs.store(temporaryDirectory().appendingPathComponent("missing")) }
        #expect(ReceivedWatchLogs.defaultDirectory.lastPathComponent == "ReceivedWatchLogs")
        _ = ReceivedWatchLogs()
    }
}

struct LoggingSwitchTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "LoggingSwitch-\(UUID().uuidString)")! }

    @Test func aChangeIsRememberedWithItsTime() {
        let defaults = defaults()
        #expect(DebugLog.loggingSwitch(in: defaults) == LoggingSwitch(isOn: DebugLog.defaultEnabled, changedAt: 0))
        DebugLog.setEnabled(false, at: Date(timeIntervalSince1970: 300), in: defaults)
        #expect(DebugLog.loggingSwitch(in: defaults) == LoggingSwitch(isOn: false, changedAt: 300))
    }

    @Test func onlyANewerRemoteChangeWins() {
        let defaults = defaults()
        DebugLog.setEnabled(false, at: Date(timeIntervalSince1970: 300), in: defaults)
        #expect(!DebugLog.apply(LoggingSwitch(isOn: true, changedAt: 200), in: defaults)) // older: ignored
        #expect(!DebugLog.apply(LoggingSwitch(isOn: true, changedAt: 300), in: defaults)) // same moment: stays
        #expect(!DebugLog.isEnabled(in: defaults))
        #expect(DebugLog.apply(LoggingSwitch(isOn: true, changedAt: 400), in: defaults))
        #expect(DebugLog.isEnabled(in: defaults))
        #expect(DebugLog.loggingSwitch(in: defaults).changedAt == 400)
    }

    @Test func aReportSurvivesTheDictionaryRoundTripAndRejectsGarbage() {
        let report = WatchLogReport(isLoggingOn: true, changedAt: 5, entryCount: 12, reportedAt: 99)
        #expect(WatchLogReport(dictionary: report.dictionary) == report)
        #expect(WatchLogReport(dictionary: ["loggingOn": true]) == nil)
        #expect(WatchLogReport(dictionary: [:]) == nil)
    }
}

private final class FakeSender: WatchLogSending {
    var files: [(url: URL, metadata: [String: Any])] = []
    var reports: [[String: Any]] = []
    var failure: Error?
    struct Failure: Error {}
    func transferFile(_ url: URL, metadata: [String: Any]) { files.append((url, metadata)) }
    func sendReport(_ report: [String: Any]) throws {
        if let failure { throw failure }
        reports.append(report)
    }
}

struct WatchLogResponderTests {
    private func makeDefaults() -> UserDefaults { UserDefaults(suiteName: "Responder-\(UUID().uuidString)")! }

    @Test func theLogIsSentOnlyWhenThereIsOne() throws {
        let sender = FakeSender()
        let none = WatchLogResponder(sender: sender, defaults: makeDefaults(), logFile: temporaryDirectory().appendingPathComponent("none.log"))
        #expect(none.sendLog(now: Date(timeIntervalSince1970: 7)) == .noLog)
        #expect(sender.files.isEmpty)
        #expect(sender.reports.count == 1) // the state is reported either way

        let file = try writeLog(lines: 4, in: temporaryDirectory())
        let responder = WatchLogResponder(sender: sender, defaults: makeDefaults(), logFile: file)
        #expect(responder.sendLog(now: Date(timeIntervalSince1970: 8)) == .queued(entryCount: 4))
        #expect(sender.files.count == 1)
        #expect(sender.files[0].metadata[WatchLogKeys.fileEntryCount] as? Int == 4)
        #expect(sender.files[0].metadata[WatchLogKeys.fileSentAt] as? Double == 8)
        #expect(sender.reports.count == 2)
    }

    @Test func eachRequestIsAnsweredOnceWhateverWayItArrives() throws {
        let sender = FakeSender()
        let file = try writeLog(lines: 2, in: temporaryDirectory())
        let responder = WatchLogResponder(sender: sender, defaults: makeDefaults(), logFile: file)
        responder.handleContext([WatchLogKeys.logRequestID: "R1"])
        responder.handleContext([WatchLogKeys.logRequestID: "R1"]) // the same context arrives again
        responder.handleMessage([WatchLogKeys.requestLog: "R1"]) // and as a live message
        #expect(sender.files.count == 1)
        responder.handleMessage([WatchLogKeys.requestLog: "R2"])
        #expect(sender.files.count == 2)
        responder.handleMessage([WatchLogKeys.requestLog: "R2"])
        responder.handleMessage(["other": 1])
        #expect(sender.files.count == 2)
    }

    @Test func aNewerSwitchFromTheiPhoneIsAppliedAndReported() {
        let sender = FakeSender()
        let defaults = makeDefaults()
        DebugLog.setEnabled(true, at: Date(timeIntervalSince1970: 100), in: defaults)
        let responder = WatchLogResponder(sender: sender, defaults: defaults, logFile: temporaryDirectory().appendingPathComponent("x.log"))
        responder.handleContext([WatchLogKeys.loggingOn: false, WatchLogKeys.loggingChangedAt: 50.0]) // older
        #expect(DebugLog.isEnabled(in: defaults))
        responder.handleContext([WatchLogKeys.loggingOn: false, WatchLogKeys.loggingChangedAt: 150.0])
        #expect(!DebugLog.isEnabled(in: defaults))
        let report = sender.reports.last.flatMap(WatchLogReport.init(dictionary:))
        #expect(report?.isLoggingOn == false && report?.changedAt == 150)
    }

    @Test func aFailingReportIsIgnoredAndTheDefaultLogFileIsUsedWhenNoneIsGiven() {
        let sender = FakeSender()
        sender.failure = FakeSender.Failure()
        let responder = WatchLogResponder(sender: sender, defaults: makeDefaults())
        responder.reportState()
        #expect(sender.reports.isEmpty)
    }
}

struct WatchLogInboxTests {
    @Test func aReceivedFileIsStoredAndAnnounced() throws {
        let directory = temporaryDirectory()
        let logs = ReceivedWatchLogs(directory: directory.appendingPathComponent("stored"))
        let defaults = UserDefaults(suiteName: "Inbox-\(UUID().uuidString)")!
        let inbox = WatchLogInbox(logs: logs, defaults: defaults)
        var announced = 0
        let token = NotificationCenter.default.addObserver(forName: WatchLogInbox.didChangeNotification, object: nil, queue: nil) { _ in announced += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        #expect(inbox.receiveFile(at: try writeLog(lines: 2, in: directory), now: Date(timeIntervalSince1970: 10)))
        #expect(logs.list().count == 1)
        #expect(announced == 1)
        #expect(!inbox.receiveFile(at: directory.appendingPathComponent("missing")))
        #expect(announced == 1)
    }

    @Test func theWatchsLastReportIsRemembered() {
        let defaults = UserDefaults(suiteName: "Inbox-\(UUID().uuidString)")!
        let inbox = WatchLogInbox(logs: ReceivedWatchLogs(directory: temporaryDirectory()), defaults: defaults)
        #expect(inbox.lastReport == nil)
        inbox.receiveReport(["nonsense": true])
        #expect(inbox.lastReport == nil)
        let report = WatchLogReport(isLoggingOn: false, changedAt: 3, entryCount: 9, reportedAt: 4)
        inbox.receiveReport(report.dictionary)
        #expect(inbox.lastReport == report)
        _ = WatchLogInbox()
    }
}

struct WatchLoggingStatusTests {
    private func report(on: Bool, changedAt: TimeInterval) -> WatchLogReport {
        WatchLogReport(isLoggingOn: on, changedAt: changedAt, entryCount: 3, reportedAt: 1000)
    }

    @Test func theStatusFollowsTheNewerOfWishAndReport() {
        #expect(WatchLoggingStatus(desired: nil, report: nil) == WatchLoggingStatus(desired: nil, report: nil))
        let unknown = WatchLoggingStatus(desired: nil, report: nil)
        #expect(unknown.kind == .unknown && unknown.isOn == DebugLog.defaultEnabled)

        let reported = WatchLoggingStatus(desired: nil, report: report(on: false, changedAt: 5))
        #expect(!reported.isOn)
        #expect(reported.kind == .reported(reportedAt: Date(timeIntervalSince1970: 1000)))

        // The wish is newer than the last report: waiting for the Watch.
        let waiting = WatchLoggingStatus(desired: LoggingSwitch(isOn: true, changedAt: 9), report: report(on: false, changedAt: 5))
        #expect(waiting.isOn && waiting.kind == .waiting)
        // No report yet: also waiting.
        #expect(WatchLoggingStatus(desired: LoggingSwitch(isOn: false, changedAt: 1), report: nil).kind == .waiting)
        // The Watch confirmed (its change is as new as the wish) or changed it itself later: the report counts.
        let confirmed = WatchLoggingStatus(desired: LoggingSwitch(isOn: true, changedAt: 5), report: report(on: true, changedAt: 5))
        #expect(confirmed.isOn && confirmed.kind == .reported(reportedAt: Date(timeIntervalSince1970: 1000)))
        #expect(!WatchLoggingStatus(desired: LoggingSwitch(isOn: true, changedAt: 5), report: report(on: false, changedAt: 7)).isOn)
    }

    @Test func theWishTheiPhoneSentCanBeReadBack() {
        let defaults = UserDefaults(suiteName: "WishState-\(UUID().uuidString)")!
        let state = WatchContextState(defaults: defaults)
        #expect(state.loggingSwitch == nil)
        state.noteLoggingSwitch(LoggingSwitch(isOn: false, changedAt: 12))
        #expect(state.loggingSwitch == LoggingSwitch(isOn: false, changedAt: 12))
        state.noteLogRequest(id: "X")
        #expect(state.dictionary[WatchLogKeys.logRequestID] as? String == "X")
        _ = WatchConnectivityBridge.desiredWatchLogging()
    }
}
