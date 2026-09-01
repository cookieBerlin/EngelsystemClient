import SwiftUI

/// Shared inline error presentation for feature screens that sync from `APIClient` —
/// avoids the same banner styling being duplicated in Shifts/News/Profile.
struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.red)
    }
}
