# SHR-002 · Share links (design): share anything, anyone can open it

## Context

The owner wants to share any catalog item with anyone: a film, show, anime, manga, book or album, a sports match or result, or a concert. The person who opens the link may have no account and no app. Today the only outward link is the friend invite (`aaruapp.com/i/{code}`, SOC-002). It works once, makes the opener a friend, and can carry one title only. Recommend (SOC-006) reaches friends only. Every catalog, sports and concert route needs a session, so nothing is public except the invite preview.

The outcome is a reusable link that can be dropped into a group chat. Anyone who taps it sees the content. Signed-in people can save it in one tap. A friend of the sender also sees who sent it and the note. This is also the demand-side on-ramp, because strangers arrive through it.

## Owner decisions (2026-10-25)

- **The opener just sees the content.** The link makes no friendship, works for many people and does not expire. "Add to my Aaru" is offered and never required.
- **The sender's name shows only to friends.** Strangers, signed-out viewers, non-friends and anyone blocked either way see the content only. A signed-in friend of the sender (no block) also sees "from {name}" and the optional note.
- **Sports show the score up front.** A finished match shows the result. A live match shows the live score.
- **The web is the app.** There is no install push and no TestFlight link. With the app installed, the iPhone opens the link in the app (universal link). Everyone else gets the web page, and sign-up returns them to it.

## Scope

**In:** titles of all six kinds (by MediaRef, the same addressing as `/app/catalog/$type/$provider/$ref`), sport events (TheSportsDB event id) and concerts (Ticketmaster event id).
**Out (my call):** lists, shelves, Board posts, profiles and a user's own rating or review. Those are library or social data, and the privacy rule keeps them friends-only. Single episodes are a later add-on. Group invites stay forbidden.

## Design

### Server (`aaru-server`)

1. **Migration: table `shares`.** Columns: `code` (12 characters, the same generator as `social_invites`), `sender_id` (nullable), `target_kind` (`title` | `sport_event` | `concert`), exactly one of `title_id` (FK to `titles`, `ON DELETE RESTRICT`, as invites do), `sport_event_id` or `concert_id` (provider ids, text), `note` (≤140 characters, nullable), `created_at`.
   - The same sender sharing the same target with the same note (or none both times) reuses the row. A different note gets a new code, so a note written for one chat never changes a link already sent to another (my call).
   - Account delete sets `sender_id` and `note` to null, and the link keeps working with content only (my call).
   - No event data is stored. That keeps the "nothing past the cache" rule for sports and concerts.
2. **`POST /v1/shares`** (auth) `{target, note?}` → `{code, url}`. Rate limit: 60 per hour per user.
3. **`GET /v1/shares/{code}`** (`security: []`, optional session) → `SharePreview {target: TitleCard | SportEventCard | ConcertCard, from?: {handle, displayName, note}, viewer?: {libraryItemId?, status?}}`.
   - `from` is present only when the viewer is a signed-in friend of the sender and neither has blocked the other.
   - An unknown code returns 404.
   - **Cost and abuse (my call):** a link opened 500 times in a big group chat costs about one provider call: titles are read from the catalog row, and sport events and concerts go through the existing shared caches (`SportsCache` event TTL 5 min, `ConcertCache`), so no new cache is added. Rate limit per client address at 600/h (the invite preview's 120/h would choke a group chat). Treat the address as best effort only, because the first `X-Forwarded-For` entry can be spoofed if the API is reachable without the Worker. The cache is what actually protects the TheSportsDB and Ticketmaster budgets. `isPublic` matches on path only, so serve nothing but GET at `/v1/shares/{code}`.
   - **Title:** the MediaRef is resolved once, when the link is made (`TitleResolver.resolve`, as `InviteService.create` does), and the row keeps the `title_id`. Opening the link reads the catalog row and calls no provider (my call, 2026-10-28). Return an explicit DTO, never raw provider JSON.
   - **Sport event:** add a user-free path in `SportsService` that calls `SportsListing.event(id:)` (`TheSportsDBSports.swift:44`) through `SportsCache`. It must not read a watch country or follows (today `SportsService+Fixtures.swift:156` mixes them in).
   - **Concert:** add `event(id:)` to `ConcertListing` (Ticketmaster `GET /discovery/v2/events/{id}`). It goes through the existing short-term cache and counts against the 4,500 per day stop. Nothing about the concert is stored, which keeps the owner rule (CLAUDE.md "Concert"). Over budget, off, or the event is gone: the target is `unavailable` and the page says "This concert's details aren't available right now" (my call).
4. **`AuthMiddleware.swift`:** add `/v1/shares/{code}` GET to `isPublic`, next to the invite rule (`:31`).
5. **`openapi.yaml`:** add the routes and DTOs. Regenerate the Apple client (`scripts/generate-api-client.sh`) and the web types (`npm run api:generate`).
6. **PostHog server events `share_created` and `share_opened`,** both carrying the **sender's** user id (the existing `ProductEvents.swift:40,51` shape) and the target kind. The opener is never identified, signed in or not. Skip `share_opened` when the sender is null (deleted account). Update `docs/privacy.md` first (my call).

### Web (`aaru-client`)

1. **New public route `routes/s.$code.tsx`,** outside `_shell` like `i.$code.tsx`.
   - The loader calls `GET /v1/shares/{code}` with an optional cookie, following `loadInvite` in `lib/social/server.ts`.
   - **New work:** the Worker forwards `CF-Connecting-IP` as `X-Forwarded-For` on this call. Nothing forwards it today (`lib/api/client.ts:12-28`), so every web visitor, invite previews included, shares one bucket. Do it in the shared client so `loadInvite` gets it too.
   - **Extend `safeNext`** (`lib/oauth/model.ts:13-19`) to allow `/s/{code}` with an optional `?add=1`. Otherwise sign-in quietly drops the opener at `/app`.
   - **Head:** `noindex`. `og:title` is the name, `og:description` is the year and kind, or "Team A 2–1 Team B · League", or the concert's date and venue. `og:image` is the poster, badge or event image URL from the catalog (no generated image, my call), falling back to `/og.jpg`.
   - **Body:** a cover card per kind (poster, title, year, kind, overview, score or result, kickoff or concert date) and "from {name}: note" when present. CTAs:
     - **Title, signed in:** Add to Plan to watch/read/listen (the same write as a tap, journaled, undo), or "In your library · {status} · Open" when the viewer already has it.
     - **Title, signed out:** "Add to my Aaru" goes to `/sign-in?next=/s/{code}?add=1`. Back on the page, `add=1` adds the title once and then strips the param.
     - **Sport event:** "Open in Sports" when signed in. Otherwise "Follow sports on Aaru" goes through sign-in.
     - **Concert:** "Tickets" links out to the Ticketmaster `url`. "Concerts near you on Aaru" goes through sign-in.
     - **Always:** a quiet "What is Aaru?" link to `/`.
2. **Share button** on the catalog preview route, the title page, the sports `EventSheet.tsx` and the concert card. It calls `POST /v1/shares`, then `navigator.share` with a fallback to copy. An optional note field is labelled "Only your friends see this note". Use shadcn-solid components from `~/components/ui` only.
3. **AASA:** add `/s/*` in `lib/links/apple.ts:12`.

### iOS (`aaru-ios`)

1. A `ShareLink`, using the pattern in `Social/InviteViews.swift:33`, on the title detail, catalog preview, sports event sheet and concert row. The URL comes from `POST /v1/shares`, and the composer has the optional note.
2. `RootView.swift:66` `.onOpenURL`: add a `SharedLink` parser for `/s/{code}` next to `InviteLink`, on the same three hosts. (The type can't be named `ShareLink`, which would clash with SwiftUI.)
3. A new `SharePreviewView` sheet works signed in or out, because the owner rule is that the opener just sees the content (as invites do at `RootView.swift:65`). It shows the same card per kind as the web page, with these CTAs:
   - **Title:** "Add to Plan to …", or "Open" when the item is already in the user's library, which pushes the library item.
   - **Sport event:** "Open in Sports" opens the event sheet.
   - **Concert:** "Tickets" links out. iOS has no concert detail (`ConcertRow.swift:110`), and none is added.
   - **Signed out:** "Add to my Aaru" holds the link as pending through sign-in, like `pendingInvite`, and then adds the title.
   - New surface: add it to `DESIGN.md` and `VIEWS.md`.
4. The entitlements already include `applinks:aaruapp.com`, so iOS needs no change beyond the AASA paths.

### Docs

- `BACKLOG.md`: an owner decision dated 2026-10-25 and the SHR-002 item. Grep `origin/main` for a collision before taking the id (parallel sessions).
- `CLAUDE.md` domain language: **Share link**, meaning a public, reusable link to one catalog item, with the sender visible only to friends. Note that it is not an Invite and not a Recommendation.
- `ARCHITECTURE.md`: the new public endpoint.
- `DESIGN.md` and `VIEWS.md`: the share page surface and the Share button.
- `docs/privacy.md`: what a stranger sees and the two events.

### PR order

Following "table → DTO → client screen":
1. Server and openapi.
2. Web page, Share button and AASA.
3. iOS.
Promote the API by hand through the infra repo (bump the api tag).

## Verification

- **Server tests** (stub providers, no real keys). A new `ShareTests` covers:
  - Create and dedupe.
  - The public GET without a session returns the content and no `from`.
  - A signed-in non-friend gets no `from`, a friend gets `from` and the note, and a block either way gets no `from`.
  - An unknown code returns 404.
  - Account delete nulls the sender and the link still resolves.
  - The rate limit holds.
  - A sport event resolves without user context.
  - A concert over budget, off or gone resolves to `unavailable`.
- **Commands:**
  - `cd aaru-server && swift test`
  - `swift test --package-path aaru-api`
  - `cd aaru-client && npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size`
  - `./scripts/lint.sh`
- **Web e2e by hand (beta Worker):**
  - Share a film from account A.
  - Open it in a private window: content shows, no name, and the OG preview is right (paste it into WhatsApp or check with an OG debugger).
  - Sign up through "Add to my Aaru": the page comes back and the film is in Plan to watch.
  - Account B, a friend of A, sees "from A" and the note.
  - Repeat for a finished match (score shown), a live match and a concert.
- **iOS:** on a TestFlight device with the app installed, tapping `/s/{code}` in Messages opens the app on the right sheet.
