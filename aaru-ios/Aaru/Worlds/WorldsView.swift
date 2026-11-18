import AaruAPI
import SwiftUI

/// GRAPH-007: the Worlds page. Every World the user has a title in, those with something left
/// first and the furthest along leading, as the server orders them. A row opens its map.
struct WorldsView: View {
    let api: Client?
    @State private var model: WorldsModel

    init(api: Client?, worlds: [WorldSummary]? = nil) {
        self.api = api
        _model = State(initialValue: WorldsModel(api: api, worlds: worlds))
    }

    var body: some View {
        content
            .navigationTitle("Worlds")
            .background(Color(.paper).ignoresSafeArea())
            .navigationDestination(for: WorldRoute.self) { route in
                WorldScreen(api: api, titleID: route.titleID)
            }
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if let worlds = model.worlds, !worlds.isEmpty {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: AaruSpace.medium)],
                    spacing: AaruSpace.medium
                ) {
                    ForEach(worlds, id: \.id) { world in
                        NavigationLink(value: WorldRoute(titleID: world.titleId)) { WorldRow(world: world) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(AaruSpace.large)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        } else if model.worlds != nil {
            ContentUnavailableView(
                "No worlds yet",
                systemImage: "circle.dotted",
                description: Text(
                    """
                    A world appears when a title in your library is part of a larger story: \
                    a sequel, an adaptation, a spin-off.
                    """
                )
            )
        } else if model.failed {
            ContentUnavailableView {
                Label("Your worlds could not be loaded", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One World in the list: a poster, its name, how far the user is, and what comes next.
struct WorldRow: View {
    let world: WorldSummary

    private var done: Bool {
        world.finished >= world.total
    }

    var body: some View {
        HStack(alignment: .top, spacing: AaruSpace.medium) {
            PosterView(url: world.posterUrl.flatMap(URL.init(string:)), kind: world.kinds.first?.kind ?? .film)
                .clipShape(.rect(cornerRadius: AaruRadius.thumb, style: .continuous))
                .frame(width: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                Text(world.name)
                    .font(.aaruDisplay(.headline))
                    .foregroundStyle(Color(.ink))
                    .lineLimit(2)
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
                    .padding(.vertical, 2)
                if done {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                } else if let next = world.startHere?.title {
                    Text("Next: \(next)")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panel()
        .accessibilityElement(children: .combine)
    }
}
