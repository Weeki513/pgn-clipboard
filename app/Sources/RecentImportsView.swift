import AppKit

private final class ImportButton: NSButton {
    var importID: UUID?
}

/// History management uses persisted snapshots, never the original file or live clipboard.
final class RecentImportsView: NSView {
    private let history: RecentImports
    private var entries: [RecentImport] = []
    private var selected = Set<UUID>()
    private let rows = NSStackView()
    private let selection = NSButton(checkboxWithTitle: "Select all", target: nil, action: nil)
    private let deleteSelected = NSButton(title: "Delete Selected", target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    var copyText: (String) -> Bool = { _ in false }

    init(history: RecentImports) {
        self.history = history
        super.init(frame: .zero)
        let layout = NSStackView(); layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 12
        layout.translatesAutoresizingMaskIntoConstraints = false; addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            layout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            layout.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            layout.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        let title = NSTextField(labelWithString: "Recent Imports")
        title.font = .systemFont(ofSize: 22, weight: .semibold); layout.addArrangedSubview(title)
        summary.textColor = .secondaryLabelColor; layout.addArrangedSubview(summary)
        let bar = NSStackView(); bar.orientation = .horizontal; bar.spacing = 12
        selection.allowsMixedState = true
        selection.target = self; selection.action = #selector(toggleAllImports)
        deleteSelected.target = self; deleteSelected.action = #selector(deleteSelection)
        bar.addArrangedSubview(selection); bar.addArrangedSubview(deleteSelected); layout.addArrangedSubview(bar)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView(); document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows); scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        layout.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        feedback.textColor = .secondaryLabelColor; feedback.font = .systemFont(ofSize: 11)
        feedback.stringValue = "Stored on this Mac. Deleting history does not change original files or the clipboard."
        layout.addArrangedSubview(feedback)
        feedback.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload() {
        do { entries = try history.entries() }
        catch { feedback.stringValue = "Could not load history: \(error.localizedDescription)"; return }
        selected.formIntersection(Set(entries.map(\.id)))
        for row in rows.arrangedSubviews { rows.removeArrangedSubview(row); row.removeFromSuperview() }
        summary.stringValue = "\(entries.count) of 10 saved imports · newest first"
        if entries.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "No recent imports yet.\nNew PGN files will appear here after importing.")
            empty.textColor = .secondaryLabelColor; rows.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        for entry in entries { addRow(entry) }
        updateSelection()
    }
    private func addRow(_ entry: RecentImport) {
        let card = NSStackView(); card.orientation = .vertical; card.alignment = .leading; card.spacing = 6
        card.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        card.wantsLayer = true; card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1; card.layer?.borderColor = NSColor.separatorColor.cgColor
        rows.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        let heading = NSStackView(); heading.orientation = .horizontal; heading.spacing = 8
        let check = ImportButton(checkboxWithTitle: entry.filename, target: self, action: #selector(toggleSelection(_:)))
        check.importID = entry.id; check.state = selected.contains(entry.id) ? .on : .off
        check.setAccessibilityLabel("Select \(entry.filename)")
        check.lineBreakMode = .byTruncatingMiddle; check.toolTip = entry.filename
        check.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        heading.addArrangedSubview(check)
        let spacer = NSView(); heading.addArrangedSubview(spacer)
        for (title, action) in [("Copy", #selector(copyEntry(_:))), ("Delete", #selector(deleteEntry(_:)))] {
            let button = ImportButton(title: title, target: self, action: action)
            button.importID = entry.id; button.setAccessibilityLabel("\(title) \(entry.filename)")
            heading.addArrangedSubview(button)
        }
        card.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -20).isActive = true
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
        let date = NSTextField(labelWithString: formatter.string(from: entry.importedAt))
        date.font = .systemFont(ofSize: 11); date.textColor = .secondaryLabelColor; card.addArrangedSubview(date)
        let preview = NSScrollView(); preview.hasVerticalScroller = true; preview.autohidesScrollers = true
        preview.borderType = .bezelBorder
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 0))
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 15; paragraph.maximumLineHeight = 15
        text.defaultParagraphStyle = paragraph
        text.string = entry.original
        text.textContainerInset = NSSize(width: 5, height: 4)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("PGN preview for \(entry.filename)")
        preview.documentView = text; card.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -20).isActive = true
        // Five rendered lines at most; wrapped lines and longer PGNs scroll vertically.
        preview.heightAnchor.constraint(equalToConstant: 5 * 15 + 10).isActive = true
    }
    private func updateSelection() {
        selection.isEnabled = !entries.isEmpty
        selection.state = selected.isEmpty ? .off : (selected.count == entries.count ? .on : .mixed)
        deleteSelected.isEnabled = !selected.isEmpty
        deleteSelected.title = selected.isEmpty ? "Delete Selected" : "Delete Selected (\(selected.count))"
    }
    @objc private func toggleAllImports() {
        selected = selected.count == entries.count ? [] : Set(entries.map(\.id)); reload()
    }
    @objc private func toggleSelection(_ sender: ImportButton) {
        guard let id = sender.importID else { return }
        if sender.state == .on { selected.insert(id) } else { selected.remove(id) }
        updateSelection()
    }
    @objc private func copyEntry(_ sender: ImportButton) {
        guard let entry = entries.first(where: { $0.id == sender.importID }) else { return }
        feedback.stringValue = copyText(entry.clipboardText)
            ? "Copied \(entry.filename)" : "Could not copy. Try again."
    }
    @objc private func deleteEntry(_ sender: ImportButton) {
        guard let id = sender.importID else { return }; remove([id])
    }
    @objc private func deleteSelection() { remove(selected) }
    private func remove(_ ids: Set<UUID>) {
        do { try history.remove(ids: ids); selected.subtract(ids); reload() }
        catch { feedback.stringValue = "Could not delete history: \(error.localizedDescription)" }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
