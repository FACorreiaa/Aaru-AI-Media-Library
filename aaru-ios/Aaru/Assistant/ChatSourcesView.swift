import AaruAPI
import SwiftUI

/// ASK-004: the web pages an answer cites, under the reply, each opening in the browser. They are
/// never part of the words read aloud.
struct ChatSourcesView: View {
    let sources: [Components.Schemas.ChatSource]

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.muted))
            ForEach(sources, id: \.url) { source in
                if let link = source.link {
                    Link(destination: link) {
                        HStack(spacing: AaruSpace.xsmall) {
                            Text(verbatim: source.title.isEmpty ? source.site : source.title)
                                .foregroundStyle(Color(.accent))
                                .lineLimit(1)
                            Text(verbatim: source.site)
                                .foregroundStyle(Color(.muted))
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ChatSourcesView(sources: [
        .init(url: "https://www.example.com/dune-part-three", title: "Dune: Part Three dated for December 2026"),
        .init(url: "https://example.org/news", title: ""),
    ])
    .padding()
}
