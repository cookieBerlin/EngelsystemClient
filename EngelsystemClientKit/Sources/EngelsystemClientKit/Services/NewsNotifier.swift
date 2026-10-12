import Foundation
import UserNotifications

/// Posts a local notification when a News sync discovers posts that weren't cached
/// before, so the user finds out even without having the News screen open. Distinct
/// from `NotificationScheduler` (shift-start reminders, planned ahead of time for a
/// future fire date): this fires immediately, once per sync, for content that already
/// exists right now — so it uses `trigger: nil` rather than a calendar trigger.
///
/// 2026-09-22, user-requested. Wired into `NewsViewModel.refresh` for every News sync
/// today (there's no separate "background sync" yet) — once that lands, this should
/// only fire from the background/interval path, not from a sync the user triggered
/// while already looking at the News screen (pull-to-refresh) or from the app-start
/// sync. Until then, note that iOS won't actually display a banner for this while the
/// app is in the foreground (the default `UNUserNotificationCenterDelegate` behavior,
/// since this project doesn't implement `willPresent`) — which today is *always*, since
/// News only ever syncs while the app is open. The notification becomes visible once
/// the background sync exists.
public struct NewsNotifier {
    public static let identifierPrefix = "new-news-"

    /// `UserDefaults` key backing the Settings toggle — mirrors `NotificationScheduler
    /// .leadTimeUserDefaultsKey`'s pattern of being defined once here, read by both the
    /// Settings UI (`@AppStorage`) and this notifier.
    public static let enabledUserDefaultsKey = "notifyOnNewNewsEnabled"

    /// Defaults to on — this is framed as an opt-out, not an opt-in.
    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: enabledUserDefaultsKey) as? Bool) ?? true
    }

    public struct Content: Equatable {
        public let title: String
        public let body: String
    }

    /// Pure content-building step, kept separate from posting so it's unit-testable
    /// without a notification center — mirrors `NotificationScheduler.plan`. `nil` when
    /// there's nothing new to report. Bundles everything from one sync pass into a
    /// *single* notification rather than one per item, so an instance that's been
    /// dormant for a while doesn't spam the user with a dozen banners the moment it's
    /// synced again. `instanceName` is only used (and only meaningful) for the
    /// single-item case — with more than one new item, attributing each to its instance
    /// would need per-item names this type doesn't carry, and would clutter a summary
    /// that's already just a list of titles.
    public static func content(for items: [CachedNews], instanceName: String?) -> Content? {
        guard !items.isEmpty else { return nil }

        if items.count == 1, let item = items.first {
            let preview = CachedNews.textParts(from: item.text).preview
            let body = instanceName.map { "\($0) — \(preview)" } ?? preview
            return Content(title: item.title, body: body)
        }

        let title = "\(items.count) New Announcements"
        let body = items.map(\.title).joined(separator: ", ")
        return Content(title: title, body: body)
    }

    private let center: NotificationCenterScheduling

    /// The real-center convenience initializer, `init()`, lives in `SystemNotificationCenter.swift`.
    public init(center: NotificationCenterScheduling) {
        self.center = center
    }

    /// Posts one notification for everything new from a single sync pass, if enabled
    /// and there's anything to report. Does nothing (no-op) otherwise — callers don't
    /// need to check `isEnabled`/emptiness themselves first.
    public func notify(newItems: [CachedNews], instanceName: String?) async {
        guard !newItems.isEmpty else { return }
        guard Self.isEnabled() else {
            DebugLog.log("NewsNotifier skipped \(newItems.count) new item(s) — disabled in Settings")
            return
        }
        guard let content = Self.content(for: newItems, instanceName: instanceName) else { return }

        let mutableContent = UNMutableNotificationContent()
        mutableContent.title = content.title
        mutableContent.body = content.body
        mutableContent.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + UUID().uuidString,
            content: mutableContent,
            trigger: nil
        )
        do {
            try await center.add(request)
            DebugLog.log("NewsNotifier posted a notification for \(newItems.count) new item(s)")
        } catch {
            DebugLog.log("NewsNotifier failed to post notification: \(error)", level: .error)
        }
    }
}
