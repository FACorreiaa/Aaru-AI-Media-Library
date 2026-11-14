# First videos: production plan

Owner decisions 2026-11-14: three videos, real UI from a demo account, captions and music (no
voice), App Store CTA (1.0 live 2026-11-14), Higgsfield for the cinematic layer and music.
Rules: `../prompts/00-video-production-rules.md`, `../rules/video-playbook.md`, `../rules/brand.md`.

| # | Video | Length | Ratio | Message | Folder |
|---|---|---|---|---|---|
| V1 | Teaser | 12 s | 9:16 | Everything you watch, read and follow. | `01-teaser/` |
| V2 | Showcase | 55 s | 16:9, re-edited 9:16 | One private library; bring your history; what's next | `02-showcase/` |
| V3 | Bring your history | 25 s | 9:16 | Import, see the matches, undo it all | `03-bring-your-history/` |

## Footage

All product footage is real UI from the review seed account (`aaru --seed-review`: 15 items over
every kind, friend Mira, "Film club" group) on a **local** API and Postgres, plus the fictional
`../assets/demo-data/letterboxd-demo.csv` imported on camera. Never the owner's library.

| Source | Shots |
|---|---|
| iOS Simulator (iPhone 17, dark, 9:41) | A2, A3, A5, B1, B2, B3 for the 9:16 cuts |
| Local web, Chrome 1440×900 dark | A1 (landing), A2, A6, A3, B1, B2, D2, G1 for V2 16:9 |

The same flow is recorded on both so V1/V3 (vertical) and V2 (wide) cut from native frames, not crops.

## Generated (Higgsfield), shared by all three

| ID | Asset | Model | Used in |
|---|---|---|---|
| H1 | Night library room: navy dark, ice-blue window light, a thin amber edge on a shelf; shelves of books, film reels, records; slow push-in; no people, no text, no logos. 5 s | Seedance 2.5 t2v, 1080p, no audio; 9:16 and 16:9 | V1 open, V2 hook, V3 close |
| H2 | Same room, slow lateral drift past spines and reels, soft defocus. 5 s | Seedance 2.5 t2v, 16:9 | V2 transitions |
| H3 | Empty dark stage: matte plinth, ice-blue rim light, faint haze, locked camera, for compositing a device frame with real recordings. 8 s | Seedance 2.5 t2v, 16:9 + 9:16 | V2, V3 device scenes |
| M1 | Calm nocturnal music bed: soft piano and warm pads, slow pulse, no vocals, 60 s, with a clean 12 s and 25 s edit point | Higgsfield audio | all |

Drafts first (480p) where the model allows, finals only for the picked take. Never: app screens,
posters, the owl, the logo or text. The owl appears only from `docs/brand/source/` PNGs.

Quotes are fetched per job and shown to the owner before anything is generated (gate B).

## Assembly

Local ffmpeg (`../capture/assemble.sh`): recordings scaled into a device frame over H3 or full
frame, captions rendered in the system sans from `design/tokens.json` colours (`ink` on `paper`,
`accent` for one word at most), cross-fades of 300–500 ms only, end card:
wordmark + "Your stories. Your world." + official "Download on the App Store" badge (from Apple's
marketing tools, unaltered) + "or aaruapp.com" + credits line.

End-card credits (all three; posters from TMDB, anime from AniList, books from Open Library are on
screen): TMDB logo (smaller than Aaru's) and "This product uses the TMDB API but is not endorsed or
certified by TMDB." · "Anime data from AniList" · "Book data from Open Library" · "Music data from
MusicBrainz" if an album cover is visible.

## Order of work (cheapest first)

1. Local stack + seed + Letterboxd demo import rehearsed. **Blocked: needs `TMDB_API_KEY`.**
2. Record iOS and web flows (3 takes each), log in `../assets/manifest.md`.
3. Rough cut of all three with placeholders for H1–H3 and M1 (free): proves timing.
4. Owner approves rough cuts and the credit quote → generate H1–H3, M1.
5. Final cuts, QA (`../prompts/09-review-video-quality.md`), owner review. Nothing is posted.

## Credit quote (Higgsfield `get_cost`, 2026-11-14; balance 1,202.8)

Seedance 2.5, no audio. Draft = 480p preview, finalised from the picked draft.

| Asset | Drafts | Finals (1080p) |
|---|---|---|
| H1 room, 5 s, 16:9 + 9:16 | 2 × 15 = 30 | 2 × 80 = 160 |
| H2 drift, 5 s, 16:9 | 15 | 80 |
| H3 stage, 8 s, 16:9 + 9:16 | 2 × 24 = 48 | 2 × 128 = 256 |
| M1 music, 60 s, ElevenLabs Music v2.5 instrumental, 2 variations | — | 17.44 |
| **Total, one draft round** | **93** | **513.44** → **≈ 606** |

A second draft round adds ≈ 93. Cheaper option: H3 as a still (one generated image) with a slow
ffmpeg push instead of video, saving ≈ 250.
