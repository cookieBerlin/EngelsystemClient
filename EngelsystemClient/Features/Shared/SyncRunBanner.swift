import SwiftUI
import EngelsystemClientKit

/// The banner of a full sync: one row per instance with its state, the area it is working on and a thin
/// line for the finished steps, plus "Stop sync" (with a confirmation, and "Skip <instance>" when several
/// instances are syncing). All texts, symbols and the "not responding" rule live in the tested Kit type
/// `SyncRunModel`; this file is layout.
struct SyncRunBanner: View {
    let model: SyncRunModel
    let isRunning: Bool
    let onStop: () -> Void
    let onSkip: (UUID) -> Void

    @State private var isConfirmingStop = false

    var body: some View {
        // Once a second, so a step that stops answering turns orange without any event arriving.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.rows) { row in
                    rowView(row, now: context.date)
                }
                if isRunning {
                    Button("Stop sync") { isConfirmingStop = true }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("stopSyncButton")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.top, 8)
        // `.contain` keeps the Stop button its own identifier (a plain identifier on the parent would override it).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("syncProgressBanner")
        .confirmationDialog("Stop sync?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
            // Every instance that is busy or still waiting can be skipped alone.
            if model.showsNames {
                ForEach(model.rows.filter { [.running, .waiting].contains($0.status) }) { row in
                    Button("Skip \(row.name)") { onSkip(row.id) }
                }
            }
            Button("Stop Sync", role: .destructive, action: onStop)
            Button("Keep Waiting", role: .cancel) {}
        } message: {
            Text("Data already loaded is kept. Instances that were not synced yet stay as they are.")
        }
    }

    private func rowView(_ row: SyncRunModel.Row, now: Date) -> some View {
        let color = color(for: row, now: now)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: model.systemImage(for: row, now: now))
                    .foregroundStyle(color)
                    .font(.caption)
                Text(model.text(for: row, now: now))
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count = model.stepCountText(for: row) {
                    Text(count)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25))
                    Capsule().fill(color).frame(width: geometry.size.width * row.fraction)
                }
            }
            .frame(height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityText(for: row, now: now))
    }

    private func color(for row: SyncRunModel.Row, now: Date) -> Color {
        switch row.status {
        case .waiting, .skipped: return .secondary
        case .running: return model.isSlow(row, now: now) ? .orange : .blue
        case .succeeded: return .green
        case .failed, .timedOut: return .red
        }
    }
}
