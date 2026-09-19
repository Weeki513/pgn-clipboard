import AppKit

/// Standard text selection, context menu and keyboard copy, even in an accessory app.
final class PGNTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if event.charactersIgnoringModifiers == "c" { copy(nil); return true }
            if event.charactersIgnoringModifiers == "a" { selectAll(nil); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class ImportDetailView: ASCIIFrameView {
    let title = NSTextField(labelWithString: "Select an import")
    let subtitle = NSTextField(labelWithString: "ORIGINAL PGN / select text to copy")
    let text = PGNTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let formatted = ASCIIButton(title: "Copy formatted", target: nil, action: nil)
    let raw = ASCIIButton(title: "Copy raw", target: nil, action: nil)
    let feedback = NSTextField(labelWithString: "")
    var options: () -> HeaderOptions = { HeaderOptions() }
    var copyText: (String) -> Bool = { _ in false }
    var isLatest = false
    var trashEnabled: () -> Bool = { false }
    private(set) var entry: RecentImport?
    func refreshPreview() {
        title.stringValue = (isLatest ? "LATEST IMPORT / " : "") + (entry?.filename ?? "No import yet")
        subtitle.stringValue = isLatest
            ? (trashEnabled() ? "Next imports: original -> Trash" : "Next imports: keep original file")
            : "FORMATTED PGN / select text to copy"
        guard let entry else { return }
        let value = PGNFormatter.format(entry.original, options: options())
        if text.string != value { text.string = value; text.scrollToBeginningOfDocument(nil) }
        text.setAccessibilityLabel("Formatted PGN preview")
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        title.font = ASCIIStyle.font()
        title.lineBreakMode = .byTruncatingMiddle; stack.addArrangedSubview(title)
        title.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        subtitle.font = ASCIIStyle.font(); subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail; stack.addArrangedSubview(subtitle)
        subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.scrollerStyle = .legacy; scroll.verticalScroller = ASCIIScroller()
        scroll.borderType = .noBorder; scroll.drawsBackground = true; scroll.backgroundColor = ASCIIStyle.paper
        text.isEditable = false; text.isSelectable = true; text.isRichText = false; text.allowsUndo = false
        text.font = ASCIIStyle.font()
        text.backgroundColor = scroll.backgroundColor; text.textColor = ASCIIStyle.ink
        text.insertionPointColor = ASCIIStyle.accent
        text.selectedTextAttributes = [.backgroundColor: NSColor(white: 0.25, alpha: 1), .foregroundColor: ASCIIStyle.ink]
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.minSize = .zero; text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel("Original PGN preview")
        scroll.documentView = text; stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let bar = NSStackView(); bar.orientation = .horizontal; bar.spacing = 8
        formatted.target = self; formatted.action = #selector(copyFormatted)
        raw.target = self; raw.action = #selector(copyRaw)
        formatted.toolTip = "Apply the current Strip headers and Auto headers settings."
        raw.toolTip = "Copy the exact original text, including all headers and whitespace."
        for button in [formatted, raw] { button.font = ASCIIStyle.font(); bar.addArrangedSubview(button) }
        stack.addArrangedSubview(bar)
        feedback.font = ASCIIStyle.font(); feedback.textColor = .secondaryLabelColor
        feedback.lineBreakMode = .byTruncatingTail; stack.addArrangedSubview(feedback)
        feedback.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        show(nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func show(_ value: RecentImport?) {
        let changed = entry?.id != value?.id
        entry = value
        title.stringValue = value?.filename ?? "Select an import"
        title.toolTip = value?.filename
        if changed || value == nil {
            text.string = value?.original ?? "Your PGN appears here.\n\nSelect a saved import from the list."
            text.scrollToBeginningOfDocument(nil); feedback.stringValue = ""
        }
        refreshPreview()
        formatted.isEnabled = value != nil; raw.isEnabled = value != nil
    }
    @objc func copyFormatted() {
        guard let entry else { return }
        feedback.stringValue = copyText(PGNFormatter.format(entry.original, options: options())) ? "Copied with current formatting." : "Copy failed. Try again."
    }
    @objc func copyRaw() {
        guard let entry else { return }
        feedback.stringValue = copyText(entry.original) ? "Copied exact original PGN." : "Copy failed. Try again."
    }
}

final class RecentImportsView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let history: RecentImports
    private let queue = DispatchQueue(label: "design.pivnev.pgnclipboard.history-ui", qos: .userInitiated)
    private var generation = 0
    private var pendingSearch: DispatchWorkItem?
    private var entries: [ImportSummary] = []
    private var offset = 0
    private let pageSize = 50
    private var matching = 0
    private var restoringSelection = false
    let table = NSTableView()
    let search = NSTextField()
    let detail = ImportDetailView()
    private let summary = NSTextField(labelWithString: "Loading history...")
    private let feedback = NSTextField(labelWithString: "")
    private let selection = ASCIIButton(title: "Select page", target: nil, action: nil)
    private let deleteSelected = ASCIIButton(title: "Delete selected", target: nil, action: nil)
    private let previous = ASCIIButton(title: "Previous", target: nil, action: nil)
    private let next = ASCIIButton(title: "Next", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    var copyText: (String) -> Bool = { _ in false } { didSet { detail.copyText = copyText } }
    var options: () -> HeaderOptions = { HeaderOptions() } { didSet { detail.options = options } }

    init(history: RecentImports) {
        self.history = history
        super.init(frame: .zero)
        let layout = NSStackView(); layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 12
        layout.translatesAutoresizingMaskIntoConstraints = false; addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), layout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            layout.topAnchor.constraint(equalTo: topAnchor, constant: 18), layout.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
        search.placeholderString = "Search filenames, players, events or PGN text"; search.delegate = self
        search.isBordered = false; search.drawsBackground = false; search.focusRingType = .none; search.textColor = ASCIIStyle.ink; search.font = ASCIIStyle.font()
        search.setAccessibilityLabel("Search history")
        let searchBox = ASCIIFrameView(); let searchLabel = NSTextField(labelWithString: "SEARCH >")
        searchLabel.font = ASCIIStyle.font(); searchLabel.textColor = ASCIIStyle.dim
        let clear = ASCIIButton(title: "x", target: self, action: #selector(clearSearch)); clear.setAccessibilityLabel("Clear search")
        for view in [searchLabel, search, clear] { view.translatesAutoresizingMaskIntoConstraints = false; searchBox.addSubview(view) }
        layout.addArrangedSubview(searchBox)
        NSLayoutConstraint.activate([
            searchBox.widthAnchor.constraint(equalTo: layout.widthAnchor), searchBox.heightAnchor.constraint(equalToConstant: 44),
            searchLabel.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 14), searchLabel.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            search.leadingAnchor.constraint(equalTo: searchLabel.trailingAnchor, constant: 10), search.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            search.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -8), clear.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -10),
            clear.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor)
        ])
        summary.font = ASCIIStyle.font(); summary.textColor = .secondaryLabelColor; layout.addArrangedSubview(summary)
        let body = NSStackView(); body.orientation = .horizontal; body.alignment = .top; body.spacing = 12
        layout.addArrangedSubview(body); body.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        let left = NSStackView(); left.orientation = .vertical; left.alignment = .leading; left.spacing = 10
        body.addArrangedSubview(left); body.addArrangedSubview(detail)
        left.widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.40).isActive = true
        left.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        detail.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        detail.widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.60, constant: -12).isActive = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = false; scroll.scrollerStyle = .legacy; scroll.verticalScroller = ASCIIScroller()
        scroll.borderType = .noBorder; scroll.drawsBackground = false
        table.headerView = nil; table.rowHeight = 54; table.intercellSpacing = NSSize(width: 0, height: 4)
        table.backgroundColor = ASCIIStyle.paper
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.style = .plain; table.dataSource = self; table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("import")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel("Saved imports"); scroll.documentView = table
        let listFrame = ASCIIFrameView(); scroll.translatesAutoresizingMaskIntoConstraints = false; listFrame.addSubview(scroll)
        left.addArrangedSubview(listFrame)
        NSLayoutConstraint.activate([
            listFrame.widthAnchor.constraint(equalTo: left.widthAnchor), listFrame.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            scroll.leadingAnchor.constraint(equalTo: listFrame.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: listFrame.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: listFrame.topAnchor, constant: 16), scroll.bottomAnchor.constraint(equalTo: listFrame.bottomAnchor, constant: -16)
        ])
        let selectionBar = NSStackView(); selectionBar.orientation = .horizontal; selectionBar.spacing = 8
        selection.target = self; selection.action = #selector(selectPage)
        deleteSelected.target = self; deleteSelected.action = #selector(deleteSelection)
        selectionBar.addArrangedSubview(selection); selectionBar.addArrangedSubview(deleteSelected); left.addArrangedSubview(selectionBar)
        let pager = NSStackView(); pager.orientation = .horizontal; pager.spacing = 8
        previous.target = self; previous.action = #selector(previousPage)
        next.target = self; next.action = #selector(nextPage)
        pageLabel.font = ASCIIStyle.font()
        pager.addArrangedSubview(previous); pager.addArrangedSubview(pageLabel); pager.addArrangedSubview(next); left.addArrangedSubview(pager)
        for button in [selection, deleteSelected, previous, next] { button.font = ASCIIStyle.font() }
        feedback.stringValue = "Only local history is deleted. Original files and clipboard are unchanged."
        feedback.font = ASCIIStyle.font(); feedback.textColor = .secondaryLabelColor
        feedback.lineBreakMode = .byTruncatingTail; layout.addArrangedSubview(feedback)
        feedback.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    func controlTextDidChange(_ notification: Notification) {
        pendingSearch?.cancel(); offset = 0
        generation += 1 // invalidate an in-flight query as soon as the text changes
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingSearch = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    func reload() {
        generation += 1; let request = generation, query = search.stringValue, start = offset
        let selectedIDs = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.history.page(search: query, limit: self.pageSize, offset: start) }
            DispatchQueue.main.async {
                guard self.generation == request else { return }
                switch result {
                case .failure(let error): self.feedback.stringValue = "History unavailable: \(error.localizedDescription)"
                case .success(let page):
                    if start > 0 && page.rows.isEmpty {
                        self.offset = max(0, ((max(1, page.matchingCount) - 1) / self.pageSize) * self.pageSize); self.reload(); return
                    }
                    self.entries = page.rows; self.matching = page.matchingCount
                    self.summary.stringValue = "\(page.totalCount) imports | \(ByteCountFormatter.string(fromByteCount: page.storageBytes, countStyle: .file)) on disk | \(page.matchingCount) matching"
                    self.restoringSelection = true; self.table.reloadData()
                    let indexes = IndexSet(page.rows.indices.filter { selectedIDs.contains(page.rows[$0].id) })
                    self.table.selectRowIndexes(indexes, byExtendingSelection: false)
                    self.restoringSelection = false
                    self.pageLabel.stringValue = "\(page.matchingCount == 0 ? 0 : start + 1)-\(start + page.rows.count)"
                    self.previous.isEnabled = start > 0; self.next.isEnabled = start + page.rows.count < page.matchingCount
                    self.selection.isEnabled = !page.rows.isEmpty
                    self.updateSelection()
                    if page.rows.isEmpty { self.feedback.stringValue = query.isEmpty ? "No imports yet. New PGNs will appear here." : "No imports match this search." }
                    else { self.feedback.stringValue = "Cmd-click or Shift-click to select multiple imports. Select page affects only these 50 rows." }
                }
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ASCIIRowView() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = NSTableCellView(); cell.identifier = NSUserInterfaceItemIdentifier("import")
        let name = NSTextField(labelWithString: entry.filename)
        name.font = ASCIIStyle.font(); name.lineBreakMode = .byTruncatingMiddle
        let date = NSTextField(labelWithString: DateFormatter.localizedString(from: entry.importedAt, dateStyle: .medium, timeStyle: .short))
        date.font = ASCIIStyle.font(); date.textColor = .secondaryLabelColor
        for field in [name, date] { field.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(field) }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 20), name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10), name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
            date.leadingAnchor.constraint(equalTo: name.leadingAnchor), date.trailingAnchor.constraint(equalTo: name.trailingAnchor), date.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 4)
        ])
        cell.textField = name; cell.toolTip = entry.filename; return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { if !restoringSelection { updateSelection() } }
    private func updateSelection() {
        let count = table.selectedRowIndexes.count
        deleteSelected.isEnabled = count > 0; deleteSelected.title = count == 0 ? "Delete selected" : "Delete (\(count))"
        guard count == 1, entries.indices.contains(table.selectedRow) else { detail.show(nil); return }
        let id = entries[table.selectedRow].id, request = generation
        if detail.entry?.id != id { detail.show(nil) }
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.history.entry(id: id) }
            DispatchQueue.main.async {
                guard self.generation == request, self.table.selectedRowIndexes.count == 1,
                      self.entries.indices.contains(self.table.selectedRow), self.entries[self.table.selectedRow].id == id else { return }
                switch result {
                case .success(let entry): self.detail.show(entry)
                case .failure(let error): self.feedback.stringValue = error.localizedDescription
                }
            }
        }
    }
    @objc private func clearSearch() {
        search.stringValue = ""; controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        window?.makeFirstResponder(search)
    }
    @objc private func selectPage() { table.selectAll(nil) }
    @objc private func previousPage() { offset = max(0, offset - pageSize); table.deselectAll(nil); reload() }
    @objc private func nextPage() { offset += pageSize; table.deselectAll(nil); reload() }
    @objc private func deleteSelection() {
        let ids = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
        guard !ids.isEmpty else { return }
        // The selected set is bounded by the visible page, never the entire database.
        deleteSelected.isEnabled = false
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.history.remove(ids: ids) }
            DispatchQueue.main.async {
                switch result {
                case .success: self.table.deselectAll(nil); self.reload()
                case .failure(let error): self.feedback.stringValue = "Delete failed: \(error.localizedDescription)"; self.updateSelection()
                }
            }
        }
    }
}
