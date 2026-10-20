import AaruAPI
import SwiftUI

/// APP-005: the Title room. Status, rating, notes, owned; for shows, seasons with episode ticks.
struct TitleDetailView: View {
    @State private var model: TitleDetailModel
    @State private var notes = ""
    @State private var page = ""
    @State private var showsListPicker = false
    private let lists: ListsModel

    init(entry: LibraryEntry, api: Client?, library: LibraryModel, lists: ListsModel) {
        _model = State(initialValue: TitleDetailModel(entry: entry, api: api, library: library))
        self.lists = lists
    }

    private var entry: LibraryEntry {
        model.entry
    }

    var body: some View {
        Form {
            Section { header }
                .listRowBackground(Color.clear)

            Section {
                Picker("Status", selection: statusBinding) {
                    ForEach(LibraryStatus.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Rating") {
                    RatingStars(rating: entry.rating) { rating in
                        Task { await setRating(rating) }
                    }
                }
                Toggle("Owned", isOn: ownedBinding)
                if entry.title._type == .book {
                    LabeledContent("Page") {
                        TextField("Page", text: $page)
                            .multilineTextAlignment(.trailing)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                            .onSubmit { Task { await savePage() } }
                    }
                }
            }

            Section("Notes") {
                TextField("Anything worth remembering", text: $notes, axis: .vertical)
                    .lineLimit(3 ... 8)
                if notes != (entry.notes ?? "") {
                    Button("Save note") { Task { await saveNotes() } }
                }
            }

            if let synopsis = model.title?.synopsis, !synopsis.isEmpty {
                Section("About") {
                    Text(synopsis).font(.callout).foregroundStyle(Color(.muted))
                }
            }

            if model.isShow {
                seasons
            }
        }
        .formStyle(.grouped)
        // The rollback message sits where the tap was: at the bottom, not above a long season list.
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: model.problem) { model.problem = nil } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add to list", systemImage: "text.badge.plus") { showsListPicker = true }
            }
        }
        .sheet(isPresented: $showsListPicker) {
            ListPickerSheet(
                ref: .init(titleId: entry.title.id, _type: entry.title._type),
                titleName: entry.title.title,
                lists: lists
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle(entry.title.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                notes = entry.notes ?? ""
                page = entry.bookProgress?.page.map(String.init) ?? ""
                await model.load()
            }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PosterView(
                url: entry.title.posterUrl.flatMap(URL.init(string:)),
                kind: MediaKind(type: entry.title._type, isAnime: entry.title.isAnime)
            )
            .frame(width: 110)
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title.title)
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                if let progress = entry.progress, progress.airedCount > 0 {
                    ProgressView(value: Double(progress.watchedCount), total: Double(progress.airedCount)) {
                        Text("\(progress.watchedCount) of \(progress.airedCount) episodes")
                            .font(.footnote)
                            .foregroundStyle(Color(.muted))
                    }
                    .tint(Color(.accent))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var meta: String {
        let kind = MediaKind(type: entry.title._type, isAnime: entry.title.isAnime).label
        let runtime = model.title?.runtimeMinutes.map { "\($0) min" }
        let status = model.title?.status.map { $0.rawValue.capitalized }
        return [entry.title.year.map(String.init), kind, runtime, status]
            .compactMap(\.self).joined(separator: " · ")
    }

    // MARK: Seasons

    @ViewBuilder private var seasons: some View {
        if let seasons = model.title?.seasons {
            ForEach(
                seasons.sorted { ($0.number == 0 ? Int.max : $0.number) < ($1.number == 0 ? Int.max : $1.number) },
                id: \.number
            ) { season in
                SeasonSection(season: season, model: model)
            }
        } else {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    // MARK: Writes

    private var statusBinding: Binding<LibraryStatus> {
        Binding(get: { entry.status }, set: { status in
            Task {
                await model.update(.init(status: status)) { $0.status = status }
            }
        })
    }

    private var ownedBinding: Binding<Bool> {
        Binding(get: { entry.isOwned }, set: { owned in
            Task {
                await model.update(.init(isOwned: owned)) { $0.isOwned = owned }
            }
        })
    }

    private func setRating(_ rating: Double?) async {
        if let rating {
            await model.update(.init(rating: rating)) { $0.rating = rating }
        } else {
            await model.update(.init(clear: [.rating])) { $0.rating = nil }
        }
    }

    private func saveNotes() async {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            await model.update(.init(clear: [.notes])) { $0.notes = nil }
        } else {
            await model.update(.init(notes: text)) { $0.notes = text }
        }
        notes = entry.notes ?? ""
    }

    private func savePage() async {
        guard let number = Int(page.filter(\.isNumber)) else { return }
        await model.update(.init(bookPage: number)) { $0.bookProgress = .init(page: number) }
        page = entry.bookProgress?.page.map(String.init) ?? page
    }
}

/// One season: a header with "Mark watched" and a tick per episode. Unaired episodes cannot be ticked.
private struct SeasonSection: View {
    let season: Components.Schemas.Season
    let model: TitleDetailModel

    private var keys: [EpisodeKey] {
        season.episodes.map { EpisodeKey(season: $0.season, number: $0.number) }
    }

    var body: some View {
        Section {
            ForEach(season.episodes, id: \.number) { episode in
                EpisodeRow(episode: episode, model: model)
            }
        } header: {
            HStack {
                Text(season.number == 0 ? "Specials" : "Season \(season.number)")
                Spacer()
                let watched = keys.count(where: model.watched.contains)
                Text("\(watched) of \(keys.count)")
                    .foregroundStyle(Color(.muted))
                if season.number > 0, !model.airedEpisodes(in: season.number).isSubset(of: model.watched) {
                    Button("Mark watched") { Task { await model.markSeasonWatched(season.number) } }
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Components.Schemas.Episode
    let model: TitleDetailModel

    private var key: EpisodeKey {
        EpisodeKey(season: episode.season, number: episode.number)
    }

    private var hasAired: Bool {
        (episode.airsAt ?? .distantPast) <= Date()
    }

    var body: some View {
        let isWatched = model.watched.contains(key)
        Button {
            Task { await model.toggle(key) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if model.pending.contains(key) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isWatched ? Color(.accent) : Color(.muted))
                    }
                }
                .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(episode.number). \(episode.name ?? "Episode \(episode.number)")")
                        .foregroundStyle(Color(.ink))
                        .lineLimit(2)
                    if let airsAt = episode.airsAt {
                        Text(hasAired ? airsAt.formatted(date: .abbreviated, time: .omitted)
                            : "Airs \(airsAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Color(.muted))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasAired && !isWatched)
        #if os(iOS)
            .contextMenu {
                if hasAired, !isWatched {
                    Button("Start watching", systemImage: "play.circle") {
                        Task { await model.startWatching(episode) }
                    }
                }
            }
        #endif
            .accessibilityLabel("Episode \(episode.number), \(episode.name ?? "")")
            .accessibilityValue(isWatched ? "Watched" : "Not watched")
    }
}

/// Five stars, each worth two points of the 1–10 scale. Tapping the current value clears it.
private struct RatingStars: View {
    let rating: Double?
    let onChange: (Double?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1 ... 5, id: \.self) { star in
                let value = Double(star * 2)
                Button {
                    onChange(rating == value ? nil : value)
                } label: {
                    Image(systemName: (rating ?? 0) >= value ? "star.fill"
                        : (rating ?? 0) >= value - 1 ? "star.leadinghalf.filled" : "star")
                        .foregroundStyle(Color(.accent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating.map { "\(Int($0)) of 10" } ?? "Not rated")
    }
}
