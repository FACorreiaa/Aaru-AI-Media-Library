import SwiftUI

/// A 2:3 poster (a square cover for an album) from the catalog URL, with a calm placeholder while it loads or when
/// there is none.
struct PosterView: View {
    let url: URL?
    let kind: MediaKind

    var body: some View {
        Color(.surface)
            .aspectRatio(kind.posterAspect, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: kind.symbol)
                            .font(.title2)
                            .foregroundStyle(Color(.muted).opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}
