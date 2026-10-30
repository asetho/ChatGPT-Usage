#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count == 4, ["0", "1"].contains(CommandLine.arguments[3]) else {
    fputs("Usage: generate-dmg-background.swift <app-icon.png> <output.png> <notarized: 0|1>\n", stderr)
    exit(64)
}

let iconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let notarized = CommandLine.arguments[3] == "1"
let size = NSSize(width: 660, height: 450)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let icon = NSImage(contentsOf: iconURL) else {
    fputs("Could not load the DMG canvas or app icon.\n", stderr)
    exit(1)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func line(_ points: [NSPoint], width: CGFloat, stroke: NSColor, dash: [CGFloat] = []) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    if !dash.isEmpty { path.setLineDash(dash, count: dash.count, phase: 0) }
    stroke.setStroke()
    path.stroke()
}

func label(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, tint: NSColor, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    value.draw(
        in: NSRect(x: x, y: y, width: width, height: size + 8),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: tint, .paragraphStyle: paragraph]
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [color(15, 19, 23), color(23, 29, 34), color(15, 20, 24)])?
    .draw(in: bounds, angle: -20)
rounded(NSRect(x: 18, y: 18, width: 624, height: 414), radius: 22,
        fill: color(255, 255, 255, 0.025), stroke: color(228, 247, 241, 0.10))

// Echo the app's segmented usage ring without competing with Finder's icons.
for radius in stride(from: CGFloat(92), through: 148, by: 28) {
    let ring = NSBezierPath(ovalIn: NSRect(x: 574 - radius, y: 354 - radius,
                                         width: radius * 2, height: radius * 2))
    ring.lineWidth = 1
    color(105, 225, 184, radius == 92 ? 0.13 : 0.055).setStroke()
    ring.stroke()
}

icon.draw(in: NSRect(x: 58, y: 315, width: 59, height: 59), from: .zero,
          operation: .sourceOver, fraction: 1)
label("Install ChatGPT Usage", x: 133, y: 342, width: 440, size: 28,
      weight: .bold, tint: color(245, 247, 245))
label("Drag the app into Applications.", x: 134, y: 316, width: 420,
      size: 15, weight: .medium, tint: color(179, 195, 190))

line([NSPoint(x: 64, y: 283), NSPoint(x: 596, y: 283)], width: 1,
     stroke: color(176, 215, 202, 0.18), dash: [3, 7])

for x in [86.0, 408.0] {
    rounded(NSRect(x: x, y: 143, width: 166, height: 122), radius: 19,
            fill: color(221, 235, 226, 0.9), stroke: color(163, 227, 207, 0.42))
}

let mint = color(98, 222, 177)
line([NSPoint(x: 288, y: 207), NSPoint(x: 370, y: 207)], width: 5, stroke: mint)
line([NSPoint(x: 351, y: 225), NSPoint(x: 371, y: 207), NSPoint(x: 351, y: 189)],
     width: 5, stroke: mint)

if notarized {
    line([NSPoint(x: 64, y: 116), NSPoint(x: 596, y: 116)], width: 1,
         stroke: color(176, 215, 202, 0.13))
    label("After copying, open ChatGPT Usage from Applications or the menu bar.",
          x: 64, y: 72, width: 532, size: 13, weight: .regular,
          tint: color(180, 196, 190), alignment: .center)
} else {
    rounded(NSRect(x: 64, y: 18, width: 532, height: 110), radius: 17,
            fill: color(221, 235, 226, 0.9), stroke: color(163, 227, 207, 0.3))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render the DMG background.\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
