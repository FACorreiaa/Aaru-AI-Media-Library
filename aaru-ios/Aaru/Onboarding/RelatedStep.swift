import SwiftUI

/// More from what you picked (DESIGN.md §0a, 4): sequels, prequels, side stories, spin-offs,
/// adaptations and sources of the picks, from the relation graph (GRAPH-001). The catalog's
/// relation data, never a recommendation: no "for you", no "because you watched". A tap adds
/// Plan to…; Continue saves them as one action.
struct RelatedStep: View {
    @Bindable var model: OnboardingModel
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicType
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var compact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        OnboardingPage(
            title: String(localized: "More from what you picked"),
            subtitle: String(localized: "Sequels, prequels, spin-offs and adaptations. Tap to plan them."),
            onBack: onBack,
            onSkip: onSkip,
            isBusy: model.isBusy
        ) {
            LazyVStack(alignment: .leading, spacing: AaruSpace.section) {
                ForEach(model.relatedGroups) { group in
                    HomeRow(title: String(localized: "More from \(group.fromTitle)")) {
                        ForEach(group.hits) { hit in
                            poster(hit)
                        }
                    }
                }
            }
        } footer: {
            OnboardingProblem(message: model.problem) { model.problem = nil }
            OnboardingPill(
                label: model.saveFailed
                    ? String(localized: "Try again")
                    : model.relatedChosen.isEmpty
                    ? String(localized: "Skip these") : String(localized: "Continue (\(model.relatedChosen.count))"),
                isBusy: model.isBusy,
                action: onContinue
            )
        }
    }

    private func poster(_ hit: CatalogHit) -> some View {
        let kind = MediaKind(type: hit._type, isAnime: hit.isAnime)
        let chosen = model.relatedChosen.contains(hit.id)
        let state: OnboardingPosterState = if let pick = model.pick(for: hit), pick.saved != nil {
            .saved(pick.status)
        } else if chosen {
            .picked(.wishlist)
        } else {
            .open
        }
        return OnboardingPoster(
            hit: hit,
            kind: kind,
            state: state,
            width: HomeCardSize.poster.width(compact: compact, dynamicType: dynamicType),
            menuStatuses: [.wishlist],
            tapHint: chosen
                ? String(localized: "Takes it off")
                : String(localized: "Adds it as \(LibraryStatus.wishlist.label(for: kind))"),
            onTap: { model.toggleRelated(hit) },
            onSet: { status in
                // The menu here is plan or not: every related title is added as planned.
                if (status == nil) == chosen {
                    model.toggleRelated(hit)
                }
            }
        )
    }
}
