import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var latestDetail: ImportDetailView?
    private let historyQueue = DispatchQueue(label: "design.pivnev.pgnclipboard.maintenance", qos: .utility)
    private var watcher: Watcher?
    private var folder: URL?
    private var securityAccess = false
    private var paused = false
    private var message = "Choose a folder to start"
    private var lastError: String?
    private var panelOpen = false
    private var controls: NSWindow?
    private var restoreWindowFrame: NSRect?
    private var tabs: PageHostView?
    private var controlsTabButton: ASCIIButton?
    private var historyTabButton: ASCIIButton?
    private var recentView: RecentImportsView?
    private var statusLabel: NSTextField?
    private var folderLabel: NSTextField?
    private var pauseButton: NSButton?
    private var loginButton: NSButton?
    private var stripButton: NSButton?
    private var autoButton: NSButton?
    private var trashButton: NSButton?
    private let history: RecentImports
    private var moveOriginalToTrash: Bool
    private let defaults: UserDefaults
    private var headerOptions: HeaderOptions

    init(defaults: UserDefaults = .standard, history: RecentImports = RecentImports()) {
        self.history = history
        self.moveOriginalToTrash = defaults.object(forKey: "moveOriginalToTrash") as? Bool ?? true
        self.defaults = defaults
        self.headerOptions = HeaderOptions(
            stripHeaders: defaults.bool(forKey: "stripHeaders"),
            autoHeaders: defaults.bool(forKey: "autoHeaders"))
        super.init()
    }

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
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self; item.menu = menu
        if CommandLine.arguments.contains("--uninstall") {
            prepareUninstall(); return
        }
        configureEditMenu()
        maintainHistory()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.maintainHistory() }
        cleanupTimer?.tolerance = 60
        paused = defaults.bool(forKey: "paused")
        if let data = defaults.data(forKey: "folderBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                try watch(url)
                if stale { try saveBookmark(url) }
            } catch { setError("Folder access needs renewal: \(error.localizedDescription)") }
        }
        if watcher == nil {
            DispatchQueue.main.async {
                if Bundle.main.object(forInfoDictionaryKey: "PGNPreview") as? Bool == true {
                    self.message = "Local preview / synthetic history / choose a test folder to try imports"
                    self.showControls()
                } else { self.chooseFolder() }
            }
        }
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
        if watcher == nil && Bundle.main.object(forInfoDictionaryKey: "PGNPreview") as? Bool != true { chooseFolder() }
        else { DispatchQueue.main.async { self.showControls() } }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); cleanupTimer?.invalidate()
        if securityAccess { folder?.stopAccessingSecurityScopedResource() }
    }
    private func setError(_ text: String) {
        lastError = text; message = text; refreshStatus()
    }
    private func saveBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "folderBookmark")
    }
    private func watch(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        let candidate = Watcher(folder: url, history: history, copy: { text in
            let board = NSPasteboard.general
            board.clearContents()
            return board.setString(text, forType: .string) && board.string(forType: .string) == text
        }, trash: { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        })
        candidate.headerOptions = headerOptions
        candidate.moveOriginalToTrash = moveOriginalToTrash
        do { try candidate.baseline() }
        catch { if access { url.stopAccessingSecurityScopedResource() }; throw error }
        if securityAccess { folder?.stopAccessingSecurityScopedResource() }
        folder = url; securityAccess = access; watcher = candidate
        candidate.report = { [weak self] text, error in
            guard let self else { return }
            if error { self.setError(text) }
            else { self.message = text; self.refreshStatus() }
            self.recentView?.reload(); self.refreshLatest()
        }
        lastError = nil; message = "Watching \(url.lastPathComponent) / new PGN files only"
        refreshStatus()
    }
    @objc private func chooseFolder() {
        guard !panelOpen else { return }
        panelOpen = true
        defer { panelOpen = false }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "PGN Clipboard"
        panel.message = "Choose Downloads. New PGN files will be saved in Recent Imports and copied. Move original to Trash is optional (on by default). Existing files stay untouched."
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
        add(menu, "Manage Recent Imports…", #selector(showRecentImports))
        let recent = NSMenuItem(title: "Recent Imports", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(); recentMenu.autoenablesItems = false
        do {
            let entries = try history.entries(limit: 10)
            let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .medium
            for entry in entries {
                let row = NSMenuItem(title: "\(entry.filename) — \(formatter.string(from: entry.importedAt))", action: nil, keyEquivalent: "")
                let actions = NSMenu(); actions.autoenablesItems = false
                let copy = add(actions, "Copy formatted", #selector(copyRecentFormatted(_:)))
                copy.representedObject = entry.original
                let raw = add(actions, "Copy raw", #selector(copyRecent(_:)))
                raw.representedObject = entry.original
                row.submenu = actions; recentMenu.addItem(row)
            }
            if entries.isEmpty { recentMenu.addItem(withTitle: "No imports yet", action: nil, keyEquivalent: "").isEnabled = false }
        } catch {
            recentMenu.addItem(withTitle: "History unavailable: \(error.localizedDescription)", action: nil, keyEquivalent: "").isEnabled = false
        }
        recent.submenu = recentMenu; menu.addItem(recent)
        menu.addItem(.separator())
        add(menu, "Open Controls…", #selector(showControls))
        add(menu, "Choose Folder…", #selector(chooseFolder))
        add(menu, paused ? "Resume" : "Pause", #selector(togglePause)).isEnabled = watcher != nil
        add(menu, "Retry Failed Files", #selector(retry)).isEnabled = watcher != nil && lastError != nil && !paused
        menu.addItem(.separator())
        let trash = add(menu, "Move original to Trash", #selector(toggleTrash))
        trash.state = moveOriginalToTrash ? .on : .off
        let strip = add(menu, "Strip headers", #selector(toggleStripHeaders))
        strip.state = headerOptions.stripHeaders ? .on : .off
        let auto = add(menu, "Auto headers", #selector(toggleAutoHeaders))
        auto.state = headerOptions.autoHeaders ? .on : .off
        auto.isEnabled = headerOptions.autoHeadersEnabled
        menu.addItem(.separator())
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
    @objc private func copyRecentFormatted(_ sender: NSMenuItem) {
        guard let original = sender.representedObject as? String else { return }
        let copy = NSMenuItem(); copy.representedObject = PGNFormatter.format(original, options: headerOptions)
        _ = copyRecent(copy)
    }
    private func configureEditMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        add(appMenu, "Quit PGN Clipboard", #selector(quit)).keyEquivalent = "q"
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Edit")
        for (name, action, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Select All", #selector(NSText.selectAll(_:)), "a"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Paste", #selector(NSText.paste(_:)), "v")] {
            submenu.addItem(withTitle: name, action: action, keyEquivalent: key)
        }
        edit.submenu = submenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
    private func maintainHistory() {
        historyQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.history.maintenance()
                DispatchQueue.main.async { self.recentView?.reload(); self.refreshLatest() }
            } catch { DispatchQueue.main.async { self.setError("History: \(error.localizedDescription)") } }
        }
    }
    private func refreshLatest() {
        guard latestDetail != nil else { return }
        historyQueue.async { [weak self] in
            guard let self else { return }
            do {
                let entry = try self.history.entries(limit: 1).first
                DispatchQueue.main.async { self.latestDetail?.show(entry) }
            } catch { DispatchQueue.main.async { self.latestDetail?.feedback.stringValue = error.localizedDescription } }
        }
    }
    @objc private func copyRecent(_ sender: NSMenuItem) -> Bool {
        guard let text = sender.representedObject as? String else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(text, forType: .string), board.string(forType: .string) == text else {
            setError("Could not copy recent import."); return false
        }
        message = "Copied from Recent Imports"; refreshStatus(); return true
    }
    @objc private func toggleTrash() {
        moveOriginalToTrash.toggle()
        defaults.set(moveOriginalToTrash, forKey: "moveOriginalToTrash")
        watcher?.moveOriginalToTrash = moveOriginalToTrash
        refreshStatus()
    }
    @objc private func toggleStripHeaders() {
        headerOptions.stripHeaders.toggle()
        saveHeaderOptions()
    }
    @objc private func toggleAutoHeaders() {
        guard headerOptions.autoHeadersEnabled else { return }
        headerOptions.autoHeaders.toggle()
        saveHeaderOptions()
    }
    private func saveHeaderOptions() {
        defaults.set(headerOptions.stripHeaders, forKey: "stripHeaders")
        defaults.set(headerOptions.autoHeaders, forKey: "autoHeaders")
        watcher?.headerOptions = headerOptions
        refreshStatus()
    }
    @objc private func togglePause() {
        if paused {
            do { try watcher?.baseline() }
            catch { setError(error.localizedDescription); return }
        }
        paused.toggle(); defaults.set(paused, forKey: "paused")
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
        latestDetail?.refreshPreview(); recentView?.detail.refreshPreview()
        item?.button?.title = ""
        item?.button?.image = StatusIcon.image(paused: paused, hasError: lastError != nil)
        item?.button?.toolTip = paused ? "PGN Clipboard — Paused" : "PGN Clipboard — \(message)"
        statusLabel?.textColor = lastError != nil ? .systemRed : (watcher != nil && !paused ? ASCIIStyle.accent : .secondaryLabelColor)
        statusLabel?.stringValue = paused ? "[ ] PAUSED - new files stay in the folder." : "[*] " + message
        folderLabel?.stringValue = folder?.path ?? "No folder selected"
        pauseButton?.title = paused ? "Resume" : "Pause"
        pauseButton?.isEnabled = watcher != nil
        trashButton?.state = moveOriginalToTrash ? .on : .off
        stripButton?.state = headerOptions.stripHeaders ? .on : .off
        autoButton?.state = headerOptions.autoHeaders ? .on : .off
        autoButton?.isEnabled = headerOptions.autoHeadersEnabled
        loginButton?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginButton?.title = SMAppService.mainApp.status == .requiresApproval
            ? "Launch at Login — Approval Needed…" : "Launch at Login"
    }
    @objc private func restoreMenuIcon() { item.isVisible = true; refreshStatus() }
    @objc private func showControls() {
        if controls == nil {
            let window = ClipboardWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 690),
                styleMask: [.borderless, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = Bundle.main.object(forInfoDictionaryKey: "PGNPreview") as? Bool == true ? "PGN Clipboard - ASCII Preview" : "PGN Clipboard"
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 1000, height: 650)
            window.appearance = NSAppearance(named: .darkAqua); window.backgroundColor = ASCIIStyle.paper
            window.hasShadow = true
            let board = BoardView(frame: window.contentView!.bounds); board.autoresizingMask = [.width, .height]; window.contentView = board
            NSLayoutConstraint.activate([
                board.widthAnchor.constraint(greaterThanOrEqualToConstant: 1000),
                board.heightAnchor.constraint(greaterThanOrEqualToConstant: 650)
            ])
            window.contentMinSize = NSSize(width: 1000, height: 650)
            let drag = WindowDragArea(); drag.translatesAutoresizingMaskIntoConstraints = false; board.addSubview(drag)
            let windowActions = NSStackView(); windowActions.orientation = .horizontal; windowActions.spacing = 0
            for (title, action, label) in [("x", #selector(closeWindow), "Close window"), ("_", #selector(minimizeWindow), "Minimize window"), ("+", #selector(zoomWindow), "Resize window")] {
                let button = ASCIIButton(title: title, target: self, action: action); button.font = ASCIIStyle.font()
                button.setAccessibilityLabel(label)
                if title == "x" { button.keyEquivalent = "w"; button.keyEquivalentModifierMask = .command }
                if title == "_" { button.keyEquivalent = "m"; button.keyEquivalentModifierMask = .command }
                windowActions.addArrangedSubview(button)
            }
            windowActions.translatesAutoresizingMaskIntoConstraints = false; board.addSubview(windowActions)
            let heading = NSTextField(labelWithString: Self.asciiTitle)
            heading.font = ASCIIStyle.font(); heading.textColor = ASCIIStyle.ink
            heading.translatesAutoresizingMaskIntoConstraints = false; board.addSubview(heading)
            let tagline = NSTextField(labelWithString: "Small games. A bigger tomorrow.")
            tagline.font = ASCIIStyle.font(); tagline.textColor = ASCIIStyle.dim
            tagline.translatesAutoresizingMaskIntoConstraints = false; board.addSubview(tagline)
            let version = NSTextField(labelWithString: "LOCAL / OFFLINE  |  v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"))
            version.font = ASCIIStyle.font(); version.textColor = ASCIIStyle.dim
            version.translatesAutoresizingMaskIntoConstraints = false; board.addSubview(version)
            let nav = NSStackView(); nav.orientation = .horizontal; nav.spacing = 14; nav.translatesAutoresizingMaskIntoConstraints = false
            let controlTab = ASCIIButton(title: "CONTROLS", target: self, action: #selector(selectControlsTab))
            let historyTab = ASCIIButton(title: "RECENT IMPORTS", target: self, action: #selector(selectHistoryTab))
            controlTab.persistentSelection = true; historyTab.persistentSelection = true
            nav.addArrangedSubview(controlTab); nav.addArrangedSubview(historyTab); board.addSubview(nav)
            controlsTabButton = controlTab; historyTabButton = historyTab
            let tabs = PageHostView()
            tabs.translatesAutoresizingMaskIntoConstraints = false; board.addSubview(tabs); self.tabs = tabs
            NSLayoutConstraint.activate([
                drag.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 12), drag.trailingAnchor.constraint(equalTo: board.trailingAnchor, constant: -12),
                drag.topAnchor.constraint(equalTo: board.topAnchor, constant: 12), drag.heightAnchor.constraint(equalToConstant: 112),
                windowActions.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 16), windowActions.topAnchor.constraint(equalTo: board.topAnchor, constant: 12),
                heading.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 30), heading.topAnchor.constraint(equalTo: board.topAnchor, constant: 43),
                tagline.leadingAnchor.constraint(equalTo: heading.leadingAnchor), tagline.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 7),
                version.trailingAnchor.constraint(equalTo: board.trailingAnchor, constant: -24), version.topAnchor.constraint(equalTo: board.topAnchor, constant: 22),
                nav.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 24), nav.topAnchor.constraint(equalTo: board.topAnchor, constant: 155),
                tabs.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 18), tabs.trailingAnchor.constraint(equalTo: board.trailingAnchor, constant: -18),
                tabs.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 8), tabs.bottomAnchor.constraint(equalTo: board.bottomAnchor, constant: -24)
            ])
            let container = NSView(); tabs.addPage(container, identifier: "controls")
            let recent = RecentImportsView(history: history)
            recent.copyText = { [weak self] text in
                let sender = NSMenuItem(); sender.representedObject = text; return self?.copyRecent(sender) ?? false
            }
            recent.options = { [weak self] in self?.headerOptions ?? HeaderOptions() }
            tabs.addPage(recent, identifier: "recent"); recentView = recent
            let latest = ImportDetailView(); latest.isLatest = true; latest.trashEnabled = { [weak self] in self?.moveOriginalToTrash ?? false }; latest.options = recent.options; latest.copyText = recent.copyText; latestDetail = latest
            latest.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(latest)
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12), stack.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.44),
                stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8), stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4),
                latest.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 14), latest.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                latest.topAnchor.constraint(equalTo: container.topAnchor), latest.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            let status = NSTextField(wrappingLabelWithString: message); status.font = ASCIIStyle.font(); status.maximumNumberOfLines = 2
            stack.addArrangedSubview(status); statusLabel = status; status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let path = NSTextField(labelWithString: ""); path.font = ASCIIStyle.font(); path.textColor = ASCIIStyle.dim; path.lineBreakMode = .byTruncatingMiddle
            stack.addArrangedSubview(path); folderLabel = path; path.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 6
            row.addArrangedSubview(ASCIIButton(title: "Choose folder", target: self, action: #selector(chooseFolder)))
            let pause = ASCIIButton(title: "Pause", target: self, action: #selector(togglePause)); row.addArrangedSubview(pause); pauseButton = pause
            row.addArrangedSubview(ASCIIButton(title: "Open folder", target: self, action: #selector(openFolder))); stack.addArrangedSubview(row)
            let trash = ASCIIButton(checkboxWithTitle: "Move original to Trash", target: self, action: #selector(toggleTrash)); stack.addArrangedSubview(trash); trashButton = trash
            let strip = ASCIIButton(checkboxWithTitle: "Strip headers", target: self, action: #selector(toggleStripHeaders)); stack.addArrangedSubview(strip); stripButton = strip
            let auto = ASCIIButton(checkboxWithTitle: "Auto headers", target: self, action: #selector(toggleAutoHeaders)); stack.addArrangedSubview(auto); autoButton = auto
            let login = ASCIIButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLogin)); stack.addArrangedSubview(login); loginButton = login
            let retention = HistorySettingsView(history: history)
            retention.didChange = { [weak self] in self?.recentView?.reload(); self?.refreshLatest() }
            stack.addArrangedSubview(retention); retention.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let tools = NSStackView(); tools.orientation = .horizontal; tools.spacing = 4
            for (title, action) in [("Retry files", #selector(retry)), ("Quit", #selector(quit))] {
                let button = ASCIIButton(title: title, target: self, action: action); button.font = ASCIIStyle.font(); tools.addArrangedSubview(button)
            }
            stack.addArrangedSubview(tools)
            let credit = ASCIIButton(title: "Made with love by pivnev.design", target: self, action: #selector(openWebsite)); credit.font = ASCIIStyle.font()
            let feedback = ASCIIButton(title: "Feedback: hi@pivnev.design", target: self, action: #selector(openFeedback)); feedback.font = ASCIIStyle.font()
            let links = NSStackView(); links.orientation = .vertical; links.alignment = .leading; links.addArrangedSubview(credit); links.addArrangedSubview(feedback); stack.addArrangedSubview(links)
            controls = window; selectControlsTab()
            window.center()
            if let screen = window.screen {
                var frame = window.frame
                frame.origin.y = min(frame.origin.y, screen.visibleFrame.maxY - frame.height - 115)
                frame.origin.y = max(screen.visibleFrame.minY + 8, frame.origin.y)
                window.setFrame(frame, display: false)
            }
            window.attachClip()
        }
        refreshStatus(); NSApp.activate(ignoringOtherApps: true)
        recentView?.reload(); refreshLatest()
        if controls?.isMiniaturized == true { controls?.deminiaturize(nil) }
        controls?.makeKeyAndOrderFront(nil)
        (controls as? ClipboardWindow)?.showClip()
    }
    @objc private func selectControlsTab() {
        tabs?.selectPage( "controls"); controlsTabButton?.state = .on; historyTabButton?.state = .off
    }
    @objc private func selectHistoryTab() {
        tabs?.selectPage( "recent"); controlsTabButton?.state = .off; historyTabButton?.state = .on
    }
    @objc private func showRecentImports() { showControls(); selectHistoryTab() }
    @objc private func closeWindow() { controls?.orderOut(nil); (controls as? ClipboardWindow)?.clipPanel?.orderOut(nil) }
    @objc private func minimizeWindow() { controls?.miniaturize(nil) }
    @objc private func zoomWindow() {
        guard let window = controls, let screen = window.screen else { return }
        let area = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        if let original = restoreWindowFrame {
            window.setFrame(original, display: true); restoreWindowFrame = nil
        } else {
            restoreWindowFrame = window.frame
            window.setFrame(NSRect(x: area.minX, y: area.minY, width: area.width, height: max(650, area.height - 107)), display: true)
        }
    }
    @objc private func openFolder() { if let folder { NSWorkspace.shared.open(folder) } }
    private static let asciiTitle: String = {
        let glyphs: [Character: [String]] = [
            "P": [" ____  ", "|  _ \\ ", "| |_) |", "|  __/ ", "|_|    "],
            "G": ["  ____ ", " / ___|", "| |  _ ", "| |_| |", " \\____|"],
            "N": [" _   _ ", "| \\ | |", "|  \\| |", "| |\\  |", "|_| \\_|"],
            "C": ["  ____ ", " / ___|", "| |    ", "| |___ ", " \\____|"],
            "L": [" _     ", "| |    ", "| |    ", "| |___ ", "|_____|"],
            "I": [" ___ ", "|_ _|", " | | ", " | | ", "|___|"],
            "B": [" ____  ", "| __ ) ", "|  _ \\ ", "| |_) |", "|____/ "],
            "O": ["  ___  ", " / _ \\ ", "| | | |", "| |_| |", " \\___/ "],
            "A": ["    _    ", "   / \\   ", "  / _ \\  ", " / ___ \\ ", "/_/   \\_\\"],
            "R": [" ____  ", "|  _ \\ ", "| |_) |", "|  _ < ", "|_| \\_\\"],
            "D": [" ____  ", "|  _ \\ ", "| | | |", "| |_| |", "|____/ "], " ": Array(repeating: "   ", count: 5)
        ]
        return (0..<5).map { row in "PGN CLIPBOARD".map { glyphs[$0]![row] }.joined(separator: " ") }.joined(separator: "\n")
    }()
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
        let alert = NSAlert(); alert.messageText = "PGN Clipboard " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        alert.informativeText = "WATCH. IMPORT. CLEAN. COPY.\n\nNew .pgn files are copied after at least 3 seconds without changes, saved in Recent Imports, then optionally moved to Trash. Search your local history and copy originals or apply your current formatting. History retention is configurable in Controls.\n\nNo network access. No analytics. No Full Disk Access."
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
            if let id = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: id) }
            defaults.synchronize()
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
