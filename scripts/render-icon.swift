import AppKit

// Keep the source artwork full resolution; apply Dock sizing only when packaging.
guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift scripts/render-icon.swift source.png output.iconset")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Unable to create icon bitmap")
        }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let side = CGFloat(pixels)
        let canvas = NSRect(x: 0, y: 0, width: side, height: side)
        NSColor.clear.setFill()
        canvas.fill(using: .copy)
        // An 824-point tile inside a 1024-point canvas prevents an oversized Dock footprint.
        let tile = canvas.insetBy(dx: side * 100 / 1024, dy: side * 100 / 1024)
        let radius = tile.width * 0.22
        NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).addClip()
        source.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode icon bitmap")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
