#!/usr/bin/env swift
//
//  Generates the Domark app icon.
//
//  Run:    swift Icon/make-icon.swift
//  Output: Icon/Domark.icns       → the one that goes into the app
//          Icon/previews/*.png    → one preview per style, open them side by side
//
//  To change the look, edit `Style` below — the drawing code stays untouched.
//

import AppKit
import Foundation

// ══════════════════════════════════════════════════════════
//  Tweak everything here
// ══════════════════════════════════════════════════════════

/// The mark drawn on the icon
enum Glyph: String, CaseIterable {
    case arrow  // chevron over a bar — the markdown mark
    case page   // folded-corner page with the markdown mark on it
    case face   // folded-corner page with a smiley
}

enum Style {
    /// ⬅︎ Pick the style here: .arrow / .page / .face
    static let glyph: Glyph = .face

    /// Background gradient, top to bottom
    static let gradientTop = hex("#FFB199")
    static let gradientBottom = hex("#FF7B8A")

    static let paper = NSColor.white
    /// Colour of the mark on the paper — reusing the background colour keeps it cohesive
    static var ink: NSColor { hex("#FF7B8A") }

    /// Transparent margin around the icon — macOS convention is about 0.09
    static let padding: CGFloat = 0.09

    /// Squircle roundness: 4 = very round, 8 = closer to a square (Apple uses about 5)
    static let squircle: CGFloat = 5.0

    /// Soft highlight across the top. Set to 0 to remove it.
    static let glossOpacity: CGFloat = 0.18
}

func hex(_ string: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: string.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

// ══════════════════════════════════════════════════════════
//  Drawing helpers
// ══════════════════════════════════════════════════════════

/// The squircle (superellipse) shape macOS uses.
/// `NSBezierPath(roundedRect:)` gives circular corners, which do not match system icons.
func squircle(in rect: CGRect, exponent: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 720
    let a = rect.width / 2, b = rect.height / 2
    let power = 2.0 / Double(exponent)

    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * CGFloat(copysign(pow(abs(c), power), c))
        let y = rect.midY + b * CGFloat(copysign(pow(abs(s), power), s))
        let point = CGPoint(x: x, y: y)
        step == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    return path
}

/// Fills a polygon with rounded corners.
///
/// NSBezierPath has no API for rounding an arbitrary shape, so fill it and stroke over the top
/// with a `radius * 2` round-joined line: the edge grows by exactly `radius` with rounded corners.
func fillRounded(_ points: [CGPoint], radius: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    path.lineJoinStyle = .round
    path.lineWidth = radius * 2
    color.setFill()
    color.setStroke()
    path.fill()
    path.stroke()
}

func strokePath(_ points: [CGPoint], width: CGFloat, color: NSColor, closed: Bool = false) {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    if closed { path.close() }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

// ══════════════════════════════════════════════════════════
//  The individual marks
// ══════════════════════════════════════════════════════════

/// `p(x, y)` maps 0–1 coordinates onto the icon (0,0 is bottom-left)
typealias Mapper = (CGFloat, CGFloat) -> CGPoint

func drawArrow(_ p: Mapper, scale: CGFloat) {
    let stroke = scale * 0.105
    strokePath([p(0.315, 0.635), p(0.5, 0.485), p(0.685, 0.635)], width: stroke, color: Style.paper)
    strokePath([p(0.295, 0.330), p(0.705, 0.330)], width: stroke, color: Style.paper)
}

/// The folded-corner page, shared by .page and .face
func drawPaper(_ p: Mapper, scale: CGFloat) {
    let radius = scale * 0.040
    let left: CGFloat = 0.262, right: CGFloat = 0.738
    let bottom: CGFloat = 0.158, top: CGFloat = 0.842
    let fold: CGFloat = 0.122

    // Inset by radius first, since the stroke grows it back by the same amount
    let inset = radius / scale
    let l = left + inset, r = right - inset
    let b = bottom + inset, t = top - inset

    fillRounded(
        [p(l, b), p(l, t), p(r - fold, t), p(r, t - fold), p(r, b)],
        radius: radius, color: Style.paper
    )

    // The fold: a paler triangle so the corner reads as folded over
    fillRounded(
        [p(r - fold, t), p(r, t - fold), p(r - fold, t - fold)],
        radius: radius * 0.35, color: Style.ink.withAlphaComponent(0.20)
    )
}

func drawPage(_ p: Mapper, scale: CGFloat) {
    drawPaper(p, scale: scale)
    let stroke = scale * 0.050
    strokePath([p(0.392, 0.565), p(0.500, 0.462), p(0.608, 0.565)], width: stroke, color: Style.ink)
    strokePath([p(0.380, 0.330), p(0.620, 0.330)], width: stroke, color: Style.ink)
}

func drawFace(_ p: Mapper, scale: CGFloat) {
    drawPaper(p, scale: scale)
    let eye = scale * 0.030
    Style.ink.setFill()
    for x in [CGFloat(0.425), CGFloat(0.575)] {
        let center = p(x, 0.545)
        NSBezierPath(ovalIn: CGRect(
            x: center.x - eye, y: center.y - eye, width: eye * 2, height: eye * 2
        )).fill()
    }

    // The smile, a single curve
    let smile = NSBezierPath()
    smile.move(to: p(0.430, 0.420))
    smile.curve(to: p(0.570, 0.420), controlPoint1: p(0.470, 0.355), controlPoint2: p(0.530, 0.355))
    smile.lineWidth = scale * 0.040
    smile.lineCapStyle = .round
    Style.ink.setStroke()
    smile.stroke()
}

// ══════════════════════════════════════════════════════════
//  Assembling the icon
// ══════════════════════════════════════════════════════════

func drawIcon(size: CGFloat, glyph: Glyph) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // The icon's real area, leaving the transparent margin macOS expects
    let inset = size * Style.padding
    let art = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    context.saveGState()
    squircle(in: art, exponent: Style.squircle).setClip()
    NSGradient(starting: Style.gradientBottom, ending: Style.gradientTop)!.draw(in: art, angle: 90)
    if Style.glossOpacity > 0 {
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(Style.glossOpacity),
            NSColor.white.withAlphaComponent(0),
        ])!.draw(in: CGRect(x: art.minX, y: art.midY, width: art.width, height: art.height / 2), angle: -90)
    }
    context.restoreGState()

    let map: Mapper = { x, y in
        CGPoint(x: art.minX + art.width * x, y: art.minY + art.height * y)
    }
    switch glyph {
    case .arrow: drawArrow(map, scale: art.width)
    case .page: drawPage(map, scale: art.width)
    case .face: drawFace(map, scale: art.width)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// ══════════════════════════════════════════════════════════
//  Writing the files
// ══════════════════════════════════════════════════════════

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Icon")
let fm = FileManager.default

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try png.write(to: url)
}

// One preview per style, for comparing them side by side
let previews = root.appendingPathComponent("previews")
try? fm.removeItem(at: previews)
try fm.createDirectory(at: previews, withIntermediateDirectories: true)
for glyph in Glyph.allCases {
    try write(drawIcon(size: 512, glyph: glyph), to: previews.appendingPathComponent("\(glyph.rawValue).png"))
}

/// (filename, real pixel size) — every size is drawn fresh rather than downscaled, so small ones stay crisp
let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let iconset = root.appendingPathComponent("Domark.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in variants {
    try write(drawIcon(size: size, glyph: Style.glyph), to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Domark.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
try? fm.removeItem(at: iconset)

print("✅ Icon/Domark.icns — style .\(Style.glyph.rawValue)")
print("   previews of every style: Icon/previews/")
