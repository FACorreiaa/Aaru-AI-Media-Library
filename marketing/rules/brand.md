# Aaru brand rules for marketing

These rules apply the product's brand (`DESIGN.md` "Brand", `PRODUCT.md`, `design/tokens.json`,
`docs/brand/README.md`) to marketing. Where they disagree, the product files win, and on a
conflict with `main` in a brand file, `main` wins (CLAUDE.md, "Brand"). Last checked 2026-11-14.

## Name and words

- **Aaru**: one word, capital A, lowercase "aru". Never "AARU", "Aaru app" in a headline, or
  "Aaru AI".
- **App Store listing:** "Aaru - Media Manager". Use it only when naming the store listing.
- **Origin:** the Egyptian Field of Reeds. Footer line: "A calm place where stories live."
- **Tagline:** "Your stories. Your world."
- **Domain words** (CLAUDE.md, "Domain language"): Title, Library, List, Shelf, Up Next, From
  here, On air, Watch party, Reading session, Ask Aaru, AI data sharing. Status labels per kind
  (`features.md`, "Labels per kind"). Never "watchlist" as the product's word, never
  "portfolio", never "Conversation" or "Message" for a chat with Aaru.

## Personality

**Calm, private, nocturnal** (PRODUCT.md). A constructed room for stories, lit at night.

- The voice is serene and exact. It proposes, never pushes. It speaks rarely and in full
  sentences.
- Menace is carried by form, darkness and restraint, never by red, threat in copy, glitches or
  alarms.
- Copy: short, plain, second person, quietly confident. **No exclamation marks, no "AI-powered",
  no hype, no gamer bravado, no emoji in headlines.**

Do / don't:

| Write | Not |
|---|---|
| Everything you watch, read and follow. | The ultimate AI-powered tracker! |
| Bring your history. Leave whenever you like. | Never lose your data again!!! |
| Ask in your own words. You approve anything larger than a tap. | Let AI manage your library |
| Private by default. No ads, no feed. | Your secure, encrypted media vault |

Anti-references (PRODUCT.md): a chat-bubble AI app, a generic poster-grid tracker, gamer RGB /
cyberpunk (neon, glitch, scanlines, HUD clutter).

## Colour

Only from `design/tokens.json`. No other hex, ever: CI's `brand-guard.sh` refuses colour
literals in the clients, and marketing follows the same rule. Values as read on 2026-11-14:

| Token | Dark (lead appearance) | Light | Use in marketing |
|---|---|---|---|
| `paper` | `#0e141e` night navy | `#f4f6fa` | Background |
| `surface` | `#161e2b` | `#e9edf3` | Cards, panels |
| `stone` | `#0a0f17` | `#dde3eb` | Deepest layer |
| `ink` | `#e7ebf1` silver-white | `#121a28` | Text |
| `muted` | `#9ba8b9` | `#4a5669` | Secondary text |
| `accent` | `#6aaeea` ice blue | `#2a62a6` | Actions, links, highlights |
| `on-accent` | `#0e141e` | `#f4f6fa` | Text on an accent fill (never white) |
| `gold` | `#e0904f` amber | `#a35f1c` | Edge light only: a hairline, a star, the owl's glow |
| `night` | `#16233a` | `#16233a` | The owl's disc, the same in both |
| `medallion` | `#2b3647` | `#c9d2de` | Silver disc under avatars and kind marks |
| `danger` | `#f2a08f` | `#a3372a` | Errors only; never for drama |

Rules: dark-first. Amber never fills a surface and never carries text. No pure black. By night,
hairlines are ice blue. Accessible pairs are in `tokens.json`; keep text at AA (4.5:1).

## Type

The system sans for everything: SF Pro on Apple renders, `system-ui` elsewhere
(`design/fonts.md`). Headings by weight and size. **No serif, no bundled or display faces.** The
wordmark is artwork, never typeset.

## Logo, mark and icons

Source files in `docs/brand/source/` (made by `docs/brand/owl_poster.py`, `owl_mascot.py`):

- `owl-poster.png`: the standard ("Aaru Owl: Your stories. Your world.").
- `wordmark.svg` / `.jpg`: the geometric "Aaru". Artwork only.
- `a-mark.svg`, `a-mark-small.svg`: the A with the amber star and swoosh.
- `app-icon.svg`, `app-icon.jpg`, `app-icon-small.svg`: the mark on night navy.
- Retired, never use: the teal bird, the reeds, the heron (`reed-lockup.jpg` is history).

Do not recolour, stretch, outline, add effects to, or animate the mark beyond the motion rules.
Leave clear space of at least the star's width around it.

## Mascot

The white and amber robot owl, always on the `night` disc. One owl, four poses
(`docs/brand/source/poses/`): **standing** (default), **curious** (nothing matched, searching),
**sleeping** (caught up, nothing airs), **celebrating** (a milestone). Never a new character,
pose, costume or expression, and never an AI-generated variant passed off as the owl.

- The owl is the face of marketing; it fronts the assistant, so it carries "Ask Aaru" without
  the word AI.
- It never appears on a plan card (an outside connection wrote it), and never with a
  speech-bubble chat UI around it.
- The 3D owl (BRD-011) is an experiment on the web sign-in, the landing hero and Welcome. Use 3D
  footage only after the owner's verdict.

## Motion

From `design/owl-motion.json` and DESIGN.md: two owl motions, never both at once: the
**breath** (Aaru is working) and **idle** (slow float, amber glow behind the eyes). Errors and
recap cards stay still. Transitions are calm cross-fades and short eases; no glitch, shake,
whip-pan or flash. Respect Reduce Motion in any interactive asset.

## Required credits

Any video or image that shows catalog data shows the credit (`docs/providers.md`). End cards and
descriptions carry the text line; posters on screen need it on the frame or the end card.

| Shown | Credit |
|---|---|
| Any film or show data or poster | TMDB logo + "This product uses the TMDB API but is not endorsed or certified by TMDB." Aaru's logo stays more prominent than TMDB's |
| Air times | "Air times from TVmaze" (CC BY-SA) |
| Where to stream | "Where to stream from JustWatch" |
| Anime or manga | "Anime data from AniList" |
| Books | "Book data from Open Library" |
| Albums | "Music data from MusicBrainz"; covers "from the Cover Art Archive"; Discover album rows "from ListenBrainz" |
| Relations | "Relations from Wikidata" |
| Sports | "Data: TheSportsDB" |
| Concerts | "Concerts from Ticketmaster" |
| Trakt import named | "Aaru uses Trakt but is not endorsed or certified by Trakt." |

The store description's closing paragraph is the model end-card credit.

## Third-party names and logos

- **Names** of import sources (Trakt, Letterboxd, IMDb, Goodreads, Netflix, TV Time, Stremio,
  MyAnimeList, AniList, Pogdesign CAT, Last.fm, ListenBrainz, Spotify, YouTube) may appear as
  plain text to say what Aaru imports from. That is nominative use. Never imply partnership or
  endorsement.
- **Logos** of those services: do not use in marketing unless the landing's `ImportSources`
  component already shows them and that use has been checked against each brand's guidelines.
  Check terms per brand; until checked, use names only.
- **Trakt:** its API terms constrain how the name is used in marketing (MARKETING.md §11.6).
  Read them before any comparison or "Trakt alternative" copy.
- **TMDB:** logo only as the required credit, smaller than Aaru's.
- **Posters and covers** belong to their owners. Show them only inside real app footage, never
  as standalone key art, a thumbnail's main image or an ad's hero.
- **Streaming services** (Netflix, Disney+, Prime Video): never show their player UI with the
  extension, since the extension is in no store.

## Standard disclaimer

For anything shown before the App Store release:

> Aaru is in beta. Features may change.

For any piece with an AI presenter (`rules/video-playbook.md`):

> Presenter is AI-generated. App footage is real.
