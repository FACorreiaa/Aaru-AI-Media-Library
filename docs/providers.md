# Providers (PRV-001)

Every outside service `aaru-server` or a client talks to: what it is for, whether it needs a
key, where that key lives, its rate limit, its terms, and the credit Aaru must show. Update this
file in the same PR that adds or changes a provider. The About screen (Apple) and `/about` (web)
render the **Credit** column; `/privacy` names every row that receives user data.

## Catalog (receive search text and catalog ids, never who is asking)

| Provider | Used for | Key | Secret | Rate limit (ours) | Terms | Credit Aaru shows |
| --- | --- | --- | --- | --- | --- | --- |
| TMDB | Movies and shows: search (incl. `search/multi` for All), details, posters, backdrops, episodes, networks; Discover rows (trending, on the air, new shows, now playing) | v3 key | `TMDB_API_KEY` in `aaru-env` (horus) | 40/s | TMDB API terms: non-commercial on the free tier; logo + notice required, our logo must stay more prominent | TMDB logo and "This product uses the TMDB API but is not endorsed or certified by TMDB." |
| TVmaze | Exact air times and networks for TMDB shows (CAT-011) | none | — | 1.8/s (~20 per 10 s per IP) | Data CC BY-SA 4.0; free API, attribution required | "Air times from TVmaze" linking to tvmaze.com, CC BY-SA |
| AniList | Anime: search, details, banners, exact airing times, episode names from its streaming links; Discover rows (this season, trending) | none | — | 1.5/s (90/min) | AniList API terms (non-commercial without permission) | "Anime data from AniList" linking to anilist.co |
| Fribb/anime-lists | AniList → TMDB/TVDB/MAL/AniDB id mappings, so mapped anime use TMDB's episodes (CAT-010). A file loaded by `aaru --anime-mappings`, monthly; no API calls at request time | none | — | one download per load | MIT | "Anime id mappings from Fribb/anime-lists" linking to github.com/Fribb/anime-lists, MIT |
| Cinemeta (Stremio) | A show's episode list, to read Stremio's watched-episode field during a Stremio history import (IMP-016) | none | — | 5/s, User-Agent | Stremio's public addon; no published terms | none |
| Open Library | Books: search, details, covers; Discover's weekly trending books | none | — | 3/s, contact User-Agent | Internet Archive terms; covers rate-limited | "Book data from Open Library" linking to openlibrary.org |
| MusicBrainz | Albums and EPs (release groups): search, details, artist credit, genres, tracklists (MUS-001) | none | — | 1/s, contact User-Agent (MusicBrainz's limit) | Core data CC0; API free, clients must identify themselves | "Music data from MusicBrainz" linking to musicbrainz.org |
| ListenBrainz | Discover's New albums and Coming soon (MUS-002): fresh releases plus this month's sitewide release-group and artist stats | none | — | 1/s, contact User-Agent; 4 calls per 6 h | Data CC0; public API | "Album rows from ListenBrainz" linking to listenbrainz.org |
| Cover Art Archive | Album covers, by release-group id, referenced and never hosted (MUS-001) | none | — | none ours (clients load images directly) | Images belong to their owners; served by the Internet Archive | "Covers from the Cover Art Archive" linking to coverartarchive.org |

Commercial use of TMDB and AniList on these keys is **not** allowed: any paid plan in
`BUSINESS.md` needs a TMDB commercial agreement and AniList's permission first.

Discover rows (DISC-001, 2026-10-20) call TMDB, AniList and Open Library through one in-memory
server cache: 6 h TTL, one fetch per list however many users ask, the stale copy served (and a
5 min back-off) when a refresh fails, and no user data in the request or the cache; the
caller's `libraryItemId` marks are applied after the cache, from Aaru's own database. All
search (CAT-019) sends every query to AniList as well as TMDB, so AniList answers on a short
deadline and a miss leaves `incomplete: true`. The Discover screen (APP-012) repeats the TMDB
notice and the AniList and Open Library credits in its footer, besides About.

## Concerts (MUS-003; receive a place, never who is asking)

| Provider | Used for | Key | Secret | Rate limit (ours) | Terms | Credit Aaru shows |
| --- | --- | --- | --- | --- | --- | --- |
| Ticketmaster Discovery API | Music events near a point and by performer; performers by name with their MusicBrainz links | free key | `TICKETMASTER_API_KEY` in `aaru-env` | 4/s; stops at 4,500 calls a UTC day (limit 5,000) | Cache only for short periods (6 h), link to Ticketmaster for tickets, no resale of the data, disclose in the privacy policy | "Concerts from Ticketmaster" under the list and in About |
| Open-Meteo geocoding | The "Concerts near" city picker: a typed city name to a point | none | — | 2/s | Free for non-commercial use; revisit before any paid plan | "City search by Open-Meteo" in About |

Ticketmaster receives a 5-character geohash cell (about 5 km across) and a radius, never the
rounded position itself and never a user id. One-off positions ("Use my location") are rounded
to two decimals on the device, sent in a POST body, used once and never stored or logged. The
saved city is stored rounded and deleted with the account. Open-Meteo receives only the text
typed into the city search; that route's query is dropped from Aaru's request log.

## Account, sign-in and delivery (receive user data)

| Provider | Used for | Key | Secret | Data it receives |
| --- | --- | --- | --- | --- |
| Apple | Sign in with Apple; push notifications (APNs) | Team key (APNs) | `APNS_PRIVATE_KEY` in `aaru-env`, `APNS_KEY_ID` env | Apple ID sign-in token; device push token + notification text |
| Google | Sign in with Google | none (public client ids) | `GOOGLE_CLIENT_IDS` env | Google sign-in token |
| Resend | Sign-in emails (code + link) | API key | `RESEND_API_KEY` in `aaru-env` | Email address and the sign-in email |
| Stremio (optional, per user) | Importing a user's Stremio history once (IMP-016): `link.stremio.com` device-link code, `api.strem.io` library read + logout. Unofficial API | none | — | The approved link code; the session key is used for one read and never stored |
| Pogdesign CAT (optional, per user) | Reading the user's own CAT iCal export once, when they paste its link (IMP-010). No other CAT page | none | — | The link, which holds the user's CAT key; used for one GET and never stored or logged |
| Trakt (optional, per user) | Importing a user's Trakt history (IMP-002/003) | OAuth client (PKCE, no secret) | `TRAKT_CLIENT_ID` env, `TRAKT_TOKEN_KEY` in `aaru-env` | The user's Trakt authorisation; tokens stored encrypted, revoked on disconnect. Credit: "Aaru uses Trakt but is not endorsed or certified by Trakt." |

## Hosting

| Provider | Used for | Data |
| --- | --- | --- |
| Hetzner (Falkenstein, Germany) | The API server and its PostgreSQL database; encrypted daily backups on a Hetzner Storage Box | Everything in the account and library |
| Cloudflare | DNS, the web app (Workers), TLS for aaruapp.com | Requests to the web app (IP address, the session cookie in transit) |
| GitHub | Source code, CI, container images | No user data |

## Not used

No analytics, advertising, attribution or crash-reporting SDKs in any client. The web app has
a `VITE_SENTRY_DSN` hook but no DSN is set and no Sentry code ships.
