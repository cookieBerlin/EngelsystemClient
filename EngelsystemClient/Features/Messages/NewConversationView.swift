import SwiftUI
import EngelsystemClientKit

/// Sheet shown from `MessagesView`'s "New Message" button. When more than one
/// messages-supporting instance is active, the user first picks which instance to
/// compose from (a message always belongs to exactly one server); with only one such
/// instance, that step is skipped and the user picker shows immediately.
struct NewConversationView: View {
    let instances: [Instance]
    /// Called once the user picks a recipient — the caller dismisses this sheet and
    /// navigates to the new/existing conversation itself; this view never navigates on
    /// its own.
    var onStart: (Instance, Reference) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedInstance: Instance?

    var body: some View {
        NavigationStack {
            Group {
                if let selectedInstance {
                    UserPickerView(instance: selectedInstance) { user in
                        onStart(selectedInstance, user)
                    }
                } else if instances.count == 1, let onlyInstance = instances.first {
                    UserPickerView(instance: onlyInstance) { user in
                        onStart(onlyInstance, user)
                    }
                } else {
                    List(instances) { instance in
                        Button(instance.name) {
                            selectedInstance = instance
                        }
                    }
                    .navigationTitle("Choose Instance")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
