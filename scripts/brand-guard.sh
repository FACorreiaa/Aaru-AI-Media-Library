#!/usr/bin/env bash
# Fails when client code steps around Aaru's brand (DESIGN.md "Brand"): a colour written as a
# literal instead of a token from design/tokens.json, or a display face other than the system
# sans. Run from the repo root; CI runs it on every client change (.github/workflows/ci-brand.yml).
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() {
  echo "::error::$1"
  echo "$2" | sed 's/^/  /'
  status=1
}

# Web and extension: hex colours live in the generated token files only (the PWA manifest is one
# of them). `#000` stays allowed, because CSS masks use it as "opaque", not as a colour.
hex=$(git grep -InE '#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})([^0-9a-zA-Z_-]|$)' -- \
  'aaru-client/src' 'aaru-client/public' 'aaru-extension/src' \
  ':!aaru-client/src/tokens.css' ':!aaru-client/src/lib/tokens.gen.ts' \
  ':!aaru-client/public/manifest.webmanifest' \
  ':!aaru-extension/src/entrypoints/popup/tokens.css' ':!aaru-extension/src/lib/tokens.gen.ts' \
  ':!*.test.ts' ':!*.svg' |
  grep -vE '#000([^0-9a-zA-Z_-]|$)' || true)
[ -z "$hex" ] || fail "Colour literal outside the tokens. Add or use a token in design/tokens.json." "$hex"

# The same for rgb()/rgba(): only black (shadows, masks) may be written out; a tint is a token,
# e.g. color-mix(in srgb, var(--accent) 60%, transparent).
rgbweb=$(git grep -InE 'rgba?\( *[0-9]' -- \
  'aaru-client/src' 'aaru-extension/src' \
  ':!aaru-client/src/tokens.css' ':!aaru-extension/src/entrypoints/popup/tokens.css' ':!*.test.ts' |
  grep -vE 'rgba?\( *0[ _,]+0[ _,]+0[ _,/)]' || true)
[ -z "$rgbweb" ] || fail "rgb() colour outside the tokens. Use a token, or color-mix() on one." "$rgbweb"

# Apple: colours come from the asset catalog's colour sets, which the same file generates.
rgb=$(git grep -InE '(Color|UIColor|NSColor)\((red|hue|white):|Color\(hex' -- 'aaru-ios/*.swift' || true)
[ -z "$rgb" ] || fail "Colour literal in Swift. Use a colour set generated from design/tokens.json." "$rgb"

# Display face: the system sans everywhere. No serif design, no bundled or named faces.
serif=$(git grep -InE '\.serif([^a-zA-Z]|$)|\.custom\("' -- 'aaru-ios/*.swift' || true)
[ -z "$serif" ] || fail "Serif or custom font in Swift. Use Font.aaruDisplay (the system sans)." "$serif"
webserif=$(git grep -IniE 'ui-serif|Newsreader|Georgia|@font-face' -- 'aaru-client/src' 'aaru-extension/src' || true)
[ -z "$webserif" ] || fail "Serif or bundled font on the web. Use var(--font-display) (the system sans)." "$webserif"

# Retired marks (DESIGN.md "Brand", 2026-10-22): the owl replaced the heron and the reed mark.
retired=$(git grep -IniE 'heron|reed[ -]?mark' -- 'aaru-client/src' 'aaru-ios' 'aaru-extension/src' || true)
[ -z "$retired" ] || fail "Retired mark. The owl (OwlMark / Image(.owlMark)) is Aaru's mark now." "$retired"

exit $status
