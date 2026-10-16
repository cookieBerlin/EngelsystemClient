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
    private var isDebugLoggingEnabled: Bool = DebugLog.defaultEnabled
    @AppStorage(DebugLog.maxEntriesUserDefaultsKey)
    private var maxDebugLogEntries: Int = DebugLog.defaultMaxEntries
    @State private var diagnosticsToExport: DiagnosticsExport?
    @State private var watchLogs = WatchLogsViewModel()
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        List {
            Section {
                // Changed through `DebugLog.setEnabled`, which also remembers when: the newer change wins against
                // the Apple Watch's.
                Toggle("Debug Logging", isOn: Binding(
                    get: { isDebugLoggingEnabled },
                    set: { DebugLog.setEnabled($0) }
                ))
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
            } header: {
                Text("This iPhone")
            } footer: {
                Text("Records internal sync and notification activity for troubleshooting. Never includes API keys or other secrets. On by default during the beta; turning it off doesn't erase what's already logged — use \"Clear\" in the log view for that. \"Export Diagnostics\" shares crash/hang/performance data collected on-device by Apple's MetricKit — nothing is sent anywhere automatically, and you see what it contains before sharing.")
            }

            watchLogsSection
        }
        .navigationTitle("Diagnostics")
        .onAppear { watchLogs.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: WatchLogInbox.didChangeNotification)) { _ in
            watchLogs.refresh()
        }
        .sheet(item: $diagnosticsToExport) { export in
            ExportDiagnosticsView(diagnosticsText: export.text)
        }
        .confirmationDialog("Delete all Watch logs?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { watchLogs.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The logs received from the Apple Watch are removed from this iPhone.")
        }
    }

    /// The Apple Watch's logs: it sends them (on its own tap or on request), this iPhone stores, lists and shares them.
    @ViewBuilder
    private var watchLogsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { watchLogs.loggingStatus.isOn },
                set: { watchLogs.setWatchLogging($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log on Apple Watch")
                    Text(watchLogs.loggingStatusText())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("watchLoggingToggle")

            Button {
                watchLogs.request()
            } label: {
                Label("Request Log from Apple Watch", systemImage: "arrow.down.circle")
            }
            .accessibilityIdentifier("requestWatchLogButton")
            if let status = watchLogs.requestStatus {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Logs received from Apple Watch")
        } footer: {
            Text("The Apple Watch sends its log when you tap “Send Log to iPhone” in its Diagnostics, or when you request it here. The log stays on this iPhone until you delete it or share it.")
        }

        Section {
            if watchLogs.items.isEmpty {
                Text("No logs received yet. On the Apple Watch: Settings › Diagnostics › Send Log to iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(watchLogs.items) { item in
                    NavigationLink {
                        WatchLogDetailView(item: item, entries: watchLogs.entries(of: item))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.receivedAt.formatted(date: .abbreviated, time: .standard))
                            Text("\(item.entryCount) entries · \(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { watchLogs.delete(item) }
                    }
                }
                ShareLink(items: watchLogs.shareURLs) {
                    Label("Share All Watch Logs", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareAllWatchLogsButton")
                Button("Delete All", role: .destructive) { isConfirmingDeleteAll = true }
            }
        }
    }
}

/// One log received from the Apple Watch, colored by level like the iPhone's own log.
private struct WatchLogDetailView: View {
    let item: ReceivedWatchLogs.Item
    let entries: [DebugLogEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                    Text(entry.displayText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(color(for: entry.level))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .textSelection(.enabled)
        .navigationTitle(item.receivedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: item.url)
            }
        }
    }

    private func color(for level: DebugLogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
