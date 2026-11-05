# Aaru assistant, iOS and Mac (ASK-009, build step 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An owl in the top bar of every main screen and title page opens a floating card on iPhone, iPad and Mac where the user talks or types and Aaru answers, over the live `/v1/chats` API.

**Architecture:** `aaru-ios` has no test target, so everything that can be wrong without a screen goes in the two tested packages: the stream parser, reply state, chat thread and voice call in `AaruAPI`, and the silence detector and read-aloud text in `AaruCore`. The app holds thin wrappers only: `VoiceRecorder`, `ReplySpeaker`, `AssistantModel` and the views. The generated client carries streaming, so the session token, the 401 routing and `X-Timezone` come from the existing middlewares and there is no second HTTP path.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, `@Observable`, AVFoundation, swift-openapi-runtime `HTTPBody`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-04-assistant-design.md`. Server contract is live at 084f0790 (openapi: `/v1/chats*`).

## Global Constraints

- Work in worktree `../aaru-wt-assistant-apple`, branch `feat/assistant-apple`, off `origin/main` 084f0790. Other sessions share the main checkout.
- Words in code and UI: **Assistant card**, Chat, Chat turn, Plan, Action. Never "Conversation" or "Message" (those are the encrypted DM).
- Colours only from generated tokens (`Color(.night)`, `Color(.muted)`…), `AaruRadius`, `AaruAlpha`, `AaruMotion`; headings `Font.aaruDisplay`; floating layer `.lift()`. No hex, no `Color(red:)`. `ci-brand.yml` enforces it.
- Reduce Motion: no rise or breathing; a plain fade. `AaruAvatar` already handles its own breathing.
- Read aloud only when the question was spoken. Mute persists locally. No speech API other than on-device `AVSpeechSynthesizer` and the server's transcribe route.
- Audio is never stored: the temp `.m4a` is deleted when the recording ends, sent or not.
- Closing the card cancels the turn. A write already applied stays journaled.
- One new file group: `aaru-ios/Aaru/Assistant/`. The Xcode project uses synchronized folders, so new files need no `project.pbxproj` entry.
- Keep Apple builds to `CODE_SIGNING_ALLOWED=NO`. Never run the App Store release lane.
- Tests never use a real key and never reach the network beyond loopback.

## Review Focus

1. A Portuguese reply whose `ã` is split across two network chunks must not turn into `�`. Pinned in Task 1.
2. A connection that drops mid-answer, with no `done` or `error` frame, must leave what was written plus "cut off", never a spinner. Pinned in Task 2.
3. The held chat gone (deleted on another device) or still busy (card closed and reopened fast) must recover without the user retyping. Pinned in Task 3.
4. A user who says nothing must not spend one of the 40 hourly transcriptions, and a mic reporting -160 dB at start must not read as speech forever. Pinned in Task 4.
5. A reply with `**Severance**` or a link must not be read as "asterisk asterisk", and Whisper's language arriving as `portuguese`, `pt-BR` or empty must still pick a voice. Pinned in Task 4.

---

### Task 1: SSE frame parser in `AaruAPI`

**Files:**
- Create: `aaru-api/Sources/AaruAPI/ChatFrame.swift`
- Create: `aaru-api/Tests/AaruAPITests/ChatFrameTests.swift`
- Create: `aaru-api/Tests/AaruAPITests/ChatStreamingTransportTests.swift`

**Interfaces:**
- Produces:
  - `public enum ChatFrame: Sendable { case status(String), delta(String), components(Components.Schemas.ChatComponentsFrame), done(turnID: String), error(code: Components.Schemas.ChatErrorFrame.CodePayload, message: String) }`
  - `public struct ChatFrameParser: Sendable { public init(); public mutating func consume(_ bytes: some Sequence<UInt8>) -> [ChatFrame] }`

- [ ] **Step 1: Write failing tests** in `ChatFrameTests.swift`:

```swift
@Test func parsesEveryFrameType()            // status, delta, components, done, error in one chunk, in order
@Test func keepsAMultibyteCharacterSplitAcrossChunks() {
    // "event: delta\ndata: {\"text\":\"não\"}\n\n" as UTF-8, cut between the two bytes of "ã".
    // Expect exactly one frame: .delta("não")
}
@Test func reassemblesAFrameAcrossEveryByteBoundary() // feed one byte at a time, same frames as one chunk
@Test func ignoresHeartbeatComments()        // ": keepalive\n\n" yields nothing, and does not disturb the next frame
@Test func acceptsCRLF()                     // same frames with \r\n line ends
@Test func skipsAnUnknownEvent()             // event: future → no frame, later frames still parsed
@Test func skipsMalformedJSONAndKeepsGoing() // bad data line → no frame, next frame parsed
@Test func decodesAPlanAndTitlesFromAComponentsFrame() // fixture with AgentPlan and TitleSummary; whole-second "2026-11-05T10:00:00Z" dates decode
```

The components fixture is a literal JSON string with the fields the generated `AgentPlan` and `TitleSummary` require, dates in the server's `apitime` form (whole seconds, UTC).

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path aaru-api --filter ChatFrameTests`
Expected: FAIL, `ChatFrameParser` not defined.

- [ ] **Step 3: Implement `ChatFrameParser`.** Buffer raw bytes and split on `\n` at byte level, dropping one trailing `\r`; decode UTF-8 only from a complete line, which is what keeps a split character intact. Lines starting `:` are ignored. A blank line ends a frame. Decode `data` with a `JSONDecoder` whose `dateDecodingStrategy` is `.iso8601` (the same as the generated client's default). Multiple `data:` lines join with `\n`, per SSE.

- [ ] **Step 4: Run to verify they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Prove the transport streams.** In `ChatStreamingTransportTests.swift`, wrapped in `#if canImport(Network)` because CI's `aaru-api` job runs on Linux:

```swift
@Test func urlSessionTransportDeliversTheFirstFrameBeforeTheSecondIsSent() async throws
// An NWListener on loopback answers POST with text/event-stream, writes one delta frame, then
// waits on a continuation that the test resumes only after it has received that first frame
// through `Client.aaru(...)`.createChatTurn with the default URLSessionTransport.
// A buffering transport deadlocks, so bound the wait to 5 s and fail on timeout.
```

Run: `swift test --package-path aaru-api --filter ChatStreamingTransportTests` on this Mac. Expected: PASS. If it fails the generated client cannot stream: stop and report rather than adding a second HTTP path.

- [ ] **Step 6: Commit**

```bash
git add aaru-api
git commit -m "feat(api): parse the assistant's event stream (ASK-009)"
```

---

### Task 2: Reply state and the voice call in `AaruAPI`

**Files:**
- Create: `aaru-api/Sources/AaruAPI/ChatReply.swift`
- Create: `aaru-api/Sources/AaruAPI/ChatVoice.swift`
- Modify: `aaru-api/Sources/AaruAPI/Client+Aaru.swift` (add the middleware)
- Create: `aaru-api/Tests/AaruAPITests/ChatReplyTests.swift`
- Create: `aaru-api/Tests/AaruAPITests/ChatVoiceTests.swift`
- Create: `aaru-api/Tests/AaruAPITests/ScriptedTransport.swift` (a queue of status/body responses that records requests and bodies; Task 3 uses it too)

**Interfaces:**
- Consumes: `ChatFrame` (Task 1).
- Produces:
  - `public struct ChatReply: Sendable { public enum State: Sendable, Equatable { case working, answered, stopped, cutOff, cancelled, failed }; public private(set) var text: String; public private(set) var status: String?; public private(set) var titles: [Components.Schemas.TitleSummary]; public private(set) var plan: Components.Schemas.AgentPlan?; public private(set) var actionID: String?; public private(set) var actionSummary: String?; public private(set) var state: State; public private(set) var problem: String?; public init(); public mutating func apply(_ frame: ChatFrame); public mutating func streamEnded(); public mutating func cancel(); public mutating func fail(_ problem: String) }`
  - `public enum ChatVoiceResult: Sendable, Equatable { case text(String, language: String), notHeard, tooLong, tooMany, off, failed(String) }`
  - `public extension Client { func transcribeQuestion(_ audio: Data, seconds: Double) async -> ChatVoiceResult }`
  - `public struct ChatAudioContentTypeMiddleware: ClientMiddleware`, added to the list in `Client.aaru`.

- [ ] **Step 1: Write failing tests** in `ChatReplyTests.swift`:

```swift
@Test func deltasAppendAndClearTheStatus()    // .status("Thinking"), .delta("Hi "), .delta("there") → text "Hi there", status nil
@Test func aLaterStatusShowsAgain()           // .delta("Hi"), .status("Checking your library") → status set, text kept
@Test func doneAnswers()                      // .done → .answered, status nil
@Test func errorStopsWithItsMessage()         // .error(.resting, "Aaru is resting") → .stopped, problem "Aaru is resting", status nil
@Test func aStreamThatEndsWithoutAnEndIsCutOff() {
    // .delta("Half an ans"), streamEnded() → .cutOff, text kept,
    // problem == "That answer was cut off. Ask again."
}
@Test func streamEndedAfterDoneChangesNothing()
@Test func componentsMerge()                  // two frames: titles add without duplicate ids; plan and action kept
@Test func cancelledKeepsWhatWasWritten()     // cancel() → .cancelled, no problem
```

In `ChatVoiceTests.swift`, over `Client.aaru(baseURL:session:transport: ScriptedTransport)`:

```swift
@Test func sendsAudioMP4NotTheWildcard()      // recorded Content-Type == "audio/mp4", because the server names the file from it
@Test func leavesOtherRequestsAlone()         // a createChat request keeps application/json
@Test func clampsTheSecondsHeaderTo60()       // seconds: 60.04 → X-Audio-Seconds parses to ≤ 60, so a full recording is not refused 413
@Test func returnsTextAndLanguage()           // 200 {"text":"olá","language":"pt"} → .text("olá", language: "pt")
@Test func mapsStatuses()                     // 422 → .notHeard, 413 → .tooLong, 429 → .tooMany, 503 → .off, 500 → .failed(body message)
@Test func aThrownTransportErrorFails()       // → .failed("Aaru could not reach the server.")
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path aaru-api --filter 'ChatReplyTests|ChatVoiceTests'`
Expected: FAIL, types not defined.

- [ ] **Step 3: Implement.** `ChatAudioContentTypeMiddleware.intercept` rewrites `Content-Type` only when `operationID == "transcribeChatAudio"`, to `audio/mp4`, the only format the Apple apps record. `transcribeQuestion` sends `.audio_Ast_(HTTPBody(audio))` with `min(seconds, 60)` and maps by status code.

- [ ] **Step 4: Run to verify they pass.** Same command, then `swift test --package-path aaru-api`. Expected: PASS, including the existing `SessionMiddlewareTests`.

- [ ] **Step 5: Commit**

```bash
git add aaru-api
git commit -m "feat(api): reply state and the spoken question call (ASK-009)"
```

---

### Task 3: `ChatThread` in `AaruAPI`

**Files:**
- Create: `aaru-api/Sources/AaruAPI/ChatThread.swift`
- Create: `aaru-api/Tests/AaruAPITests/ChatThreadTests.swift`

**Interfaces:**
- Consumes: `ChatFrameParser`, `ChatReply`, `ScriptedTransport`.
- Produces:

```swift
public actor ChatThread {
    public init(client: Client, busyRetryDelay: Duration = .seconds(1), now: @escaping @Sendable () -> Date = { Date() })
    /// Called on opening the card. True: the same chat continues. False: over 15 minutes idle, so the next send starts a new one.
    public func reopen() -> Bool
    /// Forgets the chat: sign-out and Delete my chats.
    public func reset()
    /// Sends one Chat turn. `onUpdate` gets the reply after every frame. Returns the final reply; never throws.
    public func send(_ body: String, hint: Components.Schemas.ChatHint?, onUpdate: @escaping @Sendable (ChatReply) async -> Void) async -> ChatReply
}
```

- [ ] **Step 1: Write failing tests:**

```swift
@Test func createsAChatOnceAndReusesIt()      // two sends → one POST /v1/chats, two turn POSTs on its id
@Test func sendsTheBodyAndHint()              // recorded turn JSON has body and hint.screen "title", hint.titleId
@Test func deliversUpdatesInOrder()           // onUpdate sees status, then growing text, then answered
@Test func continuesWithin15MinutesAndNotAfter() {
    // now = t0, send. now = t0 + 14:59 → reopen() true, no new POST /v1/chats on the next send.
    // now = + 15:01 → reopen() false, next send POSTs /v1/chats again.
}
@Test func aChatTheServerNoLongerHasStartsANewOneOnce() // turn 404, create, turn 200 → answered, same body sent twice
@Test func stopsAfterOne404Retry()            // turn 404 twice → .failed, no third attempt
@Test func waitsOutABusyChat()                // turn 409, 409, 200 → answered; 3 attempts, delay .zero in the test
@Test func givesUpOnABusyChatAfterThreeTries() // 409 ×3 → .failed, problem "Aaru is still finishing the last answer. Try again in a moment."
@Test func reportsAnUnavailableAssistant()    // turn 503 with {"message":"…"} → .failed with that message
@Test func aCreateFailureFails()              // POST /v1/chats throws → .failed("Aaru could not reach the server.")
@Test func aDroppedStreamIsCutOff()           // 200 body throws after one delta → .cutOff, text kept
@Test func cancellingTheTaskCancelsTheReply() // cancel the calling Task mid-stream → .cancelled, no problem
@Test func resetForgetsTheChat()              // send, reset(), send → second POST /v1/chats
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path aaru-api --filter ChatThreadTests`
Expected: FAIL, `ChatThread` not defined.

- [ ] **Step 3: Implement.** Generated calls: `createChat`, `createChatTurn(path:.init(id:), body:.json(.init(body:hint:)))`, then iterate `ok.body.textEventStream` feeding `ChatFrameParser`. A `CancellationError` or `URLError.cancelled` means `cancel()`; any other thrown error during iteration, or the stream ending, means `streamEnded()`. Update the last-used time at the start and end of a send. `reopen()` is the only place that expires: a card left open past 15 minutes keeps its chat until it is reopened.

- [ ] **Step 4: Run to verify they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add aaru-api
git commit -m "feat(api): one chat thread with retry and the 15 minute window (ASK-009)"
```

---

### Task 4: Silence, read-aloud text and language in `AaruCore`

**Files:**
- Create: `aaru-core/Sources/AaruCore/AssistantVoice.swift`
- Create: `aaru-core/Tests/AaruCoreTests/AssistantVoiceTests.swift`

**Interfaces:**
- Produces:

```swift
public struct SilenceDetector: Sendable {
    public enum Stop: Sendable, Equatable { case silence, noSpeech, cap }
    public init()
    public private(set) var heardSpeech: Bool
    /// One meter reading in dBFS at `time` seconds since recording began. Nil keeps recording.
    public mutating func feed(power: Float, at time: TimeInterval) -> Stop?
}
public enum SpokenText { public static func plain(_ markdown: String) -> String }
public enum SpeechLanguage { public static func code(from whisper: String) -> String? }
```

- [ ] **Step 1: Write failing tests** (a helper feeds a scripted power at 0.1 s steps and returns the stop and its time):

```swift
@Test func stopsAfterSpeechAndAboutASecondAndAHalfOfQuiet()
    // -55 for 1 s, -25 for 2 s, then -55 → .silence at t = 4.5 (±0.1), not before
@Test func keepsGoingThroughAPauseBetweenWords()   // -25, 1 s of -55, -25 → no stop during the pause
@Test func hearsSomeoneTalkingFromTheFirstInstant() // -20 for 2 s, then -55 → .silence at 3.5
@Test func nobodySpeakingStopsWithoutAnUpload()    // -55 throughout → .noSpeech at 8, heardSpeech false
@Test func digitalSilenceDoesNotBecomeTheFloor()   // -160 for 0.5 s, then -55 for 8 s → .noSpeech, heardSpeech false
@Test func aNoisyRoomStillStops()                  // -30 for 1 s, -15 for 2 s, -30 → .silence
@Test func capsAtSixtySeconds()                    // -25 throughout → .cap at 60

@Test(arguments: [
    ("**Severance** is on tonight", "Severance is on tonight"),
    ("*Dune* and _Arrival_", "Dune and Arrival"),
    ("Try `Up Next`", "Try Up Next"),
    ("# Tonight\n- Severance\n- Dune", "Tonight\nSeverance\nDune"),
    ("See [Severance](https://aaruapp.com/s/x) now", "See Severance now"),
    ("More at https://example.com today", "More at today"),
    ("snake_case stays", "snake_case stays"),
    ("2 * 3 stays", "2 * 3 stays"),
]) func stripsMarkdownForSpeech(input: String, spoken: String)

@Test(arguments: [("pt", "pt"), ("PT", "pt"), ("pt-BR", "pt"), ("portuguese", "pt"), ("English", "en"), ("", nil), ("klingonese", nil)])
func readsWhisperLanguage(input: String, code: String?)
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path aaru-core --filter AssistantVoiceTests`
Expected: FAIL, types not defined.

- [ ] **Step 3: Implement `SilenceDetector`** with these values as named constants in one place, to tune on a device: silence 1.5 s, no-speech 8 s, cap 60 s, margin 10 dB over the floor, early loud -30 dB within the first 0.5 s. The floor is the rolling minimum of readings above -90 dB. A reading is speech when it is at least floor + margin, or in the early window at least the early loud level. `SpeechLanguage` matches full names against `Locale(identifier: "en_US").localizedString(forLanguageCode:)` over the ISO codes.

- [ ] **Step 4: Run to verify they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add aaru-core
git commit -m "feat(core): silence detection and read-aloud text (ASK-009)"
```

---

### Task 5: Mic, speech and permissions in the app

**Files:**
- Create: `aaru-ios/Aaru/Assistant/VoiceRecorder.swift`
- Create: `aaru-ios/Aaru/Assistant/ReplySpeaker.swift`
- Modify: `aaru-ios/Config/Aaru-Info.plist`
- Modify: `aaru-ios/Config/Aaru.entitlements`
- Modify: `aaru-ios/Aaru.xcodeproj/project.pbxproj:331,448` (app target only)

**Interfaces:**
- Produces:

```swift
@MainActor final class VoiceRecorder: NSObject {
    struct Recording { let data: Data; let seconds: Double }
    static func requestPermission() async -> Bool
    /// Called once if the system takes the mic away (a call). The recording is already discarded.
    var onInterrupted: (@MainActor () -> Void)?
    func start() throws
    /// Latest level in dBFS; nil while not recording.
    func power() -> Float?
    /// The audio, or nil under 0.3 s. Deletes the file either way.
    func stop() -> Recording?
    func discard()
}
@MainActor final class ReplySpeaker: NSObject {
    /// `language` is Whisper's as sent; the voice falls back to the device's.
    func speak(_ reply: String, language: String)
    func stop()
}
```

No automated test: there is no test target and these are thin over AVFoundation. The logic they depend on is in Task 4.

- [ ] **Step 1: Add the plist key and entitlement.**
  - `Aaru-Info.plist`: `NSMicrophoneUsageDescription` = `Aaru hears your question while you talk to it. It is turned into text on Aaru's own server and never stored.`
  - `Aaru.entitlements` (Mac only; iOS uses `Aaru-iOS.entitlements`): `com.apple.security.device.audio-input` true.
  - `project.pbxproj`: `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;` beside each `ENABLE_RESOURCE_ACCESS_LOCATION`. The Mac is sandboxed through build settings, so without this the mic is silently refused.
  - No `PrivacyInfo.xcprivacy` change: audio is held only to serve the request, and chat text is already `OtherUserContent`.

- [ ] **Step 2: Implement `VoiceRecorder`.** `AVAudioApplication.requestRecordPermission()`. AAC in `.m4a`, mono, 16 kHz, 32 kbps, metering on, `record(forDuration: 60)`, a uniquely named file in the temp directory. iOS session: `.record`, Bluetooth HFP input allowed, activated on start and deactivated with `.notifyOthersOnDeactivation` on stop. Watch `AVAudioSession.interruptionNotification` to discard and call `onInterrupted`. `#if os(iOS)` around every `AVAudioSession` use.

- [ ] **Step 3: Implement `ReplySpeaker`.** Text through `SpokenText.plain`. Voice: from `SpeechLanguage.code(from:)`, try `code-<device region>`, then `AVSpeechSynthesisVoice(language: code)`, then the first voice whose language has that prefix; nil code or no match uses the device default. iOS session: `.playback`, mode `.spokenAudio`, `.duckOthers`; deactivated from the delegate on finish or cancel. `stop()` is `stopSpeaking(at: .immediate)`.

- [ ] **Step 4: Build both platforms**

Run from `aaru-ios`:
```bash
xcodebuild build -project Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet; echo "ios=$?"
xcodebuild build -project Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet; echo "mac=$?"
```
Expected: `ios=0`, `mac=0`. Then `xcodebuild -project Aaru.xcodeproj -scheme Aaru -showBuildSettings -destination 'generic/platform=macOS' | grep AUDIO_INPUT` prints `YES`.

- [ ] **Step 5: Commit**

```bash
git add aaru-ios
git commit -m "feat(apple): record a question and read a reply aloud (ASK-009)"
```

---

### Task 6: `AssistantModel` and its wiring

**Files:**
- Create: `aaru-ios/Aaru/Assistant/AssistantModel.swift`
- Modify: `aaru-ios/Aaru/Session/AppServices.swift` (own one `AssistantModel`)
- Modify: `aaru-ios/Aaru/AaruApp.swift` (`.environment(services.assistant)` on the main window)
- Modify: `aaru-ios/Aaru/RootView.swift:98-108` (reset on sign-out)
- Modify: `aaru-ios/Aaru/MainTabs.swift` (status on return to the app; close when backgrounded)
- Modify: `aaru-ios/Aaru/Navigation/AppRouter.swift` (presentation state; clear in `reset()`)

**Interfaces:**
- Consumes: `ChatThread`, `ChatReply`, `ChatVoiceResult`, `Client.transcribeQuestion`, `SilenceDetector`, `VoiceRecorder`, `ReplySpeaker`.
- Produces:

```swift
// AppRouter
struct AssistantPresentation: Equatable {
    /// The sheet hosting the card; nil is the root host on the tab view.
    let hostID: UUID?
    let listening: Bool
    let hint: Components.Schemas.ChatHint?
}
var assistant: AssistantPresentation?   // nil is closed
func openAssistant(listening: Bool, titleID: String?, onTitlePage: Bool, hostID: UUID?)
func closeAssistant()

// Assistant/AssistantModel.swift
struct AssistantTurn: Identifiable { let id: UUID; let question: String; let spoken: Bool; var reply: ChatReply; var undone: Bool }
extension Notification.Name { static let aaruChatsDeleted }

@MainActor @Observable final class AssistantModel {
    enum Phase: Equatable { case idle, asking, listening, reading, answering }
    init(api: Client?, library: LibraryModel)
    private(set) var isAvailable: Bool       // /v1/chats/status assistant; false until known
    private(set) var voiceAvailable: Bool    // /v1/chats/status voice
    private(set) var phase: Phase
    private(set) var turns: [AssistantTurn]
    private(set) var micDenied: Bool
    private(set) var voiceProblem: String?
    private(set) var level: Float            // 0…1, for the mic's meter
    private(set) var libraryChanges: Int     // bumped after any applied change or undo; title pages reload on it
    var isMuted: Bool                        // UserDefaults "assistant.muted"; muting stops speech now
    func refreshStatus() async
    func opened(_ presentation: AssistantPresentation)
    func closed()                            // cancels the turn, discards a recording, stops speech; turns stay
    func send(_ text: String)                // trims; blank or over 4000 scalars does nothing
    func toggleListening()
    func undo(_ turnID: UUID) async -> String?
    func planDecided(_ plan: AgentPlan) async
    func reset() async                       // sign-out and Delete my chats: all of the above plus turns and the thread
}
```

Screen names for the hint come from `AppTab.rawValue`, which already matches the server's enum. `.settings` sends no hint. `onTitlePage` sends `screen: "title"`.

- [ ] **Step 1: Add the router state,** with `assistant = nil` in `reset()`.

- [ ] **Step 2: Implement `AssistantModel`.** These rules decide behaviour:
  - `opened`: `await thread.reopen()`; on false clear `turns`. With `listening` true and voice on, go to `toggleListening()`.
  - `toggleListening`, starting: stop speech first, so the mic cannot hear Aaru. `.asking` during permission. Denied sets `micDenied` and returns to `.idle` so typing still works. A 100 ms loop feeds `recorder.power()` to a fresh `SilenceDetector` and sets `level`.
  - `toggleListening`, stopping, or the detector stopping with `.silence` or `.cap`: `.reading`, upload, then `send`. `.noSpeech` or a recording under 0.3 s: no upload, `voiceProblem = "I didn't catch that. Try again, or type."`
  - Voice results: `.notHeard` as above; `.tooLong` "That was too long. Try a shorter question."; `.tooMany` "Too many spoken questions for now. You can still type."; `.off` hides the mic through `refreshStatus()` and says "Voice is off right now. You can still type."; `.failed(m)` shows `m`. The transcript goes through `send` marked spoken, with its language kept for the speaker.
  - `send`: `.answering`, append a turn, run `thread.send` in a held `Task`, copying each reply to the turn on the main actor. After every turn, however it ended, call `library.sync(api:)`: it is incremental, and a write applied before the card closed must still show. Run it in a new unstructured `Task`, because the held one may be cancelled and would cancel the request. Bump `libraryChanges` when the reply has `actionID`. If it failed, `refreshStatus()`. If spoken, not muted and not cancelled, speak the whole `reply.text` when the turn ends, or `reply.problem` when there is no text.
  - `closed`: cancel the held task, `recorder.discard()`, `speaker.stop()`, phase `.idle`.
  - `undo`: `library.undo(actionID, api:)`; on nil mark `undone` and bump `libraryChanges`.
  - `planDecided`: on `.applied` `library.sync(api:)` and bump `libraryChanges`.
  - Observe `.aaruChatsDeleted` to `reset()`. It is a notification because the Mac's Settings scene does not hold this model.

- [ ] **Step 3: Wire it.** `AppServices` builds the model after `library`. `RootView` calls `await assistant.reset()` beside `library.reset()`. `MainTabs`: inside the existing `.task(id: scenePhase)` on `.active`, `await assistant.refreshStatus()`; on `.background`, `router.closeAssistant()`. A failed status read keeps the last known value.

- [ ] **Step 4: Build both platforms** as in Task 5 Step 4. Expected: `ios=0`, `mac=0`.

- [ ] **Step 5: Commit**

```bash
git add aaru-ios
git commit -m "feat(apple): the assistant's model and wiring (ASK-009)"
```

---

### Task 7: The card and its host

**Files:**
- Create: `aaru-ios/Aaru/Assistant/AssistantCard.swift`
- Create: `aaru-ios/Aaru/Assistant/AssistantTurnView.swift`
- Create: `aaru-ios/Aaru/Assistant/AssistantComposer.swift`
- Create: `aaru-ios/Aaru/Assistant/AssistantHost.swift`
- Modify: `aaru-ios/Aaru/Groups/AgentViews.swift:124-180` (`AgentTitleCard` gains `var onOpen: ((TitleSummary) -> Void)? = nil`; channel callers unchanged)
- Modify: `aaru-ios/Aaru/MainTabs.swift` (`.assistantHost(...)` on the `TabView`, and inside the `linkedTitle` and Search sheets)
- Modify: `aaru-ios/Aaru/Share/SharePreviewView.swift`, and `aaru-ios/Aaru/Profile/ProfileView.swift` if it is shown as a sheet (both reach title pages)

**Interfaces:**
- Consumes: `AssistantModel`, `AppRouter.assistant`, `PlanCardView`, `AgentTitleCard`, `AaruAvatar`, `TitlePreviewView`, `CatalogHit(TitleSummary)` (exists, `Title/TitlePreviewView.swift:182`).
- Produces:

```swift
extension EnvironmentValues { @Entry var assistantHostID: UUID? = nil }
extension View {
    /// Mounts the card here. The root passes `isSheet: false`. A sheet's content passes true, because a
    /// card on the tab view would sit behind a sheet; the owl inside it carries this host's id.
    func assistantHost(api: Client?, library: LibraryModel, lists: ListsModel, isSheet: Bool) -> some View
}
```

- [ ] **Step 1: Implement `AssistantHost`.** A `ViewModifier` with a stable `@State` id (nil for the root), which sets `\.assistantHostID` and overlays the card only while `router.assistant?.hostID` matches. It calls `model.opened` and `model.closed` from `.onChange(of: router.assistant)` at the root host only, so a change is handled once. It holds `@State var openedTitle: CatalogHit?` and presents `.sheet(item:)` with a `NavigationStack { TitlePreviewView(...) }`, a Done button and `.catalogDestination(...)`. A card title tap calls `router.closeAssistant()` then sets `openedTitle`. A sheet from here works whether this host is the root or itself in a sheet, and `TitlePreviewView` already swaps to the Title room when the title is in the library. That sheet's content is a nominal `AssistantOpenedTitle: View` carrying `.assistantHost(isSheet: true)`, since its owl needs a host too; the named struct is what breaks the opaque-type cycle.

- [ ] **Step 2: Implement `AssistantCard`.**
  - Scrim: `Color(.night)` at a token alpha, tap closes.
  - Card: bottom aligned, `.lift()`, width to 560 pt centred on regular width and Mac, full width less 12 pt on compact. It keeps the keyboard's safe area so the composer rides above it.
  - Height follows content up to 70% of the container, then the turns scroll, staying pinned to the bottom while streaming.
  - Grabber and header: `AaruAvatar(size: 28, breathing: model.phase == .answering)`, "Aaru" in `Font.aaruDisplay`, mute toggle (`speaker.wave.2` / `speaker.slash`), Close. Mute shows only while voice is on.
  - Swipe down on the grabber and header closes past 80 pt or on a fast flick; the scroll view keeps its own drag.
  - Rise with a spring from `AaruMotion`, a fade under Reduce Motion. Escape and the VoiceOver escape action close it. `.accessibilityAddTraits(.isModal)`.
  - Local `@State var toasts = ToastCenter()` with `.toastCenter(toasts).undoToast()`, so `PlanCardView`'s Undo toast shows in the card and not dimmed behind it.
  - Empty: `Ask about your library, what's airing, or anything you're tracking.`

- [ ] **Step 3: Implement `AssistantTurnView`.**
  - Question, trailing, tinted.
  - Reply text from `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`, falling back to plain, with `.textSelection(.enabled)`.
  - Status line in `Color(.muted)`.
  - Titles: horizontal `AgentTitleCard(title:onAdd:onOpen:)`; `onAdd` is `library.add(CatalogHit($0), status: .wishlist, api:)`.
  - Plan: `PlanCardView(api:plan:onShowHistory:onDecided:)`; `onShowHistory` closes the card then `router.openHistory()`; `onDecided` calls `model.planDecided`.
  - Undo ribbon on every turn with `actionID`, spoken or typed: `actionSummary · Undo`, then `Undone.` Undo's problem text shows inline. The ribbon stays until the card clears; it is not a timed toast.
  - `reply.problem` in `Color(.danger)` for `.failed`, `.cutOff`; plain `Color(.muted)` for `.stopped`, since "Aaru is resting" is not a fault.

- [ ] **Step 4: Implement `AssistantComposer`.**
  - `TextField("Ask Aaru", text:, axis: .vertical).lineLimit(1...5)`, focused on open when not listening. Return sends on Mac; on iPhone the send button does.
  - Send button disabled while blank or `.answering`.
  - Mic button only when `voiceAvailable`. While listening the field becomes a level meter from `model.level` and "Listening…", and the mic shows stop. `.reading` shows "Reading what you said…".
  - `micDenied`: `Aaru can't use the microphone. Turn it on in Settings.` with a button: `UIApplication.openSettingsURLString` on iOS, `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone` on Mac.
  - `voiceProblem` as one muted line above the field.

- [ ] **Step 5: Mount.** Add `.assistantHost(..., isSheet: false)` on the `TabView` chain, after `.frame(minWidth:...)`, and `isSheet: true` on the `NavigationStack` in the `linkedTitle` sheet, on `SearchView` in the Search sheet, and at the root of any other sheet that reaches a title page. Find them with `grep -rn 'catalogDestination(\|LibraryEntryDestination(' aaru-ios/Aaru`: every result is pushed in a tab or sits in a sheet, and each sheet needs a host, or its owl opens a card hidden behind it.

- [ ] **Step 6: Build both platforms** as in Task 5 Step 4, then `swiftformat . --lint && swiftlint --strict --quiet` from `aaru-ios`. Expected: `ios=0`, `mac=0`, lint clean.

- [ ] **Step 7: Commit**

```bash
git add aaru-ios
git commit -m "feat(apple): the assistant card (ASK-009)"
```

---

### Task 8: The owl on every screen

**Files:**
- Modify: `aaru-ios/Aaru/Navigation/NavigationHelpers.swift`
- Modify: `aaru-ios/Aaru/Navigation/AaruCommands.swift`
- Modify: `aaru-ios/Aaru/Home/HomeScreen.swift`, `Discover/DiscoverScreen.swift`, `Library/LibraryView.swift`, `Calendar/CalendarScreen.swift`, `Lists/ListsScreen.swift`, `Social/FriendsScreen.swift`, `Groups/GroupsScreen.swift`, `Kinds/KindScreen.swift`, `Sports/SportsScreen.swift` (`SportsScreen` and the compact `SportsView`), `Insights/InsightsView.swift`
- Modify: `aaru-ios/Aaru/Title/TitleDetailView.swift`, `Title/TitlePreviewView.swift`

**Interfaces:**
- Consumes: `AppRouter.openAssistant`, `AssistantModel.isAvailable`, `AssistantModel.libraryChanges`, `\.assistantHostID`.
- Produces: `func assistantButton() -> some View` and `func assistantButton(titleID: String?) -> some View` beside `accountButton()`.

- [ ] **Step 1: Implement `AssistantButtonModifier`.** A `ToolbarItem(placement: .primaryAction)` holding a `Button` whose label is `OwlHead(size: 28)` in a 44 pt `contentShape`, shown only while `model.isAvailable`.
  - Tap: `openAssistant(listening: false, ...)`.
  - iOS: `.simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { ... })` opens with `listening: true`, fires `.sensoryFeedback(.impact, trigger:)`, and sets a `didLongPress` flag the Button action reads and clears, so lifting the finger does not also fire the tap. Keep the mic's first-run prompt in mind: the card must already be open when it appears.
  - `.accessibilityLabel("Ask Aaru")`, `.accessibilityAction(named: "Talk to Aaru") { ... }`, `.help("Ask Aaru (⌘K)")`.
  - Mac: click is tap; the card's mic is the way to talk.
  - If a TestFlight build shows the toolbar swallowing the gesture, move the long press to the label with `onLongPressGesture(minimumDuration:perform:)`. That is a known fallback, not a redesign.

- [ ] **Step 2: Add ⌘K.** In `AaruCommands`' `CommandGroup(after: .textEditing)`: `Button("Ask Aaru")` with `.keyboardShortcut("k", modifiers: .command)`, disabled while signed out. It calls `router.closeSheets()` first, because the root host's card would otherwise sit behind a sheet, then `router.openAssistant(listening: false, titleID: nil, onTitlePage: false, hostID: nil)`.

- [ ] **Step 3: Apply** `.assistantButton()` to each listed main screen, beside Search where the screen has one, and `.assistantButton(titleID:)` on title pages: `entry.title.id` in `TitleDetailView`, `title?.id` in `TitlePreviewView`.

- [ ] **Step 4: Reload a title page after Aaru changes it.** `TitleDetailView`: `.onChange(of: assistant.libraryChanges) { Task { await load() } }`, so episode ticks are not stale behind the card. Read the environment as optional, as `ProgressModel` is, so previews still build.

- [ ] **Step 5: Build both platforms and lint** as in Task 7 Step 6. Expected: `ios=0`, `mac=0`, lint clean.

- [ ] **Step 6: Commit**

```bash
git add aaru-ios
git commit -m "feat(apple): the owl in the top bar and on title pages (ASK-009)"
```

---

### Task 9: Settings, docs and the branch check

**Files:**
- Modify: `aaru-ios/Aaru/Settings/Models/DataModel.swift`
- Modify: `aaru-ios/Aaru/Settings/Pages/DataPage.swift`
- Modify: `aaru-ios/Aaru/Settings/Sections/ExportDataSection.swift:31`
- Modify: `DESIGN.md`, `BACKLOG.md:3774`

**Interfaces:**
- Consumes: `.aaruChatsDeleted` (Task 6).
- Produces: `DataModel.deleteChats() async`, `DataModel.deletingChats: Bool`.

- [ ] **Step 1: Add the delete row.** A new `Section` in `DataPage` after `ExportDataSection`:
  - `Button("Delete my chats with Aaru", role: .destructive)` with a confirmation dialog: title `Delete your chats with Aaru?`, message `This removes everything you and Aaru said. Changes Aaru made to your library stay, and your daily count of questions stays.`
  - `deleteChats()` calls `api.deleteChats()`, sets `problem` on failure, and on 204 posts `.aaruChatsDeleted`.
  - Footer: `Aaru keeps your chats until you delete them.`
  - Confirm the wording against `docs/privacy.md:285`. If they disagree, `privacy.md` wins and this copy changes.

- [ ] **Step 2: Fix the export footer.** `JSON has everything.` is no longer accurate. Read what `docs/privacy.md` now lists for the JSON export and write a footer that matches: `JSON has your account, library, lists and chats. The CSV opens in Numbers or Excel and can be imported back into Aaru.`, adjusted to the doc's list.

- [ ] **Step 3: Docs.** `DESIGN.md`: a short section for the assistant card and owl, covering the owl beside Search, tap versus long press, ⌘K, the floating card, mic states and the undo ribbon. It lacks one today. `BACKLOG.md` ASK-009: note iOS and Mac done, web next. `VIEWS.md` and `CLAUDE.md` already describe this surface.

- [ ] **Step 4: Full check**

```bash
swift test --package-path aaru-core; echo "core=$?"
swift test --package-path aaru-api; echo "api=$?"
./scripts/lint.sh; echo "lint=$?"
cd aaru-ios
xcodebuild build -project Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet; echo "ios=$?"
xcodebuild build -project Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet; echo "mac=$?"
```
Expected: every value `0`. Read each one: a pipe would hide the exit code.

- [ ] **Step 5: Commit**

```bash
git add aaru-ios DESIGN.md BACKLOG.md
git commit -m "feat(apple): delete my chats, and the docs for the card (ASK-009)"
```

- [ ] **Step 6: Device checks, after merge and a TestFlight build.** There is no UI test target, so these are the proof. First confirm the release lane ran: a cancelled Apple CI skips it. On iPhone, then Mac:
  1. Long press the owl on Lists: haptic, card, listening. Say "What's airing tonight?". It sends itself, the transcript shows, the answer streams and is read aloud. This is also the first proof of Haiku, the gate, Whisper from the pod and streaming through ingress.
  2. Tap the owl: type a question. Silent, no speech.
  3. Mute, ask by voice: no speech. Relaunch: still muted.
  4. On a title page, "mark this as watched": ribbon, the page and Library update without a relaunch; Undo reverts both.
  5. Something bulk: Plan card, Approve, Undo toast in the card.
  6. Speak Portuguese: Portuguese answer, Portuguese voice.
  7. "What's the stock market doing?": refused.
  8. Close mid-answer, reopen at once, ask again: no error. Say nothing after a long press: "I didn't catch that", no upload.
  9. Tap a title card: the card closes, the title opens. Owl from a title inside Search: the card sits above the sheet.
  10. Deny the mic: typing still works, and the Settings line opens Settings. A call during recording discards cleanly.
  11. Settings → Delete my chats with Aaru: the reopened card is empty. Sign out and in as someone else: nothing carried over.
  12. Mac: click, ⌘K, mic prompt, recording works in the sandbox.
  13. `agent_usage` rows, and the Console `aaru` workspace spend.
