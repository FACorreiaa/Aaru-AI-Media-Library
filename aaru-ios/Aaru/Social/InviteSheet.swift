import AaruAPI
import SwiftUI

typealias InvitePreview = Components.Schemas.InvitePreview

/// A friend invite opened from its link (SOC-002): who sent it and the title it carries, then
/// one tap to become friends. The web shows the same letter at aaruapp.com/i/{code}.
struct InviteSheet: View {
    let api: Client?
    let link: InviteLink
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case loading
        case invalid
        case ready(InvitePreview)
        case done(name: String, note: String)
    }

    @State private var stage = Stage.loading
    @State private var needsHandle = false
    @State private var handle = ""
    @State private var addTitle = true
    @State private var accepting = false
    @State private var problem: String?

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
        }
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .invalid:
            ContentUnavailableView(
                "This invite isn't valid anymore",
                systemImage: "envelope.badge",
                description: Text("Invites work once and last two weeks. Ask your friend for a new link.")
            )
        case let .done(name, note):
            ContentUnavailableView {
                Label("You and \(name) are friends", systemImage: "person.2.fill")
            } description: {
                Text(note)
            } actions: {
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        case let .ready(preview):
            switch preview.relationship {
            case ._self?:
                ContentUnavailableView(
                    "This is your invite",
                    systemImage: "envelope.open",
                    description: Text("Send it to a friend. It works once, for the first person who opens it.")
                )
            case .friend?:
                ContentUnavailableView(
                    "You and \(preview.inviter.inviteName) are already friends",
                    systemImage: "person.2"
                )
            default:
                letter(preview)
            }
        }
    }

    private func letter(_ preview: InvitePreview) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            InviteMedallion()
                .frame(width: 112)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(preview.inviter.inviteName) invited you to Aaru.")
                    .font(.aaruDisplay(.largeTitle))
                    .fixedSize(horizontal: false, vertical: true)
                if preview.inviter.displayName != nil {
                    Text("@\(preview.inviter.handle)").foregroundStyle(Color(.muted))
                }
            }
            if let title = preview.title {
                InviteTitleOffer(title: title, addTitle: $addTitle)
            }
            if needsHandle {
                InviteHandleField(inviter: preview.inviter.inviteName, handle: $handle)
            }
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task { await accept(preview) }
                } label: {
                    Text(accepting ? "Adding…" : "Add \(preview.inviter.inviteName) as a friend")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accepting)
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Color(.danger))
                }
                Text("Your library stays private: only friends see it.")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
    }

    private func load() async {
        guard let api else { return }
        do {
            async let previewCall = api.getInvitePreview(path: .init(code: link.code))
            async let meCall = api.getMe()
            guard case let .ok(response) = try await previewCall else {
                stage = .invalid
                return
            }
            if case let .ok(account) = try await meCall {
                needsHandle = (try? account.body.json.handle) == nil
            }
            stage = try .ready(response.body.json)
        } catch {
            stage = .invalid
        }
    }

    private func accept(_ preview: InvitePreview) async {
        guard let api, !accepting else { return }
        accepting = true
        problem = nil
        defer { accepting = false }
        if needsHandle {
            if let invalid = SocialModel.handleProblem(handle) {
                problem = invalid
                return
            }
            let body = Components.Schemas.ProfileUpdate(handle: SocialModel.normalized(handle))
            do {
                switch try await api.updateProfile(body: .json(body)) {
                case .ok: needsHandle = false
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "Your handle was not saved."
                    return
                }
            } catch {
                problem = "Aaru could not reach the server."
                return
            }
        }
        let wantsTitle = preview.title != nil && addTitle
        do {
            switch try await api.redeemFriendInvite(
                path: .init(code: link.code), body: .json(.init(addTitle: wantsTitle))
            ) {
            case let .ok(response):
                let result = try response.body.json
                var note = "You can now see each other's shelves."
                if result.titleAdded, let title = preview.title {
                    let kind = MediaKind(type: title._type, isAnime: title.isAnime)
                    note = "\(title.title) is on your \(LibraryStatus.wishlist.label(for: kind)). " + note
                }
                stage = .done(name: result.friend.inviteName, note: note)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The invite could not be accepted."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }
}

/// The title an invite carries, in the sender's voice, and the friend's choice to add it.
private struct InviteTitleOffer: View {
    let title: Components.Schemas.TitleSummary
    @Binding var addTitle: Bool

    var body: some View {
        let kind = MediaKind(type: title._type, isAnime: title.isAnime)
        HStack(alignment: .top, spacing: 16) {
            PosterView(url: title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 80)
            VStack(alignment: .leading, spacing: 12) {
                Text("“\(InviteWords.plea(title.title, kind: kind))”")
                    .font(.aaruDisplay(.title3, weight: .regular))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Add to my \(LibraryStatus.wishlist.label(for: kind))", isOn: $addTitle)
                    .tint(Color(.accent))
            }
        }
    }
}

/// A handle for a friend who has none yet, so the sender sees who accepted.
private struct InviteHandleField: View {
    let inviter: String
    @Binding var handle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a handle so \(inviter) knows it's you")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 2) {
                Text("@").foregroundStyle(Color(.muted))
                TextField("handle", text: $handle)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Color(.surface), in: .rect(cornerRadius: 10))
        }
    }
}

/// The owl on the night disc, as on the welcome screen.
private struct InviteMedallion: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(.night))
            Image(.mascot)
                .resizable()
                .scaledToFit()
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
    }
}

/// How an invite speaks, the same words as the web's.
enum InviteWords {
    static func plea(_ title: String, kind: MediaKind) -> String {
        switch kind {
        case .book: "Read \(title) with me."
        case .music: "Listen to \(title) with me."
        case .film, .show, .anime: "Watch \(title) with me."
        }
    }

    /// "Expires in 13 days", "Expires tomorrow", "Expires today".
    static func expiry(_ date: Date, now: Date = .now) -> String {
        let days = Int(date.timeIntervalSince(now) / 86400)
        switch days {
        case ..<1: return "Expires today"
        case 1: return "Expires tomorrow"
        default: return "Expires in \(days) days"
        }
    }
}

extension SocialUser {
    /// How an invite names someone: their name, else their handle.
    var inviteName: String {
        let name = displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "@\(handle)" : name
    }
}
