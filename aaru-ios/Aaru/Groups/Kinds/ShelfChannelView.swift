import AaruAPI
import Observation
import SwiftUI

typealias ChannelItem = Components.Schemas.ChannelItem

/// GRP-008: a shelf channel's titles. Any member adds or removes one; "Add to my library" is the
/// same journaled add as anywhere else, for this user only.
@MainActor
@Observable
final class ShelfModel {
    private(set) var items: [ChannelItem] = []
    private(set) var hasLoaded = false
    private(set) var adding: Set<String> = []
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
        guard let api, case let .ok(response) = try? await api.listChannelItems(
            path: .init(groupId: groupID, channelId: channelID)
        ), let list = try? response.body.json else { return }
        items = list.items
        hasLoaded = true
    }

    func add(_ title: Components.Schemas.MediaRef) async -> Bool {
        guard let api else { return false }
        problem = nil
        do {
            switch try await api.addChannelItem(
                path: .init(groupId: groupID, channelId: channelID), body: .json(.init(title: title))
            ) {
            case let .ok(response):
                items = try response.body.json.items
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That title was not added."
            }
        } catch {
            problem = "That title was not added. Aaru could not reach the server."
        }
        return false
    }

    func remove(_ item: ChannelItem) async {
        guard let api else { return }
        problem = nil
        do {
            switch try await api.removeChannelItem(
                path: .init(groupId: groupID, channelId: channelID, titleId: item.title.id)
            ) {
            case .noContent: items.removeAll { $0.title.id == item.title.id }
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That title was not removed."
            }
        } catch {
            problem = "That title was not removed. Aaru could not reach the server."
        }
    }

    /// The user's own wishlist add; the shelf then shows their status.
    func addToMyLibrary(_ item: ChannelItem) async {
        guard let api, !adding.contains(item.title.id) else { return }
        adding.insert(item.title.id)
        defer { adding.remove(item.title.id) }
        problem = nil
        do {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: item.title.mediaRef, status: .wishlist))) {
            case .ok: await load()
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "\(item.title.title) was not added."
            }
        } catch {
            problem = "\(item.title.title) was not added. Aaru could not reach the server."
        }
    }

    func apply(_ event: RealtimeEvent) async {
        if event._type == .ready || (event._type == .shelf_updated && event.channelId == channelID) {
            await load()
        }
    }
}

/// The shelf as a grid of posters, with who added each and the user's own status.
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
                    Label("Nothing on this shelf yet", systemImage: "books.vertical")
                } description: {
                    Text("Anyone in the group can add a title.")
                } actions: {
                    Button("Add a title") { picksTitle = true }.buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 170), spacing: 16)], spacing: 20) {
                    ForEach(model.items, id: \.title.id) { item in
                        ShelfCard(item: item, adding: model.adding.contains(item.title.id)) {
                            Task { await model.addToMyLibrary(item) }
                        }
                        .contextMenu {
                            Button("Remove from shelf", systemImage: "minus.circle", role: .destructive) {
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
            Text(item.title.title).font(.subheadline.weight(.medium)).lineLimit(2)
            if let addedBy = item.addedBy {
                Text("Added by \(addedBy.label)").font(.caption).foregroundStyle(Color(.muted)).lineLimit(1)
            }
            if let status = item.myStatus {
                Label(status.label, systemImage: "checkmark")
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
    }
}

/// A shelf channel is its shelf: a list the group edits together, without a chat (the web does
/// the same). The other kinds are chat with their kind's panel above it.
struct ShelfScreen: View {
    let groups: GroupsModel
    let groupID: String
    let channel: GroupChannel
    let onShowMembers: () -> Void

    var body: some View {
        ShelfChannelView(groups: groups, groupID: groupID, channel: channel)
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
