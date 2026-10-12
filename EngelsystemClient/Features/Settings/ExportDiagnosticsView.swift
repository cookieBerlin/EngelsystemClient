import SwiftUI
import EngelsystemClientKit

/// Shown before diagnostics are shared (2026-10-12, user-requested): explains what the
/// export contains and that nothing leaves the device until the user picks a destination
/// in the share sheet. `ShareLink` can't be triggered programmatically, so the share
/// button lives in this sheet rather than directly in Settings.
struct ExportDiagnosticsView: View {
    let diagnosticsText: String
    @Environment(\.dismiss) private var dismiss

    private var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(diagnosticsText.utf8.count), countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What you are about to share") {
                    Text("Crash, hang and performance reports that iOS collected about this app on your device (\(sizeDescription)).")
                    Text("They contain technical details: device model, iOS version, app version, call stacks and performance figures. They do not contain your API key, shifts or messages.")
                }
                Section {
                    Text("Nothing is sent from here on its own. You choose the destination (for example Mail) in the next step. Reports are kept on the device for up to 30 days and at most 1 MB.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ShareLink(item: diagnosticsText, preview: SharePreview("MetricKit Diagnostics")) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Export Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
