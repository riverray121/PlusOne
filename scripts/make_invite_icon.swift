// Renders the friend-approval invitation thumbnail: minimalist add-person
// glyph on near-black, same palette as the app icon.
// Usage: swift scripts/make_invite_icon.swift <output.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "FriendInvite.png"
let px = 512

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: px, height: px)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: near-black, full bleed, matching the app icon.
NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.055, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: px, height: px).fill()

// Glyph: person.badge.plus, person white, plus badge green (the "+1").
// Palette order is badge-first for this symbol's layers.
let config = NSImage.SymbolConfiguration(pointSize: 200, weight: .medium)
    .applying(.init(paletteColors: [NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.29, alpha: 1), .white]))
guard let symbol = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: nil)?
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
