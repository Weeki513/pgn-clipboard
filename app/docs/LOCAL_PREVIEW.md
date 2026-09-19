# PGN Clipboard 1.4 — local review

Nothing has been pushed, released or deployed. The installed 1.3.2 app has not been replaced.

## Open

The separately identified **PGN Clipboard — Preview** window is open. To rebuild/reopen it, run `./app/scripts/preview.sh` from the repository root. Its app bundle is `app/build-preview/PGN Clipboard.app`.

The preview uses `design.pivnev.pgnclipboard.preview`, a separate sandbox container and preferences, and starts with 125 synthetic imports. One additional `Local-review.pgn` was imported end to end for QA. The preview currently watches only `/tmp/pgn-14-preview-imports`; you can add synthetic PGNs there or choose your own test folder. The production app still has its original watched folder and JSON history.

## Try

LATEST IMPORT previews the current formatting immediately. Its Trash note describes the policy for future imports, not the already-imported file. All interface text uses 12-point monospace; action feedback resets after two seconds, while tabs and retention choices stay selected. Hover uses green text in square brackets.

The entire app window uses ASCII glyphs for frames, controls, tabs and scrollbars. The supplied metal clip is a transparent child panel extending beyond the actual window. Controls and retention settings share one tab; Recent Imports is the other tab. System menus and dialogs retain macOS behavior.

- Recent Imports: search a filename or any text inside a PGN, including players/events; use Previous/Next for 50-row pages.
- Select a row and try Copy formatted versus Copy raw. Change Strip headers / Auto headers in Controls, then copy the same history record again.
- Select a fragment inside the formatted preview and press Command-C, or use its standard context menu.
- Scroll the history list and the selected PGN independently; select several rows with Command/Shift-click. Select page affects only the current page.
- Controls → Auto-delete history: Never is the default. Choose 7/30/90/180/365 days; the choice saves immediately to remove expired demo history. Deletion is permanent; only the preview database is affected.
- Disk usage appears above the history list. SQLite reuses freed pages, so physical size may not immediately decrease after deletion.

## Verification

169 automated checks passed: 70 watcher/formatting/history checks, 26 SQLite checks, 9 icon checks, 59 native menu/UI checks, and 5 installer checks. Both normal and preview bundles build and pass strict signature verification.

SQLite tests cover migration and rollback, interrupted cleanup recovery, corrupt JSON preservation, raw byte content, 1,200 additional imports without eviction, bounded pages, Unicode/literal search, retention boundaries, concurrent access and exact selected-ID deletion. The 1,200-import exercise took 0.25 seconds on this Mac (a local test result, not a cross-device benchmark).

Live native QA verified raw and formatted clipboard contents, Command-C of the selected `Demo White` fragment, search beyond the first page, native scrollbar/wheel movement, and an actual sandboxed import → SQLite → clipboard → Trash. The previous system clipboard was restored after testing.

A single idle snapshot with 126 demo imports showed 0.0% CPU and roughly 99 MiB RSS. The app uses AppKit, system SQLite and one static image, with no web view, animation loop, network service or database server.

## Migration on a future normal update

The normal build migrates existing JSON in a SQLite transaction. Only after a durable commit is the exact legacy source retired. Fingerprinted migrations recover from an interruption after commit without re-adding deleted records. A corrupt source or failed transaction remains available and raises an error. This migration was tested on isolated fixtures; your production history has not been migrated by the preview.
