import SwiftUI
import EngelsystemClientKit

/// `sheet(item:)` needs an `Identifiable` payload; a bare `String` isn't one.
private struct DiagnosticsExport: Identifiable {
    let id = UUID()
    let text: String?
}

/// Settings page "Diagnostics": debug logging, the debug log and the MetricKit export.
struct DiagnosticsSettingsView: View {
    @AppStorage(DebugLog.isEnabledUserDefaultsKey)
    private var isDebugLoggingEnabled: Bool = false
    @AppStorage(DebugLog.maxEntriesUserDefaultsKey)
    private var maxDebugLogEntries: Int = DebugLog.defaultMaxEntries
    @State private var diagnosticsToExport: DiagnosticsExport?

    var body: some View {
        List {
            Section {
                Toggle("Debug Logging", isOn: $isDebugLoggingEnabled)
                Picker("Max Log Entries", selection: $maxDebugLogEntries) {
                    ForEach(DebugLog.availableMaxEntryCounts, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                NavigationLink("View Debug Log") {
                    DebugLogView()
                }
                Button {
                    diagnosticsToExport = DiagnosticsExport(text: MetricKitReporter.shared.exportText())
                } label: {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Records internal sync and notification activity for troubleshooting. Never includes API keys or other secrets. Off by default; turning it off doesn't erase what's already logged — use \"Clear\" in the log view for that. \"Export Diagnostics\" shares crash/hang/performance data collected on-device by Apple's MetricKit — nothing is sent anywhere automatically, and you see what it contains before sharing.")
            }
        }
        .navigationTitle("Diagnostics")
        .sheet(item: $diagnosticsToExport) { export in
            ExportDiagnosticsView(diagnosticsText: export.text)
        }
    }
}
