#!/usr/bin/env swift
//
// Renders Mimer's social-preview / Open Graph card (1280×640 PNG): the brand
// indigo→violet gradient, the wordmark + tagline, and the clipboard mark — sized
// for GitHub's repo social preview and og:image / twitter:image meta tags.
// Usage: swift make_og.swift <out.png>
//
import AppKit

let W: CGFloat = 1280
let H: CGFloat = 640
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/mimer_og.png"

func roundRect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}

let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// --- brand gradient background ---
let full = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [
    NSColor(srgbRed: 0.29, green: 0.25, blue: 0.90, alpha: 1),   // indigo  #4A40E6
    NSColor(srgbRed: 0.56, green: 0.28, blue: 0.93, alpha: 1)    // violet  #8F47ED
])!.draw(in: full, angle: -50)
// soft top highlight for depth
NSGradient(colors: [NSColor(white: 1, alpha: 0.12), NSColor(white: 1, alpha: 0)])!
    .draw(in: full, angle: -90)

// --- clipboard mark on the right ---
let cx: CGFloat = 1000
let cy: CGFloat = H / 2
let boardW: CGFloat = 300
let boardH: CGFloat = 376
let board = NSRect(x: cx - boardW / 2, y: cy - boardH / 2 - 6, width: boardW, height: boardH)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.white.setFill()
roundRect(board, 38).fill()
NSGraphicsContext.restoreGraphicsState()

// clip bar at the top
let clipW: CGFloat = 118
let clip = NSRect(x: cx - clipW / 2, y: board.maxY - 28, width: clipW, height: 56)
NSColor(srgbRed: 0.40, green: 0.27, blue: 0.92, alpha: 1).setFill()
roundRect(clip, 22).fill()
NSColor.white.setFill()
roundRect(NSRect(x: cx - 32, y: clip.minY + 16, width: 64, height: 24), 12).fill()

// accent "text" lines on the board
NSColor(srgbRed: 0.46, green: 0.43, blue: 0.86, alpha: 0.5).setFill()
let lineX = board.minX + 40
let lineW = boardW - 80
for i in 0..<3 {
    let ly = board.maxY - 118 - CGFloat(i) * 64
    let w = (i == 2) ? lineW * 0.58 : lineW
    roundRect(NSRect(x: lineX, y: ly, width: w, height: 24), 12).fill()
}

// --- wordmark + tagline on the left ---
func draw(_ s: String, font: NSFont, color: NSColor, at p: NSPoint) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    s.draw(at: p, withAttributes: attrs)
}

let leftX: CGFloat = 96
draw("Mimer", font: .systemFont(ofSize: 116, weight: .bold),
     color: .white, at: NSPoint(x: leftX - 6, y: 372))
draw("Fast, private, developer-first", font: .systemFont(ofSize: 40, weight: .semibold),
     color: NSColor(white: 1, alpha: 0.96), at: NSPoint(x: leftX, y: 300))
draw("clipboard manager for macOS", font: .systemFont(ofSize: 40, weight: .semibold),
     color: NSColor(white: 1, alpha: 0.96), at: NSPoint(x: leftX, y: 250))
draw("⇧⌘V command palette · ⌘K transforms · open source", font: .systemFont(ofSize: 25, weight: .medium),
     color: NSColor(white: 1, alpha: 0.78), at: NSPoint(x: leftX, y: 176))

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
