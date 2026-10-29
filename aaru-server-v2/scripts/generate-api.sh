#!/usr/bin/env bash
# Generates internal/api/api.gen.go (types + echo strict server) from the one
# openapi.yaml the web and Apple clients also generate from. oapi-codegen reads
# OpenAPI 3.0, so the 3.1 spec is lowered first: the version line and the
# `type: [string, 'null']` form are the only 3.1 features it uses.
set -euo pipefail
cd "$(dirname "$0")/.."
SPEC="${SPEC:-../aaru-server/Sources/AppAPI/openapi.yaml}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -E \
  -e "s/^openapi: '3\.1\.0'/openapi: '3.0.3'/" \
  -e "s/^( *)type: \[string, 'null'\]/\1type: string\n\1nullable: true/" \
  "$SPEC" > "$TMP/openapi.yaml"
if grep -qE "type: \[" "$TMP/openapi.yaml"; then
  echo "openapi.yaml uses a 3.1 type list this script does not lower" >&2
  exit 1
fi
go tool oapi-codegen -config oapi-codegen.yaml "$TMP/openapi.yaml"
