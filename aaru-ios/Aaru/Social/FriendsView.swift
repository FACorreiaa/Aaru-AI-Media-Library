import AaruAPI
import SwiftUI

/// Settings → Friends & privacy (§18, SOC-001): your handle, the way to Friends, whether friends
/// see your library, and Location, the one place Aaru stores where you are (UX-022). The friend
/// lists, invites and requests live on Friends itself.
struct FriendsPage: View {
    let social: SocialModel
    @State private var concerts: ConcertsModel
    @Environment(AppRouter.self) private var router

    init(api: Client?, social: SocialModel) {
        self.social = social
        _concerts = State(initialValue: ConcertsModel(api: api))
    }

    var body: some View {
        @Bindable var social = social
        Form {
            Section {
                NavigationLink {
                    ProfileEditor(model: social)
                } label: {
                    LabeledContent("Handle", value: social.handle.map { "@\($0)" } ?? "Choose one")
                }
                if social.handle != nil {
                    Button {
                        router.showFriends()
                    } label: {
                        LabeledContent {
                            if social.incoming.isEmpty {
                                Text("\(social.friends.count)")
                            } else {
                                Text("\(social.incoming.count) asking").foregroundStyle(Color(.accent))
                            }
                        } label: {
                            Label("Friends", systemImage: "person.2")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Friends: invites, requests and your friends")
                    Toggle(
                        "Show my library to friends",
                        isOn: Binding(get: { social.shareLibrary }, set: { share in
                            Task { await social.setShareLibrary(share) }
                        })
                    )
                    Toggle(
                        "Show my badges and level to friends",
                        isOn: Binding(get: { social.showAchievements }, set: { show in
                            Task { await social.setShowAchievements(show) }
                        })
                    )
                    Toggle(
                        "Join the weekly friends board",
                        isOn: Binding(get: { social.leaderboardOptIn }, set: { join in
                            Task { await social.setLeaderboardOptIn(join) }
                        })
                    )
                }
            } header: {
                Text("Friends")
            } footer: {
                Text(
                    "Friends find you by your exact handle and see what you're watching and finished. Nobody else "
                        + "ever does."
                )
            }
            ConcertPlaceSection(model: concerts) { social.problem = $0 }
        }
        .settingsPage("Friends & privacy", problem: $social.problem)
        .refreshable { await social.load() }
        .task { await social.load() }
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
                    Text("@").foregroundStyle(Color(.muted)).accessibilityHidden(true)
                    TextField("Handle", text: $handle)
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
                Text(problem).foregroundStyle(Color(.danger))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Name and handle")
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
    /// The "You" card and the weekly board (GAM-005); nil in previews.
    @Environment(ProgressModel.self) private var achievements: ProgressModel?
    @State private var joining = false
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
            if let achievements, let progress = achievements.progress {
                Section {
                    NavigationLink {
                        AchievementsView(model: achievements)
                    } label: {
                        YouCard(progress: progress, handle: model.handle)
                    }
                }
            }
            LeaderboardSection(board: achievements?.board, joining: joining, onJoin: join)
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
                    Text("@").foregroundStyle(Color(.muted)).accessibilityHidden(true)
                    TextField("Their handle", text: $friendHandle)
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
                if !model.hasLoaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.friends.isEmpty {
                    Text("No friends yet. Send someone an invite, or ask for their handle.")
                        .foregroundStyle(Color(.muted))
                }
                ForEach(model.friends, id: \.userId) { friend in
                    // A destination link, so Friends works in any stack (its tab, Groups on iPhone).
                    NavigationLink {
                        FriendProfileView(api: model.api, friend: friend)
                    } label: {
                        PersonRow(user: friend) { EmptyView() }
                    }
                    .swipeActions {
                        Button("Block", role: .destructive) { blocking = friend }
                        Button("Remove") { Task { await model.remove(friend) } }
                    }
                    .contextMenu {
                        Button("Remove friend", systemImage: "person.badge.minus") {
                            Task { await model.remove(friend) }
                        }
                        Button("Block", systemImage: "hand.raised", role: .destructive) { blocking = friend }
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
        .refreshable {
            await model.load()
            await achievements?.loadBoard()
        }
        .task { await achievements?.loadBoard() }
        // The switch in Friends & privacy changes who is on the board.
        .onChange(of: model.leaderboardOptIn) { Task { await achievements?.loadBoard() } }
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
            isPresented: $blocking.isPresent,
            titleVisibility: .visible,
            presenting: blocking
        ) { person in
            Button("Block", role: .destructive) { Task { await model.block(person) } }
        } message: { _ in
            Text("You stop being friends, and neither of you can find the other. They aren't told.")
        }
    }

    private func join() {
        Task {
            joining = true
            await model.setLeaderboardOptIn(true)
            joining = false
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

/// The top of Friends: your level, streak and badges, opening Achievements.
private struct YouCard: View {
    let progress: AchievementProgress
    let handle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You").eyebrow()
            Text("Level \(progress.level) · \(StreakWords.headline(progress.streak.current))")
                .font(.aaruDisplay(.title3))
            Text("\(progress.weekPoints.formatted()) points this week" + (handle.map { " · @\($0)" } ?? ""))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Achievements")
    }
}

private struct PersonRow<Actions: View>: View {
    let user: SocialUser
    @ViewBuilder var actions: () -> Actions
    @ScaledMetric(relativeTo: .body) private var side = 36

    var body: some View {
        HStack(spacing: 12) {
            Text(user.monogram)
                .font(.subheadline.weight(.medium))
                .frame(width: side, height: side)
                .background(Color(.medallion).opacity(AaruAlpha.ghost), in: .circle)
                .accessibilityHidden(true)
            Text(user.label).lineLimit(2)
            Spacer(minLength: 8)
            actions()
        }
    }
}
