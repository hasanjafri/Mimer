#!/usr/bin/env swift
//
// Renders Mimer's app-icon master (1024×1024 PNG): an indigo→violet "squircle"
// with a white clipboard mark. Usage: swift make_icon.swift <out.png>
//
import AppKit

let S: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/mimer_icon_1024.png"

func roundRect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()

// --- background squircle with brand gradient ---
let margin: CGFloat = 88
let bg = NSRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let bgPath = roundRect(bg, bg.width * 0.225)

NSGraphicsContext.saveGraphicsState()
bgPath.addClip()
NSGradient(colors: [
    NSColor(srgbRed: 0.29, green: 0.25, blue: 0.90, alpha: 1),   // indigo  #4A40E6
    NSColor(srgbRed: 0.56, green: 0.28, blue: 0.93, alpha: 1)    // violet  #8F47ED
])!.draw(in: bg, angle: -55)
// soft top highlight for depth
NSGradient(colors: [NSColor(white: 1, alpha: 0.16), NSColor(white: 1, alpha: 0)])!
    .draw(in: bg, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// --- white clipboard mark ---
let cx = S / 2
let cy = S / 2
let boardW: CGFloat = 430
let boardH: CGFloat = 540
let board = NSRect(x: cx - boardW / 2, y: cy - boardH / 2 - 8, width: boardW, height: boardH)

// soft shadow under the board
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor.white.setFill()
roundRect(board, 52).fill()
NSGraphicsContext.restoreGraphicsState()

// clip bar at the top
let clipW: CGFloat = 168
let clip = NSRect(x: cx - clipW / 2, y: board.maxY - 40, width: clipW, height: 78)
NSColor(srgbRed: 0.40, green: 0.27, blue: 0.92, alpha: 1).setFill()
roundRect(clip, 30).fill()
// inner notch on the clip
NSColor.white.setFill()
roundRect(NSRect(x: cx - 46, y: clip.minY + 22, width: 92, height: 34), 17).fill()

// accent "text" lines on the board
NSColor(srgbRed: 0.46, green: 0.43, blue: 0.86, alpha: 0.5).setFill()
let lineX = board.minX + 56
let lineW = boardW - 112
for i in 0..<3 {
    let ly = board.maxY - 168 - CGFloat(i) * 92
    let w = (i == 2) ? lineW * 0.58 : lineW
    roundRect(NSRect(x: lineX, y: ly, width: w, height: 34), 17).fill()
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
