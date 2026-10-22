import AaruAPI
import SwiftUI

/// The Seasons view (DISC-002): one season as an object. The season's name heads the page
/// between the steps to the seasons either side (or a swipe across it); a segmented control
/// picks what the season lists; the grid is that season's titles, popular first, each addable
/// in place. A new season pushes in from the side it lies on; with Reduce Motion it fades.
struct SeasonBrowser: View {
    @Bindable var model: SeasonModel
    let compact: Bool
    let onAddToList: (CatalogHit) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The edge the next season comes in from.
    @State private var edge: Edge = .trailing

    private static let skeletonCount = 12

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                Picker("What to list", selection: $model.kind) {
                    ForEach(SeasonKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                content
                    .id(model.query)
                    .transition(seasonTransition)
                if model.hasMore {
                    Button(model.isLoading ? "Loading…" : "Show more") {
                        Task { await model.loadMore() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
                }
                Label("Rows from \(model.kind.provider)", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .task(id: model.query) { await model.load() }
        .refreshable { await model.reload() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            step(-1)
            VStack(spacing: 4) {
                Text(model.key.title)
                    .font(.aaruDisplay(.largeTitle))
                    .monospacedDigit()
                Text(model.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
            .frame(maxWidth: .infinity)
            .id(model.key)
            .transition(seasonTransition)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Swipe up or down for another season.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(1)
                case .decrement: move(-1)
                @unknown default: break
                }
            }
            step(1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height), abs(width) > 48 else { return }
                move(width < 0 ? 1 : -1)
            }
        )
        .clipped()
    }

    private func step(_ direction: Int) -> some View {
        let target = model.key.shifted(direction)
        return Button {
            move(direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!model.key.canShift(direction))
        .accessibilityLabel(direction < 0 ? "Previous season, \(target.title)" : "Next season, \(target.title)")
    }

    private func move(_ direction: Int) {
        guard model.key.canShift(direction) else { return }
        // The edge first, the season in the next update: the outgoing view must already carry
        // the new edge, or reversing direction pushes it out the wrong way.
        edge = direction > 0 ? .trailing : .leading
        let next = model.key.shifted(direction)
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.25)
        Task { @MainActor in
            withAnimation(animation) { model.key = next }
        }
    }

    private var seasonTransition: AnyTransition {
        reduceMotion ? .opacity : .push(from: edge)
    }

    // MARK: Grid

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: compact ? 104 : 140), spacing: 12, alignment: .top)]
    }

    @ViewBuilder private var content: some View {
        if let first = model.first {
            if first.unavailable {
                ContentUnavailableView {
                    // The vendor is named in the credit, not as the error's subject (UX-050).
                    Label("This season's list isn't answering", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Try \(model.key.title) again in a few minutes.")
                } actions: {
                    Button("Try again") { Task { await model.reload() } }
                        .buttonStyle(.bordered)
                }
            } else if model.items.isEmpty {
                ContentUnavailableView(
                    "Nothing listed for \(model.key.title) yet",
                    systemImage: "calendar",
                    description: Text("Try another season or kind.")
                )
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(model.items) { hit in
                        DiscoverCard(
                            hit: hit,
                            libraryItemID: model.libraryItemID(hit),
                            badge: DiscoverCard.releaseBadge(hit.releaseDate, row: "season"),
                            width: nil,
                            isAdding: model.adding.contains(hit.id)
                        ) { status in
                            Task { await model.add(hit, status: status) }
                        } onAddToList: {
                            onAddToList(hit)
                        }
                    }
                }
            }
        } else if model.firstFailed {
            ContentUnavailableView {
                Label("\(model.key.title) could not be loaded", systemImage: "exclamationmark.triangle")
            } actions: {
                Button("Try again") { Task { await model.reload() } }
                    .buttonStyle(.bordered)
            }
        } else {
            skeleton
        }
    }

    /// Placeholders at the real poster size, still: nothing loops while a season loads.
    private var skeleton: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(0 ..< Self.skeletonCount, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.surface))
                        .aspectRatio(2 / 3, contentMode: .fit)
                    Capsule().fill(Color(.surface)).frame(height: 12).padding(.trailing, 24)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading \(model.key.title)")
    }
}

// MARK: Previews

#Preview("Seasons") {
    NavigationStack {
        SeasonBrowser(
            model: SeasonModel(preview: .init(
                kind: .anime, season: .fall, year: 2026, from: "2026-10-01", until: "2026-12-31",
                title: "Fall 2026", items: [], page: 1, hasMore: false, total: 84, unavailable: false
            )),
            compact: true
        ) { _ in }
            .navigationTitle("Discover")
    }
}
