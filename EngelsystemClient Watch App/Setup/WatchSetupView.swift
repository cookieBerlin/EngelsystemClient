import SwiftUI
import SwiftData
import EngelsystemClientKit

struct WatchSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = WatchSetupViewModel()

    var body: some View {
        Form {
            Section("Event") {
                TextField("Name", text: $viewModel.name)
            }

            Section("Server") {
                TextField("Server URL", text: $viewModel.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Key", text: $viewModel.apiKey)
            }

            Section {
                if viewModel.isTesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.connectionTested {
                    Label("Verified", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Test Connection") {
                        Task { await viewModel.testConnection() }
                    }
                    .disabled(!viewModel.canTest)
                }
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
                if !viewModel.isTesting {
                    Button("Save") {
                        Task { _ = await viewModel.save(in: modelContext) }
                    }
                    .disabled(!viewModel.canSubmit)

                    Button("Try Demo Mode") {
                        Task { _ = await viewModel.useDemoInstance(in: modelContext) }
                    }
                }
            }
        }
        .navigationTitle("Setup")
    }
}

#Preview {
    NavigationStack {
        WatchSetupView()
    }
    .modelContainer(for: Instance.self, inMemory: true)
}
