import PhotosUI
import SwiftUI

/// DESIGN §1 and §11: the Field's one composer. Paste a list or a link, or pick a screenshot;
/// Aaru reads it into an import the user reviews before anything is added (AG-006).
struct CaptureComposer: View {
    let imports: ImportsModel
    /// The capture was taken: Home opens its review.
    var onStarted: (ImportJob) -> Void

    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    /// The picked picture, already shrunk to the JPEG that is sent.
    @State private var picture: Data?
    @State private var sending = false
    @State private var problem: String?
    @State private var quota: String?
    /// The paywall, opened with the server's quota line (BIL-004).
    @State private var paywallReason: String?
    /// Nil in previews; the quota then shows as an alert.
    @Environment(PlusModel.self) private var plus: PlusModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                if let picture {
                    preview(picture)
                }
                TextField(
                    picture == nil ? "Paste titles, a link or a screenshot" : "Aaru reads the titles in the picture",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1 ... 6)
                .disabled(sending || picture != nil)
                .padding(.vertical, 11)
                .accessibilityLabel("Capture")
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color(.muted))
                }
                .buttonStyle(.plain)
                .disabled(sending)
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
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.surface), in: .rect(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(.line), lineWidth: 1)
            }
            Text(problem ?? "Nothing is added until you approve what Aaru found.")
                .font(.footnote)
                .foregroundStyle(problem == nil ? Color(.muted) : Color(.danger))
        }
        .onChange(of: photo) { _, item in Task { await load(item) } }
        .sheet(isPresented: Binding(get: { paywallReason != nil }, set: {
            if !$0 {
                paywallReason = nil
            }
        })) {
            if let plus {
                PlusPaywall(plus: plus, reason: paywallReason)
            }
        }
        .alert(
            "This month's captures are used",
            isPresented: Binding(get: { quota != nil }, set: {
                if !$0 {
                    quota = nil
                }
            }),
            presenting: quota
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var canSend: Bool {
        !sending && (picture != nil || CaptureContent(typed: text) != nil)
    }

    private func preview(_ jpeg: Data) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = CaptureImage.thumbnail(jpeg, maxPixels: 144) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
            }
            Button("Remove the picture", systemImage: "xmark.circle.fill") {
                picture = nil
                photo = nil
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(Color(.ink))
            .offset(x: 6, y: -6)
        }
        .padding(.vertical, 6)
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        problem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = CaptureImage.jpeg(data)
        else {
            problem = "Aaru could not open that picture."
            return
        }
        picture = jpeg
    }

    private func send() async {
        let content: CaptureContent? = picture.map(CaptureContent.image) ?? CaptureContent(typed: text)
        guard let content else { return }
        sending = true
        problem = nil
        defer { sending = false }
        switch await imports.capture(content) {
        case let .started(job):
            text = ""
            picture = nil
            photo = nil
            onStarted(job)
        case let .quota(message):
            if plus == nil {
                quota = message
            } else {
                paywallReason = message
            }
        case let .failed(message):
            problem = message
        }
    }
}
