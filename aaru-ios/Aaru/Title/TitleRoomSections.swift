import AaruAPI
import SwiftUI

// The Title room's sections (`TitleDetailView`): the hero, the user's layer, About and the
// seasons. Smaller pieces (a season, an episode row, the stars) are in `TitleRoomParts`.

/// The backdrop under a veil of Paper, the poster standing over its lower edge, the name.
struct TitleHero: View {
    let entry: LibraryEntry
    let kind: MediaKind
    /// "2022 · Show · 48 min · Returning series".
    let meta: String
    let compact: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    /// How far the poster rises over the backdrop; the text beside it starts just below that.
    private var overlap: CGFloat {
        compact ? AaruSpace.page : AaruSpace.page + AaruSpace.large
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroBackdrop(url: entry.title.backdropUrl.flatMap(URL.init(string:)), seed: entry.title.id)
                .frame(height: compact ? 200 : 300)
                .clipShape(.rect(cornerRadius: AaruRadius.card, style: .continuous))
            HStack(alignment: .top, spacing: 16) {
                PosterView(url: entry.title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                    .frame(width: compact ? 96 : 140)
                    .edgeLit(cornerRadius: AaruRadius.field)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title.title)
                        .font(.aaruDisplay(.title, weight: .semibold))
                        .foregroundStyle(Color(.ink))
                        // A long name at accessibility sizes wraps instead of truncating.
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(meta)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Color(.muted))
                    if let progress = entry.progress, progress.airedCount > 0 {
                        ProgressView(value: Double(progress.watchedCount), total: Double(progress.airedCount)) {
                            Text("\(progress.watchedCount) of \(progress.airedCount) episodes")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Color(.muted))
                        }
                    }
                }
                .padding(.top, overlap + AaruSpace.small)
            }
            .padding(.horizontal, compact ? AaruSpace.medium : AaruSpace.xxlarge)
            .padding(.top, -overlap)
        }
    }
}

/// Rating, owned, the book's page and the notes: the user's own layer of the title.
struct TitleYourLayer: View {
    let model: TitleDetailModel
    @Binding var notes: String
    @Binding var page: String

    private enum Field {
        case page, chapter, volume, notes
    }

    @FocusState private var focus: Field?
    /// Manga only (MNG-001): the last chapter and volume read, as typed.
    @State private var chapter = ""
    @State private var volume = ""

    private var entry: LibraryEntry {
        model.entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Rating") {
                RatingStars(rating: entry.rating) { rating in
                    Task { await setRating(rating) }
                }
            }
            Divider()
            Toggle("Owned", isOn: ownedBinding)
            if entry.title._type == .book {
                Divider()
                LabeledContent("Page") {
                    TextField("Page", text: $page)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($focus, equals: .page)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                        .onSubmit { Task { await savePage() } }
                }
            }
            if entry.title._type == .manga {
                Divider()
                countField("Chapter", text: $chapter, total: entry.title.chapterCount, field: .chapter)
                countField("Volume", text: $volume, total: entry.title.volumeCount, field: .volume)
            }
        }
        .panel()
        .onAppear {
            chapter = entry.mangaProgress?.chapter.map(String.init) ?? ""
            volume = entry.mangaProgress?.volume.map(String.init) ?? ""
        }
        // The number pad has no Return: the page saves when the field lets go (UX-070).
        .onChange(of: focus) { old, _ in
            switch old {
            case .page: Task { await savePage() }
            case .chapter, .volume: Task { await saveMangaProgress() }
            default: break
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        #endif

        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").eyebrow()
                .accessibilityAddTraits(.isHeader)
            TextField("Anything worth remembering", text: $notes, axis: .vertical)
                .lineLimit(3 ... 8)
                .focused($focus, equals: .notes)
            if notes != (entry.notes ?? "") {
                Button("Save note") { Task { await saveNotes() } }
                    .buttonStyle(.bordered)
            }
        }
        .panel()
    }

    private func countField(_ label: String, text: Binding<String>, total: Int?, field: Field) -> some View {
        LabeledContent {
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focus, equals: field)
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
                .onSubmit { Task { await saveMangaProgress() } }
        } label: {
            Text(label)
            if let total {
                Text("of \(total)")
            }
        }
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

    /// Saves a changed chapter or volume; an emptied field leaves its number as it was.
    private func saveMangaProgress() async {
        let current = entry.mangaProgress
        let newChapter = Int(chapter.filter(\.isNumber)).flatMap { $0 == current?.chapter ? nil : $0 }
        let newVolume = Int(volume.filter(\.isNumber)).flatMap { $0 == current?.volume ? nil : $0 }
        if newChapter != nil || newVolume != nil {
            await model.update(.init(mangaChapter: newChapter, mangaVolume: newVolume)) { entry in
                entry.mangaProgress = .init(
                    chapter: newChapter ?? current?.chapter,
                    volume: newVolume ?? current?.volume
                )
            }
        }
        chapter = entry.mangaProgress?.chapter.map(String.init) ?? ""
        volume = entry.mangaProgress?.volume.map(String.init) ?? ""
    }

    /// Saves only a changed number; an unchanged or emptied field leaves the page as it was.
    private func savePage() async {
        guard let number = Int(page.filter(\.isNumber)) else {
            page = entry.bookProgress?.page.map(String.init) ?? ""
            return
        }
        guard number != entry.bookProgress?.page else { return }
        await model.update(.init(bookPage: number)) { $0.bookProgress = .init(page: number) }
        page = entry.bookProgress?.page.map(String.init) ?? page
    }
}

/// The catalog's synopsis, when it has one.
struct TitleAbout: View {
    let synopsis: String?

    var body: some View {
        if let synopsis, !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").eyebrow()
                    .accessibilityAddTraits(.isHeader)
                Text(synopsis)
                    .font(.callout)
                    .foregroundStyle(Color(.ink).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .panel()
        }
    }
}

/// The season map, then each season's episodes. Only the expanded seasons list their episodes.
struct TitleSeasons: View {
    let model: TitleDetailModel
    @Binding var expanded: Set<Int>
    let onOpen: (EpisodeKey) -> Void
    let retry: () async -> Void

    var body: some View {
        if model.title != nil {
            if !model.orderedSeasons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Episodes").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    SeasonMap(model: model, onOpen: onOpen)
                        .panel()
                    ForEach(model.orderedSeasons, id: \.number) { season in
                        SeasonSection(
                            season: season, model: model, isExpanded: expansion(of: season.number), onOpen: onOpen
                        )
                    }
                }
            }
        } else if model.loadFailed {
            LoadFailedView(title: "Episodes didn't load", message: "Aaru could not reach the server.", retry: retry)
                .panel()
        } else {
            ProgressView().frame(maxWidth: .infinity).panel()
        }
    }

    private func expansion(of season: Int) -> Binding<Bool> {
        Binding(get: { expanded.contains(season) }, set: { isExpanded in
            if isExpanded {
                expanded.insert(season)
            } else {
                expanded.remove(season)
            }
        })
    }
}
