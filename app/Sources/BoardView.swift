import AppKit

enum ASCIIStyle {
    static let paper = NSColor(white: 0.045, alpha: 1)
    static let ink = NSColor(white: 0.90, alpha: 1)
    static let dim = NSColor(white: 0.53, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.0, green: 0.8, blue: 1.0, alpha: 1)
    static func font(_ size: CGFloat = 12) -> NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
    static func text(_ string: String, at point: NSPoint, size: CGFloat = 12, color: NSColor = ink) {
        (string as NSString).draw(at: point, withAttributes: [.font: font(size), .foregroundColor: color])
    }
    static func frame(_ rect: NSRect) {
        let font = self.font(11)
        let glyph = ("M" as NSString).size(withAttributes: [.font: font])
        let columns = max(2, Int(rect.width / glyph.width))
        let right = rect.minX + CGFloat(columns - 1) * glyph.width
        let top = rect.maxY - glyph.height
        let edge = "+" + String(repeating: "-", count: columns - 2) + "+"
        text(edge, at: NSPoint(x: rect.minX, y: top), size: 11, color: dim)
        text(edge, at: NSPoint(x: rect.minX, y: rect.minY), size: 11, color: dim)
        var y = rect.minY + glyph.height
        while y < top - glyph.height * 0.4 {
            text("|", at: NSPoint(x: rect.minX, y: y), size: 11, color: dim)
            text("|", at: NSPoint(x: right, y: y), size: 11, color: dim)
            y += glyph.height
        }
    }
}

class ASCIIFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) { ASCIIStyle.frame(bounds.insetBy(dx: 2, dy: 2)) }
}
/// Both pages remain constrained to one stable viewport; changing visibility never
/// changes the window's Auto Layout constraint graph.
final class PageHostView: NSView {
    private var pages: [String: NSView] = [:]
    func addPage(_ view: NSView, identifier: String) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view); pages[identifier] = view
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        view.isHidden = true
    }
    func selectPage(_ identifier: String) {
        for (key, page) in pages { page.isHidden = key != identifier }
    }
}

final class BoardView: ASCIIFrameView {
    override func draw(_ dirtyRect: NSRect) {
        ASCIIStyle.paper.setFill(); bounds.fill()
        ASCIIStyle.frame(bounds.insetBy(dx: 6, dy: 6))
    }
}

/// AppKit continues to own tracking, targets, keyboard activation and accessibility.
/// Only the cell's visible representation changes: no native bezel or checkbox icon.
final class ASCIIButtonCell: NSButtonCell {
    var checkbox = false
    var hovered = false
    var feedbackActive = false
    var persistent = false
    override var cellSize: NSSize {
        let label = checkbox ? "[x] " + title : "[ " + title + " ]"
        let size = (label as NSString).size(withAttributes: [.font: font ?? ASCIIStyle.font()])
        return NSSize(width: ceil(size.width) + 8, height: 26)
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let marked = isHighlighted || feedbackActive || (persistent && state == .on)
        let label = checkbox ? (state == .on ? "[x] " : "[ ] ") + title
            : (marked ? "> " + title + " <" : "[ " + title + " ]")
        let color = !isEnabled ? NSColor(white: 0.32, alpha: 1) : ((marked || hovered) ? ASCIIStyle.accent : ASCIIStyle.ink)
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? ASCIIStyle.font(), .foregroundColor: color]
        let size = (label as NSString).size(withAttributes: attributes)
        let x = checkbox ? cellFrame.minX + 3 : cellFrame.midX - size.width / 2
        (label as NSString).draw(at: NSPoint(x: x, y: cellFrame.midY - size.height / 2), withAttributes: attributes)
    }
}

final class ASCIIButton: NSButton {
    var persistentSelection = false { didSet { (cell as? ASCIIButtonCell)?.persistent = persistentSelection } }
    private var hoverArea: NSTrackingArea?
    private var feedbackReset: DispatchWorkItem?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { (cell as? ASCIIButtonCell)?.hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { (cell as? ASCIIButtonCell)?.hovered = false; needsDisplay = true }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        let result = super.sendAction(action, to: target)
        if !persistentSelection && (cell as? ASCIIButtonCell)?.checkbox != true {
            state = .off; (cell as? ASCIIButtonCell)?.feedbackActive = true; needsDisplay = true
            feedbackReset?.cancel()
            let reset = DispatchWorkItem { [weak self] in
                (self?.cell as? ASCIIButtonCell)?.feedbackActive = false
                self?.state = .off; self?.needsDisplay = true
            }
            feedbackReset = reset; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
        }
        return result
    }
    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        cell = ASCIIButtonCell(textCell: title)
        self.title = title; self.target = target; self.action = action
        isBordered = false; focusRingType = .none; font = ASCIIStyle.font()
        setButtonType(.momentaryPushIn)
    }
    convenience init(checkboxWithTitle title: String, target: AnyObject?, action: Selector?) {
        self.init(title: title, target: target, action: action)
        setButtonType(.switch); (cell as? ASCIIButtonCell)?.checkbox = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override var intrinsicContentSize: NSSize { cell?.cellSize ?? NSSize(width: 80, height: 26) }
    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

final class ASCIIScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        ASCIIStyle.paper.setFill(); bounds.fill()
        guard isEnabled else { return }
        let knob = rect(for: .knob)
        let x = bounds.midX - 3.5
        var y: CGFloat = 13
        while y < bounds.height - 13 {
            ASCIIStyle.text(knob.minY <= y && y <= knob.maxY ? "#" : ":", at: NSPoint(x: x, y: y), size: 11, color: knob.minY <= y && y <= knob.maxY ? ASCIIStyle.ink : ASCIIStyle.dim)
            y += 13
        }
        ASCIIStyle.text("^", at: NSPoint(x: x, y: 0), size: 11, color: ASCIIStyle.dim)
        ASCIIStyle.text("v", at: NSPoint(x: x, y: bounds.height - 13), size: 11, color: ASCIIStyle.dim)
    }
}

final class ASCIIRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        ASCIIStyle.text(">", at: NSPoint(x: 4, y: bounds.midY - 7), color: ASCIIStyle.accent)
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect: NSRect) { }
    override func drawSeparator(in dirtyRect: NSRect) { }
}

/// Transparent child panel attached to the real window, not a simulated clipped image.
final class ClipboardWindow: NSWindow, NSWindowDelegate {
    private(set) var clipPanel: NSPanel?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        showClip()
    }
    override func orderOut(_ sender: Any?) {
        clipPanel?.orderOut(sender)
        super.orderOut(sender)
    }
    func attachClip() {
        delegate = self
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        let image = NSImageView(); image.imageScaling = .scaleProportionallyUpOrDown
        if let url = Bundle.main.url(forResource: "ClipboardClip", withExtension: "png") { image.image = NSImage(contentsOf: url) }
        panel.contentView = image; clipPanel = panel
        updateClipFrame(); addChildWindow(panel, ordered: .above)
    }
    func updateClipFrame() {
        let width: CGFloat = 310, height: CGFloat = 155
        clipPanel?.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - 48, width: width, height: height), display: true)
    }
    func windowDidResize(_ notification: Notification) { updateClipFrame() }
    func windowDidMove(_ notification: Notification) { updateClipFrame() }
    func windowDidBecomeKey(_ notification: Notification) { showClip() }
    func windowDidDeminiaturize(_ notification: Notification) { showClip() }
    func windowWillClose(_ notification: Notification) { clipPanel?.orderOut(nil) }
    func showClip() {
        guard isVisible && !isMiniaturized else { clipPanel?.orderOut(nil); return }
        updateClipFrame(); clipPanel?.orderFront(nil)
    }
}

final class WindowDragArea: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
final class HistorySettingsView: ASCIIFrameView {
    private let history: RecentImports
    private let queue = DispatchQueue(label: "design.pivnev.pgnclipboard.retention", qos: .utility)
    private let status = NSTextField(wrappingLabelWithString: "Loading...")
    private(set) var selectedDays = 0
    private(set) var choices: [ASCIIButton] = []
    var didChange: () -> Void = {}
    init(history: RecentImports) {
        self.history = history; super.init(frame: .zero)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14), stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
        func label(_ text: String, size: CGFloat = 11) {
            let field = NSTextField(wrappingLabelWithString: text); field.font = ASCIIStyle.font(size); field.textColor = ASCIIStyle.ink
            stack.addArrangedSubview(field); field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        label("AUTO-DELETE HISTORY")
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 0
        for days in [0, 7, 30, 90, 180, 365] {
            let button = ASCIIButton(title: days == 0 ? "Never" : "\(days)d", target: self, action: #selector(selectPeriod(_:)))
            button.persistentSelection = true; button.tag = days; button.font = ASCIIStyle.font(); button.isEnabled = false
            button.setAccessibilityLabel(days == 0 ? "Never delete history" : "Retain \(days) days")
            choices.append(button); row.addArrangedSubview(button)
        }
        stack.addArrangedSubview(row)
        label("Delete imports older than the selected age.\nChanges save immediately.")
        status.font = ASCIIStyle.font(); status.textColor = ASCIIStyle.dim; status.maximumNumberOfLines = 2
        stack.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        queue.async { [weak self] in
            guard let self else { return }; let result = Result { try history.retentionDays() }
            DispatchQueue.main.async {
                switch result {
                case .success(let days): self.select(days: days); self.setEnabled(true); self.status.stringValue = days == 0 ? "Saved: keep all imports." : "Saved: keep \(days) days."
                case .failure(let error): self.status.stringValue = error.localizedDescription
                }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    private func setEnabled(_ enabled: Bool) { choices.forEach { $0.isEnabled = enabled } }
    func select(days: Int) { selectedDays = days; choices.forEach { $0.state = $0.tag == days ? .on : .off } }
    @objc private func selectPeriod(_ sender: NSButton) {
        select(days: sender.tag); save()
    }
    @objc private func save() {
        let days = selectedDays; setEnabled(false); status.stringValue = "Applying..."
        queue.async { [weak self] in
            guard let self else { return }; let result = Result { try self.history.setRetention(days: days) }
            DispatchQueue.main.async {
                self.setEnabled(true)
                switch result {
                case .success: self.status.stringValue = days == 0 ? "Saved: keep all imports." : "Saved: keep \(days) days. Expired imports removed."; self.didChange()
                case .failure(let error): self.status.stringValue = "Could not apply: \(error.localizedDescription)"
                }
            }
        }
    }
}
