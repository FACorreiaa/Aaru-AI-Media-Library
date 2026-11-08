# Aaru brand rules for marketing

Sources of truth: `DESIGN.md` ("Brand", "Mindspace", "Assistant"), `PRODUCT.md` ("Brand Personality", "Anti-references"), `design/tokens.json`, `design/fonts.md`, `docs/brand/README.md`, and `docs/providers.md` for credits. If this file disagrees with them, they win. Checked on 2026-11-06 against `origin/main` 1cf2ea5e. All paths start from the workspace root, `~/Work/production/apps/aaru/`.

The current brand is the **owl poster**, adopted by the owner on 2026-10-22 (`BACKLOG.md`, decisions of that date). It replaced the teal bird, the reeds and the heron. The owner approved the app icon on 2026-10-22 and the owl poses on 2026-10-23. Several "owner checks" in `BACKLOG.md` (BRD-001, BRD-003, BRD-004, BRD-008) were still open, so treat visual choices as approved for use but open to change. **Agents draft, the owner keeps the verdict.**

## Enforced in the repo: the "Brand check"

`.github/workflows/ci-brand.yml` is a **required status check** on `main` (it runs on every PR for that reason). It runs two steps:

1. `node scripts/generate-tokens.mjs --check`: the generated colour files for web, Apple, the extension and the PWA manifest must match `design/tokens.json`, and every listed colour pair must pass WCAG AA (4.5:1 text, 3:1 non-text).
2. `scripts/brand-guard.sh`, which fails on:
   - a hex or `rgb()` colour written outside the generated token files, in `aaru-client/src`, `aaru-client/public` or `aaru-extension/src` (only `#000` / `rgb(0,0,0)` for masks and shadows is allowed);
   - `Color(red:…)`, `Color(hex…)` or a named system colour (`.white`, `.blue`, …) in Swift;
   - a serif design, `.custom("…")` font, `ui-serif`, Newsreader, Georgia or any `@font-face` in any client;
   - the retired marks by name: `heron`, `reed mark`.

**What this means for marketing:** the guard covers app code, not videos. But anything you add to the repo's clients (a landing section, an OG image change) must pass it, and anything outside the repo should follow the same rules so that video and product look the same: colours only from the table below, the system sans, the owl and the A-mark only.

## Name and words

- **Aaru** is the only public name. It comes from the Egyptian Field of Reeds, "a calm place where stories live" (landing footer). Write "Aaru", never "AARU" or "aaru" in prose.
- **Website:** https://aaruapp.com. The beta web app is https://beta.aaruapp.com.
- **Tagline (brand):** "Your stories. Your world." (from the poster, `DESIGN.md` "Brand").
- **Live landing lines** (aaruapp.com, fetched 2026-11-06): page title "One private library for everything you follow"; hero "Everything you watch, read and follow. One calm library."; footer "A calm place where stories live."
- **Paid tier name:** "Aaru Plus". It is not on sale (see `../strategy.md`, section 6). Don't name it in ads.
- **Product words to use exactly** (`CLAUDE.md`, "Domain language"):
  - Status labels per kind: films, shows and anime read Plan to watch / Watching / Watched / Dropped; books and manga read Plan to read / Reading / Read / Dropped; albums read Plan to listen / Listening / Listened / Dropped; On hold for every kind.
  - "List" is a collection you curate. "Shelf" is a saved filter. A group's shared list is also called "List" in the UI.
  - "Watch party" (never "room" in copy). "Chat" is a one-to-one thread with Aaru. Never call a group post a "message", and never call anything "end-to-end encrypted": encrypted DMs are not built.
  - The home screen heading is "The Field".
- **Never:** "AI-powered" in a headline, the app name or the first frame (`MARKETING.md` §12); "the Letterboxd killer"; "social network"; "portfolio"; "watchlist app"; "chat with your library". Say what Aaru does, never that it is AI (`MARKETING.md` §2). Don't use a vendor name (Trakt, Letterboxd…) as if it were Aaru's own feature name; vendor names appear only as import sources.

## Personality

**Calm, private, nocturnal.** "A constructed room for stories, lit at night" (`PRODUCT.md`).

- **The voice** is "Vision's calm intelligence": serene, exact, a little wise. It proposes and never pushes. It says "may I", never "done". It speaks rarely and in full sentences.
- **The undertone** is "Ultron's menace", carried only by form, darkness and restraint: machined precision, dark depth, a city at night behind glass, an owl that is a machine. Never by red, threats in copy, glitches or alarms.
- **Copy:** short, plain, second person, quietly confident. **No exclamation marks.** No gamer bravado.

**Never** (`PRODUCT.md` "Anti-references", `DESIGN.md` "Do not"):

- A chat-bubble AI app: a ChatGPT stack, a support-bot feel, an "AI" tab bolted on. Chat is how you speak; the views are what you look at.
- A generic poster-grid tracker or a Netflix-style wall of posters "with no sense of where you are".
- Gamer RGB or cyberpunk: neon magenta, glitch effects, scanlines, HUD clutter, broken-AI looks.
- Glass, gradient fills, gradient text, pure black.
- A notification or line that says an agent "did" something. "The buzz is a question, never a receipt."

**Design principles** (`PRODUCT.md`): where you are, not what exists; the agent asks, the user decides; calm power; private is the default state; one library, many kinds.

## Colour

One source: `design/tokens.json`. **Dark is the art's home** ("dark-first in the art"), and both clients follow the system unless the Appearance setting pins one. **Film dark first.**

| Token | Dark | Light | Role |
|---|---|---|---|
| `paper` | `#0e141e` | `#f4f6fa` | Page background. The poster's night navy. Never pure black |
| `surface` | `#161e2b` | `#e9edf3` | Raised: cards, panels, the active nav pill |
| `stone` | `#0a0f17` | `#dde3eb` | Sunken: wells, inset fields, empty art |
| `ink` | `#e7ebf1` | `#121a28` | Text and strong strokes |
| `muted` | `#9ba8b9` | `#4a5669` | Secondary text and metadata |
| `accent` | `#6aaeea` | `#2a62a6` | **Ice blue**, the hologram's colour: primary actions, links, selection, focus |
| `on-accent` | `#0e141e` | `#f4f6fa` | Text on an accent fill. Never white (2.4:1 on the dark accent) |
| `gold` | `#e0904f` | `#a35f1c` | **The one amber**: edge light only. Hairlines, the next-up ring, stars, the active-nav bar, the owl's glow while Aaru works |
| `night` | `#16233a` | `#16233a` | The disc behind the owl, the same in both appearances |
| `medallion` | `#2b3647` | `#c9d2de` | The silver disc under avatars, kind marks and badges |
| `danger` | `#f2a08f` | `#a3372a` | Errors and destructive actions |
| `on-scrim` | `#e7ebf1` | `#f4f6fa` | Text on a scrim |
| `line`, `line-strong` | accent at 16% / 30% | ink at 12% / 22% | Hairlines. By night they are ice blue |
| `scrim` | paper at 85% | ink at 65% | Navy veil over artwork and behind floating layers |

**Rules for video:**

- **Gold never fills a surface and never carries text.** It is edge light: a thin line, a ring, a star, a glow. One gold edge per frame is a good rule of thumb.
- Text on an ice-blue fill uses `on-accent` (navy), never white.
- Elevation is flat: tint and hairlines, no drop shadows on cards. Gradients only as a radial glow or a scrim.
- **Off-brand, do not use:** teal or deep-teal backgrounds, the "teal to gold" palette, beige or paper-cream backgrounds, red as a mood colour, neon. These belong to the retired brands (below).

## Type

- **The system sans everywhere**: SF Pro on Apple, `system-ui` on the web and in the extension (`design/fonts.md`). Aaru bundles no fonts. Headings are set apart by weight and size, not by face.
- Small uppercase eyebrows over sections (tracked; 12 px, weight 600, 0.12 em on the web). Dates, S·E codes, counts and ratings use tabular figures.
- **The wordmark is artwork**, the poster's geometric "Aaru" (`docs/brand/source/wordmark.svg`). Never retype "Aaru" in a font to imitate it.
- **No serif.** Newsreader was the display face from 2026-10-21 to 2026-10-22 and is retired.
- **To be confirmed:** the face for video titles and captions made outside the app. SF Pro's licence is written for Apple-platform UI, so the owner should confirm whether it may be used in ad graphics, or name a substitute. Until then, keep in-video text to what the app itself renders, plus the wordmark artwork.

## Logo, icon and mascot

Masters are in `docs/brand/source/`, made from the poster by `docs/brand/owl_poster.py`, `owl_mascot.py`, `owl_poses.py` and `owl_icon_appearances.py`. Rasters are written to `docs/brand/out/owl/`, which is not committed: the shipped copies below are the ready-to-use files.

| Asset | Master | Shipped copies |
|---|---|---|
| The poster ("Aaru Owl: Your stories. Your world.") | `docs/brand/source/owl-poster.png` (1536×1024) | `aaru-client/public/og.jpg` (1200×630 crop) |
| A-mark (the A, its swooshes and the amber star) | `source/a-mark.svg`; `source/a-mark-small.svg` for 40 px and below | Inside the app icons |
| App icon (A-mark on night navy with the hologram's blue glow) | `source/app-icon.svg`, `source/app-icon-small.svg` | `aaru-ios/Aaru/Assets.xcassets/AppIcon.appiconset/` (light, dark, tinted, Mac sizes); `aaru-client/src/assets/brand/app-icon.webp`; `aaru-client/public/{favicon.ico,favicon.png,apple-touch-icon.png,icon-192.png,icon-512.png}`; `aaru-extension/public/icon/{16,32,48,96,128}.png` |
| Wordmark | `source/wordmark.svg` (`fill="currentColor"`) | `aaru-client/src/assets/brand/wordmark.svg`; Apple `Wordmark` image set |
| The owl, standing | `source/owl-2048.png` (transparent; an upscale, see limits) | `aaru-client/src/assets/brand/mascot.webp`, `mascot@2x.webp`; Apple `Mascot` |
| Owl poses | `source/poses/{curious,sleeping,celebrating}.png` | `aaru-client/src/assets/brand/owl-{curious,sleeping,celebrating}{,@2x}.webp`; Apple `OwlCurious`, `OwlSleeping`, `OwlCelebrating` |
| The owl's head (the agent's mark, the assistant button) | cut from `owl-2048.png` | `aaru-client/src/assets/brand/owl-mark.webp` (128 px); Apple `OwlMark` |

**Do not use in marketing:** `AppIconBeta` (it carries a navy "BETA" band), and any capture showing the "Aaru Dev" or "Aaru Beta" names.

**Logo rules** (from the brand docs; no formal clear-space or minimum-size spec exists, so these are **to be confirmed** beyond what is quoted):

- Use the masters as they are. Don't recolour, stretch, rotate or add effects. The wordmark takes one colour, the text colour of where it sits.
- Put the app icon and mark on night navy (`paper` dark or `night`), as the app does.
- **Size limits:** the poster is 1536×1024, so the traced marks are "smoothed reconstructions, not the artist's vectors", and the owl "tops out at about 600 px tall"; `owl-2048.png` is a 4× AI upscale of that crop (`docs/brand/README.md`). Keep the owl small on screen (well under full-frame height in 1080p), and ask the owner for real masters before any large-format or print use.

**Mascot and pose rules** (`DESIGN.md` "Brand", owner 2026-10-23):

- The mascot is a white and amber robot owl. It **always sits on the `night` disc** (`#16233a`), in both appearances, so the white owl reads.
- **One owl, four poses. Never a new character, and no pose invented.** Standing is the default. **Curious** when nothing matches (search, 404). **Sleeping** when nothing airs or you are caught up. **Celebrating** for a milestone (a badge reveal, the unlock summary).
- The three poses were generated from the owl master with FLUX.1 Kontext [dev] and approved by the owner on 2026-10-23. **Any new pose, angle or animation of the owl needs the owner's approval before use**, generated by Higgsfield or anything else.
- **Two motions, never both at once.** The *breath* means Aaru is working. *Idle* (a slow float and an amber glow behind the eyes) is the owl at rest, on Home and empty states only. Errors and recap cards stay still. Under Reduce Motion the owl never moves.
- **Never on a plan card.** A plan may come from an outside agent ("Claude asks"); an owl there would say Aaru wrote it.
- **Not a presenter.** Don't give the owl lines, a voice or a personality beyond the owl head that opens the real assistant. What "Aaru" says on screen must be a real assistant reply. Whether the owl may ever speak in an ad is an owner decision (**to be confirmed**).

**The poster itself is brand art, not product UI.** It shows four kinds (Movies, TV Shows, Anime, Books) where the product now has six, a hologram labelled "Track / Save / Share / Connect", and anime-style character art. **To be confirmed by the owner:** who made the poster and with what tool, and whether its imagery (including the character art) is cleared for paid ads. Until then use it only in organic posts, as the owner already does for the OG image, and never present its hologram as the app.

## Retired and legacy assets (do not use)

| Asset | Where it still sits | Why retired |
|---|---|---|
| Teal painted bird mascot | `docs/brand/source/mascot.jpg`, `mascot-2048.png` | Replaced by the owl, 2026-10-22 |
| Teal-bird app icon set | `docs/brand/out/icon/AppIcon*.appiconset/`, `out/icon/web/` | Same; made by `install_icon.py` |
| Reeds and half-sun icon, reed lockup | `docs/brand/out/reeds/`, `source/reed-lockup.jpg`, `icon_reeds.py` | Retired 2026-10-21/22; the guard bans "reed mark" |
| Heron | (none shipped) | Retired; the guard bans "heron" |
| Old wordmark and leaf icon | `source/wordmark.jpg`, `source/app-icon.jpg` | Three different "Aaru" letterforms existed; the traced poster wordmark replaces them |
| Newsreader serif, beige paper palette | file history only | Replaced by the system sans and the owl palette, 2026-10-22 |
| Audit screenshots | `docs/audit/apple-shots/*.jpg` (2026-10-21) | Old brand: serif headings, beige palette, an old tab bar |

## Motion

From `design/tokens.json` and `DESIGN.md` "Mindspace":

| Kind | Duration |
|---|---|
| Fast | 150 ms |
| Base | 240 ms |
| Slow | 420 ms |
| Landing hero "rise" | 700 ms, the one longer entrance |
| Easing | one curve, `cubic-bezier(0.2, 0.7, 0.2, 1)` |
| Owl | slow breath while working; slow float and amber glow at rest |

The signed-in app has no page-load choreography, and its texture (faint pinstripes, grain, a daypart wash, gold top edges) appears only on the Field and the Title room, and is static. Keep edits unhurried: holds and slow pushes, not fast cuts. **Record with Reduce Motion off**, and with increased contrast and Reduce Transparency off, or the texture and owl motion disappear.

## Required credits

`docs/providers.md` is the source; `aaru-client/src/lib/credits.ts` holds the exact strings the app shows.

| Source | What footage shows | What to do |
|---|---|---|
| **TMDB** (film and TV data and artwork) | Almost every poster and backdrop | Show the notice word for word: "This product uses the TMDB API but is not endorsed or certified by TMDB." Logo asset: `aaru-client/src/assets/brand/tmdb-blue-short.svg`, used under TMDB's own logo rules |
| **Trakt** | The Trakt import | "Aaru uses Trakt but is not endorsed or certified by Trakt." |
| **JustWatch** (through TMDB) | Where-to-stream logos on On air | "Where to stream from JustWatch" |
| **TVmaze** | Exact air times on On air | "Air times from TVmaze", CC BY-SA 4.0 |
| AniList, Open Library, MusicBrainz (CC0), ListenBrainz, Cover Art Archive, Ticketmaster, TheSportsDB, Open-Meteo, Fribb/anime-lists (MIT) | Anime, books, music, concerts, sports | Credit any that appear, as in `credits.ts` |
| Streaming services, studios, labels, publishers | Poster art, covers, service logos, extension shots on Netflix etc. | **To be confirmed.** Catalog artwork belongs to its owners. Whether it may appear in **paid** ads needs the owner's view (and possibly TMDB's terms on commercial use). For organic posts, prefer public-domain or openly licensed titles where a title is the focus |

## Standard disclaimer

Aaru has **no terms of service page** (`/about` and `/privacy` only), and no "AI can be wrong" line in its legal pages. Use these, adapted to what the video shows:

> This product uses the TMDB API but is not endorsed or certified by TMDB.

For any video showing the assistant, capture or `@aaru`, **to be confirmed** by the owner: a short line such as "Aaru suggests; you approve every change." It matches the product's behaviour (`DESIGN.md` §11–12) but is not yet in any Aaru text. Label an AI presenter as AI-generated wherever a platform requires it.
