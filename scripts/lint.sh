#!/bin/sh
# Check formatting, SwiftLint, and unused code. Does not rewrite files.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
for pkg in aaru-core aaru-server; do
  echo "== $pkg =="
  (
    cd "$root/$pkg"
    swiftformat . --lint
    swiftlint
    periphery scan
  )
done
