import AaruAPI
import SwiftUI

/// One title a friend sent you (SOC-006): poster, who and their note, then Add or Dismiss.
struct RecommendationRow: View {
    let item: RecommendationItem
    let onAnswer: (_ add: Bool) -> Void

    var body: some View {
        let kind = MediaKind(type: item.title._type, isAnime: item.title.isAnime)
        HStack(alignment: .top, spacing: 12) {
            PosterView(url: item.title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.from.inviteName) recommends **\(item.title.title)**")
                if let note = item.note {
                    Text("“\(note)”").font(.aaruDisplay(.body, weight: .regular, italic: true))
                }
                HStack(spacing: 8) {
                    Button("Add to \(LibraryStatus.wishlist.label(for: kind))") { onAnswer(true) }
                        .buttonStyle(.borderedProminent)
                    Button("Dismiss") { onAnswer(false) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Sends one title to friends (SOC-006). From a title the title is fixed and you pick friends;
/// from a friend's profile the friend is fixed and you find a title.
struct RecommendSheet: View {
    let model: SocialModel
    var title: (ref: MediaRef, name: String)?
    var friend: SocialUser?

    @Environment(\.dismiss) private var dismiss
    @State private var picked: (ref: MediaRef, name: String)?
    @State private var choosingTitle = false
    @State private var chosen: Set<String> = []
    @State private var note = ""
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    if let picked {
                        LabeledContent(picked.name) {
                            if title == nil {
                                Button("Change") { choosingTitle = true }
                            }
                        }
                    } else {
                        Button("Choose a title") { choosingTitle = true }
                    }
                }
                if friend == nil {
                    Section("To") {
                        if let failure = model.loadProblem {
                            Text(failure).foregroundStyle(Color(.danger))
                            Button("Try again") { Task { await model.load() } }
                        } else if !model.hasLoaded {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if model.friends.isEmpty {
                            Text("No friends yet. Send someone an invite.").foregroundStyle(Color(.muted))
                        }
                        ForEach(model.friends, id: \.userId) { person in
                            Toggle(person.inviteName, isOn: Binding(
                                get: { chosen.contains(person.userId) },
                                set: { isOn in
                                    if isOn, chosen.count < 10 {
                                        chosen.insert(person.userId)
                                    } else {
                                        chosen.remove(person.userId)
                                    }
                                }
                            ))
                            .tint(Color(.accent))
                        }
                    }
                }
                Section {
                    TextField("Why they'll love it (optional)", text: $note)
                        .onChange(of: note) { _, text in
                            if text.count > 140 {
                                note = String(text.prefix(140))
                            }
                        }
                } footer: {
                    if sent {
                        Text("Sent. It waits at the top of their Friends.")
                    } else if let problem = model.problem {
                        Text(problem).foregroundStyle(Color(.danger))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(friend.map { "Recommend to \($0.inviteName)" } ?? "Recommend")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(sent ? "Done" : "Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send", action: send)
                            .disabled(sending || sent || picked == nil || chosen.isEmpty)
                    }
                }
                .sheet(isPresented: $choosingTitle) {
                    TitlePickerSheet(api: model.api, navigationTitle: "Recommend") { hit in
                        picked = (MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year), hit.title)
                        return true
                    }
                }
        }
        .task {
            picked = title
            if let friend {
                chosen = [friend.userId]
            } else if !model.hasLoaded {
                await model.load()
            }
        }
    }

    private func send() {
        guard let picked else { return }
        Task {
            sending = true
            sent = await model.recommend(picked.ref, to: Array(chosen), note: note)
            sending = false
        }
    }
}

/// Invites a friend into one of your groups, from their profile.
struct GroupInviteSheet: View {
    let api: Client?
    let friend: SocialUser

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [Components.Schemas.GroupSummary]?
    @State private var invited: Set<String> = []
    @State private var problem: String?
    /// The groups did not load: Try again, never "No groups yet" (UX-063).
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            List {
                if let groups, groups.isEmpty {
                    ContentUnavailableView(
                        "No groups yet", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start one from Groups, then invite \(friend.inviteName).")
                    )
                }
                ForEach(groups ?? [], id: \.id) { group in
                    LabeledContent(group.name) {
                        if invited.contains(group.id) {
                            Text("Invited").foregroundStyle(Color(.muted))
                        } else {
                            Button("Invite") { Task { await invite(group) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if let problem {
                    Text(problem).foregroundStyle(Color(.danger))
                }
            }
            .overlay {
                if loadFailed {
                    LoadFailedView(title: "Your groups didn't load", message: "Aaru could not reach the server.") {
                        await load()
                    }
                } else if groups == nil {
                    ProgressView()
                }
            }
            .navigationTitle("Invite to a group")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await load() }
    }

    private func load() async {
        guard let api else { return }
        loadFailed = false
        do {
            if case let .ok(response) = try await api.listGroups() {
                groups = try response.body.json.items
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }

    private func invite(_ group: Components.Schemas.GroupSummary) async {
        guard let api else { return }
        problem = nil
        do {
            switch try await api.inviteToGroup(
                path: .init(groupId: group.id),
                body: .json(.init(userId: friend.userId))
            ) {
            case .noContent: invited.insert(group.id)
            case let .default(_, error): problem = (try? error.body.json.message) ?? "That invite was not sent."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }
}
