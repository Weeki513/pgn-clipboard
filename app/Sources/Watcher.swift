import Foundation
import Darwin

struct FileStamp: Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let seconds: Int
    let nanos: Int
    init(_ value: stat) {
        device = value.st_dev; inode = value.st_ino; size = value.st_size
        seconds = value.st_mtimespec.tv_sec; nanos = value.st_mtimespec.tv_nsec
    }
    static func read(_ url: URL) -> FileStamp? {
        var value = stat()
        guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { return nil }
        return FileStamp(value)
    }
}

enum PGNError: LocalizedError {
    case changed, invalid, clipboard, oversized, unreadable
    var errorDescription: String? {
        switch self {
        case .changed: return "File changed while being read; left in place."
        case .invalid: return "Not a supported complete UTF-8 PGN; left in place."
        case .clipboard: return "Clipboard write failed; file left in place."
        case .oversized: return "PGN exceeds 5 MB; left in place."
        case .unreadable: return "Could not safely read this regular file; left in place."
        }
    }
}

struct PGN {
    static let maxBytes = 5 * 1024 * 1024
    // Intentionally conservative, not a full chess/PGN parser.
    static func valid(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespacesAndNewlines))
        for tag in ["Event", "White", "Black"] {
            let pattern = "(?m)^\\[" + tag + "[ \\t]+\"(?:[^\"\\\\\\r\\n]|\\\\.)*\"[ \\t]*\\][ \\t]*\\r?$"
            guard normalized.range(of: pattern, options: .regularExpression) != nil else { return false }
        }
        // Require an explicit terminal result (including * for an unfinished game).
        return normalized.range(of: "(?:^|\\s)(?:1-0|0-1|1/2-1/2|\\*)$", options: .regularExpression) != nil
    }
    static func read(_ url: URL, expected: FileStamp) throws -> String {
        guard expected.size > 0 else { throw PGNError.invalid }
        guard expected.size <= maxBytes else { throw PGNError.oversized }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PGNError.unreadable }
        defer { close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              FileStamp(value) == expected else { throw PGNError.changed }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw PGNError.unreadable }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maxBytes else { throw PGNError.oversized }
        }
        guard fstat(fd, &value) == 0, FileStamp(value) == expected,
              FileStamp.read(url) == expected else { throw PGNError.changed }
        guard let text = String(data: data, encoding: .utf8), valid(text) else { throw PGNError.invalid }
        return text
    }
}

final class Watcher {
    struct Observation {
        var stamp: FileStamp
        var changedAt: Date
        var eligible: Bool
        var attempted: Bool
    }
    let folder: URL
    let stableSeconds: TimeInterval
    private var observations: [URL: Observation] = [:]
    private let copy: (String) -> Bool
    private let trash: (URL) throws -> Void
    var report: (String, Bool) -> Void = { _, _ in }

    init(folder: URL, stableSeconds: TimeInterval = 3,
         copy: @escaping (String) -> Bool, trash: @escaping (URL) throws -> Void) {
        self.folder = folder; self.stableSeconds = stableSeconds; self.copy = copy; self.trash = trash
    }
    private func files() throws -> [URL: FileStamp] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result: [URL: FileStamp] = [:]
        for url in urls where url.pathExtension.lowercased() == "pgn" {
            if let stamp = FileStamp.read(url) { result[url] = stamp }
        }
        return result
    }
    func baseline(now: Date = Date()) throws {
        observations = try files().mapValues { Observation(stamp: $0, changedAt: now, eligible: false, attempted: false) }
    }
    func retryFailures(now: Date = Date()) {
        for url in Array(observations.keys) where observations[url]!.eligible && observations[url]!.attempted {
            observations[url]!.attempted = false; observations[url]!.changedAt = now
        }
    }
    func scan(now: Date = Date()) throws {
        let current = try files()
        observations = observations.filter { current[$0.key] != nil }
        for (url, stamp) in current {
            if observations[url]?.stamp != stamp {
                observations[url] = Observation(stamp: stamp, changedAt: now, eligible: true, attempted: false)
            }
        }
        // If multiple games arrive together, the newest one ends up in the clipboard.
        let ready = observations.filter { $0.value.eligible && !$0.value.attempted && now.timeIntervalSince($0.value.changedAt) >= stableSeconds }
            .sorted { a, b in
                let x = a.value.stamp, y = b.value.stamp
                if x.seconds != y.seconds { return x.seconds < y.seconds }
                if x.nanos != y.nanos { return x.nanos < y.nanos }
                return a.key.lastPathComponent < b.key.lastPathComponent
            }
        for (url, observation) in ready {
            observations[url]!.attempted = true
            do {
                let text = try PGN.read(url, expected: observation.stamp)
                guard copy(text) else { throw PGNError.clipboard }
                guard FileStamp.read(url) == observation.stamp else { throw PGNError.changed }
                try trash(url)
                observations.removeValue(forKey: url)
                report("Copied and moved to Trash: \(url.lastPathComponent)", false)
            } catch {
                report("\(url.lastPathComponent): \(error.localizedDescription)", true)
            }
        }
    }
}
