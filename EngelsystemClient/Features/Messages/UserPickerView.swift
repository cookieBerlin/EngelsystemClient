import SwiftUI
import EngelsystemClientKit

/// Lists every user on `instance` (`GET /users`) so the signed-in user can start a new
/// conversation. Reused as `NewConversationView`'s inner step, but kept as its own
/// view so it stays independently testable/reusable.
struct UserPickerView: View {
    let instance: Instance
    var onSelect: (Reference) -> Void

    @State private var viewModel = UserPickerViewModel()

    var body: some View {
        Group {
            if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Users",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if viewModel.users.isEmpty && viewModel.isLoading {
                ProgressView()
            } else {
                List(viewModel.users, id: \.id) { user in
                    Button {
                        onSelect(user)
                    } label: {
                        Text(user.name ?? "User \(user.id)")
                    }
                }
            }
        }
        .navigationTitle("New Message")
        .task { await viewModel.load(instance: instance) }
    }
}
