import SwiftUI
import EngelsystemClientKit

/// Settings page "Sync": background sync interval, sync on app start, and the iCloud / last
/// background sync status. Both settings are per device (not shared with the Apple Watch).
struct SyncSettingsView: View {
    @AppStorage(DeviceSyncPreferences.syncOnAppStartUserDefaultsKey)
    private var syncOnAppStart: Bool = true
    @AppStorage(DeviceSyncPreferences.pollingIntervalUserDefaultsKey)
    private var pollingIntervalMinutes: Int = PollingInterval.manual.rawValue
    @State private var cloudSyncStatus: CloudSyncStatus = .checking

    /// Changing the interval re-schedules this device's own background task immediately.
    private var pollingInterval: Binding<PollingInterval> {
        Binding(
            get: { PollingInterval(minutes: pollingIntervalMinutes) },
            set: { newValue in
                pollingIntervalMinutes = newValue.rawValue
                BackgroundSyncScheduler.scheduleNext()
            }
        )
    }

    var body: some View {
        List {
            Section {
                Picker("Background Sync", selection: pollingInterval) {
                    ForEach(PollingInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                Toggle("Sync on App Start", isOn: $syncOnAppStart)
            } footer: {
                Text("The operating system decides exactly when a background sync actually happens — depending on battery, usage, and system load, it can take longer than the interval you pick here. Both settings are per device, not shared with your Apple Watch.")
            }

            Section("Status") {
                LabeledContent("iCloud", value: cloudSyncStatus.displayText)
                if let lastBackgroundSync = DeviceSyncPreferences.lastBackgroundSyncDate() {
                    LabeledContent("Last Background Sync",
                                   value: lastBackgroundSync.formatted(.relative(presentation: .named)))
                }
            }
        }
        .navigationTitle("Sync")
        .task {
            cloudSyncStatus = await CloudSyncStatus.current(containerIdentifier: ModelContainerFactory.cloudKitContainerIdentifier)
        }
    }
}
