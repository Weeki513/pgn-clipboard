#!/bin/bash
set -euo pipefail
trap 'echo "Build failed at line $LINENO. See the error above." >&2' ERR
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
[[ "${MACOS_VERSION%%.*}" -ge 13 ]] || { echo 'macOS 13 or later is required.' >&2; exit 1; }
command -v swiftc >/dev/null || { echo 'Install Apple Command Line Tools first: xcode-select --install' >&2; exit 1; }
OUT="${PGN_BUILD_DIR:-$ROOT/build}"
mkdir -p "$OUT"
# Sign outside cloud-synced folders, which can attach Finder metadata mid-build.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pgn-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/PGN Clipboard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT/module-cache"
SWIFT_FLAGS=(-swift-version 5)
if [[ "${PGN_PREVIEW:-0}" == 1 ]]; then SWIFT_FLAGS+=(-D PGN_PREVIEW); fi
echo 'Compiling PGN Clipboard…'
swiftc "${SWIFT_FLAGS[@]}" -O -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$OUT/module-cache" \
  "$ROOT/Sources/Watcher.swift" "$ROOT/Sources/History.swift" "$ROOT/Sources/StatusIcon.swift" "$ROOT/Sources/RecentImportsView.swift" "$ROOT/Sources/BoardView.swift" "$ROOT/Sources/AppDelegate.swift" "$ROOT/Sources/main.swift" \
  -framework AppKit -framework ServiceManagement -o "$APP/Contents/MacOS/PGNClipboard"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ "${PGN_PREVIEW:-0}" == 1 ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier design.pivnev.pgnclipboard.preview' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName PGN Clipboard Preview' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :PGNPreview bool true' "$APP/Contents/Info.plist"
fi
cp "$ROOT/Resources/ClipboardClip.png" "$APP/Contents/Resources/ClipboardClip.png"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
# Remove Finder metadata from this generated bundle before signing.
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --sign "${PGN_SIGN_IDENTITY:--}" --options runtime \
  --entitlements "$ROOT/Resources/Entitlements.plist" "$APP"
/usr/bin/codesign --verify --strict "$APP"
DEST="$OUT/PGN Clipboard.app"
if [[ -e "$DEST" ]]; then
  ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
  [[ "$ID" == design.pivnev.pgnclipboard || "$ID" == design.pivnev.pgnclipboard.preview ]] || { echo "Refusing to overwrite unknown app: $DEST" >&2; exit 1; }
  rm -rf "$DEST"
fi
mv "$APP" "$DEST"
echo "Built: $DEST"
