# Faster friends + fuller groups — design and plan

## Context

Adding a friend works. **Finding** them is slow. Today the only ways are an exact `@handle`
(`PostgresSocialStore.swift:52-57`, `WHERE p.handle = $1`) or a one-use invite link. Friends
is also buried: web opens on the Board with Add/Invite at the bottom of "Lately", and
iPhone has no Friends tab (Groups → Friends button → Lately → scroll). Requests are silent
(no push, no web badge). Signing up through an invite still ends on a handle form plus an
"Add" tap.

Groups (GRP-001…012) are built and merged, Discord-shaped on web, on iPhone/iPad/Mac. But
the owner did not find them: they sit under **More** (NAV-001/002, 2026-10-25). Trying them,
chat felt thin: no message reactions, replies, images, or who's online.

Outcome: a user finds the people they know in seconds. Groups are one tap away and feel
like a real chat. The private-first rule still holds.

## Owner decisions (2026-10-27, this conversation)

1. Find friends faster through **contacts/email**, **Trakt/AniList**, and **shared groups**.
   Social sources only where the API is free.
2. Discoverability is **opt-in, off by default**, per source.
3. "People you may know" uses shared groups, Trakt/AniList follows, and contacts/email.
   **Not** friends of friends.
4. **Phone numbers deferred**. Verifying them needs paid SMS. Revisit when a verification
   choice is made.
5. Groups: bring them out of More and add **message reactions, replies, images, who's
   online**. All four. Reactions are six quick ones plus a full emoji picker. "Online" is
   asked once, when someone joins their first group.
6. iPhone: **one Friends tab** replaces Calendar in the tab bar. Inside it,
   `[Groups | Friends | Board]`, with requests and suggestions on top. Calendar moves to More.
7. One plan covers all of it.

**Earlier decisions this reverses.** Record them in `BACKLOG.md` decisions as owner,
2026-10-27:
- 2026-10-20 "friends by handle only, no email hash" → opt-in email, Trakt and AniList discovery.
- `docs/privacy.md:65-68` "nobody can search or browse for you" → rewritten (below).
- `BACKLOG.md:3178` "no presence, attachments … in v1" → images and presence now.
- NAV-002's iPhone tabs → the Friends tab.
- RT-001 (`BACKLOG.md:3557`) "presence is friends-only" → group co-members see each other
  online, if the user said yes when asked.

**Kept as is:** no group invite links, no public or discoverable groups, mutual friends
only (no follow), friends-only membership, and the agent never sends requests or invites.

## Goals / non-goals / anti-goals

- **Goal:** someone with a friend on Aaru reaches "request sent" without asking for a
  handle. Someone invited from outside lands as a friend straight after signup.
- **Non-goals:**
  - phone matching
  - Facebook, Discord, X, Instagram, MAL friend import (paid, closed, or no endpoint)
  - friends of friends
  - "X joined Aaru" pushes
  - reusable "add me" links or QR
  - group invite links
  - threads, video or file attachments
- **Anti-goals (a failure even if it works):**
  - anyone shows up to a stranger without opting in
  - a not-opted-in user can be told apart from a nonexistent one
  - an uploaded contact list is kept
  - a non-member is ever given a group image link. *My call:* links expire after 5 minutes,
    and an unsigned or expired link fails. A link a member forwards is the same risk as a
    screenshot, so the server does not stream bytes.
  - email addresses appear in logs, Sentry, or PostHog

---

## Part A — Friends quick wins (no privacy change)

**A1 · Rate limits (SOC-008, do first).**
- Handle lookup (`GET /v1/social/users/{handle}`) and `POST /v1/social/friend-requests` have
  no limit today, so handles can be enumerated.
- Reuse `FixedWindowRateLimiter` (`aaru-server/Sources/App/Auth/RateLimiter.swift:5`), as
  `InviteService.swift:34-35` does.
- *My call:* lookup 60/h per user, requests 30/h per user; 429 beyond that.

**A2 · Request alerts (finishes SOC-005).**
- Push (APNs and web push) for a new request, an accepted request, and a redeemed invite.
- Behind a new notification switch, following the pattern in `Social/GroupService+Push.swift`
  and the `Migrations+GroupPush.swift` switches.
- Badge the incoming-request count on the web Friends nav row and the iPhone Friends tab.

**A3 · Friends top strip.**
- Above Board | Lately (web `routes/_shell.app_.friends.index.tsx`, iOS `FriendsScreen.swift`):
  - incoming requests (accept/decline inline)
  - "People you may know" (Part B)
  - one add field that takes `@handle` or an email
  - "Invite a friend"
- The Board stays the default view below it (2026-10-23 decision).

**A4 · Add from where people already are.**
- Group member rows get an Add / Requested / Accept button (web
  `components/groups/MemberList`, iOS members sheet).
- The web non-friend profile `/app/friends/{handle}` stops dead-ending
  (`lib/social/server.ts:264` throws away the relationship today). It shows Add / Accept /
  Requested. Do the same on iOS.

**A5 · Invite → friend without extra taps.**
- Signing up from `/i/{code}`: the handle step is part of signup. The invite is redeemed
  automatically once the handle is claimed, showing "You and X are friends".
- *My call:* auto-redeem. Clicking "Join Aaru" on an invite is the intent. This replaces
  BACKLOG:3059's "one tap after sign-up".
- iOS keeps the pending code in `UserDefaults` (1 h), so it survives the app being killed
  (`RootView.swift:22-24`).
- Web: carry `next` inside the magic-link email so it works across devices; keep the
  localStorage fallback (`lib/session/pending-next.ts`).

**A6 · Measure it.** Fire the existing `friend_added` event on invite redeem and on the
"both asked" auto-accept, not only in `accept()` (`SocialService.swift:90`). No new event.

## Part B — Opt-in discovery

**Settings → Friends & privacy: three switches, off by default.**
- The switches: "Find me by email", "Find me by Trakt", "Find me by AniList".
- Each one states plainly who sees what. For example: "people who have this email can see
  your name and handle and send you a request".
- Turning a switch off deletes its row at once.

**Storage.**
- New table `social_discovery(user_id, source email|trakt|anilist, key_hmac bytea,
  created_at)`, `UNIQUE(source, key_hmac)`.
- `key_hmac` = HMAC-SHA256(server secret `DISCOVERY_PEPPER`, normalized key). The secret is
  sealed for `horus`.
- Emails: trimmed and lowercased. *My call:* no Gmail dot or plus folding.
- AniList: its stable numeric user id.
- Trakt: the **slug**. Trakt's friends and following lists return no other id. **Owner
  (2026-10-27): ship it, refreshed daily.** A daily job re-reads each opted-in user's slug
  from `/users/settings` and re-keys their row.
  - Known risk: for up to a day after a rename, someone who takes the old name could be
    matched instead.
  - Check against the live API with a test account before building. If a stable id turns out
    to be available, key on that instead.
- `docs/privacy.md` currently says Trakt tokens are used only for imports. That line changes too.

**Ownership: only proven identities.**
- Email: only an email Aaru has verified. Sign in with Apple users often have a relay email.
  They can add one "findable email", verified with a Resend link like magic sign-in.
- Trakt: from the existing OAuth connection (`trakt_connections`,
  `PostgresTraktStore.swift:35`). Store the Trakt user id there if it is missing.
- AniList: needs a **new AniList OAuth connect** (free, authorization code). An import by
  username proves nothing, and anyone could claim someone else's account. *My call.*

**Lookups.**
- **iPhone/Mac contacts:** "Find friends from contacts" asks for Contacts access (handles
  iOS 18 limited access) and reads **emails only**.
  - `POST /v1/social/discover/contacts { emails: [...] }`, at most 2,000 per call and 3 calls
    a day.
  - The server normalizes, HMACs and matches against `email` rows. The upload is never
    stored or logged.
- **Web:** the add field (A3) takes an email. Exact match against opted-in rows only, 20/h.
  A non-match, a not-opted-in user and a nonexistent user all return the same 404.
- **Trakt:** for a user with a Trakt connection, fetch `/users/me/friends` and
  `/users/me/following` through the existing `ProviderClient`, match against `trakt` rows,
  and cache for 24 h.
- **AniList:** for a user with an AniList connection, the GraphQL `Page { following(userId) }`,
  matched against `anilist` rows, cached for 24 h.

**Suggestions.**
- `GET /v1/social/suggestions`: up to 20 people, each with a reason ("In Movie night", "You
  follow them on Trakt", "In your contacts") and their relationship.
- **Shared-group** suggestions are computed live from co-members. *My guess, not
  contradicted:* no extra opt-in, since members already see each other.
- Contact and provider matches are stored in `social_suggestions(user_id, suggested_user_id,
  source, created_at, dismissed_at)`. This holds the **matches only, never the upload**, for
  30 days.
- Filtered out:
  - yourself
  - existing friends
  - a block in either direction
  - users without a handle
- A pending outgoing request shows as "Requested".
- Actions: one-tap **Add** (an ordinary friend request; mutual if they already asked) and
  **Dismiss**, which hides that person for good.
- New domain term, **Suggestion**: a person under People you may know. It is never a
  Recommendation, which is a title.

## Part C — Groups

**C1 · Navigation (NAV-004).**
- Web: `TOP` in `aaru-client/src/lib/shell/nav.ts` adds Groups after Friends. `MORE` becomes
  Books, Manga, Music, Sports.
- iPhone (`aaru-ios/Aaru/Navigation/AppRouter.swift`): the tab bar becomes Home, Discover,
  Library, **Friends**, More.
  - The Friends tab holds `[Groups | Friends | Board]`. *My call:* it opens on Groups, the
    first segment in your preview.
  - Requests and People you may know sit on top.
  - Calendar moves into More.
- iPad/Mac: Groups moves to the top section of the sidebar.
- Badge: unread mentions plus incoming requests.

**C2 · Stale-invite bug (GRP-013).**
- A block or unfriend must delete pending `group_invites` in both directions
  (`PostgresSocialStore.swift:179-210`).
- Accept must re-check friendship and blocks (`GroupService.swift:178-190`).
- Server test for both.

**C3 · Message reactions (GRP-014).**
- **Owner (2026-10-27):** a quick row of the six from `Reaction.all`
  (`Social/InteractionService.swift:35`), plus "more", which opens the full emoji picker
  (any single emoji).
- The server checks that the value is one emoji grapheme. *My call:* at most 20 distinct
  emoji per message, so a message can't be flooded.
- Table `group_message_reactions(message_id, user_id, emoji, created_at)` with PK on all
  three, so it is idempotent.
- `PUT` / `DELETE …/messages/{m}/reactions/{emoji}`.
- The message DTO carries per-emoji counts and `mine`.
- New WebSocket event `message.reactions` in `Realtime/RealtimeHub.swift`.

**C4 · Replies (GRP-015).**
- `group_messages.reply_to` already exists (`Migrations+Agent.swift:15`); today only
  `@aaru` uses it. Members may now set `replyTo` on POST, and it must be in the same channel.
- The DTO carries a preview: the author and the first ~100 characters, or "deleted".
- Tapping the preview jumps to the original. That needs an `around=` page parameter on
  message list; add `hasMore` at the same time, since the response has no next marker today.
- No threads.

**C5 · Images (GRP-016).**
- **Storage:** Aaru's own MinIO in `horus`. Copy `platform/infra/apps/loci/data/minio.yaml`:
  - its own instance and credentials
  - prune disabled
  - netpol and CORS pinned to the aaruapp.com origins
  - a public host for SigV4
  - 20 Gi PVC
  - credentials sealed per `secrets/*/README.md`
- **Flow:**
  1. `POST …/channels/{c}/attachments` (member check, type, size) returns an id and a
     presigned PUT, signed over length and type.
  2. The client uploads.
  3. `POST …/messages` takes `attachmentIds`, at most 4. The server HEADs each object to
     confirm it.
  4. Message lists give members 5-minute presigned GETs. The server never streams bytes.
- **Limits:** JPEG, PNG, WebP, GIF, HEIC; 10 MB each.
- **Metadata:** clients re-encode to strip EXIF and GPS before upload (iOS `CGImageDestination`
  without metadata, web canvas). The server rejects a JPEG that still has an EXIF/GPS segment.
- **Deletion:** a sweep job deletes uploads left unattached for an hour. Deleting a message,
  a group, or an account deletes its objects.
- **Report a group message:** new, through `social_reports` with a message reference.
  Admins and the owner already can delete.
- Messages stay server-visible, and the "not end-to-end" chip stays.

**C6 · Who's online (GRP-017, the groups part of RT-001).**
- `RealtimeHub` already tracks connections, on a single replica (documented).
- A `presence` envelope goes to people who share a group with the user.
- Shown as a dot on member rows and "N online" in the group header. Online only, never
  which channel.
- A "Show when I'm online" switch sits in Friends & privacy. **Owner (2026-10-27):** asked
  once, with a yes/no on joining or creating the first group. Stored as `show_online`:
  `null` means not asked yet, and the user stays hidden until they answer. Changeable in
  Settings at any time.
- Friend presence and DM delivery stay in RT-001.

---

## Docs first (repo rule: privacy.md changes first)

- `docs/privacy.md`:
  - rewrite :65-68
  - add "Finding friends": the three switches, HMAC keys, contacts never kept, matches kept
    30 days
  - add images: stored on Aaru's server, server-visible, deleted with the message
  - add presence
- `BACKLOG.md`:
  - the 2026-10-27 owner decision with the reversals above
  - new items SOC-008…011, NAV-004, GRP-013…017
  - add the missing GRP rows to the "Every item" table
  - mark ROOM-001/002 closed
- `CLAUDE.md`:
  - domain terms Suggestion, Message reaction, Attachment
  - Stack: Groups row (reactions, replies, images on MinIO), a new Storage row
  - Out of scope: phone matching, friends of friends
- `ARCHITECTURE.md`: discovery, MinIO, presence.
- `DESIGN.md` §18 and `VIEWS.md`: the Friends tab, the top strip, the reaction, reply and
  image components.

## Build order

Each step ships on its own. Every `openapi.yaml` change is followed by
`./scripts/generate-api-client.sh` and `cd aaru-client && npm run api:generate`.

0. Docs above, plus the spec copied to `docs/superpowers/specs/2026-10-27-friends-groups-design.md`.
1. Server safety: A1 rate limits, C2 stale invites.
2. Quick wins: A2 alerts, A4 add-from-anywhere, A5 invite signup, A6 events. Server, then web, then iOS.
3. C1 navigation and A3 top strip on web and iOS.
4. Part B discovery: migration, `DISCOVERY_PEPPER` sealed in `platform/infra`, AniList OAuth,
   endpoints, settings, the contacts flow on iOS, the add field on web.
5. C3 reactions and C4 replies.
6. C5 images: infra PR in `~/Work/production/platform/infra` first (MinIO, netpol, secret,
   values), then server, then clients.
7. C6 presence.

## Verification

- `cd aaru-server && swift test`. New tests:
  - 429 after the limit
  - stale group invite refused after a block
  - a not-opted-in email and an unknown email give the same 404
  - HMAC match and the switch-off delete
  - suggestion filters (blocked, friends, self)
  - reactions idempotent, and broadcast to members only
  - a reply in another channel rejected
  - attachment type and size refused, a non-member gets no GET URL, the orphan sweep runs
  - presence goes only to co-members, and the hide switch works
- Trakt and AniList through **stub servers**, never real keys (CLAUDE.md).
- `cd aaru-client && npm run check && npm run lint && npm run typecheck && npm test`, then
  `npm run build && npm run size`.
- `xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- `./scripts/lint.sh`.
- Manual, recorded in BACKLOG, with two browser profiles plus a simulator:
  - A turns on "Find me by email" and B finds A by email; with the switch off, B gets nothing.
  - A group co-member appears in suggestions, and Add sends a request.
  - A reaction and a reply show up live on the other client within 2 s.
  - An image uploads and shows to members. A non-member's API calls never return its link,
    and the link fails once it expires.
  - The online dot appears and disappears within 2 s.
  - Invite signup on a fresh account lands as friends with no extra tap.

## Left to the builder

- Exact copy for the switches and suggestion reasons.
- Ordering inside suggestions.
- Caching mechanics for the Trakt and AniList follow lists.
- Exact limits beyond those stated.
- How `around=` paging is cut.
- The look of the reaction and reply components, within DESIGN.md and shadcn-solid on web.
