import AppKit

let app = NSApplication.shared
#if PGN_PREVIEW
// A separately identified local app/container, never the installed app's history.
let history = RecentImports()
if !FileManager.default.fileExists(atPath: history.databaseURL.path) {
    for index in 0..<125 {
        let original = "[Event \"Preview training \(index + 1)\"]\n[White \"Demo White\"]\n[Black \"Demo Black\"]\n[Result \"*\"]\n\n1. e4 e5 2. Nf3 Nc6\n{Synthetic preview game.\n" + String(repeating: "A sample annotation for testing text selection and scrolling.\n", count: 20) + "}\n3. Bb5 a6 *\n"
        try! history.record(RecentImport(id: UUID(), filename: "Training-\(String(format: "%03d", index + 1)).pgn", importedAt: Date().addingTimeInterval(-Double(index) * 86400), original: original, clipboardText: original))
    }
    UserDefaults.standard.set(true, forKey: "stripHeaders")
    UserDefaults.standard.set(true, forKey: "autoHeaders")
}
let delegate = AppDelegate(history: history)
#else
let delegate = AppDelegate()
#endif
app.delegate = delegate
app.run()
