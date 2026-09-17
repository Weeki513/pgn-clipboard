#!/bin/bash
set -euo pipefail
trap 'echo "Installation failed at line $LINENO. See the error above." >&2' ERR
ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
[[ "${MACOS_VERSION%%.*}" -ge 13 ]] || { echo 'macOS 13 or later is required.' >&2; exit 1; }
[[ "$(id -u)" != 0 ]] || { echo 'Run as your normal user, without sudo.' >&2; exit 1; }
APP="$HOME/Applications/PGN Clipboard.app"
[[ ! -e "$APP" ]] || { echo 'PGN Clipboard already exists. Run Uninstall.command before reinstalling.' >&2; exit 1; }
for LABEL in design.pivnev.pgnclipboard design.pivnev.pgnclipboard.agent; do
  if [[ -e "$HOME/Library/LaunchAgents/$LABEL.plist" ]] || /bin/launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "An older PGN LaunchAgent is still installed: $LABEL. Remove it before installing this version." >&2
    exit 1
  fi
done
"$ROOT/scripts/build.sh"
mkdir -p "$HOME/Applications"
STAGE="$(mktemp -d "$HOME/Applications/.pgn-install.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto --norsrc --noextattr "${PGN_BUILD_DIR:-$ROOT/build}/PGN Clipboard.app" "$STAGE/PGN Clipboard.app"
/usr/bin/codesign --verify --strict "$STAGE/PGN Clipboard.app"
mv "$STAGE/PGN Clipboard.app" "$APP"
echo "Installed: $APP"
echo 'Choose Downloads in the system folder picker. Existing PGNs will be ignored.'
echo 'Use the chess pawn in the menu bar to enable Launch at Login.'
/usr/bin/open "$APP"
