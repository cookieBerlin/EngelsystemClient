import SwiftUI
import SwiftData
import EngelsystemClientKit

struct ProfileView: View {
    let instance: Instance

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProfileViewModel()
    @Query private var users: [CachedUser]
    @Query private var worklogs: [CachedWorklog]

    init(instance: Instance) {
        self.instance = instance
        let instanceID = instance.id
        _users = Query(filter: #Predicate<CachedUser> { $0.instanceID == instanceID })
        _worklogs = Query(
            filter: #Predicate<CachedWorklog> { $0.instanceID == instanceID },
            sort: \CachedWorklog.workedAt,
            order: .reverse
        )
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
