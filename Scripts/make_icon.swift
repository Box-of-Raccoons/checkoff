// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift Scripts/make_icon.swift   (run from the repo root)
import AppKit

func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let unit = size / 1024

    // The standard macOS icon shape: an 824 pt rounded square on a 1024 pt canvas.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(
        starting: NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.0, alpha: 1),
        ending: NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.86, alpha: 1)
    )!.draw(in: shape, angle: -90)

    // A white task circle with a tick through it.
    NSColor.white.setStroke()
    let ring = NSBezierPath(ovalIn: tile.insetBy(dx: 190 * unit, dy: 190 * unit))
    ring.lineWidth = 56 * unit
    ring.stroke()

    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: 392 * unit, y: 512 * unit))
    tick.line(to: NSPoint(x: 478 * unit, y: 426 * unit))
    tick.line(to: NSPoint(x: 642 * unit, y: 606 * unit))
    tick.lineWidth = 64 * unit
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    tick.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Checkoff.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try drawIcon(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try convert.run()
convert.waitUntilExit()
exit(convert.terminationStatus)
