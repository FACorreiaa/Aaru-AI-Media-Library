# Aaru — go-to-market, moat, and monetisation

Written 2026-08-29, revised 2026-09-02 to add the moat thesis and the money model. This
document is demand-side only. It does not change product scope; `CLAUDE.md` and
`ARCHITECTURE.md` remain the build contract. Where a moat item needs a scope change, it says
so and names the file that has to change first.

---

## 0. Reality snapshot (read this before believing any date below)

Verified against the repo on 2026-09-02. Unchanged since 2026-08-29:

| Piece | State |
| --- | --- |
| `aaru-core` | Domain models + validation + tests. ~1,380 LOC total across core and server. Real. |
| `aaru-server` | Hummingbird skeleton. `openapi.yaml` is 18 lines. The only route is `getHello`. |
| Persistence | No Fluent models, no migrations. |
| Auth, search, library, lists, progress, imports, agent | Not started. |
| `aaru-ios`, `aaru-landing`, `aaru-site` | Empty directories. |

**Strangers who have used Aaru: 0.** Every number in this plan is a target, not a forecast.

There is no marketing problem yet. There is a "nothing to market" problem. This plan is
written so that when the product exists, the launch is not improvised — and so the build
order is chosen for what actually sells and what actually compounds.

---

## 1. What "feature ready" means

Feature ready is not the MVP list in `CLAUDE.md`. It is one sentence:

> A stranger can sign up, pull in the history they already have somewhere else, find any
> movie, show, or book, track a series to the episode, keep a list, export everything, and
> delete their account — without contacting me.

Everything that does not serve that sentence is post-launch.

### The launch gate (all of it, or do not launch)

**Server — the whole thing is missing, not "nearly done".**

1. `openapi.yaml` written for real. Routes are generated from it, so the spec *is* the schedule.
2. Fluent models + migrations: users, titles, external ids, library items, episodes/progress, lists, list items, saved queries, actions, import jobs.
3. Auth: Sign in with Apple + email, sessions/JWT, auth middleware, password reset, email verification.
4. TMDB adapter (search, movie/show detail, seasons, episodes) and Open Library adapter, with caching, rate-limit handling, and keys in env.
5. `/v1/search` across video + books, deduped by external ID, returning Aaru DTOs — never raw provider JSON.
6. Library CRUD: status, `isOwned`, rating, notes; filter, sort, paginate.
7. TV progress: episode ticks, mark-season-watched, next-up.
8. Lists: create, reorder, add/remove. Shelves: saved queries.
9. Job queue + Trakt OAuth import, IMDb / Letterboxd / Goodreads CSV, CAT list + ICS, in the merge order already fixed in `CLAUDE.md`. Job status endpoint. **Unmatched-rows report** — an import that silently drops 8% of a 2,000-film history is the single fastest way to lose a Letterboxd user.
10. **Action journal + undo.** Not a nice-to-have: it is the precondition for the agent (§3, moat 2) and the thing that makes bulk imports safe to try.
11. Cross-cutting: error model, pagination convention, rate limiting, structured logging, health check.

**Product surfaces that are not the mobile client and are still missing.**

12. **Mac client.** A separate shipping surface even in one multiplatform target.
13. **Landing page** (`aaru-landing`). No landing page, no launch.
14. **Export — CSV and JSON, free, no account tier.** This is the marketing message, not a feature. See §3, moat 1.
15. **Account deletion + data export self-service.** Required for the App Store and required for the pitch to be honest.
16. **First-run onboarding = the import.** Zero to a populated library in under two minutes, or the pitch dies on contact.
17. **Offline read of your own library.** "Private-first" that shows a spinner on a plane is not private-first, it is just a server.
18. **Episode / release notifications.** The CAT-ICS crowd came for exactly this.
19. **Share sheet + Shortcuts / App Intents + a widget.** Cheap, and it is how Apple-ecosystem word of mouth actually spreads.
20. Legal and store: privacy policy, terms, TMDB attribution (required by their terms), Open Library and Trakt attribution, App Store privacy labels.
21. Ops: deploy target, hosted Postgres, migrations on deploy, backups, secrets, staging.

**Not in the launch gate but in the first paid release (phase 1.5):** the composer, plan
card, and Tonight strip from `DESIGN.md`. They are what the paid tier is made of (§5). The
launch can happen without them; the money cannot.

### Deliberately not in the launch gate

Social graph, recommendations, two-way sync, scrobbling, web client, music/comics/games.
Already out of scope in `CLAUDE.md`. Keep it that way — the plan below sells the absence.

---

## 2. Positioning

**One line:**
> Aaru is a private shelf for everything you watch and read. It imports what you already
> have, it lets you leave, and it does the bookkeeping for you.

**The wedge, stated plainly:**
- Letterboxd is a social network that happens to log films.
- Trakt is plumbing — powerful, and it charges you to see your own statistics.
- Goodreads is an Amazon property nobody defends.
- Nothing credible holds films, shows, *and* books in one place, privately, on Apple hardware,
  with an assistant that can do a whole migration or a whole season in one instruction.

Aaru is the shelf, not the feed.

**Four messaging pillars.** Every asset uses one of these; never all four at once.

1. **One shelf.** Films, shows, books. One search field, one library, one status vocabulary.
2. **Private by default.** No profile, no followers, no activity feed. Nobody sees what you read.
3. **Easy in, easy out.** Import from Trakt, IMDb, Letterboxd, Goodreads, CAT. Export everything, any time, free. Anti-lock-in is the product.
4. **It does the bookkeeping.** Say "mark season three watched" or "bring my Goodreads." See the plan, approve, undo if wrong. Native SwiftUI on iPhone and Mac, fast, offline-capable.

**Do not say:** "the Letterboxd killer", "AI-powered", "social", "portfolio", "watchlist app",
"chat with your library". Say what the agent *does*, never that it exists.
Do not use vendor names as domain terms — that rule from `CLAUDE.md` applies to copy too.

---

## 3. Moat

### 3.0 What a moat means for a one-person Apple app

Aaru will not out-integrate Trakt, out-community Letterboxd, or out-distribute Goodreads.
Those moats took a decade and a company each. "Moat" here means three narrower things:

- **A position the incumbents structurally will not take.** Not "cannot" — will not, because it
  contradicts their brand, their business model, or their org chart.
- **An asset that gets better with every user and is not the user's own data.** Compounding
  without lock-in.
- **A reason to stay that survives a free, one-tap export.** If people stay when leaving is
  trivial, that is retention earned, not held.

Anything that is a feature — cross-media search, a nice season grid, a native Mac app — is
copyable in a quarter and is not on this list. It is table stakes. The list below is ranked
by how hard it is to copy divided by how much it costs to build.

### 3.1 The moat ladder

| # | Moat | Why incumbents will not follow | Compounds? | Phase | Scope change needed |
| --- | --- | --- | --- | --- | --- |
| 1 | **Exit door as brand** — free export, forever, above the fold | Trakt VIP and Letterboxd Pro are lock-in businesses; copying this costs them revenue | No, but it is the trust that every other moat rides on | 1 | None |
| 2 | **The bookkeeping agent** — plan → approve → undo over the whole library | Incumbents are form-based web apps with public APIs; a journaled, undoable agent write path needs the action journal and component catalog Aaru is built on from day one | Yes, per user: reject signal and shelves make it better for *that* user | 1.5 | None (M13) |
| 3 | **The match ledger** — a private crosswalk of every export format to every external ID, trained by human corrections in Import Studio | Nobody owns "IMDb CSV row → Goodreads ISBN → TMDB id → TVDB id". Trakt only cares about video; Goodreads only about books | Yes, across users: every corrected mismatch improves the next stranger's import | 1 (collect) → 1.5 (apply) | None — `match_aliases` rules are in `ARCHITECTURE.md` |
| 4 | **Cross-media as identity** — one status vocabulary for a film, a season, a book | Trakt adding books dilutes Trakt; Letterboxd adding TV has been "coming" for years; Goodreads adding films is not a thing Amazon does | Weakly: the more media types in your shelf, the fewer places can take the whole shelf | 1 | None |
| 5 | **Apple-native surfaces** — App Intents, Shortcuts, widgets, Siri, share sheet, offline | Web-first companies ship thin native shells; a real Mac client is rare in this category | No | 1 | None |
| 6 | **Household** — two to five people, one private shared shelf, "watching together" progress | Letterboxd is a public graph; Trakt has no couples model; neither has a private two-person unit | Yes: the first genuine network effect that stays private-by-default | 2 | `ARCHITECTURE.md` phase 2 already allows it; needs `list_members` |
| 7 | **Agent-reachable shelf** — App Intents and a per-user MCP endpoint, where an outside agent *proposes* and the user approves in Aaru | Their write paths have no plan step and no inverse, so third-party agent writes are unauditable for them and safe for Aaru | Yes, per user: the approval habit is what makes the shelf the trusted copy | 1.5 | Yes — done: `CLAUDE.md`, `ARCHITECTURE.md` §Outbound agent surfaces, M14 |
| 8 | **Hub position** — Aaru writes *out* to Trakt, serves a Stremio catalog, accepts Plex/Jellyfin webhooks | Turns Aaru from a spoke into the centre once the library is real | Yes: each output makes leaving cost more *without* blocking export | post-v1 | Yes — `CLAUDE.md` out-of-scope list (MOAT-001..003 in `BACKLOG.md`) |

Moats 1, 4, and 5 are positioning. Moats 2, 3, 6, and 7 are the durable ones. Moat 8 is
attractive and forbidden until there is a library to put at the centre.

Moat 7 is moat 2 pointed outward, and it costs almost nothing extra: the journal, the plan
step and the undo ribbon are already built for the in-app agent, and App Intents are already
launch-gate item 19. What it buys is the demo nobody else can film — you ask an agent on a
laptop to catch up a show, your phone asks permission, you tap once, and the write is
reversible. The honest cost: one more surface for one person to support, and it is why §3.4
below had to be qualified rather than quietly ignored.

### 3.2 Moat 2 in detail — why the agent is the paid product and not a gimmick

The category's real user pain is not discovery, it is **bookkeeping**: 40 episodes to tick,
a 2,000-row CSV to reconcile, a "did I finish that?" for every half-watched show. Every
incumbent makes the user do this by hand, one row at a time, in a form.

Aaru's difference is architectural, not cosmetic:

- The agent has **no write path a tap does not have**. Every mutation lands in `actions` and is
  undoable. That is what lets it be trusted with bulk work.
- Multi-item mutations go through a **plan card** first: counts, per-op diff, unmatched,
  proposed merges, an autonomy dial. The user sees the change before it happens.
- The agent emits **only catalog components** (`TitleCard`, `SeasonMap`, `PlanCard`, `Shelf`
  …). It looks like Aaru, not like a chat log.

A Trakt or Letterboxd bolt-on assistant would have to be built on top of a public API with no
journal, no plan step, and no undo. It would be a support-bot. The gap is the data model,
and the data model is the one thing they cannot change quickly.

**Marketing consequence:** demo the agent as three sentences and a result, never as a chat.
"Bring my Goodreads." "Mark season three watched." "Shelf of books I own but never started."
Show the plan card. Show the undo ribbon. That is the 30-second video.

### 3.3 Moat 3 in detail — the match ledger

The importers already have to map five foreign formats to four external ID systems. Every
human correction in Import Studio ("this Letterboxd row is *that* TMDB title") is a fact
about the world, not about the user. Kept as an aggregate alias table, it makes every later
import for every user better. This is the only asset in Aaru that compounds across users
while the product stays private-by-default.

Rules (canonical copy lives in `ARCHITECTURE.md`, "Match ledger"; this is the summary):

- The ledger stores `(source, source_key, external_id)` triples and a confidence count.
  Never a user id, never a row from a user's library, never a timestamp finer than a day.
- A correction becomes a ledger entry only after it has been made independently by more than
  one account, or by one account and confirmed by a provider ID match.
- The ledger is exported with the app's open data (see §5, "give away the crosswalk") so the
  moat is the *freshness and coverage*, not secrecy.

Why it is a moat: the free converter tools in §4 collect corrections **before the app
exists**, from exactly the people whose exports are hardest. By launch, Aaru's match rate on
messy Letterboxd and Goodreads files should be better than anything an incumbent bothers to
build, because for them cross-source import is a feature request and for Aaru it is the
front door.

### 3.4 Where Trakt wins, and what not to fight on

| Trakt strength | Aaru response |
| --- | --- |
| Scrobbling from Plex, Kodi, Infuse, Jellyfin, browser extensions | Do not compete in v1. Import Trakt history one-way, then in post-v1 accept webhooks (moat 7). Never build a scrobbler ecosystem. |
| Broad public API and a decade of third-party clients | Do not compete. Aaru ships **no public API** — no docs, no quotas, no third-party clients, no deprecation policy — until well past 1,000 strangers. Per-user token-scoped agent access (moat 7, M14) is a different thing: the credential belongs to one user, for their own agents, and dies when they delete it. Do not let the two blur in copy. |
| Deep video metadata, calendars, comments, community | Take the calendar (Airs this week, from *your* library only). Skip comments and community entirely. |
| VIP: stats, no ads, year in review, larger limits | Never paywall stats or the user's own data. This is the grievance Aaru harvests. |
| Video only | Books. One shelf. |
| Web + apps, form-driven | Native + agent. Plan, approve, undo. |

Trakt is not the enemy; it is the on-ramp. Trakt import is the first source, and "push my
library back to Trakt" (MOAT-003) is the friendliest possible post-v1 move: a user who keeps
Trakt for scrobbling and Aaru for the shelf is a user who never leaves either.

---

## 4. The one asymmetric asset: the exit door

Every incumbent in this category makes leaving hard. Aaru's importers already have to parse
Trakt, IMDb, Letterboxd, Goodreads and CAT. Turning that machinery around costs almost
nothing and buys the entire trust position:

- Export to CSV and JSON, free forever, no paid tier, one tap.
- Say so on the landing page, above the fold.
- Ship the importers as **free standalone web tools** on the landing site before the app is
  ready: "IMDb watchlist CSV → readable list", "Letterboxd CSV → JSON", "Goodreads CSV →
  clean ISBN list". No signup. These rank for high-intent search terms, prove the matching
  engine works, collect emails from exactly the people who later need the app, and — new in
  this revision — **seed the match ledger** (§3.3) with corrections from real, messy exports.

This is the highest-leverage pre-launch work available, and it is buildable against
`AaruCore`'s existing `TitleMatching` before the server exists.

---

## 5. Monetisation

> ⚠️ **Verify before publishing.** Competitor prices below are from memory. The verification
> pass could not run on 2026-08-29 (DeepAPI credits exhausted) or on 2026-09-02 (network call
> blocked by the session's permission policy). Re-check Trakt VIP / VIP EP, Letterboxd Pro /
> Patron, StoryGraph Plus, Simkl VIP, and TV Time current pricing before any of these numbers
> appear in public copy or a comparison table.

### 5.1 The principle

Charge for **work Aaru does**, never for **data the user owns**. This is the exact inverse of
Trakt VIP, and it is what makes the pricing a marketing message instead of a toll.

Free, forever, no cap: the library, every media type, manual add, search, statuses, ratings,
notes, TV progress, shelves, one list, **all stats**, **CSV/JSON export**, account deletion.

Paid: the things that cost real money to run or real time to build — the agent's model
calls, bulk import matching and hydration, push notifications, household seats, Mac + iPhone
sync of preference signal.

### 5.2 Tiers

| Tier | Price (proposed, verify against §5 warning) | Contains |
| --- | --- | --- |
| **Free** | $0 | Everything in "free, forever" above. One connected import source, run once. |
| **Import Pass** | ~$4.99 one-time | All importers, unlimited runs for 30 days, unmatched-row triage. For the Goodreads leaver who will never subscribe. Converts migration intent without a commitment. |
| **Aaru Plus** | ~$3.99/mo, ~$29.99/yr | The agent (composer, plan cards, Tonight strip), capture, agent tokens for outside agents, all importers always, unlimited lists, episode/release notifications, widgets and App Intents, Mac + iPhone. Fair-use cap on agent calls; heavy users can bring their own model key and remove the cap. |
| **Household** | ~$49.99/yr, 2–5 people | Plus for everyone, one private shared shelf, "watching together" progress. Phase 2. Priced under two Plus subscriptions so a couple upgrades instead of sharing a login. |
| **Founding** | ~$79 one-time, first 500 accounts only | Plus forever, Household when it ships, name in the app's credits. Turns early users into invested advocates and funds the first year of hosting. |

Rules:

- Export, stats, and the user's own data are never paywalled. The moment they are, pillar 3 is
  a lie and the positioning collapses.
- Price at or slightly under the film-only incumbents, because Aaru covers more media. If
  Trakt VIP is confirmed at around $60/yr, Plus at $29.99/yr is the anchor: half the price,
  more media, plus an assistant.
- The agent is metered, not unlimited. A budget of roughly $0.50 per Plus user per month at
  Haiku-class pricing keeps gross margin above 80% at $29.99/yr. Re-derive with real usage
  after 100 strangers. Bring-your-own-key exists so a power user can never hit a wall and so
  the privacy pitch has a "your key, your model" answer.
- **Capture is Plus, and the first run is free.** Extraction is a metered model call, so it
  belongs on the paid side by the §5.1 rule — but it is also the onboarding demo and the
  30-second video, so one run costs nothing. Paste a group chat, watch the shelf fill.
- **Agent tokens are Plus, read-only scope included.** Reading your own shelf from another
  agent is cheap for Aaru; the write path is where the plan card and the support load are.
- No free trial before there are 100 users; there is not enough signal to tune one. Import
  Pass is the trial.
- App Store only for billing at launch. Family Sharing on. No web checkout until `aaru-site`
  exists.
- No ads, no data sale, no "anonymised insights" product. Write it in the privacy policy so it
  is a contract, not a promise.

### 5.3 Give away the crosswalk

Publish the match ledger (§3.3) as an open dataset and the converter tools as open source.
This sounds like giving away the moat. It is not: the moat is that Aaru is where the
corrections *arrive*. Publishing it buys the Show HN post, the r/DataHoarder goodwill, and the
"they really are not locking you in" proof that no incumbent can match. Coverage and
freshness stay with the product that has the users.

### 5.4 Unit economics to track from user one

| Line | Assumption to replace with data |
| --- | --- |
| Hosting + Postgres + object storage | Fixed, small. Fits in Founding revenue from ~30 accounts. |
| TMDB / Open Library | Free with attribution. Cache aggressively; never hotlink at scale. |
| Model calls | ~$0.50 / Plus user / month at expected usage. The one variable cost. Meter it. |
| Push notifications | Negligible on APNs. |
| Apple's cut | 15% under Small Business Program. |
| Support | The real cost. One person, five importers, two platforms. Import quality *is* support reduction. |

---

## 6. Who it is for, in priority order

1. **Trakt power users tired of paying to see their own data.** Highest intent, most vocal, already have an export. Reachable in one subreddit. Pitch: free stats, books, the agent.
2. **Letterboxd users who also read.** Have no cross-media home. Emotionally attached to their film log — so the import must be flawless before touching them.
3. **Goodreads leavers.** Large, actively looking, already migrating elsewhere. Books-only entry, films as the surprise. Import Pass exists for them.
4. **Apple-ecosystem quantified-self / privacy people.** Small, loud, buy things, write blog posts, care about native, offline, and bring-your-own-key.
5. **Couples and households who watch together.** Phase 2, but recruit them from segment 1–4 and ask what they would pay before building Household.
6. **CAT / episode-calendar holdouts.** Tiny, but the ICS on-ramp is already in scope and nobody serves them.

Ignore everyone else until 1,000 users.

---

## 7. Channels, ranked by expected return

**Tier 1 — do these.**

1. **Reddit, participating not posting.** r/trakt, r/letterboxd, r/goodreads, r/books, r/television, r/cordcutters, r/apple, r/iosapps, r/shortcuts, r/selfhosted, r/DataHoarder. Answer import questions with the free web converters for a month before mentioning an app.
2. **Show HN.** Angle: "one-way importers, an open cross-source ID crosswalk, and full export for a private media library". Not "I built a tracker" and not "AI media app". The engineering audience rewards the anti-lock-in stance, the open dataset, and the Swift-server choice.
3. **SEO on migration intent.** Target: *Trakt alternative*, *Goodreads alternative*, *export IMDb watchlist*, *import Letterboxd to*, *track books and movies in one app*, *Trakt VIP worth it*. Each free converter tool from §4 is a landing page for one of these.
4. **Apple indie press and newsletters.** MacStories / Club MacStories, Six Colors, The Sweet Setup, TidBITS, 9to5Mac, iMore, App Defaults, Indie App Santa. Pitch the Mac app and the Shortcuts/App Intents story, not the iPhone app; a good Mac client is rarer and more newsworthy.
5. **Product Hunt** on the same day as the App Store release, not before.

**Tier 2 — after 100 users.**

6. **Year in review / shareable recap card.** User-initiated share only, no auto-posting, no profile. Free, not Plus — it is the growth loop.
7. **Household invites.** The only in-product invite Aaru will ever have. One person invites one person to one private shelf. Phase 2.
8. **BookTok and film-diet creators.** Small accounts, free Founding tier, no scripts.
9. **A single owned newsletter.** Monthly, about what shipped. It is the only channel nobody can take away.

**Do not bother:** paid ads (no LTV data), Twitter/X threads (no audience), a Discord (support load for one person), influencer deals, "AI" as a headline anywhere.

---

## 8. Launch sequence, tied to the strangers scoreboard

Phase gates, not calendar dates. The count is the only metric that promotes a phase.

**Phase A — 0 strangers. Now → the server exists.**
No marketing. Build §1. The only outward artifacts: landing page with an email capture and
one honest sentence, plus the free converter tools from §4 with a "this row is wrong" button
that feeds the match ledger. Goal: 200 emails and proof that the matcher survives real
exports.

**Phase B — first 10 strangers. TestFlight.**
Recruit by hand, from the Reddit threads you have been answering, one at a time. Watch each
person import. The import is the product; the first ten will tell you exactly where it
breaks. No launch post. No Product Hunt. No pricing shown yet. Per the standing rule: no
renames, no rebrands, no re-architecture until these ten exist.

**Phase C — 100 strangers. Public launch.**
App Store release, Show HN, Product Hunt, press pitches, all on one day, with the landing
page and the comparison table finished. Founding tier and Import Pass open. Plus opens only
if the agent (phase 1.5) has shipped; otherwise launch free + Founding and add Plus when the
composer lands.

**Phase D — 1,000 strangers.**
Recap card, creator seeding, newsletter, Household. Only now reconsider the web client, the
Trakt push-back job (MOAT-003), and the Stremio catalog (MOAT-001).

---

## 9. Asset checklist for Phase C

- Landing page: one-sentence promise, import logos, export promise above the fold, three-line agent demo, screenshots, price, privacy policy, terms.
- Comparison table vs Trakt, Letterboxd, Goodreads, Simkl, TV Time, StoryGraph — **built only after the pricing verification in §5**. Rows: books, private by default, free export, free stats, undoable bulk edits, native Mac, price.
- 6 App Store screenshots, benefit captions, not feature captions. First screenshot is the import. Second is the plan card.
- 30-second screen recording: paste a Letterboxd export, watch the shelf fill, say "mark season three watched", tap undo.
- Press kit: icon, screenshots, 50/150/300-word descriptions, founder line.
- The three free converter tools, still live and still free, with the open crosswalk dataset linked.

---

## 10. Metrics

| Metric | Definition | Phase C target |
| --- | --- | --- |
| Strangers | People who are not you, who used it | the scoreboard |
| Activation | ≥1 source imported **and** ≥25 library items within 24h | 60% |
| Import completion | Jobs finishing without a fatal error | 95% |
| Match rate | Rows matched to a title on first pass | 90%+ |
| Ledger growth | Distinct corrected aliases per week | rising |
| D7 return | Opened the app 7 days later | 40% |
| W4 retention | Still active at 4 weeks | 25% |
| Free → paid | Import Pass or Plus or Founding | 4% |
| Agent acceptance | Plan cards approved ÷ plan cards shown | 70% |
| Undo rate | Agent writes undone ÷ agent writes | under 5% |
| Export-then-churn | Accounts that export and go inactive within 30 days | watch, do not fight |

Match rate is the leading indicator for all the others. Agent acceptance and undo rate are
the two that decide whether Plus is a product or a demo. Export-then-churn is measured and
never optimised against; the day it is, the exit door is fake.

---

## 11. Risks

1. **The product does not exist.** Largest risk by a wide margin. Nothing above is actionable before §1 is built.
2. **Import quality.** One bungled 2,000-film Letterboxd import produces a public complaint that outweighs a good launch post.
3. **The agent as a cost sink.** Unmetered model calls at $29.99/yr can go negative. Meter from day one, cap fair use, ship bring-your-own-key.
4. **The agent as a trust sink.** One bulk write the user did not expect and cannot undo ends the private-first story. The plan card and journal are not optional.
5. **Outbound access as a support and blast-radius sink.** Every agent token is a credential one person has to reason about, and "some agent changed my library" feels bad no matter how well it is journalled. Mitigations, all in M14: read-only by default, no self-approval, every write named with its token, revoke from the app, central rate limiting. If the first ten strangers do not ask for it, deferring M14 is the honest call — the in-app agent (moat 2) is the paid product either way.
6. **Provider terms.** TMDB attribution is mandatory. Trakt's API terms constrain how their name is used in marketing. Read both before writing the comparison table.
7. **Indifference.** "Another tracker" is the default reaction. The counter is one specific promise — the exit door — not a longer feature list.
8. **No viral loop.** Private by default means growth is earned, not compounding. Household is the only loop; accept slower growth; do not solve it by adding a feed.
9. **Name collision.** "Aaru" competes in search with the Egyptian mythology term and at least one AI company. Monitoring item only — the standing rule is no renames before 10 strangers.
10. **Solo support load.** One person, five importers, two platforms, one agent. Ship fewer sources well.
11. **Copy risk on the wrong things.** Incumbents can copy cross-media search and a season grid in a quarter. They cannot cheaply copy a journaled agent or a private household model. Spend build time accordingly.

---

## 12. What not to do

- Do not build the web client before the native apps ship.
- Do not add a social feed to solve growth.
- Do not paywall export, statistics, or the user's own data.
- Do not ship the agent without the plan card and the undo ribbon.
- Do not put "AI" in the headline, the app name, or the first screenshot.
- Do not launch publicly before ten strangers have imported successfully.
- Do not start MOAT-001..003 before phase D; they need a library to be worth anything.
- Do not rebrand, rename, or re-architect. Measure first.
