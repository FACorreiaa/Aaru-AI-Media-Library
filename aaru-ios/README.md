# aaru-ios

One multiplatform SwiftUI app (iPhone, iPad, Mac) plus one widget extension, on the
`/v1` API. Depends on `../aaru-core` by local path.

## Layout

```text
Aaru.xcodeproj         plain project (no generator); folders are synchronized groups
Aaru/                  app target sources and assets
AaruWidgets/           widget extension (iOS + macOS widgets; Live Activity later)
Shared/                compiled into both targets: App Group access, App Intents later
Config/                xcconfigs, Info.plist fragments, entitlements
```

New Swift files dropped into `Aaru/`, `AaruWidgets/`, or `Shared/` join their targets
automatically — no project-file edit needed.

## Configurations

| Config | Bundle id | Name | Icon | API |
| --- | --- | --- | --- | --- |
| Debug | `com.fernandocorreia.aaru.beta` | Aaru Dev | AppIconBeta | `http://localhost:8080` |
| Beta | `com.fernandocorreia.aaru.beta` | Aaru Beta | AppIconBeta | production |
| Release | `com.fernandocorreia.aaru` | Aaru | AppIcon | production |

The widget is `<app bundle id>.widgets`. App Group is `group.<app bundle id>` and the
keychain group is `<team prefix><app bundle id>`, so Beta and Release never share data and
install side by side. Schemes: **Aaru** (archives Release) and **Aaru Beta** (archives Beta).

The production API host is a placeholder (`api.aaru.example`) until the domain exists
(`BACKLOG.md` REL-005).

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
bundle exec fastlane beta          # Beta config -> TestFlight (internal), iOS
bundle exec fastlane release       # Release config -> App Store, phased
bundle exec fastlane hotfix        # Release config -> App Store, not phased
bundle exec fastlane seed_signing  # refresh match profiles by hand
```

In CI, `Apple Release` runs `beta` after `Apple CI` passes on `main`; `release` and `hotfix`
run only on manual dispatch behind the `app-store` environment. Until the secrets exist the
beta job skips with a notice.

**Signing** reuses Norviq's match repo, `FinancePlanner/norviq-certificates` (team
`84X9WYBF36`, distribution certificate `4AQ4Q8XM7Z`). The beta lane runs match in write mode,
like Norviq's, so the first CI run creates Aaru's App Store profiles there.

**macOS** builds in CI but does not upload yet: the Mac App Store also needs a Mac Installer
Distribution certificate, which the match repo does not hold. Add one, then add `macos` to
`PLATFORMS` in the Fastfile.

**Icons** are placeholders (reed field at dusk; the beta one carries a BETA band). The real
logo and store metadata come with the first production release.
