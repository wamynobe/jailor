#!/usr/bin/env swift

import AppKit
import CoreGraphics

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources",
    isDirectory: true
)
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") { value.removeFirst() }
    var number: UInt64 = 0
    Scanner(string: value).scanHexInt64(&number)
    let red = CGFloat((number >> 16) & 0xFF) / 255
    let green = CGFloat((number >> 8) & 0xFF) / 255
    let blue = CGFloat(number & 0xFF) / 255
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha])!
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawPane(_ context: CGContext, rect: CGRect, from: String, to: String, radius: CGFloat) {
    let path = roundedPath(rect, radius: radius)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(from), color(to)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    context.restoreGState()

    context.addPath(path)
    context.setStrokeColor(color("#FFFFFF", alpha: 0.20))
    context.setLineWidth(2)
    context.strokePath()
}

func drawIcon(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let backgroundRect = CGRect(x: 58, y: 58, width: 908, height: 908)
    let backgroundPath = roundedPath(backgroundRect, radius: 204)

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()

    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color("#303C93"), color("#0B0F1F")] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 120, y: 930),
        end: CGPoint(x: 900, y: 80),
        options: []
    )

    // Subtle dot grid
    context.setFillColor(color("#FFFFFF", alpha: 0.055))
    var x = 120.0
    while x < 920 {
        var y = 120.0
        while y < 920 {
            context.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
            y += 54
        }
        x += 54
    }

    // Top-left glow
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color("#8EA0FF", alpha: 0.50), color("#8EA0FF", alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 300, y: 840),
        startRadius: 10,
        endCenter: CGPoint(x: 300, y: 840),
        endRadius: 560,
        options: []
    )

    context.restoreGState()

    context.addPath(backgroundPath)
    context.setStrokeColor(color("#FFFFFF", alpha: 0.14))
    context.setLineWidth(3)
    context.strokePath()

    // Three workspace panes
    drawPane(
        context,
        rect: CGRect(x: 196, y: 238, width: 318, height: 548),
        from: "#A6B4FF",
        to: "#5667E8",
        radius: 52
    )
    drawPane(
        context,
        rect: CGRect(x: 536, y: 528, width: 292, height: 258),
        from: "#79F0DE",
        to: "#22A998",
        radius: 46
    )
    drawPane(
        context,
        rect: CGRect(x: 536, y: 238, width: 292, height: 258),
        from: "#C4AEFF",
        to: "#7455EB",
        radius: 46
    )

    return rep.representation(using: .png, properties: [:])!
}

let outputs: [(Int, [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"])
]

for (size, names) in outputs {
    let data = drawIcon(size: size)
    for name in names {
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Đã tạo \(outputDirectory.appendingPathComponent("AppIcon.icns").path)")
} else {
    fputs("iconutil thất bại với mã \(process.terminationStatus)\n", stderr)
    exit(1)
}
