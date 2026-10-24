import AaruAPI
import SwiftUI

/// "Now" at the top of Library (APP-017): what the user is in the middle of, as big cards with a
/// progress bar and the one next step — tick the next episode, move a book's page, finish.
struct NowSection: View {
    let library: LibraryModel
    let api: Client?
    let kind: MediaKind?
    /// Shows a failed write in the screen's banner.
    var onProblem: (String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    var body: some View {
        let groups = library.nowGroups(kind: kind)
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: AaruSpace.medium) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title)
                            .font(.aaruDisplay(.title2, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(group.items.count)").foregroundStyle(Color(.muted))
                    }
                    .padding(.horizontal, 16)
                    if isWide {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                            cards(group)
                        }
                        .padding(.horizontal, 16)
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) { cards(group) }
                                .scrollTargetLayout()
                                .padding(.horizontal, 16)
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned)
                    }
                }
            }
        }
        .padding(.top, groups.isEmpty ? 0 : 8)
    }

    private func cards(_ group: NowGroup) -> some View {
        ForEach(group.items) { item in
            NowCard(item: item, isPending: library.nowPending.contains(item.id)) { action in
                Task {
                    let problem: String? = switch action {
                    case .tickNext: await library.tickNext(item, api: api)
                    case let .page(page): await library.setPage(page, of: item, api: api)
                    case let .chapter(chapter): await library.setChapter(chapter, of: item, api: api)
                    case .finish: await library.finish(item, api: api)
                    }
                    if let problem {
                        onProblem(problem)
                    }
                }
            }
            .modifier(NowCardWidth(isScrolling: !isWide, isLarge: typeSize.isAccessibilitySize))
        }
    }
}

/// On a phone the cards scroll sideways at 290 pt; at accessibility sizes each takes most of the
/// width so its text wraps instead of clipping. The wide grid sizes them itself.
private struct NowCardWidth: ViewModifier {
    let isScrolling: Bool
    let isLarge: Bool

    func body(content: Content) -> some View {
        if isScrolling {
            content.containerRelativeFrame(.horizontal) { width, _ in
                isLarge ? width - 48 : min(290, width - 48)
            }
        } else {
            content
        }
    }
}

private struct NowCard: View {
    enum Action {
        case tickNext, page(Int), chapter(Int), finish
    }

    let item: NowItem
    let isPending: Bool
    let perform: (Action) -> Void

    @State private var editingPage = false
    @State private var pageText = ""

    private var title: Components.Schemas.TitleSummary {
        item.entry.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: item.entry.id) { art }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title.title)
                .accessibilityHint("Opens the title")
            VStack(alignment: .leading, spacing: AaruSpace.medium) {
                progress
                actions
            }
            .padding(AaruSpace.large)
        }
        .clipShape(.rect(cornerRadius: AaruRadius.card, style: .continuous))
        .card()
        .alert("Page", isPresented: $editingPage) {
            TextField("Page", text: $pageText)
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
            Button("Save") {
                if let page = Int(pageText), page >= 0 {
                    perform(.page(page))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Which page of \(title.title) are you on?")
        }
    }

    @ViewBuilder private var art: some View {
        if item.kind == .book || item.kind == .manga || item.kind == .music {
            HStack(alignment: .top, spacing: AaruSpace.medium) {
                PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: item.kind)
                    .frame(width: 76)
                    .clipShape(RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.title)
                        .font(.aaruDisplay(.title3, weight: .semibold))
                        .foregroundStyle(Color(.ink))
                        .lineLimit(3)
                    if let line = title.byline ?? title.year.map(String.init) {
                        Text(line).font(.subheadline).foregroundStyle(Color(.muted)).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding([.horizontal, .top], AaruSpace.large)
        } else {
            Color(.surface)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: (title.backdropUrl ?? title.posterUrl).flatMap(URL.init(string:))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color(.accent).opacity(AaruAlpha.wash)
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text(title.title)
                        .font(.aaruDisplay(.title3, weight: .semibold))
                        .foregroundStyle(Color(.onScrim))
                        .lineLimit(2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(
                            colors: [Color(.scrim), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        ))
                }
                .clipped()
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label).font(.subheadline.weight(.medium))
                Spacer()
                if let next = item.next {
                    Text("Next " + EpisodeCode.short(season: next.season, number: next.number))
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
            }
            if let done = item.done {
                ProgressView(value: done)
                    .accessibilityLabel("\(title.title) progress")
            }
        }
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var actions: some View {
        // Side by side, or stacked at accessibility sizes so neither label is cut.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if let next = item.next {
                Button { perform(.tickNext) } label: {
                    Label(
                        "Mark \(EpisodeCode.short(season: next.season, number: next.number)) watched",
                        systemImage: "checkmark"
                    )
                    .frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
            } else if item.kind == .book {
                Button {
                    pageText = item.entry.bookProgress?.page.map(String.init) ?? ""
                    editingPage = true
                } label: {
                    Label("Update page", systemImage: "bookmark").frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
            } else if item.kind == .manga {
                let chapter = (item.entry.mangaProgress?.chapter ?? 0) + 1
                Button { perform(.chapter(chapter)) } label: {
                    Label("Read ch. \(chapter)", systemImage: "checkmark").frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
            }
            if item.next == nil {
                Button { perform(.finish) } label: {
                    Text(
                        item.kind == .book || item.kind == .manga
                            ? "Mark read" : item.kind == .music ? "Mark listened" : "Mark watched"
                    )
                    .frame(minHeight: 30)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(isPending)
        .sensoryFeedback(.success, trigger: item.label)
    }
}
