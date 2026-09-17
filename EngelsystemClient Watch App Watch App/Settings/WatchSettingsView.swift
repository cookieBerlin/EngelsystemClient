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
/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): mirrors iOS's two-section
/// ("Active"/"Inactive") + swipe-action-to-move layout, replacing the old single list
/// with a "Use as Active Instance" button. No `multiInstanceDisplayMode` picker here —
/// that setting only affects iOS's Shifts/News/Profile catalog screens, which the Watch
/// doesn't have (see `MultiInstanceDisplayMode`).
struct WatchSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instance.createdAt) private var instances: [Instance]
    @AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)
    private var notificationLeadTimeMinutes: Int = NotificationScheduler.defaultMinutesBefore

    @State private var isPresentingSetup = false

    private var activeInstances: [Instance] { instances.filter(\.isActive) }
    private var inactiveInstances: [Instance] { instances.filter { !$0.isActive } }

    var body: some View {
        List {
            Section("Active") {
                if activeInstances.isEmpty {
                    Text("No active instances.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeInstances) { instance in
                        instanceRow(for: instance, activate: false)
                    }
                }
            }

            Section("Inactive") {
                if inactiveInstances.isEmpty {
                    Text("No inactive instances.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inactiveInstances) { instance in
                        instanceRow(for: instance, activate: true)
                    }
                }
                Button {
                    isPresentingSetup = true
                } label: {
                    Label("Add Instance", systemImage: "plus")
                }
            }

            Section {
                Picker("Notify Before Shift", selection: $notificationLeadTimeMinutes) {
                    ForEach(NotificationScheduler.availableLeadTimesInMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } header: {
                Text("Notifications")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isPresentingSetup) {
            WatchSetupView()
        }
    }

    // Destination-closure NavigationLink rather than `NavigationLink(value:)` +
    // `.navigationDestination(for:)` — the value-based flavor didn't reliably push on
    // watchOS in testing here (UI tests confirmed the tap registers but no navigation
    // occurs); this style is confirmed working.
    @ViewBuilder
    private func instanceRow(for instance: Instance, activate: Bool) -> some View {
        NavigationLink {
            WatchInstanceDetailView(instance: instance, onDelete: { delete(instance) })
        } label: {
            WatchInstanceRow(instance: instance)
        }
        .swipeActions {
            if activate {
                Button("Activate") { setActive(instance, isActive: true) }
                    .tint(.green)
            } else {
                Button("Deactivate") { setActive(instance, isActive: false) }
                    .tint(.orange)
            }
        }
    }

    private func setActive(_ instance: Instance, isActive: Bool) {
        instance.isActive = isActive
        instance.touch()
        try? modelContext.save()
    }

    private func delete(_ instance: Instance) {
        try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef)
        try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef)

        // Manual cascade delete: `Instance` (CloudKit-backed) and `CachedShift`
        // (local-only, the only Cached* type the Watch schema includes) live in
        // separate `ModelConfiguration`s now, so SwiftData's relationship-based
        // cascade delete no longer applies across them — see Instance.swift.
        let instanceID = instance.id
        try? modelContext.delete(model: CachedShift.self, where: #Predicate { $0.instanceID == instanceID })

        modelContext.delete(instance)
        try? modelContext.save()
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

    var body: some View {
        List {
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
                    TextField("User ID (optional)", text: $viewModel.userIDText)
                } footer: {
                    Text("Only needed if your server doesn't recognize automatic user detection.")
                        .font(.caption2)
                }
                Section {
                    SecureField("New API Key (optional)", text: $viewModel.apiKey)
                } footer: {
                    Text("Leave blank to keep the current key.")
                        .font(.caption2)
                }
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
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
