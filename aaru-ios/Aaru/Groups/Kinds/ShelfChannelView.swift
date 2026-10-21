import SwiftUI

/// A shared-list channel as a grid of posters, with who added each and the user's own status.
/// The kind is stored as `shelf`; the UI calls it a list (UX-041).
struct ShelfChannelView: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel
    @State private var model: ShelfModel
    @State private var picksTitle = false

    init(groups: GroupsModel, groupID: String, channel: GroupChannel) {
        self.groups = groups
        self.groupID = groupID
        self.channel = channel
        _model = State(initialValue: ShelfModel(api: groups.api, groupID: groupID, channelID: channel.id))
    }

    var body: some View {
        ScrollView {
            if model.hasLoaded, model.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing on this list yet", systemImage: ChannelKind.shelf.symbol)
                } description: {
                    Text("Anyone in the group can add a title.")
                } actions: {
                    Button("Add a title") { picksTitle = true }.buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            } else if let problem = model.loadProblem {
                LoadFailedView(title: "Couldn't load this list", message: problem) { await model.load() }
                    .padding(.top, 40)
            } else if !model.hasLoaded {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 170), spacing: 16)], spacing: 20) {
                    ForEach(model.items, id: \.title.id) { item in
                        ShelfCard(item: item, adding: model.adding.contains(item.title.id)) {
                            Task { await model.addToMyLibrary(item) }
                        }
                        .contextMenu {
                            if item.myStatus == nil {
                                Button("Add to my library", systemImage: "plus") {
                                    Task { await model.addToMyLibrary(item) }
                                }
                            }
                            Button("Remove from list", systemImage: "minus.circle", role: .destructive) {
                                Task { await model.remove(item) }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.paper))
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: model.problem) { model.problem = nil } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add a title", systemImage: "plus") { picksTitle = true }
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
        .task {
            guard let realtime = groups.realtime else { return }
            for await event in realtime.events() {
                await model.apply(event)
            }
        }
        .sheet(isPresented: $picksTitle) {
            TitlePickerSheet(api: groups.api, navigationTitle: "Add to #\(channel.name)") { hit in
                await model.add(hit.mediaRef)
            }
        }
    }
}

private struct ShelfCard: View {
    let item: ChannelItem
    let adding: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: item.title.posterURL, kind: item.title.mediaKind)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.title.title).font(.subheadline.weight(.medium)).lineLimit(3)
            if let addedBy = item.addedBy {
                Text("Added by \(addedBy.label)").font(.caption).foregroundStyle(Color(.muted)).lineLimit(2)
            }
            if let status = item.myStatus {
                Label(status.label(for: item.title.mediaKind), systemImage: "checkmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(.accent))
            } else if adding {
                ProgressView().controlSize(.small)
            } else {
                Button("Add to my library", systemImage: "plus", action: onAdd)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        #if os(iOS)
            .contentShape(.hoverEffect, .rect(cornerRadius: 8))
            .hoverEffect(.highlight)
        #endif
    }
}

/// A shared-list channel is its list, without a chat (the web does the same). It keeps the
/// channel header, so "Not end-to-end" shows here too (UX-076). The other kinds are chat with
/// their kind's panel above it.
struct ShelfScreen: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel
    let onShowMembers: () -> Void

    var body: some View {
        ShelfChannelView(groups: groups, groupID: groupID, channel: channel)
            .safeAreaInset(edge: .top, spacing: 0) {
                ChannelHeader(
                    topic: channel.topic,
                    disconnectedSince: groups.realtime?.state == .open ? nil : groups.realtime?.disconnectedSince,
                    agent: groups.details[groupID]?.agent ?? false
                )
            }
            .navigationTitle("#\(channel.name)")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Members", systemImage: "person.2", action: onShowMembers)
                }
            }
    }
}
