import SwiftUI

/// Sports → Favorites: one card per followed league, team or player, with what is live now
/// (score and clock), else the next fixture in local time, and the last result. With nothing
/// followed yet, the fixed picks to start from.
struct SportFavoritesView: View {
    let model: SportsModel
    let onFind: () -> Void
    let onOpen: (SportEvent) -> Void

    var body: some View {
        if let favorites = model.favorites {
            if favorites.items.isEmpty {
                FirstFollows(model: model, onFind: onFind)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(favorites.items, id: \.entity.followKey) { item in
                            FavoriteCard(item: item, model: model, onOpen: onOpen)
                        }
                        // The picks leave with the first follow; more are found from here.
                        Button("Find leagues and teams", systemImage: "plus", action: onFind)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        SportsCredit()
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                }
            }
        } else if model.favoritesFailed {
            LoadFailedView(
                title: "Couldn't load Sports",
                message: "Your leagues and teams didn't load."
            ) { await model.loadFavorites() }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One follow: its badge and name, then live, next and last.
private struct FavoriteCard: View {
    let item: SportFavorite
    let model: SportsModel
    let onOpen: (SportEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !item.live.isEmpty {
                ForEach(item.live, id: \.id) { event in
                    SportEventRow(event: event) { onOpen(event) }
                        .background(Color(.accent).opacity(AaruAlpha.tint), in: rowShape)
                }
            } else if let next = item.next {
                part("Next") {
                    SportEventRow(event: next, showsDay: true) { onOpen(next) }
                }
            }
            if let last = item.last {
                part("Last result") {
                    SportEventRow(event: last, showsDay: true) { onOpen(last) }
                }
            }
            if item.pending, item.live.isEmpty, item.next == nil, item.last == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    QuietNote("Fetching fixtures…")
                }
            } else if !item.pending, item.live.isEmpty, item.next == nil, item.last == nil {
                QuietNote("No fixtures listed.")
            }
        }
        .padding(16)
        .card()
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AaruRadius.row, style: .continuous)
    }

    private var header: some View {
        HStack(spacing: 12) {
            SportBadge(url: item.entity.badgeUrl, sport: item.entity.sport, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entity.name)
                    .font(.aaruDisplay(.headline, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                Text(item.entity.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if !item.live.isEmpty {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color(.onAccent))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.accent), in: .capsule)
            }
            Menu {
                Button("Unfollow \(item.entity.name)", systemImage: "star.slash", role: .destructive) {
                    Task { await model.setFollowing(item.entity, false) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .accessibilityLabel("More for \(item.entity.name)")
        }
    }

    private func part(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).eyebrow()
            content()
        }
    }
}

/// Nothing followed yet: the owl, the fixed picks as follow chips, and search.
private struct FirstFollows: View {
    let model: SportsModel
    let onFind: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OwlUnavailableView(
                    title: "Follow a league or a team",
                    message: "Their live scores, next fixtures and results show here."
                ) {
                    Button("Find leagues and teams", action: onFind)
                        .buttonStyle(.borderedProminent)
                }
                SportSuggestions(model: model)
                SportsCredit()
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }
}

/// The fixed picks (Premier League, NBA, NFL, UFC…) as chips that follow or unfollow on a tap.
/// The same for everyone; never a recommendation.
struct SportSuggestions: View {
    let model: SportsModel

    var body: some View {
        VStack(spacing: 12) {
            if !model.suggestions.isEmpty {
                Text("Start with a league").eyebrow()
                CenteredFlow(spacing: 8) {
                    ForEach(model.suggestions, id: \.followKey) { entity in
                        SportFollowChip(entity: entity, model: model)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task { await model.loadSuggestions() }
    }
}

/// A league, team or player as a chip: badge and name, filled while followed.
struct SportFollowChip: View {
    let entity: SportEntity
    let model: SportsModel

    var body: some View {
        let following = model.isFollowing(entity)
        Button {
            Task { await model.setFollowing(entity, !following) }
        } label: {
            HStack(spacing: 6) {
                SportBadge(url: entity.badgeUrl, sport: entity.sport, size: 20)
                Text(entity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: following ? "checkmark" : "plus")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color(following ? .onAccent : .ink))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(following ? .accent : .surface), in: .capsule)
            .overlay {
                Capsule().strokeBorder(Color(following ? .accent : .line), lineWidth: 1)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(model.changing.contains(entity.followKey))
        .accessibilityLabel(entity.name)
        .accessibilityValue(following ? "Following" : "Not following")
        .accessibilityHint(following ? "Unfollows" : "Follows")
    }
}
