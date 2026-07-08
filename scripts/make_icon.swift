// Renders the Grok app icon master as FULL-BLEED artwork: edge-to-edge
// black square with the glyph centered. macOS 26 masks and insets app
// icons itself — baking margins or rounded corners into the artwork makes
// the icon render smaller than its Dock neighbors (double margin).
//
// Usage:
//   swift make_icon.swift grok-icon-source.webp master.png
//   then sips -z the master into the AppIcon.appiconset slots (16..1024).
//
// Accepts any square artwork NSImage can load (webp/png/svg); a black fill
// underneath absorbs any transparent rounded corners in the source.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fatalError("usage: make_icon <glyph.svg> <out.png>")
}
guard let glyph = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("cannot load \(arguments[1])")
}

let canvas = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
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
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let fullCanvas = NSRect(x: 0, y: 0, width: canvas, height: canvas)
NSColor.black.setFill()
fullCanvas.fill()
glyph.draw(in: fullCanvas)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode png")
}
try png.write(to: URL(fileURLWithPath: arguments[2]))
print("wrote \(arguments[2])")
