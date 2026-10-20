import AaruAPI
import SwiftUI

extension Components.Schemas.ChannelKind {
    var label: String {
        switch self {
        case .text: "Text"
        case .title: "Title"
        case .watch: "Watch party"
        case .shelf: "Shelf"
        }
    }

    /// One line for the kind picker.
    var explanation: String {
        switch self {
        case .text: "Talk about anything."
        case .title: "One film, show or book. Spoilers stay hidden from anyone behind."
        case .watch: "Start watching together, with a shared countdown."
        case .shelf: "A list of titles everyone in the group adds to."
        }
    }

    var symbol: String {
        switch self {
        case .text: "number"
        case .title: "film.stack"
        case .watch: "play.rectangle"
        case .shelf: "books.vertical"
        }
    }
}

/// A new channel: its kind, then a name (a title channel takes its title's) and topic.
struct NewChannelSheet: View {
    let groups: GroupsModel
    let groupID: String
    let onCreated: (GroupChannel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind = ChannelKind.text
    @State private var name = ""
    @State private var topic = ""
    @State private var title: CatalogHit?
    @State private var picksTitle = false
    @State private var saving = false

    private var canSave: Bool {
        kind == .title ? title != nil : !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kind") {
                    ForEach(ChannelKind.allCases, id: \.self) { option in
                        Button {
                            kind = option
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.symbol)
                                    .frame(width: 24)
                                    .foregroundStyle(Color(.accent))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                    Text(option.explanation).font(.caption).foregroundStyle(Color(.muted))
                                }
                                Spacer(minLength: 8)
                                if kind == option {
                                    Image(systemName: "checkmark").foregroundStyle(Color(.accent))
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(kind == option ? .isSelected : [])
                    }
                }
                if kind == .title {
                    Section("Title") {
                        Button(title?.title ?? "Choose a title…", systemImage: "magnifyingglass") { picksTitle = true }
                    }
                }
                Section {
                    HStack(spacing: 2) {
                        Text("#").foregroundStyle(Color(.muted))
                        TextField(
                            kind == .title ? (title?.title ?? "Named after the title") : "movie-night",
                            text: $name
                        )
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    }
                    TextField("Topic (optional)", text: $topic, axis: .vertical)
                        .lineLimit(1 ... 3)
                } footer: {
                    Text("Lowercase, with dashes for spaces.")
                }
                if let problem = groups.problem {
                    Text(problem).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: save).disabled(saving || !canSave)
                }
            }
            .sheet(isPresented: $picksTitle) {
                TitlePickerSheet(api: groups.api, navigationTitle: "Choose a title") { hit in
                    title = hit
                    return true
                }
            }
        }
        .onAppear { groups.problem = nil }
    }

    private func save() {
        Task {
            saving = true
            defer { saving = false }
            if let created = await groups.createChannel(
                in: groupID, kind: kind, name: name, topic: topic, title: kind == .title ? title?.mediaRef : nil
            ) {
                dismiss()
                onCreated(created)
            }
        }
    }
}

/// A channel's mark on a list: `#` for text, the poster for a title, a symbol for the others.
struct ChannelKindMark: View {
    let channel: GroupChannel

    var body: some View {
        if channel.kind == .title, let title = channel.title {
            PosterThumb(url: title.posterURL, kind: title.mediaKind)
        } else {
            Image(systemName: channel.kind.symbol)
                .foregroundStyle(Color(.muted))
                .accessibilityHidden(true)
        }
    }
}

private struct PosterThumb: View {
    let url: URL?
    let kind: MediaKind

    var body: some View {
        PosterView(url: url, kind: kind)
            .frame(width: 14)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .accessibilityHidden(true)
    }
}
