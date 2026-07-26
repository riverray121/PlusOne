// Renders the app icon: minimalist two-person glyph on near-black.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let px = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: px, height: px)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: near-black, full bleed (iOS applies its own corner mask).
NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.055, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: px, height: px).fill()

// Glyph: person.2.fill, front person white, back person green (the "+1").
let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
    .applying(.init(paletteColors: [.white, NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.29, alpha: 1)]))
guard let symbol = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config)
else {
    fatalError("symbol unavailable")
}

// Scale to 62% of the canvas width, centered.
let targetW = CGFloat(px) * 0.62
let scale = targetW / symbol.size.width
let targetH = symbol.size.height * scale
let origin = NSPoint(x: (CGFloat(px) - targetW) / 2, y: (CGFloat(px) - targetH) / 2)
symbol.draw(
    in: NSRect(origin: origin, size: NSSize(width: targetW, height: targetH)),
    from: .zero, operation: .sourceOver, fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("png encode failed")
}
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(px)x\(px))")
