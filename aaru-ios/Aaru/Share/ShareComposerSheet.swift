import AaruAPI
import SwiftUI

/// What a share link points at (SHR-002): a title by reference, or a provider's event id.
enum ShareTarget: Hashable {
    case title(MediaRef)
    case sportEvent(id: String)
    case concert(id: String)

    var input: Components.Schemas.ShareTargetInput {
        switch self {
        case let .title(ref): .init(kind: .title, ref: ref)
        case let .sportEvent(id): .init(kind: .sportEvent, id: id)
        case let .concert(id): .init(kind: .concert, id: id)
        }
    }
}

/// Making a share link, in two steps: an optional note only friends see, then the link with the
/// share sheet and Copy link. The same target and note give back the same link.
struct ShareComposerSheet: View {
    let api: Client?
    let target: ShareTarget
    let name: String

    static let noteLimit = 140

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var link: URL?
    @State private var creating = false
    @State private var copied = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(name)
                        .font(.aaruDisplay(.title2, weight: .semibold))
                        .foregroundStyle(Color(.ink))
                        .fixedSize(horizontal: false, vertical: true)
                    if let link {
                        made(link)
                    } else {
                        compose
                    }
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(Color(.danger))
                    }
                }
                .padding(20)
                .frame(maxWidth: 480, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.paper))
            .navigationTitle("Share")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .padding(12)
                    .field()
                    .onChange(of: note) { _, text in
                        if text.count > Self.noteLimit {
                            note = String(text.prefix(Self.noteLimit))
                        }
                    }
                Text("Only your friends see this note")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            Button {
                Task { await create() }
            } label: {
                Text(creating ? "Creating…" : "Create link")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(creating)
        }
    }

    private func made(_ link: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(link.absoluteString)
                .font(.callout.monospaced())
                .foregroundStyle(Color(.ink))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .well()
            HStack(spacing: 12) {
                ShareLink(item: link, message: Text(name)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button {
                    copy(link)
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Text("Anyone with the link sees it. Only your friends see that you sent it.")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        }
    }

    private func create() async {
        guard let api, !creating else { return }
        creating = true
        problem = nil
        defer { creating = false }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch try await api.createShare(
                body: .json(.init(target: target.input, note: text.isEmpty ? nil : text))
            ) {
            case let .ok(response):
                link = try URL(string: response.body.json.url)
                if link == nil {
                    problem = "The link could not be made."
                }
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The link could not be made."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }

    private func copy(_ link: URL) {
        Pasteboard.copy(link.absoluteString)
        copied = true
    }
}
