import WidgetKit
import SwiftUI
import EngelsystemClientKit

/// The complication reads a snapshot written by the Watch app's NextShiftViewModel via
/// an App Group (see NextShiftSnapshotStore) — it never talks to the network or the
/// Keychain itself, both of which belong to the main Watch app process only.
struct NextShiftEntry: TimelineEntry {
    let date: Date
    let snapshot: NextShiftSnapshot?
}

struct NextShiftTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextShiftEntry {
        NextShiftEntry(
            date: Date(),
            snapshot: NextShiftSnapshot(
                title: "Info Desk Shift",
                startsAt: Date(),
                endsAt: Date().addingTimeInterval(3600),
                locationName: "Heaven"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextShiftEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(NextShiftEntry(date: Date(), snapshot: NextShiftSnapshotStore().load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextShiftEntry>) -> Void) {
        let entry = NextShiftEntry(date: Date(), snapshot: NextShiftSnapshotStore().load())
        // The Watch app calls WidgetCenter.reloadAllTimelines() after every sync, so this
        // periodic refresh is just a safety net between syncs.
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct NextShiftComplication: Widget {
    let kind = "NextShiftComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextShiftTimelineProvider()) { entry in
            NextShiftComplicationView(entry: entry)
        }
        .configurationDisplayName("Next Shift")
        .description("Shows your next upcoming Engelsystem shift.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextShiftComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextShiftEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    private var circularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "calendar")
            if let snapshot = entry.snapshot {
                Text(snapshot.startsAt, style: .time)
                    .font(.system(size: 12))
                    .minimumScaleFactor(0.7)
            } else {
                Text("--")
                    .font(.system(size: 12))
            }
        }
        .widgetAccentable()
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let snapshot = entry.snapshot {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(snapshot.startsAt, style: .time)
                    .font(.caption)
                if let locationName = snapshot.locationName {
                    Text(locationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No upcoming shifts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inlineView: some View {
        Group {
            if let snapshot = entry.snapshot {
                Text("\(snapshot.title) \(snapshot.startsAt, style: .time)")
            } else {
                Text("No shifts")
            }
        }
    }
}

#Preview(as: .accessoryRectangular) {
    NextShiftComplication()
} timeline: {
    NextShiftEntry(
        date: Date(),
        snapshot: NextShiftSnapshot(title: "Info Desk Shift", startsAt: Date(), endsAt: Date().addingTimeInterval(3600), locationName: "Heaven")
    )
    NextShiftEntry(date: Date(), snapshot: nil)
}
