#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/install-support.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
make_bundle() {
  mkdir -p "$1/Contents"
  cat > "$1/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>design.pivnev.pgnclipboard</string><key>CFBundleExecutable</key><string>PGNClipboard</string></dict></plist>
PLIST
  echo "$2" > "$1/version"
}
make_bundle "$TEST_DIR/staged.app" new
pgn_validate_bundle "$TEST_DIR/staged.app"
pgn_replace_bundle "$TEST_DIR/staged.app" "$TEST_DIR/installed.app" "$TEST_DIR/backup.app"
[[ "$(cat "$TEST_DIR/installed.app/version")" == new && ! -e "$TEST_DIR/backup.app" ]]
echo 'PASS: Fresh installation places the new bundle at its final path'
make_bundle "$TEST_DIR/staged.app" newer
pgn_replace_bundle "$TEST_DIR/staged.app" "$TEST_DIR/installed.app" "$TEST_DIR/backup.app"
[[ "$(cat "$TEST_DIR/installed.app/version")" == newer && "$(cat "$TEST_DIR/backup.app/version")" == new ]]
echo 'PASS: Update replaces the complete bundle and retains a recovery copy'
rm -rf "$TEST_DIR/backup.app"
make_bundle "$TEST_DIR/staged.app" broken
mv() {
  if [[ "$1" == "$TEST_DIR/staged.app" ]]; then return 1; fi
  command mv "$@"
}
if pgn_replace_bundle "$TEST_DIR/staged.app" "$TEST_DIR/installed.app" "$TEST_DIR/backup.app"; then exit 1; fi
[[ "$(cat "$TEST_DIR/installed.app/version")" == newer && ! -e "$TEST_DIR/backup.app" ]]
unset -f mv
echo 'PASS: Failed replacement restores the previous installed version'
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.unrelated' "$TEST_DIR/staged.app/Contents/Info.plist"
if pgn_validate_bundle "$TEST_DIR/staged.app"; then exit 1; fi
echo 'PASS: Unrelated apps are rejected'
ln -s "$TEST_DIR/installed.app" "$TEST_DIR/link.app"
if pgn_validate_bundle "$TEST_DIR/link.app"; then exit 1; fi
echo 'PASS: Symlink destinations are rejected'
echo '5 installer checks passed using temporary bundles only.'
