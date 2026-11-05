# Aaru assistant, server (ASK-009, build step 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A streaming one-to-one chat with Aaru on `/v1`: all of the user's own data, one-item writes like a tap, larger writes as plans, and speech to text, ready for the iOS, Mac and web assistant cards.

**Architecture:** `internal/agent/chat.go` runs the same model loop as `reply.go`, over a streaming provider that returns the same `model.Response`. Its events reach clients as SSE from a raw echo route documented in `openapi.yaml`, as `POST /v1/imports/csv` is. Chat writes reuse `Tools` and `plans.Service` through a tokenless caller.

**Tech Stack:** Go, echo v4, pgx, sqlc, goose, oapi-codegen strict server; Anthropic Messages API (`claude-haiku-5-5`); cluster Whisper (OpenAI-compatible).

**Spec:** `docs/superpowers/specs/2026-11-04-assistant-design.md`. Client and infra steps get their own plans after this merges.

**Work in:** the worktree `../aaru-wt-assistant`, branch `feat/assistant-server`, based on `origin/main` at ef63b887 (PR #223 merged). Run commands from `aaru-server-v2` unless noted.

## Global Constraints

- Anthropic requests carry no `temperature`, `top_p`, `top_k` or prefill. Read `platform/infra/docs/llm-haiku-trial.md` before Task 2.
- Tests never use a real API key: stub HTTP servers, or `scriptedModel` from `internal/httpapi/agent_reply_test.go`.
- No vendor in a type name outside its adapter: `transcription.OpenAICompatible`.
- sqlc only; no ad-hoc SQL in handlers. `make generate` after an `openapi.yaml` or query change.
- Domain words: **Chat**, **Chat turn**. Never "Conversation" or "Message" (those are E2E DMs).
- Blocks hide nothing here, because nothing reads another user. Another user's chat answers 404, never 403.
- `gofumpt`, `go vet`, `golangci-lint run ./...` clean; errors wrapped, never dropped.
- Exact values: 30 replies a UTC day shared with `@aaru`; audio at most 60 s and 8 MB, held in memory only; model `Systran/faster-whisper-small`, from config; `MaxRounds` 4.
- Exact copy: resting "Aaru is resting. Try again later."; unknown data "I can't see that yet."; out of scope "I can only help with films, shows, anime, books, music, sport and your Aaru library."

## Review Focus

1. **The API restarts mid-turn:** a `streaming` row is left behind and must not block that chat forever. Pinned in Task 3.
2. **Two sends at once on one chat** (double tap, two devices): the second gets 409 `chat_busy`, and no second model call. Pinned in Task 8.
3. **The client hangs up during a tool round:** the turn stores `stopped` with its partial text, using a context that survives the cancel, and a write already applied stays. Pinned in Task 6.
4. **A follow-up in another language or with no nouns** ("e a segunda temporada?") passes the scope gate because the gate sees earlier turns. Pinned in Task 6.
5. **Silent or empty audio:** Whisper returns blank text; respond 422 `transcription_empty` rather than sending an empty turn. Pinned in Task 7.

---

### Task 1: Privacy and decisions, first

Owner rule 2026-10-21: `docs/privacy.md` changes first.

**Files:**
- Modify: `docs/privacy.md`, `BACKLOG.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `DESIGN.md`, `VIEWS.md`

**Interfaces:** none.

- [ ] **Step 1: `docs/privacy.md`.** Update "Last updated". Under "What Aaru stores" add **Your chats with Aaru**: chats are kept until the user deletes them in Settings, are in the export, and go with the account. Add **Voice**: audio goes to Aaru's server and is transcribed on Aaru's own cluster, held in memory, never stored, never sent to a third party. Extend Anthropic in "Who else is involved": also when you ask Aaru, it receives your question, recent turns, and the parts of your own library, lists, stats, favorites, listens and followed sports Aaru reads to answer; no friends' or groups' data; no training.
- [ ] **Step 2: `BACKLOG.md`.** Check IDs with `git grep -n "ASK-009" origin/main`. Add ASK-009 under `P7 · Ask Aaru`, and a dated 2026-11-04 decision copying the spec's owner table. Say it supersedes "No new chat surface" (BRD-004) and the sparkle "Ask" entry, and that ASK-001, -005 and -006 are delivered inside it. Fix the budget line: Aaru uses its own `aaru` workspace.
- [ ] **Step 3: `CLAUDE.md`, `ARCHITECTURE.md`, `DESIGN.md`, `VIEWS.md`.** `CLAUDE.md`: Stack rows (Transcription, Assistant), domain term **Assistant card**, and an owner exception in "Later phases". `ARCHITECTURE.md`: chat boundary. `DESIGN.md`, `VIEWS.md`: the surface, chrome never agent-emitted, cards from the catalog.
- [ ] **Step 4: Commit** `docs: Aaru assistant decisions and privacy (ASK-009)`.

---

### Task 2: Streaming provider

**Files:**
- Modify: `internal/provider/transport.go`, `internal/model/model.go`, `internal/model/anthropic.go`
- Create: `internal/model/stream.go`
- Test: `internal/model/stream_test.go`

**Interfaces:**
- Produces:
  - `provider.StreamResponse{Status int; Body io.ReadCloser; Header http.Header}`
  - `(*provider.HTTPTransport).Stream(ctx, req provider.Request) (*provider.StreamResponse, error)`: no body buffering, and `req.Timeout` bounds the whole read.
  - `model.Streamer` interface: `Stream(ctx, req Request, onText func(string)) (Response, error)`.
  - `model.StreamOrComplete(ctx, p Provider, req Request, onText func(string)) (Response, error)`: uses `Streamer` when `p` has it; otherwise `Complete`, then one `onText` with the whole text. Fakes such as `scriptedModel` keep working.
- `AnthropicMessages` gains `Stream`. `Provider` itself does not change, so group replies and capture are untouched.

- [ ] **Step 1: Write failing tests** in `stream_test.go`, against an `httptest.Server` serving recorded SSE:
  - `TestStreamText`: `onText` gets `"Sev"`, `"erance"` in order; `Response.Text() == "Severance"`; `Stop == StopDone`; tokens from `message_start` and `message_delta`.
  - `TestStreamToolUse`: `input_json_delta` chunks rebuild `Input` so `ToolCalls()[0].Input` equals `{"query":"dune"}`; `Stop == StopToolUse`; `Response.Content` replays as a valid assistant turn.
  - `TestStreamNoSampling`: decoded request body has `stream: true` and no `temperature`, `top_p`, `top_k`.
  - `TestStreamOutOfCredit`: 400 with "usage limit" gives `*ProviderError{OutOfCredit: true}`, and `aaru_llm_calls_total{result="out_of_credit"}` rises.
  - `TestStreamErrorEvent`: an SSE `error` event mid-stream gives `*ProviderError`.
  - `TestStreamCancel`: cancelling ctx mid-stream returns promptly with `context.Canceled`.
  - `TestStreamOrCompleteFallback`: a Provider-only fake gets one `onText` with the whole text.
- [ ] **Step 2: Run:** `go test ./internal/model/ -run Stream`. Expected: FAIL, undefined `model.Streamer`.
- [ ] **Step 3: Implement.** Reuse `AnthropicBody` and add `"stream": true`. Share headers and the stop-reason mapping with `call` and `ParseAnthropic` by extracting them. Rebuild `text`, `tool_use` and `thinking` blocks; keep any block type the adapter does not recognise from its `content_block_start`, so unknown blocks still replay. Timeout default 120 s.
- [ ] **Step 4: Run:** `go test ./internal/model/ ./internal/provider/`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): streaming model calls (ASK-009)`.

---

### Task 3: Chat tables and store

**Files:**
- Create: `internal/db/migrations/00004_chats.sql`, `internal/db/queries/chats.sql`, `internal/agent/chatstore.go`
- Modify: `internal/db/queries/groups.sql` (`GroupAgentLoad`), `internal/db/queries/billing.sql` (`BillingCapturesSince`), the capture count behind `capture.Store.Captures`
- Test: `internal/agent/chatstore_test.go`

**Interfaces:**
- Produces, on `agent.ChatStore{Q *sqlc.Queries}`:
  - `CreateChat(ctx, user) (uuid.UUID, error)`
  - `Chat(ctx, id, user) (*Chat, error)`: nil for someone else's or missing
  - `BeginTurn(ctx, chat, user uuid.UUID, body string, now time.Time) (userTurn, agentTurn uuid.UUID, err error)`: `ErrChatBusy` when another turn is streaming
  - `FinishTurn(ctx, turn uuid.UUID, state, body string, components json.RawMessage, now time.Time) error`
  - `RecentTurns(ctx, chat, limit) ([]ChatTurn, error)`, oldest first
  - `RepliesToday(ctx, user, now) (int, error)`: `@aaru` replies plus chat turns
  - `DeleteAll(ctx, user) error`; `ForExport(ctx, user) ([]ChatWithTurns, error)`
- Constants: `TurnStreaming`, `TurnDone`, `TurnFailed`, `TurnStopped`.

- [ ] **Step 1: Write failing tests** (`testdb.New`):
  - `TestBeginTurnBusy`: a second `BeginTurn` while the first streams returns `ErrChatBusy`.
  - `TestBeginTurnClearsStale`: an agent turn `streaming` for over 5 minutes becomes `failed`, and `BeginTurn` succeeds.
  - `TestChatOtherUser`: `Chat` as another user is nil.
  - `TestUserDeleteCascades`: deleting a user removes chats and turns.
  - `TestRepliesTodayShared`: 2 `agent_replies` in counting states + 3 user chat turns today = 5; yesterday's excluded.
  - `TestGroupAgentLoadCountsChat`: `user_today` includes today's chat turns, so 30 chat turns caps `@aaru`.
  - `TestChatPlanSpendsCapture`: a row in `agent_plans` with `spends_capture = true` adds 1 to `BillingCapturesSince` and `Captures`; `false` adds nothing.
- [ ] **Step 2: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ -run 'Turn|Chat|Replies'`. Expected: FAIL to compile.
- [ ] **Step 3: Migration `00004_chats.sql`.**

```sql
-- +goose Up
CREATE TABLE chats (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chats_user ON chats (user_id, updated_at DESC);
CREATE TABLE chat_turns (
    id uuid PRIMARY KEY,
    chat_id uuid NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('user', 'agent')),
    body text NOT NULL DEFAULT '',
    components jsonb,
    state text NOT NULL CHECK (state IN ('streaming', 'done', 'failed', 'stopped')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chat_turns_chat ON chat_turns (chat_id, created_at);
CREATE INDEX chat_turns_user_day ON chat_turns (user_id, created_at) WHERE role = 'user';
CREATE UNIQUE INDEX chat_turns_one_streaming ON chat_turns (chat_id) WHERE state = 'streaming';
ALTER TABLE agent_plans ADD COLUMN spends_capture boolean NOT NULL DEFAULT false;
```

Include a matching `-- +goose Down`. Check the users table name and the Down convention against `00002` and `00003`.

- [ ] **Step 4: Queries and store.** `GroupAgentLoad`'s `user_today` adds today's `role = 'user'` chat turns. `BillingCapturesSince` and the query behind `capture.Store.Captures` add `agent_plans` rows with `spends_capture` since the same start. `make generate`. `BeginTurn` first fails that chat's stale streaming turns, and maps the unique violation to `ErrChatBusy`.
- [ ] **Step 5: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ ./internal/billing/ ./internal/imports/ ./internal/groups/ ./internal/db/...`. Expected: PASS, including `baseline_test.go`.
- [ ] **Step 6: Commit** `feat(server): chat tables, shared caps, plans that spend a capture (ASK-009)`.

---

### Task 4: Chat writes: a tap, shown as Aaru

The spec's journal call needs `library` and `plans` to accept a caller with no agent token. `plans.Propose` and `plans.prepare` take `auth.AgentCaller` and read `caller.Token` today; `Tools.apply` builds an `ActorExternalAgent` caller.

**Files:**
- Modify: `internal/library/types.go`, `internal/library/prepare.go`, `internal/plans/service.go`, `internal/plans/store.go`, `internal/plans/types.go`, `internal/agent/tools.go`
- Test: `internal/agent/chatwrite_test.go`

**Interfaces:**
- Produces:
  - `library.Caller.ByHand bool`, and `library.ChatCaller = Caller{Actor: ActorAgent, ByHand: true, AgentName: ptr("Aaru")}`. `prepare.go`'s three `caller.Actor == ActorUser` by-hand checks (lines 51, 88, 250) become `caller.setsByHand()`, meaning `Actor == ActorUser || ByHand`.
  - `plans.Origin{UserID uuid.UUID; TokenID *uuid.UUID; Name string; Caller library.Caller; SpendsCapture bool}`, and `plans.Service.ProposeFor(ctx, changes, origin) (Plan, error)`. `Propose` becomes a thin wrapper building an `Origin` from `auth.AgentCaller`. Pending limit for a nil token counts by user and the name `"Aaru"`.
  - `agent.ErrCaptureQuota` wrapping the quota message; `(*Tools).ChatPatch(ctx, in PatchInput, user uuid.UUID) (ChatPatchResult, error)`, with `ChatPatchResult{Applied bool; Item *library.Entry; ActionID *uuid.UUID; Plan *plans.Plan}`. `ActionID` comes from a new sqlc query for the user's latest action on that item.
  - `Tools.Quota func(ctx, user) error`: `imports.Service.checkCaptureQuota` exported as `CheckCaptureQuota`, set at wiring.

- [ ] **Step 1: Write failing tests:**
  - `TestChatPatchOneItem`: one `add` applies; `Applied`; `ActionID` set; journal row actor `agent`; `status_by_hand` true; undo through `library` restores it.
  - `TestChatPatchWishlistNotByHand`: a `wishlist` add leaves `status_by_hand` false, as a tap's does.
  - `TestChatPatchHoldsAgainstImport`: a chat move back to `wishlist` survives an import merge that would move it forward.
  - `TestChatPatchBulkPlan`: two adds give a pending `Plan`, `Applied` false, `agent_token_id` NULL, `agent_name` "Aaru", `spends_capture` true; approving via `plans.Service.Approve` applies it.
  - `TestChatPatchRemovePlanNoSpend`: one removal gives a plan with `spends_capture` false.
  - `TestChatPatchQuota`: at quota, two adds return `ErrCaptureQuota` and no plan row; one add still applies.
  - `TestExternalAgentUnchanged`: `ApplyLibraryPatch` with a token still journals `external_agent` and leaves by-hand false.
- [ ] **Step 2: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ -run ChatPatch`. Expected: FAIL.
- [ ] **Step 3: Implement.** `apply` takes `library.Caller` instead of building it from the token. `plans.prepare` takes `library.Caller`. A plan spends a capture when `CountsOf(writes)` shows two or more adds, checked after `prepare`, so changes that would do nothing do not spend.
- [ ] **Step 4: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ ./internal/plans/ ./internal/library/ ./internal/httpapi/ -run 'Chat|Plan|Agent|MCP'`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): chat writes journal as Aaru and hold like a tap (ASK-009)`.

---

### Task 5: Chat's read tools

**Files:**
- Modify: `internal/agent/group_tools.go`, `internal/agent/reply.go` and `internal/model/model.go` (the "none writes" comments)
- Create: `internal/agent/title_reads.go`, `internal/agent/chat_tools.go`
- Test: `internal/agent/chat_tools_test.go`

**Interfaces:**
- Consumes: `(*Tools).ChatPatch` from Task 4.
- Produces:
  - `titleReads{Catalog *catalog.Kit; Library *library.Service; User uuid.UUID; refs map[string]core.MediaRef; cards []core.Title}`: `search`, `details`, `airs`, `myLibrary`, `show`, `remember`, `resolve`, moved from `GroupTools`, which embeds it. `GroupToolDefinitions` and group behaviour do not change.
  - `ChatDeps{Tools *Tools; Stats *stats.Service; Lists *library.Store; Favorites *social.Service; Music *music.Service; Sports *sports.Service}`; a nil `Sports` means the tool is left out.
  - `ChatTools` with `Definitions() []model.Tool` and `results(ctx, calls) model.Turn`. Names: the five shared, plus `read_my_stats`, `read_my_lists`, `read_my_favorites`, `read_my_listens`, `read_my_sports`, `apply_library_patch`. Exposes `Cards()`, `Plan()`, `ActionID()`, `ActionSummary()`.

- [ ] **Step 1: Write failing tests:**
  - `TestReadsOnlyCaller`: two users with distinct data; each `read_my_*` run as A contains A's marker and not B's.
  - `TestSportsAbsentWhenOff`: nil `Sports` removes `read_my_sports` from `Definitions()`.
  - `TestPatchToolApplies`: the tool with a `r1` ref from an earlier `search_titles` applies; result text says applied.
  - `TestPatchToolPlan`: bulk result text says it needs approval in Aaru; `Plan()` is set; text never says applied.
  - `TestPatchToolQuota`: the result text carries the quota message, `is_error` set.
  - `TestGroupToolsStillReadOnly`: `GroupToolDefinitions` has no write tool. Existing `agent_reply_test.go` and `agent_parity_test.go` pass unchanged.
- [ ] **Step 2: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ -run 'Reads|Sports|PatchTool|GroupTools'`. Expected: FAIL.
- [ ] **Step 3: Implement.** Move first, with no behaviour change, then add. Tool output is short text lines, as `myLibrary` writes them, with limits: stats one period (current month unless asked), lists names with counts and up to 30 titles per list, listens latest 50, sports follows and next fixtures. `read_my_sports` output is text only. In `apply_library_patch`, titles enter by `r` refs; item ids come from `read_my_library` refs.
- [ ] **Step 4: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ ./internal/httpapi/ -run 'Agent|Group|Reads|Sports|PatchTool'`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): Aaru's tools over the user's own data (ASK-009)`.

---

### Task 6: Scope gate and the chat turn

**Files:**
- Create: `internal/agent/chat.go`, `internal/agent/scope.go`
- Test: `internal/agent/chat_test.go`, `internal/agent/scope_test.go`

**Interfaces:**
- Consumes: `ChatStore` (Task 3), `ChatTools` (Task 5), `model.StreamOrComplete` (Task 2).
- Produces:
  - `agent.Hint{Screen string; TitleID *uuid.UUID}`. `Screen` in `home|discover|library|calendar|lists|friends|groups|books|manga|music|sports|insights|title`; anything else is dropped.
  - `agent.ChatEvent{Type string; Text string; Titles []core.Title; Plan *plans.Plan; ActionID *uuid.UUID; ActionSummary string; TurnID *uuid.UUID; Code string}`. `Type` in `status|delta|components|done|error`.
  - `(*ChatService).Turn(ctx, user, chat uuid.UUID, body string, hint Hint, emit func(ChatEvent)) error`. Returns `ErrChatBusy` and nil-chat as errors before any event; everything after arrives as events.
  - `InScope(ctx, p model.Provider, recent []ChatTurn, body string) (bool, error)`: forced tool `record_scope` with `{in_scope: boolean}`, `MaxTokens` 64. Any error, or no call, returns the error, and the turn fails closed.
  - `agent.MaxChatContext = 12` turns.

- [ ] **Step 1: Write failing tests** with `scriptedModel` (move to a shared test helper if needed):
  - `TestTurnEvents`: script gate-yes, a `read_my_library` tool call, then text. Events in order: `status` "Checking your library", `delta`…, `done`. Stored agent turn `done` with the full body.
  - `TestOffTopicNoMainCall`: gate-no gives one model call; canned out-of-scope text as `delta` then `done`.
  - `TestGateErrorFailsClosed`: gate error gives an `error` event with code `try_again`, no main call, turn `failed`.
  - `TestFollowUpGateSeesTurns`: the gate request contains earlier turns' text, so `e a segunda temporada?` is judged with context.
  - `TestDisconnectStoresStopped`: cancel during the second round. Stored turn `stopped`, with partial body, written despite the cancelled ctx; a write from the first round stays.
  - `TestRestingAtCap`: 30 replies today gives `error` code `resting`, with no model call and no gate call.
  - `TestOutOfCredit`: provider `OutOfCredit` gives code `resting`, turn `failed`.
  - `TestComponentsEvent`: `show_titles` gives `components` with titles, stored in `components`, capped at `MaxCards`.
  - `TestUsageMetered`: gate and main calls each add to `agent_usage`.
  - `TestSystemPrompt`: has date, zone from `reqctx.TimeZone`, the hint's title name, the scope, and "I can't see that yet", and no other user's data.
  - `TestHintUnknownDropped`: `Screen: "evil"` never reaches the prompt.
  - `TestMaxRounds`: four tool rounds ending with no text store `FailureReply`.
  - `TestTitleFromFirstTurn`: first turn sets `chats.title`, trimmed to 80 characters.
- [ ] **Step 2: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/ -run 'Turn|Scope|Gate|Topic|Resting|Credit|Disconnect|Components|Usage|SystemPrompt|Hint|MaxRounds|Title'`. Expected: FAIL.
- [ ] **Step 3: Implement.** Same loop shape as `Answer`, with `RecordResponse` after each round and `context.WithoutCancel` to store the last state. A `status` event names each tool on the way: `read_my_library` "Checking your library", `list_airs` "Looking at what's airing", and so on. The prompt tells Aaru to answer in the question's language, keep replies short enough to read aloud, give suggestions only when asked, and guard spoilers with the user's own progress as `System` does for GRP-011. Apply a 4-minute ceiling to the whole turn.
- [ ] **Step 4: Run:** `AARU_REQUIRE_DB=1 go test ./internal/agent/`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): the chat turn, with a fail-closed scope gate (ASK-009)`.

---

### Task 7: Transcription

**Files:**
- Create: `internal/transcription/transcription.go`
- Modify: `internal/config/config.go`
- Test: `internal/transcription/transcription_test.go`, `internal/config/config_test.go`

**Interfaces:**
- Produces:
  - `transcription.OpenAICompatible{BaseURL *url.URL; Model string; Transport provider.Transport; Timeout time.Duration}`
  - `(*OpenAICompatible).Transcribe(ctx, audio []byte, contentType, prompt string) (Result, error)`, `Result{Text, Language string}`
  - `transcription.ErrEmpty`
  - `config.Transcription{BaseURL *url.URL; Model string}`, nil when `TRANSCRIPTION_BASE_URL` is unset; `Model` from `TRANSCRIPTION_MODEL`, required with the URL.

- [ ] **Step 1: Write failing tests** against an `httptest.Server`:
  - `TestMultipartShape`: `POST /audio/transcriptions` under the base URL; fields `model=Systran/faster-whisper-small`, `prompt`, `response_format=verbose_json`; a `file` part with the bytes; no `language` field; no auth header.
  - `TestResult`: `{"text":" Hello ","language":"pt"}` gives trimmed `Hello` and `pt`.
  - `TestEmpty`: blank text gives `ErrEmpty`.
  - `TestServerError`: 500 gives a wrapped error, never the audio in the message.
  - `TestConfig`: URL unset gives nil; URL without model is a config error.
- [ ] **Step 2: Run:** `go test ./internal/transcription/ ./internal/config/`. Expected: FAIL.
- [ ] **Step 3: Implement.** Filename extension by content type: `audio/mp4`, `audio/m4a` → `.m4a`; `audio/webm` → `.webm`. Timeout 60 s. Check the `verbose_json` field against the Speaches image in use.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): transcription over the OpenAI wire format (ASK-009)`.

---

### Task 8: The API

**Files:**
- Modify: `aaru-server/Sources/AppAPI/openapi.yaml`, `internal/httpapi/raw_routes.go`, `internal/httpapi/router.go`, `internal/httpapi/server.go`, `internal/httpapi/export.go`, `internal/export/export.go` as needed
- Create: `internal/httpapi/chat.go`
- Test: `internal/httpapi/chat_test.go`, `internal/httpapi/export_test.go`

**Interfaces:**
- Consumes: `ChatService.Turn` (Task 6), `OpenAICompatible` (Task 7), `ChatStore` (Task 3).
- Produces, for the client plans:
  - `POST /v1/chats` → 201 `{ id }`
  - `POST /v1/chats/{id}/turns`, body `{ body: string (1…4000), hint?: { screen, titleId? } }` → `text/event-stream`. Each frame is `event: <type>` and `data: <json>`. `delta`/`status`: `{text}`; `components`: `{titles?, plan?, actionId?, actionSummary?}`; `done`: `{turnId}`; `error`: `{code, message}`, `code` in `resting|try_again`. 404 unknown chat, 409 `chat_busy`, 503 `agent_unavailable` when `Model` is nil.
  - `POST /v1/chats/transcribe`, `application/octet-stream` or `audio/*`, `X-Audio-Seconds` optional → `{ text, language }`. 413 `file_too_large` over 8 MB; 413 `audio_too_long` when the header says over 60; 422 `transcription_empty`; 429 `rate_limited` at 40 an hour per user; 503 `transcription_unavailable` when unconfigured.
  - `DELETE /v1/chats` → 204.
  - `GET /v1/chats/status` → `{ assistant: boolean, voice: boolean }`, so clients hide the owl and the mic when the server has them off.
  - `AccountExport.chats` optional: `[{ title?, createdAt, turns: [{ role, body, createdAt }] }]`.

- [ ] **Step 1: Write failing tests** (server harness, `scriptedModel`, stub Whisper):
  - `TestTurnSSE`: signed-in POST reads `text/event-stream`; frames parse in order; `Cache-Control: no-store`, `X-Accel-Buffering: no`; each frame flushed: the test reads the first `delta` while the fake is blocked before its next one.
  - `TestTurnUnauthenticated`: 401.
  - `TestTurnOtherUsersChat`: 404.
  - `TestTurnBusy`: second concurrent POST gets 409 `chat_busy`, and the model is called once.
  - `TestTurnHangup`: client cancels; turn stored `stopped`.
  - `TestTurnNoDeadline`: with `RequestTimeoutSeconds` 1, a fake taking 2 s still finishes.
  - `TestTranscribeOK`, `TestTranscribeTooLarge`, `TestTranscribeTooLong`, `TestTranscribeEmpty`, `TestTranscribeOff`, `TestTranscribeRateLimited`: as the interface states. `TestTranscribeVocabulary`: the stub gets in-progress titles in `prompt`, at most 30.
  - `TestDeleteChats`: removes the caller's only.
  - `TestChatStatus`: `assistant` false with no `Model`; `voice` false with no transcription config.
  - `TestAgentTokenRefused`: a scrobble or MCP token gets 401 on all chat routes.
  - `TestExportHasChats`: in JSON, absent from CSV.
  - `TestChatRoutesInSpec`: `api_parity_test.go` stays green.
- [ ] **Step 2: Run:** `AARU_REQUIRE_DB=1 go test ./internal/httpapi/ -run 'Turn|Transcribe|DeleteChats|ExportHasChats|AgentTokenRefused'`. Expected: FAIL.
- [ ] **Step 3: Spec and generation.** Document all five routes with the schemas above, and the turn route's `text/event-stream` as `{type: string, format: binary}`. Follow how `createCSVImport` is documented yet served raw, including how the strict server is told to skip it. Run `make generate`, then from the repo root `./scripts/generate-api-client.sh`, and `cd aaru-client && npm run api:generate`. Commit generated output with the task, since CI fails on stale clients.
- [ ] **Step 4: Handlers.** In `registerRawRoutes`: `e.POST("/v1/chats/:id/turns", s.chatTurn)` and `e.POST("/v1/chats/transcribe", s.chatTranscribe)`. Add both to `noDeadline`; the transcribe route to `ownBodyLimits` at `8 << 20`. Session auth only, through `currentUser`. Write headers only after `ChatService.Turn` passes its pre-checks, so 404 and 409 stay JSON. Flush after each frame. Heartbeat comment line every 15 s, so Traefik and Cloudflare keep the connection. Wire `ChatService` and `ChatDeps` in `server.go`, as `AgentTools()` does, with `Tools.Quota`. Telemetry: one `assistant_turn` server event, count only, no text, and add it to `docs/privacy.md`'s event list.
- [ ] **Step 5: Run:** `AARU_REQUIRE_DB=1 make test`. Expected: PASS. Then `golangci-lint run ./...`. Expected: clean.
- [ ] **Step 6: By hand:** `docker compose up -d`, then `go run ./cmd/aaru` with `ANTHROPIC_BASE_URL` at a stub server and `curl -N` a turn. Expected: chunks arrive one by one, not all at the end.
- [ ] **Step 7: Commit** `feat(server): chat and transcription on /v1 (ASK-009)`.
- [ ] **Step 8: Open the PR** with `mattpocock-skills:pr` when the owner asks. Record that infra (the `allow-whisper` entry and values) and the promote come next, and that the API promote also carries PR #223's fixes.
