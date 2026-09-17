import SwiftUI
import SwiftData
import CoreData
import Combine

extension View {
    /// SwiftData's `@Query` doesn't always promptly re-evaluate when CloudKit delivers
    /// a remote change into the local store in the background (e.g. an edit made on
    /// another device arriving via push) — reported 2026-09-18: toggling
    /// `Instance.isActive` on the Watch only showed up in the iPhone app's Settings
    /// after leaving and re-entering the screen, meaning the data had already synced
    /// locally but the still-visible view never redrew on its own. Observing Core
    /// Data's underlying `NSPersistentStoreRemoteChange` notification (SwiftData is
    /// built on Core Data, so this still fires) and forcing an — otherwise no-op —
    /// `modelContext.save()` posts the "did save" signal `@Query`'s observers are
    /// actually listening for, which a pure remote-store merge alone doesn't generate.
    /// Applied once at the app root (`EngelsystemClientApp`), not per-screen, so every
    /// `@Query` bound to the shared context benefits.
    ///
    /// `.receive(on: DispatchQueue.main)` is required, not optional: Core Data posts
    /// `NSPersistentStoreRemoteChange` from a background queue, and `ModelContext` is
    /// main-actor-bound — without this, `modelContext.save()` runs on that background
    /// thread, which is exactly the "Publishing changes from background threads is not
    /// allowed" runtime warning spamming the console (confirmed hands-on: introduced by
    /// an earlier version of this fix that omitted it).
    func refreshesOnRemoteCloudKitChange(modelContext: ModelContext) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            try? modelContext.save()
        }
    }
}
