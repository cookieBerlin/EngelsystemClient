import Foundation

/// The debug logs the Apple Watch sent to this iPhone (2026-10-16): a folder of text files in the caches directory
/// (not backed up), newest first, at most `maxFiles` of them. The files have the same line format as the
/// iPhone's own log, so the log viewer reads them with `entries(of:)`.
public struct ReceivedWatchLogs {
    public struct Item: Identifiable, Equatable, Sendable {
        public let url: URL
        public let receivedAt: Date
        public let entryCount: Int
        public let byteCount: Int
        public var id: String { url.lastPathComponent }
    }

    /// The oldest files beyond this number are deleted when a new one arrives.
    public static let maxFiles = 20

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ReceivedWatchLogs")
    }

    private let directory: URL

    public init(directory: URL = ReceivedWatchLogs.defaultDirectory) {
        self.directory = directory
    }

    /// Takes over a received file (moves it into the folder, named after the time it arrived) and trims the folder.
    @discardableResult
    public func store(_ source: URL, receivedAt: Date = Date()) throws -> Item {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "watch-log-\(Self.stamp(receivedAt)).log"
        let target = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: source, to: target)
        // Backups never need these files.
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableTarget = target
        try? mutableTarget.setResourceValues(excluded)
        trim()
        return item(at: target, receivedAt: receivedAt)
    }

    /// Every stored log, newest first.
    public func list() -> [Item] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "log" }
            .map { item(at: $0, receivedAt: Self.receivedAt(of: $0)) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// The parsed entries of one stored log, oldest first (as in the file).
    public func entries(of item: Item) -> [DebugLogEntry] {
        guard let text = try? String(contentsOf: item.url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { DebugLogEntry.parse(persistedLine: String($0)) }
    }

    public func delete(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
    }

    public func deleteAll() {
        list().forEach(delete)
    }

    private func trim() {
        list().dropFirst(Self.maxFiles).forEach(delete)
    }

    private func item(at url: URL, receivedAt: Date) -> Item {
        // An unreadable file counts as empty (written without `??`: no never-taken fallback to cover).
        let data = [try? Data(contentsOf: url)].compactMap { $0 }.reduce(Data()) { $1 }
        let entryCount = data.split(separator: UInt8(ascii: "\n")).count
        return Item(url: url, receivedAt: receivedAt, entryCount: entryCount, byteCount: data.count)
    }

    private static func stamp(_ date: Date) -> String {
        String(Int((date.timeIntervalSince1970 * 1000).rounded()))
    }

    private static func receivedAt(of url: URL) -> Date {
        let digits = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "watch-log-", with: "")
        // A file name that is no timestamp counts as received at the very beginning (no `??` fallback to cover).
        let milliseconds = [Double(digits)].compactMap { $0 }.reduce(0) { $1 }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
