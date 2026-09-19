#!/bin/bash
# Shared installer operations; sourcing this file does not change the machine.
pgn_validate_bundle() {
  local app_path="$1" bundle_id executable
  [[ -d "$app_path" && ! -L "$app_path" ]] || return 1
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist") || return 1
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist") || return 1
  [[ "$bundle_id" == design.pivnev.pgnclipboard && "$executable" == PGNClipboard ]]
}

pgn_replace_bundle() {
  local staged_app="$1" installed_app="$2" backup_app="$3"
  [[ -d "$staged_app" && ! -e "$backup_app" ]] || return 1
  if [[ -e "$installed_app" ]]; then
    mv "$installed_app" "$backup_app" || return 1
  fi
  if mv "$staged_app" "$installed_app"; then
    return 0
  fi
  if [[ -e "$backup_app" ]]; then
    if ! mv "$backup_app" "$installed_app"; then
      echo "Could not restore the previous app. It is preserved at: $backup_app" >&2
    fi
  fi
  return 1
}
