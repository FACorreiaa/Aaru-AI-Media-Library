# Aaru: product marketing strategy

Last verified: 2026-11-14, against `aaru` `origin/main` 21b15bfb, production API `3252c467`
(`platform/infra` `origin/main` fdc6dc8).

Related documents:

- `features.md`: the feature inventory, with what can and cannot be shown.
- `rules/brand.md`: name, colour, type, the owl, credits and voice.
- `rules/video-playbook.md`: how to capture and produce videos.
- `rules/content-calendar.md`: what is planned and approved.

The older go-to-market plan is `../MARKETING.md` (2026-08-29, revised 2026-09-02). Its
§0 "reality snapshot" is obsolete: the product exists now. Its audience order, channels,
launch phases, metrics, risks and "what not to do" are the owner's thinking and are carried
forward here, with facts updated. Where the two disagree on a fact, this file wins; on intent,
ask the owner. `../BUSINESS.md` holds moat and money notes.

## Rules for anyone writing from this document

1. The product is **Aaru**. On the App Store it is listed as **"Aaru - Media Manager"**
   because plain "Aaru" was taken; use that only where the store listing itself is named.
   The name is the Egyptian Field of Reeds: "a calm place where stories live".
2. Every claim must trace to `features.md`. Follow the limits written on each feature.
3. **Availability, today:** the web app is live at `aaruapp.com`; the iPhone, iPad and Mac app
   is on TestFlight and **1.0 is in App Review** (submitted 2026-11-13). Do not write "on the
   App Store", "download now" or show an App Store badge as live until the release is out.
   "Try it on the web" is true now. Android does not exist: never mention it.
4. **No price talk.** Aaru is free today. Plus is built and off sale. Never write a price, a
   trial or "premium". The one permanent promise: export, your library and your statistics are
   never paywalled.
5. **Never lead with "AI".** Not in a headline, the first frame, the first screenshot or the
   app name (MARKETING.md §12, PRODUCT.md tone). The owl is the face; "Ask Aaru" is the verb.
   Never "AI-powered".
6. Never say recommendations, "for you", public profile, feed, followers or social network.
   Aaru has none of them, on purpose.
7. Never invent users, testimonials, statistics or results. The strangers count is **0**.
8. Imports are one-way in. Never "sync with Trakt/Letterboxd".
9. Items marked **Needs confirmation** are open decisions. Do not resolve them by guessing.

---

## 1. Product overview

| | |
|---|---|
| **Product name** | Aaru (store listing: "Aaru - Media Manager") |
| **Website** | `aaruapp.com` (landing, sign-in and the web app in one Worker) |
| **Tagline** | "Your stories. Your world." (the owl poster, DESIGN.md "Brand") |
| **Landing headline** | "Everything you watch, read and follow." with "Private by default. No ads, no feed." above it |
| **One sentence** | One private library for everything you watch, read and listen to: films, shows, anime, manga, books and albums. |
| **Category** | Media tracker / personal library. App Store primary category in `aaru-ios/fastlane/metadata/primary_category.txt` |
| **Operator** | Fernando Correia (GitHub `FACorreiaa`); X `@fatc88` on the landing footer |
| **Price today** | Free. Plus off sale (BIL-005) |
| **Community** | Aaru channel in a shared Discord, "Join us on Discord" on the site and in the app |

**Elevator pitch.** People who follow a lot of stories keep them in four places: Trakt or TV
Time for shows, Letterboxd for films, Goodreads for books, MyAnimeList for anime. Aaru brings
that history into one private library, shows what it matched before anything is added, and
then answers the nightly question, what's next, to the episode and the chapter. Nothing is
public unless you choose it, and you can export everything and leave whenever you like.

### Supported platforms

| Platform | State |
|---|---|
| Web | Live, `aaruapp.com` |
| iPhone, iPad | TestFlight; 1.0 in App Review |
| Mac | TestFlight; 1.0 in App Review. A native Mac client is a pitch on its own (MARKETING.md §7) |
| Browser extension | Built, in no store |
| Android | None |

## 2. Target audience

People who already keep their history somewhere and follow several kinds at once, check in
most evenings, and care when an import drops a row (PRODUCT.md, "Users").

### Personas (hypotheses, from MARKETING.md §6, in priority order)

1. **Trakt power users tired of paying to see their own data.** Highest intent, already have
   an export, reachable in one subreddit. Pitch: free statistics, books and anime in the same
   place, the exit door.
2. **Letterboxd users who also read.** No cross-media home. Emotionally attached to their film
   log: the import must be flawless before reaching them.
3. **Goodreads leavers.** Large, actively looking. Books-first entry, films and manga as the
   surprise.
4. **Anime and manga trackers** (added: anime and manga are first-class since MNG-001, and the
   MAL / AniList importers are among the verified ones). Reachable on r/anime and r/manga
   tooling threads. Pitch: anime that maps onto real TV seasons, manga by chapter and volume.
5. **Apple-ecosystem privacy and quantified-self people.** Small, loud, write blog posts. Pitch
   the Mac app, widgets and Shortcuts.
6. **Couples and friends who watch together.** Recruit from 1–5; Watch parties and groups
   exist but are experimental.
7. **CAT / episode-calendar holdouts.** Tiny; the CAT on-ramp exists.

Nobody here has been interviewed. Treat every persona as a guess until the first ten
strangers say otherwise.

## 3. Problem and solution

**Problem.** A cross-media life is split across services that each own one kind, each want a
subscription to show your own data, and each make leaving hard. Moving between them means
retyping years of history or trusting an import that silently merges the wrong titles.

**Solution.** One library for six kinds, one grammar of status and progress, imports that show
their matches before they write, every write undoable, nothing public, everything exportable.

### Key user benefits

- Bring years of history in from Trakt, Letterboxd, IMDb, Goodreads, MAL, AniList and more.
- See what's next tonight across everything: Up Next, the week, airing alerts.
- Tick episodes and chapters as you go.
- Ask for the larger moves in your own words, and approve them first.
- Keep it private; export everything; delete your account from Settings.

## 4. Positioning and differentiation

**Positioning statement.** For people who follow films, shows, anime, manga, books and music
at once, Aaru is the private library that holds all of it, so they always know what is next.
Unlike single-kind trackers, it takes your history from all of them and lets you leave with
all of it.

### Differentiators, with evidence and limits

| Differentiator | Evidence | Limit |
|---|---|---|
| Six kinds in one library | features §5 | manga and albums experimental |
| Imports from ten-plus sources, reviewed before writing | features §1–2 | most sources never met a stranger's real export |
| Undo for every write, including whole imports | features §3, §17 | rehearse before filming |
| Private by default, no public surface at all | features §24, CLAUDE.md product rules | — |
| Free export and statistics, promised permanently | landing FAQ | — |
| Native Mac app | features §22 | in App Review |
| Ask Aaru with plans you approve | features §16–17 | experimental; never the headline |
| From here: where a title leads across kinds | features §13 | experimental |

### Reasons someone would choose Aaru

1. They follow more than one kind and are tired of four apps.
2. They want to leave a tracker without losing their history.
3. They want nothing they watch or read to be public.
4. They want a good Mac app.

### Alternatives

Trakt, Letterboxd, Goodreads, StoryGraph, MyAnimeList, AniList, TV Time, Simkl, Serializd, a
spreadsheet. MARKETING.md §3.5 has competitor notes from 2026-10-09; **re-verify every
competitor fact and price before quoting it**, and read each provider's terms before naming
them in a comparison (Trakt's API terms constrain use of its name; MARKETING.md §11.6). Where
Trakt wins (scrobbling ecosystem, community size), do not fight (MARKETING.md §3.4).

## 5. Marketing messaging

**Primary message:** Everything you watch, read and follow, in one private library.

**Supporting line:** Bring your history, leave whenever you like.

### Five benefit messages

1. **Bring your history.** "Import what you already keep elsewhere. Aaru shows you what it
   matched before anything is added."
2. **What's next, tonight.** "Up Next and the week of everything you follow, to the episode."
3. **All of it, in one library.** "Films, shows, anime, manga, books and albums, in five plain
   statuses."
4. **Private by default.** "A new account shows nothing to anyone. No public profile, no feed,
   no ads."
5. **Leave whenever you like.** "Export everything, any time, for free."

The assistant appears as a sixth, secondary line, never first: "Ask in your own words. Anything
larger than a tap is a plan you approve."

### Brand voice

Calm, private, nocturnal (PRODUCT.md). Short, plain, second person, quietly confident. No
exclamation marks, no hype, no "AI-powered", no gamer bravado. Aaru proposes, never pushes: "may
I", never "done". Full guidance in `rules/brand.md`.

## 6. Conversion

**Primary CTA today:** "Get started on the web" → `aaruapp.com` (the landing button's label).
**Secondary:** "Join us on Discord". After the App Store release: the store badge.

Beta testers for Apple come by hand (MARKETING.md §8, Phase B): a TestFlight invite to one
person at a time, from conversations, never a public TestFlight link in a post unless the owner
decides it.

### Suggested landing messaging

The live landing already carries the right story (hero, "All of it, in one library.", "Bring
your history with you.", "Made for iPhone, iPad, Mac and the web.", FAQ). Changes to propose to
the owner, not to make:

- Drop "Android to follow" and "Google Play" until an Android client exists.
- Change "Aaru is in private beta" in the FAQ once 1.0 is on the App Store.
- MARKETING.md §9 wanted the export promise above the fold and a 30-second import recording.

### Objections

| Objection | Answer (true today) |
|---|---|
| "Another tracker." | The one that takes your history from all the others and lets you leave with it |
| "Will the import wreck my data?" | Nothing writes until you approve the match table, and the import can be undone |
| "Is it public?" | No. There is no public profile or feed |
| "What will it cost?" | Free today; export, library and statistics will never sit behind a paywall |
| "Is my data sent to an AI?" | Only if you say yes to AI data sharing, asked once; unanswered counts as no |
| "Solo developer, will it last?" | Export is a CSV that imports back; you are never locked in |

## 7. Measurement

The only scoreboard metric is **strangers who used Aaru** (owner rule; see `demand-hour`
skill). Everything else is diagnostic. Measure only through what `docs/privacy.md` already
allows: server-side PostHog events, Grafana, the database. No client analytics SDK, no
tracking pixels, no UTM-joined user profiles.

| Metric | Definition | Source |
|---|---|---|
| Strangers | People who are not the owner, who signed up and did one real thing | DB, by hand |
| Activation | ≥1 source imported **and** ≥25 library items within 24 h (MARKETING.md §10) | DB |
| Import completion | Jobs finishing without a fatal error | DB / Grafana |
| Match rate | Rows matched on first pass | import jobs |
| D7 return | Opened 7 days later | server events |
| Plan acceptance / undo rate | Plan cards approved ÷ shown; agent writes undone ÷ made | journal |
| Export-then-churn | Watch, never fight (MARKETING.md §10) | DB |

Links in posts may carry a plain `?ref=<channel>` only if the owner agrees and `docs/privacy.md`
says so first.

## 8. What must be fixed before spending on promotion

1. **App Review outcome.** Until 1.0 is out, the Apple story is TestFlight by hand.
2. **The landing's Android line** (see §6).
3. **First real imports.** Most importers have never met a stranger's export (features §1). One
   bungled 2,000-film Letterboxd import outweighs a good launch post (MARKETING.md §11.2). Run
   the owner's own Trakt/Letterboxd/Goodreads exports end to end on production first.
4. **Provider terms.** TMDB's free tier is non-commercial; AniList's API is non-commercial
   without permission; MAL needs written authorisation before anyone but the owner connects
   (`docs/providers.md`). Marketing a free app is fine; any paid plan reopens all three.
5. **`privacy@aaruapp.com` routing** (PRV-001 note).
6. **Store copy approval.** `aaru-ios/fastlane/metadata/` is a draft the owner has not approved.
7. **Phase rule.** MARKETING.md §8: no public launch (Show HN, Product Hunt, press) before ten
   strangers have imported successfully. Phase B is now: recruit by hand.

## 9. Evidence and assumptions

### How this was checked

Read `MARKETING.md`, `BUSINESS.md`, `PRODUCT.md`, `CLAUDE.md`, `DESIGN.md` "Brand",
`BACKLOG.md`'s item table, `docs/providers.md`, `aaru-ios/fastlane/metadata/en-US/*`,
`aaru-ios/fastlane/screenshots/captions.json`, and the landing route
`aaru-client/src/routes/index.tsx`. No app was run.

### Verified

- Live web at `aaruapp.com`; production API `3252c467`.
- 1.0 submitted to App Review 2026-11-13, Free.
- Plus off sale; no price anywhere in the shipped landing.
- Landing copy and FAQ quoted above.

### Inferred, so confirm before relying on it

- Persona order still holds after manga, music and sports were added.
- That the strangers count is still 0 on 2026-11-14.

### Needs confirmation (decisions for the owner)

1. Market before the App Store release (web + TestFlight), or wait for it?
2. Lead audience for the first ten: Trakt leavers (MARKETING.md's #1) or anime/manga trackers?
3. Keep or remove "Android to follow" / "Google Play" on the landing.
4. Approve the App Store copy in `aaru-ios/fastlane/metadata/`.
5. May posts link a TestFlight public link, or invites only by hand?
6. Is `@fatc88` the brand's account, or the owner's personal one? (Decides who posts.)
7. Should MARKETING.md be retired in favour of this folder, or kept as the long-form plan?
