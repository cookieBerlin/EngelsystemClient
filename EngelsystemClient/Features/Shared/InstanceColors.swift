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

#if canImport(UIKit)
import UIKit

extension InstancePalette {
    /// A small filled circle in the palette color that keeps its color inside a menu: menu items draw symbols as
    /// monochrome templates (all black), an image with the original rendering mode is left alone.
    var swatch: Image {
        let configuration = UIImage.SymbolConfiguration(pointSize: 16)
        // The system symbol always exists; the plain symbol is only the (never used) fallback behind it.
        let colored = [UIImage(systemName: "circle.fill", withConfiguration: configuration)].compactMap { $0 }
            .map { Image(uiImage: $0.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)) }
        return (colored + [Image(systemName: "circle.fill")])[0]
    }
}
#endif

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
