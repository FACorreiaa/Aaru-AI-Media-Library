import AaruAPI
import SwiftUI

/// A4: one episode up close. Still, code, name, air date, runtime, synopsis, and the same
/// watched tick as the season map. Previous and next walk the map's order.
struct EpisodeSheet: View {
    let model: TitleDetailModel
    @State private var key: EpisodeKey
    @Environment(\.dismiss) private var dismiss

    init(key: EpisodeKey, model: TitleDetailModel) {
        self.model = model
        _key = State(initialValue: key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let episode = model.episode(key) {
                    content(episode)
                }
            }
            .background(Color(.paper))
            .navigationTitle(key.season == 0 ? "Specials" : "Season \(key.season)")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { toolbar }
        }
        .presentationDetents([.medium, .large])
    }

    private func content(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            EpisodeStill(url: episode.stillUrl.flatMap(URL.init(string:)))

            VStack(alignment: .leading, spacing: 4) {
                Text("S\(episode.season) · E\(episode.number)")
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color(.muted))
                Text(episode.name ?? "Episode \(episode.number)")
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = meta(episode) {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(Color(.muted))
                }
            }

            Toggle("Watched", isOn: watchedBinding)
                .tint(Color.accentColor)
                .disabled(!model.canToggle(episode) || model.pending.contains(key))

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(Color(.ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItemGroup(placement: navigationPlacement) {
            Button("Previous episode", systemImage: "chevron.left") { step(-1) }
                .disabled(model.episode(key, offset: -1) == nil)
            Spacer()
            Button("Next episode", systemImage: "chevron.right") { step(1) }
                .disabled(model.episode(key, offset: 1) == nil)
        }
    }

    private var navigationPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .bottomBar
        #else
            .automatic
        #endif
    }

    private var watchedBinding: Binding<Bool> {
        Binding(get: { model.watched.contains(key) }, set: { _ in
            let key = key
            Task { await model.toggle(key) }
        })
    }

    private func step(_ offset: Int) {
        if let neighbor = model.episode(key, offset: offset) {
            key = neighbor
        }
    }

    /// "Aired 3 Mar 2024 · 48 min". The time shows only when the source knows it.
    private func meta(_ episode: Episode) -> String? {
        let date = episode.airsAt.map { airsAt in
            let when = episode.airTimeKnown
                ? airsAt.formatted(date: .abbreviated, time: .shortened)
                : airsAt.formatted(date: .abbreviated, time: .omitted)
            return (model.hasAired(episode) ? "Aired " : "Airs ") + when
        }
        let runtime = episode.runtimeMinutes.map { "\($0) min" }
        let parts = [date, runtime].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A 16:9 episode still from the catalog URL, with a calm placeholder while it loads or when
/// there is none. Shared by the sheet and the episode rows.
struct EpisodeStill: View {
    let url: URL?
    var cornerRadius: CGFloat = 10

    var body: some View {
        Color(.surface)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "tv")
                            .foregroundStyle(Color(.muted).opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}
