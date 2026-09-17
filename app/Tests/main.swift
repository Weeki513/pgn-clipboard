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
try FileManager.default.removeItem(at: downloads)
do { try watcher.scan(); expect(false, "Lost folder access reported") }
catch { expect(true, "Lost folder access reported") }
print("\(checks) checks passed. Tests used only a temporary folder and fake clipboard/trash.")
