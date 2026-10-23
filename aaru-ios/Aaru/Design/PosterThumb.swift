import SwiftUI

/// A small poster for a cell or a list mark: the catalog image, else the title's initials on a
/// blue-to-amber tile (when given) or the kind's symbol. Decorative: the row it sits in names the
/// title. Calendar's month cells and group channel marks share it.
struct PosterThumb: View {
    let url: URL?
    var kind: MediaKind = .show
    /// "SH" for Slow Horses. Nil shows the kind's symbol instead.
    var initials: String?
    var cornerRadius: CGFloat = AaruRadius.thumb

    var body: some View {
        Color(initials == nil ? .surface : .medallion)
            .aspectRatio(kind.posterAspect, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var placeholder: some View {
        if let initials {
            ZStack {
                LinearGradient(
                    colors: [Color(.accent).opacity(AaruAlpha.half), Color(.gold).opacity(AaruAlpha.half)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(.onAccent))
                    .minimumScaleFactor(0.6)
            }
        } else {
            Image(systemName: kind.symbol)
                .font(.caption2)
                .foregroundStyle(Color(.muted))
        }
    }
}
