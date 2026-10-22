# Boards + Ask Aaru — design and build plan

## Context

Aaru has a private library, friends (SOC-*), groups with `@aaru` replies (GRP-001…012), and an MCP tool layer. Missing:
1. A place where friends **post** (reviews or free text), **upvote** and **comment**, and can summon `@aaru` in a thread, like on X.
2. A one-to-one **chat with Aaru**, Claude-style, about the user's library, what's airing, titles, music and sport. It refuses anything else ("how is the stock market").

The owner wants both to look good on web and on iPhone/Mac. P2 gate is not met; Aaru is built out regardless (global CLAUDE.md, 2026-10-20). Record every pulled-forward item as a dated owner decision in `BACKLOG.md`.

**Base branch:** `origin/main`, not the stale `feat/browser-extension` checkout. Groups, `ModelProviding` and `AgentReplyWorker` exist only on main. Work in your own worktree (memory: parallel sessions).

## Owner decisions (2026-10-22, from this brainstorm)

| Topic | Decision |
|---|---|
| Board reach | **Friends only.** The author's current friends see the post. Strangers see nothing. No public page, no global feed. |
| Post shape | A post may attach **one title** (review: rating + text + optional spoiler stamp), or be free text. |
| Upvote | **One upvote** per user per post. Count shown, plus who upvoted. Sort: Recent (default) or Top this week. |
| Comments | Everyone who can see the post sees every comment and handle on it. Blocks hide both ways (X-011: 404, never 403). |
| Board placement | The Groups tab becomes **Social**, with a `Board | Groups` switch; Board is the default. Tab count stays 7. |
| Chat writes | **Like a tap:** one-item changes apply at once and are journaled and undoable; anything bigger is a `PlanCard` approved in Aaru (same rule as MCP, X-009). |
| Web search | **Yes, media topics only** (films, shows, anime, books, music, sport). Off-topic requests are refused before any search. |
| Suggestions | **Owner exception: personal suggestions in chat only, when asked.** Still no "because you watched" rows anywhere else. |
| Chat entry | An **Ask Aaru page** (history list + thread), opened by a separate **sparkle "Ask" button** beside the medallion (web header in `components/shell/AppShell.tsx` on main, iOS toolbar). The medallion stays Profile and stats. Title pages get "Ask Aaru about this". |
| Chat v1 | History + streaming, voice input (cluster Whisper), image upload, Share to Board. |
| Review of a title not in your library | Allowed. Posting a review with a rating **adds the title as finished (Watched/Read) with that rating**. That is one journaled, undoable action, previewed in the composer ("Adds Severance to Watched, ★4½"). For a title already in the library, the rating updates and the status is untouched. |
| LLM budget | **The shared `haiku-trial` workspace ($20 cap)**, the same key and budget as the other four apps. Aaru has no fallback model. On out-of-credit (`ModelProviderError.outOfCredit`), chat shows "Aaru is resting — try again later" and Board `@aaru` posts the resting note. Per-user caps are kept tight (below). |

**Calls I made (check these):**
- If the client disconnects, the turn keeps running on the server and is saved. Reopening the chat shows it (the client polls the turn's state while it is `streaming`), and Stop cancels it (an in-process registry; there is one API replica).
- `share_library_with_friends = false` does **not** hide posts or their ratings. A post is a deliberate share; the switch covers the library only.
- Chat writes are journaled with a new `source = aaru_chat` on `actions`/`agent_plans` (no agent token). Chat plans show inline **and** in the Approvals inbox.
- The scope gate is a classifier call, fail-closed; images are kept 30 days; the caps numbers; SSE; no realtime on the Board; one level of comment nesting.

## Domain language (add to CLAUDE.md)

- **Board**: the friends-only stream of posts. Not a table, it is a query.
- **Post**: one Board entry by a user. Optional `titleId`, rating and spoiler stamp.
- **Comment**: a reply on a post. Optional `replyTo`, one level of nesting. It can be by Aaru.
- **Upvote**: one per user per post.
- **Chat** / **Chat turn**: a one-to-one thread with Aaru, and one user or Aaru entry in it. **Never "Conversation" or "Message"**: those are the E2E DM terms.

## Part 1 — Boards (BRD-*)

**Server** (`aaru-server`, order: tables → DTO/openapi → service → handlers)
- Migration `CreateBoards`:
  - `board_posts`: id, author_id, title_id?, rating?, body ≤ 4000, spoiler_season?, spoiler_episode?, created/edited/deleted_at.
  - `board_comments`: id, post_id, author_kind user|agent, author_id?, reply_to?, body, components jsonb, mentions uuid[], mentions_agent, timestamps.
  - `board_upvotes`: post_id, user_id, PK both.
  - Extend `agent_replies` with a nullable `board_comment_id`, or add a sibling queue: builder's call. Keep one worker.
- `BoardService` in `Sources/App/Social/`:
  - Visibility is enforced in the data layer, with the same friend and block checks `SocialService` uses (X-011).
  - Feed: friends' posts + own posts, keyset-paged. `sort=recent|top` (top = upvotes in the last 7 days).
  - Edit and delete your own post. The post author can delete any comment on their post. Reports reuse `social_reports`.
- Spoiler veil: reuse the title-channel spoiler stamp logic in `GroupService+Kinds.swift:63-96`. A friend behind the stamp sees the veil.
- Rating on a review:
  - The composer reads the user's library rating. Posting writes through `LibraryService` as one journaled action: a title not in the library is added as `finished` with the rating (`status_by_hand`); a title already there gets only its rating updated.
  - The post stores a snapshot for display. Undoing the action does not delete the post.
- `@aaru` in a post or comment:
  - Reuse the `GroupService+Agent.swift` cap pattern; caps are **shared** with group mentions (30 per user per day).
  - Reuse `AgentReplyWorker` and `AgentReplyService` with a Board context builder: the post, its title and the last 30 comments.
  - Same read-only tools as `GroupAgentTools.swift`. The reply is posted as an agent comment. Never a new post.
- `@handle` mentions of friends and comments on your post push via the `GroupService+Push.swift` pattern. Upvotes don't push. New notification settings: `board_comments`, `board_mentions`.
- Title page: add `GET /v1/titles/{id}/posts`, friends' posts about this title (a slice of SOC-004).
- Endpoints:
  - `/v1/board`, `/v1/board/posts`, `/v1/board/posts/{id}`
  - `…/{id}/upvote` (PUT/DELETE), `…/{id}/comments`, `…/{id}/comments/{cid}`
  - `/v1/titles/{id}/posts`
- No realtime in v1: pull to refresh and poll while visible (`useVisiblePoll`). Agent "thinking" shows from `agent_replies` state on read.

**Web** (`aaru-client`)
- Rename the Groups nav entry to **Social** (`components/shell/AppShell.tsx` on main). Route `app_.social.tsx` holds the `Board | Groups` segmented control (`ui/segmented-control`); existing `/app/groups/*` routes stay as they are.
- `components/board/`: `PostCard`, `PostComposer`, `CommentThread`, `UpvoteButton`, `TopThisWeek`.
  - Reuse `groups/Composer.tsx` mention suggestions (Aaru first), `groups/AgentParts.tsx` (`AaruAvatar`, `AssistantTag`, `AgentCards`, `ThinkingRow`), `groups/Spoilers.tsx`, `groups/TitlePicker.tsx`, `ui/*`, and `lib/motion.ts` (upvote `pop`).
- Desktop: feed plus a "Top this week" rail. Phone: single column with a floating ✎ button.
- Title page `app_.title.$id.tsx`: a "From friends" section.

**iOS** (`aaru-ios`)
- `AppTab.groups` becomes **Social** (`RootView.swift:175-201`): a segmented `Board | Groups` view over the existing `GroupsScreen`.
- `Board/`: `BoardScreen`, `PostRow`, `PostComposerSheet`, `CommentThreadView`, `BoardModel` (`@Observable`).
  - Reuse `Groups/AgentViews.swift`, `Groups/Composer.swift` mention logic, `Kinds/SpoilerChoice.swift` and `TitlePickerSheet`.
- Title detail: a "From friends" section.

## Part 2 — Ask Aaru chat (ASK-*)

**Engine** (extend what exists; no second backend)
- `ModelProviding` / `AnthropicMessagesProvider.swift`, adding:
  - **Streaming**: SSE from `/v1/messages`, yielding text deltas, tool_use blocks and stop.
  - **Server tool blocks**: `server_tool_use` and `web_search_tool_result`; handle `pause_turn`.
  - **Image blocks**: base64.
  - **Citations** on text blocks.
  - Keep the trial rules: no `temperature`/`top_p`/`top_k`/prefill. Read `platform/infra/docs/llm-haiku-trial.md` first.
  - Provider types stay vendor-neutral outside the adapter.
- Model: `claude-haiku-5-5` (trial). Web search tool: `web_search_20250305` (the dynamic `_20260209` variant is listed for Opus/Sonnet only). `max_uses` 3 per turn. Requires web search enabled in the Console org settings for the `haiku-trial` workspace.
- **Scope gate (my call)**:
  - Before the agent loop, run a tiny Haiku classification call with structured output: `{in_scope: bool}`. Scope covers films, shows, anime, books, music, sport events, the user's library and stats, and Aaru itself.
  - Out of scope → a canned one-line reply. No main call, no search spend.
  - The system prompt repeats the scope as a second layer.
  - Fail-open or fail-closed on classifier error: **fail-closed** (reply "try again").
- `ChatService` in `Sources/App/Agent/`, with these tools:
  - Reuse the read tools in `GroupAgentTools.swift`: `search_titles`, `title_details`, `list_airs`, `read_my_library`, `show_titles`.
  - Add `read_my_stats`, wrapping `StatsService`, for profile insights.
  - Add a write tool with the same semantics as MCP `apply_library_patch` (`AgentTools.swift`, `PlanService`).
  - Add web search.
  - Spoiler guard from the user's own progress, as in GRP-011.
- Components the chat may emit come from the `VIEWS.md` catalog only: `TitleCard`, `CalendarRow`, `PlanCard`, `UndoRibbon`, `Shelf` (>10 titles). Text is markdown, rendered with `lib/markdown.ts` / `Prose.tsx` on web and `AttributedString(markdown:)` on iOS.
- Tables, in migration `CreateChats`:
  - `chats`: id, user_id, title (auto from the first turn), created/updated, deleted_at.
  - `chat_turns`: id, chat_id, role user|agent, body, components jsonb, citations jsonb, image_ref?, usage, state streaming|done|failed|stopped.
- Endpoints:
  - `GET/POST /v1/chats`, `GET/PATCH/DELETE /v1/chats/{id}`.
  - `POST /v1/chats/{id}/turns`, which **streams `text/event-stream`**: deltas, components, citations, done.
  - `POST /v1/chats/{id}/turns/{tid}/stop`.
  - `POST /v1/chats/transcribe` (audio → text).
  - The Worker forwards the stream with the cookie session; iOS reads it through the generated client's `HTTPBody` async sequence.
- **Voice**: client records m4a (iOS) or webm (web) → `/v1/chats/transcribe` → server → `http://whisper.horus.svc.cluster.local:8000/v1` (name the provider `OpenAICompatibleTranscriptionProvider`, as in Norviq). The infra repo needs aaru added to `allow-whisper` in `cluster/network-policies/horus.yaml`. Read `platform/infra/docs/transcription.md` first.
- **Images (my call)**: ≤ 5 MB, jpeg/png/webp. Sent to the model on that turn only. Kept in Postgres `bytea` for 30 days so history shows a thumbnail; later turns see the model's own earlier description, not the image. Add to `docs/privacy.md` (Anthropic as processor, image retention).
- **Metering and caps (my call)**:
  - Add a `cost_cents` column to `agent_usage`, plus `web_searches`.
  - Caps: 30 chat turns and 10 web searches per user per UTC day. Over the cap, Aaru says it is resting.
  - Spend comes from the **shared** `haiku-trial` workspace ($20, shared with Khepri, Loci, LuminaVault and Norviq). Watch Console spend after launch.
  - `outOfCredit` is a terminal "resting" state, not a retry.
- **Share to Board**: a client tap that opens `PostComposer` prefilled with the answer text (trimmed) and the first title card. The user edits it before posting. No agent write path.
- **Recommendations exception**: allowed only inside a chat turn the user asked for. Record it in BACKLOG decisions and the "Explicitly not doing" note.

**Web**
- Route `app_.ask.tsx` and `app_.ask.$chatId.tsx`.
- `components/ask/`: `ChatSidebar` (grouped Today / Yesterday / Earlier), `ChatThread`, `ChatComposer` (🎤 hold or click, 📎 image, send/stop), `TurnView` (markdown, catalog components, sources footnotes, actions: Share to Board, Retry, Copy), `EmptyState` (medallion + 3 starter prompts).
- Sparkle "Ask" button beside the medallion in `components/shell/AppShell.tsx`. "Ask Aaru about this" on the title page opens a new chat with the title attached as context.
- Reuse `AaruAvatar` (`aaru-breathe` while streaming) and `PlanCard.tsx`. Check `npm run size` budgets for the new route.

**iOS**
- `Ask/`: `AskScreen` (`NavigationSplitView`: list + thread on Mac and iPad, push on iPhone), `ChatThreadView`, `ChatComposer` (AVAudioRecorder hold-to-talk, PhotosPicker), `TurnRow`, `ChatModel` (`@Observable`, streaming).
- Sparkle "Ask" toolbar button beside the medallion on the main screens. "Ask Aaru about this" on `TitleDetailView`.
- Reuse `AgentViews.swift` and `Approvals/PlanCardView.swift`.

## After approval

Copy this design to `docs/superpowers/specs/2026-10-22-boards-and-ask-aaru-design.md` in a worktree off `origin/main`. Then break step 1 into a task plan (superpowers:writing-plans) and build one step at a time.

## Build order (one PR per step)

1. BRD-001 server: tables, service, endpoints, tests.
2. BRD-002 web Board + Social tab. BRD-003 iOS Board + Social tab.
3. BRD-004 `@aaru` on Boards (worker reuse) + push.
4. ASK-001 engine: streaming provider, scope gate, metering columns, chat tables and endpoints.
5. ASK-002 web chat. ASK-003 iOS chat.
6. ASK-004 web search + citations. ASK-005 writes via tap/plan.
7. ASK-006 voice (infra network-policy PR first). ASK-007 images. ASK-008 Share to Board.

## Docs to update with the code

- `CLAUDE.md`: domain terms; Stack row for chat, web search and voice.
- `ARCHITECTURE.md`: Board and chat boundaries.
- `DESIGN.md` and `VIEWS.md`: Social tab, Board and Ask Aaru surfaces; new app-chrome components (`PostCard`, `CommentThread`, `ChatThread`), noted as never agent-emitted.
- `BACKLOG.md`: BRD-*, ASK-* rows, and the owner decisions above.
- `docs/privacy.md`.

## Non-goals and anti-goals

- No public posts, profile pages, discoverable Boards or global trending.
- No reposts or quote-posts. No follower model.
- No agent-started posts. Aaru only answers a mention or a chat turn.
- No chat answers about stocks, politics, coding, general news, etc.
- No personalised rows outside chat.
- No paid speech API, no transcode step.
- No sports tracking in the library: sport exists only as chat and web search answers.

## Verification

- Server, with stub HTTP servers (never real keys):
  - `swift test` covering Board visibility (friend, ex-friend, blocked, stranger → 404), upvote idempotency, spoiler veil, and `@aaru` caps.
  - Chat: SSE event sequence, scope gate refusing "stock market today" without a main call, `pause_turn` resume, one-item write applied vs. bulk → plan, usage and cost rows.
- `cd aaru-server && docker compose up -d && swift run`. Curl the SSE endpoint against a stub Anthropic server.
- Web: `npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size`, then `npm run dev`. Click through Social → Board (post, upvote, comment, `@aaru`) and Ask Aaru (stream, stop, image, voice, share) at desktop and 390 px widths.
- Apple: `xcodebuild … CODE_SIGNING_ALLOWED=NO`. Verify on TestFlight on a device (memory: verify on TestFlight, not locally).
- Live: after the manual promote (memory: manual promote), run one real chat turn with web search. Check `agent_usage.cost_cents` and the Console workspace spend.
