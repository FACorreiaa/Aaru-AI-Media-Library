import AaruAPI
import SwiftUI

typealias ChatRoadmap = Components.Schemas.ChatRoadmap

extension Components.Schemas.ChatRoadmapItem {
    /// "Film · 2022", "Book · Jonathan Hickman": what tells one title from another of its name.
    var line: String {
        let kind = switch _type {
        case .movie: String(localized: "Film")
        case .show: String(localized: "Show")
        case .book: String(localized: "Book")
        case .manga: String(localized: "Manga")
        }
        return ([kind, author] + [year.map { String($0) }]).compactMap(\.self).joined(separator: " · ")
    }
}

extension ChatRoadmap {
    /// "9 titles in 3 steps", or "9 titles" for a plain list.
    var summary: String {
        let titles = steps.reduce(0) { $0 + $1.items.count }
        let counted = titles == 1 ? String(localized: "1 title") : String(localized: "\(titles) titles")
        let staged = steps.count(where: { $0.heading != nil })
        if staged == 0 {
            return counted
        }
        return staged == 1
            ? String(localized: "\(counted) in 1 step") : String(localized: "\(counted) in \(staged) steps")
    }
}

/// The list Aaru planned in a chat (ASK-011, VIEWS.md `RoadmapCard`): its name and its steps, each
/// title as Aaru named it, before any is matched. Read-only, with one action: the import's review,
/// where the titles are matched and nothing is added until the person approves.
struct RoadmapCardView: View {
    let roadmap: ChatRoadmap
    /// The import that holds it; nil when that import was deleted.
    let importID: String?
    let onReview: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            VStack(alignment: .leading, spacing: 2) {
                if let name = roadmap.listName {
                    Text(name)
                        .font(.aaruDisplay(.title3, weight: .semibold))
                        .foregroundStyle(Color(.ink))
                }
                Text("\(roadmap.summary) · nothing is added until you review")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            ForEach(Array(roadmap.steps.enumerated()), id: \.offset) { number, step in
                stepView(step, number: number + 1)
            }
            if let importID {
                Button("Review and save") { onReview(importID) }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("The review for this list was deleted.")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
        .padding(AaruSpace.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .contain)
    }

    private func stepView(_ step: Components.Schemas.ChatRoadmapStep, number: Int) -> some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            if let heading = step.heading {
                Text("\(number). \(heading)")
                    .font(.aaruDisplay(.headline, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .accessibilityAddTraits(.isHeader)
            }
            if let note = step.note {
                Text(note).font(.footnote).foregroundStyle(Color(.muted))
            }
            ForEach(Array(step.items.enumerated()), id: \.offset) { index, item in
                itemView(item, startsPair: Self.startsPair(step.items, at: index))
            }
        }
    }

    private func itemView(_ item: Components.Schemas.ChatRoadmapItem, startsPair: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.body.weight(.medium))
                .foregroundStyle(Color(.ink))
            HStack(spacing: AaruSpace.xsmall) {
                Text(item.line).font(.footnote).foregroundStyle(Color(.muted))
                if item.optional == true {
                    tag(String(localized: "Optional"))
                }
                if startsPair {
                    tag(String(localized: "Side by side"))
                }
            }
            if let note = item.note {
                Text(note).font(.footnote).foregroundStyle(Color(.muted))
            }
        }
        .padding(.leading, item.pair == nil ? 0 : AaruSpace.small)
        .overlay(alignment: .leading) {
            if item.pair != nil {
                Rectangle().fill(Color(.accent)).frame(width: 2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.ink).opacity(AaruAlpha.tint), in: Capsule())
            .foregroundStyle(Color(.ink))
    }

    /// Whether this title starts a pair read side by side: the next one shares its number.
    private static func startsPair(_ items: [Components.Schemas.ChatRoadmapItem], at index: Int) -> Bool {
        guard let pair = items[index].pair else { return false }
        let before = index > 0 ? items[index - 1].pair : nil
        let after = index + 1 < items.count ? items[index + 1].pair : nil
        return before != pair && after == pair
    }
}

#Preview {
    ScrollView {
        RoadmapCardView(
            roadmap: ChatRoadmap(listName: "Before Secret Wars", steps: [
                .init(heading: "The Multiverse begins", note: "Where the branches start.", items: [
                    .init(title: "Loki", _type: .show, year: 2021, note: "Both seasons"),
                    .init(title: "What If...?", _type: .show, year: 2021, optional: true),
                ]),
                .init(heading: "Incursions", items: [
                    .init(title: "Secret Wars", _type: .book, author: "Jonathan Hickman", note: "#1-9", pair: 1),
                    .init(title: "Avengers: Time Runs Out", _type: .book, author: "Jonathan Hickman", pair: 1),
                ]),
            ]),
            importID: "i1",
            onReview: { _ in }
        )
        .padding()
    }
}
