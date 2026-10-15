import SwiftUI
import SwiftData
import EngelsystemClientKit

/// The Settings hub (restructured 2026-10-13, user-requested): a short list of topics, each
/// opening its own page — Instances, Notifications, Sync, Phone Numbers, Privacy, Diagnostics
/// and About. Reached via the "Settings" section of `MainView`'s sidebar; hosted inside
/// `MainView`'s `NavigationSplitView`/`NavigationStack`, so it is a plain pushed list.
struct SettingsView: View {
    let instances: [Instance]

    @AppStorage(DeviceSyncPreferences.pollingIntervalUserDefaultsKey)
    private var pollingIntervalMinutes: Int = PollingInterval.manual.rawValue
    @AppStorage(MapLinkMode.userDefaultsKey)
    private var mapLinkModeRaw: String = MapLinkMode.embedded.rawValue
    @AppStorage(DebugLog.isEnabledUserDefaultsKey)
    private var isDebugLoggingEnabled: Bool = false
    @Query private var leadTimeSettingsRows: [NotificationLeadTimeSettings]

    var body: some View {
        List {
            NavigationLink {
                InstancesSettingsView(instances: instances)
            } label: {
                SettingsRowLabel(title: "Instances", systemImage: "server.rack",
                                 summary: SettingsSummary.instances(active: instances.filter(\.isActive).count, total: instances.count))
            }
            NavigationLink {
                NotificationsSettingsView()
            } label: {
                SettingsRowLabel(
                    title: "Notifications", systemImage: "bell",
                    summary: SettingsSummary.notifications(
                        leadTimes: NotificationLeadTimeSettings.leadTimes(
                            for: NotificationLeadTimeSettings.currentPlatform, in: leadTimeSettingsRows)))
            }
            NavigationLink {
                SyncSettingsView()
            } label: {
                SettingsRowLabel(title: "Sync", systemImage: "arrow.triangle.2.circlepath",
                                 summary: SettingsSummary.sync(pollingIntervalMinutes: pollingIntervalMinutes))
            }
            NavigationLink {
                PhoneNumbersSettingsView()
            } label: {
                SettingsRowLabel(title: "Phone Numbers", systemImage: "phone", summary: "")
            }
            NavigationLink {
                PrivacySettingsView()
            } label: {
                SettingsRowLabel(title: "Privacy", systemImage: "hand.raised",
                                 summary: SettingsSummary.privacy(mapLinkRaw: mapLinkModeRaw))
            }
            NavigationLink {
                DiagnosticsSettingsView()
            } label: {
                SettingsRowLabel(title: "Diagnostics", systemImage: "stethoscope",
                                 summary: SettingsSummary.diagnostics(isEnabled: isDebugLoggingEnabled))
            }
            NavigationLink {
                AboutSettingsView()
            } label: {
                SettingsRowLabel(title: "About", systemImage: "info.circle", summary: SettingsSummary.version(info: Bundle.main.infoDictionary))
            }
        }
        .navigationTitle("Settings")
    }
}

/// One row of the hub: icon, title and a short, secondary summary of the current state.
private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let summary: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            if !summary.isEmpty {
                Spacer()
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }
}

/// Instance management (page "Instances"). 2026-09-17 multi-active-instance redesign
/// (CLAUDE.md): any number of instances can be active simultaneously. Superseded
/// 2026-09-22, at the user's explicit request: a single flat list with a per-row `Toggle`
/// bound directly to `instance.isActive`, no sections.
struct InstancesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var multiInstanceDisplayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @State private var isPresentingSetup = false

    let instances: [Instance]

    private var multiInstanceDisplayMode: Binding<MultiInstanceDisplayMode> {
        Binding(
            get: { MultiInstanceDisplayMode.stored(raw: multiInstanceDisplayModeRaw) },
            set: { multiInstanceDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section("Instances") {
                if instances.isEmpty {
                    Text("No instances configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(instances) { instance in
                        instanceRow(for: instance)
                    }
                }
            }

            Section {
                Picker("Multiple Active Instances", selection: multiInstanceDisplayMode) {
                    ForEach(MultiInstanceDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text("How Shifts, News, and Profile display data when more than one instance is active at the same time.")
            }
        }
        .navigationTitle("Instances")
        .toolbar {
            ToolbarItem {
                Button {
                    isPresentingSetup = true
                } label: {
                    Label("Add Instance", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingSetup) {
            InstanceSetupView()
        }
    }

    /// A `NavigationLink` alone would make the whole row (including the toggle) into
    /// a single tap target, navigating instead of toggling whenever the toggle itself
    /// is tapped. Layering an invisible `NavigationLink` behind the real row content
    /// keeps the chevron/row-tap-to-detail behavior while letting the `Toggle` handle
    /// its own taps — a standard SwiftUI `List` pattern for "row navigates, but has
    /// its own accessory control too".
    @ViewBuilder
    private func instanceRow(for instance: Instance) -> some View {
        ZStack {
            // Destination-based (not value-based): this page is itself pushed from the hub, and a
            // value link did not push the detail page from here (found with the UI tests).
            NavigationLink {
                InstanceDetailView(instance: instance, onDelete: { delete(instance) })
            } label: {
                EmptyView()
            }
            .opacity(0)
            HStack {
                InstanceRow(instance: instance)
                Spacer()
                Toggle(isOn: Binding(
                    get: { instance.isActive },
                    set: { setActive(instance, isActive: $0) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                // `.labelsHidden()` + an `EmptyView()` label leaves the switch with no
                // accessible name of its own — bad for VoiceOver, and unfindable by a
                // UI test — so name it explicitly instead of relying on positional
                // queries.
                .accessibilityLabel("\(instance.name) Active")
            }
        }
    }

    private func setActive(_ instance: Instance, isActive: Bool) {
        instance.setActive(isActive, in: modelContext)
    }

    private func delete(_ instance: Instance) {
        InstanceRemoval.delete(
            instance, in: modelContext, keyStores: [KeychainSyncStore(), LocalKeychainStore()], scope: .all
        )
    }
}

private struct InstanceRow: View {
    let instance: Instance

    var body: some View {
        VStack(alignment: .leading) {
            Text(instance.name)
            Text(instance.normalizedBaseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct InstanceDetailView: View {
    let instance: Instance
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEdit = false
    private let capabilities = ServerCapabilities.shared

    // Unfiltered `@Query`s, same pattern as Shifts/News/Profile — filtered down to
    // this one instance below. 2026-09-23, user-requested "last sync timestamps".
    @Query private var allShifts: [CachedShift]
    @Query private var allNews: [CachedNews]
    @Query private var allUsers: [CachedUser]
    @Query private var allWorklogs: [CachedWorklog]
    @Query private var allAngelTypeMemberships: [CachedAngelTypeMembership]

    private var lastShiftsSync: Date? { CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allShifts) }
    private var lastNewsSync: Date? { CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allNews) }
    // Profile/Worklogs/AngelTypes are three separate Cached* types but always synced
    // together by ProfileSyncService in one pass (see ProfileViewModel) — the
    // freshest of the three stands in for "when Profile was last synced" as a whole,
    // matching how the sidebar groups them into a single "Profile" screen.
    private var lastProfileSync: Date? {
        CacheSyncTimestamp.mostRecent([
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allUsers),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allWorklogs),
            CacheSyncTimestamp.lastSyncDate(for: instance.id, in: allAngelTypeMemberships),
        ])
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: instance.name)
                LabeledContent("Server", value: instance.normalizedBaseURL)
                LabeledContent("Status", value: instance.isActive ? "Active" : "Inactive")
                Button("Edit Instance") { isPresentingEdit = true }
            }

            Section {
                let summary = capabilities.summary(for: instance.id)
                Text(FeaturePresentation.summaryText(available: summary.available, total: summary.total))
                    .foregroundStyle(.secondary)
                ForEach(ServerFeature.listed, id: \.self) { feature in
                    featureRow(feature)
                }
            } header: {
                Text("Features")
            } footer: {
                Text("What this server offers and this account may use, learned during every sync. An area that is not available is simply not shown.")
            }

            Section("Last Synced") {
                syncRow("Shifts", lastShiftsSync)
                syncRow("News", lastNewsSync)
                syncRow("Profile", lastProfileSync)
            }

            Section {
                Button("Remove Instance", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(instance.name)
        .sheet(isPresented: $isPresentingEdit) {
            EditInstanceView(instance: instance)
        }
    }

    private func featureRow(_ feature: ServerFeature) -> some View {
        let status = capabilities.status(feature, for: instance.id)
        return VStack(alignment: .leading, spacing: 2) {
            Label(feature.title, systemImage: FeaturePresentation.systemImage(status))
            Text(FeaturePresentation.statusText(status))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let checked = FeaturePresentation.checkedText(status) {
                Text(checked)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func syncRow(_ label: String, _ date: Date?) -> some View {
        if let date {
            LabeledContent(label, value: date.formatted(.relative(presentation: .named)))
        } else {
            LabeledContent(label, value: "Never")
        }
    }
}

/// Combined "Edit Instance" form — name, server and API Key in one dialog
/// (see `EditInstanceViewModel` for why this replaced the previously separate "Edit
/// Name / Server" and "Update API Key" sheets).
private struct EditInstanceView: View {
    let instance: Instance

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EditInstanceViewModel

    init(instance: Instance) {
        self.instance = instance
        _viewModel = State(initialValue: EditInstanceViewModel(instance: instance))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $viewModel.name)
                }
                Section("Server") {
                    TextField("Server URL", text: $viewModel.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                }
                Section {
                    SecureField("New API Key (optional)", text: $viewModel.apiKey)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Leave blank to keep the current key. Only fill this in if it's expired, been revoked, or you're pointing this instance at a different account.")
                }
                // COMPAT(#1709): the server answered 403 to a data request — warn, but allow saving.
                if viewModel.connectionTested, let accessWarning = viewModel.accessWarning {
                    Section {
                        Label(accessWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await viewModel.testConnection(for: instance) }
                    } label: {
                        if viewModel.isTesting {
                            ProgressView()
                        } else if viewModel.connectionTested {
                            Label("Connection Verified", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(!viewModel.canTest)
                } footer: {
                    Text("Re-checks the server/key, and whether automatic user detection works. Required after changing the server URL or API key before you can save.")
                }
            }
            .navigationTitle("Edit Instance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isTesting {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save(instance: instance, in: modelContext) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSubmit)
                    }
                }
            }
        }
    }
}
