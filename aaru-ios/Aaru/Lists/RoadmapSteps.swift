import AaruAPI
import SwiftUI

typealias ListRoadmap = Components.Schemas.ListRoadmap
typealias RoadmapPlace = Components.Schemas.RoadmapPlace

/// GRAPH-003: a list the owl planned in steps, read as the server keeps it. Inside a step the list's
/// own order decides; a member no step names was added by hand and is shown last.
struct RoadmapSection: Identifiable {
    struct Entry: Identifiable {
        let item: ListItem
        let note: String?
        let optional: Bool
        let pair: Int?

        var id: String {
            item.title.id
        }
    }

    let id: Int
    let heading: String
    let note: String?
    let missing: [String]
    let entries: [Entry]

    static let addedByHand = String(localized: "Added by hand")

    static func sections(_ roadmap: ListRoadmap, items: [ListItem]) -> [RoadmapSection] {
        let key = { (id: String) in id.lowercased() }
        let byID = Dictionary(items.map { (key($0.title.id), $0) }, uniquingKeysWith: { first, _ in first })
        let position = Dictionary(
            items.enumerated().map { (key($1.title.id), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var placed: Set<String> = []
        var out: [RoadmapSection] = []
        for (index, step) in roadmap.steps.enumerated() {
            var entries: [Entry] = []
            for item in step.items {
                guard let member = byID[key(item.titleId)], placed.insert(key(item.titleId)).inserted else { continue }
                entries.append(Entry(item: member, note: item.note, optional: item.optional ?? false, pair: item.pair))
            }
            entries.sort { (position[key($0.id)] ?? 0) < (position[key($1.id)] ?? 0) }
            out.append(RoadmapSection(
                id: index, heading: step.heading, note: step.note, missing: step.missing ?? [], entries: entries
            ))
        }
        let loose = items.filter { !placed.contains(key($0.title.id)) }
        if !loose.isEmpty {
            out.append(RoadmapSection(
                id: out.count, heading: addedByHand, note: nil, missing: [],
                entries: loose.map { Entry(item: $0, note: nil, optional: false, pair: nil) }
            ))
        }
        return out.filter { !$0.entries.isEmpty || !$0.missing.isEmpty }
    }

    /// The first title in step order the person has not finished or dropped, optional ones skipped.
    @MainActor static func startHere(_ sections: [RoadmapSection], library: LibraryModel) -> String? {
        for section in sections {
            for entry in section.entries where !entry.optional {
                let status = (library.entry(forTitle: entry.item.title.id) ?? entry.item.entry)?.status
                if status != .finished, status != .dropped {
                    return entry.id
                }
            }
        }
        return nil
    }
}

extension ImportRow {
    /// ASK-011: the heading a review shows above the first row of each roadmap step ("1. Hickman
    /// FF"); nil for a row in the same step as the one before, or in no headed step.
    func stepHeading(after previous: ImportRow?) -> String? {
        guard let place = roadmap, place.step > 0, let heading = place.heading,
              previous?.roadmap?.step != place.step
        else { return nil }
        return "\(place.step). \(heading)"
    }
}

extension RoadmapPlace {
    /// "FF #1-5 · Optional": what the roadmap says of a review row, under its step's heading. A
    /// step with no heading keeps its number here.
    var line: String {
        [
            step > 0 && heading == nil ? String(localized: "Step \(String(step))") : nil,
            note,
            optional == true ? String(localized: "Optional: joins the list only") : nil,
            pair != nil ? String(localized: "Read side by side") : nil,
        ].compactMap(\.self).joined(separator: " · ")
    }
}

/// The steps, numbered, each title with its note, Optional and "Read side by side"; what Aaru could
/// not find stays as text in its step. Editing is the Order view's.
struct RoadmapStepsList: View {
    let sections: [RoadmapSection]
    let library: LibraryModel

    var body: some View {
        let start = RoadmapSection.startHere(sections, library: library)
        List {
            ForEach(Array(sections.enumerated()), id: \.element.id) { number, section in
                Section {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                        entryRow(
                            entry,
                            startHere: start == entry.id,
                            pairStarts: entry.pair != nil && section.entries[safe: index - 1]?.pair != entry.pair
                                && section.entries[safe: index + 1]?.pair == entry.pair
                        )
                        .listRowBackground(Color.clear)
                    }
                    if !section.missing.isEmpty {
                        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                            Text("Not found in Aaru's catalog:")
                            ForEach(section.missing, id: \.self) { Text("• \($0)") }
                        }
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(number + 1). \(section.heading)")
                            .font(.aaruDisplay(.title3, weight: .semibold))
                            .foregroundStyle(Color(.ink))
                        if let note = section.note {
                            Text(note).font(.footnote).foregroundStyle(Color(.muted))
                        }
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private func entryRow(_ entry: RoadmapSection.Entry, startHere: Bool, pairStarts: Bool) -> some View {
        let label = VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            ListItemRow(item: entry.item)
            if let note = entry.note {
                Text(note).font(.footnote).foregroundStyle(Color(.muted))
            }
            HStack(spacing: AaruSpace.xsmall) {
                if startHere {
                    tag(String(localized: "Start here"), strong: true)
                }
                if entry.optional {
                    tag(String(localized: "Optional"))
                }
                if pairStarts {
                    tag(String(localized: "Read side by side"))
                }
            }
        }
        .padding(.leading, entry.pair == nil ? 0 : AaruSpace.small)
        .overlay(alignment: .leading) {
            if entry.pair != nil {
                Rectangle().fill(Color(.accent)).frame(width: 2)
            }
        }
        if let item = library.entry(forTitle: entry.item.title.id) ?? entry.item.entry {
            NavigationLink(value: ListMemberRoute(libraryItemID: item.id)) { label }
        } else {
            NavigationLink(value: CatalogRoute(hit: CatalogHit(entry.item.title))) { label }
        }
    }

    private func tag(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(strong ? Color(.ink) : Color(.ink).opacity(AaruAlpha.tint), in: Capsule())
            .foregroundStyle(strong ? Color(.paper) : Color(.ink))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// GRAPH-004: a roadmap list as a graph, in a sheet: its titles left to right in step order, titles
/// read side by side in one column, optional ones hanging under the title before them. A title opens
/// its page inside the sheet.
struct ListGraphSheet: View {
    let api: Client?
    let listID: String
    let library: LibraryModel
    let lists: ListsModel

    @State private var graph: RelationGraph?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let graph {
                    RelationGraphCanvas(graph: graph)
                } else if failed {
                    ContentUnavailableView("The graph could not be loaded", systemImage: "wifi.slash")
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("In order")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .catalogDestination(api: api, library: library, lists: lists)
        }
        .task { await load() }
        #if os(macOS)
            .frame(minWidth: 720, minHeight: 520)
        #endif
    }

    private func load() async {
        guard let api else { return }
        do {
            if case let .ok(response) = try await api.getListGraph(path: .init(id: listID)) {
                graph = try response.body.json
                return
            }
        } catch {}
        failed = true
    }
}
