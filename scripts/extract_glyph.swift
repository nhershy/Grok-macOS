// Extracts the white glyph from full-bleed icon artwork (white glyph on
// black background) into a white-on-transparent 1024px PNG, suitable as an
// Icon Composer layer image. Alpha is taken from source luminance.
//
// Usage: swift extract_glyph.swift grok-icon-source.webp glyph.png
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fatalError("usage: extract_glyph <in-image> <out.png>")
}
guard let source = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("cannot load \(arguments[1])")
}

let side = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("cannot create bitmap")
}
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

// Premultiplied RGBA: luminance becomes alpha, color stays white.
guard let data = rep.bitmapData else { fatalError("no bitmap data") }
let rowBytes = rep.bytesPerRow
for y in 0..<side {
    let row = data + y * rowBytes
    for x in 0..<side {
        let p = row + x * 4
        let luminance = max(p[0], max(p[1], p[2]))
        p[0] = luminance
        p[1] = luminance
        p[2] = luminance
        p[3] = luminance
    }
}

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode png")
}
try png.write(to: URL(fileURLWithPath: arguments[2]))
print("wrote \(arguments[2])")
