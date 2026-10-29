import AaruAPI
import SwiftUI

/// A shared title, as its share sheet shows it: poster, name, kind and year, and the synopsis.
/// The match and concert cards are their own screens' faces (`EventHeader`, `ConcertRow`).
struct ShareTitleCard: View {
    let title: TitleDetail

    private var kind: MediaKind {
        MediaKind(type: title._type, isAnime: title.isAnime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(maxWidth: kind == .music ? 240 : 160)
                .clipShape(.rect(cornerRadius: AaruRadius.field, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title.title)
                    .font(.aaruDisplay(.title, weight: .semibold))
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
            if let synopsis = title.synopsis, !synopsis.isEmpty {
                Text(synopsis)
                    .foregroundStyle(Color(.ink))
                    .lineLimit(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Show · 2016 · Denis Villeneuve".
    private var facts: String {
        [kind.noun, title.year.map { String($0) }, title.byline]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// "From Ana" and the note in quotes. Only the sender's friends get these from the API.
struct ShareSenderLine: View {
    let sender: Components.Schemas.ShareSender

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From \(sender.user.inviteName)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.ink))
            if let note = sender.note, !note.isEmpty {
                Text("“\(note)”")
                    .font(.aaruDisplay(.body, weight: .regular, italic: true))
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
