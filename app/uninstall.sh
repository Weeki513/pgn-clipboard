#!/bin/bash
set -euo pipefail
trap 'echo "Uninstall failed at line $LINENO. See the error above." >&2' ERR
[[ "$(uname -s)" == Darwin && "$(id -u)" != 0 ]] || { echo 'Run on macOS as your normal user, without sudo.' >&2; exit 1; }
APP="$HOME/Applications/PGN Clipboard.app"
if [[ ! -e "$APP" ]]; then echo 'PGN Clipboard is not installed in ~/Applications.'; exit 0; fi
ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
[[ "$ID" == design.pivnev.pgnclipboard && "$EXE" == PGNClipboard ]] || {
  echo 'This is a different/legacy app. Refusing to remove it with this uninstaller.' >&2; exit 1;
}
# Stop processing before launching the app in its reset-only mode.
/usr/bin/pkill -x PGNClipboard 2>/dev/null || true
for ((attempt=0; attempt<50; attempt++)); do
  /usr/bin/pgrep -x PGNClipboard >/dev/null || break
  /bin/sleep 0.1
done
if /usr/bin/pgrep -x PGNClipboard >/dev/null; then echo 'Quit PGN Clipboard and retry.' >&2; exit 1; fi
# The sandboxed app unregisters itself and clears its own saved bookmark/settings.
"$APP/Contents/MacOS/PGNClipboard" --uninstall
rm -rf "$APP"
echo 'Removed PGN Clipboard. Login item and saved folder settings were reset.'
echo 'Your PGN files and clipboard were not changed. macOS may retain an empty app container.'
