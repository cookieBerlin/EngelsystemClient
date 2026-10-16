import SwiftUI
import EngelsystemClientKit

extension InstancePalette {
    /// System colors, so they adapt to light and dark mode.
    var color: Color {
        switch self {
        case .blue: return .blue
        case .orange: return .orange
        case .green: return .green
        case .purple: return .purple
        case .pink: return .pink
        case .teal: return .teal
        case .red: return .red
        case .indigo: return .indigo
        }
    }
}

/// The color of every instance (`InstancePalette.assignments(for:)`), provided to all screens through the
/// environment by `MainView`. Looked up by id or — where a row only knows the instance's name — by name.
struct InstanceColors: Equatable {
    private let byID: [UUID: InstancePalette]
    private let byName: [String: InstancePalette]

    init(instances: [Instance] = []) {
        let assignments = InstancePalette.assignments(for: instances)
        byID = assignments
        byName = Dictionary(
            instances.compactMap { instance in assignments[instance.id].map { (instance.name, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    func color(for id: UUID) -> Color { (byID[id] ?? .blue).color }

    func color(named name: String) -> Color { (byName[name] ?? .blue).color }
}

private struct InstanceColorsKey: EnvironmentKey {
    static let defaultValue = InstanceColors()
}

extension EnvironmentValues {
    var instanceColors: InstanceColors {
        get { self[InstanceColorsKey.self] }
        set { self[InstanceColorsKey.self] = newValue }
    }
}
