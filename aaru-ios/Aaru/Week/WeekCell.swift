import AaruAPI
import SwiftUI

/// One episode in the week grid (DESIGN.md §14): banner art, show, `S01E05`, episode name,
/// network · time, and a tick that marks it watched in place.
struct WeekCell: View {
    let entry: CalendarEntry
    let isPending: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeekBanner(entry: entry)
                .overlay(alignment: .topLeading) {
                    WeekTick(isOn: entry.watched, isPending: isPending, label: tickLabel, action: onToggle)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let badge = entry.badge {
                        WeekBadge(badge: badge).padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.accent))
                    .lineLimit(2)
                Text(entry.code)
                    .font(.caption.weight(.medium).monospacedDigit())
                if let name = entry.episodeName {
                    Text(name)
                        .font(.caption)
                        .lineLimit(2)
                }
                if let detail = entry.whereAndWhen {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if let badge = entry.badge {
                RoundedRectangle(cornerRadius: 10).strokeBorder(badge.tint.opacity(0.7), lineWidth: 1.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(entry.watched ? 0.5 : 1)
        .animation(.easeOut(duration: 0.15), value: entry.watched)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: entry.watched ? "Mark unwatched" : "Mark watched", onToggle)
    }

    private var tickLabel: String {
        "\(entry.watched ? "Mark unwatched" : "Mark watched"): \(entry.title.title) \(entry.code)"
    }

    private var accessibilityText: String {
        [
            entry.title.title, entry.code, entry.episodeName, entry.whereAndWhen,
            entry.badge?.label, entry.watched ? "Watched" : nil,
        ].compactMap(\.self).joined(separator: ", ")
    }
}

/// The wide art at the top of a cell: backdrop, else the poster cropped, else a tinted block.
private struct WeekBanner: View {
    let entry: CalendarEntry

    private var url: URL? {
        (entry.title.backdropUrl ?? entry.title.posterUrl).flatMap(URL.init(string:))
    }

    var body: some View {
        Color(.medallion)
            .aspectRatio(16 / 5, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    /// No art: a quiet blue-to-amber wash. The show's name is right below, so no text here.
    private var placeholder: some View {
        LinearGradient(
            colors: [Color(.accent).opacity(0.25), Color(.gold).opacity(0.25)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// The watched tick: a 44 pt target around a small check on the banner.
private struct WeekTick: View {
    let isOn: Bool
    let isPending: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(isOn ? Color.white : Color.white, isOn ? Color(.accent) : .clear)
                .background(.black.opacity(0.35), in: Circle())
                .padding(6)
                .frame(minWidth: 44, minHeight: 44, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .accessibilityLabel(label)
    }
}

struct WeekBadge: View {
    let badge: CalendarEntry.Badge

    var body: some View {
        Text(badge.label)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(Color(.paper))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(badge.tint, in: Capsule())
    }
}

extension CalendarEntry {
    /// Premieres and finales stand out: accent for a start, ink for an end (as on the web), each
    /// under Paper text that passes AA in both appearances. Not CAT's colours.
    enum Badge {
        case premiere, newSeason, finale

        var label: String {
            switch self {
            case .premiere: "Premiere"
            case .newSeason: "New season"
            case .finale: "Finale"
            }
        }

        var tint: Color {
            switch self {
            case .premiere, .newSeason: Color(.accent)
            case .finale: Color(.ink)
            }
        }
    }

    var badge: Badge? {
        switch kind {
        case .premiere: season <= 1 ? .premiere : .newSeason
        case .finale: .finale
        case .regular: nil
        }
    }

    /// "S01E05", the week cell's code (DESIGN.md §14). Everywhere else reads `shortCode`.
    var code: String {
        EpisodeCode.padded(season: season, number: number)
    }

    /// "HBO · 9:00 PM", either half alone, or nil. A date-only air date has no time to show.
    var whereAndWhen: String? {
        let time = airTimeKnown ? airsAt.formatted(date: .omitted, time: .shortened) : nil
        let parts = [title.network, time].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
