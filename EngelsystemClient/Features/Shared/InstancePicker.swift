import SwiftUI
import EngelsystemClientKit

/// Segmented control backing `MultiInstanceDisplayMode.switcher` — lets the user pick
/// which of several active instances' data is currently shown on Shifts/News/Profile.
/// Only meaningful (and only rendered by callers) when there's more than one active
/// instance to choose from.
struct InstancePicker: View {
    let instances: [Instance]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Instance", selection: $selection) {
            ForEach(instances) { instance in
                Text(instance.name).tag(Optional(instance.id))
            }
        }
        .pickerStyle(.segmented)
        .onAppear { ensureSelection() }
        .onChange(of: instances.map(\.id)) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        selection = Self.resolvedSelection(current: selection, instances: instances)
    }

    /// The segmented control itself shows no highlighted segment at all when
    /// `selection` doesn't match any row's tag — which `nil` (its initial value)
    /// never does, since rows are only ever tagged with a real instance ID. Callers
    /// (`ShiftsView`/`NewsView`/`ProfileView`) separately fall back to
    /// `instances.first` to decide *which data* to show, but that only fixed the
    /// content, never the picker's own visual selection (2026-09-22, user-reported:
    /// "no tab preselected" in switcher mode). Also re-anchors selection if the
    /// previously selected instance dropped out of `instances` (e.g. deactivated),
    /// rather than silently pointing at nothing again. A `static` pure function, not
    /// inlined into `ensureSelection`, so it's unit-testable
    /// (`EngelsystemClientTests.InstancePickerSelectionTests`) without needing to
    /// construct a full `InstancePicker`/drive its `body`.
    static func resolvedSelection(current: UUID?, instances: [Instance]) -> UUID? {
        if instances.contains(where: { $0.id == current }) {
            return current
        }
        return instances.first?.id
    }
}
