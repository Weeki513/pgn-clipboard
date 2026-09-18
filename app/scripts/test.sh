#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${PGN_BUILD_DIR:-$ROOT/build}"
mkdir -p "$OUT/module-cache"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$OUT/module-cache" \
  "$ROOT/Sources/Watcher.swift" "$ROOT/Tests/main.swift" -o "$OUT/watcher-tests"
"$OUT/watcher-tests"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$OUT/module-cache" \
  "$ROOT/Sources/StatusIcon.swift" "$ROOT/Tests/StatusIcon/main.swift" \
  -framework AppKit -o "$OUT/icon-tests"
"$OUT/icon-tests"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$OUT/module-cache" \
  "$ROOT/Sources/Watcher.swift" "$ROOT/Sources/StatusIcon.swift" "$ROOT/Sources/AppDelegate.swift" \
  "$ROOT/Tests/Menu/main.swift" -framework AppKit -framework ServiceManagement -o "$OUT/menu-tests"
"$OUT/menu-tests"
for SCRIPT in "$ROOT"/*.sh "$ROOT"/../*.command "$ROOT"/scripts/*.sh; do bash -n "$SCRIPT"; done
/usr/bin/plutil -lint "$ROOT/Resources/Info.plist" "$ROOT/Resources/Entitlements.plist"
