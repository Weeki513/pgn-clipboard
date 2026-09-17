import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var watcher: Watcher?
    private var folder: URL?
    private var securityAccess = false
    private var paused = false
    private var message = "Choose a folder to start"
    private var lastError: String?
    private var panelOpen = false
    private var controls: NSWindow?
    private var statusLabel: NSTextField?
    private var folderLabel: NSTextField?
    private var pauseButton: NSButton?
    private var loginButton: NSButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments
        if arguments.contains("--login-status") || arguments.contains("--enable-login") || arguments.contains("--disable-login") {
            do {
                if arguments.contains("--enable-login") { try SMAppService.mainApp.register() }
                if arguments.contains("--disable-login"), SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                switch SMAppService.mainApp.status {
                case .enabled: print("Launch at Login: enabled")
                case .requiresApproval: print("Launch at Login: requires approval in System Settings")
                case .notRegistered: print("Launch at Login: disabled")
                case .notFound: print("Launch at Login: app not found")
                @unknown default: print("Launch at Login: unknown status")
                }
                exit(EXIT_SUCCESS)
            } catch { fputs("Login item: \(error.localizedDescription)\n", stderr); exit(EXIT_FAILURE) }
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "PGNClipboard.StatusItem"
        item.isVisible = true
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("PGN Clipboard")
        refreshStatus()
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        if CommandLine.arguments.contains("--uninstall") {
            prepareUninstall(); return
        }
        paused = UserDefaults.standard.bool(forKey: "paused")
        if let data = UserDefaults.standard.data(forKey: "folderBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                try watch(url)
                if stale { try saveBookmark(url) }
            } catch { setError("Folder access needs renewal: \(error.localizedDescription)") }
        }
        if watcher == nil { DispatchQueue.main.async { self.chooseFolder() } }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.paused, !self.panelOpen else { return }
            do { try self.watcher?.scan() }
            catch { self.setError("Cannot read folder: \(error.localizedDescription)") }
        }
        timer?.tolerance = 0.2
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refreshStatus()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if watcher == nil { chooseFolder() }
        else { DispatchQueue.main.async { self.showControls() } }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if securityAccess { folder?.stopAccessingSecurityScopedResource() }
    }
    private func setError(_ text: String) {
        lastError = text; message = text; refreshStatus()
    }
    private func saveBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: "folderBookmark")
    }
    private func watch(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        let candidate = Watcher(folder: url, copy: { text in
            let board = NSPasteboard.general
            board.clearContents()
            return board.setString(text, forType: .string) && board.string(forType: .string) == text
        }, trash: { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        })
        do { try candidate.baseline() }
        catch { if access { url.stopAccessingSecurityScopedResource() }; throw error }
        if securityAccess { folder?.stopAccessingSecurityScopedResource() }
        folder = url; securityAccess = access; watcher = candidate
        candidate.report = { [weak self] text, error in
            guard let self else { return }
            if error { self.setError(text) }
            else { self.message = text; self.refreshStatus() }
        }
        lastError = nil; message = "Watching \(url.lastPathComponent) · new PGN files only"
        refreshStatus()
    }
    @objc private func chooseFolder() {
        guard !panelOpen else { return }
        panelOpen = true
        defer { panelOpen = false }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "PGN Clipboard"
        panel.message = "Choose Downloads. New PGN files will be copied to your clipboard and moved to Trash. Existing files stay untouched."
        panel.prompt = "Watch Folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try watch(url); try saveBookmark(url); showControls() }
        catch { setError(error.localizedDescription); showDetails() }
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: paused ? "Paused" : message, action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status)
        if let folder {
            let path = NSMenuItem(title: folder.path, action: nil, keyEquivalent: "")
            path.isEnabled = false; menu.addItem(path)
        }
        menu.addItem(.separator())
        add(menu, "Open Controls…", #selector(showControls))
        add(menu, "Choose Folder…", #selector(chooseFolder))
        add(menu, paused ? "Resume" : "Pause", #selector(togglePause)).isEnabled = watcher != nil
        add(menu, "Retry Failed Files", #selector(retry)).isEnabled = watcher != nil && lastError != nil && !paused
        let login = add(menu, "Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval { login.title = "Launch at Login — Approval Needed…" }
        if lastError != nil { add(menu, "Show Last Error…", #selector(showDetails)) }
        menu.addItem(.separator())
        add(menu, "Made with love by pivnev.design", #selector(openWebsite))
        add(menu, "Feedback: hi@pivnev.design", #selector(openFeedback))
        add(menu, "About PGN Clipboard…", #selector(about))
        add(menu, "Reset Access and Quit…", #selector(reset))
        add(menu, "Quit", #selector(quit)).keyEquivalent = "q"
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; menu.addItem(entry); return entry
    }
    @objc private func togglePause() {
        if paused {
            do { try watcher?.baseline() }
            catch { setError(error.localizedDescription); return }
        }
        paused.toggle(); UserDefaults.standard.set(paused, forKey: "paused")
        refreshStatus()
    }
    @objc private func retry() { watcher?.retryFailures(); lastError = nil; message = "Retrying failed files…"; refreshStatus() }
    @objc private func toggleLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
        } catch { setError("Login item: \(error.localizedDescription)"); showDetails() }
        refreshStatus()
    }
    private func refreshStatus() {
        guard item != nil else { return }
        item.button?.title = ""
        item.button?.image = StatusIcon.image(paused: paused, hasError: lastError != nil)
        item.button?.toolTip = paused ? "PGN Clipboard — Paused" : "PGN Clipboard — \(message)"
        statusLabel?.stringValue = paused ? "Paused. New files will stay in the folder." : message
        folderLabel?.stringValue = folder?.path ?? "No folder selected"
        pauseButton?.title = paused ? "Resume" : "Pause"
        pauseButton?.isEnabled = watcher != nil
        loginButton?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginButton?.title = SMAppService.mainApp.status == .requiresApproval
            ? "Launch at Login — Approval Needed…" : "Launch at Login"
    }
    @objc private func restoreMenuIcon() { item.isVisible = true; refreshStatus() }
    @objc private func showControls() {
        if controls == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 470),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "PGN Clipboard"
            window.isReleasedWhenClosed = false
            let stack = NSStackView()
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
            ])
            let title = NSTextField(labelWithString: "Download a game. Paste its PGN.")
            title.font = .systemFont(ofSize: 20, weight: .semibold)
            stack.addArrangedSubview(title)
            let status = NSTextField(wrappingLabelWithString: message)
            status.font = .systemFont(ofSize: 13)
            status.maximumNumberOfLines = 4
            stack.addArrangedSubview(status); statusLabel = status
            status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let path = NSTextField(wrappingLabelWithString: "")
            path.textColor = .secondaryLabelColor; path.font = .systemFont(ofSize: 12)
            path.maximumNumberOfLines = 2; path.lineBreakMode = .byTruncatingMiddle
            stack.addArrangedSubview(path); folderLabel = path
            path.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
            row.addArrangedSubview(NSButton(title: "Choose Folder…", target: self, action: #selector(chooseFolder)))
            let pause = NSButton(title: "Pause", target: self, action: #selector(togglePause))
            row.addArrangedSubview(pause); pauseButton = pause
            row.addArrangedSubview(NSButton(title: "Retry Failed Files", target: self, action: #selector(retry)))
            stack.addArrangedSubview(row)
            let login = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLogin))
            stack.addArrangedSubview(login); loginButton = login
            let hint = NSTextField(wrappingLabelWithString: "Look for the pawn in the menu bar. If the bar is crowded, you can always reopen this app to access these controls.")
            hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(hint)
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let bottom = NSStackView(); bottom.orientation = .horizontal; bottom.spacing = 8
            bottom.addArrangedSubview(NSButton(title: "Show Menu Bar Icon", target: self, action: #selector(restoreMenuIcon)))
            bottom.addArrangedSubview(NSButton(title: "Quit", target: self, action: #selector(quit)))
            stack.addArrangedSubview(bottom)
            let credit = NSButton(title: "Made with love by pivnev.design", target: self, action: #selector(openWebsite))
            credit.bezelStyle = .inline; credit.isBordered = false
            credit.contentTintColor = .linkColor
            credit.font = .systemFont(ofSize: 13, weight: .semibold)
            credit.toolTip = "https://www.pivnev.design/"
            stack.addArrangedSubview(credit)
            let feedback = NSButton(title: "Feedback: hi@pivnev.design", target: self, action: #selector(openFeedback))
            feedback.bezelStyle = .inline; feedback.isBordered = false
            feedback.contentTintColor = .linkColor
            feedback.font = .systemFont(ofSize: 13)
            feedback.toolTip = "mailto:hi@pivnev.design"
            stack.addArrangedSubview(feedback)
            window.center(); controls = window
        }
        refreshStatus()
        NSApp.activate(ignoringOtherApps: true)
        controls?.makeKeyAndOrderFront(nil)
    }
    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://www.pivnev.design/")!)
    }
    @objc private func openFeedback() {
        NSWorkspace.shared.open(URL(string: "mailto:hi@pivnev.design")!)
    }
    @objc private func showDetails() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "PGN Clipboard"
        alert.informativeText = lastError ?? message; alert.runModal()
    }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "PGN Clipboard 1.0.3"
        alert.informativeText = "Download a game. Paste its PGN.\n\nNew .pgn files are copied after at least 3 seconds without changes, then moved to Trash. Only the latest processed game stays in the clipboard.\n\nNo network access. No analytics. No Full Disk Access."
        alert.runModal()
    }
    @objc private func reset() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Reset PGN Clipboard?"
        alert.informativeText = "Forget the selected folder, disable Launch at Login, and quit. Your PGN files will not be changed."
        alert.addButton(withTitle: "Reset and Quit"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { prepareUninstall() }
    }
    private func prepareUninstall() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            UserDefaults.standard.synchronize()
            NSApp.terminate(nil)
        } catch {
            if CommandLine.arguments.contains("--uninstall") {
                fputs("Could not disable Launch at Login: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            setError("Could not disable Launch at Login: \(error.localizedDescription)"); showDetails()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
