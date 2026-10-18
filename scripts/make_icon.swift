#!/usr/bin/env swift
// Renders the ClipBar app icon (violet→cyan squircle with a clipboard glyph) at every size
// an .iconset needs. Usage: swift scripts/make_icon.swift <output.iconset> [extra-png-path size]
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make_icon.swift <output.iconset> [flat.png size]\n".data(using: .utf8)!)
    exit(1)
}
let iconsetURL = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    // macOS icons leave a margin: the squircle covers ~80% of the canvas.
    let inset = size * 0.1
    let squircle = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = squircle.width * 0.225
    let backgroundPath = NSBezierPath(roundedRect: squircle, xRadius: radius, yRadius: radius)

    // Soft drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.05, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    backgroundPath.fill()
    context.restoreGState()

    // Gradient background.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.09, blue: 0.48, alpha: 1),
        NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.83, blue: 0.93, alpha: 1),
    ])!
    gradient.draw(in: backgroundPath, angle: 55)

    // Specular highlight.
    context.saveGState()
    backgroundPath.addClip()
    let highlight = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0), 0.0),
        (NSColor.white.withAlphaComponent(0.06), 0.45),
        (NSColor.white.withAlphaComponent(0.3), 1.0))!
    highlight.draw(in: backgroundPath, angle: 90)
    context.restoreGState()

    // Clipboard board.
    let boardWidth = squircle.width * 0.5
    let boardHeight = squircle.height * 0.6
    let board = CGRect(x: squircle.midX - boardWidth / 2, y: squircle.midY - boardHeight / 2 - size * 0.02, width: boardWidth, height: boardHeight)
    let boardPath = NSBezierPath(roundedRect: board, xRadius: board.width * 0.12, yRadius: board.width * 0.12)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    boardPath.fill()
    context.restoreGState()

    // Clip at the top.
    let clipWidth = boardWidth * 0.42
    let clipHeight = boardHeight * 0.14
    let clip = CGRect(x: board.midX - clipWidth / 2, y: board.maxY - clipHeight * 0.55, width: clipWidth, height: clipHeight)
    NSColor(calibratedRed: 0.11, green: 0.07, blue: 0.3, alpha: 1).setFill()
    NSBezierPath(roundedRect: clip, xRadius: clipHeight * 0.4, yRadius: clipHeight * 0.4).fill()

    // Three "lines" of content, the middle one accented.
    let lineHeight = boardHeight * 0.075
    let lineInsetX = boardWidth * 0.16
    let lineColors = [
        NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.83, blue: 0.93, alpha: 1),
        NSColor(calibratedWhite: 0.78, alpha: 1),
    ]
    let lineWidths: [CGFloat] = [0.68, 0.5, 0.6]
    for (index, color) in lineColors.enumerated() {
        let y = board.maxY - clipHeight - boardHeight * 0.2 - CGFloat(index) * lineHeight * 2.4
        let rect = CGRect(x: board.minX + lineInsetX, y: y, width: boardWidth * lineWidths[index], height: lineHeight)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixelSize: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "make_icon", code: 1) }
    try data.write(to: url)
}

let master = drawIcon(size: 1024)
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in sizes {
    // Re-render at the native size so strokes stay crisp instead of downsampling the 1024 master.
    let image = entry.pixels >= 512 ? master : drawIcon(size: CGFloat(entry.pixels))
    try writePNG(image, pixelSize: entry.pixels, to: iconsetURL.appendingPathComponent("\(entry.name).png"))
}
if arguments.count >= 4, let flatSize = Int(arguments[3]) {
    try writePNG(master, pixelSize: flatSize, to: URL(fileURLWithPath: arguments[2]))
}
print("wrote \(sizes.count) icon sizes to \(iconsetURL.path)")
