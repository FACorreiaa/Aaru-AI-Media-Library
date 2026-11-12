import AaruAPI
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A file on its way into the next turn (ASK-010): being read by the server while `file` is nil.
struct AssistantChip: Identifiable, Equatable {
    let id: UUID
    var name: String
    var file: ChatFile?
}

/// The files the next Chat turn carries (ASK-010). Each goes to the chat as soon as it is picked,
/// so its chip can say what the server read it as; the server is the judge of what is inside.
@MainActor
@Observable
final class AssistantFiles {
    /// Files one turn carries; the server holds the same limit.
    static let maxPerTurn = 5
    /// A paste longer than a typed question goes as a text file instead.
    static let pasteAsFile = 4000
    /// The largest file the API reads: a listening history.
    static let maxBytes = 24 << 20

    /// What the file picker offers.
    static let pickable: [UTType] = [
        .commaSeparatedText, .tabSeparatedText, .plainText, .text, .xml, .gzip, .json, .pdf, .calendarEvent, .image,
    ] + [UTType(filenameExtension: "md"), UTType(filenameExtension: "ics")].compactMap(\.self)

    private(set) var chips: [AssistantChip] = []
    /// Why the last file was refused, or nil.
    private(set) var problem: String?

    @ObservationIgnored private let thread: ChatThread?
    /// Bumped by `clear()`, so an upload still in flight adds nothing afterwards.
    @ObservationIgnored private var token = 0

    init(thread: ChatThread?) {
        self.thread = thread
    }

    /// Whether a file is still being read: the turn waits for it.
    var isReading: Bool {
        chips.contains { $0.file == nil }
    }

    var ready: [ChatFile] {
        chips.compactMap(\.file)
    }

    var isFull: Bool {
        chips.count >= Self.maxPerTurn
    }

    /// The files read so far, for the turn being sent; the chips empty.
    func take() -> [ChatFile] {
        let files = ready
        chips = []
        problem = nil
        return files
    }

    /// The chat ended, the account changed, or the user deleted their chats.
    func clear() {
        token += 1
        chips = []
        problem = nil
    }

    func show(_ problem: String) {
        self.problem = problem
    }

    /// One file, sent to the chat now.
    func attach(_ data: Data, name: String) {
        guard let thread, room(for: 1) else { return }
        let chip = AssistantChip(id: UUID(), name: name.isEmpty ? String(localized: "Pasted text") : name)
        chips.append(chip)
        problem = nil
        let started = token
        Task { [weak self] in
            let result = await thread.attach(data, name: name)
            guard let self, started == token, let index = chips.firstIndex(where: { $0.id == chip.id }) else { return }
            switch result {
            case let .attached(_, file):
                chips[index].file = file
                chips[index].name = file.name
            case let .refused(reason):
                chips.remove(at: index)
                problem = "\(chip.name): \(reason)"
            }
        }
    }

    /// A picture, as capture sends it: shrunk to JPEGs, a tall screenshot in pieces.
    func attachPicture(_ data: Data, name: String) {
        switch CaptureImage.pieces(data) {
        case let .jpegs(jpegs):
            guard room(for: jpegs.count) else { return }
            for (index, jpeg) in jpegs.enumerated() {
                attach(jpeg, name: jpegs.count > 1 ? "\(name) (\(index + 1) of \(jpegs.count)).jpg" : "\(name).jpg")
            }
        case .tooLong:
            problem = String(localized: "That picture is too long. Paste the text instead.")
        case .unreadable:
            problem = String(localized: "Aaru could not open that picture.")
        }
    }

    /// A paste too long to be a question, as a text file.
    func attachPasted(_ text: String) {
        attach(Data(text.utf8), name: "")
    }

    /// Photos from the picker.
    func attachPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                problem = String(localized: "Aaru could not open that picture.")
                return
            }
            attachPicture(data, name: "Picture")
        }
    }

    /// Files from the picker or a drop: pictures shrunk as capture does, anything else as it is.
    func attachFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maxBytes, let data = try? Data(contentsOf: url) else {
                problem = String(localized: "\(url.lastPathComponent) could not be read, or is larger than 24 MB.")
                continue
            }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                attachPicture(data, name: url.deletingPathExtension().lastPathComponent)
            } else {
                attach(data, name: url.lastPathComponent)
            }
        }
    }

    func remove(_ id: UUID) {
        guard let index = chips.firstIndex(where: { $0.id == id }) else { return }
        let chip = chips.remove(at: index)
        guard let file = chip.file, let thread else { return }
        Task {
            if let chat = await thread.current() {
                await thread.detach(chat: chat, id: file.id)
            }
        }
    }

    private func room(for count: Int) -> Bool {
        guard chips.count + count <= Self.maxPerTurn else {
            problem = String(localized: "Send up to \(Self.maxPerTurn) files at a time.")
            return false
        }
        return true
    }
}

/// The paperclip beside the field: photos or files.
struct AssistantAttachMenu: View {
    let files: AssistantFiles
    let disabled: Bool

    @State private var photos: [PhotosPickerItem] = []
    @State private var pickingPhotos = false
    @State private var pickingFiles = false

    var body: some View {
        Menu {
            Button("Photos", systemImage: "photo") { pickingPhotos = true }
            Button("Files", systemImage: "folder") { pickingFiles = true }
        } label: {
            Label("Attach a file", systemImage: "paperclip")
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .hoverInk()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(disabled || files.isFull)
        .help("Attach a file")
        .photosPicker(
            isPresented: $pickingPhotos,
            selection: $photos,
            maxSelectionCount: max(1, AssistantFiles.maxPerTurn - files.chips.count),
            matching: .images
        )
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await files.attachPhotos(items)
                photos = []
            }
        }
        .fileImporter(
            isPresented: $pickingFiles,
            allowedContentTypes: AssistantFiles.pickable,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                files.attachFiles(urls)
            }
        }
    }
}

/// The files the next turn carries, each with what Aaru read it as and a remove button.
struct AssistantFileChips: View {
    let files: AssistantFiles

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AaruSpace.xsmall) {
                ForEach(files.chips) { chip in
                    HStack(spacing: AaruSpace.xsmall) {
                        if chip.file == nil {
                            ProgressView().controlSize(.mini)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(chip.name)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(.ink))
                            Text(chip.file?.summary ?? String(localized: "Reading…"))
                                .font(.caption)
                                .foregroundStyle(Color(.muted))
                        }
                        .lineLimit(1)
                        Button {
                            files.remove(chip.id)
                        } label: {
                            Label("Remove \(chip.name)", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color(.muted))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        // The chip's padding is part of the target, so the chip stays slim.
                        .padding(.vertical, -AaruSpace.xsmall)
                    }
                    .padding(.leading, AaruSpace.small)
                    .padding(.vertical, AaruSpace.xsmall)
                    .field()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
