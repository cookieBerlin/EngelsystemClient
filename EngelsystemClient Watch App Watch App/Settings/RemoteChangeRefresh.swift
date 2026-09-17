import SwiftUI
import SwiftData
import CoreData
import Combine

/// Watch equivalent of the iOS app's `RemoteChangeRefresh` (`Features/Shared`) —
/// duplicated rather than shared since it's SwiftUI view-layer code, and this project
/// keeps UI-layer code out of the platform-agnostic `EngelsystemClientKit` package.
extension View {
    /// `.receive(on: DispatchQueue.main)` is required: Core Data posts
    /// `NSPersistentStoreRemoteChange` from a background queue, and `ModelContext` is
    /// main-actor-bound — see the iOS counterpart's doc comment for the full story.
    func refreshesOnRemoteCloudKitChange(modelContext: ModelContext) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            try? modelContext.save()
        }
    }
}
