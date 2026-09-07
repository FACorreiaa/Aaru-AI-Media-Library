# Aaru — agentic surfaces (phase 1.5)

Written 2026-09-07. This document is the design source for the phase-1.5 agent work.
`CLAUDE.md` and `ARCHITECTURE.md` remain the build contract; where this design needed a
scope change, it names the file that changed and the change was made in the same pass.

Scope: three additions — **Capture**, **outbound surfaces** (App Intents and MCP) with
**remote approval**, and **model plumbing** (provider, bring-your-own-key, metering).

Not in scope: two-way sync, scrobbling, a public API, recommendations, a second backend,
any new UI component, any change to the M1–M9 launch gate.

---

## 0. State when this was written

Verified against the repo on 2026-09-07:

| Piece | State |
| --- | --- |
| `aaru-core` | 15 files, ~755 lines. Domain models, `TitleMatching`, validation. Real |
| `aaru-server` | Hummingbird skeleton. `openapi.yaml` has one path, `getHello` |
| Agent layer | Prose only. Zero hits for `agent|llm|prompt|Anthropic|OpenAI` in Swift |
| `aaru-ios`, `aaru-landing`, `aaru-site` | Empty directories |

Strangers who have used Aaru: **0**. Everything below is phase 1.5 — after the native
client, on components that already work by direct touch. Nothing here is startable before
the launch gate in `MARKETING.md` §1 exists.

---

## 1. Why — the thesis

Aaru's docs already describe an agent that lives *inside* Aaru: a composer, a plan
preview, four tools, nine components, a journal, an undo ribbon. That is table stakes on a
two-year horizon. Every incumbent will bolt an assistant onto a form-based web app, and the
result will be a support bot over a public API with no journal and no undo.

What Aaru can do that they structurally cannot:

> An **outside** agent proposes a change to your library, and the change waits for you.
> Claude says "mark season three watched". Aaru holds it as a `PlanCard`. You approve it on
> your phone. It lands in `actions` with the calling token's name on it, and it is undoable.

This is not a new feature. It is a consequence of two rules already fixed:

- **X-007** — every mutating library path writes a journal row with its inverse, in the
  same transaction. Applies to taps as well as agent calls.
- **AG-003** — every multi-item mutation is a dry run returning a `PlanCard`, then an apply
  against that plan id. A plan whose library changed is rejected, not re-planned.

An incumbent adding third-party agent write access has to expose their existing API, which
has no plan step and no inverse. They ship "the AI changed 40 rows and we cannot tell you
which". Aaru ships a plan card and a ribbon. The gap is the data model, and the data model
is the thing they cannot change quickly (`MARKETING.md` §3.2).

**Marketing consequence:** the demo is a phone buzzing. Ask Claude on a laptop to catch up a
show; the phone shows a plan; approve; the shelf changes. Never demo a chat log.

---

## 2. Capture as an import source

**The problem it solves.** Recommendations arrive as mess: a text thread, a screenshot of
someone's list, a photo of a shelf, a paragraph in a newsletter, a URL. Today every tracker
makes the user retype that mess into a search field one row at a time.

**The design.** Capture is not a new subsystem. It is a new value of `ImportJob.source`, so
it inherits the entire pipeline in `ARCHITECTURE.md` §Import pipeline:

```text
POST /v1/imports/capture     # multipart or JSON: text | image | url
```

Returns an import job id, exactly like `POST /v1/imports/csv`. Then:

| Pipeline step | What capture does |
| --- | --- |
| 1. Parse source into rows | Model extracts `[MediaRef]` from text, image, or fetched page |
| 2. Read `match_aliases` | Unchanged |
| 3. Match by external ID, then normalized title + year + type | `TitleMatching`, unchanged |
| 4. Hydrate unknown titles | Unchanged |
| 5. Upsert library items | Unchanged, behind a plan |
| 6. Record unmatched | Unchanged — `MatchTable`, three buckets |
| 7. Promote confirmed corrections | Unchanged — feeds the match ledger |

Consequences worth stating:

- **Renders `JobLedger` → `MatchTable` → `PlanCard`. No new component.** If capture needed a
  tenth component, the design would be wrong.
- **Corrections feed `match_aliases`.** Capture makes moat 3 stronger rather than sitting
  beside it. A screenshot of a friend's list is exactly the messy input the ledger wants.
- **`plan_import` is extended, not duplicated.** No `plan_capture` tool. One fewer typed
  surface to validate.
- **Out-of-band in the merge order.** The fixed order — Trakt, IMDb CSV, Letterboxd CSV,
  Goodreads CSV, CAT — describes reconciling one account's connected sources. Capture is a
  user-triggered one-shot and does not join it. Stated as an exception in `CLAUDE.md`.
- **Extraction is a model call**, which is why capture is the first thing that needs §6.

**What capture must not do.** It never writes without a `PlanCard`, even for one row, because
the extraction is a guess and the user has to see the guess. It never skips the `MatchTable`.
It does not accept a site to scrape — a URL is fetched once and read, and no on-ramp becomes
a scraper (`CLAUDE.md`: no Pogdesign, IMDb page, or unofficial-API scraping).

**Pricing.** Plus, with the first run free. Per `MARKETING.md` §5.1 the rule is charge for
work Aaru does; extraction is a metered model call. The free first run exists because capture
is the onboarding demo and the 30-second video.

---

## 3. The tool layer, revisited

`ARCHITECTURE.md` listed four tools. Mapping the surfaces against them exposed a gap:

| Tool | Wraps | Feeds |
| --- | --- | --- |
| `search_titles` | `GET /v1/search`, `GET /v1/titles/{id}` | `TitleCard` |
| `plan_import` | dry run over `POST /v1/imports/*` | `PlanCard`, `MatchTable` |
| `apply_library_patch` | `PATCH /v1/library/items/{id}`, episode and season writes | `SeasonMap`, `TitleCard` |
| `list_airs` | library items joined to `show_episodes` | `CalendarMonth` |
| **`read_library`** | **`GET /v1/library/items`, `GET /v1/shelves/{id}/items`** | **`Shelf`, `TonightStrip`** |

**`search_titles` reads the catalog, not the library.** With only the original four tools,
nothing could populate a `Shelf` or a `TonightStrip` — the two surfaces `DESIGN.md` §5 and §6
make central. `read_library` is required by the *inbound* agent regardless of anything
outbound, so it belongs to `AG-001`, not to the new milestone.

The tool-layer rules do not change and are worth restating because everything in §4 and §5
rides on them:

- Removing the tool layer entirely must leave every feature reachable through the plain API.
  The agent is a caller, never a privileged path.
- A tool cannot accept what a route rejects. Argument validation is the route's own code.
- Every tool write goes through the same data layer as a tap, so it lands in `actions` and is
  undoable. There is no agent-only write path.

---

## 4. Outbound transports

Two new transports, both **skins over the tool layer in §3**. Neither adds a capability, a
route behind the tools, or a write path.

### 4.1 App Intents and Shortcuts

The cheapest outbound surface, and the one that ships first. Each tool becomes an App Intent
in `aaru-ios`, which gets Siri, Shortcuts, Spotlight, and the share sheet for free.
`TitleCard` and `TonightStrip` serve as intent snippet views, so a Shortcut result looks like
Aaru rather than like a string.

Zero new server work. This is already launch-gate item 19 in `MARKETING.md`; this design just
names it as an agent surface instead of a convenience feature, and points it at the same
tools the composer uses.

### 4.2 MCP endpoint

```text
POST /v1/mcp                 # streamable HTTP
```

Lives in `aaru-server/Sources/AppMCP`. **In the existing server** — the "no Vapor, no Node, no
second backend" rule is not relaxed, and MCP is a transport, not a service.

It exposes exactly the five tools in §3 and nothing else. The `AG-001` test applies unchanged:
delete `AppMCP` and every feature is still reachable through `/v1`.

**This is not a public API.** It is a per-user, token-scoped endpoint the user turns on for
their own agents. `MARKETING.md` §3.4 said "Aaru's API is for its own clients until 1,000
strangers"; that line was written about a documented third-party platform with clients,
quotas, and support obligations, and it has been qualified rather than dropped. The
distinction that matters:

| | Public API (still refused) | Agent access (this design) |
| --- | --- | --- |
| Who holds credentials | Third-party developers | One user, for their own agents |
| Discovery | Documented, versioned, promoted | A token you generate in Settings |
| Support obligation | Deprecation policy, third-party clients | Revoke the token |
| Write path | Would be direct | Plan, then in-app approval |

---

## 5. Remote approval

The load-bearing piece. Without it, outbound writes are the trust sink in `MARKETING.md`
risk #4 and the whole private-first story dies on one unexpected bulk write.

An external caller holding `library:write` **cannot write more than one item directly**. It
gets a plan id:

```text
1. External agent calls a plan_* tool
   -> server returns { planId, humanSummary, counts, unmatched }
2. Server pushes a notification
   -> Aaru renders the plan as a PlanCard, labelled with the calling token's name
3. User approves or denies in Aaru. Nowhere else.
   POST /v1/plans/{id}/approve
   POST /v1/plans/{id}/deny
4. Apply runs through the same data layer as a tap
   -> one actions row, actor = external_agent, agentTokenId set, inverse recorded
5. UndoRibbon shows it. One tap reverts.
```

Rules:

- **The approval surface is Aaru.** There is no route by which an external caller approves its
  own plan, and no token scope grants it.
- **Plans expire, and a stale plan is rejected.** AG-003's rule, unchanged — a plan whose
  underlying library changed since the dry run is rejected rather than silently re-planned.
- **Single-item writes within scope may skip the plan**, because that is exactly what a user
  tap does. The symmetry is the rule: an external caller gets a tap's power, not more.
- **The `PlanCard` names the caller.** "Claude · laptop wants to mark 18 episodes watched" is
  the difference between a feature and a security incident.
- **Denied plans are journaled too**, as a denial, so the ledger answers "what did it try".

The notification leg depends on the push work in launch-gate item 18. Until push exists,
pending plans appear in The Field as a pinned artifact — which is the offline-correct
behaviour anyway, and keeps `OUT-004` from blocking on APNs.

---

## 6. Model provider, BYOK, metering

Nothing in the repo says which model runs the agent or who pays for it.
`MARKETING.md` §5.2 already promises bring-your-own-key and §5.4 already calls model calls
"the one variable cost". This section makes that real.

**Provider.** A `ModelProviding` protocol in `aaru-server/Sources/App/`, following the
narrow-protocol style already used by `CatalogSearching` and `UserLibraryImporting`. Anthropic
adapter is the default; keys stay in environment config.

```swift
protocol ModelProviding: Sendable {
    func complete(_ request: ModelRequest) async throws -> ModelResponse
}
```

**Bring your own key.** A per-user encrypted key. When set, the fair-use cap does not apply.
This is simultaneously the answer to risk #3 (agent as a cost sink), the answer to the
privacy pitch ("your key, your model"), and the reason a power user never hits a wall.

**Metering.** Table `agent_usage`: `userId`, `day`, `inputTokens`, `outputTokens`,
`costCents`. Day granularity, matching the `match_aliases` precedent — fine enough to bill and
too coarse to be a behavioural log. Metered from the first call, per risk #3, not added later.

**Settings.** `GET /v1/settings` and `PATCH /v1/settings` — the first settings routes in the
API. The autonomy dial (`ask me` / `fill empty only` / `overwrite if newer`) moves here,
because AG-003 requires it be server-stored config the model cannot choose.

---

## 7. Security model

**Tokens.** Table `agent_tokens`: `id`, `userId`, `name`, `hashedToken`, `scopes`,
`lastUsedAt`, `expiresAt`, `revokedAt`. Only the hash is stored. The secret is shown once, at
creation. Deleting the account deletes the tokens.

**Scopes**, narrowest useful set, defaulting to read-only:

| Scope | Grants |
| --- | --- |
| `library:read` | `read_library`, `search_titles`, `list_airs` |
| `library:write` | `apply_library_patch` for a single item; plan proposal for anything larger |
| `imports:write` | `plan_import`, including capture. Never an apply |

**What an external caller can never do**, by construction rather than by policy:

- Approve its own plan. There is no route.
- Write more than one library item without an in-app approval.
- Reach Fluent or a provider directly, or receive vendor JSON.
- Read another user's data. Tokens are per-user and every library route requires a user.
- Read the match ledger's origin. `match_aliases` holds no user identity by design.
- Escalate its own scope, or mint a token.
- Perform a write whose inverse cannot be stated. X-007 refuses it.

**Provenance.** `actions.actor` gains `external_agent`, and `actions` gains a nullable
`agentTokenId`. The undo ribbon can then say *which* agent did it, and revoking a token leaves
its history readable. This is the concrete requirement behind X-009.

**Rate limiting.** Agent tokens go through the central rate limiter, per X-002. A token is not
a bypass.

---

## 8. What this deliberately does not add

| Not added | Why |
| --- | --- |
| A tenth UI component | Everything renders on the existing nine. If it needed a new one, the reuse claim was false |
| A public API | §4.2 — per-user token-scoped access is a different thing, and the distinction is written into `CLAUDE.md` |
| Two-way sync or scrobbling | Still out of scope. Outbound *read* and *proposed* writes are not sync; nothing in Aaru follows a remote change |
| A `plan_capture` tool | `plan_import` extends. One fewer typed surface |
| A second backend | MCP is a transport inside `aaru-server` |
| A recommendations engine | `TonightStrip` stays derived from the user's own library only, per AG-005 |
| A new import merge-order slot | Capture is out-of-band and user-triggered |
| Changes to the M1–M9 launch gate | This is phase 1.5. The launch does not wait for it |

## 9. Open questions

- **Export.** `MARKETING.md` launch-gate item 14 requires free CSV/JSON export, and no backlog
  ticket exists for it — there is no `EXP` prefix in use. `OUT-005` (`GET /v1/context`) should
  merge into that export once it has a ticket rather than becoming a second export path.
  Recommendation: file the export ticket before building `OUT-005`.
- **Capture of images.** Vision extraction is the most expensive call in the product and the
  most likely to be wrong. Recommendation: text and URL first, image behind the same route but
  shipped second, so the `MatchTable` triage flow is proven on cheap input.
- **Pending-plan expiry for remote approval.** A plan proposed from a laptop and approved two
  days later is almost certainly stale. Recommendation: same expiry as any plan, and let the
  stale-plan rejection in AG-003 do the work rather than inventing a second rule.
