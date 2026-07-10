#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift <output.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let temporaryRoot = fileManager.temporaryDirectory
    .appendingPathComponent("ReluxProxyIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = temporaryRoot.appendingPathComponent("ReluxProxy.iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryRoot) }

let representations: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024),
]

func renderIcon(pixels: Int, to url: URL) throws {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw CocoaError(.featureUnsupported)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext
    let scale = CGFloat(pixels) / 1_024
    context.scaleBy(x: scale, y: scale)

    let backgroundRect = NSRect(x: 48, y: 48, width: 928, height: 928)
    let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 218, yRadius: 218)
    let gradient = NSGradient(
        colorsAndLocations:
            (NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.32, alpha: 1), 0),
            (NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.88, alpha: 1), 0.62),
            (NSColor(calibratedRed: 0.27, green: 0.78, blue: 0.83, alpha: 1), 1)
    )!
    gradient.draw(in: background, angle: -42)

    NSColor.white.withAlphaComponent(0.14).setStroke()
    background.lineWidth = 14
    background.stroke()

    let tunnel = NSBezierPath()
    tunnel.move(to: NSPoint(x: 280, y: 512))
    tunnel.curve(
        to: NSPoint(x: 744, y: 512),
        controlPoint1: NSPoint(x: 400, y: 720),
        controlPoint2: NSPoint(x: 624, y: 304)
    )
    tunnel.lineWidth = 70
    tunnel.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.94).setStroke()
    tunnel.stroke()

    for point in [NSPoint(x: 256, y: 512), NSPoint(x: 768, y: 512)] {
        let outer = NSBezierPath(ovalIn: NSRect(x: point.x - 104, y: point.y - 104, width: 208, height: 208))
        NSColor.white.setFill()
        outer.fill()

        let inner = NSBezierPath(ovalIn: NSRect(x: point.x - 48, y: point.y - 48, width: 96, height: 96))
        NSColor(calibratedRed: 0.14, green: 0.28, blue: 0.72, alpha: 1).setFill()
        inner.fill()
    }

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url, options: .atomic)
}

for representation in representations {
    try renderIcon(
        pixels: representation.pixels,
        to: iconsetURL.appendingPathComponent(representation.name)
    )
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}
