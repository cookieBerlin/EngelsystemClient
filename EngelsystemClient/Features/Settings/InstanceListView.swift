import SwiftUI
import SwiftData
import EngelsystemClientKit

/// First runnable feature after InstanceSetup: manages the configured instances,
/// including switching the active instance. `NavigationSplitView` instead of a plain
/// TabView, so iPad gets a sidebar/detail layout (see CLAUDE.md).
struct InstanceListView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("activeInstanceID") private var activeInstanceIDString: String = ""

    let instances: [Instance]

    @State private var selection: Instance.ID?
    @State private var isPresentingSetup = false

    var body: some View {
        NavigationSplitView {
            List(instances, selection: $selection) { instance in
                InstanceRow(
                    instance: instance,
                    isActive: instance.id.uuidString == activeInstanceIDString
                )
                .tag(instance.id)
            }
            .navigationTitle("Instances")
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
            .onAppear { activateFirstInstanceIfNeeded() }
        } detail: {
            if let selectedInstance = instances.first(where: { $0.id == selection }) {
                InstanceDetailView(
                    instance: selectedInstance,
                    isActive: selectedInstance.id.uuidString == activeInstanceIDString,
                    onActivate: { activate(selectedInstance) },
                    onDelete: { delete(selectedInstance) }
                )
            } else {
                ContentUnavailableView(
                    "No Instance Selected",
                    systemImage: "server.rack",
                    description: Text("Select an instance on the left.")
                )
            }
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

        if selection == instance.id {
            selection = nil
        }
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
                Button("Remove Instance", role: .destructive, action: onDelete)
            }
        }
        .navigationTitle(instance.name)
    }
}
