import Foundation
import Darwin

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    checks += 1
    guard condition() else { fputs("FAIL: \(description)\n", stderr); exit(1) }
    print("PASS: \(description)")
}
let game = "[Event \"Test\"]\n[White \"White\"]\n[Black \"Black\"]\n\n1. e4 e5 2. Nf3 *\n"
let root = FileManager.default.temporaryDirectory.appendingPathComponent("pgn-tests-\(UUID().uuidString)")
let downloads = root.appendingPathComponent("Downloads")
let trash = root.appendingPathComponent("Trash")
try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
func write(_ name: String, _ content: String = game) throws -> URL {
    let url = downloads.appendingPathComponent(name)
    try Data(content.utf8).write(to: url); return url
}
let old = try write("old.pgn")
var clipboard = "previous clipboard"
var copySucceeds = true
var trashSucceeds = true
var copies = 0
var errors = [String]()
let watcher = Watcher(folder: downloads, copy: { text in
    copies += 1
    if !copySucceeds { return false }; clipboard = text; return true
}, trash: { url in
    if !trashSucceeds { throw CocoaError(.fileWriteNoPermission) }
    let dest = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
    try FileManager.default.moveItem(at: url, to: dest)
})
watcher.report = { text, error in if error { errors.append(text) } }
let start = Date()
try watcher.baseline(now: start)
try watcher.scan(now: start.addingTimeInterval(10))
expect(FileManager.default.fileExists(atPath: old.path) && copies == 0, "Existing PGNs ignored")
let fresh = try write("fresh.PGN")
try watcher.scan(now: start.addingTimeInterval(11))
try watcher.scan(now: start.addingTimeInterval(13))
expect(FileManager.default.fileExists(atPath: fresh.path), "Wait at least three seconds")
try watcher.scan(now: start.addingTimeInterval(14))
expect(!FileManager.default.fileExists(atPath: fresh.path) && clipboard == game, "New uppercase PGN copied intact and moved")
let slow = try write("slow.pgn", "[Event \"Test\"]")
try watcher.scan(now: start.addingTimeInterval(15))
try Data(game.utf8).write(to: slow)
try watcher.scan(now: start.addingTimeInterval(17))
try watcher.scan(now: start.addingTimeInterval(19))
expect(FileManager.default.fileExists(atPath: slow.path), "Further writes restart stability interval")
try watcher.scan(now: start.addingTimeInterval(20))
expect(!FileManager.default.fileExists(atPath: slow.path), "Completed slow download processed")
let invalid = try write("invalid.pgn", "not chess")
let partial = try write("partial.pgn", "[Event \"Test\"]\n[White \"A\"]\n[Black \"B\"]\n1. e4")
try watcher.scan(now: start.addingTimeInterval(21)); try watcher.scan(now: start.addingTimeInterval(24))
expect(FileManager.default.fileExists(atPath: invalid.path) && FileManager.default.fileExists(atPath: partial.path), "Invalid and incomplete PGNs left untouched")
let before = copies
copySucceeds = false
let failed = try write("clipboard-failure.pgn")
try watcher.scan(now: start.addingTimeInterval(25)); try watcher.scan(now: start.addingTimeInterval(28))
expect(FileManager.default.fileExists(atPath: failed.path), "Clipboard failure never trashes source")
try watcher.scan(now: start.addingTimeInterval(40))
expect(copies == before + 1, "Failures do not repeatedly overwrite clipboard")
copySucceeds = true
watcher.retryFailures(now: start.addingTimeInterval(41)); try watcher.scan(now: start.addingTimeInterval(44))
expect(!FileManager.default.fileExists(atPath: failed.path), "Explicit retry recovers clipboard failure")
trashSucceeds = false
let moveFailed = try write("trash-failure.pgn")
try watcher.scan(now: start.addingTimeInterval(45)); try watcher.scan(now: start.addingTimeInterval(48))
expect(FileManager.default.fileExists(atPath: moveFailed.path) && !errors.isEmpty, "Trash failure retains file and reports error")
trashSucceeds = true
let target = root.appendingPathComponent("outside.pgn")
try Data(game.utf8).write(to: target)
try FileManager.default.createSymbolicLink(at: downloads.appendingPathComponent("link.pgn"), withDestinationURL: target)
let count = copies
try watcher.scan(now: start.addingTimeInterval(49)); try watcher.scan(now: start.addingTimeInterval(53))
expect(copies == count && FileManager.default.fileExists(atPath: target.path), "Symlinks ignored")
let oversized = try write("huge.pgn", String(repeating: "x", count: PGN.maxBytes + 1))
try watcher.scan(now: start.addingTimeInterval(54)); try watcher.scan(now: start.addingTimeInterval(57))
expect(FileManager.default.fileExists(atPath: oversized.path), "Oversized files retained")
let renamed = try write("browser.crdownload")
try watcher.scan(now: start.addingTimeInterval(58))
let completed = downloads.appendingPathComponent("browser.pgn")
try FileManager.default.moveItem(at: renamed, to: completed)
try watcher.scan(now: start.addingTimeInterval(59)); try watcher.scan(now: start.addingTimeInterval(62))
expect(!FileManager.default.fileExists(atPath: completed.path), "Browser rename picked up")
let paused = try write("during-pause.pgn")
try watcher.baseline(now: start.addingTimeInterval(63)); try watcher.scan(now: start.addingTimeInterval(70))
expect(FileManager.default.fileExists(atPath: paused.path), "Resume baseline ignores files received while paused")
expect(PGN.valid(game.replacingOccurrences(of: "\n", with: "\r\n")), "CRLF PGN accepted")
expect(PGN.valid("\u{FEFF}" + game), "UTF-8 BOM accepted")
expect(!PGN.valid("[Event \"A\"]\n[White \"B\"]\n*"), "Required Black header enforced")
let race = try write("race.pgn")
let stamp = FileStamp.read(race)!
try Data((game + "changed").utf8).write(to: race)
do { _ = try PGN.read(race, expected: stamp); expect(false, "Changed file rejected") }
catch { expect(true, "Changed file rejected") }
let first = try write("batch-a.pgn", game.replacingOccurrences(of: "Test", with: "First"))
let second = try write("batch-b.pgn", game.replacingOccurrences(of: "Test", with: "Second"))
try FileManager.default.setAttributes([.modificationDate: start], ofItemAtPath: first.path)
try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(1)], ofItemAtPath: second.path)
try watcher.scan(now: start.addingTimeInterval(80)); try watcher.scan(now: start.addingTimeInterval(83))
expect(!FileManager.default.fileExists(atPath: first.path) && !FileManager.default.fileExists(atPath: second.path) && clipboard.contains("Second"), "Batch processing leaves newest game in clipboard")
let broken = downloads.appendingPathComponent("bad-encoding.pgn")
try Data([0xff, 0xfe, 0x80]).write(to: broken)
try watcher.scan(now: start.addingTimeInterval(84)); try watcher.scan(now: start.addingTimeInterval(87))
expect(FileManager.default.fileExists(atPath: broken.path), "Invalid UTF-8 retained")
// Formatting matrix: original text is byte-for-byte preserved unless stripping is on.
let moves = "1. e4 e5 2. Nf3 *"
let secondGame = "[Event \"Second\"]\n[White \"Alice\"]\n[Black \"Bob\"]\n[Result \"1-0\"]\n\n1. d4 d5 1-0\n"
let multi = game + "\n" + secondGame
func formatted(_ text: String, _ strip: Bool = true, _ auto: Bool = false) -> String {
    PGNFormatter.format(text, options: HeaderOptions(stripHeaders: strip, autoHeaders: auto))
}
expect(formatted(game, false, false) == game, "Both options off preserves single PGN exactly")
expect(formatted(multi, false, false) == multi, "Both options off preserves multi PGN exactly")
expect(formatted(multi, false, true) == multi, "Saved Auto headers cannot affect output while stripping is off")
expect(!HeaderOptions().autoHeadersEnabled && HeaderOptions(stripHeaders: true).autoHeadersEnabled, "Auto headers enabled only with stripping")
expect(formatted(game) == moves, "Strip headers removes all original tags")
expect(formatted(game, true, true) == moves, "Single game never gets a separator")
expect(formatted(multi) == moves + "\n\n1. d4 d5 1-0", "Multiple games stay separated without auto headings")
expect(formatted(multi, true, true) == "Game 1 — White vs Black\n\n" + moves + "\n\nGame 2 — Alice vs Bob\n\n1. d4 d5 1-0", "Multi-game numbered separators include both players")
expect(formatted(multi + "\n" + game, true, true).contains("Game 3 — White vs Black"), "Three games numbered in source order")
for value in ["", "?", "   "] {
    let missing = secondGame.replacingOccurrences(of: "[White \"Alice\"]", with: "[White \"\(value)\"]")
    expect(formatted(game + missing, true, true).hasSuffix("Game 2\n\n1. d4 d5 1-0"), "Unknown/empty player falls back to Game N: \(value)")
}
let absent = secondGame.replacingOccurrences(of: "[Black \"Bob\"]\n", with: "")
expect(formatted(game + absent, true, true).contains("Game 2\n\n"), "Missing player tag falls back to number")
let escaped = secondGame.replacingOccurrences(of: "Alice", with: #"Alice \"Ace\" \\ Team"#)
expect(formatted(game + escaped, true, true).contains(#"Alice "Ace" \ Team vs Bob"#), "Escaped quotes and backslashes decoded in names")
let unicode = secondGame.replacingOccurrences(of: "Alice", with: "Алиса ♟").replacingOccurrences(of: "Bob", with: "李")
expect(formatted(game + unicode, true, true).contains("Алиса ♟ vs 李"), "Unicode player names preserved")
expect(formatted("\u{FEFF}" + multi.replacingOccurrences(of: "\n", with: "\r\n"), true, true) == formatted(multi, true, true), "BOM and CRLF normalized when stripping")
expect(formatted(multi.replacingOccurrences(of: "\n", with: "\r")) == formatted(multi), "CR-only line endings supported by formatter")
let annotatedMoves = "1. e4 {keep this\n[White \"Comment\"]\n1-0} e5 (1... c5 (1... e6) *)\n; [Event \"Not a game\"] 0-1\n2. Nf3 $1 *"
let annotated = game.replacingOccurrences(of: moves, with: annotatedMoves)
expect(formatted(annotated) == annotatedMoves, "Comments, fake tags, NAGs and nested variations remain intact")
expect(formatted(annotated + secondGame, true, true).components(separatedBy: "Game ").count == 3, "Comment and variation results do not split games")
let inline = "[Event \"Test\"] [White \"A\"] [Black \"B\"] 1. e4 *"
expect(formatted(inline) == "1. e4 *", "Tags on a shared line removed")
expect(formatted(game.replacingOccurrences(of: "[Event \"Test\"]", with: "[Event \"Test\"]\n[Custom_Tag \"value\"]")) == moves, "Custom headers removed")
for result in ["1-0", "0-1", "1/2-1/2", "*"] {
    let endedGame = game.replacingOccurrences(of: "2. Nf3 *", with: "2. Nf3 \(result)")
    expect(formatted(endedGame + secondGame, true, true).contains("Game 2 — Alice vs Bob"), "Game boundary after \(result)")
}
expect(formatted(game + "{final annotation}\n" + secondGame, true, true).contains("Game 2 — Alice vs Bob"), "Trailing annotation does not hide boundary")
expect(formatted(game + "\n1. d4 d5 1/2-1/2", true, true).hasSuffix("Game 2\n\n1. d4 d5 1/2-1/2"), "Headerless subsequent game gets numbered fallback")
expect(formatted("").isEmpty, "Empty formatter input safe")
// Real watcher path applies current options after reading and validating the source.
watcher.headerOptions = HeaderOptions(stripHeaders: true, autoHeaders: true)
let formatFile = try write("format-options.pgn", multi)
try watcher.scan(now: start.addingTimeInterval(88)); try watcher.scan(now: start.addingTimeInterval(91))
expect(clipboard == formatted(multi, true, true) && !FileManager.default.fileExists(atPath: formatFile.path), "Watcher copies formatted multi-game text and trashes original")
let movedOriginal = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasSuffix("-format-options.pgn") }!
let originalContents = try String(contentsOf: movedOriginal, encoding: .utf8)
expect(originalContents == multi, "Trashed source contents are unchanged")
watcher.headerOptions.stripHeaders = false
let next = try write("format-disabled.pgn", game)
try watcher.scan(now: start.addingTimeInterval(92)); try watcher.scan(now: start.addingTimeInterval(95))
expect(clipboard == game && !FileManager.default.fileExists(atPath: next.path), "Options apply immediately to subsequent files")
watcher.headerOptions.stripHeaders = true
copySucceeds = false
let formatFailure = try write("format-failure.pgn", game)
try watcher.scan(now: start.addingTimeInterval(96)); try watcher.scan(now: start.addingTimeInterval(99))
expect(FileManager.default.fileExists(atPath: formatFailure.path), "Formatting still preserves source on clipboard failure")
copySucceeds = true

try FileManager.default.removeItem(at: downloads)
do { try watcher.scan(); expect(false, "Lost folder access reported") }
catch { expect(true, "Lost folder access reported") }
print("\(checks) checks passed. Tests used only a temporary folder and fake clipboard/trash.")
