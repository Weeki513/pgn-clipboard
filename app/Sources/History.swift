import Foundation
import SQLite3
import CryptoKit

struct ImportSummary {
    let id: UUID
    let filename: String
    let importedAt: Date
}
struct HistoryPage {
    let rows: [ImportSummary]
    let matchingCount: Int
    let totalCount: Int
    let storageBytes: Int64
}
struct HistoryFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One serialized SQLite connection. Lists read metadata only; originals load on selection.
final class RecentImports {
    static let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PGN Clipboard/recent-imports.json")
    let databaseURL: URL
    private let legacyURL: URL
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL = RecentImports.defaultURL) {
        legacyURL = url.pathExtension == "json" ? url : url.deletingPathExtension().appendingPathExtension("json")
        databaseURL = url.pathExtension == "json" ? url.deletingPathExtension().appendingPathExtension("sqlite3") : url
    }
    deinit { if let db { sqlite3_close(db) } }
    private func failure() -> HistoryFailure {
        HistoryFailure(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "History database is unavailable.")
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func statement(_ sql: String, _ values: [String] = []) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(stmt, Int32(index + 1), value, Int32(value.utf8.count), transient) == SQLITE_OK else {
                sqlite3_finalize(stmt); throw failure()
            }
        }
        return stmt
    }
    private func run(_ sql: String, _ values: [String] = []) throws {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    private func scalar(_ sql: String, _ values: [String] = []) throws -> Int {
        let stmt = try statement(sql, values); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int64(stmt, 0))
    }
    private func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        guard let bytes = sqlite3_column_text(stmt, column) else { return "" }
        // Explicit byte count preserves embedded NULs in raw imported text.
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(stmt, column))), as: UTF8.self)
    }
    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try operation(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func open() throws {
        if db != nil { return }
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure(); if let db { sqlite3_close(db) }; db = nil; throw error
        }
        do {
            sqlite3_busy_timeout(db, 5000)
            try execute("PRAGMA auto_vacuum=INCREMENTAL; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON;")
            try execute("""
                CREATE TABLE IF NOT EXISTS imports (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    id TEXT NOT NULL UNIQUE, filename TEXT NOT NULL,
                    imported_at REAL NOT NULL, original TEXT NOT NULL, clipboard_text TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS imports_newest ON imports(imported_at DESC, sequence DESC);
                CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
                """)
            sqlite3_create_function_v2(db, "pgn_contains", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, values in
                guard let context, let values, let haystack = sqlite3_value_text(values[0]), let needle = sqlite3_value_text(values[1]) else {
                    sqlite3_result_int(context, 0); return
                }
                let source = String(cString: haystack), query = String(cString: needle)
                sqlite3_result_int(context, source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? 0 : 1)
            }, nil, nil, nil)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                let data = try Data(contentsOf: legacyURL)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let migrated = try scalar("SELECT count(*) FROM settings WHERE key=?", ["json_migrated_" + digest])
                if migrated == 0 {
                    // Decode before the transaction: corrupt JSON stays untouched.
                    let entries = try JSONDecoder().decode([RecentImport].self, from: data)
                    try transaction {
                        for entry in entries.reversed() { try insert(entry) }
                        try run("INSERT INTO settings(key,value) VALUES(?,1)", ["json_migrated_" + digest])
                    }
                }
                // Only remove the exact successfully committed source. A fingerprint
                // also handles interruption after COMMIT and before this cleanup.
                guard try Data(contentsOf: legacyURL) == data else { throw HistoryFailure(message: "Legacy history changed during migration. Quit the older app and retry.") }
                try FileManager.default.removeItem(at: legacyURL)
            }
        } catch {
            if let db { sqlite3_close(db) }; db = nil; throw error
        }
    }
    private func insert(_ entry: RecentImport) throws {
        try run("""
            INSERT INTO imports(id,filename,imported_at,original,clipboard_text) VALUES(?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET filename=excluded.filename,imported_at=excluded.imported_at,
                original=excluded.original,clipboard_text=excluded.clipboard_text
            """, [entry.id.uuidString, entry.filename, String(entry.importedAt.timeIntervalSince1970), entry.original, entry.clipboardText])
    }
    func entries(limit: Int = 50) throws -> [RecentImport] {
        lock.lock(); defer { lock.unlock() }; try open()
        let stmt = try statement("SELECT id,filename,imported_at,original,clipboard_text FROM imports ORDER BY imported_at DESC,sequence DESC LIMIT ?", [String(max(0, limit))])
        defer { sqlite3_finalize(stmt) }
        var result: [RecentImport] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: result.append(try readEntry(stmt))
            case SQLITE_DONE: return result
            default: throw failure()
            }
        }
    }
    private func readEntry(_ stmt: OpaquePointer) throws -> RecentImport {
        guard let id = UUID(uuidString: text(stmt, 0)) else { throw HistoryFailure(message: "Invalid history record identifier.") }
        return RecentImport(id: id, filename: text(stmt, 1), importedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)), original: text(stmt, 3), clipboardText: text(stmt, 4))
    }
    func entry(id: UUID) throws -> RecentImport? {
        lock.lock(); defer { lock.unlock() }; try open()
        let stmt = try statement("SELECT id,filename,imported_at,original,clipboard_text FROM imports WHERE id=?", [id.uuidString])
        defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw failure() }
        return try readEntry(stmt)
    }
    func page(search: String = "", limit: Int = 50, offset: Int = 0) throws -> HistoryPage {
        lock.lock(); defer { lock.unlock() }; try open()
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = query.isEmpty ? "" : " WHERE pgn_contains(filename,?) OR pgn_contains(original,?)"
        let args = query.isEmpty ? [] : [query, query]
        let total = try scalar("SELECT count(*) FROM imports")
        let matching = query.isEmpty ? total : try scalar("SELECT count(*) FROM imports" + filter, args)
        let stmt = try statement("SELECT id,filename,imported_at FROM imports" + filter + " ORDER BY imported_at DESC,sequence DESC LIMIT ? OFFSET ?", args + [String(max(1, min(limit, 100))), String(max(0, offset))])
        defer { sqlite3_finalize(stmt) }
        var rows: [ImportSummary] = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let id = UUID(uuidString: text(stmt, 0)) else { throw failure() }
            rows.append(ImportSummary(id: id, filename: text(stmt, 1), importedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))))
        }
        let bytes = [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"].reduce(Int64(0)) {
            $0 + ((try? FileManager.default.attributesOfItem(atPath: $1)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        return HistoryPage(rows: rows, matchingCount: matching, totalCount: total, storageBytes: bytes)
    }
    func record(_ entry: RecentImport) throws {
        lock.lock(); defer { lock.unlock() }; try open()
        try transaction { try insert(entry); try prune(now: Date()) }
    }
    func remove(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }; try open()
        try transaction { for id in ids { try run("DELETE FROM imports WHERE id=?", [id.uuidString]) } }
        try reclaim()
    }
    func retentionDays() throws -> Int {
        lock.lock(); defer { lock.unlock() }; try open()
        return try scalar("SELECT COALESCE((SELECT value FROM settings WHERE key='retention_days'),0)")
    }
    func setRetention(days: Int, now: Date = Date()) throws {
        guard days >= 0 && days <= 36500 else { throw HistoryFailure(message: "Invalid retention period.") }
        lock.lock(); defer { lock.unlock() }; try open()
        try transaction {
            try run("INSERT INTO settings(key,value) VALUES('retention_days',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [String(days)])
            try prune(now: now)
        }
        try reclaim()
    }
    func maintenance(now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }; try open()
        try transaction { try prune(now: now) }
        try reclaim()
    }
    private func prune(now: Date) throws {
        let days = try scalar("SELECT COALESCE((SELECT value FROM settings WHERE key='retention_days'),0)")
        if days > 0 { try run("DELETE FROM imports WHERE imported_at < ?", [String(now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)]) }
    }
    private func reclaim() throws {
        try execute("PRAGMA incremental_vacuum(256); PRAGMA wal_checkpoint(TRUNCATE)")
    }
}
