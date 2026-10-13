import SwiftUI
import SwiftData
import EngelsystemClientKit

/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): `instances` is every
/// currently active instance, aggregated per `MultiInstanceDisplayMode` — see
/// `ShiftsView` for the shared pattern. Profile is a little different from Shifts/News:
/// the "who are you" identity fields (name/pronoun/T-shirt/arrived) are inherently
/// per-instance (you can have a different profile on each server), so `.merged`/
/// `.sectioned` show one compact identity row per instance rather than trying to
/// combine them into a single card; only `.switcher` shows the full single-instance
/// identity card, same as before this redesign.
struct ProfileView: View {
    let instances: [Instance]
    /// Shared with `MainView` — see `ShiftsView`'s matching property for why.
    let syncStatus: MainSyncStatus
    var onUnauthorized: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProfileViewModel()
    @State private var selectedInstanceID: UUID?
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @Query private var allUsers: [CachedUser]
    @Query(sort: \CachedWorklog.workedAt, order: .reverse) private var allWorklogs: [CachedWorklog]
    @Query private var allAngelTypeMemberships: [CachedAngelTypeMembership]

    private var displayMode: MultiInstanceDisplayMode {
        InstanceScope.displayMode(raw: displayModeRaw, instanceCount: instances.count)
    }

    private var users: [CachedUser] { InstanceScope.filter(allUsers, to: instances, instanceID: \.instanceID) }
    private var worklogs: [CachedWorklog] { InstanceScope.filter(allWorklogs, to: instances, instanceID: \.instanceID) }
    private var angelTypeMemberships: [CachedAngelTypeMembership] { InstanceScope.filter(allAngelTypeMemberships, to: instances, instanceID: \.instanceID) }

    private var switcherInstance: Instance? {
        InstanceScope.switcherInstance(in: instances, selected: selectedInstanceID)
    }

    private func instanceName(for instanceID: UUID) -> String? {
        InstanceScope.instanceName(withID: instanceID, in: instances)
    }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableView(
                    "No Active Instance",
                    systemImage: "person.crop.circle",
                    description: Text("Activate an instance in Settings to see your profile.")
                )
            } else {
                List {
                    if let errorMessage = viewModel.errorMessage {
                        Section {
                            ErrorBanner(message: errorMessage)
                        }
                        .listRowInsets(EdgeInsets())
                    }

                    switch displayMode {
                    case .merged:
                        mergedProfileSection
                        mergedAngelTypesSection
                        mergedWorklogsSection
                    case .switcher:
                        if instances.count > 1 {
                            InstancePicker(instances: instances, selection: $selectedInstanceID)
                                .listRowSeparator(.hidden)
                        }
                        switcherContent
                    case .sectioned:
                        ForEach(instances) { instance in
                            sectionedContent(for: instance)
                        }
                    }

                    // Profile is three Cached* types (User/Worklog/AngelTypeMembership)
                    // synced together in one ProfileSyncService pass — the freshest of
                    // the three stands in for "when Profile was last synced" as a whole,
                    // same reasoning (and the same CacheSyncTimestamp.mostRecent helper)
                    // as Settings' instance-detail "Last Synced" section.
                    SyncTimestampFooter(date: CacheSyncTimestamp.mostRecent([
                        users.map(\.cachedAt).max(),
                        worklogs.map(\.cachedAt).max(),
                        angelTypeMemberships.map(\.cachedAt).max(),
                    ]))
                }
                .toolbar {
                    if viewModel.isLoading {
                        ToolbarItem { ProgressView() }
                    }
                }
                // No `.task`-on-appear sync — see ShiftsView's matching comment.
                .refreshable {
                    await syncStatus.run(statusText: "Profile") {
                        await viewModel.refresh(instances: instances, in: modelContext)
                        return viewModel.errorMessage == nil
                    }
                }
                .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
                    if isUnauthorized { onUnauthorized() }
                }
            }
        }
        .navigationTitle("Profile")
    }

    // MARK: - Merged

    @ViewBuilder
    private var mergedProfileSection: some View {
        Section("Profile") {
            if users.isEmpty {
                Text("No profile data yet.").foregroundStyle(.secondary)
            } else {
                ForEach(users) { profile in
                    ProfileIdentityRow(profile: profile, instanceName: instanceName(for: profile.instanceID))
                }
            }
        }
    }

    @ViewBuilder
    private var mergedAngelTypesSection: some View {
        Section("Angel Types") {
            if angelTypeMemberships.isEmpty {
                Text("No angel types yet.").foregroundStyle(.secondary)
            } else {
                ForEach(CachedAngelTypeMembership.sortedByName(angelTypeMemberships)) { membership in
                    AngelTypeRow(membership: membership, instanceName: instanceName(for: membership.instanceID))
                }
            }
        }
    }

    @ViewBuilder
    private var mergedWorklogsSection: some View {
        Section("Worklogs") {
            if worklogs.isEmpty {
                Text("No worklogs yet.").foregroundStyle(.secondary)
            } else {
                ForEach(worklogs) { worklog in
                    WorklogRow(worklog: worklog, instanceName: instanceName(for: worklog.instanceID))
                }
                LabeledContent("Total", value: String(format: "%.1fh", CachedWorklog.totalHours(worklogs)))
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Switcher

    @ViewBuilder
    private var switcherContent: some View {
        let instanceID = switcherInstance?.id
        let profile = users.first(where: { $0.instanceID == instanceID })
        let instanceAngelTypes = CachedAngelTypeMembership.sortedByName(angelTypeMemberships.filter { $0.instanceID == instanceID })
        let instanceWorklogs = worklogs.filter { $0.instanceID == instanceID }

        if let profile {
            Section("Profile") {
                ProfileIdentityDetail(profile: profile)
            }
        }

        Section("Angel Types") {
            if instanceAngelTypes.isEmpty {
                Text("No angel types yet.").foregroundStyle(.secondary)
            } else {
                ForEach(instanceAngelTypes) { membership in
                    AngelTypeRow(membership: membership)
                }
            }
        }

        Section("Worklogs") {
            if instanceWorklogs.isEmpty {
                Text("No worklogs yet.").foregroundStyle(.secondary)
            } else {
                ForEach(instanceWorklogs) { worklog in
                    WorklogRow(worklog: worklog)
                }
                LabeledContent("Total", value: String(format: "%.1fh", CachedWorklog.totalHours(instanceWorklogs)))
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Sectioned

    @ViewBuilder
    private func sectionedContent(for instance: Instance) -> some View {
        let profile = users.first(where: { $0.instanceID == instance.id })
        let instanceAngelTypes = CachedAngelTypeMembership.sortedByName(angelTypeMemberships.filter { $0.instanceID == instance.id })
        let instanceWorklogs = worklogs.filter { $0.instanceID == instance.id }

        Section(instance.name) {
            if let profile {
                ProfileIdentityDetail(profile: profile)
            }
            if instanceAngelTypes.isEmpty && instanceWorklogs.isEmpty && profile == nil {
                Text("No profile data yet.").foregroundStyle(.secondary)
            }
            ForEach(instanceAngelTypes) { membership in
                AngelTypeRow(membership: membership)
            }
            ForEach(instanceWorklogs) { worklog in
                WorklogRow(worklog: worklog)
            }
            if !instanceWorklogs.isEmpty {
                LabeledContent("Total", value: String(format: "%.1fh", CachedWorklog.totalHours(instanceWorklogs)))
                    .fontWeight(.semibold)
            }
        }
    }
}

private struct ProfileIdentityRow: View {
    let profile: CachedUser
    var instanceName: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(profile.displayName)
                if let pronoun = profile.pronoun {
                    Text(pronoun)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dect = profile.dect {
                    PhoneNumberRow(label: "DECT", value: dect)
                }
                if let mobile = profile.mobile {
                    PhoneNumberRow(label: "Mobile", value: mobile)
                }
            }
            Spacer()
            if let instanceName {
                InstanceBadge(name: instanceName)
            }
        }
    }
}

private struct ProfileIdentityDetail: View {
    let profile: CachedUser

    var body: some View {
        LabeledContent("Name", value: profile.displayName)
        if let pronoun = profile.pronoun {
            LabeledContent("Pronoun", value: pronoun)
        }
        if let dect = profile.dect {
            PhoneNumberRow(label: "DECT", value: dect)
        }
        if let mobile = profile.mobile {
            PhoneNumberRow(label: "Mobile", value: mobile)
        }
        if let tshirtSize = profile.tshirtSize {
            LabeledContent("T-Shirt Size", value: tshirtSize)
        }
        if let arrived = profile.arrived {
            LabeledContent("Arrived", value: arrived ? "Yes" : "No")
        }
    }
}

private struct AngelTypeRow: View {
    let membership: CachedAngelTypeMembership
    var instanceName: String?

    var body: some View {
        HStack {
            Text(membership.angelTypeName ?? "Unknown")
            Spacer()
            if membership.supporter {
                Text("Supporter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !membership.confirmed {
                Text("Unconfirmed")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let instanceName {
                InstanceBadge(name: instanceName)
            }
        }
    }
}

private struct WorklogRow: View {
    let worklog: CachedWorklog
    var instanceName: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(worklog.workLogDescription)
                Text("\(String(format: "%.1f", worklog.hours))h · \(worklog.workedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let instanceName {
                InstanceBadge(name: instanceName)
            }
        }
    }
}
