# Aaru

Private-first library for the films, shows, anime, manga, books and albums you care about.

Aaru is named after the Field of Reeds — a quiet place where stories live. Track what
you want, what you are in the middle of, and what you have finished. Import the history
you already keep on Trakt, IMDb, Letterboxd, Goodreads, or a Pogdesign CAT show list.
Friends are opt-in. The library has to be good alone first.

Native iPhone and Mac apps, a web app and a browser extension all talk to one Go API.

## Status

In beta. The API runs in production; the Apple apps ship to TestFlight and the web app to a
beta Worker on every merge to `main`. Nothing is on the App Store yet. `BACKLOG.md` has the
state of every item and what still stands before a 1.0 release.

What is built:

- **Library** for six kinds: films, shows, anime, manga, books and albums. Status, rating,
  notes, lists, episode and chapter progress, a calendar and Up Next.
- **Imports**, one way in: Trakt, Stremio, IMDb, Letterboxd, Goodreads, Netflix, TV Time,
  MyAnimeList, AniList, a CAT show list, any other CSV, and pasted text or a picture.
- **Tracking**: scrobbles from Plex, Jellyfin, Stremio, the browser extension and music
  scrobblers; widgets and a "Now watching" Live Activity.
- **Friends**, private by default: groups with channels, watch parties and reading sessions,
  a friends-only board, recommendations, share links.
- **Aaru**, the assistant: ask by text or voice; anything larger than one change is a plan you
  approve.

## Stack

- **API**: `aaru-server-v2`, Go (echo, pgx, sqlc, goose) on PostgreSQL, generated from one
  OpenAPI spec. Import and background jobs run inside the same process
- **Apple**: SwiftUI, one multiplatform target for iPhone, iPad and Mac, plus a widget
  extension. `AaruCore` holds the shared models, `AaruAPI` the generated client
- **Web**: `aaru-client`, SolidJS + TanStack Start on Cloudflare Workers: landing page and the
  web app
- **Extension**: `aaru-extension`, one Manifest V3 source for Chrome and Firefox
- **Catalog**: TMDB (films, shows), AniList (anime, manga), Open Library (books), MusicBrainz
  (albums), and a few more for air times, relations, sports and concerts
- **Hosting**: API and Postgres on the `maat` cluster through `platform/infra`; beta and
  production apps share one API

Aaru is the source of truth after import. No two-way sync (MyAnimeList is the one exception).
No scraping.

## Repo layout

```text
aaru/
  aaru-core/        AaruCore package: models, IDs, validation, for the Apple apps
  aaru-api/         AaruAPI package: the generated /v1 client for the Apple apps
  aaru-server-v2/   The API (Go)
  aaru-server/      Archived Swift API: keeps openapi.yaml and the client generator only
  aaru-ios/         SwiftUI app for iPhone, iPad and Mac, plus widgets
  aaru-client/      Web: landing page and the web app
  aaru-extension/   Browser extension
  docs/             Privacy policy, terms, providers
```

## Docs

- [`CLAUDE.md`](CLAUDE.md): the working contract: rules, scope, domain words, commands
- [`ARCHITECTURE.md`](ARCHITECTURE.md): system design, data model, routes, import pipeline
- [`DESIGN.md`](DESIGN.md) and [`VIEWS.md`](VIEWS.md): what Aaru feels like, and its surfaces
- [`BACKLOG.md`](BACKLOG.md): every item, its state, and the owner's decisions
- [`docs/privacy.md`](docs/privacy.md), [`docs/terms.md`](docs/terms.md) and
  [`docs/providers.md`](docs/providers.md): the policy the site serves, and every provider
- [`aaru-server-v2/README.md`](aaru-server-v2/README.md) and
  [`aaru-ios/README.md`](aaru-ios/README.md): running the API, and building and releasing
  the Apple apps

Read `CLAUDE.md` and `ARCHITECTURE.md` before changing boundaries between core, server and
apps.

## Product rules (short)

- Catalog metadata and the user's library are different layers.
- Every saved title stores its external IDs when known.
- Status is `wishlist` | `in_progress` | `on_hold` | `finished` | `dropped`. Owning a title is
  a separate flag.
- Private by default. Friends are mutual and opt-in; there is no public profile and no global
  feed.
- Aaru never recommends. Rows on Discover are the providers' own, the same for everyone.

`CLAUDE.md` has the full rules, the import order and what is out of scope.

## Development

```bash
# server (needs Postgres)
cd aaru-server-v2 && docker compose up -d
cd aaru-server-v2 && make test
cd aaru-server-v2 && go run ./cmd/aaru

# web
cd aaru-client && npm run dev

# Apple
swift test --package-path aaru-core
xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

The full list of commands is in `CLAUDE.md`. You will need Go, Node, Xcode with Swift 6,
PostgreSQL (the compose file starts one), and a TMDB API key for films and shows.

Never commit provider secrets. Never run destructive database commands against a non-local
database.

## License

TBD.
