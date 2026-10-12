import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Instance management, reached via the "Settings" section of `MainView`'s sidebar
/// (CLAUDE.md multi-instance concept: "switching in Settings"). A plain pushed list
/// rather than its own `NavigationSplitView`, since it's already hosted inside
/// `MainView`'s `NavigationSplitView`/`NavigationStack`.
///
/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): any number of instances can
/// be active simultaneously, so the single "Use as Active Instance" button/label is
/// gone. ~~Originally two sections ("Active"/"Inactive") with a swipe action per row
/// to move an instance between them — a per-row `Toggle` was explicitly rejected at
/// the time.~~ **Superseded 2026-09-22, at the user's explicit request**: back to a
/// single flat list with a per-row `Toggle` bound directly to `instance.isActive`, no
/// sections. People change their minds about UI decisions; this isn't a mistake being
/// corrected, just a later preference overriding an earlier one.
/// `sheet(item:)` needs an `Identifiable` payload; a bare `String` isn't one.
private struct DiagnosticsExport: Identifiable {
    let id = UUID()
    let text: String?
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NewsNotifier.enabledUserDefaultsKey)
    private var notifyOnNewNews: Bool = true
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var multiInstanceDisplayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @AppStorage(DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    private var syncOnAppStart: Bool = true
    @AppStorage(DeviceSyncPreferences.pollingIntervalUserDefaultsKey)
    private var pollingIntervalMinutes: Int = PollingInterval.manual.rawValue
    @AppStorage(DebugLog.isEnabledUserDefaultsKey)
    private var isDebugLoggingEnabled: Bool = false
    @AppStorage(DebugLog.maxEntriesUserDefaultsKey)
    private var maxDebugLogEntries: Int = DebugLog.defaultMaxEntries

    let instances: [Instance]

    // CloudKit-synced (within iOS — see NotificationLeadTimeSettings), so this is a
    // @Query, not @AppStorage like the settings above.
    @Query private var leadTimeSettingsRows: [NotificationLeadTimeSettings]
    @State private var isPresentingSetup = false
    @State private var diagnosticsToExport: DiagnosticsExport?
    @State private var cloudSyncStatus: CloudSyncStatus = .checking

    private var multiInstanceDisplayMode: Binding<MultiInstanceDisplayMode> {
        Binding(
            get: { MultiInstanceDisplayMode.stored(raw: multiInstanceDisplayModeRaw) },
            set: { multiInstanceDisplayModeRaw = $0.rawValue }
        )
    }

    /// 2026-09-22, "multiple reminders" feature: sorted ascending purely for a stable,
    /// predictable display order (Settings' own list, not the notifications
    /// themselves — order doesn't matter there). Parameterized by platform, not just
    /// `currentPlatform`, since iOS's `SettingsView` shows *both* rows now
    /// (2026-09-22, further user-requested: "also show the Watch's settings in the
    /// iOS app") — both are equally reachable from here via the same CloudKit-synced
    /// model, there's no reason to require physical access to the tiny Watch screen
    /// to edit its own reminder list.
    private func leadTimesMinutes(for platform: String) -> [Int] {
        NotificationLeadTimeSettings.leadTimes(for: platform, in: leadTimeSettingsRows)
    }

    private func leadTimesAvailableToAdd(for platform: String) -> [Int] {
        NotificationLeadTimeSettings.availableToAdd(currentlySelected: leadTimesMinutes(for: platform))
    }

    private func addLeadTime(_ minutes: Int, for platform: String) {
        NotificationLeadTimeSettings.addLeadTime(minutes, for: platform, in: modelContext)
    }

    private func removeLeadTime(_ minutes: Int, for platform: String) {
        NotificationLeadTimeSettings.removeLeadTime(minutes, for: platform, in: modelContext)
    }

    /// Plain per-device `@AppStorage`, iOS-only — **not** synced to the Apple Watch
    /// (2026-09-22, reverted the same day it originally shipped as a CloudKit-synced
    /// singleton: Watch background execution isn't implemented at all — see
    /// CLAUDE.md — so `WatchSettingsView` doesn't show this setting any more either).
    /// Changing it re-schedules this device's own background task immediately, not
    /// just on the next launch.
    private var pollingInterval: Binding<PollingInterval> {
        Binding(
            get: { PollingInterval(minutes: pollingIntervalMinutes) },
            set: { newValue in
                pollingIntervalMinutes = newValue.rawValue
                BackgroundSyncScheduler.scheduleNext()
            }
        )
    }

    var body: some View {
        List {
            Section("Instances") {
                if instances.isEmpty {
                    Text("No instances configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(instances) { instance in
                        instanceRow(for: instance)
                    }
                }
            }

            Section {
                Picker("Multiple Active Instances", selection: multiInstanceDisplayMode) {
                    ForEach(MultiInstanceDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text("How Shifts, News, and Profile display data when more than one instance is active at the same time.")
            }

            Section {
                ForEach(leadTimesMinutes(for: NotificationLeadTimeSettings.currentPlatform), id: \.self) { minutes in
                    HStack {
                        Text("\(minutes) min")
                        Spacer()
                        Button {
                            removeLeadTime(minutes, for: NotificationLeadTimeSettings.currentPlatform)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove \(minutes) min reminder")
                    }
                }
                if !leadTimesAvailableToAdd(for: NotificationLeadTimeSettings.currentPlatform).isEmpty {
                    Menu {
                        ForEach(leadTimesAvailableToAdd(for: NotificationLeadTimeSettings.currentPlatform), id: \.self) { minutes in
                            Button("\(minutes) min") { addLeadTime(minutes, for: NotificationLeadTimeSettings.currentPlatform) }
                        }
                    } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                }
                Toggle("Notify on New News", isOn: $notifyOnNewNews)
            } header: {
                Text("Notifications")
            } footer: {
                Text("A local reminder is scheduled before each of your shifts starts, once per time added here. Shared with other iOS/iPadOS devices on this account. Also whether a notification is posted when a News sync finds a new announcement.")
            }

            // 2026-09-22, further user-requested: the Apple Watch's own reminder
            // list, editable right from here too — both rows live in the same
            // CloudKit-synced `NotificationLeadTimeSettings` model, so there's no
            // reason editing the Watch's list should require physical access to its
            // much smaller screen. Distinct accessibility labels ("... Watch
            // reminder"/"Add Watch Reminder") from the section above, so the two
            // "Add Reminder"-shaped controls stay unambiguous.
            Section {
                ForEach(leadTimesMinutes(for: "watch"), id: \.self) { minutes in
                    HStack {
                        Text("\(minutes) min")
                        Spacer()
                        Button {
                            removeLeadTime(minutes, for: "watch")
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove \(minutes) min Watch reminder")
                    }
                }
                if !leadTimesAvailableToAdd(for: "watch").isEmpty {
                    Menu {
                        ForEach(leadTimesAvailableToAdd(for: "watch"), id: \.self) { minutes in
                            Button("\(minutes) min") { addLeadTime(minutes, for: "watch") }
                        }
                    } label: {
                        Label("Add Watch Reminder", systemImage: "plus")
                    }
                }
            } header: {
                Text("Apple Watch Reminders")
            } footer: {
                Text("Your Apple Watch's own reminder list — independent from the one above, but editable from here too.")
            }

            Section {
                Picker("Background Sync", selection: pollingInterval) {
                    ForEach(PollingInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                Toggle("Sync on App Start", isOn: $syncOnAppStart)
            } header: {
                Text("Sync")
            } footer: {
                Text("The operating system decides exactly when a background sync actually happens — depending on battery, usage, and system load, it can take longer than the interval you pick here. Both settings are per device, not shared with your Apple Watch.")
            }

            Section {
                Toggle("Debug Logging", isOn: $isDebugLoggingEnabled)
                Picker("Max Log Entries", selection: $maxDebugLogEntries) {
                    ForEach(DebugLog.availableMaxEntryCounts, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                NavigationLink("View Debug Log") {
                    DebugLogView()
                }
                Button {
                    diagnosticsToExport = DiagnosticsExport(text: MetricKitReporter.shared.exportText())
                } label: {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Records internal sync and notification activity for troubleshooting. Never includes API keys or other secrets. Off by default; turning it off doesn't erase what's already logged — use \"Clear\" in the log view for that. \"Export Diagnostics\" shares crash/hang/performance data collected on-device by Apple's MetricKit — nothing is sent anywhere automatically, and you see what it contains before sharing.")
            }

            Section {
                VStack(spacing: 4) {
                    Text(cloudSyncStatus.displayText)
                    if let lastBackgroundSync = DeviceSyncPreferences.lastBackgroundSyncDate() {
                        Text("Last Background Sync: \(lastBackgroundSync.formatted(.relative(presentation: .named)))")
                    }
                    Text(AppVersionInfo.displayString)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem {
                Button {
                    isPresentingSetup = true
                } label: {
                    Label("Add Instance", systemImage: "plus")
                }
            }
        }
        .task {
            cloudSyncStatus = await CloudSyncStatus.current(containerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier)
        }
        .sheet(item: $diagnosticsToExport) { export in
            ExportDiagnosticsView(diagnosticsText: export.text)
        }
        .sheet(isPresented: $isPresentingSetup) {
            InstanceSetupView()
        }
        .navigationDestination(for: Instance.self) { instance in
            InstanceDetailView(instance: instance, onDelete: { delete(instance) })
        }
    }

    /// A `NavigationLink` alone would make the whole row (including the toggle) into
    /// a single tap target, navigating instead of toggling whenever the toggle itself
    /// is tapped. Layering an invisible `NavigationLink` behind the real row content
    /// keeps the chevron/row-tap-to-detail behavior while letting the `Toggle` handle
    /// its own taps — a standard SwiftUI `List` pattern for "row navigates, but has
    /// its own accessory control too".
    @ViewBuilder
    private func instanceRow(for instance: Instance) -> some View {
        ZStack {
            NavigationLink(value: instance) { EmptyView() }
                .opacity(0)
            HStack {
                InstanceRow(instance: instance)
                Spacer()
                Toggle(isOn: Binding(
                    get: { instance.isActive },
                    set: { setActive(instance, isActive: $0) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                // `.labelsHidden()` + an `EmptyView()` label leaves the switch with no
                // accessible name of its own — bad for VoiceOver, and unfindable by a
                // UI test — so name it explicitly instead of relying on positional
                // queries.
                .accessibilityLabel("\(instance.name) Active")
            }
        }
    }

    private func setActive(_ instance: Instance, isActive: Bool) {
        instance.setActive(isActive, in: modelContext)
    }

    private func delete(_ instance: Instance) {
        InstanceRemoval.delete(
            instance, in: modelContext, keyStores: [KeychainSyncStore(), LocalKeychainStore()], scope: .all
        )
    }
}

private struct InstanceRow: View {
    let instance: Instance

    var body: some View {
        VStack(alignment: .leading) {
            Text(instance.name)
            Text(instance.normalizedBaseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct InstanceDetailView: View {
    let instance: Instance
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEdit = false

    // Unfiltered `@Query`s, same pattern as Shifts/News/Profile — filtered down to
    // this one instance below. 2026-09-23, user-requested "last sync timestamps".
    @Query private var allShifts: [CachedShift]
    @Query private var allNews: [CachedNews]
    @Query private var allUsers: [CachedUser]
    @Query private var allWorklogs: [CachedWorklog]
    @Query private var allAngelTypeMemberships: [CachedAngelTypeMembership]

    private var lastShiftsSync: Date? { CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allShifts) }
    private var lastNewsSync: Date? { CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allNews) }
    // Profile/Worklogs/AngelTypes are three separate Cached* types but always synced
    // together by ProfileSyncService in one pass (see ProfileViewModel) — the
    // freshest of the three stands in for "when Profile was last synced" as a whole,
    // matching how the sidebar groups them into a single "Profile" screen.
    private var lastProfileSync: Date? {
        CacheSyncTimestamp.mostRecent([
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allUsers),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allWorklogs),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allAngelTypeMemberships),
        ])
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Server", value: instance.normalizedBaseURL)
                LabeledContent("Status", value: instance.isActive ? "Active" : "Inactive")
                Button("Edit Instance") { isPresentingEdit = true }
            }

            Section("Last Synced") {
                syncRow("Shifts", lastShiftsSync)
                syncRow("News", lastNewsSync)
                syncRow("Profile", lastProfileSync)
            }

            Section {
                Button("Remove Instance", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(instance.name)
        .sheet(isPresented: $isPresentingEdit) {
            EditInstanceView(instance: instance)
        }
    }

    @ViewBuilder
    private func syncRow(_ label: String, _ date: Date?) -> some View {
        if let date {
            LabeledContent(label, value: date.formatted(.relative(presentation: .named)))
        } else {
            LabeledContent(label, value: "Never")
        }
    }
}

/// Combined "Edit Instance" form — name, server, User ID, and API Key in one dialog
/// (see `EditInstanceViewModel` for why this replaced the previously separate "Edit
/// Name / Server" and "Update API Key" sheets).
private struct EditInstanceView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EditInstanceViewModel

    init(instance: Instance) {
        self.instance = instance
        _viewModel = State(initialValue: EditInstanceViewModel(instance: instance))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $viewModel.name)
                }
                Section("Server") {
                    TextField("Server URL", text: $viewModel.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                }
                Section {
                    SecureField("New API Key (optional)", text: $viewModel.apiKey)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Leave blank to keep the current key. Only fill this in if it's expired, been revoked, or you're pointing this instance at a different account.")
                }
                // Hidden when the last check (at creation, the previous save, or a
                // fresh "Test Connection" tap) found the server resolves `self`
                // correctly — unless a value is already configured, so an active
                // override never just disappears silently.
                if !viewModel.selfReferenceWorks || !viewModel.userIDText.isEmpty {
                    Section {
                        TextField("User ID", text: $viewModel.userIDText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    } footer: {
                        Text("This server doesn't support automatic user detection. Enter your numeric user ID, visible in your Engelsystem profile URL.")
                    }
                }
                // COMPAT(#1709): the server answered 403 to a data request — warn, but allow saving.
                if viewModel.connectionTested, let accessWarning = viewModel.accessWarning {
                    Section {
                        Label(accessWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await viewModel.testConnection(for: instance) }
                    } label: {
                        if viewModel.isTesting {
                            ProgressView()
                        } else if viewModel.connectionTested {
                            Label("Connection Verified", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(!viewModel.canTest)
                } footer: {
                    Text("Re-checks the server/key, and whether automatic user detection works. Required after changing the server URL or API key before you can save.")
                }
            }
            .navigationTitle("Edit Instance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isTesting {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save(instance: instance, in: modelContext) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSubmit)
                    }
                }
            }
        }
    }
}
