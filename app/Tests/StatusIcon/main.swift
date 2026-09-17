import AppKit

var checks = 0
func expect(_ value: Bool, _ label: String) {
    guard value else { fputs("FAIL: \(label)\n", stderr); exit(1) }
    checks += 1; print("PASS: \(label)")
}
for (name, paused, error) in [("Watching", false, false), ("Paused", true, false), ("Error", false, true)] {
    let image = StatusIcon.image(paused: paused, hasError: error)
    expect(image.isTemplate, "\(name) icon uses native template tinting")
    expect(image.size == NSSize(width: 18, height: 18), "\(name) icon fits the menu bar")
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
        fputs("FAIL: \(name) icon cannot be rasterized\n", stderr); exit(1)
    }
    var opaque = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 { opaque += 1 }
        }
    }
    expect(opaque > 10 && opaque < bitmap.pixelsWide * bitmap.pixelsHigh,
           "\(name) icon renders visible pixels on a transparent canvas")
}
print("\(checks) icon checks passed.")
