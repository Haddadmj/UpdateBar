// Generates Resources/dmg-background.tiff — the picture behind the installer
// window, in the app icon's colours, with an arrow from the app to Applications.
//
// Run it after changing the design or the icon positions in release.sh; the
// .tiff is committed so a plain build doesn't need this script:
//   swift scripts/make-dmg-background.swift

import AppKit

let canvas = NSSize(width: 660, height: 400)

/// Where release.sh places the two icons, measured from the top-left as
/// Finder does. Kept in step by hand: the arrow has to span the gap between them.
let iconCentreY: CGFloat = 170
let appCentreX: CGFloat = 180
let applicationsCentreX: CGFloat = 480

/// A graphite ground, to suit the icon's dark rendering. Finder picks the icon
/// labels' colour itself and offers no way to set it, so they may be black or
/// white; this is as dark as it can go with black labels still legible.
let groundTop = NSColor(srgbRed: 0.40, green: 0.41, blue: 0.44, alpha: 1)
let groundBottom = NSColor(srgbRed: 0.32, green: 0.33, blue: 0.36, alpha: 1)

/// Faint concentric rings, echoing the icon's circle, too quiet to compete with it.
func drawRings(around centre: NSPoint) {
    NSColor.white.withAlphaComponent(0.07).setStroke()
    for radius in stride(from: CGFloat(120), through: 520, by: 80) {
        let ring = NSBezierPath(ovalIn: NSRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2
        ))
        ring.lineWidth = 1.5
        ring.stroke()
    }
}

func drawArrow(y: CGFloat) {
    // Clear of both 128pt icons, whose edges are 64pt from their centres.
    let start = appCentreX + 88
    let tip = applicationsCentreX - 88
    let headLength: CGFloat = 18
    let headHalfWidth: CGFloat = 13

    NSColor.white.set()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: start, y: y))
    shaft.line(to: NSPoint(x: tip - headLength, y: y))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: tip, y: y))
    head.line(to: NSPoint(x: tip - headLength, y: y + headHalfWidth))
    head.line(to: NSPoint(x: tip - headLength, y: y - headHalfWidth))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 4
    head.fill()
    head.stroke()
}

func drawCaption() {
    let text = NSAttributedString(string: "Drag UpdateBar to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
        .foregroundColor: NSColor.white,
    ])
    let size = text.size()
    // Well above the bottom edge: Finder's title bar takes its height out of the
    // window, so the last 30pt or so of the picture can be cut off.
    text.draw(at: NSPoint(x: (canvas.width - size.width) / 2, y: 62))
}

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width) * scale, pixelsHigh: Int(canvas.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = canvas

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(origin: .zero, size: canvas)
    NSGradient(colors: [groundTop, groundBottom])?.draw(in: bounds, angle: -90)
    let arrowY = canvas.height - iconCentreY
    drawRings(around: NSPoint(x: canvas.width / 2, y: arrowY))
    drawArrow(y: arrowY)
    drawCaption()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let work = root.appendingPathComponent(".build/dmg-background")
try? FileManager.default.removeItem(at: work)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let standard = work.appendingPathComponent("background.png")
let retina = work.appendingPathComponent("background@2x.png")
try render(scale: 1).write(to: standard)
try render(scale: 2).write(to: retina)

// A single multi-resolution file, so the window stays sharp on Retina displays.
let output = root.appendingPathComponent("Resources/dmg-background.tiff")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
task.arguments = ["-cathidpicheck", standard.path, retina.path, "-out", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("error: tiffutil failed\n".utf8))
    exit(1)
}
print("wrote \(output.path)")
