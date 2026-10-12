import SwiftUI
import SwiftData
import EngelsystemClientKit

struct InstanceSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = InstanceSetupViewModel()

    /// Set when this view is shown as the very first entry point (no instance exists yet) —
    /// in that case there's no Cancel button, since there's nothing to return to.
    var isInitialSetup: Bool = false

    var onSaved: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Name (e.g. 42C3)", text: $viewModel.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Engelsystem Server") {
                    TextField("https://engelsystem.example.org", text: $viewModel.baseURL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Key", text: $viewModel.apiKey)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await viewModel.testConnection() }
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
                    Text("Checks the server and API key before adding this instance.")
                }

                // COMPAT(#1709): the server answered 403 to a data request — warn, but allow saving.
                if viewModel.connectionTested, let accessWarning = viewModel.accessWarning {
                    Section {
                        Label(accessWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("You can find the API key in your Engelsystem user settings. Requires the “API” or “Bureaucrat” group.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Try Demo Mode") {
                        Task {
                            if await viewModel.useDemoInstance(in: modelContext) {
                                onSaved?()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isTesting)
                } footer: {
                    Text("Explore the app with sample data — no real server or API key needed.")
                }
            }
            .navigationTitle("Add Instance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !isInitialSetup {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isTesting {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save(in: modelContext) {
                                    onSaved?()
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

#Preview {
    InstanceSetupView(isInitialSetup: true)
        .modelContainer(for: Instance.self, inMemory: true)
}
