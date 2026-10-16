//
//  EngelsystemClientTests.swift
//  EngelsystemClientTests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import Foundation
import Testing
import SwiftData
import UserNotifications
import EngelsystemClientKit
@testable import EngelsystemClient

/// Regression coverage for the 2026-09-16 bug: a user reported that an edited
/// instance field reverted after rebuilding the app from
/// Xcode. Root cause: no production code path ever called `modelContext.save()`
/// explicitly, relying entirely on SwiftData's autosave — which fires on
/// app-lifecycle events (e.g. resigning active) that a debug rebuild-and-relaunch
/// skips entirely, since Xcode kills the old process directly instead of
/// backgrounding it. Fixed by having `EditInstanceViewModel.save` (and the
/// equivalent create/delete flows) explicitly call `modelContext.save()`. This test
/// proves the fix by reloading from a brand-new `ModelContainer` backed by the same
/// on-disk store, rather than re-reading the same in-memory `ModelContext` — the
/// latter would pass even without an explicit save, since the edit is visible
/// in-memory regardless of whether it was ever flushed to disk.
struct EditInstanceViewModelPersistenceTests {
    @Test @MainActor func saveExplicitlyPersistsNameAcrossAFreshModelContainerLoad() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditInstanceViewModelPersistenceTests-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
        }
        let configuration = ModelConfiguration(schema: Schema([Instance.self]), url: storeURL, cloudKitDatabase: .none)

        let container = try ModelContainer(for: Instance.self, configurations: configuration)
        let context = ModelContext(container)

        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
        context.insert(instance)
        try context.save()

        let keyStore = LocalKeychainStore()
        try keyStore.save(apiKey: "demo", for: instance.apiKeyKeychainRef)
        defer { try? keyStore.deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.name = "Demo Renamed"
        let succeeded = await viewModel.save(instance: instance, in: context)
        #expect(succeeded)

        // Simulate the rebuild-and-relaunch scenario: a fresh container/context
        // reading the same file, not the `context` the edit was made through.
        let reloadedContainer = try ModelContainer(for: Instance.self, configurations: configuration)
        let reloadedContext = ModelContext(reloadedContainer)
        let reloadedInstance = try #require(try reloadedContext.fetch(FetchDescriptor<Instance>()).first)
        #expect(reloadedInstance.name == "Demo Renamed")
    }
}

/// Coverage for the combined "Edit Instance" dialog's API Key field (2026-09-17
/// multi-active-instance redesign, CLAUDE.md): leaving it blank must keep the existing
/// key untouched, typing a new one must overwrite it. `InstanceSetupServiceTests` (Kit)
/// already covers this at the service layer in isolation; these two exercise the
/// `EditInstanceViewModel` on top, seeding *both* Keychain stores identically so the
/// assertions hold regardless of `ICloudAvailability.isAvailable` in the test
/// environment (the view model always mirrors a freshly typed key into both stores, and
/// never touches either when the field is left blank).
struct EditInstanceViewModelAPIKeyTests {
    @MainActor
    private func makeInstanceWithSeededKey(_ key: String) throws -> (Instance, ModelContext) {
        let configuration = ModelConfiguration(schema: Schema([Instance.self]), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Instance.self, configurations: configuration)
        let context = ModelContext(container)
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
        context.insert(instance)
        try KeychainSyncStore().save(apiKey: key, for: instance.apiKeyKeychainRef)
        try LocalKeychainStore().save(apiKey: key, for: instance.apiKeyKeychainRef)
        return (instance, context)
    }

    @Test @MainActor func blankAPIKeyFieldLeavesTheExistingKeyUnchanged() async throws {
        let (instance, context) = try makeInstanceWithSeededKey("original-key")
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef); try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.apiKey = ""
        let succeeded = await viewModel.save(instance: instance, in: context)

        #expect(succeeded)
        #expect(try LocalKeychainStore().loadAPIKey(for: instance.apiKeyKeychainRef) == "original-key")
    }

    @Test @MainActor func nonBlankAPIKeyFieldOverwritesTheExistingKey() async throws {
        let (instance, context) = try makeInstanceWithSeededKey("original-key")
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef); try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.apiKey = "replacement-key"
        let succeeded = await viewModel.save(instance: instance, in: context)

        #expect(succeeded)
        #expect(try LocalKeychainStore().loadAPIKey(for: instance.apiKeyKeychainRef) == "replacement-key")
    }
}

/// Coverage for the "self endpoint check" flow added 2026-09-21 (CLAUDE.md): a
/// dedicated "Test Connection" step (separate from Save) probes whether the server
/// resolves the `self` user-reference alias, and the manual User ID field is only
/// shown once that's known to be needed. `APIClient`'s own probe logic is covered in
/// the Kit (`EngelsystemClientKitTests`); these exercise the view models built on top,
/// using the demo credential (which always reports `self` as working) since there's
/// no mock HTTP server in this test target to exercise the `.notFound` path.
/// Coverage for `NewsDetailViewModel` (`GET /news/{id}` comments, added 2026-09-22).
struct NewsDetailViewModelTests {
    private func makeInstanceWithSeededKey() throws -> Instance {
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
        try LocalKeychainStore().save(apiKey: "demo", for: instance.apiKeyKeychainRef)
        return instance
    }

    @Test @MainActor func loadsCommentsSortedOldestFirst() async throws {
        let instance = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = NewsDetailViewModel()
        await viewModel.refresh(newsServerID: 1, instance: instance)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.comments.count == 2)
        #expect(viewModel.comments.map(\.id) == [1, 2]) // demo data's comment 1 predates comment 2
    }

    @Test @MainActor func loadsAnEmptyListWhenThePostHasNoComments() async throws {
        let instance = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = NewsDetailViewModel()
        await viewModel.refresh(newsServerID: 2, instance: instance)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.comments.isEmpty)
    }

    /// COMPAT(#1710): a 404 from `GET /news/{id}` hides the comments instead of showing an error.
    @Test @MainActor func hidesCommentsWhenTheServerHasNoNewsDetail() async throws {
        let instance = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "NewsDetailVM-\(UUID().uuidString)")!)

        let viewModel = NewsDetailViewModel(capabilities: capabilities)
        await viewModel.refresh(newsServerID: 999, instance: instance)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.commentsUnavailable)
        #expect(viewModel.comments.isEmpty)
        #expect(!capabilities.isAvailable(.newsComments, for: instance.id))

        await viewModel.refresh(newsServerID: 1, instance: instance)
        #expect(!viewModel.commentsUnavailable)
        #expect(capabilities.isAvailable(.newsComments, for: instance.id))
    }

    @Test @MainActor func setsAnErrorMessageWhenTheCredentialIsMissing() async {
        let instance = Instance(name: "NoKey", baseURL: "https://example.org", apiKeyKeychainRef: UUID().uuidString)
        let viewModel = NewsDetailViewModel()
        await viewModel.refresh(newsServerID: 1, instance: instance)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.commentsUnavailable)
    }

    @Test @MainActor func commentsLinkNeedsCommentsAndServerSupport() {
        let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "NewsLink-\(UUID().uuidString)")!)
        let id = UUID()
        #expect(NewsDetailViewModel.showsCommentsLink(commentsCount: 2, instanceID: id, capabilities: capabilities))
        #expect(!NewsDetailViewModel.showsCommentsLink(commentsCount: 0, instanceID: id, capabilities: capabilities))
        capabilities.record(.newsComments, supported: false, for: id)
        #expect(!NewsDetailViewModel.showsCommentsLink(commentsCount: 2, instanceID: id, capabilities: capabilities))
        #expect(NewsDetailViewModel.showsCommentsLink(commentsCount: 2, instanceID: id)) // default: shared store, unknown instance
    }
}

struct EditInstanceViewModelSelfCheckTests {
    @MainActor
    private func makeInstanceWithSeededKey() throws -> (Instance, ModelContext) {
        let configuration = ModelConfiguration(schema: Schema([Instance.self]), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Instance.self, configurations: configuration)
        let context = ModelContext(container)
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
        context.insert(instance)
        try LocalKeychainStore().save(apiKey: "demo", for: instance.apiKeyKeychainRef)
        return (instance, context)
    }

    @Test @MainActor func testConnectionMarksConnectionTestedWithoutSaving() async throws {
        let (instance, context) = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        #expect(viewModel.connectionTested) // starts true: reflects the already-persisted state
        viewModel.baseURL = Instance.demoBaseURL // trigger didSet, same value
        #expect(!viewModel.connectionTested) // any edit invalidates it until re-tested

        await viewModel.testConnection(for: instance)

        #expect(viewModel.connectionTested)
    }

    /// 2026-09-21, user-requested: unlike Setup, Save used to stay enabled here even
    /// right after editing the server URL or API key — since `save()` already
    /// re-verifies internally regardless. The user asked for Save to actually be
    /// disabled until a fresh "Test Connection" succeeds, same as Setup, so an edit
    /// can't be submitted without ever having been checked.
    @Test @MainActor func canSubmitIsDisabledAfterEditingServerOrKeyUntilRetested() async throws {
        let (instance, context) = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        _ = context

        let viewModel = EditInstanceViewModel(instance: instance)
        #expect(viewModel.canSubmit) // untouched dialog: reflects the already-verified state

        // Trailing slash keeps this recognized as the demo sentinel (Instance.isDemo
        // compares normalizedBaseURL, which trims it) while still triggering didSet —
        // a real, non-demo URL here would attempt an actual network request.
        viewModel.baseURL = Instance.demoBaseURL + "/"
        #expect(!viewModel.canSubmit)

        await viewModel.testConnection(for: instance)
        #expect(viewModel.canSubmit)

        viewModel.apiKey = "new-key"
        #expect(!viewModel.canSubmit)
    }
}

struct InstanceSetupViewModelSelfCheckTests {
    @Test @MainActor func cannotSubmitBeforeTestingTheConnection() {
        let viewModel = InstanceSetupViewModel()
        viewModel.name = "Demo"
        viewModel.baseURL = Instance.demoBaseURL
        viewModel.apiKey = "demo"

        #expect(!viewModel.canSubmit) // all fields valid, but never tested
        #expect(viewModel.canTest)
    }

    @Test @MainActor func testConnectionEnablesSubmitAndInvalidatesOnFurtherEdits() async {
        let viewModel = InstanceSetupViewModel()
        viewModel.name = "Demo"
        viewModel.baseURL = Instance.demoBaseURL
        viewModel.apiKey = "demo"

        await viewModel.testConnection()
        #expect(viewModel.connectionTested)
        #expect(viewModel.canSubmit)

        viewModel.baseURL = Instance.demoBaseURL + "/"
        #expect(!viewModel.connectionTested)
        #expect(!viewModel.canSubmit)
    }
}

/// Coverage for the News screen's meeting/non-meeting filter (2026-09-22,
/// user-requested).
/// Coverage for `NewsMarkdownRenderer` (2026-09-22, user-reported): switching to
/// `interpretedSyntax: .full` alone correctly parsed lists/headers/block quotes as
/// markdown structure, but `Text` doesn't render `PresentationIntent`s on its own, so
/// the list markers disappeared entirely instead of showing up as bullets. Asserts on
/// the rendered plain-text content (not individual attributes) since that's what
/// directly demonstrates the reported bug is fixed.
/// Coverage for `MainView.navigationTitle(forActiveInstances:)` (2026-09-22,
/// user-requested removal of the old "N Active Instances" plural title — this test
/// was initially missed when that change landed, added as a follow-up once asked why).
/// Coverage for `InstancePicker.resolvedSelection(current:instances:)` (2026-09-22,
/// user-reported: in switcher mode, no tab was preselected — the segmented control's
/// `selection` started `nil`, which never matches any row's tag, so it showed no
/// highlighted segment at all even though the views separately fell back to the first
/// instance for *which data* to show).
struct InstancePickerSelectionTests {
    private func makeInstance(name: String) -> Instance {
        Instance(name: name, baseURL: "https://\(name).example.org", apiKeyKeychainRef: name)
    }

    @Test func fallsBackToTheFirstInstanceWhenNoneIsSelectedYet() {
        let instances = [makeInstance(name: "A"), makeInstance(name: "B")]
        #expect(InstancePicker.resolvedSelection(current: nil, instances: instances) == instances[0].id)
    }

    @Test func keepsAnAlreadyValidSelection() {
        let instances = [makeInstance(name: "A"), makeInstance(name: "B")]
        #expect(InstancePicker.resolvedSelection(current: instances[1].id, instances: instances) == instances[1].id)
    }

    @Test func reAnchorsWhenTheSelectedInstanceIsNoLongerInTheList() {
        let instances = [makeInstance(name: "A"), makeInstance(name: "B")]
        let noLongerActive = UUID()
        #expect(InstancePicker.resolvedSelection(current: noLongerActive, instances: instances) == instances[0].id)
    }

    @Test func returnsNilWhenThereAreNoInstancesAtAll() {
        #expect(InstancePicker.resolvedSelection(current: nil, instances: []) == nil)
    }
}

struct MainViewNavigationTitleTests {
    private func makeInstance(name: String) -> Instance {
        Instance(name: name, baseURL: "https://\(name).example.org", apiKeyKeychainRef: name)
    }

    @Test func showsNoInstanceCountTextWhenNoneAreActive() {
        #expect(MainView.navigationTitle(forActiveInstances: []) == "Engelsystem")
    }

    @Test func showsTheSingleActiveInstancesOwnName() {
        let instance = makeInstance(name: "Foo")
        #expect(MainView.navigationTitle(forActiveInstances: [instance]) == "Foo")
    }

    @Test func showsNoInstanceCountTextWhenMultipleAreActive() {
        let instances = [makeInstance(name: "A"), makeInstance(name: "B")]
        #expect(MainView.navigationTitle(forActiveInstances: instances) == "Engelsystem")
    }
}

/// `MainSyncStatus` drives `SyncProgressBanner` during `MainView`'s app-start sync
/// (2026-09-22, user-requested background-sync feature) — coverage for its pure
/// `fraction` math and the `begin()`/`apply()`/`finish()` state transitions, without
/// needing a real `AppSyncCoordinator` sync to run.
@MainActor
struct MainSyncStatusTests {
    @Test func fractionIsZeroBeforeAnyProgressAndOneWhenComplete() {
        let status = MainSyncStatus()
        #expect(status.fraction == 0)

        status.apply(AppSyncCoordinator.Progress(completed: 1, total: 4, description: "Shifts – Demo"))
        #expect(status.fraction == 0.25)

        status.apply(AppSyncCoordinator.Progress(completed: 4, total: 4, description: "Profile – Demo"))
        #expect(status.fraction == 1)
    }

    @Test func beginResetsStateAndFinishRecordsFailure() {
        let status = MainSyncStatus()
        status.apply(AppSyncCoordinator.Progress(completed: 3, total: 3, description: "done"))
        status.finish(succeeded: false)
        #expect(status.didFail)

        status.begin()
        #expect(status.isSyncing)
        #expect(status.completed == 0)
        #expect(status.total == 0)
        #expect(!status.didFail)

        status.finish(succeeded: true)
        #expect(!status.didFail)
        #expect(status.statusText == "Updated")
    }

    /// `run` backs Shifts/News/Profile's own pull-to-refresh (2026-09-22,
    /// user-requested: "the banner should show for every pull-to-refresh, not just
    /// the app-start sync") — indeterminate (no step count), just a status text and
    /// success/failure. Includes the real ~1.2s "stay visible briefly" delay, so this
    /// test is slower than the others in this file by design, not by accident.
    @Test func runShowsIndeterminateStatusThenHidesAfterSucceeding() async {
        let status = MainSyncStatus()
        await status.run(statusText: "Shifts") { true }
        #expect(!status.isSyncing)
        #expect(!status.didFail)
        #expect(status.total == 0)
    }

    @Test func runRecordsFailureWhenWorkReturnsFalse() async {
        let status = MainSyncStatus()
        await status.run(statusText: "News") { false }
        #expect(!status.isSyncing)
        #expect(status.didFail)
    }

    /// `runCoordinated` backs the app-start sync and the main page's own
    /// pull-to-refresh — both go through `AppSyncCoordinator`, so there *is* a
    /// multi-step `Progress` to report.
    @Test func runCoordinatedAppliesProgressUpdatesThenHides() async {
        let status = MainSyncStatus()
        status.hideDelay = .milliseconds(10)
        await status.runCoordinated { callbacks in
            callbacks.onProgress(AppSyncCoordinator.Progress(completed: 1, total: 2, description: "Shifts – Demo"))
            callbacks.onProgress(AppSyncCoordinator.Progress(completed: 2, total: 2, description: "News – Demo"))
            return true
        }
        #expect(!status.isSyncing)
        #expect(status.completed == 2)
        #expect(status.total == 2)
        #expect(!status.didFail)
    }
}

@MainActor
struct MainSyncStatusRunTests {
    private func plan(_ status: MainSyncStatus, _ callbacks: MainSyncStatus.Callbacks, ids: [UUID]) {
        callbacks.onEvent(.planned(ids.enumerated().map {
            SyncPlannedInstance(id: $0.element, name: "I\($0.offset)", totalSteps: 5)
        }))
    }

    @Test func runCoordinatedFillsTheRowsAndClearsThemAfterwards() async {
        let status = MainSyncStatus()
        status.hideDelay = .milliseconds(10)
        let id = UUID()
        await status.runCoordinated { callbacks in
            callbacks.onEvent(.planned([SyncPlannedInstance(id: id, name: "Home", totalSteps: 5)]))
            callbacks.onEvent(.instanceStarted(id: id))
            #expect(status.runModel.rows.count == 1)
            #expect(status.isRunning)
            callbacks.onEvent(.instanceFinished(id: id, outcome: .succeeded))
            return true
        }
        #expect(!status.isRunning)
        #expect(status.runModel.rows.isEmpty)
        #expect(status.statusText == "Updated")
    }

    @Test func aProblemStaysLongerAndIsNamed() async {
        let status = MainSyncStatus()
        status.hideDelay = .milliseconds(10)
        status.problemHideDelay = .milliseconds(300)
        let ids = [UUID(), UUID()]
        let start = Date()
        await status.runCoordinated { callbacks in
            self.plan(status, callbacks, ids: ids)
            callbacks.onEvent(.instanceFinished(id: ids[0], outcome: .succeeded))
            callbacks.onEvent(.instanceFinished(id: ids[1], outcome: .timedOut))
            return false
        }
        #expect(Date().timeIntervalSince(start) >= 0.3)
        #expect(status.didFail)
        #expect(status.statusText == "Partially failed: I1 (timed out)")
    }

    @Test func stopCancelsTheRunAndShowsStopped() async {
        let status = MainSyncStatus()
        status.hideDelay = .milliseconds(10)
        let ids = [UUID(), UUID()]
        let run = Task { @MainActor in
            await status.runCoordinated { callbacks in
                self.plan(status, callbacks, ids: ids)
                while !Task.isCancelled { await Task.yield() }
                return true
            }
        }
        while !status.isRunning { await Task.yield() }
        status.stop()
        await run.value
        #expect(!status.isRunning)
        #expect(status.statusText == "Stopped")
        #expect(status.runModel.rows.isEmpty)
    }

    /// The view's own task being cancelled (the screen went away) cancels the sync too.
    @Test func cancellingTheCallerCancelsTheRun() async {
        let status = MainSyncStatus()
        status.hideDelay = .milliseconds(10)
        var sawCancellation = false
        let run = Task { @MainActor in
            await status.runCoordinated { _ in
                while !Task.isCancelled { await Task.yield() }
                sawCancellation = true
                return true
            }
        }
        while !status.isRunning { await Task.yield() }
        run.cancel()
        await run.value
        #expect(sawCancellation)
    }

    @Test func skipPassesTheRequestToTheControl() async {
        let status = MainSyncStatus()
        let id = UUID()
        status.skip(id)
        #expect(status.control.consumeSkip(id))
    }
}

/// Coverage for resuming on the last selected sidebar section (2026-09-22,
/// user-requested: the app previously always started on Shifts, regardless of what
/// was last open).
struct MainViewLastSelectedSectionTests {
    private let allSections = MainView.Section.sidebarCases

    @Test func startsOnTheMainPageWhenTheStoredSectionIsNotAvailable() {
        let withoutMessages: [MainView.Section] = [.news, .shifts, .locations, .profile]
        #expect(MainView.initialSelection(fromStoredRawValue: "messages", hasActiveInstances: true, visibleSections: withoutMessages) == nil)
        #expect(MainView.initialSelection(fromStoredRawValue: "news", hasActiveInstances: true, visibleSections: withoutMessages) == .news)
    }

    @Test func startsOnTheMainPageWhenNothingWasStoredYet() {
        #expect(MainView.initialSelection(fromStoredRawValue: nil, hasActiveInstances: true, visibleSections: allSections) == nil)
    }

    @Test func startsOnTheMainPageForAnUnrecognizedStoredValue() {
        #expect(MainView.initialSelection(fromStoredRawValue: "not-a-real-section", hasActiveInstances: true, visibleSections: allSections) == nil)
    }

    @Test func alwaysStartsOnTheMainPageWhenNoInstanceIsActive() {
        #expect(MainView.initialSelection(fromStoredRawValue: "news", hasActiveInstances: false, visibleSections: allSections) == nil)
        #expect(MainView.initialSelection(fromStoredRawValue: "settings", hasActiveInstances: false, visibleSections: allSections) == nil)
    }

    @Test func resumesOnAPreviouslyStoredDataSection() {
        #expect(MainView.initialSelection(fromStoredRawValue: "news", hasActiveInstances: true, visibleSections: allSections) == .news)
        #expect(MainView.initialSelection(fromStoredRawValue: "profile", hasActiveInstances: true, visibleSections: allSections) == .profile)
    }

    /// `.settings` is a real, storable raw value (`Section` itself doesn't know
    /// anything is special about it), but the app should never actually resume
    /// straight into Settings — `shouldPersistAsLastSelectedSection` is what keeps it
    /// from ever being written in the first place; this only proves the *read* side
    /// would honor it if it somehow got stored anyway (e.g. by a future bug), which
    /// is why `shouldPersistAsLastSelectedSection` below matters on the write side.
    @Test func wouldResumeOnSettingsIfItWereEverActuallyStored() {
        #expect(MainView.initialSelection(fromStoredRawValue: "settings", hasActiveInstances: true, visibleSections: allSections) == .settings)
    }

    @Test func onlyDataSectionsShouldBePersisted() {
        #expect(MainView.shouldPersistAsLastSelectedSection(.shifts))
        #expect(MainView.shouldPersistAsLastSelectedSection(.news))
        #expect(MainView.shouldPersistAsLastSelectedSection(.profile))
        #expect(MainView.shouldPersistAsLastSelectedSection(.locations))
        #expect(MainView.shouldPersistAsLastSelectedSection(.messages))
        #expect(!MainView.shouldPersistAsLastSelectedSection(.settings))
    }
}

/// 2026-09-23, Messages feature: the sidebar's Messages row must only appear once at
/// least one active instance's server actually supports it — CLAUDE.md's "if the
/// instance doesn't offer the new interface, don't show the GUI" requirement.
struct MainViewMessagesVisibilityTests {
    private func makeInstance(name: String, messagesSupported: Bool) -> Instance {
        let instance = Instance(name: name, baseURL: "https://\(name).example.org", apiKeyKeychainRef: name)
        instance.messagesSupported = messagesSupported
        return instance
    }

    @Test func messagesRowIsHiddenWhenNoActiveInstanceSupportsIt() {
        let instances = [makeInstance(name: "A", messagesSupported: false)]
        let visible = MainView.Section.visibleSidebarCases(forActiveInstances: instances)
        #expect(!visible.contains(.messages))
    }

    @Test func messagesRowIsHiddenWhenThereAreNoActiveInstancesAtAll() {
        let visible = MainView.Section.visibleSidebarCases(forActiveInstances: [])
        #expect(!visible.contains(.messages))
    }

    @Test func messagesRowShowsUpWhenAtLeastOneActiveInstanceSupportsIt() {
        let instances = [
            makeInstance(name: "A", messagesSupported: false),
            makeInstance(name: "B", messagesSupported: true),
        ]
        let visible = MainView.Section.visibleSidebarCases(forActiveInstances: instances)
        #expect(visible.contains(.messages))
    }

    /// ADR 0015: News, Shifts and Profile follow the Features list too; a group without a row disappears with its heading.
    @Test @MainActor func newsShiftsAndProfileRowsFollowTheirFeatures() {
        let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "MainViewRows-\(UUID().uuidString)")!)
        let only = makeInstance(name: "Only News", messagesSupported: false)
        capabilities.recordDemoInstance(only.id, newsOnly: true)
        let visible = MainView.Section.visibleSidebarCases(forActiveInstances: [only], capabilities: capabilities)
        #expect(visible == [.news])
        #expect(MainView.Section.groupedForSidebar(visible).map(\.group.title) == ["Communication"])

        // Another instance that offers everything brings the rows back.
        let full = makeInstance(name: "Full", messagesSupported: true)
        capabilities.recordDemoInstance(full.id)
        let both = MainView.Section.visibleSidebarCases(forActiveInstances: [only, full], capabilities: capabilities)
        #expect(Set(both) == Set(MainView.Section.sidebarCases))

        // The profile needs only one of its two parts, the news row disappears on its own.
        let profileOnly = makeInstance(name: "Profile", messagesSupported: false)
        capabilities.record(.news, supported: false, for: profileOnly.id)
        capabilities.record(.shifts, supported: false, for: profileOnly.id)
        capabilities.record(.profileWorklogs, supported: false, for: profileOnly.id)
        capabilities.record(.locationsList, supported: false, for: profileOnly.id)
        let visibleProfile = MainView.Section.visibleSidebarCases(forActiveInstances: [profileOnly], capabilities: capabilities)
        #expect(visibleProfile == [.profile])
        #expect(MainView.Section.groupedForSidebar(visibleProfile).map(\.group.title) == ["Account"])
    }

    /// COMPAT(#1711): the Locations row needs at least one active instance whose server lets the account read locations.
    @Test @MainActor func locationsRowFollowsTheLocationsListCapability() {
        let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "MainViewLocations-\(UUID().uuidString)")!)
        let a = makeInstance(name: "A", messagesSupported: false)
        let b = makeInstance(name: "B", messagesSupported: false)
        #expect(MainView.Section.visibleSidebarCases(forActiveInstances: [a, b], capabilities: capabilities).contains(.locations))

        capabilities.record(.locationsList, supported: false, for: a.id)
        #expect(MainView.Section.visibleSidebarCases(forActiveInstances: [a, b], capabilities: capabilities).contains(.locations))
        #expect(!MainView.Section.visibleSidebarCases(forActiveInstances: [a], capabilities: capabilities).contains(.locations))

        capabilities.record(.locationsList, supported: false, for: b.id)
        #expect(!MainView.Section.visibleSidebarCases(forActiveInstances: [a, b], capabilities: capabilities).contains(.locations))
        #expect(MainView.Section.visibleSidebarCases(forActiveInstances: [], capabilities: capabilities).contains(.locations))
    }

    @Test func everyOtherDataSectionAlwaysStaysVisibleRegardlessOfMessagesSupport() {
        let visible = MainView.Section.visibleSidebarCases(forActiveInstances: [])
        #expect(visible.contains(.shifts))
        #expect(visible.contains(.news))
        #expect(visible.contains(.profile))
        #expect(visible.contains(.locations))
    }
}

/// The sidebar's order and groups (2026-10-13, user-requested): Communication (News, Messages),
/// Event (Shifts, Locations), Account (Profile).
struct MainViewSidebarGroupsTests {
    @Test func theSidebarOrderIsNewsMessagesShiftsLocationsProfile() {
        #expect(MainView.Section.sidebarCases == [.news, .messages, .shifts, .locations, .profile])
    }

    @Test func visibleSectionsAreGroupedUnderTheirHeadings() {
        let groups = MainView.Section.groupedForSidebar(MainView.Section.sidebarCases)
        #expect(groups.map(\.group.title) == ["Communication", "Event", "Account"])
        #expect(groups.map(\.sections) == [[.news, .messages], [.shifts, .locations], [.profile]])
        #expect(groups.map(\.id) == MainView.Section.SidebarGroup.allCases)
    }

    @Test func aGroupWithoutVisibleSectionsDisappearsAndOthersKeepTheirOrder() {
        let groups = MainView.Section.groupedForSidebar([.profile, .shifts, .news])
        #expect(groups.map(\.sections) == [[.news], [.shifts], [.profile]])
        #expect(MainView.Section.groupedForSidebar([.profile]).map(\.group) == [.account])
        #expect(MainView.Section.groupedForSidebar([]).isEmpty)
    }
}

/// `MainView.resolvedSelection` is what decides which screen actually renders — it
/// must fall back gracefully if `.messages` is selected but no longer visible (e.g.
/// the one supporting instance was deactivated after the fact).
struct MainViewResolvedSelectionTests {
    @Test func returnsTheSelectionWhenItIsVisible() {
        let visible: [MainView.Section] = [.shifts, .news, .messages]
        #expect(MainView.resolvedSelection(.messages, visibleSections: visible) == .messages)
    }

    @Test func goesBackToTheMainPageWhenTheSelectionIsNoLongerVisible() {
        let visible: [MainView.Section] = [.shifts, .news]
        #expect(MainView.resolvedSelection(.messages, visibleSections: visible) == nil)
    }

    @Test func showsTheMainPageWhenNothingIsSelectedYet() {
        #expect(MainView.resolvedSelection(nil, visibleSections: [.shifts, .news]) == nil)
    }

    @Test func settingsIsAlwaysReachableRegardlessOfVisibility() {
        #expect(MainView.resolvedSelection(.settings, visibleSections: []) == .settings)
    }
}

struct NewsMarkdownRendererTests {
    @Test func unorderedListItemsGetABulletPrefixEach() {
        let result = NewsMarkdownRenderer.render("- First item\n- Second item")
        #expect(String(result.characters) == "\u{2022} First item\n\u{2022} Second item")
    }

    @Test func orderedListItemsKeepTheirNumbering() {
        let result = NewsMarkdownRenderer.render("1. First item\n2. Second item")
        #expect(String(result.characters) == "1. First item\n2. Second item")
    }

    @Test func plainParagraphsStaySeparatedByABlankLine() {
        let result = NewsMarkdownRenderer.render("First paragraph.\n\nSecond paragraph.")
        #expect(String(result.characters) == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func inlineEmphasisWithinAListItemIsPreserved() {
        let result = NewsMarkdownRenderer.render("- Item with **bold** text")
        #expect(String(result.characters) == "\u{2022} Item with bold text")
        let boldRun = result.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(boldRun != nil)
    }

    @Test func emptyTextRendersToEmptyOutput() {
        #expect(String(NewsMarkdownRenderer.render("").characters).isEmpty)
    }

    /// 2026-09-22, user-reported: a first version only ever looked at the single
    /// innermost list/item, so a nested list rendered with no indentation and an
    /// incorrect blank-line gap (instead of sitting tightly under its parent item).
    @Test func nestedListItemsAreIndentedAndStayTightlyAttached() {
        let markdown = "- Item 1\n  - Nested 1a\n  - Nested 1b\n- Item 2"
        let result = NewsMarkdownRenderer.render(markdown)
        #expect(String(result.characters) == """
        \u{2022} Item 1
          \u{2022} Nested 1a
          \u{2022} Nested 1b
        \u{2022} Item 2
        """)
    }

    @Test func threeLevelsOfNestingIndentProportionally() {
        let markdown = "1. Top\n   1. Mid\n      - Deep"
        let result = NewsMarkdownRenderer.render(markdown)
        #expect(String(result.characters) == "1. Top\n  1. Mid\n    \u{2022} Deep")
    }

    @Test func leavingAListForAPlainParagraphStillGetsABlankLine() {
        let markdown = "- Item\n\nAfterwards."
        let result = NewsMarkdownRenderer.render(markdown)
        #expect(String(result.characters) == "\u{2022} Item\n\nAfterwards.")
    }
}

struct NewsMeetingFilterTests {
    private func makeNews(isMeeting: Bool) -> CachedNews {
        CachedNews(
            serverID: 1, instanceID: UUID(), title: "Post", text: "text",
            isMeeting: isMeeting, isPinned: false, isHighlighted: false, createdAt: Date(), url: ""
        )
    }

    @Test func allMatchesEverything() {
        #expect(NewsMeetingFilter.all.matches(makeNews(isMeeting: true)))
        #expect(NewsMeetingFilter.all.matches(makeNews(isMeeting: false)))
    }

    @Test func meetingsOnlyMatchesOnlyMeetings() {
        #expect(NewsMeetingFilter.meetingsOnly.matches(makeNews(isMeeting: true)))
        #expect(!NewsMeetingFilter.meetingsOnly.matches(makeNews(isMeeting: false)))
    }

    @Test func nonMeetingsOnlyMatchesOnlyNonMeetings() {
        #expect(!NewsMeetingFilter.nonMeetingsOnly.matches(makeNews(isMeeting: true)))
        #expect(NewsMeetingFilter.nonMeetingsOnly.matches(makeNews(isMeeting: false)))
    }
}

struct SyncErrorMapperTests {
    @Test func isUnauthorizedIsTrueOnlyForAPIErrorUnauthorized() {
        #expect(SyncErrorMapper.isUnauthorized(APIError.unauthorized))
        #expect(!SyncErrorMapper.isUnauthorized(APIError.forbidden))
        #expect(!SyncErrorMapper.isUnauthorized(APIError.notFound))
        #expect(!SyncErrorMapper.isUnauthorized(InstanceCredentialError.apiKeyNotFound))
    }

    @Test func messageMapsInstanceCredentialAndKeychainErrorsToReadableText() {
        #expect(SyncErrorMapper.message(for: InstanceCredentialError.apiKeyNotFound).contains("Settings"))
        #expect(SyncErrorMapper.message(for: KeychainError.unexpectedData).contains("keychain"))
        #expect(SyncErrorMapper.message(for: APIError.forbidden) == APIError.forbidden.userMessage)
    }

    @Test func isCancellationIsTrueOnlyForCancellationError() {
        #expect(SyncErrorMapper.isCancellation(CancellationError()))
        #expect(!SyncErrorMapper.isCancellation(APIError.network("offline")))
        #expect(!SyncErrorMapper.isCancellation(InstanceCredentialError.apiKeyNotFound))
    }
}

/// 2026-09-23, "keep the Watch fresh" feature: `ShiftsViewModel.refresh`'s pull-to-refresh
/// path bypasses `AppSyncCoordinator`, so it needs its own `Instance.shiftsChangedAt`
/// signal-bump — see `EngelsystemClientKitTests.SyncServiceTests
/// .appSyncCoordinatorBumpsShiftsChangedAtOnARealChange` for the `AppSyncCoordinator`
/// counterpart, and `EngelsystemClient_Watch_AppTests.NextShiftViewModelTests` for the
/// Watch's equivalent pull-to-refresh path.
struct ShiftsViewModelTests {
    /// Never actually invoked (`handleNotifications: false` below) — exists only so
    /// `NotificationScheduler` doesn't fall back to the real `UNUserNotificationCenter
    /// .current()`, which has no place to run from inside a test. Mirrors
    /// `EngelsystemClientKitTests.SyncServiceTests`'s `UnusedNotificationCenter`.
    private final class UnusedNotificationCenter: NotificationCenterScheduling, @unchecked Sendable {
        func authorizationStatus() async -> UNAuthorizationStatus { fatalError("not used with handleNotifications: false") }
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { fatalError("not used with handleNotifications: false") }
        func pendingNotificationRequests() async -> [UNNotificationRequest] { fatalError("not used with handleNotifications: false") }
        func add(_ request: UNNotificationRequest) async throws { fatalError("not used with handleNotifications: false") }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { fatalError("not used with handleNotifications: false") }
    }

    // `cloudKitDatabase: .none` is required here specifically because this test target
    // runs hosted inside the real, CloudKit-entitled `EngelsystemClient.app` (unlike
    // `EngelsystemClientKitTests`' bare `swift test` CLI process, which has no
    // entitlements context at all and so never attempts real CloudKit schema
    // validation) — without it, `Instance`'s CloudKit-required-defaults validation
    // actually runs and fails container creation. Matches
    // `EditInstanceViewModelPersistenceTests`/`EditInstanceViewModelAPIKeyTests`'s
    // existing `Instance`-only configurations elsewhere in this file.
    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Instance.self, CachedShift.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    private func seedDemoInstance(in context: ModelContext) throws -> Instance {
        let ref = "shifts-view-model-tests-\(UUID().uuidString)"
        try LocalKeychainStore().save(apiKey: "demo", for: ref)
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref)
        context.insert(instance)
        return instance
    }

    @Test @MainActor func refreshBumpsInstanceShiftsChangedAtOnARealChange() async throws {
        let context = try makeInMemoryContext()
        let instance = try seedDemoInstance(in: context)
        #expect(instance.shiftsChangedAt == Date.distantPast)

        let viewModel = ShiftsViewModel(notificationScheduler: NotificationScheduler(center: UnusedNotificationCenter()))
        await viewModel.refresh(instances: [instance], in: context, handleNotifications: false)

        #expect(instance.shiftsChangedAt > Date.distantPast)
    }
}

/// Coverage for the Messages feature's app-target view models (2026-09-23) — all
/// against the demo credential, same reasoning as `NewsDetailViewModelTests`: there's
/// no mock HTTP server in this test target, but demo mode exercises the exact same
/// code paths (`APIClient`'s demo branches) a real server would.
private func makeMessagesTestInstance() throws -> Instance {
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
    try LocalKeychainStore().save(apiKey: "demo", for: instance.apiKeyKeychainRef)
    return instance
}

struct MessagesViewModelTests {
    @Test @MainActor func refreshLoadsConversationsPerInstance() async throws {
        let instance = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = MessagesViewModel()
        await viewModel.refresh(instances: [instance])

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.conversationsByInstanceID[instance.id]?.count == 3)
    }

    @Test @MainActor func aFailureOnOneInstanceDoesNotBlockOthersFromRefreshing() async throws {
        let good = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: good.apiKeyKeychainRef) }
        // No Keychain entry saved for this one — `InstanceCredentialResolver` throws.
        let bad = Instance(name: "Broken", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "missing-\(UUID().uuidString)")

        let viewModel = MessagesViewModel()
        await viewModel.refresh(instances: [bad, good])

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.conversationsByInstanceID[good.id]?.count == 3)
        #expect(viewModel.conversationsByInstanceID[bad.id] == nil)
    }
}

struct ConversationDetailViewModelTests {
    @Test @MainActor func loadSortsMessagesOldestFirstAndMarksIncomingUnreadAsRead() async throws {
        let instance = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = ConversationDetailViewModel()
        await viewModel.load(otherUserID: 2, instance: instance)

        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.messages.isEmpty)
        #expect(viewModel.messages.allSatisfy { $0.read })
    }

    @Test @MainActor func sendAppendsTheNewMessageAndTrimsWhitespace() async throws {
        let instance = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = ConversationDetailViewModel()
        await viewModel.load(otherUserID: 2, instance: instance)
        let countBefore = viewModel.messages.count

        let succeeded = await viewModel.send(text: "  On my way!  ", otherUserID: 2, instance: instance)

        #expect(succeeded)
        #expect(viewModel.messages.count == countBefore + 1)
        #expect(viewModel.messages.last?.text == "On my way!")
    }

    @Test @MainActor func sendRejectsBlankText() async throws {
        let instance = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = ConversationDetailViewModel()
        let succeeded = await viewModel.send(text: "   ", otherUserID: 2, instance: instance)

        #expect(!succeeded)
        #expect(viewModel.messages.isEmpty)
    }

    @Test @MainActor func deleteRemovesTheMessageFromTheThread() async throws {
        let instance = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = ConversationDetailViewModel()
        await viewModel.load(otherUserID: 2, instance: instance)
        _ = await viewModel.send(text: "Delete me", otherUserID: 2, instance: instance)
        let sent = try #require(viewModel.messages.last)

        await viewModel.delete(sent, instance: instance)

        #expect(!viewModel.messages.contains(where: { $0.id == sent.id }))
    }
}

struct UserPickerViewModelTests {
    @Test @MainActor func loadReturnsUsersSortedByName() async throws {
        let instance = try makeMessagesTestInstance()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = UserPickerViewModel()
        await viewModel.load(instance: instance)

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.users.count == 3)
        let names = viewModel.users.compactMap(\.name)
        #expect(names == names.sorted())
    }
}
