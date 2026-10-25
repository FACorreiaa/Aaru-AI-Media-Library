# Product

## Register

product

## Users

Cross-media power trackers. People who already keep their history somewhere (Trakt,
Letterboxd, MyAnimeList, AniList, Goodreads, TV Time, a Pogdesign CAT list) and juggle
several kinds at once: a few shows and anime airing this week, a film tonight, a book and a
manga in progress, albums on the side. They track to the episode and the chapter, they care
when an import drops a row, and they check in most evenings, on the phone on the sofa and
on the Mac or the web at a desk, usually in a dim room after the day is done.

The job on any given screen is one of: decide what to watch, read or listen to next; tick
what was just finished; bring an old history in without bad merges; look back at what they
have been through. The agent (in the app, or through Claude, MCP and App Intents) does the
larger moves, and the user approves them inside Aaru.

## Product Purpose

One private library for every story a person follows: films, shows, anime, manga, books and
albums, with what they plan to, what they are in the middle of, and what they finished.
Aaru is the source of truth after import. Private by default; social is opt-in and
friends-only.

Success is a stranger who signs up, pulls in the history they already have, tracks a series
to the episode, and comes back the next evening without being asked, because Aaru is the
calmest place to see where they are in everything.

## Brand Personality

**Calm, private, nocturnal.** A constructed room for stories, lit at night; the owl poster
(`docs/brand/source/owl-poster.png`, "Your stories. Your world.") is the standard.

Futuristic, after *Avengers: Age of Ultron*, held in tension:

- **Vision's calm intelligence** is the voice and the agent. Serene, exact, a little wise.
  It proposes, it never pushes; it says "may I", never "done". Amber light means it is
  thinking. It speaks rarely and in full sentences, never in hype.
- **Ultron's menace** is the undertone, never the voice. Machined precision, dark depth,
  scale, a sense that something intelligent is watching over the room: hard edges on the
  hologram, the city at night behind the glass, an owl that is a machine. It is carried by
  form, darkness and restraint, not by red, threat in copy, glitches or alarms. The
  uncanny is a texture, never an effect.

Tone of copy: short, plain, second person, quietly confident. No exclamation marks, no
"AI-powered", no gamer bravado.

## Anti-references

- **Chat-bubble AI app.** A ChatGPT stack, a support-bot feel, an "AI" tab bolted onto a
  tracker. Chat is how you speak; the views are what you look at.
- **Generic poster-grid tracker.** The five-tab Search / Movies / Shows / Books / Settings
  app, a Plex or Netflix clone wall of posters with no sense of where you are.
- **Gamer RGB / cyberpunk.** Neon magenta, glitch effects, scanlines, HUD clutter, broken-AI
  aesthetics. Futuristic here means Stark-calm, not arcade.

## Design Principles

1. **Where you are, not what exists.** Every surface answers "what is next for me" before
   "what is out there". Progress, next-up and airing time outrank catalog breadth.
2. **The agent asks, the user decides.** Anything larger than a tap becomes a plan the user
   approves inside Aaru, and every write is undoable. The interface makes that trust
   visible: plan cards, match tables, the undo ribbon.
3. **Calm power.** Dense where trackers need density (week grid, S·E codes, ticks), quiet
   everywhere else. Intelligence shows as restraint and precision, never as spectacle.
4. **Private is the default state.** Nothing visible to anyone until the user opts in, and
   the UI never blurs what the server can read (group messages) with what it cannot (DMs).
5. **One library, many kinds.** Films, shows, anime, manga, books and albums share one
   grammar of status, progress and lists; each kind keeps its own words and its own unit.

## Accessibility & Inclusion

WCAG 2.2 AA across web, iPhone, iPad, Mac and widgets. Token pairs are checked for AA in
`design/tokens.json` (4.5:1 text, 3:1 non-text) and CI fails below it. Reduce Motion makes
every transition instant and every entrance a cross-fade; the owl holds still. Dynamic Type
scales every heading; VoiceOver and the web's live regions read progress and undo. The
night texture disappears under increased contrast, forced colours and Reduce Transparency.
Colour never carries meaning alone (status, badges and spoiler guards have labels or
shapes).
