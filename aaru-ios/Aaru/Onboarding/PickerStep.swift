import SwiftUI

/// One kind's picker (DESIGN.md §0a, 2): a search field, then rows of well-known titles. A tap
/// on a poster marks it Watched / Read / Listened and further taps cycle the statuses; a hold
/// offers the menu. Continue saves the screen's picks as one action, with no minimum.
struct PickerStep: View {
    @Bindable var model: OnboardingModel
    let kind: OnboardingKind
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    @State private var search: TitlePickerModel
    @State private var query = ""
    @Environment(\.dynamicTypeSize) private var dynamicType
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(
        model: OnboardingModel, kind: OnboardingKind,
        onBack: @escaping () -> Void, onSkip: @escaping () -> Void, onContinue: @escaping () -> Void
    ) {
        self.model = model
        self.kind = kind
        self.onBack = onBack
        self.onSkip = onSkip
        self.onContinue = onContinue
        _search = State(initialValue: TitlePickerModel(api: model.api))
    }

    private var compact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        OnboardingPage(title: kind.pickHeading, onBack: onBack, onSkip: onSkip, isBusy: model.isBusy) {
            searchField
                .padding(.horizontal, 20)
            if isSearching {
                results
            } else {
                rows
            }
        } footer: {
            OnboardingProblem(message: model.problem) { model.problem = nil }
            OnboardingPill(
                label: model.saveFailed ? "Try again" : kind.continueLabel(count: model.picks(of: kind).count),
                isBusy: model.isBusy,
                action: onContinue
            )
        }
        .task { await model.loadRows(kind) }
        .task(id: query) { await search.search(query, kind: kind.mediaKind) }
    }

    private var searchField: some View {
        HStack(spacing: AaruSpace.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(.muted))
                .accessibilityHidden(true)
            TextField(kind.mediaKind.searchPrompt, text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color(.muted))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, AaruSpace.medium)
        .frame(minHeight: 44)
        .field()
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        switch model.rows[kind] {
        case nil, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, AaruSpace.block)
        case let .failed(message):
            // A failed first load is an error, not an empty catalog (UX-063).
            LoadFailedView(title: "Couldn't load titles", message: "\(message) Search still works.") {
                await model.loadRows(kind, force: true)
            }
            .frame(minHeight: 320)
        case let .loaded(rows):
            // No rows for this kind: the search alone.
            LazyVStack(alignment: .leading, spacing: AaruSpace.section) {
                ForEach(rows, id: \.id) { row in
                    HomeRow(title: row.title, note: row.note) {
                        ForEach(row.items) { hit in
                            poster(hit, width: HomeCardSize.poster.width(compact: compact, dynamicType: dynamicType))
                        }
                    }
                }
            }
        }
    }

    // MARK: Search

    @ViewBuilder private var results: some View {
        if let problem = search.problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(Color(.danger))
                .padding(.horizontal, 20)
        } else if search.hits.isEmpty, search.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, AaruSpace.block)
        } else if search.hits.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compact ? 104 : 140), spacing: 12, alignment: .top)],
                spacing: 20
            ) {
                ForEach(search.hits) { hit in
                    poster(hit, width: nil)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func poster(_ hit: CatalogHit, width: CGFloat?) -> some View {
        OnboardingPoster(
            hit: hit,
            kind: kind.mediaKind,
            state: state(of: hit),
            width: width,
            onTap: { model.cycle(hit, kind: kind) },
            onSet: { model.set(hit, kind: kind, status: $0) }
        )
    }

    private func state(of hit: CatalogHit) -> OnboardingPosterState {
        if let pick = model.pick(for: hit) {
            return pick.saved == nil ? .picked(pick.status) : .saved(pick.status)
        }
        return model.libraryItemID(hit) == nil ? .open : .inLibrary
    }
}
