import SwiftUI
import SwiftData
import EngelsystemClientKit

/// The Settings hub (restructured 2026-10-13, user-requested): a short list of topics, each
/// opening its own page — Instances, Notifications, Sync, Phone Numbers, Privacy, Diagnostics
/// and About. Reached via the "Settings" section of `MainView`'s sidebar; hosted inside
/// `MainView`'s `NavigationSplitView`/`NavigationStack`, so it is a plain pushed list.
struct SettingsView: View {
    let instances: [Instance]
    /// Called when an instance was switched on, so the caller can refresh its (possibly old) cache.
    var onInstanceActivated: (Instance) -> Void = { _ in }

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
                InstancesSettingsView(instances: instances, onActivated: onInstanceActivated)
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
    @AppStorage(ParallelSyncSetting.userDefaultsKey) private var parallelSyncs = 0

    let instances: [Instance]
    var onActivated: (Instance) -> Void = { _ in }

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
                Stepper(value: $parallelSyncs, in: ParallelSyncSetting.range) {
                    LabeledContent("Parallel Syncs", value: ParallelSyncSetting.title(for: parallelSyncs))
                }
                .accessibilityIdentifier("parallelSyncsStepper")
            } footer: {
                Text("How many instances are synced at the same time. Unlimited syncs all at once. Applies to this device only.")
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
                InstanceDetailView(instance: instance, onDelete: { delete(instance) }, onChanged: onActivated)
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
        if instance.setActive(isActive, in: modelContext) { onActivated(instance) }
    }

    private func delete(_ instance: Instance) {
        InstanceRemoval.delete(
            instance, in: modelContext, keyStores: [KeychainSyncStore(), LocalKeychainStore()], scope: .all
        )
    }
}

private struct InstanceRow: View {
    let instance: Instance

    @Environment(\.instanceColors) private var colors

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 6) {
                Circle().fill(colors.color(for: instance.id)).frame(width: 9, height: 9)
                Text(instance.name)
            }
            Text(instance.normalizedBaseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One page for an instance: the editable fields (name, server, API key with Save/Discard), the instance's status
/// and color, the connection test, the Features list and the sync times (2026-10-16 — it replaced the page plus
/// the separate "Edit Instance" sheet).
private struct InstanceDetailView: View {
    let instance: Instance
    let onDelete: () -> Void
    /// Called after the server or the key changed, so the instance gets refreshed.
    let onChanged: (Instance) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.instanceColors) private var colors
    @State private var form: EditInstanceViewModel
    @State private var isConfirmingDiscard = false

    init(instance: Instance, onDelete: @escaping () -> Void, onChanged: @escaping (Instance) -> Void) {
        self.instance = instance
        self.onDelete = onDelete
        self.onChanged = onChanged
        _form = State(initialValue: EditInstanceViewModel(instance: instance))
    }

    private var hasChanges: Bool { form.hasChanges(for: instance) }
    private let capabilities = ServerCapabilities.shared
    @State private var featuresExpandedByUser: Bool?

    private var featuresExpanded: Binding<Bool> {
        Binding(
            get: {
                featuresExpandedByUser
                    ?? FeatureListLayout.startsExpanded(ServerFeature.listed.map { capabilities.status($0, for: instance.id).state })
            },
            set: { featuresExpandedByUser = $0 }
        )
    }

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
            Section("Instance") {
                TextField("Name", text: $form.name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("instanceNameField")
                TextField("Server URL", text: $form.baseURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("instanceServerField")
                if form.requiresAPIKey {
                    SecureField("API Key (empty keeps the saved key)", text: $form.apiKey)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("instanceKeyField")
                } else {
                    // A demo address ignores the key: greyed out, with the reason.
                    SecureField("API Key", text: .constant(""))
                        .disabled(true)
                    Text(InstanceForm.demoKeyHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await form.testConnection(for: instance) }
                } label: {
                    if form.isTesting {
                        ProgressView()
                    } else if form.connectionTested {
                        Label("Connection Verified", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(!form.canTest)
                if form.connectionTested, let summary = form.featureSummary {
                    Label(summary, systemImage: "checklist")
                        .foregroundStyle(.secondary)
                }
                if let message = form.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            } footer: {
                Text("Optional: checks the server and key as entered above. Saving does not need it.")
            }

            Section {
                LabeledContent("Status", value: instance.isActive ? "Active" : "Inactive")
                // Auto spreads the colors evenly over the instances; a hand-picked color is kept and synced to the other devices.
                Picker(selection: Binding(
                    get: { InstancePalette.stored(instance.colorKey) },
                    set: { instance.setColor($0, in: modelContext) }
                )) {
                    Text("Auto").tag(InstancePalette?.none)
                    ForEach(InstancePalette.allCases) { color in
                        Label {
                            Text(color.title)
                        } icon: {
                            color.swatch
                        }
                        .tag(Optional(color))
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Color")
                        Circle().fill(colors.color(for: instance.id)).frame(width: 10, height: 10)
                    }
                }
                .accessibilityIdentifier("instanceColorPicker")
            }

            Section {
                // Collapsed while everything works, open (problems first) otherwise; a tap on the summary
                // opens or closes it and that choice holds while the page is open.
                DisclosureGroup(isExpanded: featuresExpanded) {
                    ForEach(FeatureListLayout.ordered(ServerFeature.listed, state: { capabilities.status($0, for: instance.id).state }), id: \.self) { feature in
                        featureRow(feature)
                    }
                } label: {
                    Text(capabilities.summaryText(for: instance.id))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("featuresSummary")
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
        // Unsaved edits are saved or discarded on purpose: no way back (button or swipe) until then.
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { isConfirmingDiscard = true }
                        .accessibilityIdentifier("instanceDiscardButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let serverChanged = form.save(instance: instance, in: modelContext), serverChanged {
                            onChanged(instance)
                        }
                    }
                    .disabled(!form.canSave)
                    .accessibilityIdentifier("instanceSaveButton")
                }
            }
        }
        .confirmationDialog("Discard changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { form.discard(to: instance) }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this instance will be lost.")
        }
        .task {
            if instance.isDemo { capabilities.recordDemoInstance(instance.id, newsOnly: instance.isNewsOnlyDemo) }
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
