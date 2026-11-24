# aaru-android

The Android client of Aaru: Kotlin and Jetpack Compose, a pure client of `/v1` like the Apple
apps and the web. The plan, milestone by milestone, is in [`PLAN.md`](PLAN.md).

## Build

Needs JDK 21 and the Android SDK (platform 37.2, build-tools 37.0.0). Point Gradle at the SDK
in `local.properties` (git-ignored): `sdk.dir=/path/to/sdk`.

```bash
./gradlew :app:assembleDevDebug        # dev: talks to a server on this machine (10.0.2.2:8080)
./gradlew :app:assembleBetaDebug       # beta: production API, installs beside prod
./gradlew test                         # unit tests
./gradlew spotlessCheck detekt :app:lintBetaDebug   # format, static analysis, Android Lint
./gradlew spotlessApply                # rewrites files
./gradlew :core:api:generateApi        # after any openapi.yaml change; commit the result
node ../scripts/generate-tokens.mjs    # after any design/tokens.json change
```

## Modules

| Module | What it holds |
| --- | --- |
| `app` | Entry point, navigation shell, Hilt graph, flavors `dev` / `beta` / `prod` |
| `core/api` | The `/v1` client generated from `openapi.yaml` (`src/generated`, committed), plus the hand-written session, time zone and assistant-stream code |
| `core/design` | `Tokens.gen.kt` and `colors.gen.xml` (generated from `design/tokens.json`), `AaruTheme` |
| `build-logic` | Convention plugins: `aaru.android.application`, `aaru.android.library`, `aaru.android.compose`, `aaru.kotlin.jvm`, `aaru.hilt`, `aaru.serialization`, `aaru.openapi`, `aaru.quality` |

## Rules

- No rule lives here: every rule is in `aaru-server-v2`. The app shows what `/v1` says.
- Colours come only from the generated tokens (`AaruTheme.colors`, `@color/aaru_*`); no dynamic
  colour, no bundled fonts. `scripts/brand-guard.sh` refuses the rest.
- Every string a person reads is a resource. No XML layouts.
- A feature module depends on `core/*`, never on another feature.
- Versions are written once, in `gradle/libs.versions.toml`.
