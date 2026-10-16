import SwiftUI
import SwiftData
import EngelsystemClientKit

/// The footer of the main page's list: per active instance how old its cached data
/// is — grey with a check mark while it is fresh, orange with a warning triangle from 12 hours on,
/// red when nothing was ever synced. A tap refreshes that instance. All decisions and texts live in
/// the tested Kit type `InstanceFreshness`; this file is layout.
struct InstanceFreshnessFooter: View {
    let instances: [Instance]
    let onRefresh: (Instance) -> Void

    // Unfiltered `@Query`s, filtered per instance below (same pattern as the instance detail page).
    @Query private var shifts: [CachedShift]
    @Query private var news: [CachedNews]
    @Query private var users: [CachedUser]
    @Query private var worklogs: [CachedWorklog]
    @Query private var angelTypes: [CachedAngelTypeMembership]

    private func lastSync(of instance: Instance) -> Date? {
        CacheSyncTimestamp.mostRecent([
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: shifts),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: news),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: users),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: worklogs),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: angelTypes),
        ])
    }

    var body: some View {
        // The ages move on with the clock, so the rows are rebuilt every minute.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                ForEach(InstanceFreshness.rows(for: instances, lastSync: lastSync(of:), now: context.date)) { row in
                    Button {
                        if let instance = instances.first(where: { $0.id == row.id }) { onRefresh(instance) }
                    } label: {
                        Label(row.text, systemImage: row.systemImage)
                            .font(.footnote)
                            .foregroundStyle(color(for: row.level))
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.accessibilityText)
                    .accessibilityIdentifier("freshness-\(row.instanceName)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(for level: InstanceFreshness.Level) -> Color {
        switch level {
        case .current: return .secondary
        case .stale: return .orange
        case .neverSynced: return .red
        }
    }
}
