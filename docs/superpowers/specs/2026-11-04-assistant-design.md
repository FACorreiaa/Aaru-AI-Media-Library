# Aaru assistant: long-press the owl, talk or type, get an answer (ASK-009)

## Context

The owner wants a Siri-like way to reach Aaru: long-press an AI button, a card pops up, talk or type, and Aaru replies. It must know the user's whole Aaru world whichever screen they are on.

The owner believed a ChatGPT-style chat already exists. It does not: on `origin/main` (6b0fabd4) there is no one-to-one chat, AI button, mic code, or streaming. Only `@aaru` in group channels exists (`internal/agent/reply.go`, non-streaming `model.Provider.Complete`). Ask Aaru (ASK-001…008) is an unbuilt design: `docs/superpowers/specs/2026-10-22-boards-and-ask-aaru-design.md`. The owner chose to build the assistant first, with only the engine it needs. The full Ask Aaru page reuses that engine later.

## Owner decisions (2026-11-04)

| Topic | Decision |
| --- | --- |
| Order | Assistant first; Ask Aaru page later on the same engine |
| Entry | An owl in the top bar of every main screen, beside Search |
| Surface | A floating card rising from the bottom over the dimmed current screen; grows with the reply; swipe down dismisses |
| Input | Talk or type |
| Context | Global: whichever screen, Aaru reads all of the user's own data (library, lists, stats, airing schedule, favorites, listens, followed sports) and the catalog. No friends' or groups' data |
| Access | Free for every account. A plan adding many titles counts as one capture against the free quota (3 a month); answers and one-item changes do not count |
| Sequence | The owner merges open PR #223 (`fix/go-audit`) first; this work branches from the resulting `main` |
| Replies | Written and read aloud |
| Library changes | Yes: one item like a tap (journaled, undoable), anything larger a `PlanCard` (X-009) |
| Speech languages | Not English-only |
| Platforms | iPhone, Mac, web together |

Standing decisions from 2026-10-22 that still apply: media-only scope with off-topic refused, personal suggestions only when asked, a "resting" state on out-of-credit.

The 2026-10-22 spec's budget line is out of date. Aaru's production key belongs to its own `aaru` Console workspace (`ANTHROPIC_WORKSPACE_ID` in the infra values; the old `haiku-trial` id 404s for this key). `@aaru`, capture and the assistant all draw on that key, so running out takes all three down. Its limit and balance are not visible from the repo: check them in the Console before launch.

This supersedes two recorded decisions; record both in `BACKLOG.md`: "No new chat surface" (BRD-004, 2026-10-23), and the sparkle "Ask" button as chat entry (2026-10-22).

## Calls I made (owner: check these)

- **Press:** long press (0.4 s, haptic) opens the card listening. Tap opens it ready to type, because long press alone is undiscoverable and inaccessible. Web and Mac clicks do the same as tap, plus a keyboard shortcut (one free on both clients).
- **Read aloud only when the question was spoken;** a typed question stays silent. A mute button persists locally.
- **Speech ends and sends itself:** recording stops on about 1.5 s of silence, on tapping the mic, or at the 60 s cap, then sends without a confirm step. The transcript shows in the card.
- **Language:** always `Systran/faster-whisper-small` with auto-detection; no language setting. English accuracy is slightly lower than `.en`, and very short clips can misdetect. Aaru answers in the language of the question.
- **Owl on title pages too,** beyond the main screens, because that is the one place "this show" means something. The client sends a small hint: `{ screen: <enum>, titleId?: <id> }`. Nothing free-form.
- **Closing the card cancels the turn** (CLAUDE.md: cancel in-flight work on disconnect). This replaces the 2026-10-22 spec's keep-running registry, polling and Stop endpoint. A write already applied stays journaled. An unfinished Aaru turn is stored as `stopped`.
- **Reopening within 15 minutes continues the same chat;** otherwise a new one. The client holds the chat id in memory.
- **Stored chats have no history UI yet, so users still control them:** "Delete my chats with Aaru" in Settings on both clients, included in the account export, removed with the account.
- **A chat write counts as the user's own choice, shown as Aaru's.** It sets `status_by_hand`, so "put this back to Plan to watch" holds against later imports and MAL's read-back, as a tap does. It journals under the existing `agent` actor, which History already shows as Aaru, so no migration of `actions_actor_check`. `library/prepare.go` sets by-hand only for `ActorUser` today, so chat needs an explicit way to ask for it.
- **Voice can write without a confirm.** A misheard sentence could apply one change straight away. Accepted because a single change shows the undo ribbon, and anything larger or any removal needs approval. Bigger risk with short clips, so a voice-originated write always shows the ribbon in the card.
- **No invented answers.** An in-scope question with no data behind it (web search is out) gets an honest "I can't see that yet". Questions about how Aaru works are answered only from what the system prompt states.
- **One daily ceiling.** Chat turns share `groups.AgentDailyCapPerUser` (30) with `@aaru`, as the 2026-10-22 spec said. No global spend guard in this version; the Console limit and the "resting" state are the backstop.

## Non-goals

- Ask Aaru page and history list (ASK-002, ASK-003), web search (ASK-004), images (ASK-007), Share to Board (ASK-008).
- Wake word, "Hey Aaru", the system Siri, or acting outside the app.
- Personalised rows anywhere else. Any paid speech API or transcode step. Storing audio.
- Answers outside media, the user's library, and Aaru itself.
- Any capability a tap lacks, or a second backend.

## Server (`aaru-server-v2`; tables → DTO/openapi → service → handlers)

- **Streaming provider.** `internal/model`: add streaming alongside `Complete` (text deltas, `tool_use` blocks, stop, usage). `internal/provider` transport buffers today and needs a streaming send. Group replies and capture stay on `Complete`. No `temperature`/`top_p`/`top_k`/prefill: read `platform/infra/docs/llm-haiku-trial.md` first. Keep `aaru_llm_calls_total` and out-of-credit detection working for streams.
- **Tables (goose).** `chats` (id, user_id, title from the first turn, timestamps). `chat_turns` (id, chat_id, role `user|agent`, body, components jsonb, state `streaming|done|failed|stopped`, timestamps). FK cascade from users. sqlc only.
- **Chat service.** `internal/agent/chat.go`, reusing the loop shape in `reply.go` (`MaxRounds`, metering through `RecordResponse`). Tools:
  - Reads: extract the shared parts of `GroupTools` (`group_tools.go`): `search_titles`, `title_details`, `list_airs`, `read_my_library`, `show_titles`. Add own-data reads, each over the existing service and scoped to the signed-in user: `read_my_stats` (`internal/stats`), `read_my_lists`, `read_my_favorites`, `read_my_listens` (`internal/music`), `read_my_sports` (`internal/sports`: follows and their fixtures, text only, since `VIEWS.md` gives the agent no Sports components; absent when sports is off). Nothing reads another user's data.
  - Write: `Tools.ApplyLibraryPatch` (`tools.go:365`), so single items apply and larger ones call `Plans.Propose`. Build the caller for a signed-in user's own chat without an agent token, as the write call above says. Update the "none writes" comments in `model.go` and `reply.go`.
  - Capture quota: a plan adding many titles spends one capture through `internal/billing` (`FreeCapturesPerMonth`). Over quota, Aaru says so in the card with the existing Plus line, and proposes no plan. The threshold is the same as tap-sized vs plan (`IsTapSized`): removals and other non-add plans do not spend.
  - Spoiler guard from the user's own progress, as in GRP-011.
- **Scope gate.** A tiny classification call before the agent loop, fail-closed, that sees the last few turns so follow-ups ("and season two?") pass, and works in any language. Out of scope returns a canned line with no main call. The system prompt repeats the scope and includes date, time zone and the screen hint.
- **Caps.** 30 Aaru replies per user per UTC day across chat and `@aaru` (`groups.AgentDailyCapPerUser`), plus a transcription rate limit (`internal/ratelimit`). Over cap or out of credit reads "Aaru is resting".
- **Transcription.** `internal/transcription`, type named for the wire format (`OpenAICompatible`, as Norviq's `internal/platform/transcription`). Base URL and model come from config. Off when unconfigured, and clients hide the mic. Hold audio in memory, never store it; refuse over 60 s / 8 MB. Pass in-progress library titles as the `prompt` vocabulary hint. Return `{ text, language }`.
- **Endpoints** (`aaru-server/Sources/AppAPI/openapi.yaml`, then `make generate`, `scripts/generate-api-client.sh`, `npm run api:generate`):
  - `POST /v1/chats`
  - `POST /v1/chats/{id}/turns`: `text/event-stream` with events `status` ("Checking your library"), `delta`, `components`, `done`, `error`. No SSE exists yet: confirm flushing past echo middleware (compression, timeouts), and past cluster ingress.
  - `POST /v1/chats/transcribe`: audio body, as the import endpoint's `application/octet-stream`.
  - `DELETE /v1/chats`: delete all of the user's chats.
- Add chats to `internal/export`.

## iOS and Mac (`aaru-ios`)

- `Aaru/Assistant/`: `AssistantCard`, `AssistantModel` (`@Observable`, streaming), `VoiceRecorder` (`AVAudioRecorder`, m4a, metering for silence), `ReplySpeaker` (`AVSpeechSynthesizer`, free and on-device; voice by language: the transcribed one, else device; Markdown stripped; stops on dismiss).
- `.assistantButton()` in `Navigation/NavigationHelpers.swift`, next to `accountButton()`. Applied to each main screen and `TitleDetailView`. A `ToolbarItem` with `OwlHead` that keeps `Button` for tap with a simultaneous long-press gesture. Add an accessibility action "Talk to Aaru".
- Mount the card once as an overlay on the `TabView` in `MainTabs.swift`, state in `AppRouter`, so it sits above the tab bar. Tapping a title card dismisses and navigates.
- Reuse `Groups/AgentViews.swift` and `Approvals/PlanCardView.swift`. `aaru-breathe`-style breathing while working; respect Reduce Motion.
- Add `NSMicrophoneUsageDescription`, and the Mac `com.apple.security.device.audio-input` entitlement. Denied mic falls back to typing with a line pointing at Settings.
- Settings: "Delete my chats with Aaru".

## Web (`aaru-client`)

- **Change `Permissions-Policy` in `src/start.ts:24` to `microphone=(self)`.** Today's `microphone=()` blocks recording outright.
- `components/assistant/`: `AssistantCard` on `Drawer` from `~/components/ui`, `AssistantButton`, recorder on `MediaRecorder` (webm, or mp4 on Safari; both accepted as-is) with an `AnalyserNode` for silence, `speechSynthesis` for replies. Lazy-load it and check `npm run size`.
- Owl beside Search in both places in `components/shell/AppShell.tsx`: the phone header and `SidebarHeader` (desktop has no top bar). Press-and-hold on pointer events, suppressing the phone context menu and text selection. Motion through `lib/motion.ts`.
- Stream through a Worker route carrying the cookie session, as `lib/export/proxy.ts`; `lib/api/client.ts` is server-only. Reuse `groups/AgentParts.tsx` and `PlanCard.tsx`.
- Settings: "Delete my chats with Aaru". Tokens only, no hex, per `ci-brand.yml`. No raw `button`/`textarea`.

## Infra (`platform/infra`, owner merges)

- `cluster/network-policies/horus.yaml`: add a `podSelector` for `app.kubernetes.io/name: aaru-api` to `allow-whisper`, with `matchLabels`. Without it the failure looks like the service being down.
- Aaru values: transcription base URL `http://whisper.horus.svc.cluster.local:8000/v1`, model `Systran/faster-whisper-small` (already preloaded). `platform/infra/docs/transcription.md` applies.

## Docs (privacy first, owner rule 2026-10-21)

- `docs/privacy.md`: voice goes to Aaru's own server and is transcribed on its own cluster, never stored; chat text goes to Anthropic as processor; chats are kept until the user deletes them.
- `BACKLOG.md`: ASK-009 (grep `origin/main` for a collision first) and the 2026-11-04 decisions. `CLAUDE.md`: Stack row, domain term **Assistant card**. `ARCHITECTURE.md`, `DESIGN.md`, `VIEWS.md`: the surface, and that its chrome is never agent-emitted; cards stay catalog components.

## Build order (own worktree off `origin/main`, one PR each)

0. Owner merges PR #223 (`fix/go-audit`). It changes `provider/transport.go`, `agent/reply.go`, `plans/service.go`, `library/prepare.go` and `export.go`, and takes migrations `00002` and `00003`, so the chat tables follow it. The next API promote ships the audit fixes as well as this work.
1. Docs and privacy, with server: streaming, tables, chat service, endpoints, tests.
2. Infra PR: `allow-whisper` and values; manual promote of the API (infra PR, api tag + cronjob image).
3. iOS and Mac.
4. Web.

## Verification

- **Server** (`AARU_REQUIRE_DB=1 make test`, `golangci-lint run ./...`), stub HTTP servers and never a real key: SSE event sequence; off-topic refused with no main call; classifier error fails closed; a follow-up passes the gate; one-item write applied and undoable, with `status_by_hand` set and journaled as `agent`; larger becomes a plan; a many-title plan spends one capture and over quota proposes none; a question with no data behind it gets "I can't see that yet"; every read tool returns only the caller's data; disconnect stores `stopped`; the shared cap across chat and `@aaru`; `agent_usage` rows; request bodies have no sampling fields; transcription stub receives model and prompt, oversize refused; `DELETE /v1/chats`; another user's chat is 404. `curl -N` shows chunks arriving incrementally.
- **Web:** `npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size`. On beta at desktop and 390 px: hold to talk, click to type, stream, read aloud, mute, plan card, denied mic.
- **Apple:** `xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`, then on a device through TestFlight (not locally), and check the release lane ran.
- **Live, after promote:** ask from a screen unrelated to the answer ("What's airing tonight?" from Lists). Ask "mark this as watched" on a title page, and undo. Ask something bulk, and approve it. Speak in English and in Portuguese. Ask about the stock market and get refused. Confirm in logs that whisper is reached, and check `agent_usage` and the spend on the Console `aaru` workspace.
