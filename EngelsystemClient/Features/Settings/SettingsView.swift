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
/// gone, replaced by two sections ("Active"/"Inactive") with a swipe action per row to
/// move an instance between them — chosen over a per-row `Toggle` (rejected) and over
/// drag-and-drop between sections (doesn't translate to watchOS, where Settings
/// otherwise mirrors iOS's).
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)
    private var notificationLeadTimeMinutes: Int = NotificationScheduler.defaultMinutesBefore
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var multiInstanceDisplayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue

    let instances: [Instance]

    @State private var isPresentingSetup = false

    private var activeInstances: [Instance] { instances.filter(\.isActive) }
    private var inactiveInstances: [Instance] { instances.filter { !$0.isActive } }

    private var multiInstanceDisplayMode: Binding<MultiInstanceDisplayMode> {
        Binding(
            get: { MultiInstanceDisplayMode(rawValue: multiInstanceDisplayModeRaw) ?? .merged },
            set: { multiInstanceDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section("Active") {
                if activeInstances.isEmpty {
                    Text("No active instances.")
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
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inactiveInstances) { instance in
                        instanceRow(for: instance, activate: true)
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
            } header: {
                Text("Notifications")
            } footer: {
                Text("How far in advance a local reminder is scheduled before each of your shifts starts.")
            }

            Section {
                Text(AppVersionInfo.displayString)
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
        .sheet(isPresented: $isPresentingSetup) {
            InstanceSetupView()
        }
        .navigationDestination(for: Instance.self) { instance in
            InstanceDetailView(instance: instance, onDelete: { delete(instance) })
        }
    }

    @ViewBuilder
    private func instanceRow(for instance: Instance, activate: Bool) -> some View {
        NavigationLink(value: instance) {
            InstanceRow(instance: instance)
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
                    TextField("User ID (optional)", text: $viewModel.userIDText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    Text("Only needed if your server doesn't recognize automatic user detection. Leave blank unless Shifts/Profile show up empty — your numeric user ID is visible in your Engelsystem profile URL.")
                }
                Section {
                    SecureField("New API Key (optional)", text: $viewModel.apiKey)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Leave blank to keep the current key. Only fill this in if it's expired, been revoked, or you're pointing this instance at a different account.")
                }
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
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
