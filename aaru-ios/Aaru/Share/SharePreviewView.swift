import AaruAPI
import AaruCore
import SwiftUI

typealias ShareLinkPreview = Components.Schemas.SharePreview

/// A share link opened in the app (SHR-002), signed in or out: who sent it (friends only), the
/// shared title, match or concert, and one action. The web shows the same postcard at /s/{code}.
struct SharePreviewView: View {
    let api: Client?
    let link: SharedLink
    let library: LibraryModel
    let lists: ListsModel
    /// Signed out: hands the link back (with `add` set for a title) to reopen after sign-in.
    let onSignIn: (SharedLink) -> Void

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case loading
        case missing
        case ready(ShareLinkPreview)
    }

    @State private var stage = Stage.loading
    @State private var adding = false
    @State private var autoAdded = false
    @State private var problem: String?
    @State private var openItem: String?
    @State private var openEvent: SharedEvent?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 480, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.paper))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(item: $openItem) { id in
                LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
            }
        }
        .sheet(item: $openEvent) { event in
            SportEventDetailView(model: SportsModel(api: api), id: event.id)
        }
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .missing:
            ContentUnavailableView(
                "This link doesn't work",
                systemImage: "link",
                description: Text("Ask whoever sent it for a new one.")
            )
        case let .ready(preview):
            if let from = preview.from {
                ShareSenderLine(sender: from)
            }
            if preview.unavailable {
                ContentUnavailableView(
                    preview.kind == .concert
                        ? "This concert's details aren't available right now"
                        : "This match isn't available right now",
                    systemImage: preview.kind == .concert ? "music.mic" : "sportscourt",
                    description: Text("Try the link again later.")
                )
            } else if let title = preview.title {
                ShareTitleCard(title: title)
                titleAction(preview, title: title)
            } else if let event = preview.sportEvent {
                EventHeader(event: event)
                eventAction(event)
            } else if let concert = preview.concert {
                ConcertRow(concert: concert)
                if !session.isSignedIn {
                    signInButton("Concerts near you on Aaru", link: link)
                }
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Color(.danger))
            }
            if let about = URL(string: "https://aaruapp.com/") {
                Link("What is Aaru?", destination: about)
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
    }

    @ViewBuilder private func titleAction(_ preview: ShareLinkPreview, title: TitleDetail) -> some View {
        let kind = MediaKind(type: title._type, isAnime: title.isAnime)
        if let itemID = preview.libraryItemId {
            HStack(spacing: 12) {
                Text(inLibrary(preview.status, kind: kind))
                    .foregroundStyle(Color(.muted))
                Spacer(minLength: 8)
                Button("Open") { openItem = itemID }
                    .buttonStyle(.bordered)
            }
        } else if session.isSignedIn {
            Button {
                Task { await add(title) }
            } label: {
                Text(adding ? "Adding…" : "Add to \(LibraryStatus.wishlist.label(for: kind))")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(adding)
        } else {
            signInButton("Add to my Aaru", link: link.addingTitle())
        }
    }

    @ViewBuilder private func eventAction(_ event: SportEvent) -> some View {
        if !session.isSignedIn {
            signInButton("Follow sports on Aaru", link: link)
        } else if router.sportsAvailable {
            Button {
                openEvent = SharedEvent(id: event.id)
            } label: {
                Text("Open in Sports").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    /// Closes onto Welcome; RootView reopens the link once the person is signed in.
    private func signInButton(_ label: String, link: SharedLink) -> some View {
        Button {
            onSignIn(link)
            dismiss()
        } label: {
            Text(label).frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// "In your library · Watching".
    private func inLibrary(_ status: LibraryStatus?, kind: MediaKind) -> String {
        guard let status else { return "In your library" }
        return "In your library · \(status.label(for: kind))"
    }

    private func load() async {
        guard let api else {
            stage = .missing
            return
        }
        do {
            guard case let .ok(response) = try await api.getSharePreview(path: .init(code: link.code)) else {
                stage = .missing
                return
            }
            let preview = try response.body.json
            stage = .ready(preview)
            if link.add, !autoAdded, let title = preview.title, ShareAutoAdd.should(
                add: link.add, signedIn: session.isSignedIn, isTitle: preview.kind == .title,
                unavailable: preview.unavailable, alreadyInLibrary: preview.libraryItemId != nil
            ) {
                autoAdded = true
                await add(title)
            }
        } catch {
            stage = .missing
        }
    }

    /// Plan to watch, the same write as a tap anywhere else; then the preview says it is theirs.
    private func add(_ title: TitleDetail) async {
        guard !adding else { return }
        adding = true
        problem = nil
        defer { adding = false }
        let ref = MediaRef(_type: title._type, ids: title.ids, title: title.title, year: title.year)
        if let failed = await library.add(ref, named: title.title, status: .wishlist, api: api) {
            problem = failed
            return
        }
        await load()
    }
}

/// A match to open from the share sheet, as a sheet item.
private struct SharedEvent: Identifiable {
    let id: String
}
