# Aaru video playbook

How to capture and produce Aaru videos. Product facts come from `../features.md`, positioning
from `../strategy.md`, visual rules from `brand.md`. Last checked 2026-11-14.

## Rules that never bend

1. **Real UI only** for anything the product does. Generated footage is for presenters,
   backgrounds and transitions, never for screens.
2. **Demo account only.** Film the App Review account seeded by `aaru --seed-review`
   (`aaru-server-v2/internal/reviewseed/`) or a fresh local account. **Never the owner's
   library**, never a real person's name, avatar, post, group message or friend list. The
   seed's friend ("Mira") is fictional and may be filmed.
3. **Nothing secret in frame:** sign-in codes, agent tokens, scrobble tokens, API keys, `.env`,
   App Store Connect, Grafana, email inboxes.
4. **No "AI" in the first frame or headline.** The owl opens; "Ask Aaru" names the assistant.
5. **Credits on every piece that shows catalog data** (`brand.md`, "Required credits").
6. **Only market what `features.md` lets you.** No Plus, no price, no Android, no extension
   install, no "on the App Store" before release.
7. **Two gates for paid generation:** plan first; spend credits only after explicit approval.
8. **Nothing is published** without the owner's explicit go.

## What's missing before a first shoot

- App Review outcome for 1.0 (decides the CTA and the end card).
- A demo account with a rich, realistic library: the review seed is small. Decide whether to
  extend the seed (a code change: owner's call) or build a local account by hand with imports.
- A demo Letterboxd CSV and a Trakt test account that are not the owner's (for import shots).
- A physical iPhone for widgets, Live Activity and push shots.
- Owner's answer on whether the 3D owl may appear (BRD-011).
- Music licence for background tracks.

## Capture environments

| Environment | How | Use for |
|---|---|---|
| Local web | `cd aaru-server-v2 && docker compose up -d && go run ./cmd/aaru --db-migrate && go run ./cmd/aaru`, then `cd aaru-client && npm run dev` | Most web shots. Needs `TMDB_API_KEY` and provider keys in the local env; the model off unless a key is set |
| Beta web | the `env.staging` Worker on the production API | Real catalog data. Blocked by Zscaler on the owner's Mac: capture from another network or machine |
| iOS Simulator | `xcodebuild` the "Aaru Beta" scheme, or the store harness below | iPhone and iPad screens |
| Store harness | `scripts/store-screenshots.sh "iPhone 17 Pro" "Aaru iPad 13"`, simulator booted and signed in to the demo account; status bar 9:41, full battery | Clean stills; same captions as `aaru-ios/fastlane/screenshots/captions.json` |
| Mac | the TestFlight Mac app, window 1440×900 pt, `screencapture -R` | Mac shots (2880×1800) |
| Physical iPhone | TestFlight build | Widgets, Live Activity, push alerts |

## Recording recipes

- **Web:** 1440×900 browser window (16:9) and 430×932 (9:16, mobile layout). Dark appearance.
  Hide bookmarks and extensions. Cursor moves slow and straight; pause 1 s on every result.
- **iOS:** `xcrun simctl io booted recordVideo --codec=h264 out.mov`; status bar override as the
  store harness does. Dark appearance unless a shot is about light mode.
- **Mac:** QuickTime screen recording of the window only.
- Record each flow three times; keep the cleanest.

## Clear these before every recording

- Signed in to the demo account, not the owner's.
- Notifications off (Focus on); no other apps' banners.
- Browser: no other tabs, no autofill, no extensions bar, devtools closed.
- No email address on screen (Settings → Account shows it: avoid or blur).
- Discover, On air and trending rows change daily: check the posters are not adult, violent or
  off-brand before rolling.
- Time and date plausible (9:41 on device).

## Shot bank

Shot IDs are stable; reference them from scripts. Status from `features.md`.

| ID | Shot | Platform | Feature | Status | Notes |
|---|---|---|---|---|---|
| A1 | Landing hero: "Everything you watch, read and follow." | Web | — | verified | 3D owl only after the owner's verdict |
| A2 | Home with Up Next and the owl beside "The Field" | All | §7 | verified | |
| A3 | One search returning a film, a book and an anime of one name | All | §5 | verified | |
| A4 | Add a title, set status, the label changes per kind | All | §5, §9 | verified | |
| A5 | Tick three episodes on a show page | All | §6 | verified | |
| A6 | The week grid | All | §8 | verified | |
| A7 | Library tabs with counts, On hold | All | §9 | experimental | |
| B1 | Settings → Import, drop a Letterboxd CSV | All | §1 | verified | demo CSV, not the owner's |
| B2 | Match table: fix one row, approve | All | §2 | verified | |
| B3 | Undo the import, library empties | All | §3 | verified | rehearse first |
| B4 | Paste a list from notes as a capture | All | §4 | experimental | needs AI data sharing on and a model key |
| C1 | From here: a film to its book and its director | All | §13 | experimental | |
| C2 | Discover → On air by channel | All | §15 | experimental | check the row content |
| D1 | Open the owl's card, ask "what's next tonight" | All | §16 | experimental | no "AI" text overlay |
| D2 | "Mark season three watched" → plan card → approve → undo | All | §17 | experimental | the trust shot |
| E1 | Group with `#general` and a Watch party countdown, with Mira | All | §19 | experimental | seed friend only |
| F1 | Insights / Recap story | All | §12 | verified | |
| G1 | Settings → export, Settings → delete (do not confirm) | All | §25 | verified | |
| G2 | Mac app, wide window, library | Mac | §22 | verified | |
| G3 | Home Screen widget and Live Activity | iPhone | §11 | experimental | physical device |

## Formats

### 1. Full application showcase (45–60 s)

16:9 primary, 9:16 alternate. Hook (0–5 s): A1 or "Four apps for what you watch and read?";
history (5–18 s): B1, B2; what's next (18–32 s): A2, A5, A6; all kinds (32–40 s): A3; ask (40–48 s):
D2; trust (48–55 s): G1 + "Private by default."; end card (55–60 s): wordmark, tagline, CTA,
credits.

### 2. AI presenter / UGC advertisement (30–45 s)

9:16. The presenter is AI-generated and labelled (`brand.md`, disclaimer). Never a "real user"
or "I switched from Trakt" testimonial. Story: problem (four apps) → B1/B2 → A2/A5 → "and it's
private" → CTA. Picture-in-picture over real UI; full-screen UI where controls matter.

### 3. Individual feature demos (15–30 s)

Lead order: Bring your history (B1–B3), What's next (A2, A5, A6), Six kinds (A3, A4), Private and
export (G1), Ask with a plan (D1, D2), From here (C1).

### 4. Short teaser (10–15 s)

9:16. "Everything you watch, read and follow." → A3, A5, B2 in 2 s cuts → owl + "Your stories.
Your world." → CTA.

## Using Higgsfield

The Higgsfield MCP is connected in this environment. Use it for: presenter clips, the night
room backgrounds (navy, ice-blue light, amber edge), slow transitions. Never to generate app
screens, posters, the owl in a new pose, or the logo. Check the actual tools and credit costs
with the MCP before planning; show the estimate and stop for approval before any generation.

## Asset manifest

`../assets/manifest.md` records every capture and export: path, type, platform, resolution,
orientation, shot ID, feature, date, app commit / build, capture method, review status. Large
files stay out of Git (keep them in `marketing/assets/raw/`, which is ignored, or external
storage).

## Quality control

Before a video is called done, `prompts/09-review-video-quality.md` runs and every item passes:
no unmarketable feature, demo data only, credits present, no "AI" in the first frame, tokens-only
colours, system sans, captions synced, CTA true for today's availability.
