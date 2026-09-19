#!/bin/bash
set -euo pipefail
trap 'echo "Installation failed at line $LINENO. See the error above." >&2' ERR
ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
[[ "${MACOS_VERSION%%.*}" -ge 13 ]] || { echo 'macOS 13 or later is required.' >&2; exit 1; }
[[ "$(id -u)" != 0 ]] || { echo 'Run as your normal user, without sudo.' >&2; exit 1; }
source "$ROOT/scripts/install-support.sh"
APP="$HOME/Applications/PGN Clipboard.app"
UPDATING=false
if [[ -e "$APP" || -L "$APP" ]]; then
  pgn_validate_bundle "$APP" || { echo 'A different or legacy app exists at the install path. Refusing to replace it.' >&2; exit 1; }
  UPDATING=true
fi
for LABEL in design.pivnev.pgnclipboard design.pivnev.pgnclipboard.agent; do
  if [[ -e "$HOME/Library/LaunchAgents/$LABEL.plist" ]] || /bin/launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "An older PGN LaunchAgent is still installed: $LABEL. Remove it before installing this version." >&2
    exit 1
  fi
done
"$ROOT/scripts/build.sh"
mkdir -p "$HOME/Applications"
STAGE="$(mktemp -d "$HOME/Applications/.pgn-install.XXXXXX")"
# Keep a backup if replacement or restoration fails; never delete the only copy.
cleanup() {
  if [[ -e "$STAGE/Previous.app" ]]; then
    echo "Previous app preserved at: $STAGE/Previous.app" >&2
  else
    rm -rf "$STAGE"
  fi
}
trap cleanup EXIT
/usr/bin/ditto --norsrc --noextattr "${PGN_BUILD_DIR:-$ROOT/build}/PGN Clipboard.app" "$STAGE/PGN Clipboard.app"
/usr/bin/codesign --verify --strict "$STAGE/PGN Clipboard.app"
pgn_validate_bundle "$STAGE/PGN Clipboard.app"
if $UPDATING; then
  # Build and verify first, then stop the watcher without resetting preferences,
  # its security-scoped folder bookmark, history, or login-item registration.
  /usr/bin/pkill -x PGNClipboard 2>/dev/null || true
  for ((attempt=0; attempt<50; attempt++)); do
    /usr/bin/pgrep -x PGNClipboard >/dev/null || break
    /bin/sleep 0.1
  done
  if /usr/bin/pgrep -x PGNClipboard >/dev/null; then
    echo 'Quit PGN Clipboard and retry. The installed app has not been replaced.' >&2
    exit 1
  fi
fi
pgn_replace_bundle "$STAGE/PGN Clipboard.app" "$APP" "$STAGE/Previous.app"
rm -rf "$STAGE/Previous.app"
echo "Installed: $APP"
if $UPDATING; then
  echo 'Updated. Your watched folder, settings, and Recent Imports have been preserved.'
else
  echo 'Choose Downloads in the system folder picker. Existing PGNs will be ignored.'
  echo 'Use the chess pawn in the menu bar to enable Launch at Login.'
fi
/usr/bin/open "$APP"
