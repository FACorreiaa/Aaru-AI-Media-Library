import AaruAPI
import Observation
import SwiftUI

typealias ChannelProgress = Components.Schemas.ChannelProgress
typealias MemberProgress = Components.Schemas.MemberProgress

/// What sits under a channel's header for its kind: the title card, the watch party, or nothing.
struct ChannelKindPanel: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel

    var body: some View {
        switch channel.kind {
        case .title:
            TitleChannelHeader(groups: groups, groupID: groupID, channelID: channel.id)
        case .watch:
            WatchPanel(groups: groups, groupID: groupID, channelID: channel.id)
        case .text, .shelf:
            EmptyView()
        }
    }
}

/// GRP-007: a title channel's title, the viewer's progress, the progress of members who share
/// theirs in this group, and the viewer's own share switch (off until they turn it on).
@MainActor
@Observable
final class TitleChannelModel {
    private(set) var progress: ChannelProgress?
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored let groupID: String
    @ObservationIgnored let channelID: String

    init(api: Client?, groupID: String, channelID: String) {
        self.api = api
        self.groupID = groupID
        self.channelID = channelID
    }

    func load() async {
        guard let api, case let .ok(response) = try? await api.getChannelProgress(
            path: .init(groupId: groupID, channelId: channelID)
        ), let body = try? response.body.json else { return }
        progress = body
    }
}

struct TitleChannelHeader: View {
    let groups: GroupsModel
    let groupID: String
    @State private var model: TitleChannelModel
    @State private var expanded = true
    @State private var explainsSharing = false

    init(groups: GroupsModel, groupID: String, channelID: String) {
        self.groups = groups
        self.groupID = groupID
        _model = State(initialValue: TitleChannelModel(api: groups.api, groupID: groupID, channelID: channelID))
    }

    private var sharing: Bool {
        groups.details[groupID]?.group.shareProgress ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress = model.progress {
                Button {
                    expanded.toggle()
                } label: {
                    TitleCardRow(title: progress.title, mine: progress.mine)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Hides who shares their progress" : "Shows who shares their progress")
                if expanded {
                    sharedProgress(progress.members)
                    shareToggle
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.surface).opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .task { await model.load() }
        .task {
            guard let realtime = groups.realtime else { return }
            for await event in realtime.events() {
                // Someone switched sharing on or off, or the socket came back.
                if event._type == .ready || (event._type == .group_updated && event.groupId == groupID) {
                    await model.load()
                }
            }
        }
    }

    @ViewBuilder
    private func sharedProgress(_ members: [MemberProgress]) -> some View {
        if members.isEmpty {
            Text("Nobody here shares their progress yet.")
                .font(.caption)
                .foregroundStyle(Color(.muted))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(members, id: \.user.userId) { member in
                        HStack(spacing: 6) {
                            Monogram(text: member.user.monogram, size: 22)
                            Text(member.user.label).font(.caption.weight(.medium)).lineLimit(1)
                            Text(member.summary).font(.caption).foregroundStyle(Color(.muted))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.paper), in: .capsule)
                    }
                }
            }
        }
    }

    private var shareToggle: some View {
        HStack(spacing: 6) {
            Toggle("Share my progress in this group", isOn: Binding(get: { sharing }, set: { share in
                Task {
                    await groups.setShareProgress(groupID, share: share)
                    await model.load()
                }
            }))
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.mini)
            Button("About sharing", systemImage: "info.circle") { explainsSharing = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
                .popover(isPresented: $explainsSharing) {
                    Text("""
                    Off by default. When on, members of this group see how far you are in the titles its \
                    channels are about. Spoilers are hidden from you either way.
                    """)
                    .font(.callout)
                    .padding()
                    .frame(idealWidth: 300)
                    .presentationCompactAdaptation(.popover)
                }
        }
    }
}

/// TitleCard: poster, title and year, and the viewer's own status and furthest episode.
struct TitleCardRow: View {
    let title: TitleSummary
    let mine: MemberProgress?

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: title.posterURL, kind: title.mediaKind)
                .frame(width: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text([title.year.map(String.init), mine.map { "You: \($0.summary)" }].compactMap(\.self)
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension MemberProgress {
    /// "S1E3", "Finished", "Not started".
    var summary: String {
        if status == .finished {
            return "Finished"
        }
        if let season, let episode {
            return "S\(season)E\(episode)"
        }
        return status?.label ?? "Not started"
    }
}

extension GroupsModel {
    /// Shows or hides the user's progress in this group's title channels.
    func setShareProgress(_ groupID: String, share: Bool) async {
        guard let api else { return }
        await run("That setting was not saved.") {
            switch try await api.updateMyMembership(
                path: .init(groupId: groupID), body: .json(.init(shareProgress: share))
            ) {
            case .ok: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }
}
