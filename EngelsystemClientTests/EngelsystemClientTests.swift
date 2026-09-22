//
//  EngelsystemClientTests.swift
//  EngelsystemClientTests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import Foundation
import Testing
import SwiftData
import EngelsystemClientKit
@testable import EngelsystemClient

/// Regression coverage for the 2026-09-16 bug: a user reported that a manually
/// re-entered `Instance.userID` reverted to `nil` after rebuilding the app from
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
///
/// Exercises `name` rather than the original bug report's `userID`: since 2026-09-21,
/// `InstanceSetupService.updateInstance` force-clears `userID` whenever
/// `selfReferenceWorks` is true (see `InstanceSetupServiceTests
/// .instanceSetupServiceClearsUserIDWhenSelfReferenceWorks`, Kit), and every demo
/// credential always reports `selfReferenceWorks == true` — so `userID` can no longer
/// be used as this test's "any edited field" probe. The persistence mechanism being
/// tested here is unrelated to which field is edited.
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

    @Test @MainActor func setsAnErrorMessageForAnUnknownPost() async throws {
        let instance = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = NewsDetailViewModel()
        await viewModel.refresh(newsServerID: 999, instance: instance)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.comments.isEmpty)
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
        #expect(viewModel.selfReferenceWorks)
        #expect(instance.userID == nil) // testConnection never saves
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

    @Test @MainActor func testConnectionClearsUserIDTextWhenSelfNowWorks() async throws {
        let (instance, context) = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        _ = context // only needed to keep the in-memory store alive for the keychain-backed instance

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.userIDText = "42"

        await viewModel.testConnection(for: instance)

        #expect(viewModel.selfReferenceWorks)
        #expect(viewModel.userIDText.isEmpty)
        // Verify only previews, at the user's explicit request — it must not touch the
        // persisted store on its own; deleting a now-stale userID happens at Save time
        // instead (see saveClearsAStaleUserIDEvenWithoutPressingTestConnectionFirst
        // below), not here.
        #expect(instance.userID == nil)
    }

    /// 2026-09-21, user-requested: a stale `userID` (e.g. left over from before the
    /// server's `self`/worklogs bug was fixed) must be cleared once Save is pressed —
    /// even if the user never explicitly presses "Test Connection" first, since Save
    /// always re-probes internally (`InstanceSetupService.updateInstance`).
    @Test @MainActor func saveClearsAStaleUserIDEvenWithoutPressingTestConnectionFirst() async throws {
        let (instance, context) = try makeInstanceWithSeededKey()
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        instance.userID = 42 // simulate a pre-existing manual override

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.userIDText = "42" // the form still shows the old value

        let succeeded = await viewModel.save(instance: instance, in: context)

        #expect(succeeded)
        #expect(instance.selfReferenceWorks)
        #expect(instance.userID == nil)
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
        #expect(viewModel.selfReferenceWorks)
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

/// Coverage for resuming on the last selected sidebar section (2026-09-22,
/// user-requested: the app previously always started on Shifts, regardless of what
/// was last open).
struct MainViewLastSelectedSectionTests {
    @Test func fallsBackToShiftsWhenNothingWasStoredYet() {
        #expect(MainView.initialSelection(fromStoredRawValue: nil) == .shifts)
    }

    @Test func fallsBackToShiftsForAnUnrecognizedStoredValue() {
        #expect(MainView.initialSelection(fromStoredRawValue: "not-a-real-section") == .shifts)
    }

    @Test func resumesOnAPreviouslyStoredDataSection() {
        #expect(MainView.initialSelection(fromStoredRawValue: "news") == .news)
        #expect(MainView.initialSelection(fromStoredRawValue: "profile") == .profile)
    }

    /// `.settings` is a real, storable raw value (`Section` itself doesn't know
    /// anything is special about it), but the app should never actually resume
    /// straight into Settings — `shouldPersistAsLastSelectedSection` is what keeps it
    /// from ever being written in the first place; this only proves the *read* side
    /// would honor it if it somehow got stored anyway (e.g. by a future bug), which
    /// is why `shouldPersistAsLastSelectedSection` below matters on the write side.
    @Test func wouldResumeOnSettingsIfItWereEverActuallyStored() {
        #expect(MainView.initialSelection(fromStoredRawValue: "settings") == .settings)
    }

    @Test func onlyDataSectionsShouldBePersisted() {
        #expect(MainView.shouldPersistAsLastSelectedSection(.shifts))
        #expect(MainView.shouldPersistAsLastSelectedSection(.news))
        #expect(MainView.shouldPersistAsLastSelectedSection(.profile))
        #expect(!MainView.shouldPersistAsLastSelectedSection(.settings))
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
