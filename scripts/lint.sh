#!/bin/sh
# Check formatting, SwiftLint, and unused code in the Swift packages. Does not rewrite files.
# aaru-server is archived (the API is aaru-server-v2, linted by golangci-lint).
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
for pkg in aaru-core aaru-api; do
  echo "== $pkg =="
  (
    cd "$root/$pkg"
    swiftformat . --lint
    swiftlint
    periphery scan
  )
done
