import AaruAPI
import SwiftUI

/// `BadgeShelf` (VIEWS.md): the badges by family, earned first in each, the rest with their
/// progress ("62 / 100"). A hidden badge not yet earned is a blank "???" with no hint. A badge
/// opens its tiers.
struct BadgeShelf: View {
    let badges: [AchievementBadge]
    @State private var opened: AchievementBadge?
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = 104

    private var families: [(family: Components.Schemas.BadgeFamily, badges: [AchievementBadge])] {
        Components.Schemas.BadgeFamily.allCases.compactMap { family in
            let inFamily = badges.filter { $0.family == family }
            guard !inFamily.isEmpty else { return nil }
            // Earned first, keeping the catalog's order within each half.
            return (family, inFamily.filter(\.earned) + inFamily.filter { !$0.earned })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(families, id: \.family) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(BadgeGlyph.familyName(group.family))
                            .font(.aaruDisplay(.title3))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(group.badges.count { $0.earned }) of \(group.badges.count)")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Color(.muted))
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(group.badges, id: \.id) { badge in
                            Button {
                                opened = badge
                            } label: {
                                BadgeCell(badge: badge)
                            }
                            .buttonStyle(.plain)
                            .disabled(badge.hidden && !badge.earned)
                        }
                    }
                }
            }
        }
        .sheet(item: $opened) { badge in
            BadgeDetailSheet(badge: badge)
        }
    }
}

extension Components.Schemas.Badge: @retroactive Identifiable {}

/// One badge on the shelf: medallion, name, and its tier or progress.
private struct BadgeCell: View {
    let badge: AchievementBadge

    private var secret: Bool {
        badge.hidden && !badge.earned
    }

    var body: some View {
        VStack(spacing: 6) {
            BadgeMedallion(badge: badge.id, family: badge.family, tier: badge.tier, secret: secret)
            Text(badge.name ?? "???")
                .font(.aaruDisplay(.subheadline))
                .foregroundStyle(badge.earned ? Color(.ink) : Color(.muted))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let word = BadgeGlyph.tierWord(badge.tier, of: badge.maxTier) {
                Text(word).eyebrow()
            }
            if let progress = badge.progress {
                Text("\(progress.current.formatted()) / \(progress.target.formatted())")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if secret {
            return "Hidden badge, not yet earned"
        }
        var parts = [badge.name ?? ""]
        if let word = BadgeGlyph.tierWord(badge.tier, of: badge.maxTier) {
            parts.append(word)
        } else if badge.earned {
            parts.append("earned")
        }
        if let progress = badge.progress {
            parts.append("\(progress.current) of \(progress.target)")
        }
        return parts.joined(separator: ", ")
    }
}

/// A badge's tiers: what each asks, and when it was earned.
private struct BadgeDetailSheet: View {
    let badge: AchievementBadge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        BadgeMedallion(badge: badge.id, family: badge.family, tier: badge.tier, size: 88)
                        Text(badge.name ?? "")
                            .font(.aaruDisplay(.title2))
                        if let description = badge.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(Color(.muted))
                                .multilineTextAlignment(.center)
                        }
                        if badge._private == true {
                            Label("Only you see this one", systemImage: "lock")
                                .font(.footnote)
                                .foregroundStyle(Color(.muted))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                if let tiers = badge.tiers, tiers.count > 1 {
                    Section("Tiers") {
                        ForEach(tiers, id: \.tier) { tier in
                            LabeledContent {
                                if let awarded = tier.awardedAt {
                                    Text(awarded.formatted(date: .abbreviated, time: .omitted))
                                } else {
                                    Text("Not yet").foregroundStyle(Color(.muted))
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(BadgeGlyph.tierWord(tier.tier, of: badge.maxTier) ?? "").eyebrow()
                                    Text(tier.description)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .navigationTitle(badge.name ?? "Badge")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A friend's badges on their profile: one row of the most recent, "See all" for the rest. The
/// server leaves out private badges and sends nothing when the friend turned the switch off.
struct FriendBadgeRow: View {
    let name: String
    let achievements: Components.Schemas.FriendAchievements
    @State private var showsAll = false

    private var recent: [BadgeAward] {
        achievements.badges.sorted { $0.awardedAt > $1.awardedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(achievements.level)")
                    .font(.aaruDisplay(.title3))
                Text(achievements.badges.count == 1 ? "1 badge" : "\(achievements.badges.count) badges")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                Spacer()
                if achievements.badges.count > 6 {
                    Button("See all") { showsAll = true }
                        .font(.subheadline)
                }
            }
            if !recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(recent.prefix(6), id: \.id) { award in
                            AwardCell(award: award)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsAll) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)], spacing: 16) {
                        ForEach(recent, id: \.id) { award in
                            AwardCell(award: award)
                        }
                    }
                    .padding(20)
                }
                .background(Color(.paper))
                .navigationTitle("\(name)'s badges")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsAll = false }
                    }
                }
            }
        }
    }
}

/// An earned badge, as a friend's profile and the unlock show it.
struct AwardCell: View {
    let award: BadgeAward

    var body: some View {
        VStack(spacing: 6) {
            BadgeMedallion(badge: award.badge, family: award.family, tier: award.tier, size: 52)
            Text(award.name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let word = BadgeGlyph.tierWord(award.tier, of: award.maxTier) {
                Text(word).eyebrow()
            }
        }
        .frame(width: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [award.name, BadgeGlyph.tierWord(award.tier, of: award.maxTier)].compactMap(\.self).joined(separator: ", ")
        )
    }
}
