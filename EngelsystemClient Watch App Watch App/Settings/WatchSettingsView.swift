import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `SettingsView` (`Features/Settings`) — instance
/// management (switch/add/remove, update API key) plus the notification lead-time
/// picker, now that the Watch app supports the same settings as iOS. Structured the
/// same way as its iOS counterpart (a plain pushed `List`, private row/detail views in
/// the same file), just via its own `@Query` instead of an `instances` parameter, since
/// the Watch app has no `MainView`-equivalent already holding that array.
struct WatchSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instance.createdAt) private var instances: [Instance]
    @AppStorage("activeInstanceID") private var activeInstanceIDString: String = ""
    @AppStorage(NotificationScheduler.leadTimeUserDefaultsKey)
    private var notificationLeadTimeMinutes: Int = NotificationScheduler.defaultMinutesBefore

    @State private var isPresentingSetup = false

    var body: some View {
        List {
            Section("Instances") {
                ForEach(instances) { instance in
                    // Destination-closure NavigationLink rather than
                    // `NavigationLink(value:)` + `.navigationDestination(for:)` — the
                    // value-based flavor didn't reliably push on watchOS in testing here
                    // (UI tests confirmed the tap registers but no navigation occurs);
                    // this style is confirmed working.
                    NavigationLink {
                        WatchInstanceDetailView(
                            instance: instance,
                            isActive: instance.id.uuidString == activeInstanceIDString,
                            onActivate: { activate(instance) },
                            onDelete: { delete(instance) }
                        )
                    } label: {
                        WatchInstanceRow(
                            instance: instance,
                            isActive: instance.id.uuidString == activeInstanceIDString
                        )
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

    private func activate(_ instance: Instance) {
        activeInstanceIDString = instance.id.uuidString
    }

    private func delete(_ instance: Instance) {
        try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef)
        try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef)

        if activeInstanceIDString == instance.id.uuidString {
            activeInstanceIDString = ""
        }
        modelContext.delete(instance)
    }
}

private struct WatchInstanceRow: View {
    let instance: Instance
    let isActive: Bool

    var body: some View {
        HStack {
            Text(instance.name)
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct WatchInstanceDetailView: View {
    let instance: Instance
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingKeyUpdate = false
    @State private var isPresentingEdit = false

    var body: some View {
        List {
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
            WatchUpdateAPIKeyView(instance: instance)
        }
        .sheet(isPresented: $isPresentingEdit) {
            WatchEditInstanceView(instance: instance)
        }
    }
}

private struct WatchEditInstanceView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WatchEditInstanceViewModel

    init(instance: Instance) {
        self.instance = instance
        _viewModel = State(initialValue: WatchEditInstanceViewModel(instance: instance))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Name", text: $viewModel.name)
                }
                Section("Server") {
                    TextField("Server URL", text: $viewModel.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                                if await viewModel.save(instance: instance) {
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

private struct WatchUpdateAPIKeyView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = WatchUpdateAPIKeyViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("API Key") {
                    SecureField("New API Key", text: $viewModel.apiKey)
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
                                if await viewModel.update(instance: instance) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSubmit)
                    }
                }
            }
            .navigationTitle("Update API Key")
        }
    }
}
