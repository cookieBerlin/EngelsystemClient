import SwiftUI
import SwiftData
import EngelsystemClientKit

/// One shift in full (ADR 0015, backlog S-02 – S-04): type and description, the team by angel
/// type with the own entry highlighted, and — on the own shift — until when a sign-out is possible
/// with a button that opens the shift in the browser. The app never signs out by itself. Every text
/// and decision comes from `ShiftDetail` (tested); this file is layout.
struct ShiftDetailView: View {
    let shift: CachedShift
    let location: CachedLocation?
    let instance: Instance?
    let ownUserID: Int?

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ShiftDetailViewModel()
    @State private var expandedTeams: Set<String> = []

    private var detail: ShiftDetail { ShiftDetail(shift: shift, ownUserID: ownUserID) }

    var body: some View {
        let detail = detail
        List {
            headerSection(detail)
            if detail.shiftTypeName != nil || detail.description != nil {
                aboutSection(detail)
            }
            if detail.talkURL != nil || !detail.tags.isEmpty || detail.signupAvailableFrom != nil {
                extrasSection(detail)
            }
            if !detail.team.isEmpty {
                ForEach(detail.team, id: \.angelTypeName) { group in
                    teamSection(group)
                }
            }
            if let signOut = detail.signOut {
                signOutSection(signOut)
            }
        }
        .navigationTitle(detail.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if viewModel.isLoading {
                ToolbarItem { ProgressView() }
            }
        }
        .refreshable {
            guard let instance else { return }
            await viewModel.refresh(shift: shift, instance: instance, in: modelContext)
        }
        .safeAreaInset(edge: .top) {
            if let message = viewModel.errorMessage {
                ErrorBanner(message: message)
            }
        }
    }

    private func headerSection(_ detail: ShiftDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.title).font(.title3.bold())
                Label(shift.formattedTimeRange() + " · " + detail.durationText, systemImage: "clock")
                    .foregroundStyle(.secondary)
                if detail.isNightShift {
                    Label("Night shift", systemImage: "moon.stars")
                        .foregroundStyle(.secondary)
                }
                // COMPAT(#1711): without readable locations the name stays plain text.
                if let location, ServerCapabilities.shared.isAvailable(.locationsList, for: shift.instanceID) {
                    NavigationLink {
                        LocationDetailView(location: location, instance: instance)
                    } label: {
                        Label(location.name, systemImage: "mappin.and.ellipse")
                    }
                } else if let name = detail.locationName {
                    Label(name, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func aboutSection(_ detail: ShiftDetail) -> some View {
        Section("About") {
            if let name = detail.shiftTypeName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    if let text = detail.shiftTypeDescription {
                        Text(text).foregroundStyle(.secondary)
                    }
                }
            }
            if let text = detail.description {
                Text(text)
            }
        }
    }

    private func extrasSection(_ detail: ShiftDetail) -> some View {
        Section {
            if !detail.tags.isEmpty {
                Label(detail.tags.joined(separator: ", "), systemImage: "tag")
            }
            if let from = detail.signupAvailableFrom {
                Label("Sign-up opens \(from.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar.badge.clock")
            }
            if let talk = detail.talkURL {
                Button {
                    openURL(talk)
                } label: {
                    Label("Open talk page", systemImage: "safari")
                }
            }
        }
    }

    private func teamSection(_ group: ShiftDetail.TeamGroup) -> some View {
        let collapsed = group.members.count > ShiftDetail.collapsedMemberLimit && !expandedTeams.contains(group.angelTypeName)
        let shown = collapsed ? group.members.filter(\.isOwn) : group.members
        return Section {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, member in
                memberRow(member)
            }
            if collapsed {
                Button("Show all \(group.members.count)") { expandedTeams.insert(group.angelTypeName) }
            }
        } header: {
            HStack {
                Text(group.angelTypeName)
                Spacer()
                Text(group.occupancyText)
            }
        }
    }

    private func memberRow(_ member: ShiftDetail.Member) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(member.name)
                    .fontWeight(member.isOwn ? .bold : .regular)
                if member.isOwn {
                    Text("You").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if member.didNotShow {
                    Label("Did not show up", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if member.didNotShow, let markedBy = member.markedBy {
                Text("Marked by \(markedBy)").font(.caption).foregroundStyle(.secondary)
            }
            if member.didNotShow, let comment = member.comment {
                Text(comment).font(.caption).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(member.isOwn ? Color.accentColor.opacity(0.12) : nil)
    }

    private func signOutSection(_ signOut: ShiftDetail.SignOut) -> some View {
        Section("Sign out") {
            let time = signOut.deadline.formatted(date: .abbreviated, time: .shortened)
            if signOut.isOpen {
                Text(signOut.isAssumed ? "Usually until 3 hours before the start (\(time))" : "Until \(time)")
            } else {
                Text("The sign-out period has ended.").foregroundStyle(.secondary)
            }
            if signOut.isOpen, let url = signOut.browserURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Sign out in browser", systemImage: "safari")
                }
            }
        }
    }
}
