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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title)
                            .font(.system(.title2, design: .serif, weight: .semibold))
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
                    case .finish: await library.finish(item, api: api)
                    }
                    if let problem {
                        onProblem(problem)
                    }
                }
            }
            .frame(width: isWide ? nil : 290)
        }
    }
}

private struct NowCard: View {
    enum Action {
        case tickNext, page(Int), finish
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
            VStack(alignment: .leading, spacing: 10) {
                progress
                actions
            }
            .padding(14)
        }
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
        if item.kind == .book {
            HStack(alignment: .top, spacing: 14) {
                PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: .book)
                    .frame(width: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Color(.ink))
                        .lineLimit(3)
                    if let year = title.year {
                        Text(String(year)).font(.subheadline).foregroundStyle(Color(.muted))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding([.horizontal, .top], 14)
        } else {
            Color(.medallion)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: (title.backdropUrl ?? title.posterUrl).flatMap(URL.init(string:))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color(.accent).opacity(0.15)
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text(title.title)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(
                            colors: [.black.opacity(0.7), .clear],
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
                    Text("Next S\(next.season) · E\(next.number)")
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
            }
            if let done = item.done {
                ProgressView(value: done)
                    .tint(Color(.accent))
                    .accessibilityLabel("\(title.title) progress")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let next = item.next {
                Button { perform(.tickNext) } label: {
                    Label("Watched S\(next.season) · E\(next.number)", systemImage: "checkmark")
                        .frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.accent))
            } else if item.kind == .book {
                Button {
                    pageText = item.entry.bookProgress?.page.map(String.init) ?? ""
                    editingPage = true
                } label: {
                    Label("Update page", systemImage: "bookmark").frame(minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.accent))
            }
            if item.next == nil {
                Button { perform(.finish) } label: {
                    Text(item.kind == .book ? "Finished" : "Mark watched").frame(minHeight: 30)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(isPending)
        .sensoryFeedback(.success, trigger: item.label)
    }
}
