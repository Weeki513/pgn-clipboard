# Changelog

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
