import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Instance management, reached via the "Settings" section of `MainView`'s sidebar
/// (CLAUDE.md multi-instance concept: "switching in Settings"). A plain pushed list
/// rather than its own `NavigationSplitView`, since it's already hosted inside
/// `MainView`'s `NavigationSplitView`/`NavigationStack`.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("activeInstanceID") private var activeInstanceIDString: String = ""
    @AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)
    private var notificationLeadTimeMinutes: Int = NotificationScheduler.defaultMinutesBefore

    let instances: [Instance]

    @State private var isPresentingSetup = false

    var body: some View {
        List {
            Section("Instances") {
                ForEach(instances) { instance in
                    NavigationLink(value: instance) {
                        InstanceRow(
                            instance: instance,
                            isActive: instance.id.uuidString == activeInstanceIDString
                        )
                    }
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
            } footer: {
                Text("How far in advance a local reminder is scheduled before each of your shifts starts.")
            }
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
            InstanceSetupView { activateFirstInstanceIfNeeded() }
        }
        .navigationDestination(for: Instance.self) { instance in
            InstanceDetailView(
                instance: instance,
                isActive: instance.id.uuidString == activeInstanceIDString,
                onActivate: { activate(instance) },
                onDelete: { delete(instance) }
            )
        }
    }

    private func activateFirstInstanceIfNeeded() {
        guard activeInstanceIDString.isEmpty, let first = instances.first else { return }
        activate(first)
    }

    private func activate(_ instance: Instance) {
        activeInstanceIDString = instance.id.uuidString
    }

    private func delete(_ instance: Instance) {
        // Store affiliation (iCloud vs. local) isn't persisted, so we clean up
        // both stores — deleting a nonexistent entry is a no-op.
        try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef)
        try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef)

        if activeInstanceIDString == instance.id.uuidString {
            activeInstanceIDString = ""
        }
        modelContext.delete(instance)
    }
}

private struct InstanceRow: View {
    let instance: Instance
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(instance.name)
                Text(instance.normalizedBaseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct InstanceDetailView: View {
    let instance: Instance
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingKeyUpdate = false
    @State private var isPresentingEdit = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Server", value: instance.normalizedBaseURL)
                Button("Edit Name / Server") { isPresentingEdit = true }
            }

            Section {
                if isActive {
                    Label("Active Instance", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Use as Active Instance", action: onActivate)
                }
            }

            Section {
                Button("Update API Key") { isPresentingKeyUpdate = true }
            } footer: {
                Text("If shifts, news, or your profile stop loading with an authorization error, the API key may have expired or been revoked — update it here.")
            }

            Section {
                Button("Remove Instance", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(instance.name)
        .sheet(isPresented: $isPresentingKeyUpdate) {
            UpdateAPIKeyView(instance: instance)
        }
        .sheet(isPresented: $isPresentingEdit) {
            EditInstanceView(instance: instance)
        }
    }
}

private struct EditInstanceView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
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
                                if await viewModel.save(instance: instance) {
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

private struct UpdateAPIKeyView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = UpdateAPIKeyViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("API Key") {
                    SecureField("New API Key", text: $viewModel.apiKey)
                        .autocorrectionDisabled()
                }
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Update API Key")
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
                                if await viewModel.update(instance: instance) {
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
