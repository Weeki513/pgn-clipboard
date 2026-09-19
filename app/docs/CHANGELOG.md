# Changelog

## 1.4.1 — 2026-09-19

- Restore the complete original ClipboardClip.png; the 1.4.0 resource contained corrupted image data.
- Validate PNG chunk checksums and compressed image data before testing and packaging releases.

## 1.4.0 — 2026-09-19

- Replace the ten-entry JSON store with SQLite and transactional migration.
- Add background search, 50-row pages, on-demand originals, and disk usage.
- Add never-delete or age-based retention with startup/import/hourly cleanup.
- Copy using current formatting or copy the exact raw source; support native text selection and copy.
- Draw the app interface with ASCII frames, buttons, tabs, checkboxes and scrollbars; keep native keyboard and text selection behavior.
- Attach the supplied metal clip as a transparent child panel extending outside the window. Merge retention settings into Controls.
- Replace nested preview cards with a native scrolling list and full-height preview.
- Refresh the dark macOS window using the supplied clipboard asset and monospaced typography.
- Add an isolated preview build with synthetic history for review before release.
- Use a consistent monospace size and cyan accent, live formatted previews, hover states, and brief copy feedback.
- Keep window dimensions stable when switching tabs and simplify retention settings.
- Restore executable permissions for build, test, and preview scripts; verify source-package permissions in CI.

## 1.3.2

- Let Install.command update an existing native app without uninstalling or resetting settings, folder access, history, or login registration.
- Build and verify before stopping the old app; restore the previous bundle if replacement fails.
- Refuse to overwrite an unrelated or legacy app.

## 1.3.1

- Mark White with □ and Black with ■ in auto headers: `Game 1 — □ Player1 vs Player2 ■`.
- Add auto headers to single-game files too.
- Normalize whitespace between moves on copy, with or without stripping headers.
- Preserve comment contents, semicolon-comment line endings, and separation between games.

## 1.3.0

- Add Controls and Recent Imports tabs to the main application window, with a direct menu shortcut.
- Show original PGN previews capped at five visible lines with independent vertical scrolling.
- Add Copy feedback, individual Delete, selection checkboxes, Select all, and Delete Selected.
- Persist history deletion atomically without touching source files or clipboard contents.
- Add history panel interaction tests and refresh README screenshots using synthetic games.

## 1.2.0

- Add Recent Imports with timestamps and Copy for the last 10 imports, persisted locally with original and formatted content.
- Add a persistent Move original to Trash option, enabled by default.
- Serialize watcher operations and save history atomically before clipboard/Trash; prevent duplicate retries and repeat imports of retained files.
- Cover simultaneous scans, rapid arrivals, retention, reload after source removal, persistence failures, and menu settings.

## 1.1.0

- Add persistent Strip headers and dependent Auto headers checkboxes to the menu and Controls window.
- Preserve moves and annotations while optionally adding numbered, player-aware multi-game separators.
- Add formatting and watcher integration coverage, refreshed native screenshots, and a stable latest-release download asset.

## 1.0.3

- Prepare the first public GitHub release with a quick start, project banner, and application screenshots.
- Adopt the PolyForm Noncommercial License 1.0.0 and add contribution and independence statements.

## 1.0.2

- Add a full-resolution application icon and native ICNS resources.
- Add prominent clickable creator and feedback links to the controls window and menu.
- Simplify the package root to Install.command, Uninstall.command, and README.md, with supporting files in subfolders.

## 1.0.1

- Replace the Unicode menu title with an 18-point vector template pawn icon. The system tints it for the menu bar appearance; pause/error states also use template images.
- Use a fixed square status item, set its visibility explicitly on launch, and add an accessibility label.
- Add a controls window with folder selection, pause/resume, retry, Launch at Login, and an option to restore the menu icon.
- Reopening the app shows controls even when the menu bar icon is hidden or inaccessible.
- Show controls after initial folder setup.
- Add rasterization checks for all three icon states.

## 1.0.0

- Initial native macOS source release: sandboxed folder access, stable-file detection, clipboard verification, native Trash handling, login item support, installer, and uninstaller.
