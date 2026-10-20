# Providers (PRV-001)

Every outside service `aaru-server` or a client talks to: what it is for, whether it needs a
key, where that key lives, its rate limit, its terms, and the credit Aaru must show. Update this
file in the same PR that adds or changes a provider. The About screen (Apple) and `/about` (web)
render the **Credit** column; `/privacy` names every row that receives user data.

## Catalog (receive search text and catalog ids, never who is asking)

| Provider | Used for | Key | Secret | Rate limit (ours) | Terms | Credit Aaru shows |
| --- | --- | --- | --- | --- | --- | --- |
| TMDB | Movies and shows: search, details, posters, backdrops, episodes, networks | v3 key | `TMDB_API_KEY` in `aaru-env` (horus) | 40/s | TMDB API terms: non-commercial on the free tier; logo + notice required, our logo must stay more prominent | TMDB logo and "This product uses the TMDB API but is not endorsed or certified by TMDB." |
| TVmaze | Exact air times and networks for TMDB shows (CAT-011) | none | — | 1.8/s (~20 per 10 s per IP) | Data CC BY-SA 4.0; free API, attribution required | "Air times from TVmaze" linking to tvmaze.com, CC BY-SA |
| AniList | Anime: search, details, banners, exact airing times, episode names from its streaming links | none | — | 1.5/s (90/min) | AniList API terms (non-commercial without permission) | "Anime data from AniList" linking to anilist.co |
| Fribb/anime-lists | AniList → TMDB/TVDB/MAL/AniDB id mappings, so mapped anime use TMDB's episodes (CAT-010). A file loaded by `aaru --anime-mappings`, monthly; no API calls at request time | none | — | one download per load | MIT | "Anime id mappings from Fribb/anime-lists" linking to github.com/Fribb/anime-lists, MIT |
| Open Library | Books: search, details, covers | none | — | 3/s, contact User-Agent | Internet Archive terms; covers rate-limited | "Book data from Open Library" linking to openlibrary.org |

Commercial use of TMDB and AniList on these keys is **not** allowed: any paid plan in
`BUSINESS.md` needs a TMDB commercial agreement and AniList's permission first.

## Account, sign-in and delivery (receive user data)

| Provider | Used for | Key | Secret | Data it receives |
| --- | --- | --- | --- | --- |
| Apple | Sign in with Apple; push notifications (APNs) | Team key (APNs) | `APNS_PRIVATE_KEY` in `aaru-env`, `APNS_KEY_ID` env | Apple ID sign-in token; device push token + notification text |
| Google | Sign in with Google | none (public client ids) | `GOOGLE_CLIENT_IDS` env | Google sign-in token |
| Resend | Sign-in emails (code + link) | API key | `RESEND_API_KEY` in `aaru-env` | Email address and the sign-in email |
| Trakt (optional, per user) | Importing a user's Trakt history (IMP-002/003) | OAuth client | `TRAKT_*` (not configured yet) | The user's Trakt authorisation; tokens stored encrypted |

## Hosting

| Provider | Used for | Data |
| --- | --- | --- |
| Hetzner (Falkenstein, Germany) | The API server and its PostgreSQL database; encrypted daily backups on a Hetzner Storage Box | Everything in the account and library |
| Cloudflare | DNS, the web app (Workers), TLS for aaruapp.com | Requests to the web app (IP address, the session cookie in transit) |
| GitHub | Source code, CI, container images | No user data |

## Not used

No analytics, advertising, attribution or crash-reporting SDKs in any client. The web app has
a `VITE_SENTRY_DSN` hook but no DSN is set and no Sentry code ships.
