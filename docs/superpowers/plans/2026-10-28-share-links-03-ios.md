# SHR-002 Share links · iOS and Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping `aaruapp.com/s/{code}` on an iPhone, iPad or Mac with Aaru installed opens a share sheet in the app, signed in or out. A Share action on titles, the catalog preview, sport events and concerts makes the link.

**Architecture:**
- The link parser and the auto-add rule are pure Swift in `AaruCore`, unit-tested in `AaruCoreTests`. The iOS app has no test target, and the precedent is `BoardRules` and `Streak`.
- `RootView` routes `/s/{code}` next to `InviteLink`. Unlike an invite, a share opens signed out too.
- `SharePreviewView` calls the generated `getSharePreview`, and `ShareComposerSheet` calls `createShare`. Both operations are already in `AaruAPI` (#215).
- The AASA claim for `/s/*` ships in this same PR, so iPhones never open share links in an app that ignores them.
- There are no API changes.

**Tech Stack:**
- Swift 6 and SwiftUI with Observation.
- The multiplatform target `aaru-ios/Aaru`. It uses `PBXFileSystemSynchronizedRootGroup`, so new files need no pbxproj edit.
- The generated `AaruAPI` client.
- swift-testing in `aaru-core`.
- vitest for the AASA test in `aaru-client`.

**Spec:** `docs/superpowers/specs/2026-10-28-share-links-design.md` (§iOS). The web build it mirrors is `aaru-client/src/routes/s.$code.tsx`, `aaru-client/src/lib/shares/model.ts` and `aaru-client/src/components/shares/*` (#216). The surfaces are already described in `DESIGN.md` §"Share links" and in `VIEWS.md` rows "Share link page" and "Share (sheet)".

## Global Constraints

- **Worktree:** `/Users/fernandocorreiachill/Work/production/apps/aaru-share-ios`, on branch `feat/share-links-ios` from `origin/main`.
- **Toolchain:** Swift 6 strict concurrency. Use `~/.swiftly/bin/swift` for `aaru-core`.
- **Colours** come only from tokens: `Color(.paper)`, `.ink`, `.muted`, `.accent`, `.gold`, `.danger`.
- **Spacing** comes from the existing numbers and `AaruSpace.*`.
- **Type:** headings use `.aaruDisplay(...)`. No hex and no new fonts (`ci-brand.yml`).
- **Skills:** load `swiftui-design-principles` and `swiftui-pro` before writing views (owner: no generic UI). Follow the HIG.
- **The opener just sees the content.** There's no friendship, no install push and no TestFlight link.
- **Sender and note:** "From {name}" and the note show only when the API sends `from`. The app never infers them.
- **Note field:** labelled "Only your friends see this note", at most 140 characters (trim to 140 as the person types). The server validates it.
- **Sports show the score up front:** the final result when finished, the live score when live.
- **Concert:** "Tickets" opens the event's `url`. iOS has no concert detail, and none is added.
- **Status words** come from `LibraryStatus.label(for:)`. "Add to Plan to watch/read/listen" uses the kind's wishlist label.
- **Hosts:** `aaruapp.com`, `www.aaruapp.com`, `beta.aaruapp.com`, the same as `InviteLink.hosts`.
- **Code:** `[A-Za-z0-9]{1,32}`.
- **Done** means all of these pass:
  - `swift test --package-path aaru-core`
  - `swiftformat . --lint` and `swiftlint` from the repo root
  - `xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - the same with `-destination 'generic/platform=macOS'`
  - `cd aaru-client && npm run check && npm run lint && npm run typecheck && npm test`
- **Disk is short.** Delete `aaru-core/.build`, Xcode DerivedData for the worktree, and `aaru-client/node_modules` when done.

## Rulings made while planning

- **The parser lives in `AaruCore` (`ShareLinkCode`), and the app's `SharedLink` wraps it.** The app has no test target, and this parser decides which links open the app. `InviteLink` stays where it is (no refactor). Cost if wrong: one small duplicated host set.
- **Signed out, "Add to my Aaru" closes the sheet onto Welcome and holds the link as `pendingShare` with `add: true`.** After sign-in, `RootView` reopens the sheet, and it adds the title once when `ShareAutoAdd.should(...)` says so. This mirrors `pendingInvite` and the web's `?add=1`. Cost if wrong: one extra tap after sign-in.
- **"Open in Sports" opens `SportEventDetailView` as a sheet over the share sheet**, with a fresh `SportsModel(api:)`. It shows only when signed in and `router.sportsAvailable`. `SportEventDetailView` already owns its `NavigationStack` and needs no route. Signed out, the action is "Follow sports on Aaru", which closes the sheet onto Welcome. Cost if wrong: a second Done tap.
- **The sport card reuses `EventHeader` from `SportEventDetailView.swift`.** Drop its `private`; it stays in that file. The concert card reuses `ConcertRow`. The title card is new and small (poster, name, kind and year, overview) and borrows `PosterView`. Cost if wrong: none; these are the same faces as their own screens.
- **Concert rows get a share button through an optional `onShare: (() -> Void)?` on `ConcertRow`,** which is nil for the placeholder rows. `ConcertsView` holds `@State sharing: Concert?` and presents the composer with the model's client. Make `ConcertsModel`'s `api` readable (not `private`) if it is. Cost if wrong: the button moves into a context menu later.
- **On a title, Share sits in the More menu** after "Recommend to friends…" ("Share…", `square.and.arrow.up`), per DESIGN.md "beside Add to list and Recommend". On the catalog preview and the sports sheet it is a toolbar button. Cost if wrong: a toolbar move.
- **The composer takes two steps, as on the web:** note, then Create link, then `ShareLink` and Copy link. SwiftUI's `ShareLink` needs the URL before it is tapped. Cost if wrong: none.
- **A window remains in which a TestFlight build from before this PR opens `/s/*` and ignores it.** The beta Worker gets the AASA claim on merge, and TestFlight builds on the same merge, so the window lasts until people update. The prod Worker deploys by manual dispatch: ship it after the TestFlight build is out. Cost if wrong: a few taps open the app on Home.

## Review Focus

1. **A share link opened while signed in, routed by both `RootView` and `MainTabs.open`.** Expected: one sheet, and `MainTabs.open` ignores share links as it does invites. Pinned in Task 2, Step 3.
2. **A signed-in viewer returns from sign-in with `add: true` but already has the title** (`libraryItemId` is set). Expected: no second add, and "In your library · {status} · Open" shows. Pinned by `ShareAutoAddTests` (Task 1).
3. **The URL looks like a share but isn't one:** `/s/`, `/s/a/b`, `/s/../x`, a 33-character code, an `http:` scheme, or another host. Expected: nil, and the link falls through to the existing routing. Pinned by `ShareLinkCodeTests` (Task 1).
4. **`unavailable: true`, or a 404.** Expected: a plain `ContentUnavailableView` per case ("This match isn't available right now" / "This concert's details aren't available right now" / "This link doesn't work"), never an empty card. Checked by hand in Task 2, Step 5.
5. **A UFC or WWE card with no sides, or a match with no score yet.** Expected: `EventHeader` already handles both; the share sheet never prints "nil" or "0–0" for a match that hasn't started. Checked by hand in Task 2, Step 5.

---

### Task 1: `ShareLinkCode` and `ShareAutoAdd` in AaruCore

**Files:**
- Create: `aaru-core/Sources/AaruCore/ShareLinks.swift`
- Test: `aaru-core/Tests/AaruCoreTests/ShareLinksTests.swift`

**Interfaces:**
- Produces: `public enum ShareLinkCode { public static let hosts: Set<String>; public static func code(in url: URL) -> String? }`
- Produces: `public enum ShareAutoAdd { public static func should(add: Bool, signedIn: Bool, isTitle: Bool, unavailable: Bool, alreadyInLibrary: Bool) -> Bool }`

- [ ] **Step 1: Write the failing tests.**
  - **`ShareLinkCodeTests` returns `"k7Q2xPa9Lm3Z"` for:**
    - `https://aaruapp.com/s/k7Q2xPa9Lm3Z`
    - `https://www.aaruapp.com/s/k7Q2xPa9Lm3Z`
    - `https://beta.aaruapp.com/s/k7Q2xPa9Lm3Z/`
    - `https://aaruapp.com/s/k7Q2xPa9Lm3Z?add=1`
  - **It returns nil for:**
    - `http://aaruapp.com/s/abc`
    - `https://evil.example/s/abc`
    - `https://aaruapp.com/s/`
    - `https://aaruapp.com/s/a/b`
    - `https://aaruapp.com/i/abc`
    - `https://aaruapp.com/s/ab-c`
    - `https://aaruapp.com/s/` followed by 33 × `a`
  - **`ShareAutoAddTests`:**
    - It is true only for `(add: true, signedIn: true, isTitle: true, unavailable: false, alreadyInLibrary: false)`.
    - Flipping each argument alone gives false: five cases in a parameterised `@Test(arguments:)`.

- [ ] **Step 2: Run them.** `~/.swiftly/bin/swift test --package-path aaru-core --filter ShareLinks`. Expected: a build failure, because `ShareLinkCode` is undefined.

- [ ] **Step 3: Implement both in `ShareLinks.swift`.** The parser uses the same rules as `InviteLink.init?` (`aaru-ios/Aaru/Social/InviteLink.swift`):
  - the scheme is `https` and the host is in `hosts`;
  - the non-`/` path components are exactly `["s", code]`;
  - the code `wholeMatch`es `/[A-Za-z0-9]{1,32}/`.

  Add one doc comment per type: the parser is for SHR-002 universal links, and `should` saves the shared title once, on return from sign-in.

- [ ] **Step 4: Run them.** The same command. Expected: all pass. Then run the whole `swift test --package-path aaru-core` and expect it green.

- [ ] **Step 5: Commit.** `git add aaru-core/Sources/AaruCore/ShareLinks.swift aaru-core/Tests/AaruCoreTests/ShareLinksTests.swift && git commit -m "feat(core): share link parser and auto-add rule (SHR-002)"`

### Task 2: Open a share link: `SharedLink`, routing, and `SharePreviewView`

**Files:**
- Create: `aaru-ios/Aaru/Share/SharedLink.swift`, `aaru-ios/Aaru/Share/SharePreviewView.swift`, `aaru-ios/Aaru/Share/ShareCards.swift`
- Modify: `aaru-ios/Aaru/RootView.swift` (state at :22-24, `.sheet` at :61, `.onOpenURL` at :66, `.onChange` at :75)
- Modify: `aaru-ios/Aaru/MainTabs.swift:205-210` (`open(_:)`)
- Modify: `aaru-ios/Aaru/Sports/SportEventDetailView.swift:98` (`EventHeader` loses `private`)

**Interfaces:**
- Consumes: `ShareLinkCode.code(in:)` and `ShareAutoAdd.should(...)` (Task 1). `api.getSharePreview(path: .init(code:))`. `LibraryModel.add(_ ref: MediaRef, named:status:api:)`. `LibraryEntryDestination(id:api:library:lists:)`. `SportEventDetailView(model:id:)`. `ConcertRow(concert:)`.
- Produces: `struct SharedLink: Identifiable, Equatable { let code: String; var add = false; init?(_ url: URL) }`, where `id` is `code`.
- Produces: `typealias SharePreview = Components.Schemas.SharePreview`.
- Produces: `struct SharePreviewView: View { let api: Client?; let link: SharedLink; let library: LibraryModel; let lists: ListsModel; let onSignIn: (SharedLink) -> Void }`. `onSignIn` hands back the link with `add` set, for the pending path.

- [ ] **Step 1: Add `SharedLink`.** It wraps `ShareLinkCode.code(in:)`. Doc comment: why it isn't named `ShareLink` (it would clash with SwiftUI).

- [ ] **Step 2: Build `SharePreviewView`, modelled on `InviteSheet`.**
  - **Shell:** `NavigationStack`, `ScrollView`, a `maxWidth: 480` column on `Color(.paper)`, a Close button, and `.task { await load() }`.
  - **Stages:** `.loading`, `.missing` (404 or a network failure), and `.ready(SharePreview)`.
  - **Signed in?** Read `SessionStore` from the environment (`session.isSignedIn`).
  - **Body:**
    1. "From {displayName ?? handle}" and the note in quotes, only when `preview.from` is set.
    2. The card. `ShareCards.swift` holds `ShareTitleCard(title: TitleDetail)`, plus `EventHeader(event:)` for a match and `ConcertRow(concert:)` for a concert.
    3. One action:
       - **A title the viewer has** (`libraryItemId` set): "In your library · {status label}" with Open, which pushes `LibraryEntryDestination`.
       - **A title, signed in:** "Add to Plan to …", through `library.add(MediaRef(_type:ids:title:year:), named:status: .wishlist, api:)`. On success it shows the in-library line. Use the `id` from `library.entry(matching:)` after the upsert, else reload the preview.
       - **A title, signed out:** "Add to my Aaru" → `onSignIn(link with add = true)` then `dismiss()`.
       - **A sport event:** "Open in Sports" when signed in and `router.sportsAvailable`; signed out, "Follow sports on Aaru" → `onSignIn(link)`.
       - **A concert:** the row's own Tickets, plus "Concerts near you on Aaru" when signed out → `onSignIn(link)`.
    4. A quiet "What is Aaru?" `Link` to `https://aaruapp.com/`.
  - **Unavailable:** `ContentUnavailableView` with "This match isn't available right now" or "This concert's details aren't available right now". **Missing:** "This link doesn't work".
  - **Auto-add:** after `load()`, if `ShareAutoAdd.should(add: link.add, signedIn:, isTitle: preview.kind == .title, unavailable: preview.unavailable, alreadyInLibrary: preview.libraryItemId != nil)`, run the add once.

- [ ] **Step 3: Route it in `RootView`.**
  - Add `@State private var openShare: SharedLink?` and `@State private var pendingShare: SharedLink?`.
  - `.onOpenURL`: try `SharedLink(url)` first and set `openShare`, signed in or out. Then the existing invite branch.
  - `.sheet(item: $openShare)` presents `SharePreviewView(api:link:library:lists:onSignIn: { pendingShare = $0 })`.
  - In `.onChange(of: session.isSignedIn)`: when signed in, a `pendingShare` moves to `openShare`; when signed out, clear both.
  - In `MainTabs.open(_:)`, return early for `SharedLink(url) != nil` too, with the comment updated: "RootView opens friend invites and share links, signed in or out".

- [ ] **Step 4: Verify the build and lint.** Run the iOS and macOS `xcodebuild` builds, `swiftformat . --lint` and `swiftlint`. Expected: all clean.

- [ ] **Step 5: Check by hand in the Simulator against production.** Use `xcrun simctl openurl booted "https://aaruapp.com/s/{code}"`, with codes made on the web beta from these targets: a film, a finished match, a match that hasn't started, a concert, and a made-up code. Check each card, the unavailable and missing lines, signed out and signed in, and dark mode.

  The Simulator may open Safari instead, because the AASA doesn't claim `/s/*` yet. If it does, call `RootView`'s handler through a temporary `#if DEBUG` launch argument, and remove it before commit. Record what was and wasn't seen.

- [ ] **Step 6: Commit** the files above: `feat(ios): open share links in the app, signed in or out (SHR-002)`.

### Task 3: Make a share link: `ShareComposerSheet` and the four Share entry points

**Files:**
- Create: `aaru-ios/Aaru/Share/ShareComposerSheet.swift`
- Modify: `aaru-ios/Aaru/Title/TitleDetailView.swift` (`moreMenu` at :162, and a sheet beside `RecommendSheet` at :109)
- Modify: `aaru-ios/Aaru/Title/TitlePreviewView.swift` (toolbar on `page(_:)`)
- Modify: `aaru-ios/Aaru/Sports/SportEventDetailView.swift` (toolbar at :46)
- Modify: `aaru-ios/Aaru/Discover/ConcertRow.swift`, `aaru-ios/Aaru/Discover/ConcertsView.swift` (call sites :64 and :229)

**Interfaces:**
- Consumes: `api.createShare(body: .json(.init(target: .init(kind:ref:id:), note:)))` → `.ok` with `ShareLink {code, url}`.
- Produces: `enum ShareTarget: Hashable { case title(MediaRef), sportEvent(id: String), concert(id: String) }`.
- Produces: `struct ShareComposerSheet: View { let api: Client?; let target: ShareTarget; let name: String }`.
- Produces: `ConcertRow.onShare: (() -> Void)? = nil`.

- [ ] **Step 1: Build `ShareComposerSheet`.**
  - **Step one:** the name, and a `TextField("Add a note", text:, axis: .vertical)` captioned "Only your friends see this note", cut to 140 characters in `onChange`. Then a "Create link" `.borderedProminent` button.
  - **Step two:**
    - The URL as text.
    - `ShareLink(item: url, message: Text(name))` labelled "Share".
    - A "Copy link" button that uses `UIPasteboard` on iOS and `NSPasteboard` on macOS, behind `#if os(iOS)`.
    - The footnote "Anyone with the link sees it. Only your friends see that you sent it."
  - **Errors:** `.default(_, error)` → `try? error.body.json.message`. A network error → "Aaru could not reach the server." Show it under the button in `Color(.danger)`.
  - **Presentation:** `.presentationDetents([.medium])` on iOS.

- [ ] **Step 2: Wire the entry points.**
  - **Title room:** a "Share…" (`square.and.arrow.up`) button in `moreMenu` after Recommend, presenting the composer with `.title(MediaRef(_type: entry.title._type, ids: entry.title.ids, title: entry.title.title, year: entry.title.year))`. Adjust to the entry's real field names.
  - **Catalog preview:** a toolbar `ShareLink`-styled button with `.title(...)` built from `hit`.
  - **Sports sheet:** a `.primaryAction` "Share" button, shown once `detail` loads, with `.sportEvent(id: id)`.
  - **Concert row:** when `onShare` is set, a `square.and.arrow.up` icon button (44 × 44, `accessibilityLabel("Share \(concert.name)")`) beside Tickets. `ConcertsView` sets `onShare` on both call sites and presents the composer with `.concert(id: concert.id)`. The placeholders pass nothing.

- [ ] **Step 3: Verify the build and lint.** The two builds, `swiftformat . --lint` and `swiftlint`. Expected: clean.

- [ ] **Step 4: Check by hand in the Simulator (signed in, production API).** Make a link from each of the four entry points. The returned URL opens on the web beta and shows the same content. The same target and note give back the same link.

- [ ] **Step 5: Commit.** `feat(ios): share titles, matches and concerts (SHR-002)`.

### Task 4: Claim `/s/*` and update the docs

**Files:**
- Modify: `aaru-client/src/lib/links/apple.ts`, `aaru-client/src/lib/links/apple.test.ts`
- Modify: `ARCHITECTURE.md` (the sentence "The Apple apps claim `/s/*` as a universal link with the iOS work, once they can open one")
- Modify: `DESIGN.md` §"Share links", `VIEWS.md` rows "Share link page" and "Share (sheet)", and `BACKLOG.md` SHR-002

- [ ] **Step 1: Write the failing test.** In `apple.test.ts`, rename the case to "claims invite and share links, for the App Store and Beta apps" and expect these components:

  ```ts
  [
    { '/': '/i/*', comment: 'Friend invite links' },
    { '/': '/s/*', comment: 'Share links' },
  ]
  ```

- [ ] **Step 2: Run it.** `cd aaru-client && npx vitest run src/lib/links/apple.test.ts`. Expected: FAIL, with the `/s/*` entry missing.

- [ ] **Step 3: Implement.**
  - Add the component to `apple.ts`.
  - Update its header comment: share links (SHR-002) open the app too.

- [ ] **Step 4: Run the web gate.** `npm run check && npm run lint && npm run typecheck && npm test`. Expected: all pass.

- [ ] **Step 5: Docs.**
  - **ARCHITECTURE.md:** the apps claim `/s/*` and open it in `SharePreviewView`, signed in or out.
  - **DESIGN.md:** one paragraph on the Apple apps. A share link opens as a sheet with the same card and action as the web page. Signed out, "Add to my Aaru" goes through Welcome and back. "Open in Sports" opens the event sheet. On a title, Share is in More.
  - **VIEWS.md:** the "Share link page" row also names the Apple sheet `SharePreviewView`, and the "Share (sheet)" row names `ShareComposerSheet`.
  - **BACKLOG.md:** mark the SHR-002 iOS part done.

- [ ] **Step 6: Commit.** `feat: claim share links in the Apple apps (SHR-002)`. Include the AASA, the test and the docs.

### Final

- Run the full Done set (Global Constraints).
- Review the whole branch with a fresh reviewer.
- Open the PR (mattpocock template). The PR says real verification is a TestFlight device: tap a `/s/{code}` link in Messages and the right sheet opens.
- Deploy the prod Worker (which carries the AASA) only after that TestFlight build is out (see Rulings).
