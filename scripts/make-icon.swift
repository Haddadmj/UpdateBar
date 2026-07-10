#!/usr/bin/env swift
// Generates AppIcon.icns from an SF Symbol on a gradient background.
// Usage: swift scripts/make-icon.swift <output-dir>   (writes AppIcon.icns there)
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default
let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    color.set()
    let r = NSRect(origin: .zero, size: image.size)
    image.draw(in: r)
    r.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func render(_ px: Int) -> Data {
    let dim = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: dim, height: dim)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect gradient background (macOS-style corner radius).
    let inset = dim * 0.08
    let rect = NSRect(x: inset, y: inset, width: dim - 2 * inset, height: dim - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: dim * 0.2237, yRadius: dim * 0.2237)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.47, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.45, green: 0.28, blue: 0.88, alpha: 1)
    ])!
    gradient.draw(in: path, angle: -90)

    // Centered white SF Symbol.
    let config = NSImage.SymbolConfiguration(pointSize: dim * 0.52, weight: .semibold)
    if let base = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let sym = tinted(base, .white)
        let s = sym.size
        sym.draw(in: NSRect(x: (dim - s.width) / 2, y: (dim - s.height) / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// (pixelSize, filename) pairs for a complete iconset.
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (px, name) in variants {
    try! render(px).write(to: URL(fileURLWithPath: (iconset as NSString).appendingPathComponent(name)))
}

// Compile to .icns.
let icns = (outDir as NSString).appendingPathComponent("AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", icns]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)
print(p.terminationStatus == 0 ? "Wrote \(icns)" : "iconutil failed")
