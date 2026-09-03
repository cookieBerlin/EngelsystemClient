import SwiftUI
import SwiftData
import EngelsystemClientKit

struct ProfileView: View {
    let instance: Instance
    var onUnauthorized: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProfileViewModel()
    @Query private var users: [CachedUser]
    @Query private var worklogs: [CachedWorklog]
    @Query private var angelTypeMemberships: [CachedAngelTypeMembership]

    init(instance: Instance, onUnauthorized: @escaping () -> Void = {}) {
        self.instance = instance
        self.onUnauthorized = onUnauthorized
        let instanceID = instance.id
        _users = Query(filter: #Predicate<CachedUser> { $0.instanceID == instanceID })
        _worklogs = Query(
            filter: #Predicate<CachedWorklog> { $0.instanceID == instanceID },
            sort: \CachedWorklog.workedAt,
            order: .reverse
        )
        _angelTypeMemberships = Query(filter: #Predicate<CachedAngelTypeMembership> { $0.instanceID == instanceID })
    }

    private var profile: CachedUser? { users.first }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    ErrorBanner(message: errorMessage)
                }
                .listRowInsets(EdgeInsets())
            }

            if let profile {
                Section("Profile") {
                    LabeledContent("Name", value: profile.displayName)
                    if let pronoun = profile.pronoun {
                        LabeledContent("Pronoun", value: pronoun)
                    }
                    if let tshirtSize = profile.tshirtSize {
                        LabeledContent("T-Shirt Size", value: tshirtSize)
                    }
                    if let arrived = profile.arrived {
                        LabeledContent("Arrived", value: arrived ? "Yes" : "No")
                    }
                }
            }

            Section("Angel Types") {
                if angelTypeMemberships.isEmpty {
                    Text("No angel types yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(CachedAngelTypeMembership.sortedByName(angelTypeMemberships)) { membership in
                        AngelTypeRow(membership: membership)
                    }
                }
            }

            Section("Worklogs") {
                if worklogs.isEmpty {
                    Text("No worklogs yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(worklogs) { worklog in
                        WorklogRow(worklog: worklog)
                    }
                    LabeledContent(
                        "Total",
                        value: String(format: "%.1fh", CachedWorklog.totalHours(worklogs))
                    )
                    .fontWeight(.semibold)
                }
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            if viewModel.isLoading {
                ToolbarItem { ProgressView() }
            }
        }
        .refreshable { await viewModel.refresh(instance: instance, in: modelContext) }
        .task { await viewModel.refresh(instance: instance, in: modelContext) }
        .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
            if isUnauthorized { onUnauthorized() }
        }
    }
}

private struct AngelTypeRow: View {
    let membership: CachedAngelTypeMembership

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
        }
    }
}

private struct WorklogRow: View {
    let worklog: CachedWorklog

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(worklog.workLogDescription)
            Text("\(String(format: "%.1f", worklog.hours))h · \(worklog.workedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
