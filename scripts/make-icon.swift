import AppKit

// Original code-drawn icon: a product tile inside a selection on a transparent canvas.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 208, yRadius: 208).fill()
        let tile = NSRect(x: 208, y: 208, width: 608, height: 608)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile, xRadius: 28, yRadius: 28).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: tile, xRadius: 28, yRadius: 28).addClip()
        NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
        for y in 0..<8 {
            for x in 0..<8 where (x + y).isMultiple(of: 2) {
                NSRect(x: 208 + x * 76, y: 208 + y * 76, width: 76, height: 76).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 366, y: 326, width: 292, height: 372), xRadius: 72, yRadius: 72).fill()
        NSColor(calibratedRed: 0.13, green: 0.38, blue: 0.82, alpha: 1).setStroke()
        let selection = NSBezierPath(rect: NSRect(x: 320, y: 280, width: 384, height: 464))
        selection.lineWidth = 12; selection.stroke()
        for x in [320, 704] {
            for y in [280, 744] {
                let handle = NSBezierPath(roundedRect: NSRect(x: x - 23, y: y - 23, width: 46, height: 46), xRadius: 7, yRadius: 7)
                NSColor.white.setFill(); handle.fill(); handle.lineWidth = 9; handle.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
