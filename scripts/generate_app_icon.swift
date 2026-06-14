#!/usr/bin/env swift
//
// Generates Delve's macOS app icon entirely in code - no design tools.
// Concept: the standard macOS rounded-square ("squircle") in the app's dark
// navy, holding a miniature treemap of vivid, sibling-distinct tiles - a tiny
// version of exactly what the app shows.
//
// Re-run to regenerate after tweaking colors/layout:
//   swift scripts/generate_app_icon.swift <AppIcon.appiconset path>
//
// Everything is drawn in a 1024-unit design space and rasterized natively at
// each target pixel size, so even the 16px icon stays crisp (no downscaling).

import AppKit
import CoreGraphics

let designSize: CGFloat = 1024

// macOS icon grid: an 824x824 body centered in 1024 with ~100px margins, so
// the system shadow and neighboring dock icons have breathing room.
let bodyInset: CGFloat = 100
let bodyRect = CGRect(x: bodyInset, y: bodyInset,
                      width: designSize - 2 * bodyInset,
                      height: designSize - 2 * bodyInset)
let bodyRadius: CGFloat = 184   // ~0.2237 * body width, Apple's continuous-corner look

// A hand-placed mini treemap inside the body (one dominant tile plus a packed
// cluster), with navy "grout" gaps showing the background between tiles. The
// index drives the color and is assigned largest-area-first, mirroring the app.
struct Tile { let rect: CGRect; let colorIndex: Int }
let tileRadius: CGFloat = 28
let tiles: [Tile] = [
    Tile(rect: CGRect(x: 172, y: 172, width: 350, height: 680), colorIndex: 0), // left, biggest
    Tile(rect: CGRect(x: 540, y: 172, width: 170, height: 300), colorIndex: 2), // right-top-left
    Tile(rect: CGRect(x: 728, y: 172, width: 124, height: 300), colorIndex: 3), // right-top-right
    Tile(rect: CGRect(x: 540, y: 490, width: 150, height: 362), colorIndex: 1), // bottom-left
    Tile(rect: CGRect(x: 708, y: 490, width: 144, height: 200), colorIndex: 4), // bottom-right-top
    Tile(rect: CGRect(x: 708, y: 708, width: 144, height: 144), colorIndex: 5), // bottom-right-bottom
]

// Sibling-distinct hue: identical to TreemapStyle.sliceColor in the app.
func sliceColor(_ index: Int, brightnessDelta: CGFloat = 0) -> NSColor {
    let golden = 0.6180339887498949
    let hue = (0.03 + Double(index) * golden).truncatingRemainder(dividingBy: 1)
    return NSColor(hue: CGFloat(hue), saturation: 0.60,
                   brightness: min(1, 0.80 + brightnessDelta), alpha: 1)
}

let navyTop = NSColor(hue: 0.62, saturation: 0.32, brightness: 0.24, alpha: 1)
let navyBottom = NSColor(hue: 0.65, saturation: 0.42, brightness: 0.12, alpha: 1)

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func verticalGradient(_ top: NSColor, _ bottom: NSColor) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: [top.cgColor, bottom.cgColor] as CFArray,
               locations: [0, 1])!
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    // Map the 1024 design space (origin top-left, y down) onto the pixel canvas.
    let scale = CGFloat(pixels) / designSize
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: designSize)
    ctx.scaleBy(x: 1, y: -1)

    let body = roundedPath(bodyRect, bodyRadius)

    // Soft drop shadow under the body, then the navy gradient fill on top.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 42,
                  color: NSColor.black.withAlphaComponent(0.32).cgColor)
    ctx.addPath(body)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(verticalGradient(navyTop, navyBottom),
                           start: CGPoint(x: bodyRect.midX, y: bodyRect.minY),
                           end: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
                           options: [])
    ctx.restoreGState()

    // The treemap tiles, each a vertical gradient (lighter on top) like the app.
    for tile in tiles {
        ctx.saveGState()
        ctx.addPath(roundedPath(tile.rect, tileRadius))
        ctx.clip()
        let top = sliceColor(tile.colorIndex, brightnessDelta: 0.10)
        let bottom = sliceColor(tile.colorIndex, brightnessDelta: -0.02)
        ctx.drawLinearGradient(verticalGradient(top, bottom),
                               start: CGPoint(x: tile.rect.midX, y: tile.rect.minY),
                               end: CGPoint(x: tile.rect.midX, y: tile.rect.maxY),
                               options: [])
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Each macOS AppIcon slot -> the exact pixel size it needs.
let slots: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let outURL = URL(fileURLWithPath: outDir, isDirectory: true)

for slot in slots {
    let data = renderPNG(pixels: slot.pixels)
    try! data.write(to: outURL.appendingPathComponent(slot.name))
    print("wrote \(slot.name) (\(slot.pixels)px)")
}
print("Done -> \(outDir)")
