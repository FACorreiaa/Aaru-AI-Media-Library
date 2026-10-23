import SwiftUI

/// The "Concerts near" city picker (MUS-003): type two letters or more, pick a city, and it is
/// saved. Opened from Settings and from Discover's Concerts view. The search goes to Open-Meteo
/// through Aaru, a short pause after the last keystroke.
struct ConcertPlacePicker: View {
    let model: ConcertsModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var results: [ConcertPlace] = []
    @State private var searched = ""
    @State private var isSearching = false
    @State private var failed = false
    @State private var saving: ConcertPlace?

    private static let minimum = 2

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.key) { place in
                Button {
                    Task { await choose(place) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(Color(.ink))
                            if let detail = place.detail {
                                Text(detail).font(.subheadline).foregroundStyle(Color(.muted))
                            }
                        }
                        Spacer(minLength: 0)
                        if saving == place {
                            ProgressView()
                        } else if place == model.savedPlace {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(.accent))
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(saving != nil)
                .accessibilityLabel(place.label)
                .accessibilityAddTraits(place == model.savedPlace ? .isSelected : [])
            }
            .paperPage()
            .overlay { overlay }
            #if os(iOS)
                .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "City")
                .navigationBarTitleDisplayMode(.inline)
            #else
                .searchable(text: $text, prompt: "City")
            #endif
                .task(id: trimmed) { await search(trimmed) }
                .navigationTitle("Concerts near")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    @ViewBuilder private var overlay: some View {
        if trimmed.count < Self.minimum {
            ContentUnavailableView(
                "Search for a city",
                systemImage: "building.2",
                description: Text("Aaru keeps only the city you pick, to look for concerts around it.")
            )
        } else if failed {
            ContentUnavailableView(
                "City search isn't answering",
                systemImage: "wifi.exclamationmark",
                description: Text("Try again in a moment.")
            )
        } else if results.isEmpty, isSearching || searched != trimmed {
            ProgressView()
        } else if results.isEmpty {
            ContentUnavailableView.search
        }
    }

    private func search(_ query: String) async {
        guard query.count >= Self.minimum else {
            results = []
            searched = ""
            failed = false
            return
        }
        // A pause after the last keystroke; typing on cancels this and starts again.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let found = await model.searchPlaces(query)
        guard !Task.isCancelled else { return }
        failed = found == nil
        results = found ?? []
        searched = query
    }

    private func choose(_ place: ConcertPlace) async {
        saving = place
        defer { saving = nil }
        if await model.choose(place) {
            dismiss()
        }
    }
}
