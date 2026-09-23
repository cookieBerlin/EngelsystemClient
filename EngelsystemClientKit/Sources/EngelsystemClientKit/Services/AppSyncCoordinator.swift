import Foundation
import SwiftData

/// Syncs every active instance's data in one call — the shared logic behind the iOS
/// app-start sync, the iOS background/interval sync, and the Watch app-start sync
/// (2026-09-22, user-requested "reduce server load" feature; see CLAUDE.md). Each of
/// those three call sites otherwise duplicated the same "loop instances, resolve a
/// credential, sync each domain, sync shift notifications" shape the per-screen
/// ViewModels already had.
///
/// Deliberately headless: no `isLoading`/`errorMessage`/`isUnauthorized` state like
/// the per-screen ViewModels have — a 401 here doesn't navigate anywhere (there's no
/// screen the user is looking at to navigate *from*), it just leaves that instance's
/// data as it was; the per-screen ViewModels still own that behavior for pull-to-refresh.
@MainActor
public struct AppSyncCoordinator {
    public struct Progress: Equatable, Sendable {
        public let completed: Int
        public let total: Int
        public let description: String

        public init(completed: Int, total: Int, description: String) {
            self.completed = completed
            self.total = total
            self.description = description
        }
    }

    private let shiftSyncService: ShiftSyncService
    private let newsSyncService: NewsSyncService
    private let profileSyncService: ProfileSyncService
    private let credentialResolver: InstanceCredentialResolver
    private let notificationScheduler: NotificationScheduler
    private let newsNotifier: NewsNotifier

    // Several of these types are @MainActor, so their defaults can't be evaluated as
    // literal parameter defaults (evaluated in a nonisolated context) — same reason
    // every ViewModel in this project constructs its @MainActor defaults inside the
    // (already MainActor-isolated) init body instead. See e.g. ShiftsViewModel.
    public init(
        shiftSyncService: ShiftSyncService? = nil,
        newsSyncService: NewsSyncService? = nil,
        profileSyncService: ProfileSyncService? = nil,
        credentialResolver: InstanceCredentialResolver? = nil,
        notificationScheduler: NotificationScheduler = NotificationScheduler(),
        newsNotifier: NewsNotifier = NewsNotifier()
    ) {
        self.shiftSyncService = shiftSyncService ?? ShiftSyncService()
        self.newsSyncService = newsSyncService ?? NewsSyncService()
        self.profileSyncService = profileSyncService ?? ProfileSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
        self.notificationScheduler = notificationScheduler
        self.newsNotifier = newsNotifier
    }

    /// Syncs Shifts (+ shift notifications) for every instance, and — unless
    /// `shiftsOnly` (the Watch's minimal scope, which has no News/Profile catalog at
    /// all) — News and Profile too. Returns whether every instance synced cleanly.
    ///
    /// `notifyOnNewNews` should only be `true` for the background/interval sync path
    /// (see `NewsNotifier`) — the app-start sync and pull-to-refresh both happen while
    /// the user is already looking at the app, so a push notification there would just
    /// be noise; it defaults to `false` so a caller has to opt in deliberately.
    ///
    /// Reports one `Progress` update per completed unit of work (one unit per domain
    /// per instance — 1 for `shiftsOnly`, 3 otherwise), including failed ones, so
    /// `completed` always reaches `total` by the end regardless of errors — a caller
    /// driving a progress bar from this doesn't need its own separate "did it finish"
    /// bookkeeping.
    /// `handleNotifications` exists purely so tests can exercise the sync logic
    /// without touching `NotificationScheduler.requestAuthorizationIfNeeded()` —
    /// that method calls the real `UNUserNotificationCenter.notificationSettings()`,
    /// which returns `UNNotificationSettings`, a type with no public initializer at
    /// all, so no fake can honestly stand in for it (see the existing, deliberately
    /// untested boundary in `NotificationSchedulerTests`'s `FakeNotificationCenter`).
    /// Always `true` in production; only ever passed `false` from tests.
    @discardableResult
    public func syncEverything(
        instances: [Instance],
        in modelContext: ModelContext,
        shiftsOnly: Bool = false,
        notifyOnNewNews: Bool = false,
        handleNotifications: Bool = true,
        onProgress: (Progress) -> Void = { _ in }
    ) async -> Bool {
        let stepsPerInstance = shiftsOnly ? 1 : 3
        let total = max(instances.count * stepsPerInstance, 1)
        var completed = 0
        var allSucceeded = true

        func reportStep(_ description: String) {
            completed += 1
            onProgress(Progress(completed: completed, total: total, description: description))
        }

        // 2026-09-23, user-requested "check the data flow for logging gaps": this
        // coordinator is the *only* path for app-start sync, background sync, and
        // the main page's own pull-to-refresh (Shifts/News/ProfileViewModel's own
        // logging only ever covers their own screen's pull-to-refresh) — previously
        // it logged nothing at all, making those three triggers completely invisible.
        DebugLog.log("AppSyncCoordinator starting sync of \(instances.count) instance(s) (shiftsOnly: \(shiftsOnly))")

        var allShifts: [CachedShift] = []
        var newNewsByInstance: [(item: CachedNews, instanceName: String)] = []

        for instance in instances {
            let credential = try? credentialResolver.credential(for: instance)
            if credential == nil {
                allSucceeded = false
                DebugLog.log("AppSyncCoordinator: no credential for '\(instance.name)' — skipping", level: .error)
            }

            if let credential {
                do {
                    let shifts = try await shiftSyncService.sync(instance: instance, credential: credential, in: modelContext)
                    allShifts.append(contentsOf: shifts)
                    DebugLog.log("AppSyncCoordinator: synced \(shifts.count) shift(s) for '\(instance.name)'")
                } catch {
                    guard !(error is CancellationError) else { continue }
                    allSucceeded = false
                    DebugLog.log("AppSyncCoordinator: Shifts failed for '\(instance.name)': \(error)", level: .error)
                }
            }
            reportStep("Shifts – \(instance.name)")

            if !shiftsOnly {
                if let credential {
                    do {
                        let result = try await newsSyncService.sync(instance: instance, credential: credential, in: modelContext)
                        newNewsByInstance.append(contentsOf: result.insertedItems.map { (item: $0, instanceName: instance.name) })
                        DebugLog.log("AppSyncCoordinator: synced \(result.items.count) news item(s), \(result.insertedItems.count) new, for '\(instance.name)'")
                    } catch {
                        if !(error is CancellationError) {
                            allSucceeded = false
                            DebugLog.log("AppSyncCoordinator: News failed for '\(instance.name)': \(error)", level: .error)
                        }
                    }
                }
                reportStep("News – \(instance.name)")

                if let credential {
                    do {
                        _ = try await profileSyncService.syncProfile(instance: instance, credential: credential, in: modelContext)
                        _ = try await profileSyncService.syncWorklogs(instance: instance, credential: credential, in: modelContext)
                        _ = try await profileSyncService.syncAngelTypes(instance: instance, credential: credential, in: modelContext)
                        DebugLog.log("AppSyncCoordinator: synced Profile for '\(instance.name)'")
                    } catch {
                        if !(error is CancellationError) {
                            allSucceeded = false
                            DebugLog.log("AppSyncCoordinator: Profile failed for '\(instance.name)': \(error)", level: .error)
                        }
                    }
                }
                reportStep("Profile – \(instance.name)")
            }
        }

        if handleNotifications {
            if allSucceeded, await notificationScheduler.requestAuthorizationIfNeeded() {
                let leadTimes = NotificationLeadTimeSettings.resolve(in: modelContext).leadTimesMinutes
                await notificationScheduler.syncNotifications(for: allShifts, leadTimes: leadTimes)
            }

            if notifyOnNewNews, !newNewsByInstance.isEmpty, await notificationScheduler.requestAuthorizationIfNeeded() {
                let newItems = newNewsByInstance.map(\.item)
                let instanceName = newNewsByInstance.count == 1 ? newNewsByInstance.first?.instanceName : nil
                await newsNotifier.notify(newItems: newItems, instanceName: instanceName)
            }
        }

        DebugLog.log("AppSyncCoordinator finished (allSucceeded: \(allSucceeded))", level: allSucceeded ? .info : .warning)
        return allSucceeded
    }
}
