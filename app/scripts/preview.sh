#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGN_PREVIEW=1 PGN_BUILD_DIR="$ROOT/build-preview" "$ROOT/scripts/build.sh"
echo 'Opening an isolated preview with synthetic games. Production settings and history are untouched.'
/usr/bin/open -n "$ROOT/build-preview/PGN Clipboard.app"
