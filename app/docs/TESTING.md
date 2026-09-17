# Testing

Run on macOS with Apple's Command Line Tools or Xcode:

```sh
./app/scripts/test.sh
./app/scripts/build.sh
```

## Automated coverage

The watcher suite runs 21 checks in a temporary directory, using injected clipboard and Trash operations. It covers existing files, stability delays, interrupted writes, case-insensitive extensions, invalid/incomplete PGN, failed clipboard writes, explicit retries, failed Trash operations, symlinks, size limits, browser rename behavior, pause/resume baseline, CRLF, BOM, required headers, file-change detection, batch ordering, invalid UTF-8, and inaccessible folders.

The icon suite runs 9 checks: the normal, paused, and error images must use template tinting, fit an 18-point canvas, and actually rasterize nontransparent pixels. This guards against empty or font-dependent menu bar content.

Shell scripts are syntax-checked and property lists are validated. The build verifies the generated app's signature. GitHub Actions runs the test and build commands on a macOS runner.

## Manual release checklist

Use a dedicated test folder with synthetic PGNs, not a folder containing important downloads. Preserve your clipboard before testing.

- First launch: choose the test folder; existing PGNs stay untouched.
- Confirm the pawn is visible with light and dark menu bar appearances. Check standard and notched displays where available.
- Reopen the app: the controls window appears. Close it and reopen again.
- Exercise pause/resume, choose-folder, retry, and Show Menu Bar Icon.
- Create a new complete PGN: clipboard matches its text and the original is in system Trash.
- Copy a partial file in stages, or rename a `.crdownload` file to `.pgn`.
- Relaunch: folder access is restored, existing files stay untouched, and new files still process.
- Enable Launch at Login, check its status, and test login/reboot on a dedicated machine.
- Uninstall while Launch at Login is enabled; confirm the app exits, its login item is disabled, and preferences are reset.
- For prebuilt releases, separately verify Developer ID signing, notarization, architecture compatibility, and Gatekeeper handling of the downloaded artifact.

A release should be tested across its supported OS and hardware matrix. A successful local build does not establish compatibility on every supported Mac. macOS can hide menu bar items when space is limited; reopening the app must always provide access to controls.
