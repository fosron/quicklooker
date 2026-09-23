#!/usr/bin/env swift
// Generates the QuickLooker app icon set.
// Usage: swift Scripts/generate_app_icon.swift Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import Foundation

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets.xcassets/AppIcon.appiconset"

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create bitmap context")
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Background: macOS style squircle with a deep blue gradient.
let margin: CGFloat = 64
let backgroundRect = CGRect(x: margin, y: margin, width: CGFloat(size) - margin * 2, height: CGFloat(size) - margin * 2)
let backgroundPath = roundedPath(backgroundRect, radius: 210)

context.saveGState()
context.addPath(backgroundPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.19, green: 0.36, blue: 0.92, alpha: 1),
        CGColor(red: 0.06, green: 0.13, blue: 0.44, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: margin, y: CGFloat(size) - margin),
    end: CGPoint(x: CGFloat(size) - margin, y: margin),
    options: []
)
context.restoreGState()

// Document sheet.
let sheetRect = CGRect(x: 258, y: 236, width: 420, height: 540)
let sheetPath = roundedPath(sheetRect, radius: 40)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
context.addPath(sheetPath)
context.setFillColor(CGColor(red: 0.98, green: 0.99, blue: 1, alpha: 1))
context.fillPath()
context.restoreGState()

// Code lines on the sheet.
context.setFillColor(CGColor(red: 0.72, green: 0.78, blue: 0.9, alpha: 1))
let lineWidths: [CGFloat] = [280, 220, 250, 160]
for (index, width) in lineWidths.enumerated() {
    let y = sheetRect.maxY - 120 - CGFloat(index) * 72
    context.addPath(roundedPath(CGRect(x: sheetRect.minX + 70, y: y, width: width, height: 26), radius: 13))
    context.fillPath()
}

// Magnifying glass.
let lensCenter = CGPoint(x: 690, y: 300)
let lensRadius: CGFloat = 168
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
context.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius,
    y: lensCenter.y - lensRadius,
    width: lensRadius * 2,
    height: lensRadius * 2
))
context.setStrokeColor(CGColor(red: 0.14, green: 0.16, blue: 0.2, alpha: 1))
context.setLineWidth(58)
context.strokePath()
context.restoreGState()

context.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius,
    y: lensCenter.y - lensRadius,
    width: lensRadius * 2,
    height: lensRadius * 2
))
context.setFillColor(CGColor(red: 0.36, green: 0.78, blue: 1, alpha: 0.55))
context.fillPath()

// Handle.
context.setLineCap(.round)
context.setStrokeColor(CGColor(red: 0.14, green: 0.16, blue: 0.2, alpha: 1))
context.setLineWidth(64)
context.move(to: CGPoint(x: lensCenter.x + lensRadius * 0.72, y: lensCenter.y - lensRadius * 0.72))
context.addLine(to: CGPoint(x: lensCenter.x + lensRadius * 1.45, y: lensCenter.y - lensRadius * 1.45))
context.strokePath()

guard let image = context.makeImage() else {
    fatalError("Unable to create image")
}

try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
let masterURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent("icon_1024.png")
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}
try png.write(to: masterURL)

// Downscale into the sizes the asset catalog expects.
let renderings: [(name: String, pixels: Int)] = [
    ("icon_16", 16), ("icon_16@2x", 32),
    ("icon_32", 32), ("icon_32@2x", 64),
    ("icon_128", 128), ("icon_128@2x", 256),
    ("icon_256", 256), ("icon_256@2x", 512),
    ("icon_512", 512), ("icon_512@2x", 1024),
]
for rendering in renderings {
    let target = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(rendering.name).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(rendering.pixels)", "\(rendering.pixels)", masterURL.path, "--out", target.path]
    try process.run()
    process.waitUntilExit()
}
try? FileManager.default.removeItem(at: masterURL)
print("Wrote icon set to \(outputDirectory)")
