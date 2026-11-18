import AaruAPI
import SwiftUI

/// GRAPH-007: one World, whole: its name, how far the user is, the map, a share card of their
/// path, and "Add the rest". Catalog data and the user's own marks; nothing here is a
/// recommendation. It expects a navigation stack that opens library items and catalog pages.
struct WorldScreen: View {
    @State private var model: WorldModel
    @State private var planning = false
    /// Called once "Add the rest" has a plan to review, so a sheet can close first.
    var onPlanned: (() -> Void)?

    init(api: Client?, titleID: String, world: StoryWorld? = nil, onPlanned: (() -> Void)? = nil) {
        _model = State(initialValue: WorldModel(api: api, titleID: titleID, world: world))
        self.onPlanned = onPlanned
    }

    var body: some View {
        content
            .navigationTitle(model.world?.name ?? String(localized: "World"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .background(Color(.paper).ignoresSafeArea())
            .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if let world = model.world, model.isReady {
            VStack(alignment: .leading, spacing: 0) {
                header(world)
                    .padding(.horizontal, AaruSpace.large)
                    .padding(.top, AaruSpace.medium)
                WorldMap(world: world)
                    .padding(.top, AaruSpace.small)
                footer(world)
                    .padding(AaruSpace.large)
            }
        } else if model.isBuilding || (model.world == nil && !model.failed) {
            VStack(spacing: AaruSpace.medium) {
                ProgressView()
                Text("Mapping this world…")
                    .font(.callout)
                    .foregroundStyle(Color(.muted))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.failed {
            ContentUnavailableView {
                Label("This world could not be loaded", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        } else {
            ContentUnavailableView(
                "No world here",
                systemImage: "circle.dotted",
                description: Text("This title is not part of a larger story the catalog knows.")
            )
        }
    }

    private func header(_ world: StoryWorld) -> some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            Text(world.name ?? "")
                .font(.aaruDisplay(.title))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: AaruSpace.small) {
                Text(WorldWords.count(finished: world.finished, total: world.total))
                    .font(.headline)
                    .monospacedDigit()
                Text(WorldWords.kinds(world.kinds))
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
            .accessibilityElement(children: .combine)
            WorldProgressBar(finished: world.finished, total: world.total)
            if world.truncated {
                note("This universe is larger than one map holds. It is shown from its first title.")
            }
            if world.partial {
                note("Some titles are still being found.")
            }
            if let problem = model.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Color(.danger))
            }
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color(.muted))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footer(_ world: StoryWorld) -> some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            WorldLegend()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AaruSpace.medium) { actions(world) }
                VStack(alignment: .leading, spacing: AaruSpace.small) { actions(world) }
            }
            Text("Relations from AniList, TMDB and Wikidata.")
                .font(.caption)
                .foregroundStyle(Color(.muted))
        }
    }

    @ViewBuilder private func actions(_ world: StoryWorld) -> some View {
        WorldShareButton(world: world)
        if world.missing > 0 {
            Button {
                Task { await addRest() }
            } label: {
                Label("Add the rest (\(world.missing))", systemImage: "text.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(planning)
            .accessibilityHint("Opens a list to review before anything is added")
        }
    }

    /// The missing titles become a capture to review, the way "Add the chain" does it: nothing is
    /// added until the user approves the plan.
    private func addRest() async {
        planning = true
        defer { planning = false }
        guard let id = await model.planRest() else { return }
        onPlanned?()
        try? await Task.sleep(for: .milliseconds(400))
        PushInbox.shared.importID = id
    }
}

/// How far the user is through a World, as a bar.
struct WorldProgressBar: View {
    let finished: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.line))
                Capsule().fill(Color(.accent))
                    .frame(width: proxy.size.width * WorldWords.share(finished: finished, total: total))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A World in a sheet, opened from a title's page. A title on the map opens inside the sheet.
struct WorldSheet: View {
    let api: Client?
    let titleID: String
    let library: LibraryModel
    let lists: ListsModel
    var world: StoryWorld?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WorldScreen(api: api, titleID: titleID, world: world) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .catalogDestination(api: api, library: library, lists: lists)
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
    }
}

/// The title room's World section (`WorldStrip`): the World this title is part of and how far the
/// user is, opening the map. Absent until the World is built, and for a title that has none.
struct WorldStrip: View {
    let api: Client?
    let titleID: String
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: WorldModel
    @State private var showsMap = false

    private static func spokenCount(_ world: StoryWorld) -> String {
        WorldWords.count(finished: world.finished, total: world.total)
    }

    init(api: Client?, titleID: String, library: LibraryModel, lists: ListsModel, world: StoryWorld? = nil) {
        self.api = api
        self.titleID = titleID
        self.library = library
        self.lists = lists
        _model = State(initialValue: WorldModel(api: api, titleID: titleID, world: world))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let world = model.world, model.isReady {
                Button {
                    showsMap = true
                } label: {
                    VStack(alignment: .leading, spacing: AaruSpace.small) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("World").eyebrow()
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.muted))
                        }
                        Text(world.name ?? "")
                            .font(.aaruDisplay(.title3))
                            .foregroundStyle(Color(.ink))
                            .multilineTextAlignment(.leading)
                        HStack(alignment: .firstTextBaseline, spacing: AaruSpace.small) {
                            Text(WorldWords.count(finished: world.finished, total: world.total))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color(.ink))
                            Text(WorldWords.kinds(world.kinds))
                                .font(.subheadline)
                                .foregroundStyle(Color(.muted))
                                .lineLimit(1)
                        }
                        WorldProgressBar(finished: world.finished, total: world.total)
                    }
                    .panel()
                    .edgeLit()
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text("World: \(world.name ?? ""), \(Self.spokenCount(world)) finished")
                )
                .accessibilityHint("Opens the map")
                .accessibilityAddTraits(.isButton)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: titleID) { await model.load() }
        .sheet(isPresented: $showsMap) {
            WorldSheet(api: api, titleID: titleID, library: library, lists: lists, world: model.world)
        }
        // The map may have changed a title's status: read the count again once it closes.
        .onChange(of: showsMap) { _, open in
            if !open {
                Task { await model.load() }
            }
        }
    }
}
