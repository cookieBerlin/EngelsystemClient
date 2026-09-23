import SwiftUI
import UIKit
import EngelsystemClientKit

/// 2026-09-23, user-requested: the in-app viewer for `DebugLog` — every entry
/// color-coded by level, selectable text, plus bulk "Copy to Clipboard" and "Clear"
/// actions. Reached from Settings' "Diagnostics" section (`SettingsView`).
struct DebugLogView: View {
    @State private var debugLog = DebugLog.shared
    @State private var isPresentingClearConfirmation = false

    var body: some View {
        Group {
            if debugLog.entries.isEmpty {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Nothing has been logged yet. Turn on Debug Logging above and use the app for a bit.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(debugLog.entries) { entry in
                            Text(entry.displayText)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                // Lets the user select and copy an individual line or range, in
                // addition to the bulk "Copy to Clipboard" toolbar action below.
                .textSelection(.enabled)
            }
        }
        .navigationTitle("Debug Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = debugLog.exportText
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .disabled(debugLog.entries.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    isPresentingClearConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(debugLog.entries.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear the debug log? This can't be undone.",
            isPresented: $isPresentingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { debugLog.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func color(for level: DebugLogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
