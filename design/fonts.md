# Fonts

Aaru bundles no fonts. Every client uses the system sans: SF Pro on Apple, `system-ui` on the
web and in the browser extension (DESIGN.md "Brand", owner 2026-10-22). Headings are set apart by
weight and size, through `Font.aaruDisplay(_:)` / `Font.widgetDisplay` on Apple and
`--font-display` on the web, so a later face change stays a one-place change.

The poster's geometric "Aaru" is artwork (`docs/brand/`), never set in a font.

Newsreader (OFL), the display face from 2026-10-21 to 2026-10-22, was removed with BRD-001. Its
subsetting recipe is in this file's history.

`scripts/brand-guard.sh` fails CI on a serif design, `.custom(...)` font or `@font-face` in any
client.
