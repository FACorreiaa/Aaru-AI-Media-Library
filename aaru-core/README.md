# AaruCore

Shared Swift types for [Aaru](../README.md). One definition of a title, a library
item, a status, and an import job — used by `aaru-server` and, when they exist, by
the iOS and Mac clients.

No dependencies. Pure value types, `Codable` and `Sendable`, Swift 6 strict concurrency.

```bash
swift build --package-path aaru-core
swift test  --package-path aaru-core
```

## Why this package exists

The server generates its HTTP types from `Sources/AppAPI/openapi.yaml`, but
`openapi-generator-config.yaml` sets `accessModifier: package` — those types cannot
leave the `aaruAPI` target. Anything the server and a client must both understand is
written here by hand.

## Boundaries

| Belongs here | Does not |
| --- | --- |
| Domain models and identifiers | Persistence, migrations, Fluent models |
| Status and source enums | HTTP server, routing, middleware |
| Validation shared by server and clients | TMDB / Trakt / Open Library keys or adapters |
| Title matching and normalization | SwiftUI views, StoreKit |

## What is in it

| Type | Notes |
| --- | --- |
| `MediaType` | `movie`, `show`, `book` |
| `AaruID<Scope>` + `TitleID`, `LibraryItemID`, `UserID`, `ListID`, `ImportJobID` | UUID-backed, phantom-scoped so a title id cannot be passed as a user id. Encodes as a plain UUID string |
| `ExternalIDs` | `tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`, `openLibrary`, plus `matches(_:)` and fill-empty-only `filling(from:)` |
| `Title`, `Season`, `Episode`, `EpisodeKey` | Catalog layer. `seasons == nil` means not loaded; `[]` means loaded and empty |
| `LibraryStatus` | `wishlist`, `in_progress`, `finished`, `dropped` |
| `LibraryItem` | User layer: status, `isOwned`, rating, notes, progress, timestamps |
| `Rating` | Validating wrapper, one scale |
| `Progress`, `ShowProgress`, `BookProgress` | Episode ticks; optional page/percent for books. Movies carry none |
| `AaruList` | Holds `TitleID`s, so a list can include a title with no status yet |
| `ImportSource`, `ImportJobState`, `ImportStats`, `ImportJob` | One run of a Trakt/CSV/CAT ingest |
| `MediaRef` | Add-to-library payload: title id, or external ids, or title + year |
| `MatchKey` | Normalized title + year + type, and `canMerge(_:_:)` |
| `ValidationError` | The shared rejection vocabulary |

## Conventions this package fixes

These are decisions, not defaults. Changing one is a migration.

- **Rating scale is 1–10 in 0.5 steps.** `Rating` rejects anything else, on
  construction and on decode. Clients showing five stars divide by two.
- **`status` is consumption only.** Ownership is `LibraryItem.isOwned`. Do not add an
  `owned` case to `LibraryStatus`.
- **Raw values are a wire contract.** `in_progress`, `imdb_csv`, `cat_ics` and the rest
  are stored server-side and cached on clients. `WireContractTests` fails loudly if one
  changes.
- **External ids match first.** `MatchKey.canMerge` falls back to normalized title only
  when no provider id is shared, and then still requires the same media type and
  compatible years. Two titles that share nothing but a name never merge.
- **`ImportSource`'s declaration order is the merge order** — Trakt, IMDb, Letterboxd,
  Goodreads, CAT — exposed as `mergeRank`. Later sources fill empty fields only.
- **`AaruList`, not `List`.** A bare `List` collides with SwiftUI in every client file.
  The domain word in the API and the UI is still "list".

## Using it

From a package beside this one:

```swift
.package(path: "../aaru-core"),
// then, on the target:
.product(name: "AaruCore", package: "aaru-core"),
```

`aaru-server` already does this. The dependency is a relative path, so the two
directories must stay siblings.

## Adding a type

1. Add the model here with tests, and run `swift test --package-path aaru-core`.
2. Then the server route or persistence that uses it.
3. Then the client screen.

API first, in that order — see `CLAUDE.md`. If the change adds a status, a source, or a
client, update `CLAUDE.md` and `ARCHITECTURE.md` in the same pass.
