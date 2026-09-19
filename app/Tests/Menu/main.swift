import AppKit

let application = NSApplication.shared
let suite = "PGNClipboard.MenuTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    guard value() else { fatalError(label) }
    print("PASS: \(label)")
}
let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("menu-history-\(UUID().uuidString)")
let historyURL = testFolder.appendingPathComponent("history.json")
let history = RecentImports(url: historyURL)
defer { try? FileManager.default.removeItem(at: testFolder) }
var delegate = AppDelegate(defaults: defaults, history: history)
let menu = NSMenu()
menu.autoenablesItems = false
func items() -> (NSMenuItem, NSMenuItem) {
    delegate.menuWillOpen(menu)
    menu.update()
    return (menu.item(withTitle: "Strip headers")!, menu.item(withTitle: "Auto headers")!)
}
func click(_ item: NSMenuItem) { _ = (item.target as? NSObject)?.perform(item.action) }
var (strip, auto) = items()
expect(strip.state == .off && auto.state == .off, "Menu defaults both options off")
expect(strip.isEnabled && !auto.isEnabled, "Menu disables dependent option")
click(auto)
expect(!defaults.bool(forKey: "autoHeaders"), "Disabled action guarded even if invoked directly")
click(strip)
(strip, auto) = items()
expect(strip.state == .on && auto.isEnabled, "Strip menu action enables Auto headers")
click(auto)
(strip, auto) = items()
expect(auto.state == .on && defaults.bool(forKey: "autoHeaders"), "Auto menu action persists preference")
click(strip)
(strip, auto) = items()
expect(strip.state == .off && !auto.isEnabled && auto.state == .on, "Disabling strip retains inactive auto preference")
delegate = AppDelegate(defaults: defaults, history: history)
(strip, auto) = items()
expect(strip.state == .off && auto.state == .on && !auto.isEnabled, "Relaunch restores gated preferences")
click(strip)
(strip, auto) = items()
expect(strip.state == .on && auto.state == .on && auto.isEnabled, "Re-enabling strip restores auto setting")
click(auto)
(strip, auto) = items()
expect(auto.state == .off && auto.isEnabled, "Auto can be turned off independently")
expect(defaults.bool(forKey: "stripHeaders") && !defaults.bool(forKey: "autoHeaders"), "Both preferences stored independently")

delegate.menuWillOpen(menu)
let trash = menu.item(withTitle: "Move original to Trash")!
expect(trash.state == .on, "Trash defaults ON")
click(trash)
delegate = AppDelegate(defaults: defaults, history: history)
delegate.menuWillOpen(menu)
expect(menu.item(withTitle: "Move original to Trash")!.state == .off, "Trash OFF survives relaunch")
try history.record(RecentImport(id: UUID(), filename: "example.pgn", importedAt: Date(), original: "original", clipboardText: "formatted"))
delegate.menuWillOpen(menu)
let recent = menu.item(withTitle: "Recent Imports")!.submenu!
expect(recent.items.count == 1 && recent.items[0].title.contains("example.pgn — "), "Recent menu displays filename and timestamp")
let copy = recent.items[0].submenu!.item(withTitle: "Copy formatted")!
let raw = recent.items[0].submenu!.item(withTitle: "Copy raw")!
expect(copy.isEnabled && copy.representedObject as? String == "original" && copy.action != raw.action, "Menu offers formatted and raw actions from the original")

// Real AppKit history list, asynchronous queries, native selection and scrolling.
let secondID = UUID()
let source = "[Event \"Preview\"]\n[White \"A\"]\n[Black \"B\"]\n\n1. e4\n e5 *\n"
try history.record(RecentImport(id: secondID, filename: "second.pgn", importedAt: Date(), original: source, clipboardText: "outdated snapshot"))
let panel = RecentImportsView(history: history)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 580), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
window.contentView = panel
var copied = ""
var options = HeaderOptions(stripHeaders: true, autoHeaders: true)
panel.copyText = { copied = $0; return true }; panel.options = { options }
func waitFor(_ label: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    expect(condition(), label)
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func button(_ label: String) -> NSButton { descendants(panel).compactMap { $0 as? NSButton }.first { $0.title == label }! }
waitFor("History loads two rows asynchronously") { panel.table.numberOfRows == 2 }
panel.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
waitFor("Selecting a row loads its full original") { panel.detail.entry?.id == secondID }
panel.detail.formatted.performClick(nil)
expect(copied == "Game 1 — □ A vs B ■\n\n1. e4 e5 *", "Formatted copy applies current options instead of the saved snapshot")
options = HeaderOptions(stripHeaders: true, autoHeaders: false)
panel.detail.refreshPreview()
expect(panel.detail.text.string == "1. e4 e5 *", "Preview updates immediately with current formatting")
panel.detail.isLatest = true
var trashPreview = true
panel.detail.trashEnabled = { trashPreview }
panel.detail.refreshPreview()
expect(panel.detail.title.stringValue.hasPrefix("LATEST IMPORT / ") && panel.detail.subtitle.stringValue.contains("-> Trash"), "Latest preview labels next-import Trash policy")
trashPreview = false; panel.detail.refreshPreview()
expect(panel.detail.subtitle.stringValue.contains("keep original"), "Trash preview updates without altering the stored source")
panel.detail.formatted.performClick(nil)
expect(copied == "1. e4 e5 *", "Changing formatting takes effect immediately for history copy")
panel.detail.raw.performClick(nil)
expect(copied == source, "Raw copy preserves exact headers, spaces and trailing newline")
expect((panel.detail.raw.cell as? ASCIIButtonCell)?.feedbackActive == true, "Action button briefly shows active feedback")
waitFor("Action feedback returns to default automatically") { (panel.detail.raw.cell as? ASCIIButtonCell)?.feedbackActive == false }
expect(panel.detail.raw.state == .off, "Copy action does not latch as a toggle")
expect(!panel.detail.text.isEditable && panel.detail.text.isSelectable, "Full preview is selectable and read-only")
panel.detail.text.setSelectedRange(NSRange(location: 0, length: 7))
panel.reload()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
expect(panel.detail.text.selectedRange() == NSRange(location: 0, length: 7), "Background refresh preserves text selection on the same import")
button("Delete (1)").performClick(nil)
waitFor("Delete affects only the selected row") { panel.table.numberOfRows == 1 }
expect(try! history.entry(id: secondID) == nil, "Deleted record is absent from SQLite")
button("Select page").performClick(nil); button("Delete (1)").performClick(nil)
waitFor("Empty history disables copy and deletion") { panel.table.numberOfRows == 0 && !panel.detail.raw.isEnabled }
for index in 0..<80 { try history.record(RecentImport(id: UUID(), filename: "\(index).pgn", importedAt: Date(), original: String(repeating: "Annotation line\n", count: 100), clipboardText: "")) }
panel.reload()
waitFor("List is capped at one 50-row page") { panel.table.numberOfRows == 50 }
window.contentView?.layoutSubtreeIfNeeded()
expect(panel.detail.frame.width > panel.frame.width * 0.5, "Preview fills the available right column")
let listScroll = panel.table.enclosingScrollView!
panel.table.scrollRowToVisible(49)
expect(listScroll.contentView.bounds.origin.y > 0 && listScroll.contentView.bounds.height > 100, "History list scrolls vertically within its viewport")
button("Next").performClick(nil)
waitFor("Next page loads remaining records") { panel.table.numberOfRows == 30 }
button("Previous").performClick(nil)
waitFor("Previous page returns to first 50 records") { panel.table.numberOfRows == 50 }
panel.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
waitFor("Long original loads for preview scrolling") { panel.detail.entry != nil }
window.contentView?.layoutSubtreeIfNeeded()
panel.detail.text.layoutManager?.ensureLayout(for: panel.detail.text.textContainer!)
panel.detail.text.scrollToEndOfDocument(nil)
expect(panel.detail.text.enclosingScrollView!.contentView.bounds.origin.y > 0, "Long PGN preview scrolls independently")
panel.search.stringValue = "79.pgn"
panel.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
waitFor("Debounced search finds the matching import") { panel.table.numberOfRows == 1 }
button("Select page").performClick(nil); button("Delete (1)").performClick(nil)
waitFor("Filtered deletion leaves an empty result") { panel.table.numberOfRows == 0 }
expect(try! history.page().totalCount == 79, "Filtered selection never deletes hidden records")
let oldID = UUID()
try history.record(RecentImport(id: oldID, filename: "old.pgn", importedAt: Date().addingTimeInterval(-90 * 86400), original: "old", clipboardText: "old"))
let settings = HistorySettingsView(history: history)
let retention = settings.choices.first!
var changed = false
settings.didChange = { changed = true }
waitFor("Retention settings load without blocking the UI") { retention.isEnabled }
expect(settings.selectedDays == 0, "Settings initially select never delete")
settings.choices.first { $0.tag == 30 }!.performClick(nil)
waitFor("Applying retention notifies history views") { changed }
expect(try! history.retentionDays() == 30 && history.entry(id: oldID) == nil, "Settings action persists policy and removes expired imports")
changed = false; settings.choices.first { $0.tag == 0 }!.performClick(nil)
waitFor("Never-delete setting can be restored") { changed }
expect(try! history.retentionDays() == 0, "Never-delete policy persists")
// ASCII surfaces keep AppKit actions/selection and the clip is a real attached window.
expect(panel.detail.formatted.cell is ASCIIButtonCell && !panel.detail.formatted.isBordered, "Copy buttons render ASCII cells without native bezels")
expect(panel.search.isBordered == false && panel.search.focusRingType == .none, "Search has no native rounded field chrome")
expect(panel.table.enclosingScrollView?.verticalScroller is ASCIIScroller, "History uses a symbolic scroller with native tracking")
expect(panel.detail.text.enclosingScrollView?.verticalScroller is ASCIIScroller, "PGN preview uses the same symbolic scrollbar")
let asciiCheck = ASCIIButton(checkboxWithTitle: "Toggle", target: nil, action: nil)
asciiCheck.performClick(nil)
expect(asciiCheck.state == .on, "ASCII checkbox preserves native toggle behavior")
let shell = ClipboardWindow(contentRect: NSRect(x: 120, y: 120, width: 1080, height: 690), styleMask: [.borderless, .resizable, .miniaturizable], backing: .buffered, defer: false)
shell.attachClip()
expect(shell.canBecomeKey && !shell.styleMask.contains(.titled), "ASCII window accepts keyboard focus without a native titlebar")
expect(shell.clipPanel?.parent === shell && shell.childWindows?.count == 1, "Metal clip is one attached child panel")
expect(shell.clipPanel!.frame.maxY > shell.frame.maxY && shell.clipPanel!.frame.minY < shell.frame.maxY, "Metal clip truly straddles the window boundary")
shell.setFrame(NSRect(x: 220, y: 160, width: 1120, height: 720), display: false)
shell.updateClipFrame()
expect(abs(shell.clipPanel!.frame.midX - shell.frame.midX) < 0.01 && abs(shell.clipPanel!.frame.minY - (shell.frame.maxY - 48)) < 0.01, "Clip remains centered after moving and resizing")
shell.windowWillClose(Notification(name: NSWindow.willCloseNotification))
expect(shell.clipPanel?.isVisible == false, "Clip hides with the parent window")
// Exercise the actual Controls/History layout, including async history refreshes.
_ = delegate.perform(NSSelectorFromString("showControls"))
let controlsWindow = application.windows.first { $0.title == "PGN Clipboard" }!
let controlsBoard = controlsWindow.contentView!
let pageHost = descendants(controlsBoard).compactMap { $0 as? PageHostView }.first!
let initialFrame = controlsWindow.frame
var stable = true
for index in 0..<60 {
    pageHost.selectPage(index.isMultiple(of: 2) ? "recent" : "controls")
    controlsBoard.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    stable = stable && abs(controlsWindow.frame.width - initialFrame.width) < 1
        && abs(pageHost.frame.width - (controlsBoard.bounds.width - 36)) < 1
        && pageHost.subviews.allSatisfy { abs($0.frame.width - pageHost.bounds.width) < 1 }
}
expect(stable, "Repeated real page switches preserve window and both page widths")
controlsWindow.setContentSize(NSSize(width: 1200, height: 760))
controlsBoard.layoutSubtreeIfNeeded()
pageHost.selectPage("recent"); controlsBoard.layoutSubtreeIfNeeded()
expect(pageHost.subviews.allSatisfy { abs($0.frame.width - pageHost.bounds.width) < 1 }, "Both pages follow a resized viewport")
expect(controlsWindow.contentMinSize.width >= 1000, "Content minimum width survives page changes")
controlsWindow.orderOut(nil)
print("\(checks) total menu and history panel checks passed.")
