import AaruAPI
import SwiftUI

/// A new party: the title, and what it is for. A show needs its episode; a manga can carry a
/// chapter and volume and a book a page, each optional (ROOM-005).
struct OpenPartySheet: View {
    let api: Client?
    let onOpen: (Components.Schemas.MediaRef, PartyTarget) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: CatalogHit?
    @State private var picksTitle = false
    @State private var season = 1
    @State private var episode = 1
    @State private var chapter: Int?
    @State private var volume: Int?
    @State private var page: Int?
    @State private var saving = false

    private var isShow: Bool {
        title?._type == .show
    }

    private var isReading: Bool {
        title?._type == .manga || title?._type == .book
    }

    /// The target for the picked title's kind; fields of another kind are left out.
    private var target: PartyTarget {
        switch title?._type {
        case .show: PartyTarget(season: season, episode: episode)
        case .manga: PartyTarget(chapter: chapter, volume: volume)
        case .book: PartyTarget(page: page)
        default: PartyTarget()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you watching or reading?") {
                    Button(title?.title ?? String(localized: "Choose a title…"), systemImage: "magnifyingglass") {
                        picksTitle = true
                    }
                }
                if isShow {
                    Section("Episode") {
                        Stepper("Season \(season)", value: $season, in: 0 ... 99)
                        Stepper("Episode \(episode)", value: $episode, in: 1 ... 999)
                    }
                }
                if title?._type == .manga {
                    Section("Read to") {
                        numberRow(String(localized: "Chapter"), value: $chapter)
                        numberRow(String(localized: "Volume"), value: $volume)
                    }
                }
                if title?._type == .book {
                    Section("Read to") {
                        numberRow(String(localized: "Page"), value: $page)
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text(isReading
                        ? String(
                            localized: """
                            Everyone reads on their own. When the host \
                            ends, it is marked for everyone who joined.
                            """
                        )
                        : String(localized: """
                        Everyone presses play on their own screen when the countdown reaches zero. \
                        When the host ends, it is marked for everyone who joined.
                        """))
                }
            }
            .paperPage()
            .navigationTitle(isReading ? "Reading session" : "Watch party")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: open).disabled(title == nil || saving)
                }
            }
            .sheet(isPresented: $picksTitle) {
                TitlePickerSheet(api: api, navigationTitle: String(localized: "Choose a title")) { hit in
                    title = hit
                    return true
                }
            }
        }
    }

    /// An optional whole number, typed: blank leaves the target out.
    private func numberRow(_ label: String, value: Binding<Int?>) -> some View {
        LabeledContent(label) {
            TextField("Optional", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
        }
    }

    private func open() {
        guard let title else { return }
        Task {
            saving = true
            defer { saving = false }
            if await onOpen(title.mediaRef, target) {
                dismiss()
            }
        }
    }
}
