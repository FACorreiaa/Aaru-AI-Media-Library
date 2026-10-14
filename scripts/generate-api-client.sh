#!/bin/sh
# Regenerate aaru-api's client from the server's spec. CI fails if the committed output is stale.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/aaru-api/Sources/AaruAPI/Generated"
rm -rf "$out" && mkdir -p "$out"
swift run --package-path "$root/aaru-server" swift-openapi-generator generate \
  "$root/aaru-server/Sources/AppAPI/openapi.yaml" \
  --config "$root/aaru-api/openapi-generator-config.yaml" \
  --output-directory "$out"
