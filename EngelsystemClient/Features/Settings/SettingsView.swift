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
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)
    private var notificationLeadTimeMinutes: Int = NotificationScheduler.defaultMinutesBefore
    @AppStorage(NewsNotifier.enabledUserDefaultsKey)
    private var notifyOnNewNews: Bool = true
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var multiInstanceDisplayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @AppStorage(DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    private var syncOnAppStart: Bool = true
    @AppStorage(DeviceSyncPreferences.pollingIntervalUserDefaultsKey)
    private var pollingIntervalMinutes: Int = PollingInterval.manual.rawValue

    let instances: [Instance]

    @State private var isPresentingSetup = false
    @State private var cloudSyncStatus: CloudSyncStatus = .checking

    private var multiInstanceDisplayMode: Binding<MultiInstanceDisplayMode> {
        Binding(
            get: { MultiInstanceDisplayMode(rawValue: multiInstanceDisplayModeRaw) ?? .merged },
            set: { multiInstanceDisplayModeRaw = $0.rawValue }
        )
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
                Picker("Notify Before Shift", selection: $notificationLeadTimeMinutes) {
                    ForEach(NotificationScheduler.availableLeadTimesInMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                Toggle("Notify on New News", isOn: $notifyOnNewNews)
            } header: {
                Text("Notifications")
            } footer: {
                Text("How far in advance a local reminder is scheduled before each of your shifts starts, and whether a notification is posted when a News sync finds a new announcement.")
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
        instance.isActive = isActive
        instance.touch()
        try? modelContext.save()
    }

    private func delete(_ instance: Instance) {
        // Store affiliation (iCloud vs. local) isn't persisted, so we clean up
        // both stores — deleting a nonexistent entry is a no-op.
        try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef)
        try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef)

        // Manual cascade delete: `Instance` (CloudKit-backed) and the `Cached*` models
        // (local-only) live in separate `ModelConfiguration`s now, so SwiftData's
        // relationship-based cascade delete no longer applies across them — see
        // Instance.swift.
        let instanceID = instance.id
        try? modelContext.delete(model: CachedShift.self, where: #Predicate { $0.instanceID == instanceID })
        try? modelContext.delete(model: CachedNews.self, where: #Predicate { $0.instanceID == instanceID })
        try? modelContext.delete(model: CachedUser.self, where: #Predicate { $0.instanceID == instanceID })
        try? modelContext.delete(model: CachedWorklog.self, where: #Predicate { $0.instanceID == instanceID })
        try? modelContext.delete(model: CachedAngelTypeMembership.self, where: #Predicate { $0.instanceID == instanceID })

        modelContext.delete(instance)
        try? modelContext.save()
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

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Server", value: instance.normalizedBaseURL)
                LabeledContent("Status", value: instance.isActive ? "Active" : "Inactive")
                Button("Edit Instance") { isPresentingEdit = true }
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
