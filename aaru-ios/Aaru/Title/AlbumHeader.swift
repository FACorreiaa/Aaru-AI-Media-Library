import SwiftUI

/// MUS-001: the top of an album's page. A large square cover with almost no chrome, the name in
/// the title serif, the artist under it, the year, and the genres as chips.
struct AlbumHeader: View {
    let title: String
    let artist: String?
    let year: Int?
    let genres: [String]
    let coverURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            PosterView(url: coverURL, kind: .music)
                .frame(maxWidth: 280)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let artist {
                    Text(artist)
                        .font(.title3)
                        .foregroundStyle(Color(.muted))
                        .multilineTextAlignment(.center)
                }
                if let year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                        .monospacedDigit()
                }
            }
            if !genres.isEmpty {
                CenteredFlow(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre.capitalized)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color(.surface), in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Genres: \(genres.joined(separator: ", "))")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview("Album header") {
    Form {
        Section {
            AlbumHeader(
                title: "OK Computer", artist: "Radiohead", year: 1997,
                genres: ["alternative rock", "art rock", "experimental rock"], coverURL: nil
            )
        }
        .listRowBackground(Color.clear)
        AlbumTracklist(tracks: AlbumSample.okComputerTracks, isLoading: false)
    }
    .formStyle(.grouped)
}
