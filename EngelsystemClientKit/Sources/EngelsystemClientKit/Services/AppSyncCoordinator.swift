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
/// The counters of one `syncEverything` run, shared by the per-instance tasks.
@MainActor
private final class RunState {
    var failures = 0
    /// Every shift sync succeeded (reminders are only planned then).
    var shiftsOK = true
    var completed = 0
    var stepsDone: [UUID: Int] = [:]
    var failedInstances: Set<UUID> = []
    var allShifts: [CachedShift] = []
    var newNews: [(item: CachedNews, instanceName: String)] = []
}

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
    private let locationSyncService: LocationSyncService
    private let credentialResolver: InstanceCredentialResolver
    private let notificationScheduler: NotificationScheduler
    private let newsNotifier: NewsNotifier
    private let apiClient: APIClient
    private let capabilities: ServerCapabilities

    // Several of these types are @MainActor, so their defaults can't be evaluated as
    // literal parameter defaults (evaluated in a nonisolated context) — same reason
    // every ViewModel in this project constructs its @MainActor defaults inside the
    // (already MainActor-isolated) init body instead. See e.g. ShiftsViewModel.
    public init(
        shiftSyncService: ShiftSyncService? = nil,
        newsSyncService: NewsSyncService? = nil,
        profileSyncService: ProfileSyncService? = nil,
        locationSyncService: LocationSyncService? = nil,
        credentialResolver: InstanceCredentialResolver? = nil,
        notificationScheduler: NotificationScheduler = NotificationScheduler(),
        newsNotifier: NewsNotifier = NewsNotifier(),
        apiClient: APIClient? = nil,
        capabilities: ServerCapabilities? = nil
    ) {
        self.capabilities = capabilities ?? .shared
        self.shiftSyncService = shiftSyncService ?? ShiftSyncService()
        self.newsSyncService = newsSyncService ?? NewsSyncService()
        self.profileSyncService = profileSyncService ?? ProfileSyncService()
        self.locationSyncService = locationSyncService ?? LocationSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
        self.notificationScheduler = notificationScheduler
        self.newsNotifier = newsNotifier
        self.apiClient = apiClient ?? APIClient.shared
    }

    /// Syncs Shifts (+ shift notifications) for every instance, and — unless
    /// `shiftsOnly` (the Watch's minimal scope, which has no News/Profile/Locations
    /// catalog at all) — News, Profile, and Locations too. Returns whether every
    /// instance synced cleanly.
    ///
    /// `notifyOnNewNews` should only be `true` for the background/interval sync path
    /// (see `NewsNotifier`) — the app-start sync and pull-to-refresh both happen while
    /// the user is already looking at the app, so a push notification there would just
    /// be noise; it defaults to `false` so a caller has to opt in deliberately.
    ///
    /// Reports one `Progress` update per completed unit of work (one unit per domain
    /// per instance — 1 for `shiftsOnly`, 4 otherwise), including failed ones, so
    /// `completed` always reaches `total` by the end regardless of errors — a caller
    /// driving a progress bar from this doesn't need its own separate "did it finish"
    /// bookkeeping.
    /// `maxConcurrentInstances`: how many instances are synced at the same time (0 = all at once); `nil`
    /// takes the device's "Parallel Syncs" setting (`ParallelSyncSetting`).
    /// `reminderInstances`: when only some instances are synced (one freshly switched on), the shift
    /// reminders must still be planned over **all** active instances' cached shifts — planning over
    /// the synced ones alone would cancel the others' reminders. `nil` plans over what was synced.
    /// `handleNotifications: false` skips all notification work (shift reminders and the
    /// new-news announcement). Always `true` in production; the app targets' view-model
    /// tests pass `false` so they don't depend on a notification center at all.
    @discardableResult
    public func syncEverything(
        instances: [Instance],
        in modelContext: ModelContext,
        shiftsOnly: Bool = false,
        notifyOnNewNews: Bool = false,
        handleNotifications: Bool = true,
        reminderInstances: [Instance]? = nil,
        control: SyncControl? = nil,
        maxConcurrentInstances: Int? = nil,
        onEvent: @escaping (SyncEvent) -> Void = { _ in },
        onProgress: @escaping (Progress) -> Void = { _ in }
    ) async -> Bool {
        let control = control ?? SyncControl()
        let state = RunState()
        // `nil`: the device's own "Parallel Syncs" setting.
        let requestedLimit = ParallelSyncSetting.clamp(maxConcurrentInstances ?? ParallelSyncSetting.stored())
        let total = max(instances.count * (shiftsOnly ? 1 : 5), 1)
        // Shift reminders only depend on the *shift* syncs of every instance — a failing News,
        // Profile, Locations or Messages step must not suppress them (`state.shiftsOK`).

        /// One step is done: counts it, reports it and — if another follows — announces that one. Also
        /// restarts the no-progress timer.
        func finishStep(_ instance: Instance, _ area: String, next: String?) {
            state.completed += 1
            state.stepsDone[instance.id, default: 0] += 1
            onProgress(Progress(completed: state.completed, total: total, description: "\(area) – \(instance.name)"))
            onEvent(.stepFinished(id: instance.id, area: area))
            if let next { onEvent(.stepStarted(id: instance.id, area: next)) }
            control.progressMade(instance.id)
        }

        // 2026-09-23, user-requested "check the data flow for logging gaps": this
        // coordinator is the *only* path for app-start sync, background sync, and
        // the main page's own pull-to-refresh (Shifts/News/ProfileViewModel's own
        // logging only ever covers their own screen's pull-to-refresh) — previously
        // it logged nothing at all, making those three triggers completely invisible.
        DebugLog.log("AppSyncCoordinator starting sync of \(instances.count) instance(s) (shiftsOnly: \(shiftsOnly))")

        func fail(_ instance: Instance) {
            state.failures += 1
            state.failedInstances.insert(instance.id)
        }

        /// Syncs one instance; runs as its own task so it can be cancelled (timeout, skip, stop).
        func runInstance(_ instance: Instance) async {
            let credential = try? credentialResolver.credential(for: instance)
            if credential == nil {
                fail(instance)
                state.shiftsOK = false
                DebugLog.log("AppSyncCoordinator: no credential for '\(instance.name)' — skipping", level: .error)
            }

            if let credential {
                do {
                    let result = try await shiftSyncService.sync(instance: instance, credential: credential, in: modelContext)
                    state.allShifts.append(contentsOf: result.shifts)
                    DebugLog.log("AppSyncCoordinator: synced \(result.shifts.count) shift(s) for '\(instance.name)'")
                    capabilities.record(.shifts, state: .available, evidence: .probe, for: instance.id)
                    // 2026-09-23, "keep the Watch fresh" feature: bump the CloudKit-synced
                    // signal only on a genuine change, not on every routine sync — see
                    // Instance.shiftsChangedAt and WatchConnectivityBridge. Safe to call
                    // unconditionally regardless of which platform is running this
                    // coordinator (no-op on watchOS/macOS).
                    if result.didChange {
                        instance.shiftsChangedAt = Date()
                        instance.touch()
                        try? modelContext.save()
                        WatchConnectivityBridge.notifyShiftsChanged()
                    }
                } catch {
                    guard !(error is CancellationError) else { return }
                    // A 403/404 is "not allowed"/"not offered", not a failure to report (ADR 0015); the
                    // reminders are still left alone because no shift list was received.
                    if !capabilities.record(.shifts, afterError: error, for: instance.id) { fail(instance) }
                    state.shiftsOK = false
                    DebugLog.log("AppSyncCoordinator: Shifts failed for '\(instance.name)': \(error)", level: .error)
                }
            }
            finishStep(instance, "Shifts", next: "News")
            if Task.isCancelled { return }

            if !shiftsOnly {
                if let credential {
                    do {
                        let result = try await newsSyncService.sync(instance: instance, credential: credential, in: modelContext)
                        state.newNews.append(contentsOf: result.insertedItems.map { (item: $0, instanceName: instance.name) })
                        DebugLog.log("AppSyncCoordinator: synced \(result.items.count) news item(s), \(result.insertedItems.count) new, for '\(instance.name)'")
                        capabilities.record(.news, state: .available, evidence: .probe, for: instance.id)
                    } catch {
                        if !(error is CancellationError) {
                            if !capabilities.record(.news, afterError: error, for: instance.id) {
                                fail(instance)
                            }
                            DebugLog.log("AppSyncCoordinator: News failed for '\(instance.name)': \(error)", level: .error)
                        }
                    }
                }
                finishStep(instance, "News", next: "Profile")
                if Task.isCancelled { return }

                if let credential {
                    do {
                        _ = try await profileSyncService.syncProfile(instance: instance, credential: credential, in: modelContext)
                        do {
                            _ = try await profileSyncService.syncWorklogs(instance: instance, credential: credential, in: modelContext)
                            capabilities.record(.profileWorklogs, state: .available, evidence: .probe, for: instance.id)
                        } catch {
                            if !capabilities.record(.profileWorklogs, afterError: error, for: instance.id) { throw error }
                        }
                        do {
                            _ = try await profileSyncService.syncAngelTypes(instance: instance, credential: credential, in: modelContext)
                            capabilities.record(.profileAngelTypes, state: .available, evidence: .probe, for: instance.id)
                        } catch {
                            if !capabilities.record(.profileAngelTypes, afterError: error, for: instance.id) { throw error }
                        }
                        DebugLog.log("AppSyncCoordinator: synced Profile for '\(instance.name)'")
                    } catch {
                        if !(error is CancellationError) {
                            fail(instance)
                            DebugLog.log("AppSyncCoordinator: Profile failed for '\(instance.name)': \(error)", level: .error)
                        }
                    }
                }
                finishStep(instance, "Profile", next: "Locations")
                if Task.isCancelled { return }

                if let credential {
                    do {
                        let locations = try await locationSyncService.sync(instance: instance, credential: credential, in: modelContext)
                        DebugLog.log("AppSyncCoordinator: synced \(locations.count) location(s) for '\(instance.name)'")
                    } catch {
                        if !(error is CancellationError) {
                            fail(instance)
                            DebugLog.log("AppSyncCoordinator: Locations failed for '\(instance.name)': \(error)", level: .error)
                        }
                    }
                }
                finishStep(instance, "Locations", next: "Messages")
                if Task.isCancelled { return }

                if let credential {
                    // COMPAT(#1720), 2026-09-23, Messages feature: a lightweight capability re-check, not
                    // a data sync — updates `Instance.messagesSupported` (which gates the
                    // whole Messages sidebar entry) so a server that gains or loses support
                    // is picked up without a dedicated Setup/Edit-time probe. Cheap: a single
                    // GET, no persistence beyond the one Bool.
                    let state = await apiClient.messagesState(credential)
                    let supported = state != .notOffered
                    capabilities.record(
                        .messages, state: state, evidence: state == .available ? .probe : state == .notAllowed ? .forbidden : .notFound,
                        privilege: state == .notAllowed ? ServerFeature.messages.requiredPrivilege : nil, for: instance.id)
                    if instance.messagesSupported != supported {
                        instance.messagesSupported = supported
                        instance.touch()
                        try? modelContext.save()
                    }
                }
                finishStep(instance, "Messages", next: nil)
                if Task.isCancelled { return }
            }
    
        }

        let stepsPerInstance = shiftsOnly ? 1 : 5
        onEvent(.planned(instances.map { SyncPlannedInstance(id: $0.id, name: $0.name, totalSteps: stepsPerInstance) }))

        /// Syncs one instance start to finish: skip check, worker task with its no-progress watchdog, outcome.
        func runOne(_ instance: Instance) async {
            if control.consumeSkip(instance.id) {
                state.failures += 1
                state.shiftsOK = false
                completeSteps(of: instance, description: "Skipped – \(instance.name)")
                onEvent(.instanceFinished(id: instance.id, outcome: .skipped))
                return
            }
            onEvent(.instanceStarted(id: instance.id))
            onEvent(.stepStarted(id: instance.id, area: "Shifts"))
            let worker = Task { @MainActor in await runInstance(instance) }
            control.begin(instance.id, worker: worker)
            await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            let end = control.end(instance.id)

            let outcome: SyncInstanceOutcome
            if end.timedOut {
                outcome = .timedOut
            } else if end.skipped {
                outcome = .skipped
            } else {
                outcome = state.failedInstances.contains(instance.id) ? .failed : .succeeded
            }
            if outcome == .timedOut || outcome == .skipped {
                state.failures += 1
                state.shiftsOK = false
                DebugLog.log("AppSyncCoordinator: '\(instance.name)' \(outcome == .timedOut ? "made no progress for too long" : "was skipped")", level: .warning)
            }
            // A cancelled instance reports fewer steps; `completed` still reaches the instance's share of `total`.
            if !Task.isCancelled { completeSteps(of: instance, description: "\(outcome) – \(instance.name)") }
            onEvent(.instanceFinished(id: instance.id, outcome: outcome))
        }

        /// Counts the steps an instance did not report (skipped, timed out, cancelled) as done.
        func completeSteps(of instance: Instance, description: String) {
            let missing = stepsPerInstance - state.stepsDone[instance.id, default: 0]
            guard missing > 0 else { return }
            state.completed += missing
            state.stepsDone[instance.id] = stepsPerInstance
            onProgress(Progress(completed: state.completed, total: total, description: description))
        }

        // Up to `limit` instances at a time (0 = all at once); the next one starts as soon as one finishes.
        let limit = max(1, requestedLimit == 0 ? instances.count : requestedLimit)
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            func startNext() {
                guard next < instances.count, !Task.isCancelled else { return }
                let instance = instances[next]
                next += 1
                group.addTask { @MainActor in await runOne(instance) }
            }
            for _ in 0..<min(limit, instances.count) { startNext() }
            while await group.next() != nil { startNext() }
        }

        if handleNotifications, state.shiftsOK, !Task.isCancelled, await notificationScheduler.requestAuthorizationIfNeeded() {
            let leadTimes = NotificationLeadTimeSettings.resolve(in: modelContext).leadTimesMinutes
            let reminderShifts = reminderInstances.map { Self.cachedShifts(of: $0, in: modelContext) } ?? state.allShifts
            await notificationScheduler.syncNotifications(for: reminderShifts, leadTimes: leadTimes)
        }

        if handleNotifications, notifyOnNewNews, !state.newNews.isEmpty, !Task.isCancelled, await notificationScheduler.requestAuthorizationIfNeeded() {
            let newItems = state.newNews.map(\.item)
            let instanceName = state.newNews.count == 1 ? state.newNews.first?.instanceName : nil
            await newsNotifier.notify(newItems: newItems, instanceName: instanceName)
        }

        let allSucceeded = state.failures == 0
        DebugLog.log("AppSyncCoordinator finished (allSucceeded: \(allSucceeded))", level: allSucceeded ? .info : .warning)
        return allSucceeded
    }

    /// Every cached shift of the given instances.
    static func cachedShifts(of instances: [Instance], in modelContext: ModelContext) -> [CachedShift] {
        let ids = Set(instances.map(\.id))
        // A failed fetch yields nothing (no `?? []` so there is no never-taken autoclosure to cover).
        return [try? modelContext.fetch(FetchDescriptor<CachedShift>())].compactMap { $0 }.flatMap { $0 }
            .filter { ids.contains($0.instanceID) }
    }
}
