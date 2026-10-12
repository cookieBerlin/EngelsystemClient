import SwiftUI

/// Compact, non-blocking status overlay shown while `MainView`'s app-start sync runs
/// (2026-09-22, user-requested): an `.overlay`, not a sheet, so the rest of the app —
/// including navigating into Shifts/News/Profile while the sync is still going —
/// stays fully usable underneath it. Shows a determinate progress bar with the
/// current step's description; falls back to a plain indeterminate spinner before
/// the first progress update arrives (`total == 0`).
struct SyncProgressBanner: View {
    let statusText: String
    let fraction: Double
    let total: Int
    let didFail: Bool

    var body: some View {
        VStack(spacing: 6) {
            if didFail {
                Label("Partially Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if total > 0 {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.top, 8)
        // Lets the screenshot UI tests wait until a sync has finished and the banner is gone.
        .accessibilityIdentifier("syncProgressBanner")
    }
}
