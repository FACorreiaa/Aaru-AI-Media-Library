import PhotosUI
import SwiftUI

/// DESIGN §1 and §11: the Field's one composer. Paste a list or a link, or pick screenshots;
/// Aaru reads them into an import the user reviews before anything is added (AG-006). Books passes
/// its kind: only books are read, and the words say so (BOOK-001).
struct CaptureComposer: View {
    let imports: ImportsModel
    var kind: MediaKind?
    /// The capture was taken: the page opens its review.
    var onStarted: (ImportJob) -> Void

    @State private var text = ""
    @State private var photos: [PhotosPickerItem] = []
    /// The picked pictures, already shrunk to the JPEGs that are sent.
    @State private var pictures: [Data] = []
    @State private var sending = false
    @State private var problem: String?

    private var placeholder: String {
        switch (kind == .book, pictures.isEmpty) {
        case (true, true): "Paste a chat or list, or ask for books"
        case (true, false): "Aaru reads the books in the picture"
        case (false, true): "Paste titles, a link or a screenshot"
        case (false, false): "Aaru reads the titles in the picture"
        }
    }

    private var hint: String {
        kind == .book
            ? "A whole ChatGPT chat, screenshots, a photo of a list, or a request like "
            + "\u{201C}X-Men books in reading order\u{201D}. Nothing is added until you approve."
            : "Nothing is added until you approve what Aaru found."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if !pictures.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(Array(pictures.enumerated()), id: \.offset) { index, jpeg in
                            preview(jpeg, at: index)
                        }
                    }
                    .padding(.top, 10)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(1 ... 6)
                        .disabled(sending || !pictures.isEmpty)
                        .padding(.vertical, AaruSpace.medium)
                        .accessibilityLabel("Capture")
                    PhotosPicker(
                        selection: $photos,
                        maxSelectionCount: max(1, CaptureImage.maxPictures - pictures.count),
                        matching: .images
                    ) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .foregroundStyle(Color(.muted))
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || pictures.count >= CaptureImage.maxPictures)
                    .accessibilityLabel("Add a screenshot")
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .disabled(!canSend)
                }
            }
            .padding(.leading, AaruSpace.large)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            Text(problem ?? hint)
                .font(.footnote)
                .foregroundStyle(problem == nil ? Color(.muted) : Color(.danger))
        }
        .onChange(of: photos) { _, items in Task { await load(items) } }
    }

    private var canSend: Bool {
        !sending && (!pictures.isEmpty || CaptureContent(typed: text) != nil)
    }

    private func preview(_ jpeg: Data, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = CaptureImage.thumbnail(jpeg, maxPixels: 144) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: AaruRadius.field, style: .continuous))
            }
            Button("Remove the picture", systemImage: "xmark.circle.fill") {
                pictures.remove(at: index)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(Color(.ink))
            .offset(x: 6, y: -6)
        }
    }

    /// Adds what was picked, in order, and clears the picker so the next pick adds to these.
    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        problem = nil
        defer { photos = [] }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                problem = "Aaru could not open that picture."
                return
            }
            switch CaptureImage.pieces(data) {
            case let .jpegs(jpegs) where pictures.count + jpegs.count <= CaptureImage.maxPictures:
                pictures += jpegs
            case .jpegs, .tooLong:
                problem = "That's long. Paste the text instead."
                return
            case .unreadable:
                problem = "Aaru could not open that picture."
                return
            }
        }
    }

    private func send() async {
        let content = pictures.isEmpty ? CaptureContent(typed: text) : .images(pictures)
        guard let content else { return }
        sending = true
        problem = nil
        defer { sending = false }
        switch await imports.capture(content, kind: kind) {
        case let .started(job):
            text = ""
            pictures = []
            onStarted(job)
        case let .failed(message):
            problem = message
        }
    }
}
