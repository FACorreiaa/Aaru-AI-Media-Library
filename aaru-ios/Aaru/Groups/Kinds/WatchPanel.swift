import AaruAPI
import SwiftUI

/// GRP-009: the watch party above a watch channel's chat. Lobby with a ready list, a countdown
/// every member sees on the server's clock, reactions while it is live, and "Mark watched for
/// me", which ticks only this user's library. Aaru never controls anyone's player.
struct WatchPanel: View {
    let groups: GroupsModel
    let groupID: String
    @State private var model: WatchPartyModel
    @State private var opensParty = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(groups: GroupsModel, groupID: String, channelID: String) {
        self.groups = groups
        self.groupID = groupID
        _model = State(initialValue: WatchPartyModel(api: groups.api, groupID: groupID, channelID: channelID))
    }

    private var isHost: Bool {
        guard let party = model.party else { return false }
        return party.host?.userId == groups.myUserID || groups.role(in: groupID)?.manages == true
    }

    private var amReady: Bool {
        model.party?.ready.contains { $0.userId == groups.myUserID } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            if !model.hasLoaded, let problem = model.problem {
                // The first load failed: say so, never "No watch party yet" (UX-063).
                PanelLoadFailed(message: problem) { await model.load() }
            } else if !model.hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if let party = model.party {
                TitleCardRow(title: party.title, mine: nil)
                    .overlay(alignment: .trailing) { episodeBadge(party) }
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    stage(party, at: context.date)
                }
            } else {
                HStack {
                    Text("No watch party yet.").font(.callout).foregroundStyle(Color(.muted))
                    Spacer()
                    Button("Start one", systemImage: "play.rectangle") { opensParty = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if model.hasLoaded, let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(Color(.danger))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.surface).opacity(AaruAlpha.half))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(.line)).frame(height: 0.5) }
        .overlay(alignment: .topTrailing) { floatingReactions }
        .task { await model.load() }
        .task {
            guard let realtime = groups.realtime else { return }
            for await event in realtime.events() {
                await model.apply(event)
            }
        }
        .sheet(isPresented: $opensParty) {
            OpenPartySheet(api: groups.api) { title, season, episode in
                await model.open(title, season: season, episode: episode)
            }
        }
    }

    @ViewBuilder
    private func episodeBadge(_ party: WatchParty) -> some View {
        if let season = party.season, let episode = party.episode {
            Text(EpisodeCode.text(season: season, episode: episode))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.medallion).opacity(AaruAlpha.ghost), in: .capsule)
        }
    }

    @ViewBuilder
    private func stage(_ party: WatchParty, at date: Date) -> some View {
        switch model.state(at: date) {
        case .lobby:
            lobby(party)
        case .countdown:
            countdown(party, at: date)
        case .live:
            live(party)
        case .ended, nil:
            ended(party)
        }
    }

    private func lobby(_ party: WatchParty) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            readyList(party)
            HStack(spacing: 8) {
                Button(amReady ? "Ready" : "I'm ready", systemImage: amReady ? "checkmark.circle.fill" : "circle") {
                    Task { await model.setReady(!amReady) }
                }
                .buttonStyle(.bordered)
                if isHost {
                    Menu("Start countdown", systemImage: "timer") {
                        ForEach([5, 10, 30], id: \.self) { seconds in
                            Button("\(seconds) seconds") { Task { await model.startCountdown(seconds: seconds) } }
                        }
                    } primaryAction: {
                        Task { await model.startCountdown(seconds: 10) }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    endButton
                }
            }
            .controlSize(.small)
        }
    }

    private func countdown(_ party: WatchParty, at date: Date) -> some View {
        let remaining = max(0, (party.startsAt ?? date).timeIntervalSince(model.serverNow(date)))
        return HStack(alignment: .firstTextBaseline, spacing: AaruSpace.small) {
            Text("\(Int(remaining.rounded(.up)))")
                .font(.aaruDisplay(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            Text("Press play when it reaches zero.").font(.callout).foregroundStyle(Color(.muted))
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Starting in \(Int(remaining.rounded(.up))) seconds")
    }

    private func live(_ party: WatchParty) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Watching now", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.accent))
                Spacer()
                markWatchedButton(party)
                if isHost {
                    endButton
                }
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                ForEach(WatchPartyModel.reactionSet, id: \.self) { emoji in
                    Button(emoji) { react(emoji) }
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("React \(emoji)")
                }
            }
        }
    }

    private func ended(_ party: WatchParty) -> some View {
        HStack(spacing: 8) {
            Text("This party ended.").font(.callout).foregroundStyle(Color(.muted))
            Spacer()
            if party.startsAt != nil {
                markWatchedButton(party)
            }
            Button("Start another", systemImage: "play.rectangle") { opensParty = true }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func readyList(_ party: WatchParty) -> some View {
        if party.ready.isEmpty {
            Text("Nobody is ready yet.").font(.caption).foregroundStyle(Color(.muted))
        } else {
            HStack(spacing: 4) {
                ForEach(party.ready.prefix(8), id: \.userId) { user in
                    Monogram(text: user.monogram, avatarUrl: user.avatarUrl, size: 24)
                }
                Text("\(party.ready.count) ready").font(.caption).foregroundStyle(Color(.muted))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ready: \(party.ready.map(\.label).joined(separator: ", "))")
        }
    }

    private func markWatchedButton(_ party: WatchParty) -> some View {
        let done = model.markedWatchedID == party.id
        return Button(done ? "Marked watched" : "Mark watched for me", systemImage: done ? "checkmark" : "eye") {
            Task { await model.markWatched() }
        }
        .buttonStyle(.bordered)
        .disabled(done)
        .help("Ticks it in your library only.")
    }

    private var endButton: some View {
        Button("End", role: .destructive) { Task { await model.end() } }
            .buttonStyle(.bordered)
    }

    private var floatingReactions: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(model.reactions) { reaction in
                Text("\(reaction.emoji) \(reaction.name)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: .capsule)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(8)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35), value: model.reactions)
        .allowsHitTesting(false)
    }

    private func react(_ emoji: String) {
        guard groups.realtime?.sendReaction(group: groupID, channel: model.channelID, emoji: emoji) == true
        else { return }
        model.show(emoji, from: "You")
    }
}

/// A new party: the title, and for a show the episode.
private struct OpenPartySheet: View {
    let api: Client?
    let onOpen: (Components.Schemas.MediaRef, Int?, Int?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: CatalogHit?
    @State private var picksTitle = false
    @State private var season = 1
    @State private var episode = 1
    @State private var saving = false

    private var isShow: Bool {
        title?._type == .show
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you watching?") {
                    Button(title?.title ?? "Choose a title…", systemImage: "magnifyingglass") { picksTitle = true }
                }
                if isShow {
                    Section("Episode") {
                        Stepper("Season \(season)", value: $season, in: 0 ... 99)
                        Stepper("Episode \(episode)", value: $episode, in: 1 ... 999)
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("Everyone presses play on their own screen when the countdown reaches zero.")
                }
            }
            .paperPage()
            .navigationTitle("Watch party")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: open).disabled(title == nil || saving)
                }
            }
            .sheet(isPresented: $picksTitle) {
                TitlePickerSheet(api: api, navigationTitle: "Choose a title") { hit in
                    title = hit
                    return true
                }
            }
        }
    }

    private func open() {
        guard let title else { return }
        Task {
            saving = true
            defer { saving = false }
            if await onOpen(title.mediaRef, isShow ? season : nil, isShow ? episode : nil) {
                dismiss()
            }
        }
    }
}
