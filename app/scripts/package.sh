#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?Usage: package.sh OUTPUT_DIRECTORY}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
# Package the committed source, never local build products or credentials.
git -C "$ROOT" archive --format=zip --prefix=pgn-clipboard/ \
  --output="$OUT/pgn-clipboard-source.zip" HEAD \
  Install.command Uninstall.command README.md app
(cd "$OUT" && shasum -a 256 pgn-clipboard-source.zip > pgn-clipboard-source.sha256)
echo "Release assets: $OUT/pgn-clipboard-source.zip and .sha256"
