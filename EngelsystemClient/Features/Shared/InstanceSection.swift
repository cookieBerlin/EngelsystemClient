import SwiftUI
import EngelsystemClientKit

/// The heading of one instance in the "separate sections" mode: a tinted band across the full width with the
/// instance's color, its name, how many entries it has and a chevron. Tapping it folds the instance away.
struct InstanceSectionHeader: View {
    let instance: Instance
    let countText: String
    let isCollapsed: Bool
    let onToggle: () -> Void

    @Environment(\.instanceColors) private var colors

    var body: some View {
        let color = colors.color(for: instance.id)
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(instance.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if !countText.isEmpty {
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.16))
            .overlay(alignment: .top) { Rectangle().fill(color).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .listRowInsets(EdgeInsets())
        .accessibilityLabel("\(instance.name), \(countText), \(isCollapsed ? "collapsed" : "expanded")")
        .accessibilityHint("Double tap to \(isCollapsed ? "expand" : "collapse")")
        .accessibilityIdentifier("instanceHeader-\(instance.name)")
    }
}

/// A section of one instance whose content can be folded away. `collapsed` lives in the screen that owns
/// the list and holds while that screen is open.
struct InstanceSection<Content: View>: View {
    let instance: Instance
    let countText: String
    @Binding var collapsed: Set<UUID>
    @ViewBuilder var content: Content

    var body: some View {
        let isCollapsed = collapsed.contains(instance.id)
        Section {
            if !isCollapsed { content }
        } header: {
            InstanceSectionHeader(instance: instance, countText: countText, isCollapsed: isCollapsed) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsed.remove(instance.id) } else { collapsed.insert(instance.id) }
                }
            }
        }
    }
}

/// A small heading inside an instance (a topic like "Angel types" or a day), set apart from the
/// instance band above it.
struct SubheadingRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// A colored edge on the left of a row that belongs to an instance (merged mode), in the instance's color.
    func instanceEdge(named name: String?, colors: InstanceColors) -> some View {
        listRowBackground(
            HStack(spacing: 0) {
                if let name { colors.color(named: name).frame(width: 4) }
                Color.clear
            }
        )
    }
}
