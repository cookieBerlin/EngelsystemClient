import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Settings page "Notifications": shift reminders (this device and the Apple Watch) and the
/// new-news notification. The lead times are CloudKit-synced (`NotificationLeadTimeSettings`),
/// hence a `@Query`, while "Notify on New News" is a per-device `@AppStorage`.
struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(NewsNotifier.enabledUserDefaultsKey)
    private var notifyOnNewNews: Bool = true
    @Query private var leadTimeSettingsRows: [NotificationLeadTimeSettings]

    /// Sorted ascending for a stable display order. Parameterized by platform because both
    /// the iOS and the Watch list are editable from here.
    private func leadTimesMinutes(for platform: String) -> [Int] {
        NotificationLeadTimeSettings.leadTimes(for: platform, in: leadTimeSettingsRows)
    }

    private func leadTimesAvailableToAdd(for platform: String) -> [Int] {
        NotificationLeadTimeSettings.availableToAdd(currentlySelected: leadTimesMinutes(for: platform))
    }

    var body: some View {
        List {
            Section {
                ForEach(leadTimesMinutes(for: NotificationLeadTimeSettings.currentPlatform), id: \.self) { minutes in
                    HStack {
                        Text("\(minutes) min")
                        Spacer()
                        Button {
                            NotificationLeadTimeSettings.removeLeadTime(
                                minutes, for: NotificationLeadTimeSettings.currentPlatform, in: modelContext)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove \(minutes) min reminder")
                    }
                }
                if !leadTimesAvailableToAdd(for: NotificationLeadTimeSettings.currentPlatform).isEmpty {
                    Menu {
                        ForEach(leadTimesAvailableToAdd(for: NotificationLeadTimeSettings.currentPlatform), id: \.self) { minutes in
                            Button("\(minutes) min") {
                                NotificationLeadTimeSettings.addLeadTime(
                                    minutes, for: NotificationLeadTimeSettings.currentPlatform, in: modelContext)
                            }
                        }
                    } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                }
                Toggle("Notify on New News", isOn: $notifyOnNewNews)
            } header: {
                Text("Reminders")
            } footer: {
                Text("A local reminder is scheduled before each of your shifts starts, once per time added here. Shared with other iOS/iPadOS devices on this account. Also whether a notification is posted when a News sync finds a new announcement.")
            }

            // The Apple Watch's own reminder list, editable from here too (same CloudKit-synced
            // model). Distinct accessibility labels keep the two "Add Reminder"-shaped controls
            // unambiguous.
            Section {
                ForEach(leadTimesMinutes(for: "watch"), id: \.self) { minutes in
                    HStack {
                        Text("\(minutes) min")
                        Spacer()
                        Button {
                            NotificationLeadTimeSettings.removeLeadTime(minutes, for: "watch", in: modelContext)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove \(minutes) min Watch reminder")
                    }
                }
                if !leadTimesAvailableToAdd(for: "watch").isEmpty {
                    Menu {
                        ForEach(leadTimesAvailableToAdd(for: "watch"), id: \.self) { minutes in
                            Button("\(minutes) min") {
                                NotificationLeadTimeSettings.addLeadTime(minutes, for: "watch", in: modelContext)
                            }
                        }
                    } label: {
                        Label("Add Watch Reminder", systemImage: "plus")
                    }
                }
            } header: {
                Text("Apple Watch Reminders")
            } footer: {
                Text("Your Apple Watch's own reminder list — independent from the one above, but editable from here too.")
            }
        }
        .navigationTitle("Notifications")
    }
}
