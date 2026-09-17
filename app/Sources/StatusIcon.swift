import AppKit

/// A template silhouette, independent of Unicode/emoji font rendering.
enum StatusIcon {
    static func pawn() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6, y: 11, width: 6, height: 6)).fill()
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 8, width: 5, height: 4), xRadius: 1, yRadius: 1).fill()
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 7, y: 9))
            body.line(to: NSPoint(x: 11, y: 9))
            body.line(to: NSPoint(x: 14, y: 3))
            body.line(to: NSPoint(x: 4, y: 3))
            body.close(); body.fill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 1, width: 12, height: 3), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PGN Clipboard"
        return image
    }
    static func image(paused: Bool, hasError: Bool) -> NSImage {
        let symbol = hasError ? "exclamationmark.triangle.fill" : (paused ? "pause.fill" : "")
        guard !symbol.isEmpty,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PGN Clipboard") else { return pawn() }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
