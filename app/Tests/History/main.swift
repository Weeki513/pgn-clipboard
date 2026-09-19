import Foundation
import SQLite3

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1; guard condition() else { fatalError(message) }; print("PASS: \(message)")
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pgn-sqlite-tests-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let legacy = directory.appendingPathComponent("history.json")
let now = Date()
func entry(_ name: String, age: Double = 0, original: String = "[Event \"Турнир\"]\r\n1. e4  e5 *\r\n") -> RecentImport {
    RecentImport(id: UUID(), filename: name, importedAt: now.addingTimeInterval(-age * 86400), original: original, clipboardText: "old snapshot")
}
let originals = [entry("new.pgn"), entry("old.pgn", age: 100)]
let legacyData = try JSONEncoder().encode(originals)
try legacyData.write(to: legacy)
var store = RecentImports(url: legacy)
let migrated = try store.entries()
expect(migrated.map(\.id) == originals.map(\.id) && migrated[0].original == originals[0].original, "JSON migration preserves IDs, dates, order and exact original text")
expect(FileManager.default.fileExists(atPath: store.databaseURL.path) && !FileManager.default.fileExists(atPath: legacy.path), "Legacy JSON retired only after SQLite commit")
store = RecentImports(url: legacy)
expect(try! store.entries().count == 2, "Reopening never duplicates migrated records")
try store.remove(ids: [originals[1].id])
// Simulate a crash after COMMIT but before JSON cleanup: matching migration fingerprint avoids resurrection.
try legacyData.write(to: legacy)
store = RecentImports(url: legacy)
expect(try! store.entries().count == 1, "Retrying completed migration does not resurrect a deleted import")
expect(try! store.retentionDays() == 0, "Retention defaults to never delete")
let nul = entry("nul.pgn", original: "before\0after\n")
try store.record(nul)
expect(try! store.entry(id: nul.id)?.original == nul.original, "Raw history preserves embedded NUL and trailing newline")
let started = Date()
for index in 0..<1200 { try store.record(entry("game-\(index).pgn", age: Double(index % 120))) }
let first = try store.page(limit: 50)
let second = try store.page(limit: 50, offset: 50)
expect(first.totalCount == 1202 && first.rows.count == 50 && second.rows.count == 50, "1,202 records remain stored; pages contain only 50 summaries")
expect(Set(first.rows.map(\.id)).isDisjoint(with: Set(second.rows.map(\.id))), "Pagination is stable even for identical timestamps")
expect(first.storageBytes > 0, "Disk usage includes SQLite storage")
expect(try! store.page(search: "турнир").matchingCount == 1201, "Search matches PGN contents with Unicode case folding")
expect(try! store.page(search: "GAME-1199").matchingCount == 1, "Filename search is case insensitive")
expect(try! store.page(search: "%' OR 1=1 --").matchingCount == 0, "Search input is literal and safely bound")
expect(try! store.page(search: "missing").rows.isEmpty, "Search supports empty results")
try store.record(originals[0])
expect(try! store.page().totalCount == 1202, "Retrying an import updates its UUID instead of duplicating it")
try store.setRetention(days: 30, now: now)
let kept = try store.page()
expect(kept.totalCount == 312, "Retention removes only imports strictly older than 30 days")
store = RecentImports(url: legacy)
expect(try! store.retentionDays() == 30, "Retention setting persists after reopen")
try store.maintenance(now: now.addingTimeInterval(86400))
expect(try! store.page().totalCount == 302, "Idle maintenance advances expiry without a new import")
try store.setRetention(days: 0)
let ancient = entry("ancient.pgn", age: 900)
try store.record(ancient); try store.maintenance(now: now.addingTimeInterval(10000 * 86400))
expect(try! store.entry(id: ancient.id) != nil, "Never-delete mode retains arbitrarily old records")
let countBeforeDelete = try store.page().totalCount
let ids = Set(try store.page(limit: 50).rows.map(\.id))
try store.remove(ids: ids)
expect(try! store.page().totalCount == countBeforeDelete - 50, "Bulk deletion removes exactly the selected page IDs")
let corruptURL = directory.appendingPathComponent("broken.json")
let corrupt = Data("broken JSON".utf8); try corrupt.write(to: corruptURL)
let broken = RecentImports(url: corruptURL)
do { _ = try broken.page(); fatalError("Corrupt migration should fail") } catch { }
expect(try! Data(contentsOf: corruptURL) == corrupt, "Failed migration keeps the complete original JSON")
try JSONEncoder().encode(originals).write(to: corruptURL)
expect(try! broken.page().totalCount == 2, "A failed migration can be retried after repairing the source")
let rollbackURL = directory.appendingPathComponent("rollback.json")
let rollbackDB = RecentImports(url: rollbackURL)
_ = try rollbackDB.page()
var rawDB: OpaquePointer?
expect(sqlite3_open(rollbackDB.databaseURL.path, &rawDB) == SQLITE_OK, "Open migration failure fixture")
expect(sqlite3_exec(rawDB, "CREATE TRIGGER reject_import BEFORE INSERT ON imports WHEN NEW.filename='new.pgn' BEGIN SELECT RAISE(ABORT,'injected failure'); END", nil, nil, nil) == SQLITE_OK, "Install migration failure trigger")
sqlite3_close(rawDB)
try legacyData.write(to: rollbackURL)
let retryMigration = RecentImports(url: rollbackURL)
do { _ = try retryMigration.page(); fatalError("Injected migration must fail") } catch { }
expect(try! rollbackDB.page().totalCount == 0, "Failed migration rolls back all inserted rows")
expect(try! Data(contentsOf: rollbackURL) == legacyData, "Failed SQL transaction preserves legacy JSON byte-for-byte")
let concurrent = RecentImports(url: directory.appendingPathComponent("parallel.sqlite3"))
DispatchQueue.concurrentPerform(iterations: 40) { index in
    try! concurrent.record(entry("parallel-\(index).pgn")); _ = try! concurrent.page()
}
expect(try! concurrent.page().totalCount == 40, "Concurrent reads/imports serialize without lost writes")
print("\(checks) SQLite checks passed. 1,200-import exercise: \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
