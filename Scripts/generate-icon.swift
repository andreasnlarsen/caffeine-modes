#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-icon.swift OUTPUT.png\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.055, green: 0.102, blue: 0.165, alpha: 1).setFill()
background.fill()

let halo = NSBezierPath(ovalIn: NSRect(x: 162, y: 160, width: 700, height: 700))
NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.35, alpha: 1).setFill()
halo.fill()

let steamColors = [
    NSColor(calibratedRed: 0.98, green: 0.73, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.60, green: 0.78, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.43, green: 0.88, blue: 0.66, alpha: 1)
]
let steamX: [CGFloat] = [380, 512, 644]
for (index, x) in steamX.enumerated() {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x - 26, y: 650))
    path.curve(
        to: NSPoint(x: x + 20, y: 830),
        controlPoint1: NSPoint(x: x + 70, y: 700),
        controlPoint2: NSPoint(x: x - 70, y: 780)
    )
    path.lineWidth = 34
    path.lineCapStyle = .round
    steamColors[index].setStroke()
    path.stroke()
}

let cup = NSBezierPath(roundedRect: NSRect(x: 274, y: 310, width: 430, height: 300), xRadius: 76, yRadius: 76)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
cup.fill()

let coffee = NSBezierPath(ovalIn: NSRect(x: 300, y: 548, width: 378, height: 76))
NSColor(calibratedRed: 0.25, green: 0.13, blue: 0.07, alpha: 1).setFill()
coffee.fill()

let handle = NSBezierPath(ovalIn: NSRect(x: 640, y: 374, width: 190, height: 176))
handle.lineWidth = 52
NSColor(calibratedWhite: 0.97, alpha: 1).setStroke()
handle.stroke()

let saucer = NSBezierPath(roundedRect: NSRect(x: 226, y: 244, width: 578, height: 62), xRadius: 31, yRadius: 31)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
saucer.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("Could not render icon.\n".utf8))
    exit(1)
}
try png.write(to: outputURL)
