import AaruAPI
import AaruCore
import Foundation
import Observation

/// One Chat turn in the Assistant card: what was asked and Aaru's reply so far.
struct AssistantTurn: Identifiable {
    let id: UUID
    let question: String
    let spoken: Bool
    var reply: ChatReply
    var undone: Bool
}

extension Notification.Name {
    /// Delete my chats succeeded. A notification because the Mac's Settings scene does not hold
    /// the model.
    static let aaruChatsDeleted = Notification.Name("aaruChatsDeleted")
}

/// The Assistant card's state (ASK-009): one Chat, typed or spoken, one flow at a time. A flow is
/// listening, reading what was said, and answering; closing the card ends it. A write already
/// applied stays journaled, and the library is synced after every turn so it shows.
@MainActor
@Observable
final class AssistantModel {
    enum Phase: Equatable {
        case idle, asking, listening, reading, answering
    }

    /// `/v1/chats/status`'s assistant; false until known. False hides the owl.
    private(set) var isAvailable = false
    /// `/v1/chats/status`'s voice; false until known. False hides the mic.
    private(set) var voiceAvailable = false
    private(set) var phase = Phase.idle
    private(set) var turns: [AssistantTurn] = []
    /// Plans answered in the card, by id, as the server left them. A reply freezes when it ends, so
    /// a card closed and reopened would otherwise offer Approve again.
    private(set) var decidedPlans: [String: AgentPlan] = [:]
    private(set) var micDenied = false
    private(set) var voiceProblem: String?
    /// 0…1, for the mic's meter.
    private(set) var level: Float = 0
    /// Bumped after any applied change or undo; title pages reload on it.
    private(set) var libraryChanges = 0
    /// Persists on this device. Muting stops speech now.
    var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
            if isMuted {
                speaker.stop()
            }
        }
    }

    private static let mutedKey = "assistant.muted"
    static let maxQuestionScalars = 4000
    private static let notHeard = "I didn't catch that. Try again, or type."

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let thread: ChatThread?
    @ObservationIgnored private let recorder = VoiceRecorder()
    @ObservationIgnored private let speaker = ReplySpeaker()
    @ObservationIgnored private var hint: Components.Schemas.ChatHint?
    @ObservationIgnored private var flow: Task<Void, Never>?
    /// Bumped when the card closes or resets. A flow compares the value it started with after
    /// every await: the voice call and the thread can report a cancel as a failure.
    @ObservationIgnored private var flowToken = 0
    /// Bumped by `reset()`, so a read still in flight says nothing to the next account.
    @ObservationIgnored private var accountToken = 0

    init(api: Client?, library: LibraryModel) {
        self.api = api
        self.library = library
        thread = api.map { ChatThread(client: $0) }
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .aaruChatsDeleted) {
                guard let self else { return }
                await reset()
                // Only the chats went: this account is still signed in, so the owl comes back.
                await refreshStatus()
            }
        }
    }

    /// A failed read keeps the last known values.
    func refreshStatus() async {
        guard let api else { return }
        let started = accountToken
        guard case let .ok(response) = try? await api.getChatStatus(),
              let status = try? response.body.json,
              started == accountToken
        else { return }
        isAvailable = status.assistant
        voiceAvailable = status.voice
    }

    func opened(_ presentation: AssistantPresentation) {
        hint = presentation.hint
        let started = flowToken
        Task { [weak self, thread] in
            let continues = await thread?.reopen() ?? true
            guard let self else { return }
            // Even if the card closed again: the chat has expired either way.
            if !continues, phase == .idle {
                turns = []
                decidedPlans = [:]
            }
            // From idle only: while listening, toggling would stop the recording.
            guard started == flowToken, presentation.listening, voiceAvailable, phase == .idle else { return }
            toggleListening()
        }
    }

    /// Cancels the turn, discards a recording and stops speech. The turns stay.
    func closed() {
        flowToken += 1
        flow?.cancel()
        recorder.discard()
        speaker.stop()
        // The flow's own updates are ignored from here, so its turn ends now.
        if let last = turns.indices.last {
            turns[last].reply.cancel()
        }
        phase = .idle
        level = 0
        voiceProblem = nil
        micDenied = false
    }

    /// Trims. Blank or over 4000 scalars does nothing, as does a flow already running.
    func send(_ text: String) {
        _ = ask(text, language: nil)
    }

    /// Starts listening, or stops and sends what was heard. Does nothing mid-flow.
    func toggleListening() {
        switch phase {
        case .idle: startListening()
        // The listening loop sees this on its next reading and goes on to upload.
        case .listening: phase = .reading
        case .asking, .reading, .answering: break
        }
    }

    /// What went wrong, or nil once undone.
    func undo(_ turnID: UUID) async -> String? {
        guard let turn = turns.first(where: { $0.id == turnID }), !turn.undone,
              let actionID = turn.reply.actionID
        else { return nil }
        let started = accountToken
        if let problem = await library.undo(actionID, api: api) {
            return problem
        }
        guard started == accountToken else { return nil }
        // Undoing an add deletes the item, which only a sync takes off the shelf.
        await library.sync(api: api)
        guard started == accountToken else { return nil }
        if let index = turns.firstIndex(where: { $0.id == turnID }) {
            turns[index].undone = true
        }
        libraryChanges += 1
        return nil
    }

    func planDecided(_ plan: AgentPlan) async {
        decidedPlans[plan.id] = plan
        guard plan.status == .applied else { return }
        let started = accountToken
        await library.sync(api: api)
        guard started == accountToken else { return }
        libraryChanges += 1
    }

    /// Sign-out and Delete my chats: everything `closed()` does, plus the turns and the thread.
    /// All of it but the thread is done before the first suspension, so nothing can race it.
    func reset() async {
        closed()
        accountToken += 1
        hint = nil
        turns = []
        decidedPlans = [:]
        isAvailable = false
        voiceAvailable = false
        await thread?.reset()
    }

    /// Runs after the flow before it has wound down: `ChatThread` does not serialise sends, and a
    /// closed flow may still be stopping.
    private func startFlow(_ work: @escaping @MainActor () async -> Void) {
        let previous = flow
        flow = Task {
            await previous?.value
            await work()
        }
    }

    // MARK: - Chat turns

    /// `language` is set when the question was spoken: Whisper's, kept for the speaker. False when
    /// no turn started.
    private func ask(_ text: String, language: String?) -> Bool {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .idle, let thread, !question.isEmpty,
              question.unicodeScalars.count <= Self.maxQuestionScalars
        else { return false }
        speaker.stop()
        voiceProblem = nil
        let turnID = UUID()
        turns.append(AssistantTurn(
            id: turnID, question: question, spoken: language != nil, reply: ChatReply(), undone: false
        ))
        phase = .answering
        let started = flowToken
        let account = accountToken
        let hint = hint
        startFlow { [weak self] in
            let reply = await thread.send(question, hint: hint) { [weak self] reply in
                await self?.update(turnID, with: reply, started)
            }
            self?.turnEnded(turnID, reply: reply, flow: started, account: account, language: language)
        }
        return true
    }

    private func update(_ turnID: UUID, with reply: ChatReply, _ started: Int) {
        guard started == flowToken, let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].reply = reply
    }

    private func turnEnded(_ turnID: UUID, reply: ChatReply, flow started: Int, account: Int, language: String?) {
        // However it ended: a write applied before the card closed must still show. Not after a
        // reset, which may be a sign-out.
        if account == accountToken {
            syncLibrary(changed: reply.actionID != nil)
        }
        guard started == flowToken else { return }
        update(turnID, with: reply, started)
        phase = .idle
        if let language, !isMuted, reply.state != .cancelled,
           let words = reply.text.isEmpty ? reply.problem : reply.text
        {
            speaker.speak(words, language: language)
        }
        if reply.problem != nil {
            refreshStatusSoon()
        }
    }

    /// Unstructured: the flow that asked may be cancelled, which would cancel the request. A turn
    /// closed mid-answer has no `actionID` even if it wrote, so the sync's own changes count too.
    private func syncLibrary(changed: Bool) {
        let account = accountToken
        Task { [weak self, library, api] in
            let before = library.revision
            await library.sync(api: api)
            guard let self, account == accountToken, changed || library.revision != before else { return }
            libraryChanges += 1
        }
    }

    /// Unstructured: the next flow waits for this one, and should not wait for a status read.
    private func refreshStatusSoon() {
        Task { [weak self] in
            await self?.refreshStatus()
        }
    }
}

// MARK: - Listening

private extension AssistantModel {
    func startListening() {
        guard voiceAvailable, let api else { return }
        // First, so the mic cannot hear Aaru.
        speaker.stop()
        voiceProblem = nil
        micDenied = false
        phase = .asking
        let started = flowToken
        startFlow { [weak self] in
            await self?.listen(started, api: api)
        }
    }

    func listen(_ started: Int, api: Client) async {
        // The flow before may have taken long enough for the card to close: no mic prompt then.
        guard started == flowToken else { return }
        let granted = await VoiceRecorder.requestPermission()
        guard started == flowToken else { return }
        guard granted else {
            micDenied = true
            phase = .idle
            return
        }
        do {
            try recorder.start()
        } catch {
            voiceProblem = "The mic could not start. You can still type."
            phase = .idle
            return
        }
        phase = .listening
        let ended = await meterUntilStopped(started)
        guard started == flowToken else { return }
        level = 0
        if ended == .noSpeech {
            recorder.discard()
            voiceProblem = Self.notHeard
            phase = .idle
            return
        }
        phase = .reading
        guard let recording = recorder.stop() else {
            voiceProblem = Self.notHeard
            phase = .idle
            return
        }
        let result = await api.transcribeQuestion(recording.data, seconds: recording.seconds)
        guard started == flowToken else { return }
        handle(result)
    }

    /// Feeds the meter to a fresh detector every 100 ms. Returns why the recording ended, or nil
    /// when `toggleListening` stopped it or the card closed.
    func meterUntilStopped(_ started: Int) async -> SilenceDetector.Stop? {
        var detector = SilenceDetector()
        let began = ContinuousClock.now
        while phase == .listening, started == flowToken {
            // Nil power: the recorder stopped itself at its limit, or the system took the mic.
            guard let power = recorder.power() else { return .cap }
            level = Self.meterLevel(power)
            if let stop = detector.feed(power: power, at: (ContinuousClock.now - began) / .seconds(1)) {
                return stop
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func handle(_ result: ChatVoiceResult) {
        phase = .idle
        switch result {
        case let .text(text, language):
            if !ask(text, language: language) {
                voiceProblem = Self.notHeard
            }
        case .notHeard:
            voiceProblem = Self.notHeard
        case .tooLong:
            voiceProblem = "That was too long. Try a shorter question."
        case .tooMany:
            voiceProblem = "Too many spoken questions for now. You can still type."
        case .off:
            voiceProblem = "Voice is off right now. You can still type."
            refreshStatusSoon()
        case let .failed(problem):
            voiceProblem = problem
        }
    }

    /// dBFS to 0…1, with -50 dB and below reading as nothing.
    static func meterLevel(_ power: Float) -> Float {
        min(max((power + 50) / 50, 0), 1)
    }
}
