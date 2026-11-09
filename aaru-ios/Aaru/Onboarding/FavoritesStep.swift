import SwiftUI

/// Your favorites (DESIGN.md §0a, 3): the titles saved as Watched / Read / Listened, by kind. A
/// tap stars one, up to ten a kind, in tap order (FAV-001); they join the end of any favorites
/// the account has.
struct FavoritesStep: View {
    let model: OnboardingModel
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    @State private var favorites: FavoritesModel
    /// Starred picks per kind, by pick id, in tap order.
    @State private var starred: [OnboardingKind: [String]] = [:]
    @State private var isSaving = false
    @State private var saveFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(
        model: OnboardingModel,
        onBack: @escaping () -> Void, onSkip: @escaping () -> Void, onContinue: @escaping () -> Void
    ) {
        self.model = model
        self.onBack = onBack
        self.onSkip = onSkip
        self.onContinue = onContinue
        _favorites = State(initialValue: FavoritesModel(api: model.api))
    }

    private var compact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    /// The finished, saved picks of each kind, in Library's kind order.
    private var groups: [(kind: OnboardingKind, picks: [OnboardingPick])] {
        OnboardingKind.allCases.compactMap { kind in
            let picks = model.livePicks.filter { $0.kind == kind && $0.status == .finished && $0.saved != nil }
            return picks.isEmpty ? nil : (kind, picks)
        }
    }

    private var starCount: Int {
        starred.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        OnboardingPage(
            title: "Your favorites",
            subtitle: "Star the ones you love most. They show on your profile, first starred first.",
            onBack: onBack,
            onSkip: onSkip,
            isBusy: isSaving || model.isAwaitingRelated
        ) {
            ForEach(groups, id: \.kind) { group in
                VStack(alignment: .leading, spacing: AaruSpace.medium) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.kind.label)
                            .font(.aaruDisplay(.title3, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if let count = starred[group.kind]?.count, count > 0 {
                            Text("\(count) of \(FavoritesModel.limit)")
                                .font(.caption)
                                .foregroundStyle(Color(.muted))
                        }
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: compact ? 96 : 128), spacing: 12, alignment: .top)],
                        spacing: 16
                    ) {
                        ForEach(group.picks) { pick in
                            card(pick)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        } footer: {
            OnboardingProblem(message: favorites.problem) { favorites.problem = nil }
            OnboardingPill(
                label: saveFailed ? "Try again" : (starCount > 0 ? "Continue (\(starCount))" : "Skip favorites"),
                isBusy: isSaving || model.isAwaitingRelated
            ) { Task { await save() } }
        }
    }

    private func card(_ pick: OnboardingPick) -> some View {
        let order = starred[pick.kind]?.firstIndex(of: pick.id)
        let full = (starred[pick.kind]?.count ?? 0) >= FavoritesModel.limit
        return Button {
            toggle(pick)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterView(url: pick.hit.posterUrl.flatMap(URL.init(string:)), kind: pick.kind.mediaKind)
                    .overlay {
                        if order != nil {
                            RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous)
                                .strokeBorder(Color(.gold), lineWidth: 3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: order == nil ? "star" : "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(order == nil ? Color(.ink) : Color(.night))
                            .frame(width: 28, height: 28)
                            .background(
                                order == nil ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color(.gold)),
                                in: Circle()
                            )
                            .padding(6)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let order {
                            HomeChip(text: "\(order + 1)", tint: Color(.gold), foreground: Color(.night))
                                .padding(6)
                        }
                    }
                    .animation(reduceMotion ? nil : AaruMotion.ease(AaruMotion.fast), value: order)
                Text(pick.hit.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(order == nil && full)
        .modifier(HoverLift())
        .accessibilityLabel(pick.hit.title)
        .accessibilityValue(order.map { "Favorite \($0 + 1)" } ?? "")
        .accessibilityAddTraits(order != nil ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ pick: OnboardingPick) {
        var list = starred[pick.kind] ?? []
        if let index = list.firstIndex(of: pick.id) {
            list.remove(at: index)
        } else if list.count < FavoritesModel.limit {
            list.append(pick.id)
        }
        starred[pick.kind] = list
    }

    /// One `PUT` per kind starred; a kind that saved is not sent again on a retry.
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        for (kind, ids) in starred where !ids.isEmpty {
            let refs = ids.compactMap { id -> MediaRef? in
                guard let pick = model.picks.first(where: { $0.id == id }), let saved = pick.saved else { return nil }
                return MediaRef(titleId: saved.titleID, _type: pick.hit._type)
            }
            guard await favorites.append(refs, to: kind.favoriteKind) else {
                saveFailed = true
                return
            }
            starred[kind] = nil
        }
        saveFailed = false
        onContinue()
    }
}
