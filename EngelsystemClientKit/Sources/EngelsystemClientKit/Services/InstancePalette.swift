import Foundation

/// The colors an instance can be marked with (headings, badges, row edges). The names are mapped to
/// system colors by the app, so they adapt to light and dark mode.
public enum InstancePalette: String, CaseIterable, Identifiable, Sendable {
    case blue, orange, green, purple, pink, teal, red, indigo

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    /// The color stored for an instance (`Instance.colorKey`); nil or an unknown key means "Auto".
    public static func stored(_ key: String?) -> InstancePalette? {
        key.flatMap(InstancePalette.init(rawValue:))
    }

    /// The colors of all instances. A color the user picked by hand stays; every instance on "Auto" gets
    /// the next palette color that no instance picked by hand, in the order the instances were created,
    /// so the colors are spread evenly and the same on every device. When there are more instances than
    /// colors the palette starts over.
    public static func assignments(for instances: [Instance]) -> [UUID: InstancePalette] {
        let ordered = instances.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var result: [UUID: InstancePalette] = [:]
        var picked: Set<InstancePalette> = []
        for instance in ordered {
            if let color = stored(instance.colorKey) {
                result[instance.id] = color
                picked.insert(color)
            }
        }
        let free = allCases.filter { !picked.contains($0) }
        let pool = free.isEmpty ? allCases : free
        var next = 0
        for instance in ordered where result[instance.id] == nil {
            result[instance.id] = pool[next % pool.count]
            next += 1
        }
        return result
    }
}
