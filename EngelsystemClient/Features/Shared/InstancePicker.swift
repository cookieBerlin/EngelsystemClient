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
    }
}
