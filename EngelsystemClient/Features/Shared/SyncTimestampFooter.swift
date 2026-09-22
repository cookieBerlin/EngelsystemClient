import SwiftUI

/// A small, centered "Last Synced: …" row at the bottom of a `List` — 2026-09-23,
/// user-requested, extending the same "Last Synced" info already shown on Settings'
/// per-instance detail screen to Shifts/News/Profile themselves. Styled identically
/// to Settings' own version/sync-status footer (`.footnote`, `.secondary`, centered,
/// transparent row background).
///
/// Shows one aggregate timestamp for the whole screen — the freshest sync across
/// *all* currently active instances contributing to it, not a per-instance
/// breakdown (that's what the Settings instance-detail screen is for). `nil` means
/// nothing for the active instance(s) has ever been cached (shown as "Never") —
/// note this can't currently distinguish "never synced" from "synced, but the
/// server returned zero items", since there's no dedicated timestamp separate from
/// the cached rows themselves; matches the same known limitation already accepted
/// for Settings' equivalent section.
struct SyncTimestampFooter: View {
    let date: Date?

    var body: some View {
        Section {
            Text(date.map { "Last Synced: \($0.formatted(.relative(presentation: .named)))" } ?? "Last Synced: Never")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color.clear)
    }
}
