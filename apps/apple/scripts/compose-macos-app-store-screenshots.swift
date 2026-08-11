#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct CopyFile: Decodable {
    struct Canvas: Decodable {
        let width: Int
        let height: Int
        let colorSpace: String
        let minimumOuterMargin: Int
        let captureWidth: Int
        let captureHeight: Int
    }

    struct Screen: Decodable {
        let index: Int
        let capture: String
        let output: String
        let headline: String
        let supportingCopy: String
        let chips: [String]
        let reviewNote: String
    }

    let schemaVersion: Int
    let canvas: Canvas
    let supportedLocales: [String]
    let locales: [String: [Screen]]
}

private struct Arguments {
    let copyURL: URL
    let locale: String
    let capturesURL: URL
    let outputURL: URL
    let reviewURL: URL

    static func parse() throws -> Arguments {
        var values: [String: String] = [:]
        var index = 1
        let arguments = CommandLine.arguments
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw CompositionError.invalidArguments("Expected --key value pairs")
            }
            values[key] = arguments[index + 1]
            index += 2
        }

        func required(_ key: String) throws -> String {
            guard let value = values[key], !value.isEmpty else {
                throw CompositionError.invalidArguments("Missing \(key)")
            }
            return value
        }

        return Arguments(
            copyURL: URL(fileURLWithPath: try required("--copy")),
            locale: try required("--locale"),
            capturesURL: URL(fileURLWithPath: try required("--captures"), isDirectory: true),
            outputURL: URL(fileURLWithPath: try required("--output"), isDirectory: true),
            reviewURL: URL(fileURLWithPath: try required("--review"), isDirectory: true)
        )
    }
}

private enum CompositionError: LocalizedError {
    case invalidArguments(String)
    case invalidCopy(String)
    case missingFile(String)
    case invalidImage(String)
    case textOverflow(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message),
             .invalidCopy(let message),
             .missingFile(let message),
             .invalidImage(let message),
             .textOverflow(let message),
             .writeFailed(let message):
            return message
        }
    }
}

private extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat(value & 0xff) / 255.0
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

private final class ScreenshotCanvas: NSView {
    private let screen: CopyFile.Screen
    private let capture: NSImage
    private let canvas: CopyFile.Canvas

    override var isFlipped: Bool { true }

    init(screen: CopyFile.Screen, capture: NSImage, canvas: CopyFile.Canvas) {
        self.screen = screen
        self.capture = capture
        self.canvas = canvas
        super.init(frame: NSRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackdrop()

        var cursorY: CGFloat = 104
        drawOverline(at: cursorY)
        cursorY += 46

        let headline = fittedText(
            screen.headline,
            maximumSize: 116,
            minimumSize: 84,
            weight: .bold,
            color: NSColor(hex: "292331"),
            width: 2_400,
            maximumLines: 2,
            lineHeightMultiple: 0.95
        )
        let headlineRect = NSRect(x: 240, y: cursorY, width: 2_400, height: headline.height)
        headline.value.draw(
            with: headlineRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        cursorY += headline.height + 22

        let supporting = fittedText(
            screen.supportingCopy,
            maximumSize: 43,
            minimumSize: 34,
            weight: .regular,
            color: NSColor(hex: "5D5567"),
            width: 2_300,
            maximumLines: 2,
            lineHeightMultiple: 1.04
        )
        let supportingRect = NSRect(x: 290, y: cursorY, width: 2_300, height: supporting.height)
        supporting.value.draw(
            with: supportingRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        cursorY += supporting.height + 30

        drawChips(y: cursorY)
        cursorY += 62

        let captureTop = max(cursorY + 35, 462)
        drawCapture(top: captureTop)
    }

    private func drawBackdrop() {
        let bounds = self.bounds
        NSGradient(
            colors: [NSColor(hex: "FCFBFD"), NSColor(hex: "F5F1FA")]
        )!.draw(in: bounds, angle: 90)

        NSColor(hex: "E9DEFA", alpha: 0.62).setFill()
        NSBezierPath(ovalIn: NSRect(x: -280, y: 860, width: 1_080, height: 1_080)).fill()

        NSColor(hex: "DDECFB", alpha: 0.52).setFill()
        NSBezierPath(ovalIn: NSRect(x: 2_240, y: 930, width: 920, height: 920)).fill()

        NSColor(hex: "F0E8FA", alpha: 0.78).setFill()
        NSBezierPath(roundedRect: NSRect(x: 120, y: 86, width: 70, height: 12), xRadius: 6, yRadius: 6).fill()
    }

    private func drawOverline(at y: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = String(format: "HEALTH.MD  ·  MAC  ·  %02d / 05", screen.index)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: NSColor(hex: "7B45B0"),
                .kern: 2.2,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(in: NSRect(x: 240, y: y, width: 2_400, height: 34))
    }

    private func fittedText(
        _ text: String,
        maximumSize: CGFloat,
        minimumSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        width: CGFloat,
        maximumLines: Int,
        lineHeightMultiple: CGFloat
    ) -> (value: NSAttributedString, height: CGFloat) {
        var size = maximumSize
        while size >= minimumSize {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineHeightMultiple = lineHeightMultiple
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                    .kern: weight == .bold ? -1.5 : -0.15
                ]
            )
            let measured = attributed.boundingRect(
                with: NSSize(width: width, height: 1_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let lineHeight = font.ascender - font.descender + font.leading
            if measured.height <= lineHeight * CGFloat(maximumLines) * 1.12 {
                return (attributed, ceil(measured.height))
            }
            size -= 2
        }

        fatalError("Text overflow for screen \(screen.index): \(text)")
    }

    private func drawChips(y: CGFloat) {
        let font = NSFont.systemFont(ofSize: 27, weight: .semibold)
        let widths = screen.chips.map { chip -> CGFloat in
            let size = (chip as NSString).size(withAttributes: [.font: font])
            return ceil(size.width) + 76
        }
        let spacing: CGFloat = 20
        let totalWidth = widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
        precondition(totalWidth <= 2_400, "Chip row overflow for screen \(screen.index)")

        var x = (CGFloat(canvas.width) - totalWidth) / 2
        for (chip, width) in zip(screen.chips, widths) {
            let rect = NSRect(x: x, y: y, width: width, height: 54)
            NSColor.white.withAlphaComponent(0.88).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 27, yRadius: 27).fill()
            NSColor(hex: "CDB7E4", alpha: 0.9).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 27, yRadius: 27)
            border.lineWidth = 1.5
            border.stroke()

            NSColor(hex: "8B55B8").setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 22, y: y + 20, width: 14, height: 14)).fill()

            let text = NSAttributedString(
                string: chip,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor(hex: "44384F")
                ]
            )
            let textSize = text.size()
            text.draw(at: NSPoint(x: x + 48, y: y + (54 - textSize.height) / 2 - 1))
            x += width + spacing
        }
    }

    private func drawCapture(top: CGFloat) {
        let aspect = capture.size.width / capture.size.height
        let maximumWidth: CGFloat = 2_160
        let availableHeight = CGFloat(canvas.height) - top - 92
        let width = min(maximumWidth, availableHeight * aspect)
        let height = width / aspect
        let rect = NSRect(
            x: (CGFloat(canvas.width) - width) / 2,
            y: top,
            width: width,
            height: height
        )

        NSColor(hex: "8A62AE", alpha: 0.08).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -170, dy: -120)).fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(hex: "30203F", alpha: 0.22)
        shadow.shadowBlurRadius = 44
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).addClip()
        capture.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor(hex: "C9BBD5", alpha: 0.72).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 30, yRadius: 30)
        border.lineWidth = 1.5
        border.stroke()
    }
}

private func bitmapDimensions(at url: URL) throws -> (Int, Int) {
    guard let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data) else {
        throw CompositionError.invalidImage("Could not decode PNG: \(url.path)")
    }
    return (bitmap.pixelsWide, bitmap.pixelsHigh)
}

private func render(
    screen: CopyFile.Screen,
    captureURL: URL,
    outputURL: URL,
    canvas: CopyFile.Canvas
) throws {
    guard FileManager.default.fileExists(atPath: captureURL.path) else {
        throw CompositionError.missingFile("Missing capture: \(captureURL.path)")
    }
    let dimensions = try bitmapDimensions(at: captureURL)
    guard dimensions == (canvas.captureWidth, canvas.captureHeight) else {
        throw CompositionError.invalidImage(
            "Capture \(captureURL.lastPathComponent) is \(dimensions.0)x\(dimensions.1); expected \(canvas.captureWidth)x\(canvas.captureHeight)"
        )
    }
    guard let capture = NSImage(contentsOf: captureURL) else {
        throw CompositionError.invalidImage("Could not load capture: \(captureURL.path)")
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: canvas.width,
            height: canvas.height,
            bitsPerComponent: 8,
            bytesPerRow: canvas.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw CompositionError.writeFailed("Could not create an sRGB canvas")
    }

    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    let view = ScreenshotCanvas(screen: screen, capture: capture, canvas: canvas)
    view.displayIgnoringOpacity(view.bounds, in: graphicsContext)
    NSGraphicsContext.restoreGraphicsState()

    guard let renderedImage = context.makeImage(),
          let outputContext = CGContext(
            data: nil,
            width: canvas.width,
            height: canvas.height,
            bitsPerComponent: 8,
            bytesPerRow: canvas.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw CompositionError.writeFailed("Could not finalize the sRGB canvas")
    }
    outputContext.translateBy(x: 0, y: CGFloat(canvas.height))
    outputContext.scaleBy(x: 1, y: -1)
    outputContext.draw(
        renderedImage,
        in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    )

    guard let image = outputContext.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
          ) else {
        throw CompositionError.writeFailed("Could not create \(outputURL.path)")
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
        kCGImagePropertyProfileName: "sRGB IEC61966-2.1"
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw CompositionError.writeFailed("Could not finalize \(outputURL.path)")
    }
}

private func relativePath(from directory: URL, to file: URL) -> String {
    let base = directory.standardizedFileURL.pathComponents
    let target = file.standardizedFileURL.pathComponents
    var common = 0
    while common < min(base.count, target.count), base[common] == target[common] {
        common += 1
    }
    let ups = Array(repeating: "..", count: base.count - common)
    return (ups + target.dropFirst(common)).joined(separator: "/")
}

private func htmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private func writeReviewPage(
    locale: String,
    screens: [CopyFile.Screen],
    outputURL: URL,
    reviewURL: URL
) throws {
    let cards = screens.map { screen -> String in
        let imageURL = outputURL.appendingPathComponent(screen.output)
        let path = relativePath(from: reviewURL, to: imageURL)
        return """
        <article>
          <h2>\(String(format: "%02d", screen.index)). \(htmlEscape(screen.headline))</h2>
          <p>\(htmlEscape(screen.reviewNote))</p>
          <div class="views">
            <figure><figcaption>Full size (scroll to inspect)</figcaption><div class="full"><img src="\(path)" alt="\(htmlEscape(screen.headline))"></div></figure>
            <figure><figcaption>App Store thumbnail (~20%)</figcaption><img class="thumb" src="\(path)" alt="\(htmlEscape(screen.headline)) thumbnail"></figure>
          </div>
        </article>
        """
    }.joined(separator: "\n")

    let html = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Health.md macOS screenshots — \(htmlEscape(locale))</title>
      <style>
        :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #292331; background: #f7f4fc; }
        body { margin: 0 auto; max-width: 1480px; padding: 48px; }
        h1 { font-size: 40px; margin: 0 0 8px; } .lede { color: #655b70; margin-bottom: 44px; }
        article { background: white; border: 1px solid #ded4e8; border-radius: 24px; padding: 28px; margin: 0 0 40px; box-shadow: 0 18px 50px #3d245012; }
        h2 { margin: 0 0 8px; } article > p { color: #655b70; max-width: 80ch; }
        .views { display: grid; grid-template-columns: minmax(0, 1fr) 600px; gap: 24px; align-items: start; }
        figure { margin: 0; } figcaption { color: #766b80; font-size: 14px; margin-bottom: 8px; }
        .full { max-height: 720px; overflow: auto; border-radius: 12px; border: 1px solid #ded4e8; background: #eee9f4; }
        img { display: block; width: 100%; height: auto; } .full img { width: 2880px; max-width: none; }
        .thumb { width: 576px; border-radius: 8px; box-shadow: 0 10px 24px #3d24501f; }
        @media (max-width: 1000px) { .views { grid-template-columns: 1fr; } .thumb { width: 100%; } }
      </style>
    </head>
    <body>
      <h1>Health.md macOS App Store screenshots</h1>
      <p class="lede">Locale: \(htmlEscape(locale)) · Full-size and ~20% review views · Generated, not hand edited.</p>
      \(cards)
    </body>
    </html>
    """
    try html.write(
        to: reviewURL.appendingPathComponent("index.html"),
        atomically: true,
        encoding: .utf8
    )
}

do {
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    let arguments = try Arguments.parse()
    let data = try Data(contentsOf: arguments.copyURL)
    let copy = try JSONDecoder().decode(CopyFile.self, from: data)

    guard copy.schemaVersion == 1 else {
        throw CompositionError.invalidCopy("Unsupported copy schema version: \(copy.schemaVersion)")
    }
    guard copy.canvas.width == 2_880,
          copy.canvas.height == 1_800,
          copy.canvas.colorSpace == "sRGB",
          copy.canvas.minimumOuterMargin >= 120 else {
        throw CompositionError.invalidCopy("Canvas must be 2880x1800 sRGB with at least 120 px margins")
    }
    guard copy.supportedLocales.contains(arguments.locale) else {
        throw CompositionError.invalidCopy("Unsupported locale: \(arguments.locale)")
    }
    guard let screens = copy.locales[arguments.locale] else {
        throw CompositionError.invalidCopy("Missing copy for supported locale: \(arguments.locale)")
    }
    guard screens.count == 5,
          screens.map(\.index) == [1, 2, 3, 4, 5],
          Set(screens.map(\.output)).count == 5 else {
        throw CompositionError.invalidCopy("Locale \(arguments.locale) must contain five uniquely named screens in explicit 1...5 order")
    }
    guard screens.allSatisfy({
        !$0.headline.isEmpty && !$0.supportingCopy.isEmpty && !$0.capture.isEmpty && !$0.output.isEmpty && $0.chips.count <= 3
    }) else {
        throw CompositionError.invalidCopy("Locale \(arguments.locale) contains missing copy or more than three chips")
    }

    try FileManager.default.createDirectory(at: arguments.outputURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: arguments.reviewURL, withIntermediateDirectories: true)

    for screen in screens {
        let captureURL = arguments.capturesURL.appendingPathComponent(screen.capture)
        let outputURL = arguments.outputURL.appendingPathComponent(screen.output)
        try render(screen: screen, captureURL: captureURL, outputURL: outputURL, canvas: copy.canvas)
        let dimensions = try bitmapDimensions(at: outputURL)
        guard dimensions == (copy.canvas.width, copy.canvas.height) else {
            throw CompositionError.invalidImage("Generated output has incorrect dimensions: \(outputURL.path)")
        }
        print("[compose] wrote \(outputURL.path)")
    }

    try writeReviewPage(
        locale: arguments.locale,
        screens: screens,
        outputURL: arguments.outputURL,
        reviewURL: arguments.reviewURL
    )
    print("[compose] wrote \(arguments.reviewURL.appendingPathComponent("index.html").path)")
} catch {
    fputs("compose-macos-app-store-screenshots: \(error.localizedDescription)\n", stderr)
    exit(1)
}
