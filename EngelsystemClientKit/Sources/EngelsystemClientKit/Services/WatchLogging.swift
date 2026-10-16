import Foundation

/// The two sides of the Watch-log feature that need no WatchConnectivity (2026-10-16): what the iPhone and the Watch
/// tell each other, and how each side reacts. The system session itself sits behind small protocols
/// (`WatchSessionControlling` on the iPhone, `WatchLogSending` on the Watch), so all of this is tested on every
/// platform.

/// The state of a "debug logging" switch and when it was last changed (seconds since 1970). The newer change wins when
/// iPhone and Watch disagree.
public struct LoggingSwitch: Equatable, Sendable {
    public var isOn: Bool
    public var changedAt: TimeInterval

    public init(isOn: Bool, changedAt: TimeInterval) {
        self.isOn = isOn
        self.changedAt = changedAt
    }
}

public extension DebugLog {
    nonisolated static let changedAtUserDefaultsKey = "debugLoggingChangedAt"

    /// Switches logging and remembers when (the switch in Settings goes through here).
    nonisolated static func setEnabled(_ isOn: Bool, at date: Date = Date(), in defaults: UserDefaults = .standard) {
        defaults.set(isOn, forKey: isEnabledUserDefaultsKey)
        defaults.set(date.timeIntervalSince1970, forKey: changedAtUserDefaultsKey)
    }

    /// The effective state of the switch; never changed by hand means "since forever" (0).
    nonisolated static func loggingSwitch(in defaults: UserDefaults = .standard) -> LoggingSwitch {
        LoggingSwitch(isOn: isEnabled(in: defaults), changedAt: defaults.double(forKey: changedAtUserDefaultsKey))
    }

    /// Takes over a switch change from the other device when it is newer than the local one; returns whether it did.
    @discardableResult
    nonisolated static func apply(_ remote: LoggingSwitch, in defaults: UserDefaults = .standard) -> Bool {
        guard remote.changedAt > loggingSwitch(in: defaults).changedAt else { return false }
        defaults.set(remote.isOn, forKey: isEnabledUserDefaultsKey)
        defaults.set(remote.changedAt, forKey: changedAtUserDefaultsKey)
        return true
    }
}

/// What the Watch tells the iPhone about its log (the iPhone shows it next to the switch).
public struct WatchLogReport: Equatable, Sendable {
    public var isLoggingOn: Bool
    public var changedAt: TimeInterval
    public var entryCount: Int
    public var reportedAt: TimeInterval

    public init(isLoggingOn: Bool, changedAt: TimeInterval, entryCount: Int, reportedAt: TimeInterval) {
        self.isLoggingOn = isLoggingOn
        self.changedAt = changedAt
        self.entryCount = entryCount
        self.reportedAt = reportedAt
    }

    var dictionary: [String: Any] {
        [
            WatchLogKeys.reportLoggingOn: isLoggingOn, WatchLogKeys.reportChangedAt: changedAt,
            WatchLogKeys.reportEntryCount: entryCount, WatchLogKeys.reportedAt: reportedAt,
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let isOn = dictionary[WatchLogKeys.reportLoggingOn] as? Bool,
              let changedAt = dictionary[WatchLogKeys.reportChangedAt] as? Double,
              let entryCount = dictionary[WatchLogKeys.reportEntryCount] as? Int,
              let reportedAt = dictionary[WatchLogKeys.reportedAt] as? Double else { return nil }
        self.init(isLoggingOn: isOn, changedAt: changedAt, entryCount: entryCount, reportedAt: reportedAt)
    }
}

/// The keys of the messages between the devices.
public enum WatchLogKeys {
    // iPhone -> Watch (application context, merged with `shiftsChangedAt`)
    static let logRequestID = "logRequestID"
    static let loggingOn = "watchLoggingOn"
    static let loggingChangedAt = "watchLoggingChangedAt"
    // iPhone -> Watch (live message)
    static let requestLog = "requestLog"
    // Watch -> iPhone (report, application context of the Watch)
    static let reportLoggingOn = "loggingOn"
    static let reportChangedAt = "loggingChangedAt"
    static let reportEntryCount = "entryCount"
    static let reportedAt = "reportedAt"
    // Watch -> iPhone (file metadata)
    static let fileEntryCount = "entryCount"
    static let fileSentAt = "sentAt"
}

/// The iPhone's application context for the Watch. `updateApplicationContext` replaces the whole dictionary, so the
/// pieces (shifts changed, log request, logging switch) are kept here and always sent together.
struct WatchContextState {
    private let defaults: UserDefaults
    private let key = "watchContextState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var values: [String: Any] {
        get { defaults.dictionary(forKey: key) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: key) }
    }

    /// What goes to the Watch right now.
    var dictionary: [String: Any] { values }

    func noteShiftsChanged(at timestamp: TimeInterval) {
        values["shiftsChangedAt"] = timestamp
    }

    /// A new request (the Watch answers each id once).
    func noteLogRequest(id: String) {
        values[WatchLogKeys.logRequestID] = id
    }

    /// The logging wish the iPhone last sent, nil when it never did.
    var loggingSwitch: LoggingSwitch? {
        guard let on = values[WatchLogKeys.loggingOn] as? Bool, let at = values[WatchLogKeys.loggingChangedAt] as? Double else { return nil }
        return LoggingSwitch(isOn: on, changedAt: at)
    }

    func noteLoggingSwitch(_ loggingSwitch: LoggingSwitch) {
        values[WatchLogKeys.loggingOn] = loggingSwitch.isOn
        values[WatchLogKeys.loggingChangedAt] = loggingSwitch.changedAt
    }
}

/// What the Watch can do with the session (its side of `WCSession`).
public protocol WatchLogSending {
    func transferFile(_ url: URL, metadata: [String: Any])
    func sendReport(_ report: [String: Any]) throws
}

public enum SendLogResult: Equatable, Sendable {
    /// The file was handed to the connection (it arrives when the iPhone can take it).
    case queued(entryCount: Int)
    /// There is no log (nothing logged yet, or logging never ran).
    case noLog
}

/// The Watch's side: sends its log on request or on the user's tap, applies the switch of the iPhone, reports its
/// state.
public struct WatchLogResponder {
    private let sender: WatchLogSending
    private let defaults: UserDefaults
    private let logFile: URL
    private let handledRequestKey = "watchLogLastHandledRequest"

    public init(sender: WatchLogSending, defaults: UserDefaults = .standard, logFile: URL? = nil) {
        self.sender = sender
        self.defaults = defaults
        self.logFile = logFile ?? DebugLog.fileURL
    }

    private var entryCount: Int {
        let data = (try? Data(contentsOf: logFile)) ?? Data()
        return data.split(separator: UInt8(ascii: "\n")).count
    }

    /// Hands the log file to the connection; also tells the iPhone the current state.
    @discardableResult
    public func sendLog(now: Date = Date()) -> SendLogResult {
        defer { reportState(now: now) }
        let count = entryCount
        guard count > 0 else { return .noLog }
        sender.transferFile(logFile, metadata: [
            WatchLogKeys.fileEntryCount: count, WatchLogKeys.fileSentAt: now.timeIntervalSince1970,
        ])
        return .queued(entryCount: count)
    }

    /// Reacts to the iPhone's application context: a new log request, a newer logging switch.
    public func handleContext(_ context: [String: Any], now: Date = Date()) {
        if let on = context[WatchLogKeys.loggingOn] as? Bool, let changedAt = context[WatchLogKeys.loggingChangedAt] as? Double {
            DebugLog.apply(LoggingSwitch(isOn: on, changedAt: changedAt), in: defaults)
        }
        if let id = context[WatchLogKeys.logRequestID] as? String, id != defaults.string(forKey: handledRequestKey) {
            defaults.set(id, forKey: handledRequestKey)
            sendLog(now: now)
        } else {
            reportState(now: now)
        }
    }

    /// A live request from the iPhone (the Watch app is reachable).
    public func handleMessage(_ message: [String: Any], now: Date = Date()) {
        guard let id = message[WatchLogKeys.requestLog] as? String, id != defaults.string(forKey: handledRequestKey) else { return }
        defaults.set(id, forKey: handledRequestKey)
        sendLog(now: now)
    }

    /// Tells the iPhone whether logging is on here, since when, and how many entries there are.
    public func reportState(now: Date = Date()) {
        let state = DebugLog.loggingSwitch(in: defaults)
        let report = WatchLogReport(
            isLoggingOn: state.isOn, changedAt: state.changedAt, entryCount: entryCount, reportedAt: now.timeIntervalSince1970)
        try? sender.sendReport(report.dictionary)
    }
}

/// The iPhone's side of the receiving end: stores the files the Watch sends and remembers the Watch's last report.
public struct WatchLogInbox {
    public static let didChangeNotification = Notification.Name("WatchLogInboxDidChange")

    private let logs: ReceivedWatchLogs
    private let defaults: UserDefaults
    private let reportKey = "watchLogLastReport"

    public init(logs: ReceivedWatchLogs = ReceivedWatchLogs(), defaults: UserDefaults = .standard) {
        self.logs = logs
        self.defaults = defaults
    }

    /// Stores a received log file; returns whether that worked.
    @discardableResult
    public func receiveFile(at url: URL, now: Date = Date()) -> Bool {
        let stored = (try? logs.store(url, receivedAt: now)) != nil
        if stored { NotificationCenter.default.post(name: Self.didChangeNotification, object: nil) }
        return stored
    }

    /// Remembers the Watch's report (ignores a message that is none).
    public func receiveReport(_ dictionary: [String: Any]) {
        guard let report = WatchLogReport(dictionary: dictionary) else { return }
        defaults.set(report.dictionary, forKey: reportKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// The Watch's last known state, nil until it ever reported.
    public var lastReport: WatchLogReport? {
        defaults.dictionary(forKey: reportKey).flatMap(WatchLogReport.init(dictionary:))
    }
}

/// What the iPhone shows next to "Log on Apple Watch": the state to display and whether it is confirmed.
public struct WatchLoggingStatus: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The Watch never reported.
        case unknown
        /// The Watch reported this state at `reportedAt`.
        case reported(reportedAt: Date)
        /// The iPhone's wish is newer than the Watch's last report: not confirmed yet.
        case waiting
    }

    public let isOn: Bool
    public let kind: Kind

    /// `desired`: the switch the iPhone last sent; `report`: the Watch's last report.
    public init(desired: LoggingSwitch?, report: WatchLogReport?) {
        switch (desired, report) {
        case let (desired?, report?) where desired.changedAt > report.changedAt:
            isOn = desired.isOn
            kind = .waiting
        case let (desired?, nil):
            isOn = desired.isOn
            kind = .waiting
        case let (_, report?):
            isOn = report.isLoggingOn
            kind = .reported(reportedAt: Date(timeIntervalSince1970: report.reportedAt))
        case (nil, nil):
            isOn = DebugLog.defaultEnabled
            kind = .unknown
        }
    }
}
