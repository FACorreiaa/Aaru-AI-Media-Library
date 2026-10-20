import AaruAPI
import SwiftUI

extension GroupsModel {
    /// Groups where the user can add channels.
    var managedGroups: [GroupSummary] {
        groups.filter(\.role.manages)
    }

    /// Opens the group's channel about this title, creating it first when there is none.
    func discuss(_ title: TitleSummary, in groupID: String) async -> Bool {
        if details[groupID] == nil {
            await loadDetail(groupID)
        }
        if let existing = details[groupID]?.channels.first(where: { $0.kind == .title && $0.title?.id == title.id }) {
            openRequest = ChannelOpenRequest(group: groupID, channel: existing.id)
            return true
        }
        guard let created = await createChannel(in: groupID, kind: .title, name: "", topic: "", title: title.mediaRef)
        else { return false }
        openRequest = ChannelOpenRequest(group: groupID, channel: created.id)
        return true
    }
}

/// "Discuss in a group…" from a title: pick one of the groups the user runs, and Aaru opens its
/// channel about the title, making one if it has none.
struct DiscussInGroupSheet: View {
    let groups: GroupsModel
    let title: TitleSummary
    @Environment(\.dismiss) private var dismiss
    @State private var working: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups.managedGroups, id: \.id) { group in
                        Button {
                            open(group)
                        } label: {
                            HStack(spacing: 12) {
                                Monogram(text: group.monogram, size: 32)
                                Text(group.name).lineLimit(1)
                                Spacer(minLength: 8)
                                if working == group.id {
                                    ProgressView()
                                } else if hasChannel(in: group.id) {
                                    Text("Open").foregroundStyle(Color(.muted))
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(working != nil)
                    }
                } footer: {
                    Text("Messages there hide spoilers from anyone who hasn't caught up.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .navigationTitle("Discuss \(title.title)")
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: groups.problem) { groups.problem = nil } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await groups.loadAllDetails() }
        }
    }

    private func hasChannel(in groupID: String) -> Bool {
        groups.details[groupID]?.channels.contains { $0.kind == .title && $0.title?.id == title.id } ?? false
    }

    private func open(_ group: GroupSummary) {
        Task {
            working = group.id
            defer { working = nil }
            if await groups.discuss(title, in: group.id) {
                dismiss()
            }
        }
    }
}
