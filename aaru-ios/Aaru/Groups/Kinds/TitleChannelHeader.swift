import SwiftUI

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

/// GRP-007: the title card above a title channel's chat, with who shares their progress here.
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
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
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
                    SharedProgressRow(members: progress.members, kind: progress.title.mediaKind)
                    shareToggle
                }
            } else if let problem = model.loadProblem {
                PanelLoadFailed(message: problem) { await model.load() }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.surface).opacity(AaruAlpha.half))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(.line)).frame(height: 0.5) }
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .popover(isPresented: $explainsSharing) {
                    Text("""
                    Off by default. When on, members of this group see how far you are in the titles its \
                    channels are about. Spoilers are hidden from you either way.
                    """)
                    .font(.callout)
                    .padding()
                    .frame(idealWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .presentationCompactAdaptation(.popover)
                }
        }
    }
}

/// Members who share their progress here, each in the title's own words.
private struct SharedProgressRow: View {
    let members: [MemberProgress]
    let kind: MediaKind

    var body: some View {
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
                            Text(member.summary(for: kind)).font(.caption).foregroundStyle(Color(.muted))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.paper), in: .capsule)
                        .accessibilityElement(children: .combine)
                    }
                }
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
                .clipShape(RoundedRectangle(cornerRadius: AaruRadius.thumb, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([title.year.map(String.init), mine.map { "You: \($0.summary(for: title.mediaKind))" }]
                    .compactMap(\.self)
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A panel above a channel's chat (title card, watch party) that could not load: the reason
/// and Try again, in the panel's own small space. Full screens use `LoadFailedView`.
struct PanelLoadFailed: View {
    let message: String
    let retry: () async -> Void
    @State private var retrying = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(message, systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(Color(.muted))
            Spacer(minLength: 8)
            Button("Try again") {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(retrying)
        }
    }
}
