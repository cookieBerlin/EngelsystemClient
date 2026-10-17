import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `SettingsView` (`Features/Settings`) — instance
/// management (switch/add/remove, edit) plus the notification lead-time picker, now
/// that the Watch app supports the same settings as iOS. Structured the same way as its
/// iOS counterpart (a plain pushed `List`, private row/detail views in the same file),
/// just via its own `@Query` instead of an `instances` parameter, since the Watch app
/// has no `MainView`-equivalent already holding that array.
///
/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): replaced the old single list
/// with a "Use as Active Instance" button. ~~Originally a two-section ("Active"/
/// "Inactive") + swipe-action-to-move layout.~~ **Superseded 2026-09-22, mirroring
/// iOS's `SettingsView`**: a single flat list with a per-row `Toggle` bound to
/// `instance.isActive`. No `multiInstanceDisplayMode` picker here — that setting only
/// affects iOS's Shifts/News/Profile catalog screens, which the Watch doesn't have
/// (see `MultiInstanceDisplayMode`).
struct WatchSettingsView: View {
    @Query(sort: \Instance.createdAt) private var instances: [Instance]
    @Query private var leadTimeSettingsRows: [NotificationLeadTimeSettings]
    @AppStorage(DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    private var syncOnAppStart: Bool = true
    @AppStorage(DebugLog.isEnabledUserDefaultsKey)
    private var isDebugLoggingEnabled: Bool = DebugLog.defaultEnabled

    @State private var isPresentingSetup = false
    /// Debug-only deep link (`-open-settings-page <name>`), used by the guide's screenshots.
    @State private var deepLinkedPage: String? = DemoSeeding.settingsPage(arguments: ProcessInfo.processInfo.arguments)

    /// The Watch's own reminder list (resolves the "watch" row specifically — independent from the iPhone's).
    private var leadTimesMinutes: [Int] {
        NotificationLeadTimeSettings.leadTimes(for: NotificationLeadTimeSettings.currentPlatform, in: leadTimeSettingsRows)
    }

    /// A short list of topics, each opening its own page with a summary behind it — the same structure as the
    /// iPhone's Settings (2026-10-16; before, this was one long list).
    var body: some View {
        List {
            // Without any instance the first thing to do is adding one.
            if instances.isEmpty {
                Button {
                    isPresentingSetup = true
                } label: {
                    Label("Add Instance", systemImage: "plus")
                }
            }
            NavigationLink {
                WatchInstancesSettingsView()
            } label: {
                WatchSettingsRowLabel(
                    title: "Instances", systemImage: "server.rack",
                    summary: SettingsSummary.instances(active: instances.filter(\.isActive).count, total: instances.count))
            }
            NavigationLink {
                WatchNotificationsSettingsView()
            } label: {
                WatchSettingsRowLabel(
                    title: "Notifications", systemImage: "bell",
                    summary: SettingsSummary.notifications(leadTimes: leadTimesMinutes))
            }
            NavigationLink {
                WatchSyncSettingsView()
            } label: {
                WatchSettingsRowLabel(
                    title: "Sync", systemImage: "arrow.triangle.2.circlepath",
                    summary: SettingsSummary.watchSync(onAppStart: syncOnAppStart))
            }
            NavigationLink {
                WatchDiagnosticsSettingsView()
            } label: {
                WatchSettingsRowLabel(
                    title: "Diagnostics", systemImage: "stethoscope",
                    summary: SettingsSummary.diagnostics(isEnabled: isDebugLoggingEnabled))
            }
            NavigationLink {
                WatchAboutSettingsView()
            } label: {
                WatchSettingsRowLabel(
                    title: "About", systemImage: "info.circle",
                    summary: SettingsSummary.version(info: Bundle.main.infoDictionary))
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(item: $deepLinkedPage) { page in
            switch page {
            case "Notifications": WatchNotificationsSettingsView()
            case "Sync": WatchSyncSettingsView()
            case "Diagnostics": WatchDiagnosticsSettingsView()
            case "About": WatchAboutSettingsView()
            default: WatchInstancesSettingsView()
            }
        }
        .sheet(isPresented: $isPresentingSetup) {
            WatchSetupView()
        }
    }
}

/// One row of the hub: icon, title and a short, secondary summary of the current state.
private struct WatchSettingsRowLabel: View {
    let title: String
    let systemImage: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Instances page: the list with an active switch each, "Add Instance" and the Parallel Syncs stepper.
private struct WatchInstancesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instance.createdAt) private var instances: [Instance]
    @AppStorage(ParallelSyncSetting.userDefaultsKey) private var parallelSyncs = 0
    @State private var isPresentingSetup = false

    var body: some View {
        List {
            Section("Instances") {
                if instances.isEmpty {
                    Text("No instances configured.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(instances) { instance in
                        instanceRow(for: instance)
                    }
                }
                Button {
                    isPresentingSetup = true
                } label: {
                    Label("Add Instance", systemImage: "plus")
                }
            }

            Section {
                // Title and value above the -/+ buttons: beside them the title is squeezed by the buttons.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parallel Syncs")
                        .font(.caption)
                    Text(ParallelSyncSetting.title(for: parallelSyncs))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Stepper(value: $parallelSyncs, in: ParallelSyncSetting.range) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityLabel("Parallel Syncs, \(ParallelSyncSetting.title(for: parallelSyncs))")
                }
            } footer: {
                Text("How many instances are synced at the same time. Applies to this device only.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Instances")
        .sheet(isPresented: $isPresentingSetup) {
            WatchSetupView()
        }
    }

    // Destination-closure NavigationLink rather than `NavigationLink(value:)` +
    // `.navigationDestination(for:)` — the value-based flavor didn't reliably push on
    // watchOS in testing here (UI tests confirmed the tap registers but no navigation
    // occurs); this style is confirmed working. Made invisible and layered behind the
    // real row content (same technique as iOS's `SettingsView.instanceRow`) so the
    // `Toggle` handles its own taps instead of the whole row navigating.
    @ViewBuilder
    private func instanceRow(for instance: Instance) -> some View {
        ZStack {
            NavigationLink {
                WatchInstanceDetailView(instance: instance, onDelete: { delete(instance) })
            } label: {
                EmptyView()
            }
            .opacity(0)
            HStack {
                WatchInstanceRow(instance: instance)
                Spacer()
                Toggle(isOn: Binding(
                    get: { instance.isActive },
                    set: { setActive(instance, isActive: $0) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                // A wider tap area over the full row height (like the "Add Instance" button below): a switch alone is
                // small, and a tap that just misses it opens the instance.
                .frame(minWidth: 64, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityLabel("\(instance.name) Active")
            }
            .frame(minHeight: 44)
        }
    }

    private func setActive(_ instance: Instance, isActive: Bool) {
        // A freshly activated instance may have an old cache: refresh it right away.
        guard instance.setActive(isActive, in: modelContext) else { return }
        Task { await WatchShiftsSyncCoordinator.shared.refresh(instances: [instance], in: modelContext, allActive: instances.filter(\.isActive)) }
    }

    private func delete(_ instance: Instance) {
        InstanceRemoval.delete(
            instance, in: modelContext, keyStores: [KeychainSyncStore(), LocalKeychainStore()], scope: .shiftsOnly
        )
    }
}

/// Notifications page: the Watch's own reminder times, independent from the iPhone's.
private struct WatchNotificationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var leadTimeSettingsRows: [NotificationLeadTimeSettings]

    /// See the iOS `SettingsView`'s matching properties for why this is a `@Query` (CloudKit-synced within a
    /// platform) rather than `@AppStorage`, and why it resolves the "watch" row specifically.
    private var leadTimesMinutes: [Int] {
        NotificationLeadTimeSettings.leadTimes(for: NotificationLeadTimeSettings.currentPlatform, in: leadTimeSettingsRows)
    }

    private var leadTimesAvailableToAdd: [Int] {
        NotificationLeadTimeSettings.availableToAdd(currentlySelected: leadTimesMinutes)
    }

    private func addLeadTime(_ minutes: Int) {
        NotificationLeadTimeSettings.addLeadTime(minutes, for: NotificationLeadTimeSettings.currentPlatform, in: modelContext)
    }

    private func removeLeadTime(_ minutes: Int) {
        NotificationLeadTimeSettings.removeLeadTime(minutes, for: NotificationLeadTimeSettings.currentPlatform, in: modelContext)
    }

    var body: some View {
        List {
            Section {
                ForEach(leadTimesMinutes, id: \.self) { minutes in
                    HStack {
                        Text("\(minutes) min")
                        Spacer()
                        Button {
                            removeLeadTime(minutes)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove \(minutes) min reminder")
                    }
                }
                // `Menu` isn't available on watchOS — a pushed list of the remaining
                // presets is the standard watchOS substitute for "tap to pick one
                // from a short list".
                if !leadTimesAvailableToAdd.isEmpty {
                    NavigationLink {
                        WatchAddReminderView(availableMinutes: leadTimesAvailableToAdd, onAdd: addLeadTime)
                    } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                }
            } footer: {
                Text("Its own list, independent from your iPhone's.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Notifications")
    }
}

/// Sync page. No interval picker (2026-09-22, user-requested background-sync feature): actually *running* a
/// background sync on watchOS isn't implemented — `BackgroundTasks` isn't available there and watchOS's own
/// background-refresh API has been reported unreliable (see CLAUDE.md) — said plainly in the footer.
private struct WatchSyncSettingsView: View {
    @AppStorage(DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    private var syncOnAppStart: Bool = true

    var body: some View {
        List {
            Section {
                Toggle("Sync on App Start", isOn: $syncOnAppStart)
            } footer: {
                Text("Background sync by interval isn't available on Apple Watch. This app still syncs when you open it or pull to refresh.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Sync")
    }
}

/// Diagnostics page: the Watch's own debug logging switch (on by default in the beta) and "Send Log to iPhone".
private struct WatchDiagnosticsSettingsView: View {
    @AppStorage(DebugLog.isEnabledUserDefaultsKey)
    private var isDebugLoggingEnabled: Bool = DebugLog.defaultEnabled
    @State private var viewModel = WatchDiagnosticsViewModel()
    @State private var entryCount = 0

    var body: some View {
        List {
            Section {
                // The switch changes through the model, which also remembers when (the newer change wins against
                // the iPhone's remote switch).
                Toggle("Debug Logging", isOn: Binding(
                    get: { isDebugLoggingEnabled },
                    set: { viewModel.setLogging($0) }
                ))
            } footer: {
                Text("Records this app's internal activity on the Watch for troubleshooting. Never includes API keys or other secrets.")
                    .font(.caption2)
            }

            Section {
                Button {
                    viewModel.sendLog()
                    entryCount = DebugLog.shared.entries.count
                } label: {
                    Label("Send Log to iPhone", systemImage: "paperplane")
                }
                .disabled(DebugLog.shared.entries.isEmpty)
                if let status = viewModel.statusText {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let lastSent = viewModel.lastSentText() {
                    Text(lastSent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Only when you tap. The log goes to your own iPhone, nowhere else.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Diagnostics")
    }
}

/// About page: version and iCloud status.
private struct WatchAboutSettingsView: View {
    @State private var cloudSyncStatus: CloudSyncStatus = .checking

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text(cloudSyncStatus.displayText)
                    Text(AppVersionInfo.displayString)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("About")
        .task {
            cloudSyncStatus = await CloudSyncStatus.current(containerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier)
        }
    }
}

/// The watchOS substitute for iOS's `Menu`-based "Add Reminder" (unavailable on this
/// platform) — a pushed list of the remaining presets; tapping one adds it and pops
/// back to `WatchSettingsView` via `dismiss()`.
private struct WatchAddReminderView: View {
    let availableMinutes: [Int]
    let onAdd: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(availableMinutes, id: \.self) { minutes in
                Button("\(minutes) min") {
                    onAdd(minutes)
                    dismiss()
                }
            }
        }
        .navigationTitle("Add Reminder")
    }
}

private struct WatchInstanceRow: View {
    let instance: Instance

    var body: some View {
        Text(instance.name)
    }
}

/// One page for an instance on the Watch: editable name, server and API key (Save/Discard with a confirmation),
/// the status and the last sync (2026-10-16 — it replaced the page plus the separate "Edit Instance" sheet).
private struct WatchInstanceDetailView: View {
    let instance: Instance
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var form: WatchEditInstanceViewModel
    @State private var isConfirmingDiscard = false
    // Watch's schema only includes CachedShift (CLAUDE.md's Watch App Scope) — no
    // News/Profile row to show here, unlike iOS's equivalent screen.
    @Query private var allShifts: [CachedShift]

    init(instance: Instance, onDelete: @escaping () -> Void) {
        self.instance = instance
        self.onDelete = onDelete
        _form = State(initialValue: WatchEditInstanceViewModel(instance: instance))
    }

    private var lastShiftsSync: Date? { CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allShifts) }
    private var hasChanges: Bool { form.hasChanges(for: instance) }

    var body: some View {
        List {
            Section("Instance") {
                TextField("Name", text: $form.name)
                TextField("Server URL", text: $form.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if form.requiresAPIKey {
                    SecureField("New API Key", text: $form.apiKey)
                } else {
                    // A demo address ignores the key: greyed out, with the reason.
                    SecureField("API Key", text: .constant(""))
                        .disabled(true)
                    Text(InstanceForm.demoKeyHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if form.isTesting {
                    ProgressView()
                } else if form.connectionTested {
                    Label("Verified", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Test Connection") {
                        Task { await form.testConnection(for: instance) }
                    }
                    .disabled(!form.canTest)
                }
                if form.connectionTested, let summary = form.featureSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let message = form.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Optional. Saving does not need it.")
                    .font(.caption2)
            }

            Section {
                LabeledContent("Status", value: instance.isActive ? "Active" : "Inactive")
            }

            Section("Last Synced") {
                if let lastShiftsSync {
                    LabeledContent("Shifts", value: lastShiftsSync.formatted(.relative(presentation: .named)))
                } else {
                    LabeledContent("Shifts", value: "Never")
                }
            }

            if hasChanges {
                Section {
                    Button("Save") {
                        if let serverChanged = form.save(instance: instance, in: modelContext), serverChanged {
                            Task { await WatchShiftsSyncCoordinator.shared.refreshActiveInstances(in: modelContext) }
                        }
                    }
                    .disabled(!form.canSave)
                    Button("Discard", role: .destructive) { isConfirmingDiscard = true }
                }
            }

            Section {
                Button("Remove Instance", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(instance.name)
        // Unsaved edits are saved or discarded on purpose: no way back until then.
        .navigationBarBackButtonHidden(hasChanges)
        .confirmationDialog("Discard changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { form.discard(to: instance) }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this instance will be lost.")
        }
    }
}
