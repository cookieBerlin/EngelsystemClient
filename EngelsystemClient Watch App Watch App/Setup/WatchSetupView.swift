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
                TextField("User ID (optional)", text: $viewModel.userIDText)
            } footer: {
                Text("Only needed if your server doesn't recognize automatic user detection.")
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
                        Task { _ = await viewModel.testAndSave(in: modelContext) }
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
