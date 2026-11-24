# Aaru for Android: the plan

Written 2026-11-24. This is the working plan for building the Android client to parity with the
Apple app. It is written so a later session (a person or an agent) can start from any milestone
without the conversation that produced it.

Read first: the repo's `CLAUDE.md` (product rules, domain language), `DESIGN.md`, `VIEWS.md`,
`ARCHITECTURE.md`. This file does not repeat them.

## 1. Where things stand

The scaffold below landed with AND-001 (branch `feat/android-m0`). It passes its own gates
locally; see the AND-001 PR for its first CI run.

| Piece | State |
| --- | --- |
| Gradle project (`settings`, wrapper 9.9.2, version catalog, `build-logic` convention plugins) | Done, builds |
| Quality gates: Spotless + ktlint 1.8.0, detekt 1.23.8 with the Compose rules, Android Lint with warnings as errors, Kotlin `allWarningsAsErrors`, explicit API in libraries | Done, green for `dev` and `beta`. One gap: `core/api` turns `allWarningsAsErrors` off for the whole module because of the generated code, so its hand-written files are not held to it (AND-004) |
| `core/api`: Retrofit client generated from `openapi.yaml` (223 operations, 325 files, committed under `src/generated`) | Done, compiles |
| `core/api` hand-written: `AaruJson`, `SessionInterceptor`, `TimeZoneInterceptor`, `ChatFrameParser`, `AaruClient` | Done, 11 tests pass |
| `core/design`: `Tokens.gen.kt`, `colors.gen.xml` (light and night), `AaruTheme` on Material 3 | Done |
| `scripts/generate-tokens.mjs`: three Android outputs; `--check` covers them | Done |
| `scripts/brand-guard.sh`: Kotlin and Android XML rules, owl JSON copy path | Done |
| `app`: flavors `dev`/`beta`/`prod`, Hilt, adaptive five-tab shell showing each tab's name, launcher icons from the Apple art | Done, `assembleDevDebug` builds a 38 MB debug APK |
| `.github/workflows/ci-android.yml` | Written; first run on the AND-001 PR |
| Everything else in this file | Not started |

Not verified, check before relying on it:

- The app was built, never installed or launched: no emulator image is installed yet.
- `ci-android.yml` uses `actions/setup-java@v5` and `gradle/actions/setup-gradle@v5`; confirm
  those major versions exist, and that the runner can fetch platform 37.2.
- `no-binaries.yml` should accept `gradle/wrapper/gradle-wrapper.jar` (it looks for ELF, Mach-O,
  PE and `ar` archives; a jar is a zip). Confirm on the first PR.
- Release build (`assembleProdRelease`, R8) has not been run.
- Facts about the Apple app and the server in sections 5 to 8 come from two read-only surveys of
  the code on 2026-11-24, not from my own reading of each file. Open the named file before
  building on a detail.

## 2. Decisions the owner made (2026-11-24)

Record these in `BACKLOG.md` "Decisions recorded" with the first PR.

1. The Android app lives in this repo as `aaru-android/` (supersedes "later, its own project",
   `BACKLOG.md:634`).
2. Sign-in on Android: Google, Apple, and the emailed code, as on iOS.
3. Google Play Billing is planned: Aaru Plus can be bought on Android. This changes "bought in
   the Apple apps only" (`CLAUDE.md` Billing row). Built last; Plus is off sale today.
4. Devices: phone, tablet and foldable; then a minimal Wear OS app and a minimal Android TV app.
   Neither has an Apple counterpart, so their scope is defined here (M10, M11), not by parity.
5. Release in phases: a closed Play beta once the basics work (end of M3), production at M9.
6. Stack as the owner proposed: Compose + Material 3, MVVM with one-way data flow, Navigation 3,
   ViewModel + coroutines + StateFlow, Hilt, Retrofit + OkHttp, Room, Coil, Vico, WorkManager,
   JUnit + MockK + Compose UI tests + Maestro. Linters and good practice are part of the scaffold.

Calls made while scaffolding (mine; change them if you disagree):

- **Retrofit over Ktor.** The OpenAPI generator's `jvm-retrofit2` output compiled from the
  3.1.0 spec after three small mends (section 4). No reason left to try Ktor.
- **Code package `app.aaru`, application id `com.fernandocorreia.aaru`** (`.beta` suffix for
  `dev` and `beta`), matching the Apple bundle ids.
- **minSdk 28, compile 37.2, target 37.** Compose BOM 2026.11.01 needs compile 37.1 or later; 37.2 is the newest platform installed.
- **No connection-retry interceptor.** The Apple client retries a GET once on a dead pooled
  connection; OkHttp does that itself.
- **Backups off** (`data_extraction_rules.xml` excludes everything): the session token and the
  cache stay on the device. `docs/privacy.md` should say so when Android is added to it.
- **Lottie is not added.** Nothing on iOS is a Lottie file; motion is Compose animation on the
  three token durations. Add it only when a surface needs a designed vector animation.

## 3. Toolchain on this machine

Installed on the external disk, nothing in the shell profile:

```bash
export JAVA_HOME=/Volumes/PortableSSD/Android/jdk-21/Contents/Home     # Temurin 21
export ANDROID_HOME=/Volumes/PortableSSD/Android/sdk                   # platforms 36, 37.0, 37.2; build-tools 36.0.0, 37.0.0
export GRADLE_USER_HOME=/Volumes/PortableSSD/Android/gradle-home
cd aaru-android && ./gradlew spotlessCheck detekt :app:lintDevDebug test :app:assembleDevDebug
```

`aaru-android/local.properties` (git-ignored) holds `sdk.dir`. The system JDK is 26, which the
Android Gradle Plugin does not accept: always set `JAVA_HOME` as above.

Still to install when first needed: an emulator and a system image
(`sdkmanager "emulator" "system-images;android-37.0;google_apis;arm64-v8a"`), and Maestro.

The Sonatype dependency check could not be used (its token is expired). The versions in
`libs.versions.toml` are the latest stable ones on Maven Central and Google's Maven on
2026-11-24; **none has been checked for known vulnerabilities or licence.** Do that (AND-003)
before the first release build.

## 4. Things the scaffold taught, so nobody learns them twice

- **Gradle plugins and classloaders.** Every Gradle plugin is a dependency of `build-logic`
  and is reached through an `aaru.*` convention plugin. Applying one in a module by
  `alias(libs.plugins.x)` loads it in a second classloader and breaks Spotless's shared service
  and KSP. To add a plugin: add its artifact to `build-logic/build.gradle.kts`, then a
  precompiled script plugin under `build-logic/src/main/kotlin`.
- **Generated client.** `./gradlew :core:api:generateApi` runs the generator into `build/` and
  syncs into `core/api/src/generated` through `MendGeneratedApi` (in `build-logic`), which fixes
  three generator slips line by line: an import of a type it never writes
  (`CreateCaptureImportRequest1`), HTML-escaped backticks around names made from keywords, and
  the reaction emoji enum (named `heart`, `laugh`, `wow`, `cry`, `fire`, `clap`). Parameters
  called `for` and `in` are renamed `purpose` and `within`. If a spec change breaks compilation,
  look there first. Use `--rerun` when only the mend changed.
- **One API interface.** The spec has no tags, so everything is `DefaultApi` (about 3,500
  lines). Do not split it by hand; give each repository the one interface.
- **Enums are strict.** A generated enum has no "unknown" case, so a value the server adds later
  fails decoding of the whole body on an installed app. Before M2, decide per enum that a client
  must survive (statuses are fixed; `RealtimeEvent` types, component types and source names are
  not) and decode those leniently. `AaruJson` already skips unknown fields.
- **UUID and date fields** are `java.util.UUID` and `java.time.OffsetDateTime` with
  `@Contextual`; `AaruJson` registers both serializers. Always use `AaruJson`, never a bare `Json`.
- **Nulls are left out of request bodies.** `AaruJson` has `explicitNulls = false`, so a null field is not sent. Where the API reads an explicit null as "clear this" (a rating, a note, a date), that is wrong. Before M2, check each PATCH/PUT body against what the Swift client sends and what the server does with a missing field versus a null one, and encode those bodies with nulls kept.
- **The staleness check** in `ci-android.yml` uses `git status --porcelain` on `src/generated`, so a newly generated file that nobody added fails it too. Generation is deterministic (two runs, same checksum).
- **Raw routes are not in the generated client in a usable shape** (as on iOS): chat turns
  (SSE), voice upload, chat attachments, CSV/CAT/capture imports, the WebSocket. Each gets a
  small hand-written class in `core/api` beside the generated code, with MockWebServer tests.
- **Brand guard reads tracked files only** (`git grep`). It says nothing about a new file until
  the file is added to git.
- **ktlint and Composables.** `.editorconfig` lets `@Composable` functions start with a capital.
  detekt's config (`config/detekt.yml`) does the same and treats every finding as an error.
- **Launcher icon** is the Apple app's square art, resized; `IconLauncherShape` is disabled in
  `app/build.gradle.kts` with a note. AND-002 replaces it.

## 5. What "the same behaviour" means

The Apple app is the reference: `aaru-ios/Aaru` (323 Swift files, about 48,000 lines), the
widget extension `aaru-ios/AaruWidgets`, shared code in `aaru-ios/Shared`, the client in
`aaru-api`, the rules in `aaru-core`.

Rules to hold on Android:

- **Client only.** No provider is called from the app, and no rule is decided in it.
- **Session.** One opaque bearer token, 90 days, no refresh. A 401 signs the user out once
  (`SessionInterceptor`) and Welcome says the session ended. Token stored encrypted with a
  Keystore key (iOS: Keychain, `aaru-ios/Shared/SessionKeychain.swift`).
- **Cache, not a database of record.** iOS keeps JSON files: `library.json` (sync token plus
  entries, fed by `GET /v1/library/sync?since=`), `home.json`, `discover-rows.json`,
  `tonight.json`; all cleared on sign-out; cached content stays on screen when a refresh fails.
  Android uses Room for the library and one table or DataStore blob per cached page. **There is
  no offline write queue**: a write needs the network, and fails visibly without it.
- **State.** iOS has app-wide observable models built once in `Session/AppServices.swift`
  (`LibraryModel`, `ListsModel`, `ImportsModel`, `GroupsModel`, `ProgressModel`, `PlusModel`,
  `AssistantModel`, `AISharingModel`, `AvatarLoader`, `RealtimeClient`), each with a `reset()`
  called on sign-out and a generation counter that drops responses from a previous session.
  Android: `@Singleton` repositories exposing `StateFlow`, each implementing a `SessionScoped`
  interface whose `reset()` a `SessionManager` calls on sign-out; `LibraryModel.revision` /
  `onWrite` becomes a `SharedFlow` other repositories collect to refetch.
- **Errors.** First load failed: a full-screen retry (`LoadFailedView`). Later failure: a banner
  over the cached content (`ProblemBanner`). Server message shown is `ErrorResponse.message`.
- **Assistant stream.** SSE events `status`, `delta`, `components`, `done`, `error`, with `:`
  heartbeats. A 404 on a turn recreates the chat; a 409 (busy) retries up to three times; a chat
  idle for 15 minutes is expired and a new one starts. Reference: `aaru-api/Sources/AaruAPI/ChatThread.swift`
  (327 lines) and its tests in `aaru-api/Tests`.
- **Realtime.** `wss://host/v1/ws` with the bearer header on the upgrade (apps do not use the
  ticket; that is for browsers). Open only while the app is in the foreground. `ready` means
  refetch over REST. Sends `typing` at most every 3 s and `react` every 1 s. Reconnect with
  1 to 30 s backoff and jitter. Only Groups uses it. Reference: `aaru-ios/Aaru/Realtime/RealtimeClient.swift`.
- **Navigation.** Phone: Home, Discover, Library, Calendar, More (More pushes Groups, Books,
  Manga, Music, Sports). Wide window: Home, Discover, Library, Calendar, Lists, Friends, a More
  section, Insights, Settings. On a phone Lists opens from Library, Friends from Groups, Insights
  from Library's menu (`LibraryView.swift:238`) and from Home's last-7-days strip
  (`HomeSections.swift:232`), Settings as a sheet from the account button. Sports shows only when
  `getSportSettings` says so. Search, linked title, plan, import, invite and share are sheets.
  The assistant card floats over the root and over each sheet. Reference:
  `aaru-ios/Aaru/MainTabs.swift`, `Navigation/AppRouter.swift`, `RootView.swift`.
- **Gate order at launch.** Signed out: Welcome. Signed in: `GET /v1/me` onboarding check, then
  first run if not done, then the AI sharing ask if unanswered, then the tabs.
- **Links.** `https://aaruapp.com/i/{code}` (invite) and `/s/{code}` (share), also on `www.` and
  `beta.`; handled signed in or out, and kept through sign-in. Custom scheme `aaru://`:
  `title/{libraryItemId}`, `settings[/slug]` (`settings/trakt` and `settings/myanimelist` are
  OAuth returns), `groups`, `group/{id}/channel/{id}`. Push payload keys: `libraryItemId`,
  `planId`, `importId`, `url`.
- **Brand.** Colours only from tokens; Material dynamic colour off; system sans; radii, spacing
  and motion from `Tokens.gen.kt`; motion on entrances only, 150/240/420 ms, one curve. English only.
- **Accessibility.** Content descriptions, 48 dp targets, font scale to 200%, TalkBack order,
  and the system "remove animations" setting honoured wherever iOS honours Reduce Motion.

Out of scope because iOS has not built them: Composer (AG-004), DMs (DM-001…005),
FriendStories (SOC-003), a Shortcuts surface. Out of scope because they are web-only: landing,
`/privacy`, `/terms`, OAuth consent, extension connect.

## 6. Architecture

```text
aaru-android/
  build-logic/        convention plugins (done)
  app/                entry, shell, navigation graph, Hilt modules, deep links
  core/api/           generated client + hand-written transport (done: session, zone, SSE parser)
  core/rules/         Kotlin port of the AaruCore rules the clients use (pure JVM)
  core/data/          SessionManager, token store, repositories, Room cache, delta sync
  core/design/        tokens, theme (done); shared components; the owl
  core/testing/       fakes, MockWebServer fixtures, a main-dispatcher rule
  feature/<area>/     one module per area, listed with its milestone below
  widgets/            Glance widgets and their snapshot
  wear/  tv/          M10, M11
```

- A feature depends on `core/*` only. `app` knows every feature and wires navigation. Enforce
  with a Konsist test in `app` (AND-004).
- Each screen: a `@HiltViewModel` exposing one `StateFlow<UiState>` (a data class or sealed
  interface) and taking events as function calls; a stateless `Screen(state, onEvent)` composable
  with a `@Preview` per state; a thin `Route` composable that connects the two. Collect with
  `collectAsStateWithLifecycle`.
- Repositories return domain-shaped Kotlin types where the UI needs more than the DTO, else the
  generated model. No use-case class unless it holds a rule from `core/rules` or is used twice.
- Coroutines: `viewModelScope` for screens, an injected application scope for work that
  outlives one, injected dispatchers (never `Dispatchers.IO` written inline) so tests control time.
- Navigation 3: one back stack per tab, keys are `@Serializable` data classes; the two typed
  destinations iOS has are a library item id and a catalog route (`CatalogRoute`).
- Images: Coil 3 with a disk cache (iOS: 64 MB memory, 512 MB disk). Avatars load through the
  authenticated OkHttp client and never on a signed-out route.

`core/rules` ports only what the Apple app uses from `aaru-core/Sources/AaruCore`:
`BoardRules`/`BoardThread` (threading, pages of 20, merge, upvote toggle, stars and rating
words, 4,000 characters), `Streak*` (runs, summary, local dates, milestones 7/30/100/365),
`Onboarding` (kinds, steps, picks, `nextStatus`), `ShareLinkCode`, `ShareAutoAdd`,
`ShareLoadFailure`, `SilenceDetector`, `SpokenText` (markdown to speech), `SpeechLanguage`.
Port the matching `AaruCoreTests` with the same inputs and expected values. The rest of AaruCore
is unused by the Apple app (it works on the generated schemas) and is not ported.

## 7. Server and repo work Android needs

Each is its own PR in `aaru-server-v2` (table, then DTO in `openapi.yaml`, then client), and
ships through a promote PR in `~/Work/production/platform/infra` before the Android milestone
that needs it. `docs/privacy.md` changes first for S4 and S6. Tests use stub servers, never real keys.

| Id | Work | Notes |
| --- | --- | --- |
| S1 | Android OAuth client id in `GOOGLE_CLIENT_IDS` | Config only (`internal/config/config.go:386`, infra values). `POST /v1/auth/google` and `POST /v1/me/identities/google` exist. Needs a Google Cloud OAuth client for the app's package and signing certificate (owner). Needed by M1 |
| S2 | Sign in with Apple from Android | Apple has no Android SDK: open Apple's web sign-in in a Custom Tab with a Services ID, and return to the app. `APPLE_AUDIENCES` (`config.go:361`) must accept the Services ID; `AppleSignInRequest.redirectUri` is documented "Web only" today; the return prefixes (`config.go:363`) already allow `aaru://` and `https://aaruapp.com/`. Read the web client's Apple flow first and reuse it. Needed by M1, because accounts are keyed on the provider's `sub` and never merged on email: an Apple-only user has no other way in |
| S3 | `assetlinks.json` | Serve `/.well-known/assetlinks.json` from `aaru-client` beside `apple-app-site-association` (`aaru-client/src/routes/[.]well-known/`), listing the prod and beta package names and signing-certificate fingerprints for `/i/*` and `/s/*`. Needed by M7; harmless earlier |
| S4 | Push through FCM | Today `DeviceRegistration` is `{token, environment: sandbox|production, bundleId}`, storage is `apns_devices`, and `internal/push/push.go:34` pins the allowed topics to the two Apple bundle ids. Add a platform to the device row (or an `fcm_devices` table), extend the DTO, add an FCM HTTP v1 sender beside `apns.go`, fan every alert out to both. Needs a Firebase project and a sealed service-account secret in the `horus` namespace (owner). Needed by M4 |
| S5 | Now playing on Android | iOS starts, updates and ends a Live Activity by push (`internal/push/liveactivity.go`, tokens at `PUT /v1/devices/live-activity`). Android: send FCM data messages on the same three moments; the app shows an ongoing notification (a Live Update where the OS has it). `GET /v1/me/now-playing` is the fallback when a message is missed. Needed by M8 |
| S6 | Google Play Billing | `internal/billing` verifies StoreKit only; `Entitlement` has Apple-worded fields (`appAccountToken`, `sandbox`). Add `POST /v1/billing/google/purchases` (verify the purchase token with the Play Developer API, acknowledge it), a Real-time Developer Notifications receiver (Pub/Sub push), and make `Entitlement` store-neutral without breaking the Apple apps. Products mirror `aaru_plus_monthly` / `aaru_plus_yearly`. Needs a Play Console service account (owner). Needed by M9 |
| S7 | Device link for TV | A code shown on the TV, approved on a signed-in phone or the web, returning a session. Specify when M11 starts; the Stremio link-code and OAuth device patterns in the server are the starting point |

Docs to change with the first Android PR: `CLAUDE.md` (stack row, repo layout, commands,
release channels, the Billing row), `ARCHITECTURE.md` (clients, and the line saying Android
"will claim" links), `BACKLOG.md` (the `AND-` items below, the decisions in section 2).
`DESIGN.md` and `VIEWS.md` change when Wear and TV surfaces are designed (M10, M11), and where
an Android surface differs from iOS (the Now playing notification, widgets).
`marketing/` says "Android does not exist: never mention it"; leave it until production (M9).

## 8. Milestones

Every item is done when: its screens match the iOS behaviour on a phone and a tablet width, in
light and dark, at font scale 200%, with TalkBack; ViewModels have unit tests; each screen state
has a preview; a Maestro flow covers the happy path; all gates are green. Per-item "Done when"
lines below add what is specific. Sizes: S about a day, M a few days, L a week or more.

Milestone order is fixed by dependencies; inside a milestone, items can go in parallel.
Appendix A lists every `/v1` operation with its Kotlin function name, by path group; Appendix B
lists every Swift file of the Apple app with its line count, by folder. Each milestone's
"iOS reference" and "Endpoints" lines point into them.

### M0 Rails (mostly done)

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-001 | Commit the scaffold, open the PR, get `ci-android.yml` green, update `CLAUDE.md`, `ARCHITECTURE.md`, `BACKLOG.md` | S | CI green on the PR; brand and no-binaries checks pass with the Android files tracked |
| AND-002 | Adaptive launcher icon (foreground, background, monochrome) cut from the owl master in `docs/brand`, prod and beta | S | `IconLauncherShape` re-enabled and Lint clean |
| AND-003 | Dependency check: vulnerabilities and licences for every entry in `libs.versions.toml`; turn on Gradle dependency verification and locking | S | A recorded result per dependency; `gradle/verification-metadata.xml` committed |
| AND-004 | `core/testing`, `core/rules` (section 6), Konsist boundary test, Kover on `core/*`, the generated client moved to its own module (`core/api-generated`) so `allWarningsAsErrors` is back on for hand-written `core/api`, Roborazzi screenshot tests wired, emulator and Maestro installed, R8 release build proven | M | `./gradlew test verifyRoborazziDebug :app:assembleProdRelease` passes; one Maestro flow launches the app and taps each tab |
| AND-005 | `core/data`: token store (DataStore + Keystore), `SessionManager` (sign-in result, sign-out, `reset()` fan-out), Hilt module providing OkHttp, `DefaultApi`, dispatchers; lenient decoding for the enums named in section 4 | M | A test signs in against MockWebServer, gets a 401, and sees every repository reset once |
| AND-006 | `release-android.yml`: signed bundle to Play's internal track on merge to `main` (beta id), production by manual dispatch; Sentry (errors only, no PII, no tracing) | M | An internal-track build is installable from Play. Needs a Play Console app and an upload key (owner) |

### M1 Session and first run

iOS reference: `Aaru/Session` (6 files), `WelcomeView.swift`, `RootView.swift`, `Onboarding`
(12 files, about 1,600 lines), `AISharing` (3 files), `Settings/Pages` delete account.
Endpoints: `auth/apple`, `auth/google`, `auth/email/link`, `auth/email/verify`, `me`,
`onboarding/*`, AI sharing under `me`. Server: S1, S2.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-010 | Welcome: owl, three pillars, the three sign-in buttons. The owl is a still image until AND-096 brings the 3D one | S | Signed-out launch shows it; an ended session says so |
| AND-011 | Google sign-in through Credential Manager (id token + nonce to `auth/google`) | M | A Google account signs in on a device; hidden when no client id is configured, as on iOS |
| AND-012 | Email code: request, type the 6 digits, verify. The app opens no link | S | Wrong and expired codes show the server's message |
| AND-013 | Sign in with Apple through a Custom Tab (S2) | M | An account made with Apple on iOS reaches its library on Android |
| AND-014 | Launch gate and first run (ONB-001): kinds, picks with a status, favorites, related titles, AI sharing, alerts; Skip on every screen | L | A new account lands on Home with its picks journaled as `onboarding`; rules come from `core/rules` Onboarding |
| AND-015 | AI sharing ask and the 403 `ai_sharing_required` path used by every later AI feature | S | Declining leaves every AI entry point asking, never failing silently |
| AND-016 | Sign out, delete account with `reauth_required` | S | Sign-out clears the token, Room and DataStore caches |

### M2 Basics: search, library, title

iOS reference: `Search` (4 files), `Library` (10, about 2,200 lines: `LibraryModel`,
`LibraryCache`, `LibraryRow`), `Title` (21, about 3,500 lines), `Design` components
(`PosterThumb`, card and well surfaces, `UndoToast`/`ToastCenter`, `LoadFailedView`,
`ProblemBanner`). Endpoints: `search`, `library/*` (10 operations), `titles/*` (9), `actions/*`.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-020 | Shared components in `core/design`: poster, card and well, status chips and tabs, undo toast, load-failed, problem banner, empty state with the owl | M | Each has previews and a screenshot test in light and dark |
| AND-021 | Library repository: Room cache, delta sync by token, refresh on foreground and on write | M | Cold start shows the cached library before the network answers; a deletion on another device disappears after sync |
| AND-022 | Search sheet and add menu (status per kind labels from `CLAUDE.md` Status) | M | Every kind can be found and added; adult works never appear (server rule, nothing to do but not filter locally) |
| AND-023 | Library tab: kind chips, status tabs, grid and list layouts, Now cards, the Now group page (Keeping up, Anime backlog from `inBacklog`), filter with 20 per page | L | Matches iOS for an account with 1,000+ items without jank (baseline profile) |
| AND-024 | Title room: status, owned, rating (1 to 10 in halves), notes, seasons and the episode sheet with bulk tick, whole show watched, book page/percent, manga chapter/volume, album tracklist, where to watch (link out only) | L | Every write is one journaled Action and shows the undo toast |
| AND-025 | Catalog title page for a title not in the library (`CatalogRoute`) | S | Add from it lands in the title room |
| AND-026 | History and undo (Settings → History, `actions`) | S | Undo from the toast and from History give the same result |

### M3 Home, Calendar, Lists, Imports → closed beta

iOS reference: `Home` (19 files, about 3,100 lines, `HomeCache`), `Week` (5), `Calendar` (13),
`Lists` (7), `Capture` (5), `Approvals` (2: `PlanCardView`, `PlanModel`), `Settings/Sections`
import and connection sections. Endpoints: `up-next`, `tonight`, `calendar`, `lists/*`,
`shelves/*`, `imports/*` (21), `plans/*`, `connections/*`.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-030 | Home ("The Field"): Continue, Start, Calendar and Discover rows, Tonight strip, last-7-days strip, status chips, Unfinished, list chips, last import ledger, "Waiting for you" approvals, capture composer; cached | L | Row choice follows the kinds the user keeps; On hold items are absent |
| AND-031 | Week grid; Calendar month plus agenda, Missed/catch-up, filters | L | Filters persist as on iOS (`@AppStorage` → DataStore) |
| AND-032 | Lists index, a list as a Shelf, pinned shelves (saved queries), roadmap steps | M | A roadmap list shows headings, notes, Optional and paired titles |
| AND-033 | Import studio: every source in `CLAUDE.md` "User import" (Trakt OAuth through a Custom Tab returning to `aaru://settings/trakt`, Stremio link code, files through the system picker, AniList by username, `source=auto`), `MatchTable`, `PlanCard`, `JobLedger`, unmatched triage, undo by job | L | A Trakt import and an IMDb CSV import complete on a device; imports are jobs polled, never request-path work |
| AND-034 | Capture: pasted text, images (photo picker, up to 5), catalog links, `?kind=book`; review then approve | M | AI sharing gate honoured; daily limit message shown |
| AND-035 | Plans: `PlanCard` approve and dismiss, "Waiting for you" | S | Approving inside the app is the only way a plan is applied |
| AND-036 | Closed beta: Play closed testing track, store listing draft, privacy answers (Data safety) from `docs/privacy.md` | M | Testers install from Play. Needs owner's Play Console |

### M4 Push and widgets

iOS reference: `Push` (3 files), `Widgets` (2), `aaru-ios/AaruWidgets` (13 files, about 1,850
lines), `aaru-ios/Shared` (`WidgetSnapshot`, `WidgetSync`, `MarkEpisodeWatchedIntent`).
Server: S4.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-040 | FCM registration, token refresh, unregister on sign-out, Android 13 notification permission asked in first run's alerts step and in Settings | M | The server holds one row per signed-in device and none after sign-out |
| AND-041 | Notification channels and handling for airing, group mention, group invite, plan and capture alerts; taps route through the same deep-link handler | M | Each payload key opens the right screen from a cold start |
| AND-042 | Widget snapshot written by the app and refreshed hourly by WorkManager | S | Widgets never call the network from the widget process except "mark watched" |
| AND-043 | Glance widgets: Up Next (small, medium, large, with mark watched), Next Episode countdown, This Week, Listening, Streak | L | Each matches its iOS content; colours from tokens; a signed-out widget says so |

### M5 Discover, kinds, sports, graphs

iOS reference: `Discover` (14 files, about 2,500 lines), `Kinds` (3), `Music` (4), `Sports`
(9, about 2,000), `Title` relation graph and title tree, `Worlds` (5, about 960).
Endpoints: `discover/*`, `concerts/*`, `sports/*`, titles' relations, tree, world, watch.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-050 | Discover: Today rows, On air guide (country from the device language, per request), Seasons browser | L | Rows are the same for every user; nothing is called a recommendation |
| AND-051 | Books, Manga and Music pages: the kind's shelf plus its rows | M | `kindPageOnly` rows never show on Home |
| AND-052 | Concerts: list and map, "Concerts near" city, a one-shot coarse location rounded to two decimals and never stored; tickets link out | M | Denying location still allows a typed city |
| AND-053 | Listens: Recent and Top, music insights | S | |
| AND-054 | Sports tab: Favorites, Schedule, event sheet, search to follow; hidden unless enabled | L | A sport follow is never shown to friends |
| AND-055 | Relation graph, RelatedRow, "Start here" | M | Layout logic ported with the iOS tests (`AaruTests` TitleTree, TitleWatch) |
| AND-056 | Title tree "From here" with person chips (one person's row at a time on a phone) | M | |
| AND-057 | Worlds: WorldStrip, WorldMap with a lane per kind, Worlds index, share card | L | `WorldMap` layout tests ported from `AaruTests` |

### M6 Assistant

iOS reference: `Assistant` (15 files, about 2,500 lines), `aaru-api` `ChatThread`, `ChatReply`,
`ChatHistory`, `ChatVoice`, `ChatFile`. Endpoints: `chats/*` (10), raw: turns, transcribe,
attachments.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-060 | `ChatThread` in `core/api`: turn stream over OkHttp, the 404/409/15-minute rules, tests ported from `AaruAPITests` | M | The scripted-transport tests pass with the same scripts |
| AND-061 | The card: opened from the owl in the top bar over any screen and any sheet, typed question, streaming reply, status line, New chat | L | Back closes the card, not the screen under it |
| AND-062 | Components in a reply: titles (TitleCard), PlanCard, import link, RoadmapCard, action summary with undo, sources under the reply | M | A searched turn shows its pages and writes only plans |
| AND-063 | Voice: `MediaRecorder` m4a AAC 16 kHz mono, 60 s cap, end of speech by `SilenceDetector`, upload to transcribe (422, 413, 429, 503 handled); read-aloud with `TextToSpeech` in the language Whisper found, sources never read; mute | M | Microphone permission asked at first use only |
| AND-064 | Files and long pastes: picker, photos, drag in on large screens; `import_attachment`; while a file is in the chat every write is a plan | M | Refusals from the server's file check show its message |
| AND-065 | History in the card and in Settings: list, reopen, delete one, delete all | S | |

### M7 Social

iOS reference: `Social` (13 files, about 2,300 lines), `Profile` (5), `Share` (4), `Board`
(12, about 2,100). Endpoints: `social/*` (18), `invites`, `shares`, `board/*` (11), `users`,
`activity/*`. Server: S3.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-070 | App Links for `/i/{code}` and `/s/{code}` (S3), kept through sign-in; `aaru://` scheme | M | `adb shell am start` with each link opens the right sheet signed in and signed out |
| AND-071 | Friends tab: Board and Lately, requests, suggestions, opt-in discovery, blocks | L | A blocked user's rows and counts never show |
| AND-072 | Invites (make, share, the invite letter) and share links with preview and note | M | |
| AND-073 | Recommend a title; the friend's inbox: add to Plan to watch or dismiss | S | |
| AND-074 | Profile, edit profile, avatar (one square JPEG made on the device), favorites (top 10 per kind), friend profile | M | No avatar is loaded on a signed-out route |
| AND-075 | Board: posts, post page, comments (one level), upvotes, spoiler stamp, report, Aaru's comments; rules from `core/rules` | L | |
| AND-076 | Reactions on activity rows (six emoji) | S | |

### M8 Groups, realtime, Now playing

iOS reference: `Groups` (33 files, about 5,100 lines), `Realtime` (1), `Home` Now playing,
`Shared/NowPlayingActivity`. Endpoints: `groups/*` (28), `group-invites`, `realtime`.
Server: S5.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-080 | `RealtimeClient` over OkHttp WebSocket with the rules in section 5; lifecycle-bound | M | Tests cover backoff, `ready` refetch, throttles |
| AND-081 | Groups: rail, channel list, members and roles, create and invite friends, settings | L | Every channel says "not end-to-end" |
| AND-082 | Messages: send, edit, delete, replies, reactions, images, mentions, typing, read state, presence, report | L | Works with two devices live |
| AND-083 | `@aaru` in a group, replies in `#ai-reply` (found by `is_agent_replies`), only members who allowed AI sharing are sent | M | |
| AND-084 | Channel kinds: `title` with the spoiler veil, `shelf` (labelled "List"), `watch` | M | |
| AND-085 | Watch party / Reading session: invite, ready, countdown, reactions, shared check-off, "Mark it for me", end marks each joined member's own Action | L | Undo works per member; a dropped item is never touched |
| AND-086 | Now playing: ongoing notification from FCM data messages (S5), up to three rows, mark watched and end-time actions; the by-hand "Now watching" check-in | M | Starts, updates and ends from a scrobble with the app closed |

### M9 Gamification, Settings, Plus → production

iOS reference: `Achievements` (7), `Insights` (4, Swift Charts), `Recap` (9), `Settings` (38
files, about 4,500 lines), `Plus` (3), `Review` (2). Server: S6.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-090 | Level, streak, badges (hidden ones stay hidden), friends leaderboard with opt-in, unlock toast; Streak rules from `core/rules` | L | |
| AND-091 | Insights with Vico charts | M | |
| AND-092 | Recap: the story deck for a month or year, share card as an image | L | Nothing loops after it lands |
| AND-093 | Settings, eight pages: Account, Friends & privacy, Notifications, Import, Connections (Trakt, Stremio, MyAnimeList, CAT), Your data (export, chats, History), About, Delete account; plus AI data sharing, music scrobblers, agent tokens and connections, sports | L | Every row iOS has exists and does the same thing |
| AND-094 | Aaru Plus with Play Billing (S6): paywall, purchase, restore, entitlement from `/v1/me/entitlement` | L | A licence-tester purchase grants Plus on Android, iOS and web |
| AND-095 | In-app review prompt with the iOS gating (`Review/ReviewPrompter`) | S | |
| AND-096 | 3D owl: the web's `owl.glb` and `owl-on-books.glb` (`cdn.aaruapp.com/aaru/owl3d/v2/`) bundled, drawn with Filament, moved by `design/owl-motion.json` and `owl-rig.json` (copies under `core/design/src/main/assets`, checked by the brand guard); motion math ported with the `OwlMotion` test values shared with iOS and web; a still image when animations are off or on battery saver | L | Welcome and first run show it. Can move earlier if wanted for the beta; nothing depends on it |
| AND-097 | Production: store listing, screenshots, Data safety, staged rollout; landing page's "Android to follow" and `marketing/` updated | M | Owner's call to publish |

### M10 Wear OS (minimal)

No Apple counterpart; scope set by the owner as "minimal". Design the surfaces in `DESIGN.md`
and `VIEWS.md` first.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-100 | `wear` module, Compose for Wear, tokens theme | S | |
| AND-101 | Session handed from the phone through the Wearable Data Layer; no sign-in on the watch; signed out when the phone signs out | M | |
| AND-102 | Tiles and complications: Up Next, next-episode countdown, streak (the content of the iOS lock-screen widgets) | M | |
| AND-103 | Mark the next episode watched from the watch | S | One journaled Action, undoable on the phone |

### M11 Android TV (minimal)

Aaru plays nothing, so TV is for looking and ticking. Server: S7.

| Id | Item | Size | Done when |
| --- | --- | --- | --- |
| AND-110 | `tv` module, Compose for TV, focus and remote handling | M | |
| AND-111 | Sign-in by a code approved on the phone or web (S7) | M | |
| AND-112 | Home rows, Up Next, Calendar, a title page with mark watched | L | No assistant, groups, imports or settings beyond sign-out |

## 9. How to verify

- Every PR: `./gradlew spotlessCheck detekt test :app:lintBetaDebug :app:assembleBetaDebug`,
  `node scripts/generate-tokens.mjs --check`, `scripts/brand-guard.sh`, generated client not
  stale (`./gradlew :core:api:generateApi --rerun && git diff --exit-code -- aaru-android/core/api/src/generated`).
- Against a real server: `cd aaru-server-v2 && docker compose up -d && go run ./cmd/aaru`, then
  the `dev` flavor on an emulator (it reaches the host at `10.0.2.2:8080`).
- Parity: one account on an iPhone and an Android device side by side; for each surface in the
  milestone, compare against the `VIEWS.md` catalog and check that a write on one shows on the
  other after a refresh.
- Maestro flows live in `aaru-android/maestro/`, one per area, run on a phone and a tablet profile.
- Server items: `make test`, `golangci-lint run ./...`, `make vuln` in `aaru-server-v2`.

## 10. What the owner must provide

| Needed for | What |
| --- | --- |
| AND-006, AND-036 | Google Play Console developer account and an app entry; an upload signing key (kept as a CI secret) |
| S1, AND-011 | A Google Cloud OAuth client for the Android package and its signing-certificate fingerprints (debug, upload, Play app signing) |
| S2, AND-013 | An Apple Services ID with the return URL configured |
| S4 | A Firebase project for FCM and its service-account key (sealed for `horus`) |
| S6 | Play Console API access (service account) and a Pub/Sub topic for notifications; product ids and prices |
| AND-006 | A Sentry project (or the existing one) for the Android DSN |

## Appendix A: every /v1 operation

Read from `core/api/src/generated/.../DefaultApi.kt` on 2026-11-24: 223 operations, grouped by
the first path segment after `v1`. Regenerate the client and this list will drift; the source
of truth is `aaru-server/Sources/AppAPI/openapi.yaml`.

### `actions` (2)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/actions` | `listActions` |
| POST | `/v1/actions/{id}/undo` | `undoAction` |

### `activity` (3)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/activity` | `listFriendActivity` |
| DELETE | `/v1/activity/{id}/reaction` | `clearActivityReaction` |
| PUT | `/v1/activity/{id}/reaction` | `setActivityReaction` |

### `agent` (4)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/agent/setup/{kind}` | `getAgentSetup` |
| GET | `/v1/agent/tokens` | `listAgentTokens` |
| POST | `/v1/agent/tokens` | `createAgentToken` |
| DELETE | `/v1/agent/tokens/{id}` | `revokeAgentToken` |

### `auth` (6)

| Method | Path | Function |
| --- | --- | --- |
| POST | `/v1/auth/apple` | `signInWithApple` |
| POST | `/v1/auth/email/link` | `requestMagicLink` |
| POST | `/v1/auth/email/verify` | `verifyMagicLink` |
| POST | `/v1/auth/google` | `signInWithGoogle` |
| DELETE | `/v1/auth/session` | `signOut` |
| DELETE | `/v1/auth/sessions` | `signOutOtherDevices` |

### `billing` (2)

| Method | Path | Function |
| --- | --- | --- |
| POST | `/v1/billing/apple/notifications` | `receiveAppleNotification` |
| POST | `/v1/billing/apple/transactions` | `recordAppleTransaction` |

### `board` (11)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/board` | `listBoard` |
| POST | `/v1/board/posts` | `createBoardPost` |
| DELETE | `/v1/board/posts/{postId}` | `deleteBoardPost` |
| GET | `/v1/board/posts/{postId}` | `getBoardPost` |
| PATCH | `/v1/board/posts/{postId}` | `editBoardPost` |
| GET | `/v1/board/posts/{postId}/comments` | `listBoardComments` |
| POST | `/v1/board/posts/{postId}/comments` | `createBoardComment` |
| DELETE | `/v1/board/posts/{postId}/comments/{commentId}` | `deleteBoardComment` |
| DELETE | `/v1/board/posts/{postId}/upvote` | `removeBoardPostUpvote` |
| PUT | `/v1/board/posts/{postId}/upvote` | `upvoteBoardPost` |
| GET | `/v1/board/posts/{postId}/upvotes` | `listBoardPostUpvoters` |

### `calendar` (1)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/calendar` | `getCalendar` |

### `chats` (10)

| Method | Path | Function |
| --- | --- | --- |
| DELETE | `/v1/chats` | `deleteChats` |
| GET | `/v1/chats` | `listChats` |
| POST | `/v1/chats` | `createChat` |
| GET | `/v1/chats/status` | `getChatStatus` |
| POST | `/v1/chats/transcribe` | `transcribeChatAudio` |
| DELETE | `/v1/chats/{id}` | `deleteChat` |
| GET | `/v1/chats/{id}` | `getChat` |
| POST | `/v1/chats/{id}/attachments` | `createChatAttachment` |
| DELETE | `/v1/chats/{id}/attachments/{attachmentId}` | `deleteChatAttachment` |
| POST | `/v1/chats/{id}/turns` | `createChatTurn` |

### `concerts` (5)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/concerts/artists` | `getArtistConcerts` |
| POST | `/v1/concerts/near` | `getConcertsNear` |
| POST | `/v1/concerts/performers` | `searchConcertPerformers` |
| GET | `/v1/concerts/places` | `searchConcertPlaces` |
| POST | `/v1/concerts/search` | `searchConcerts` |

### `connections` (4)

| Method | Path | Function |
| --- | --- | --- |
| DELETE | `/v1/connections/mal` | `disconnectMAL` |
| GET | `/v1/connections/mal` | `getMALConnection` |
| POST | `/v1/connections/mal/connect` | `connectMAL` |
| POST | `/v1/connections/mal/pull` | `requestMALPull` |

### `devices` (3)

| Method | Path | Function |
| --- | --- | --- |
| PUT | `/v1/devices` | `registerDevice` |
| PUT | `/v1/devices/live-activity` | `registerLiveActivityToken` |
| DELETE | `/v1/devices/{token}` | `unregisterDevice` |

### `discover` (3)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/discover` | `getDiscover` |
| GET | `/v1/discover/on-air` | `getDiscoverOnAir` |
| GET | `/v1/discover/season` | `getDiscoverSeason` |

### `group-invites` (2)

| Method | Path | Function |
| --- | --- | --- |
| DELETE | `/v1/group-invites/{id}` | `declineGroupInvite` |
| POST | `/v1/group-invites/{id}/accept` | `acceptGroupInvite` |

### `groups` (28)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/groups` | `listGroups` |
| POST | `/v1/groups` | `createGroup` |
| DELETE | `/v1/groups/{groupId}` | `deleteGroup` |
| GET | `/v1/groups/{groupId}` | `getGroup` |
| PATCH | `/v1/groups/{groupId}` | `updateGroup` |
| POST | `/v1/groups/{groupId}/channels` | `createChannel` |
| DELETE | `/v1/groups/{groupId}/channels/{channelId}` | `deleteChannel` |
| PATCH | `/v1/groups/{groupId}/channels/{channelId}` | `updateChannel` |
| GET | `/v1/groups/{groupId}/channels/{channelId}/items` | `listChannelItems` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/items` | `addChannelItem` |
| DELETE | `/v1/groups/{groupId}/channels/{channelId}/items/{titleId}` | `removeChannelItem` |
| GET | `/v1/groups/{groupId}/channels/{channelId}/messages` | `listMessages` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/messages` | `postMessage` |
| DELETE | `/v1/groups/{groupId}/channels/{channelId}/messages/{messageId}` | `deleteMessage` |
| PATCH | `/v1/groups/{groupId}/channels/{channelId}/messages/{messageId}` | `editMessage` |
| GET | `/v1/groups/{groupId}/channels/{channelId}/party` | `getWatchParty` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/party` | `openWatchParty` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/party/end` | `endWatchParty` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/party/ready` | `setWatchPartyReady` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/party/start` | `startWatchParty` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/party/watched` | `markWatchPartyWatched` |
| GET | `/v1/groups/{groupId}/channels/{channelId}/progress` | `getChannelProgress` |
| POST | `/v1/groups/{groupId}/channels/{channelId}/read` | `markChannelRead` |
| POST | `/v1/groups/{groupId}/invites` | `inviteToGroup` |
| PUT | `/v1/groups/{groupId}/me` | `updateMyMembership` |
| DELETE | `/v1/groups/{groupId}/members/{userId}` | `removeGroupMember` |
| PATCH | `/v1/groups/{groupId}/members/{userId}` | `updateGroupMember` |
| POST | `/v1/groups/{groupId}/transfer` | `transferGroup` |

### `health` (1)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/health` | `getHealth` |

### `imports` (21)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/imports` | `listImports` |
| POST | `/v1/imports/anilist` | `createAniListImport` |
| POST | `/v1/imports/capture` | `createCaptureImport` |
| POST | `/v1/imports/cat` | `createCATImport` |
| POST | `/v1/imports/cat/feed` | `createCATFeedImport` |
| POST | `/v1/imports/csv` | `createCSVImport` |
| POST | `/v1/imports/lastfm` | `createLastFMImport` |
| POST | `/v1/imports/listenbrainz` | `createListenBrainzImport` |
| POST | `/v1/imports/stremio/link` | `startStremioLink` |
| POST | `/v1/imports/stremio/link/{code}` | `pollStremioLink` |
| POST | `/v1/imports/trakt` | `createTraktImport` |
| POST | `/v1/imports/trakt/connect` | `connectTrakt` |
| DELETE | `/v1/imports/trakt/connection` | `disconnectTrakt` |
| GET | `/v1/imports/trakt/connection` | `getTraktConnection` |
| DELETE | `/v1/imports/{id}` | `deleteImport` |
| GET | `/v1/imports/{id}` | `getImport` |
| POST | `/v1/imports/{id}/apply` | `applyImport` |
| POST | `/v1/imports/{id}/match-all` | `matchAllImportRows` |
| POST | `/v1/imports/{id}/rows/{index}/left-out` | `leaveOutImportRow` |
| POST | `/v1/imports/{id}/rows/{index}/resolve` | `resolveImportRow` |
| POST | `/v1/imports/{id}/undo` | `undoListenImport` |

### `invites` (1)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/invites/{code}` | `getInvitePreview` |

### `library` (10)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/library/items` | `listLibraryItems` |
| POST | `/v1/library/items` | `addLibraryItem` |
| DELETE | `/v1/library/items/{id}` | `deleteLibraryItem` |
| GET | `/v1/library/items/{id}` | `getLibraryItem` |
| PATCH | `/v1/library/items/{id}` | `updateLibraryItem` |
| PUT | `/v1/library/items/{id}/episodes/{season}/{episode}` | `setEpisodeWatched` |
| POST | `/v1/library/items/{id}/seasons/{season}/watched` | `markSeasonWatched` |
| POST | `/v1/library/items/{id}/watched` | `markShowWatched` |
| GET | `/v1/library/sync` | `syncLibrary` |
| GET | `/v1/library/watching` | `listWatching` |

### `lists` (9)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/lists` | `listLists` |
| POST | `/v1/lists` | `createList` |
| DELETE | `/v1/lists/{id}` | `deleteList` |
| GET | `/v1/lists/{id}` | `getList` |
| PATCH | `/v1/lists/{id}` | `renameList` |
| GET | `/v1/lists/{id}/graph` | `getListGraph` |
| POST | `/v1/lists/{id}/items` | `addListItem` |
| DELETE | `/v1/lists/{id}/items/{titleId}` | `removeListItem` |
| PUT | `/v1/lists/{id}/order` | `reorderList` |

### `me` (38)

| Method | Path | Function |
| --- | --- | --- |
| DELETE | `/v1/me` | `deleteAccount` |
| GET | `/v1/me` | `getMe` |
| PUT | `/v1/me/ai-sharing` | `setAISharing` |
| DELETE | `/v1/me/avatar` | `deleteAvatar` |
| PUT | `/v1/me/avatar` | `uploadAvatar` |
| GET | `/v1/me/badges` | `listBadges` |
| POST | `/v1/me/badges/seen` | `markBadgesSeen` |
| DELETE | `/v1/me/concert-place` | `deleteConcertPlace` |
| GET | `/v1/me/concert-place` | `getConcertPlace` |
| PUT | `/v1/me/concert-place` | `saveConcertPlace` |
| GET | `/v1/me/entitlement` | `getEntitlement` |
| GET | `/v1/me/export` | `exportAccount` |
| GET | `/v1/me/favorites` | `getMyFavorites` |
| PUT | `/v1/me/favorites/{kind}` | `setMyFavorites` |
| GET | `/v1/me/group-invites` | `listGroupInvites` |
| POST | `/v1/me/identities/google` | `linkGoogle` |
| GET | `/v1/me/listens` | `listListens` |
| GET | `/v1/me/listens/top` | `getTopListens` |
| GET | `/v1/me/notifications` | `getNotificationSettings` |
| PUT | `/v1/me/notifications` | `updateNotificationSettings` |
| GET | `/v1/me/now-playing` | `getNowPlaying` |
| PUT | `/v1/me/onboarding` | `finishOnboarding` |
| GET | `/v1/me/points` | `listPoints` |
| PUT | `/v1/me/profile` | `updateProfile` |
| GET | `/v1/me/profile/stats` | `getProfileStats` |
| GET | `/v1/me/progress` | `getProgress` |
| GET | `/v1/me/recommendations` | `listRecommendations` |
| DELETE | `/v1/me/recommendations/{id}` | `dismissRecommendation` |
| POST | `/v1/me/recommendations/{id}/add` | `addRecommendation` |
| GET | `/v1/me/social-settings` | `getSocialSettings` |
| PUT | `/v1/me/social-settings` | `updateSocialSettings` |
| GET | `/v1/me/sport-follows` | `listSportFollows` |
| DELETE | `/v1/me/sport-follows/{kind}/{providerId}` | `unfollowSport` |
| PUT | `/v1/me/sport-follows/{kind}/{providerId}` | `followSport` |
| GET | `/v1/me/sport-settings` | `getSportSettings` |
| PUT | `/v1/me/sport-settings` | `saveSportSettings` |
| GET | `/v1/me/stats` | `getStats` |
| GET | `/v1/me/worlds` | `listMyWorlds` |

### `oauth` (3)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/oauth/requests/{id}` | `getOAuthRequest` |
| POST | `/v1/oauth/requests/{id}/approve` | `approveOAuthRequest` |
| POST | `/v1/oauth/requests/{id}/deny` | `denyOAuthRequest` |

### `onboarding` (3)

| Method | Path | Function |
| --- | --- | --- |
| POST | `/v1/onboarding/picks` | `addOnboardingPicks` |
| POST | `/v1/onboarding/related` | `getOnboardingRelated` |
| GET | `/v1/onboarding/rows` | `getOnboardingRows` |

### `plans` (4)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/plans` | `listPlans` |
| GET | `/v1/plans/{id}` | `getPlan` |
| POST | `/v1/plans/{id}/approve` | `approvePlan` |
| POST | `/v1/plans/{id}/deny` | `denyPlan` |

### `realtime` (1)

| Method | Path | Function |
| --- | --- | --- |
| POST | `/v1/realtime/ticket` | `createRealtimeTicket` |

### `search` (1)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/search` | `searchCatalog` |

### `shares` (2)

| Method | Path | Function |
| --- | --- | --- |
| POST | `/v1/shares` | `createShare` |
| GET | `/v1/shares/{code}` | `getSharePreview` |

### `shelves` (5)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/shelves` | `listShelves` |
| POST | `/v1/shelves` | `createShelf` |
| DELETE | `/v1/shelves/{id}` | `deleteShelf` |
| PATCH | `/v1/shelves/{id}` | `updateShelf` |
| GET | `/v1/shelves/{id}/items` | `listShelfItems` |

### `social` (18)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/social/blocks` | `listBlocks` |
| DELETE | `/v1/social/blocks/{userId}` | `unblockUser` |
| PUT | `/v1/social/blocks/{userId}` | `blockUser` |
| GET | `/v1/social/friend-requests` | `listFriendRequests` |
| POST | `/v1/social/friend-requests` | `sendFriendRequest` |
| DELETE | `/v1/social/friend-requests/{id}` | `withdrawFriendRequest` |
| POST | `/v1/social/friend-requests/{id}/accept` | `acceptFriendRequest` |
| GET | `/v1/social/friends` | `listFriends` |
| DELETE | `/v1/social/friends/{userId}` | `removeFriend` |
| GET | `/v1/social/friends/{userId}/profile` | `getFriendProfile` |
| GET | `/v1/social/invites` | `listFriendInvites` |
| POST | `/v1/social/invites` | `createFriendInvite` |
| DELETE | `/v1/social/invites/{code}` | `revokeFriendInvite` |
| POST | `/v1/social/invites/{code}/redeem` | `redeemFriendInvite` |
| GET | `/v1/social/leaderboard` | `getLeaderboard` |
| POST | `/v1/social/recommendations` | `recommendTitle` |
| POST | `/v1/social/reports` | `reportUser` |
| GET | `/v1/social/users/{handle}` | `getSocialUser` |

### `sports` (5)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/sports/events/{id}` | `getSportEvent` |
| GET | `/v1/sports/favorites` | `getSportFavorites` |
| GET | `/v1/sports/schedule` | `getSportSchedule` |
| GET | `/v1/sports/search` | `searchSports` |
| GET | `/v1/sports/suggested` | `getSportSuggestions` |

### `titles` (9)

| Method | Path | Function |
| --- | --- | --- |
| POST | `/v1/titles/resolve` | `resolveTitle` |
| GET | `/v1/titles/{id}` | `getTitle` |
| GET | `/v1/titles/{id}/posts` | `listTitlePosts` |
| GET | `/v1/titles/{id}/relations` | `getTitleRelations` |
| POST | `/v1/titles/{id}/relations/chain` | `planRelationChain` |
| GET | `/v1/titles/{id}/tree` | `getTitleTree` |
| GET | `/v1/titles/{id}/watch` | `getTitleWatch` |
| GET | `/v1/titles/{id}/world` | `getTitleWorld` |
| POST | `/v1/titles/{id}/world/plan` | `planWorldRest` |

### `tonight` (3)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/tonight` | `getTonight` |
| DELETE | `/v1/tonight/{id}/feedback` | `clearTonightFeedback` |
| POST | `/v1/tonight/{id}/feedback` | `sendTonightFeedback` |

### `up-next` (1)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/up-next` | `getUpNext` |

### `users` (1)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/users/{userId}/avatar` | `getUserAvatar` |

### `web-push` (3)

| Method | Path | Function |
| --- | --- | --- |
| GET | `/v1/web-push/key` | `getWebPushKey` |
| DELETE | `/v1/web-push/subscriptions` | `deleteWebPushSubscription` |
| PUT | `/v1/web-push/subscriptions` | `saveWebPushSubscription` |

## Appendix B: the Apple app, file by file

Swift files and line counts under `aaru-ios` on 2026-11-24 (generated token files left out).
The file to read before building the Android counterpart of anything.

### `aaru-ios/Aaru`

`AaruApp.swift` 82, `AppEnvironment.swift` 22, `CrashReporting.swift` 38, `MainTabs.swift` 368, `RootView.swift` 261, `WelcomeView.swift` 197

### `aaru-ios/Aaru/AISharing`

`AISharingAsk.swift` 112, `AISharingDisclosure.swift` 151, `AISharingModel.swift` 144

### `aaru-ios/Aaru/Achievements`

`AchievementsView.swift` 146, `BadgeMedallion.swift` 129, `BadgeShelf.swift` 251, `LeaderboardSection.swift` 84, `ProgressModel.swift` 215, `StreakBar.swift` 142, `UnlockToast.swift` 152

### `aaru-ios/Aaru/Approvals`

`PlanCardView.swift` 177, `PlanModel.swift` 78

### `aaru-ios/Aaru/Assistant`

`AssistantCard.swift` 314, `AssistantComposer.swift` 230, `AssistantFiles.swift` 268, `AssistantHistory.swift` 82, `AssistantHost.swift` 181, `AssistantModel.swift` 399, `AssistantOpening.swift` 39, `AssistantTurn.swift` 21, `AssistantTurnView.swift` 180, `ChatHistoryViews.swift` 284, `ChatSourcesView.swift` 43, `ChatsModel.swift` 108, `ReplySpeaker.swift` 70, `RoadmapCardView.swift` 153, `VoiceRecorder.swift` 128

### `aaru-ios/Aaru/Board`

`BoardModel.swift` 249, `BoardTypes.swift` 76, `BoardView.swift` 156, `CommentComposer.swift` 154, `CommentSafety.swift` 44, `CommentThread.swift` 234, `PostComposer.swift` 204, `PostModel.swift` 243, `PostRow.swift` 171, `PostScreen.swift` 370, `ReportPostSheet.swift` 130, `UpvoteButton.swift` 82

### `aaru-ios/Aaru/Calendar`

`AgendaList.swift` 103, `AiringChannels.swift` 70, `CalendarEpisodeRow.swift` 81, `CalendarEpisodeSheet.swift` 148, `CalendarFeed.swift` 251, `CalendarFilter.swift` 176, `CalendarSample.swift` 93, `CalendarScreen.swift` 298, `CatchUpView.swift` 87, `DaySheet.swift` 46, `MonthGridView.swift` 198, `MonthModel.swift` 160, `MonthView.swift` 82

### `aaru-ios/Aaru/Capture`

`CaptureCard.swift` 40, `CaptureComposer.swift` 174, `CaptureContent.swift` 167, `ImportsModel+Capture.swift` 86, `MatchAllButton.swift` 148

### `aaru-ios/Aaru/Design`

`AaruType.swift` 28, `ActionUndo.swift` 20, `AgentPresence.swift` 26, `Appearance.swift` 60, `Atmosphere.swift` 136, `AvatarView.swift` 104, `HoverInk.swift` 21, `LoadFailedView.swift` 57, `MentionSuggestions.swift` 53, `Optional+IsPresent.swift` 12, `Owl.swift` 241, `Owl3DView.swift` 336, `OwlMotion.swift` 187, `Paging.swift` 41, `Pasteboard.swift` 18, `PosterThumb.swift` 47, `ProblemBanner.swift` 29, `Surfaces.swift` 98, `UndoToast.swift` 155

### `aaru-ios/Aaru/Discover`

`ApproximateLocation.swift` 48, `ConcertPlacePicker.swift` 122, `ConcertRow.swift` 211, `ConcertTypes.swift` 64, `ConcertsFetcher.swift` 66, `ConcertsModel.swift` 375, `ConcertsParts.swift` 119, `ConcertsView.swift` 388, `DiscoverModel.swift` 106, `DiscoverScreen.swift` 291, `OnAirModel.swift` 108, `OnAirView.swift` 109, `SeasonBrowser.swift` 203, `SeasonModel.swift` 250

### `aaru-ios/Aaru/Groups`

`AgentViews.swift` 297, `ChannelEditorSheet.swift` 78, `ChannelHeader.swift` 79, `ChannelModel+Agent.swift` 24, `ChannelModel.swift` 382, `ChannelStart.swift` 35, `ChannelView.swift` 372, `Composer.swift` 78, `GroupLink.swift` 21, `GroupLists.swift` 260, `GroupNameSheet.swift` 60, `GroupSheets.swift` 175, `GroupsModel+Channels.swift` 91, `GroupsModel+Realtime.swift` 67, `GroupsModel+Report.swift` 43, `GroupsModel.swift` 361, `GroupsScreen.swift` 325, `InviteFriendsSheet.swift` 56, `MemberList.swift` 138, `MemberStrip.swift` 36, `MessageRow.swift` 272

### `aaru-ios/Aaru/Groups/Kinds`

`DiscussInGroupSheet.swift` 123, `NewChannelSheet.swift` 160, `OpenPartySheet.swift` 118, `ShelfChannelView.swift` 143, `ShelfModel.swift` 111, `SpoilerChoice.swift` 141, `TitleChannelHeader.swift` 193, `TitleChannelModel.swift` 72, `TitlePickerModel.swift` 49, `TitlePickerSheet.swift` 148, `WatchPanel.swift` 274, `WatchPartyModel.swift` 278

### `aaru-ios/Aaru/Home`

`DiscoverCard.swift` 242, `HomeCache.swift` 71, `HomeCards.swift` 225, `HomeLabels.swift` 60, `HomeModel+Discover.swift` 67, `HomeModel.swift` 396, `HomeRow.swift` 142, `HomeSample.swift` 171, `HomeScreen.swift` 255, `HomeScreenPreviews.swift` 45, `HomeSections.swift` 292, `HomeSummary.swift` 200, `LastImportCard.swift` 53, `NowPlaying.swift` 116, `NowPlayingCard.swift` 236, `ReadingRow.swift` 67, `Tonight.swift` 162, `TonightCard.swift` 213, `TonightFeed.swift` 75

### `aaru-ios/Aaru/Insights`

`InsightsModel.swift` 177, `InsightsView.swift` 138, `StatsCharts.swift` 218, `StatsPanel.swift` 177

### `aaru-ios/Aaru/Kinds`

`BooksImport.swift` 213, `KindScreen.swift` 249, `KindShelf.swift` 101

### `aaru-ios/Aaru/Library`

`LibraryCache.swift` 32, `LibraryCards.swift` 288, `LibraryModel+Now.swift` 230, `LibraryModel.swift` 275, `LibraryRow.swift` 204, `LibraryView.swift` 262, `MarkWatched.swift` 269, `NowGroupView.swift` 368, `NowSection.swift` 278, `PosterView.swift` 26

### `aaru-ios/Aaru/Lists`

`ListDetailView.swift` 255, `ListItemRow.swift` 74, `ListPickerSheet.swift` 79, `ListsModel.swift` 209, `ListsScreen.swift` 60, `ListsView.swift` 259, `RoadmapSteps.swift` 244

### `aaru-ios/Aaru/Music`

`Listening.swift` 184, `ListensModel.swift` 91, `MusicInsights.swift` 72, `MusicView.swift` 188

### `aaru-ios/Aaru/Navigation`

`AaruCommands.swift` 75, `AppRouter.swift` 375, `MoreScreen.swift` 46, `NavigationHelpers.swift` 126

### `aaru-ios/Aaru/Onboarding`

`AISharingStep.swift` 28, `FavoritesStep.swift` 171, `KindsStep.swift` 92, `NotificationsStep.swift` 81, `OnboardingFlow.swift` 140, `OnboardingGate.swift` 44, `OnboardingKind+App.swift` 92, `OnboardingModel.swift` 371, `OnboardingParts.swift` 294, `OnboardingScreen.swift` 29, `PickerStep.swift` 162, `RelatedStep.swift` 84

### `aaru-ios/Aaru/Plus`

`PlusModel.swift` 153, `PlusPaywall.swift` 131, `PlusSection.swift` 32

### `aaru-ios/Aaru/Profile`

`FavoritesEditor.swift` 147, `FavoritesModel.swift` 149, `ProfileModel.swift` 106, `ProfileSections.swift` 385, `ProfileView.swift` 335

### `aaru-ios/Aaru/Push`

`LiveActivityRegistrar.swift` 139, `PushInbox.swift` 19, `PushRegistrar.swift` 109

### `aaru-ios/Aaru/Realtime`

`RealtimeClient.swift` 211

### `aaru-ios/Aaru/Recap`

`RecapBanner.swift` 34, `RecapCardParts.swift` 187, `RecapCards.swift` 222, `RecapDeck.swift` 266, `RecapModel.swift` 58, `RecapOnRepeat.swift` 42, `RecapPeriod.swift` 64, `RecapShareCard.swift` 78, `RecapView.swift` 193

### `aaru-ios/Aaru/Review`

`ReviewPromptPresenter.swift` 45, `ReviewPrompter.swift` 123

### `aaru-ios/Aaru/Search`

`AddMenu.swift` 33, `SearchModel.swift` 122, `SearchRows.swift` 116, `SearchView.swift` 248

### `aaru-ios/Aaru/Session`

`APIStatusLabel.swift` 28, `AppServices.swift` 118, `AuthFlow.swift` 131, `EmailSignInSheet.swift` 126, `GoogleSignIn.swift` 107, `SessionStore.swift` 45

### `aaru-ios/Aaru/Settings`

`Gunzip.swift` 43, `ImportDetailView.swift` 396, `ImportLedger.swift` 160, `ImportSources.swift` 221, `ImportsModel+Listens.swift` 86, `ImportsModel.swift` 396, `SettingsPage.swift` 74, `SettingsView.swift` 180, `SettingsWindow.swift` 72

### `aaru-ios/Aaru/Settings/Models`

`AccountModel.swift` 91, `ConnectionsModel.swift` 211, `DataModel.swift` 134, `HistoryModel.swift` 127, `NotificationsModel.swift` 75, `SettingsServices.swift` 61

### `aaru-ios/Aaru/Settings/Pages`

`AISharingPage.swift` 51, `AboutView.swift` 129, `AccountPage.swift` 79, `ConnectionsPage.swift` 74, `DataPage.swift` 76, `DeleteAccountPage.swift` 71, `HistoryView.swift` 126, `ImportPage.swift` 201, `NotificationsPage.swift` 44

### `aaru-ios/Aaru/Settings/Sections`

`AgentsSection.swift` 62, `BrowserExtensionView.swift` 44, `CATImportSheet.swift` 87, `ConcertPlaceSection.swift` 47, `ConnectionSetupView.swift` 174, `ExportDataSection.swift` 77, `LinkGoogleButton.swift` 34, `MALSection.swift` 95, `MusicSection.swift` 66, `MusicSetupView.swift` 220, `SportSettingsSection.swift` 46, `StremioHistoryImport.swift` 117, `StremioSection.swift` 194, `TraktSection.swift` 75

### `aaru-ios/Aaru/Share`

`ShareCards.swift` 63, `ShareComposerSheet.swift` 164, `SharePreviewView.swift` 231, `SharedLink.swift` 27

### `aaru-ios/Aaru/Social`

`FriendProfileView.swift` 310, `FriendsScreen.swift` 256, `FriendsView.swift` 351, `InviteLink.swift` 22, `InviteSheet.swift` 260, `InviteViews.swift` 93, `ProfileEditor.swift` 171, `RecommendViews.swift` 233, `SocialModel+Achievements.swift` 43, `SocialModel+Profile.swift` 67, `SocialModel+Report.swift` 26, `SocialModel.swift` 393, `SocialWords.swift` 39

### `aaru-ios/Aaru/Sports`

`SportCountryPicker.swift` 100, `SportEventDetailView.swift` 347, `SportEventRow.swift` 209, `SportFavoritesView.swift` 212, `SportFormat.swift` 245, `SportScheduleView.swift` 184, `SportsModel.swift` 340, `SportsScreen.swift` 128, `SportsSearchView.swift` 192

### `aaru-ios/Aaru/Title`

`AlbumHeader.swift` 66, `AlbumPagePreviews.swift` 39, `AlbumSample.swift` 51, `AlbumTracklist.swift` 105, `CenteredFlow.swift` 55, `EpisodeCode.swift` 49, `EpisodeSheet.swift` 136, `LibraryEntryDestination.swift` 37, `RelationGraphCanvas.swift` 149, `SeasonMap.swift` 152, `TitleDetailModel.swift` 351, `TitleDetailView.swift` 313, `TitleFromFriends.swift` 90, `TitlePreviewView.swift` 198, `TitleRelated.swift` 270, `TitleRelationsModel.swift` 204, `TitleRoomParts.swift` 177, `TitleRoomSections.swift` 284, `TitleTree.swift` 294, `TitleTreeModel.swift` 288, `TitleWatch.swift` 180

### `aaru-ios/Aaru/Week`

`WeekCell.swift` 190, `WeekDayPager.swift` 124, `WeekGridView.swift` 111, `WeekModel.swift` 135, `WeekView.swift` 186

### `aaru-ios/Aaru/Widgets`

`NowWatchingStart.swift` 54, `WidgetRefresh.swift` 29

### `aaru-ios/Aaru/Worlds`

`WorldMap.swift` 215, `WorldModel.swift` 270, `WorldScreen.swift` 262, `WorldShareCard.swift` 101, `WorldsView.swift` 113

### `aaru-ios/AaruWidgets`

`AaruWidgetsBundle.swift` 17, `CountdownWidget.swift` 194, `ListeningWidget.swift` 197, `NowPlayingIsland.swift` 158, `NowPlayingLiveActivity.swift` 158, `NowPlayingLiveActivityPreviews.swift` 98, `NowPlayingRowParts.swift` 212, `StreakWidget.swift` 177, `UpNextWidget.swift` 215, `WeekWidget.swift` 180, `WidgetCommon.swift` 137, `WidgetSample.swift` 64

### `aaru-ios/Shared`

`AppGroup.swift` 9, `MarkEpisodeWatchedIntent.swift` 151, `NowPlayingActivity.swift` 101, `NowPlayingArtwork.swift` 107, `NowWatching.swift` 115, `SessionKeychain.swift` 52, `WidgetSnapshot.swift` 265, `WidgetSync.swift` 164
