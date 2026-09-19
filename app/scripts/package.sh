#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:?Usage: package.sh OUTPUT_DIRECTORY}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
# Package the committed source, never local build products or credentials.
# Validate the exact committed image, not a possibly different working copy.
CHECK_DIR="$(mktemp -d)"
trap 'rm -r "$CHECK_DIR"' EXIT
git -C "$ROOT" show HEAD:app/Resources/ClipboardClip.png > "$CHECK_DIR/ClipboardClip.png"
python3 "$ROOT/app/Tests/resources.py" "$CHECK_DIR/ClipboardClip.png"
git -C "$ROOT" archive --format=zip --prefix=pgn-clipboard/ \
  --output="$OUT/pgn-clipboard-source.zip" HEAD \
  Install.command Uninstall.command README.md app
(cd "$OUT" && shasum -a 256 pgn-clipboard-source.zip > pgn-clipboard-source.sha256)
echo "Release assets: $OUT/pgn-clipboard-source.zip and .sha256"
