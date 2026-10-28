# SHR-002 Share links · Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone can open `aaruapp.com/s/{code}` on the web and see the shared title, match or concert; signed-in people can save a title in one tap. A Share button on titles, sport events and concerts makes the link.

**Architecture:** A public route `s.$code.tsx` outside `_shell`, built like `i.$code.tsx`: a server function loads `GET /v1/shares/{code}` with the optional session cookie, and pure helpers in `lib/shares/model.ts` give the head and the page lines. A `ShareDialog` component (note, then the link with Share and Copy) calls `POST /v1/shares`. The Worker forwards the visitor's address so the API's per-address preview limit sees people, not the Worker.

**Tech Stack:** SolidJS + TanStack Start on Workers, openapi-fetch (`lib/api/client.ts`), zod server functions, shadcn-solid through `~/components/ui`, vitest.

**Spec:** `docs/superpowers/specs/2026-10-28-share-links-design.md` (§Web, §Docs). The server is merged (#215); its plan is `docs/superpowers/plans/2026-10-28-share-links-01-server.md`.

## Global Constraints

- All UI comes from `~/components/ui` (shadcn-solid). Never a raw `button`/`input`/`textarea`/`dialog`. ESLint enforces it.
- Colours only from tokens (no hex). Headings are `font-display` (the system sans). `ci-brand.yml` enforces it.
- The opener just sees the content. No friendship, no install push, no TestFlight link.
- The sender's name and note show only when the API sends `from`. The web never infers them.
- The note field is labelled "Only your friends see this note". The note is at most 140 characters (`maxLength={140}`). The server validates it.
- The share page is `noindex`.
- `safeNext` allows exactly `/s/{code}` and `/s/{code}?add=1`, where the code is `[A-Za-z0-9]{1,32}`.
- Sports show the score up front: the final result when finished, the live score when live.
- Concert "Tickets" links out to the event's `url` (`target="_blank" rel="noopener noreferrer"`).
- `docs/privacy.md` changes before the code it describes (owner, 2026-10-21).
- Commands: `cd aaru-client && npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size`.
- `npm run typecheck` may rewrite `src/routeTree.gen.ts` and drop the Start register block. Keep the route's real entries, restore that block (`git diff src/routeTree.gen.ts`), and commit only the route lines.

## Rulings made while planning

- **The AASA `/s/*` claim moves to plan 03 (iOS).** The installed app claims `aaruapp.com` already. If the AASA claimed `/s/*` before the app parses `/s/{code}`, every iPhone with Aaru would open share links in an app that ignores them, and the web page would never show. Plan 03 adds the claim with the parser. Cost if wrong: one line is late.
- **The Share flow takes two taps: Create link, then Share.** Safari drops the tap's user activation across the `POST /v1/shares` await, so calling `navigator.share` after it can fail. Cost if wrong: one extra tap.
- **"Open in Sports" goes to `/app/sports?view=schedule&date={event.day}`.** The Sports page has no way to open an event by id, and adding one is outside this plan. Cost if wrong: the person finds the match in that day's schedule.
- **There's no Undo toast after Add on the share page.** `POST /v1/library/items` returns no action id, and the catalog preview's Add has no toast either. The write is journaled, so History undoes it. Cost if wrong: a later small task.
- **The sender line is text only:** "From {name}" plus the note. A `SocialUser` avatar URL is never sent on a public route.

## Review Focus

1. **A signed-in viewer comes back from sign-in on `?add=1` but already has the title** (the API sends `libraryItemId`). Expected: no second add, "In your library" shows, and the param is stripped. Pinned by `shouldAutoAdd` tests (Task 2).
2. **The session cookie is expired or invalid.** Expected: the page renders as signed out and never errors. `loadShare` treats a failed `/v1/me` as signed out (Task 2).
3. **A sport event with no score yet, or a UFC or WWE card with no sides.** Expected: the description never says "undefined" or "NaN". Pinned by `shareDescription` tests (Task 2).
4. **`unavailable: true`.** Expected: a plain line per kind, no broken card, and the head falls back to the default description and `/og.jpg`. Pinned (Task 2).
5. **An `og:image` value that isn't absolute https** (a relative path or `http:`). Expected: `/og.jpg`. Pinned by `shareImage` tests (Task 2).

---

### Task 1: Privacy line, `safeNext` for share links, and forwarding the visitor's address

**Files:**
- Modify: `docs/privacy.md` (the **Share links** paragraph, around line 122)
- Modify: `aaru-client/src/lib/oauth/model.ts:13-19` and its test `model.test.ts`
- Create: `aaru-client/src/lib/api/forwarded.ts` and `forwarded.test.ts`
- Modify: `aaru-client/src/lib/api/client.ts`

**Interfaces:**
- Produces: `safeNext` accepts `/s/{code}` and `/s/{code}?add=1`.
- Produces: `forwardedFor(address: string | null | undefined): Record<string, string>` returns `{ 'X-Forwarded-For': address }` for a plausible IPv4 or IPv6 address, otherwise `{}`.

- [ ] **Step 1: Privacy first.** Append to the **Share links** paragraph: "To stop one address opening links without limit, the website passes your IP address to Aaru's server with each request. The server counts it in memory for up to an hour and never stores it."

- [ ] **Step 2: Write the failing tests.** In `oauth/model.test.ts`, add `safeNext('/s/k7Q2xPa9Lm3Z')` and `safeNext('/s/k7Q2xPa9Lm3Z?add=1')`, both expected to keep their input. Add to the refusal list: `'/s/'`, `'/s/abc/def'`, `'/s/abc?add=2'`, `'/s/abc?add=1&next=//evil.example'`, `'/s/../app'`.

  `forwarded.test.ts` cases:
  - `forwardedFor('203.0.113.7')` gives `{ 'X-Forwarded-For': '203.0.113.7' }`.
  - `forwardedFor('2001:db8::1')` keeps it.
  - `undefined`, `null`, `''`, `'not an ip'` and `'1.2.3.4, 5.6.7.8'` all give `{}`.

- [ ] **Step 3: Run them.** `cd aaru-client && npx vitest run src/lib/oauth src/lib/api/forwarded`. Expected: FAIL, because the new `safeNext` cases fall back to `/app` and the `forwarded` module is missing.

- [ ] **Step 4: Implement.**
  - In `safeNext`, add `/^\/s\/[A-Za-z0-9]{1,32}(\?add=1)?$/.test(next)` and update the doc comment ("…a friend invite link and a share link").
  - Write `forwardedFor` to accept `^[0-9A-Fa-f:.]{2,45}$`.
  - In `api()`, merge `forwardedFor(requestAddress())` into `headers`. `requestAddress()` reads `getRequestHeader('cf-connecting-ip')` from `@tanstack/solid-start/server`, wrapped in try/catch like `requestTimeZone`, and returns null outside a request.
  - Add one comment line: the API's per-address limits (invite and share previews) see the visitor, not the Worker.

- [ ] **Step 5: Run the tests again.** Same command. Expected: PASS. Then run `npm run typecheck && npm run lint`. Expected: clean.

- [ ] **Step 6: Commit.**
```bash
git add docs/privacy.md aaru-client/src/lib/oauth aaru-client/src/lib/api/forwarded.ts aaru-client/src/lib/api/forwarded.test.ts aaru-client/src/lib/api/client.ts
git commit -m "Web: sign-in returns to share links; forward the visitor's address to the API"
```

### Task 2: Share model and server functions

**Files:**
- Create: `aaru-client/src/lib/shares/model.ts` and `model.test.ts`
- Create: `aaru-client/src/lib/shares/server.ts`

**Interfaces:**
- Consumes: `components['schemas']` from `~/lib/api/schema`, `kindOf` and `kindName` (`lib/library/model`), `eventTitle` and `hasScore` (`lib/sports/model`), `placeLine` from `lib/concerts/model` (import it as `concertPlace`), and `SITE_URL`.
- Produces, in `model.ts`:
  - The types `SharePreview`, `ShareTarget = components['schemas']['ShareTargetInput']` and `ShareLink`.
  - `shareName(p: SharePreview): string | null`: the title's name, `eventTitle(sportEvent)` or the concert's `name`. Null when the preview is unavailable or has no content.
  - `shareDate(day: string): string`: `'2026-11-14'` becomes `'Sat 14 Nov 2026'` (UTC). Build it from `Intl.DateTimeFormat('en-GB', …).formatToParts` so no comma creeps in. An input that isn't a day comes back unchanged.
  - `shareDescription(p: SharePreview): string`.
  - `shareImage(p: SharePreview): string`.
  - `addNext(code: string): string`, which returns `` `/s/${code}?add=1` ``.
  - `shouldAutoAdd(input: { add: boolean; signedIn: boolean; preview: SharePreview }): boolean`.
  - `DEFAULT_DESCRIPTION = 'One private shelf for everything you watch and read.'`
- Produces, in `server.ts`:
  - `loadShare({ data: { code } }) → Promise<SharePage>`, where `type SharePage = { preview: SharePreview | null; signedIn: boolean }`.
  - `createShare({ data: { target, note? } }) → Promise<ShareLink>`.

- [ ] **Step 1: Write the failing tests** in `model.test.ts`, with fixtures built as plain objects typed `SharePreview`.
  - `shareDescription`, title: a film from 2016 gives `'Film · 2016'`. A book from 1965 with byline `Frank Herbert` gives `'Book · 1965 · Frank Herbert'`.
  - `shareDescription`, sport finished: home Arsenal 2, away Chelsea 1, league Premier League gives `'Arsenal 2–1 Chelsea · Premier League'`.
  - Sport live at the same score gives `'Arsenal 2–1 Chelsea · Live · Premier League'`.
  - Sport scheduled on day `2026-11-14` with no scores gives `'Arsenal v Chelsea · Premier League · Sat 14 Nov 2026'`.
  - A card (no sides) named `UFC 320` on `2026-11-14` with no league gives `'UFC 320 · Sat 14 Nov 2026'`.
  - A concert on `2026-11-14` at venue O2 Arena, city London gives `'Sat 14 Nov 2026 · O2 Arena · London'`.
  - `unavailable: true` gives `DEFAULT_DESCRIPTION`.
  - `shareImage`:
    - A title with `posterUrl` `https://image.tmdb.org/t/p/w500/x.jpg` returns it.
    - A sport event with no `imageUrl` but a home `badgeUrl` returns the badge.
    - A concert `imageUrl` of `http://x` or `/x.jpg` returns `https://aaruapp.com/og.jpg`.
    - Unavailable returns `https://aaruapp.com/og.jpg`.
  - `shareName`: unavailable returns `null`, and the sport case returns `'Arsenal v Chelsea'`.
  - `shouldAutoAdd` is true only for `{add: true, signedIn: true}` on an available title with no `libraryItemId`. It's false when `libraryItemId` is set, when signed out, when `add` is false, and for `sport_event`.
  - `addNext('abc')` returns `'/s/abc?add=1'`.

- [ ] **Step 2: Run them.** `npx vitest run src/lib/shares`. Expected: FAIL, because the module is missing.

- [ ] **Step 3: Implement `model.ts`.**
  - Sport order: the score part (`hasScore`, so `{home} {h}–{a} {away}`), else `eventTitle`. Then `Live` when live, then the league, then `shareDate(day)` only when there's no score. Join with `' · '` and skip parts that are empty.
  - Image order: title `posterUrl`; sport `imageUrl ?? home.badgeUrl ?? leagueBadgeUrl`; concert `imageUrl`. Accept only `https://` URLs.

- [ ] **Step 4: Implement `server.ts`** like `loadInvite` and `createInvite` in `lib/social/server.ts`.
  - `loadShare`:
    - Validate `code` with `z.string().min(1).max(32)`.
    - Read `token = getCookie(SESSION_COOKIE)` and run `GET /v1/shares/{code}` and (with a token) `GET /v1/me` together.
    - A 404 gives `preview: null`. Any other status without data throws `errorMessage(error, 'This link could not be opened.')`.
    - `signedIn` is `!!me?.data`.
  - `createShare`:
    - Validator: `{ target: { kind: z.enum(['title','sport_event','concert']), ref: mediaRef.optional(), id: z.string().min(1).max(64).optional() }, note: z.string().max(560).optional() }`. Copy the `mediaRef` zod object from `social/server.ts`. The server enforces the real 140-character limit.
    - POST `/v1/shares` with `api(sessionToken())`, and send `note: note?.trim() || undefined`.
    - Wrap the call in `check(…, 'The link was not made.')`.

- [ ] **Step 5: Run the tests again.** `npx vitest run src/lib/shares && npm run typecheck`. Expected: PASS, and typecheck clean.

- [ ] **Step 6: Commit.**
```bash
git add aaru-client/src/lib/shares
git commit -m "Web: share link model and server functions"
```

### Task 3: The public share page `/s/$code`

**Files:**
- Create: `aaru-client/src/routes/s.$code.tsx`
- Modify: `aaru-client/src/routeTree.gen.ts` (generated, route lines only)
- Modify: `aaru-client/size-budget.json` (add `"/s/$code"`)

**Interfaces:**
- Consumes: everything Task 2 produces; `addToLibrary` (`lib/library/server`); `kindOf` and `statusLabel` (`lib/library/model`); `inviterName` (`lib/social/model`); sports `hasScore`, `isCard`, `statusLabel` (as `sportStatus`), `whenLine`, `clockLabel` and `placeLine`; concerts `placeLine`; `viewerTimeZone` (`lib/timezone`); `localDayKey` (`lib/calendar/model`); `Poster`; `Wordmark`; `SportBadge`; `Button` and `buttonVariants`.

- [ ] **Step 1: Write the route.**
  - **Route setup:**
    - `createFileRoute('/s/$code')`.
    - `validateSearch: (s) => ({ add: s.add === 1 || s.add === '1' ? true : undefined })`.
    - `loader: ({ params }) => loadShare({ data: { code: params.code } })`.
  - **`head`:**
    - `title: \`${shareName(p) ?? 'Shared on Aaru'} · Aaru\``.
    - `robots: noindex`.
    - `description`, `og:description` from `shareDescription`, and `og:title` from `shareName` (falling back to 'Shared on Aaru').
    - `og:image` from `shareImage`, plus `og:type website` and `twitter:card summary_large_image`.
    - With `preview: null`, use 'Aaru' and `DEFAULT_DESCRIPTION`.
  - **Layout:** the same `Page` shell as the invite page (`Wordmark`, then `max-w-md`). With `preview` null, show the `Invalid` block:
    - Heading: "This link doesn’t work."
    - Body: "It may have been mistyped. Ask whoever sent it for the link again."
    - A "What is Aaru?" link to `/`.
  - **Sender line,** when `from` is present: "From {inviterName(from.user)}", then the note in `“…”` on its own line, `text-muted`. Above the card.
  - **Title card:**
    - `Poster`, `h1` name (`font-display`), facts `kindName · year · byline`, and the synopsis clamped to 6 lines.
    - CTA, by state:
      - Has `libraryItemId`: "In your library · {statusLabel(status, kind)}" with a `Link` "Open" to `/app/title/$id`.
      - Signed in: a `Button variant="ink" size="lg"` "Add to {statusLabel('wishlist', kind)}". It calls `addToLibrary({type, ids, title, year, status: 'wishlist'})`. On success, show "On your {label}" plus Open. On error, show `role="alert"`.
      - Signed out: "Add to my Aaru". It navigates to `/sign-in` with `search: { next: addNext(code) }`.
  - **Sport card:**
    - League badge and league eyebrow.
    - Score up front: `{home.score}–{away.score}` in `font-display text-5xl tabular-nums` (accent when live) when `hasScore`. Otherwise `v` and the kick-off from `whenLine(event, today, timeZone)`.
    - A card shows `imageUrl` and its name.
    - A status line uses `sportStatus` (and a Live dot with `clockLabel`), then `placeLine`.
    - CTA: signed in, a `Link` "Open in Sports" to `/app/sports` with `search: { view: 'schedule', date: event.day }`. Signed out, "Follow sports on Aaru" goes to `/sign-in?next=/app/sports`.
    - `timeZone` and `today` start as `'UTC'` and the UTC day, and switch to `viewerTimeZone()` and `localDayKey(new Date())` in `onMount`, as the Sports page does.
  - **Concert card:**
    - `imageUrl` (`referrerpolicy="no-referrer"`), name, artists joined by `, `, `shareDate(localDate)` plus `localTime`, and the concert `placeLine`.
    - An `<a>` "Tickets ↗" styled `buttonVariants({ variant: 'ink', size: 'lg' })` with `target="_blank" rel="noopener noreferrer"` and the aria-label "Tickets for {name} on Ticketmaster (opens a new tab)".
    - Then a quiet link "Concerts near you on Aaru": `/app/music` when signed in, `/sign-in?next=/app/music` when signed out.
  - **Unavailable:** the line "This match’s details aren’t available right now." or "This concert’s details aren’t available right now." A title is never unavailable.
  - **Footer, always:** a quiet `Link` "What is Aaru?" to `/`.
  - **Auto-add:** `onMount`, if `shouldAutoAdd({ add: !!search().add, signedIn, preview })`, run the same add once. Then strip the param: `navigate({ to: '/s/$code', params, search: {}, replace: true })`. Whether or not it adds, strip `add` once mounted.

- [ ] **Step 2: Check the route.** `npm run typecheck` (then restore the register block in `routeTree.gen.ts`), `npm run lint`, `npm run check`. Expected: clean.

- [ ] **Step 3: Check by hand,** with the local API on `swift run` and `npm run dev`:
  - Create a share with `curl -X POST /v1/shares` for a film, a show and a book.
  - In a private window, open `/s/{code}`: content shows, no "From", and the head has noindex plus `og:*` (view source).
  - Click "Add to my Aaru", sign up, and land back on `/s/{code}`: the film is on Plan to watch, and the URL has no `?add`.
  - As the sender's friend, you see "From …" and the note. As a stranger signed in, you don't.
  - An unknown code shows "This link doesn’t work."
  - With sports or concerts off locally, the unavailable line shows.

- [ ] **Step 4: Budget.** Run `npm run build && npm run size`. Add `"/s/$code"` set to the measured size rounded up to the next 100 bytes. Expected: `size` passes.

- [ ] **Step 5: Commit.**
```bash
git add aaru-client/src/routes/s.\$code.tsx aaru-client/src/routeTree.gen.ts aaru-client/size-budget.json
git commit -m "Web: the public share page, /s/{code}"
```

### Task 4: `ShareDialog` and the Share buttons

**Files:**
- Create: `aaru-client/src/components/ShareDialog.tsx`
- Modify: `aaru-client/src/routes/_shell.app_.catalog.$type.$provider.$ref.tsx` (in `actions()`)
- Modify: `aaru-client/src/routes/_shell.app_.title.$id.tsx` (after Recommend in the action row, and in the `AlbumHeader` children)
- Modify: `aaru-client/src/components/sports/EventSheet.tsx` (header, beside Done)
- Modify: `aaru-client/src/components/ConcertList.tsx` (`ConcertRow`, beside Tickets; one dialog per list)
- Modify: `aaru-client/size-budget.json` (the routes that grow)

**Interfaces:**
- Consumes: `createShare` and `ShareTarget` (Task 2).
- Produces: `ShareDialog(props: { open: boolean; target: ShareTarget; name: string; onClose: () => void })`. The caller keeps it mounted after the first open and passes `open`, so the exit animation plays (WEB-011, the `recommendedOnce` pattern).

- [ ] **Step 1: Write `ShareDialog`,** modelled on `RecommendDialog` (`placement="sheet"`, header with title "Share {name}" and Cancel/Done). Every time it opens, the state resets.
  - **Step A:**
    - A `TextField` with label "Note (optional)" and description "Only your friends see this note".
    - `TextFieldInput maxLength={140}` with placeholder "Why it’s worth it".
    - A `Button` "Create link" (busy: "Making the link…") that calls `createShare({ data: { target, note } })`.
  - **Step B:**
    - The URL in a read-only `TextFieldInput` that selects all on focus.
    - When `typeof navigator.share === 'function'`, a `Button` "Share…": `navigator.share({ title: name, url })`, with `AbortError` ignored.
    - Always a `Button variant="outline"` "Copy link": `navigator.clipboard.writeText(url)`, then the notice "Link copied."
    - The line "Anyone with the link can see {name}. Only your friends see that you sent it."
  - Errors go in a `role="alert"` `text-danger` paragraph, as `RecommendDialog` does.

- [ ] **Step 2: Wire the buttons.** Each one is a `Button variant="quiet"` "Share", mounted on first open.
  - Catalog preview: target `{ kind: 'title', ref: { type, ids, title, year } }`.
  - Title page: `{ kind: 'title', ref: { titleId: entry().title.id, type: entry().title.type } }`.
  - `EventSheet`: a ghost `size="bare"` "Share" before Done, with `{ kind: 'sport_event', id: event().id }` and `name: eventTitle(event())`. The `ShareDialog` nests inside the sheet's dialog.
  - `ConcertRow`: an `onShare` prop, and the button beside Tickets. `ConcertList` holds `sharing = createSignal<Concert | null>` with `lastShown` and renders one `ShareDialog` with `{ kind: 'concert', id: concert.id }`.

- [ ] **Step 3: Check the wiring.** `npm run check && npm run lint && npm run typecheck && npm test`. Expected: clean, and every existing test passes.

- [ ] **Step 4: Check by hand** (`npm run dev`, signed in):
  - Share from a catalog preview, a title page (show and album), a sports event sheet (the inner sheet opens over the event sheet and Esc closes only the inner one) and a concert row.
  - Each one makes a link that opens the right page in a private window.
  - Making the same note twice gives the same URL.
  - Copy link works on desktop.

- [ ] **Step 5: Budget.** Run `npm run build && npm run size`. Raise each route that grew to its measured size rounded up to the next 100 bytes, and record which ones in the commit message. Expected: `size` passes.

- [ ] **Step 6: Commit.**
```bash
git add aaru-client/src/components/ShareDialog.tsx aaru-client/src/routes aaru-client/src/components/sports/EventSheet.tsx aaru-client/src/components/ConcertList.tsx aaru-client/size-budget.json
git commit -m "Web: Share on titles, sport events and concerts"
```

### Task 5: Docs

**Files:**
- Modify: `DESIGN.md` §17 (a new `### Share links (SHR-002, owner 2026-10-25)` after `### Invites`)
- Modify: `VIEWS.md` (Surface map rows after "Invite letter")
- Modify: `ARCHITECTURE.md` (the Share links bullet near line 1256)
- Modify: `BACKLOG.md` (the SHR-002 status row, line 862)

- [ ] **Step 1: Write them.**
  - **DESIGN.md:** a share link is a postcard, not a letter. It shows the content first, the sender only to friends, one action per kind, and a quiet "What is Aaru?". Describe the Share sheet as note, then link, then Share or Copy.
  - **VIEWS.md:** two rows.
    - "Share link page": web `/s/{code}`, the per-kind card, CTAs, `GET /v1/shares/{code}` (public), `POST /v1/library/items`, SHR-002 (2026-10-28).
    - "Share (sheet)": from the catalog preview, a title, a sport event and a concert. It holds the note "Only your friends see this note", then Share/Copy, and calls `POST /v1/shares`.
  - **ARCHITECTURE.md:** add one sentence: the web serves `/s/{code}` outside the shell, and the Worker forwards `CF-Connecting-IP` as `X-Forwarded-For` so per-address limits see visitors. The `/s/*` universal link comes with the iOS plan.
  - **BACKLOG.md:** set the SHR-002 row's evidence to "server #215 (promoted); web plan `…-02-web.md`" and next to "iOS plan 03".

- [ ] **Step 2: Run the full gate.** `cd aaru-client && npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size`. Expected: all pass.

- [ ] **Step 3: Commit.**
```bash
git add DESIGN.md VIEWS.md ARCHITECTURE.md BACKLOG.md
git commit -m "Docs: SHR-002 web share page and Share sheet"
```
