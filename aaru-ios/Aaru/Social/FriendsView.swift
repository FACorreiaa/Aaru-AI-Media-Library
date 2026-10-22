import AaruAPI
import SwiftUI

/// The Settings rows for friends: your handle, and whether friends see your library (SOC-001).
struct FriendsSection: View {
    @State private var model: SocialModel

    init(api: Client?) {
        _model = State(initialValue: SocialModel(api: api))
    }

    var body: some View {
        Section {
            NavigationLink {
                ProfileEditor(model: model)
            } label: {
                LabeledContent("Handle", value: model.handle.map { "@\($0)" } ?? "Choose one")
            }
            if model.handle != nil {
                Toggle(
                    "Show my library to friends",
                    isOn: Binding(get: { model.shareLibrary }, set: { share in
                        Task { await model.setShareLibrary(share) }
                    })
                )
                .tint(Color(.accent))
            }
        } header: {
            Text("Profile and friends")
        } footer: {
            Text("Friends see what you're watching and finished. Nobody else ever does. Invites live in Friends.")
        }
        .task { await model.load() }
    }
}

/// Claim or change the handle, and the optional display name.
struct ProfileEditor: View {
    let model: SocialModel
    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Color(.muted))
                    TextField("handle", text: $handle)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
            } footer: {
                Text(SocialModel.handleProblem(handle) ?? "3–20 letters, numbers or underscores.")
            }
            if let problem = model.problem {
                Text(problem).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle(model.handle == nil ? "Choose a handle" : "Your handle")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        saving = true
                        if await model.saveProfile(handle: handle, displayName: name) {
                            dismiss()
                        }
                        saving = false
                    }
                }
                .disabled(saving || SocialModel.handleProblem(handle) != nil)
            }
        }
        .onAppear {
            model.problem = nil
            handle = model.handle ?? ""
            name = model.displayName ?? ""
        }
    }
}

/// Requests both ways, friends, and blocks. Every act is a tap the other side is never told about,
/// except a request, which they see.
struct FriendsView: View {
    let model: SocialModel
    @State private var friendHandle = ""
    @State private var blocking: SocialUser?
    @State private var sending = false
    @State private var choosingTitle = false
    @State private var inviting = false
    /// The link just made, shown in a sheet to send.
    @State private var fresh: FriendInvite?
    /// A link made from the title picker, shown once that sheet has gone.
    @State private var pickedInvite: FriendInvite?

    var body: some View {
        List {
            if !model.recommendations.isEmpty {
                Section("For you from friends") {
                    ForEach(model.recommendations, id: \.id) { item in
                        RecommendationRow(item: item) { add in Task { await model.answer(item, add: add) } }
                    }
                }
            }
            if !model.activity.isEmpty {
                Section("Lately") {
                    ForEach(model.activity, id: \.id) { item in
                        let own = item.user.handle == model.handle
                        ActivityRow(item: item, own: own) { emoji in Task { await model.react(emoji, to: item) } }
                    }
                    if model.activityNext != nil {
                        Button("Earlier") { Task { await model.loadEarlierActivity() } }
                    }
                }
            }
            Section {
                Button {
                    makeInvite()
                } label: {
                    Label("Invite a friend", systemImage: "envelope")
                }
                .disabled(inviting)
                Button {
                    choosingTitle = true
                } label: {
                    Label("Invite to watch something together", systemImage: "popcorn")
                }
                .disabled(inviting)
                ForEach(model.invites, id: \.code) { invite in
                    InviteRow(invite: invite)
                        .swipeActions {
                            Button("Revoke", role: .destructive) { Task { await model.revoke(invite) } }
                        }
                        .contextMenu {
                            Button("Revoke", role: .destructive) { Task { await model.revoke(invite) } }
                        }
                }
            } header: {
                Text("Invite")
            } footer: {
                Text("A link works once, for two weeks. Whoever opens it joins Aaru and becomes your friend.")
            }

            Section {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Color(.muted))
                    TextField("their handle", text: $friendHandle)
                        .autocorrectionDisabled()
                        .onSubmit(send)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    Button("Send", action: send)
                        .disabled(sending || friendHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let notice = model.notice {
                    Text(notice).font(.callout)
                }
            } header: {
                Text("Add a friend")
            }

            if !model.incoming.isEmpty {
                Section("Asking you") {
                    ForEach(model.incoming, id: \.id) { request in
                        PersonRow(user: request.user) {
                            Button("Accept") { Task { await model.accept(request) } }
                                .buttonStyle(.borderedProminent)
                            Button("Decline") { Task { await model.withdraw(request) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if !model.outgoing.isEmpty {
                Section("Waiting on") {
                    ForEach(model.outgoing, id: \.id) { request in
                        PersonRow(user: request.user) {
                            Button("Cancel") { Task { await model.withdraw(request) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Friends") {
                if model.friends.isEmpty {
                    Text("No friends yet. Send someone an invite, or ask for their handle.")
                        .foregroundStyle(Color(.muted))
                }
                ForEach(model.friends, id: \.userId) { friend in
                    NavigationLink(value: friend) { PersonRow(user: friend) { EmptyView() } }
                        .swipeActions {
                            Button("Block", role: .destructive) { blocking = friend }
                            Button("Remove") { Task { await model.remove(friend) } }
                        }
                        .contextMenu {
                            Button("Remove friend") { Task { await model.remove(friend) } }
                            Button("Block", role: .destructive) { blocking = friend }
                        }
                }
            }

            if !model.blocked.isEmpty {
                Section("Blocked") {
                    ForEach(model.blocked, id: \.userId) { person in
                        PersonRow(user: person) {
                            Button("Unblock") { Task { await model.unblock(person) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Friends")
        .refreshable { await model.load() }
        .sheet(
            isPresented: $choosingTitle,
            onDismiss: {
                fresh = pickedInvite
                pickedInvite = nil
            },
            content: {
                TitlePickerSheet(api: model.api, navigationTitle: "Watch together") { hit in
                    pickedInvite = await model.invite(with: hit)
                    return pickedInvite != nil
                }
            }
        )
        .sheet(item: $fresh) { invite in
            FreshInviteSheet(invite: invite)
        }
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: model.problem) { model.problem = nil } }
        .confirmationDialog(
            "Block @\(blocking?.handle ?? "")?",
            isPresented: Binding(get: { blocking != nil }, set: {
                if !$0 {
                    blocking = nil
                }
            }),
            titleVisibility: .visible,
            presenting: blocking
        ) { person in
            Button("Block", role: .destructive) { Task { await model.block(person) } }
        } message: { _ in
            Text("You stop being friends, and neither of you can find the other. They aren't told.")
        }
    }

    private func makeInvite() {
        Task {
            inviting = true
            fresh = await model.invite(with: nil)
            inviting = false
        }
    }

    private func send() {
        let handle = friendHandle
        Task {
            sending = true
            if await model.send(to: handle) {
                friendHandle = ""
            }
            sending = false
        }
    }
}

private struct PersonRow<Actions: View>: View {
    let user: SocialUser
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(user.monogram)
                .font(.subheadline.weight(.medium))
                .frame(width: 36, height: 36)
                .background(Color(.medallion).opacity(0.2), in: .circle)
                .accessibilityHidden(true)
            Text(user.label).lineLimit(1)
            Spacer(minLength: 8)
            actions()
        }
    }
}

extension FriendInvite: @retroactive Identifiable {
    public var id: String {
        code
    }
}

private extension FriendInvite {
    var plea: String {
        guard let title else { return "Join me on Aaru." }
        return InviteWords.plea(title.title, kind: MediaKind(type: title._type, isAnime: title.isAnime))
    }
}

/// One open invite: what it says and how long it has left, with the share sheet a tap away.
private struct InviteRow: View {
    let invite: FriendInvite

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.plea).lineLimit(1)
                Text(InviteWords.expiry(invite.expiresAt))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 8)
            if let url = URL(string: invite.url) {
                ShareLink(item: url, message: Text(invite.plea)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share invite")
            }
        }
    }
}

/// The link just made: what it will say, and the share sheet to send it.
private struct FreshInviteSheet: View {
    let invite: FriendInvite
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let title = invite.title {
                    PosterView(
                        url: title.posterUrl.flatMap(URL.init(string:)),
                        kind: MediaKind(type: title._type, isAnime: title.isAnime)
                    )
                    .frame(width: 96)
                } else {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color(.accent))
                }
                VStack(spacing: 8) {
                    Text("Your invite is ready")
                        .font(.system(.title, design: .serif, weight: .medium))
                    Text("“\(invite.plea)”")
                        .font(.system(.body, design: .serif))
                        .italic()
                    Text("It works once, for the first person who opens it, for two weeks.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .multilineTextAlignment(.center)
                }
                if let url = URL(string: invite.url) {
                    ShareLink(item: url, message: Text(invite.plea)) {
                        Label("Send invite", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
