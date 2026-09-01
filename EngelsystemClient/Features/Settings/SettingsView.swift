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

    var body: some View {
        Form {
            Section("Event") {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Server", value: instance.normalizedBaseURL)
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
                Button("Remove Instance", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(instance.name)
    }
}
