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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instance.createdAt) private var instances: [Instance]
    @Query private var leadTimeSettingsRows: [NotificationLeadTimeSettings]
    @AppStorage(DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    private var syncOnAppStart: Bool = true

    @State private var isPresentingSetup = false
    @AppStorage(ParallelSyncSetting.userDefaultsKey) private var parallelSyncs = 0
    @State private var cloudSyncStatus: CloudSyncStatus = .checking

    /// See the iOS `SettingsView`'s matching properties for why this is a `@Query`
    /// (CloudKit-synced within a platform) rather than `@AppStorage`, and why it
    /// resolves the "watch" row specifically — this list is deliberately independent
    /// from the iOS one (2026-09-22, user-requested).
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
                Stepper(value: $parallelSyncs, in: ParallelSyncSetting.range) {
                    VStack(alignment: .leading) {
                        Text("Parallel Syncs")
                        Text(ParallelSyncSetting.title(for: parallelSyncs))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("How many instances are synced at the same time. Applies to this device only.")
                    .font(.caption2)
            }

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
            } header: {
                Text("Notifications")
            } footer: {
                Text("Its own list, independent from your iPhone's.")
                    .font(.caption2)
            }

            // 2026-09-22, user-requested background-sync feature: no interval picker
            // here at all (originally shown/settable here too, shared via CloudKit
            // with iOS — reverted the same day, at the user's explicit request, once
            // it became clear it did nothing on this platform). Actually *running* a
            // background sync on watchOS isn't implemented — the `BackgroundTasks`
            // framework this app uses on iOS isn't available on watchOS at all, and
            // watchOS's own separate background-refresh API has been reported
            // unreliable on recent watchOS versions (see CLAUDE.md). Said plainly in
            // the footer below, rather than showing a setting that would do nothing.
            Section {
                Toggle("Sync on App Start", isOn: $syncOnAppStart)
            } header: {
                Text("Sync")
            } footer: {
                Text("Background sync by interval isn't available on Apple Watch. This app still syncs when you open it or pull to refresh.")
                    .font(.caption2)
            }

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
        .navigationTitle("Settings")
        .sheet(isPresented: $isPresentingSetup) {
            WatchSetupView()
        }
        .task {
            cloudSyncStatus = await CloudSyncStatus.current(containerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier)
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
                .accessibilityLabel("\(instance.name) Active")
            }
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

private struct WatchInstanceDetailView: View {
    let instance: Instance
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEdit = false
    // Watch's schema only includes CachedShift (CLAUDE.md's Watch App Scope) — no
    // News/Profile row to show here, unlike iOS's equivalent screen.
    @Query private var allShifts: [CachedShift]

    private var lastShiftsSync: Date? { CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allShifts) }

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Server", value: instance.normalizedBaseURL)
                LabeledContent("Status", value: instance.isActive ? "Active" : "Inactive")
                Button("Edit Instance") { isPresentingEdit = true }
            }

            Section("Last Synced") {
                if let lastShiftsSync {
                    LabeledContent("Shifts", value: lastShiftsSync.formatted(.relative(presentation: .named)))
                } else {
                    LabeledContent("Shifts", value: "Never")
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
        .sheet(isPresented: $isPresentingEdit) {
            WatchEditInstanceView(instance: instance)
        }
    }
}

/// Combined "Edit Instance" form — see the iOS `EditInstanceView`'s matching comment
/// for why this merged what used to be separate "Edit Name / Server" and "Update API
/// Key" sheets.
private struct WatchEditInstanceView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WatchEditInstanceViewModel

    init(instance: Instance) {
        self.instance = instance
        _viewModel = State(initialValue: WatchEditInstanceViewModel(instance: instance))
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
                }
                Section {
                    SecureField("New API Key (optional)", text: $viewModel.apiKey)
                } footer: {
                    Text("Leave blank to keep the current key.")
                        .font(.caption2)
                }
                if viewModel.connectionTested, let featureSummary = viewModel.featureSummary {
                    Section {
                        Text(featureSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await viewModel.testConnection(for: instance) }
                    } label: {
                        if viewModel.isTesting {
                            ProgressView()
                        } else if viewModel.connectionTested {
                            Label("Verified", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(!viewModel.canTest)
                } footer: {
                    Text("Required after changing the server URL or API key before you can save.")
                        .font(.caption2)
                }
                Section {
                    if viewModel.isTesting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
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
            .navigationTitle("Edit Instance")
        }
    }
}
