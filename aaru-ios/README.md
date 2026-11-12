# aaru-ios

One multiplatform SwiftUI app (iPhone, iPad, Mac) plus one widget extension, on the
`/v1` API. Depends on `../aaru-core` by local path.

## Layout

```text
Aaru.xcodeproj         plain project (no generator); folders are synchronized groups
Aaru/                  app target sources and assets
AaruWidgets/           widget extension (iOS + macOS widgets; Live Activity later)
AaruTests/             unit tests for the app target (Swift Testing), hosted by the app
Shared/                compiled into both targets: App Group access, App Intents later
Config/                xcconfigs, Info.plist fragments, entitlements
```

New Swift files dropped into `Aaru/`, `AaruWidgets/`, `AaruTests/`, or `Shared/` join their
targets automatically — no project-file edit needed.

## Tests

`AaruTests` holds unit tests for logic that lives in the app target: no network, no UI tests.
Rules shared with the server are tested in `aaru-core`; the API client in `aaru-api`.

```bash
xcodebuild test -project Aaru.xcodeproj -scheme Aaru \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
bundle exec fastlane test   # the same, on the first iPhone simulator installed
```

"Apple CI" runs them on every pull request that touches the app.

## Configurations

| Config | Bundle id | Name | Icon | API |
| --- | --- | --- | --- | --- |
| Debug | `com.fernandocorreia.aaru.beta` | Aaru Dev | AppIconBeta | `http://localhost:8080` |
| Beta | `com.fernandocorreia.aaru.beta` | Aaru Beta | AppIconBeta | production |
| Release | `com.fernandocorreia.aaru` | Aaru | AppIcon | production |

The widget is `<app bundle id>.widgets`. App Group is `group.<app bundle id>` and the
keychain group is `<team prefix><app bundle id>`, so Beta and Release never share data and
install side by side. Schemes: **Aaru** (archives Release) and **Aaru Beta** (archives Beta).

Beta and Release talk to the production API at `https://api.aaruapp.com`; Debug uses
`http://localhost:8080`.

## Building

```bash
xcodebuild build -project Aaru.xcodeproj -scheme Aaru \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Aaru.xcodeproj -scheme Aaru \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Signing is automatic on team `84X9WYBF36`. Before the first signed build, register the
App IDs (`com.fernandocorreia.aaru`, `.beta`, and their `.widgets`) and the App Groups in
the Developer portal. Release signing goes through fastlane match (REL-004).

## Releasing (fastlane)

```bash
cd aaru-ios && bundle install
bundle exec fastlane beta          # Beta config -> TestFlight (internal), iOS then macOS
bundle exec fastlane release       # Release config -> App Store, phased
bundle exec fastlane hotfix        # Release config -> App Store, not phased
bundle exec fastlane metadata      # store copy in fastlane/metadata -> App Store Connect, no build
bundle exec fastlane seed_signing  # refresh match profiles by hand
```

In CI, `Apple Release` runs `beta` after `Apple CI` passes on `main`; `release` and `hotfix`
run only on manual dispatch behind the `app-store` environment. Until the secrets exist the
beta job skips with a notice.

**Signing** reuses Khepri's match repo, `NorthAIProject/north-ios-certificates` (team
`84X9WYBF36`, distribution certificate `BC73LRR48W`, expires 2027-09-23), as ScanIt does. The
beta lane signs read-only; dispatch **Seed signing** once to create Aaru's profiles there, and
again after an entitlement change or a certificate renewal.

**macOS** ships beside iOS: every lane runs once per platform in the Fastfile's `PLATFORMS`.
The Mac App Store takes a signed `.pkg`, which needs a Mac Installer Distribution certificate
beside the distribution one. **Seed signing** creates it in the match repo the first time it
runs with `macos` in `PLATFORMS`, with Aaru's four Mac profiles; the beta and release lanes only
read it. Both app records in App Store Connect need the macOS platform added before the first
Mac upload. The Mac app is sandboxed and may read and write only the files the person picks
(`ENABLE_USER_SELECTED_FILES`), which imports and the data export use. Mac push is not on yet:
the Mac profile has no Push capability.

**Store copy** lives in `fastlane/metadata/` (one `en-US` listing for both platforms) and goes
up with `release`, or alone with `metadata`. App Review's contact and demo account come from the
`REVIEW_*` secrets, never from a file. Screenshots are still added in App Store Connect.

**Icons** are the owl (the beta one carries a BETA band). BRD-003 asks for a 2048 px master
before an App Store release.
