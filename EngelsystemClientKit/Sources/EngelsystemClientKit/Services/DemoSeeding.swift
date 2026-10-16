import Foundation
import SwiftData

/// Debug-only launch argument that inserts a Demo Mode instance on startup (2026-10-12), so the
/// automatic App Store screenshot run (`Scripts/screenshots.sh`) and the Watch screenshot can start
/// in a populated app without driving the setup screen. In Release builds `shouldSeed` is always
/// `false`, so the argument does nothing in anything shipped.
public enum DemoSeeding {
    public static let launchArgument = "-seed-demo-instance"

    /// Debug-only: deletes every instance on launch, so UI tests always start at the "no instance
    /// configured" setup screen instead of depending on the simulator's earlier state.
    public static let resetArgument = "-reset-instances"

    public static func shouldReset(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains(resetArgument)
        #else
        false
        #endif
    }

    /// Deletes all instances when `shouldReset` says so. Returns whether it ran.
    @MainActor
    @discardableResult
    public static func resetIfRequested(arguments: [String], in modelContext: ModelContext) -> Bool {
        guard shouldReset(arguments: arguments) else { return false }
        try? modelContext.delete(model: Instance.self)
        try? modelContext.save()
        return true
    }

    /// Debug-only: the Watch app opens its Settings screen on launch, for the Watch settings screenshot.
    public static let openSettingsArgument = "-open-settings"

    public static func shouldOpenSettings(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains(openSettingsArgument)
        #else
        false
        #endif
    }

    /// Debug-only: with `-open-settings`, the Watch app opens this Settings page (`Instances`, `Notifications`, `Sync`,
    /// `Diagnostics`, `About`) instead of the hub — for the guide's Watch screenshots (`Scripts/screenshots.sh manual`).
    public static let openSettingsPageArgument = "-open-settings-page"

    /// The page named by `-open-settings-page <name>`; nil without the argument (and in Release builds).
    public static func settingsPage(arguments: [String]) -> String? {
        #if DEBUG
        guard let index = arguments.firstIndex(of: openSettingsPageArgument) else { return nil }
        return arguments.dropFirst(index + 1).first
        #else
        return nil
        #endif
    }

    /// Seeds only when the argument was passed (Debug builds) and no instance exists yet.
    public static func shouldSeed(arguments: [String], existingInstanceCount: Int) -> Bool {
        #if DEBUG
        arguments.contains(launchArgument) && existingInstanceCount == 0
        #else
        false
        #endif
    }

    /// Inserts a "Demo" instance (its API key goes to `store`) when `shouldSeed` says so.
    /// Returns whether an instance was inserted.
    @MainActor
    @discardableResult
    public static func seedIfRequested(arguments: [String], in modelContext: ModelContext, store: APIKeyStore) async -> Bool {
        resetIfRequested(arguments: arguments, in: modelContext)
        // A failed count is treated as 0 (compactMap drops the nil) — written without `?? 0`
        // so there is no never-taken autoclosure region to cover.
        let existing = [try? modelContext.fetchCount(FetchDescriptor<Instance>())].compactMap { $0 }.reduce(0, +)
        guard shouldSeed(arguments: arguments, existingInstanceCount: existing) else { return false }
        guard let instance = try? await InstanceSetupService().createInstance(
            name: "Demo", baseURL: Instance.demoBaseURL, apiKey: "demo", store: store
        ) else { return false }
        modelContext.insert(instance)
        try? modelContext.save()
        return true
    }
}
