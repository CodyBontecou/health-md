#!/usr/bin/env swift
// Deterministic App Store slide compositor.
//
// Renders each `AS_*` board from docs/design/liquid-glass/screens with WebKit, so background,
// artwork, device frames, rotations, positions and fonts come straight from the board's inline
// styles. The board's `<dc-import>` screens are replaced with real app captures, and its headline
// and caption are replaced with the requested locale's copy from the platform JSON (en-US must
// match the board verbatim, which doubles as a drift check). Output is an sRGB PNG without alpha
// at exactly board size × scale.
//
// Usage (from apps/apple):
//   swift scripts/app-store-screenshots/compose.swift --copy <platform.json> --check
//   swift scripts/app-store-screenshots/compose.swift --copy <platform.json> --locale en-US \
//       --captures <dir> --output <dir> [--only AS_iPhone_1] [--placeholder]
//
// --placeholder fills missing captures with labelled blocks. It exists only to check layout and
// must never feed App Store output.

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

// MARK: - Arguments

struct Options {
    var copyURL: URL
    var locale = "en-US"
    var capturesURL: URL?
    var outputURL: URL?
    var only: Set<String> = []
    var placeholder = false
    var checkOnly = false

    static func parse(_ arguments: [String]) throws -> Options {
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var only: Set<String> = []
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            switch key {
            case "--placeholder", "--check":
                flags.insert(key)
                index += 1
            case "--copy", "--locale", "--captures", "--output", "--only":
                guard index + 1 < arguments.count else { throw Failure("Missing value for \(key)") }
                if key == "--only" { only.insert(arguments[index + 1]) } else { values[key] = arguments[index + 1] }
                index += 2
            default:
                throw Failure("Unknown argument \(key)")
            }
        }
        guard let copy = values["--copy"] else { throw Failure("--copy is required") }
        var options = Options(copyURL: URL(fileURLWithPath: copy))
        options.locale = values["--locale"] ?? "en-US"
        options.capturesURL = values["--captures"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        options.outputURL = values["--output"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        options.only = only
        options.placeholder = flags.contains("--placeholder")
        options.checkOnly = flags.contains("--check")
        if !options.checkOnly && (options.capturesURL == nil || options.outputURL == nil) {
            throw Failure("--captures and --output are required unless --check is passed")
        }
        return options
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Copy JSON

struct Size: Codable { let width: Int; let height: Int }

struct CaptureSpec: Codable {
    let file: String
    let optional: Bool?
}

struct SlideCopy: Codable {
    /// One entry per headline line; `{…}` marks the accent-coloured run, as the board's `<span>`.
    let headline: [String]
    /// The board's plain caption paragraph, or null when the board has none.
    let caption: String?
}

struct Slide: Codable {
    let board: String
    let output: String
    let size: Size?
    let captures: [String: CaptureSpec]
    let copy: [String: SlideCopy]
}

struct PlatformCopy: Codable {
    let schemaVersion: Int
    let platform: String
    let boardsDirectory: String
    let boardPrefix: String
    let appStoreDisplayType: String?
    let boardSize: Size
    let scale: Int
    let supportedLocales: [String]
    let slides: [Slide]
}

/// Pixel sizes App Store Connect accepts for the display types these boards target.
let acceptedSizes: [String: [(Int, Int)]] = [
    "IPHONE_69": [(1320, 2868), (2868, 1320), (1290, 2796), (2796, 1290), (1260, 2736), (2736, 1260)],
    "IPAD_PRO_3GEN_129": [(2064, 2752), (2752, 2064), (2048, 2732), (2732, 2048)],
    "DESKTOP": [(2880, 1800), (2560, 1600), (1440, 900), (1280, 800)],
]

// MARK: - Board HTML

func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func headlineHTML(_ lines: [String], accent: String?) throws -> String {
    try lines.map { line in
        var html = ""
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "{") {
            html += escapeHTML(String(rest[..<open]))
            guard let close = rest[open...].firstIndex(of: "}") else { throw Failure("Unclosed { in headline: \(line)") }
            guard let accent else { throw Failure("Headline marks an accent but the board has none: \(line)") }
            html += "<span style=\"color: \(accent)\">\(escapeHTML(String(rest[rest.index(after: open)..<close])))</span>"
            rest = rest[rest.index(after: close)...]
        }
        return html + escapeHTML(String(rest))
    }.joined(separator: "<br>")
}

func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
}

func matches(_ expression: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
    expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
}

func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
    String(text[Range(match.range(at: index), in: text)!])
}

func replacing(_ match: NSTextCheckingResult, group index: Int, in text: String, with replacement: String) -> String {
    var copy = text
    copy.replaceSubrange(Range(match.range(at: index), in: text)!, with: replacement)
    return copy
}

struct PreparedBoard {
    let html: String
    let missingRequired: [String]
    let omitted: [String]
}

/// Applies copy and captures to one board. `english` anchors the replacement: it must equal the
/// board's own text, so a design change that is not reflected in the JSON fails loudly.
func prepareBoard(
    html source: String,
    slide: Slide,
    expectedSize: Size,
    english: SlideCopy,
    localized: SlideCopy,
    capturesURL: URL?,
    assetsURL: URL,
    placeholder: Bool
) throws -> PreparedBoard {
    var html = source

    let root = matches(regex(#"<div style="width: (\d+)px; height: (\d+)px; position: relative"#), in: html)
    guard let first = root.first,
          Int(group(first, 1, in: html)) == expectedSize.width,
          Int(group(first, 2, in: html)) == expectedSize.height else {
        throw Failure("\(slide.board): board root is not \(expectedSize.width) x \(expectedSize.height)")
    }

    // Headline.
    let headlines = matches(regex(#"<h1 style="[^"]*">(.*?)</h1>"#), in: html)
    guard headlines.count == 1, let headline = headlines.first else {
        throw Failure("\(slide.board): expected exactly one <h1>, found \(headlines.count)")
    }
    let boardHeadline = group(headline, 1, in: html)
    let accentMatch = matches(regex(#"<span style="color: (#[0-9A-Fa-f]{6})">"#), in: boardHeadline).first
    let accent = accentMatch.map { group($0, 1, in: boardHeadline) }
    guard try headlineHTML(english.headline, accent: accent) == boardHeadline else {
        throw Failure("\(slide.board): en-US headline in the JSON no longer matches the board:\n  board: \(boardHeadline)")
    }
    html = replacing(headline, group: 1, in: html, with: try headlineHTML(localized.headline, accent: accent))

    // Caption.
    let plainParagraphs = matches(regex(#"<p style="[^"]*">([^<]*)</p>"#), in: html)
    if let caption = english.caption {
        let hits = plainParagraphs.filter { group($0, 1, in: html) == escapeHTML(caption) }
        guard hits.count == 1, let hit = hits.first else {
            throw Failure("\(slide.board): en-US caption not found verbatim on the board: \(caption)")
        }
        guard let localizedCaption = localized.caption else {
            throw Failure("\(slide.board): the locale has no caption but the board does")
        }
        html = replacing(hit, group: 1, in: html, with: escapeHTML(localizedCaption))
    } else if !plainParagraphs.isEmpty {
        throw Failure("\(slide.board): the board has a plain caption paragraph but the JSON caption is null")
    }

    // Product screens.
    var missingRequired: [String] = []
    var omitted: [String] = []
    let imports = matches(regex(#"<dc-import name="([^"]+)" hint-size="(\d+)px,(\d+)px"></dc-import>"#), in: html)
    let importNames = Set(imports.map { group($0, 1, in: html) })
    guard importNames == Set(slide.captures.keys) else {
        throw Failure("\(slide.board): board screens \(importNames.sorted()) differ from JSON captures \(slide.captures.keys.sorted())")
    }
    for match in imports.reversed() {
        let name = group(match, 1, in: html)
        let width = group(match, 2, in: html)
        let height = group(match, 3, in: html)
        let spec = slide.captures[name]!
        let replacement: String
        if let capturesURL, FileManager.default.fileExists(atPath: capturesURL.appendingPathComponent(spec.file).path) {
            let url = capturesURL.appendingPathComponent(spec.file).absoluteString
            replacement = "<img src=\"\(url)\" alt=\"\" style=\"display: block; width: \(width)px; height: \(height)px; object-fit: cover; object-position: top center\">"
        } else if spec.optional == true {
            omitted.append("\(name) (\(spec.file))")
            replacement = "<span data-omit-insert></span>"
        } else if placeholder {
            replacement = "<div style=\"width: \(width)px; height: \(height)px; display: flex; align-items: center; justify-content: center; text-align: center; background: repeating-linear-gradient(45deg, #2A2540 0 24px, #1C1830 24px 48px); color: #FFFFFF; font: 700 28px -apple-system, sans-serif\">\(name)<br>\(spec.file)</div>"
        } else {
            missingRequired.append(spec.file)
            replacement = ""
        }
        html.replaceSubrange(Range(match.range, in: html)!, with: replacement)
    }

    // Offline and deterministic: no web fonts (system fonts are first in every stack), no canvas
    // runtime, no design-tool logic.
    html = html.replacingOccurrences(of: #"<link[^>]*fonts\.(googleapis|gstatic)\.com[^>]*>"#, with: "", options: .regularExpression)
    html = html.replacingOccurrences(of: #"<script src="[^"]*"></script>"#, with: "", options: .regularExpression)
    html = html.replacingOccurrences(of: #"<script type="text/x-dc".*?</script>"#, with: "", options: [.regularExpression])
    html = html.replacingOccurrences(of: "src=\"../assets/", with: "src=\"\(assetsURL.absoluteString)")
    html = html.replacingOccurrences(of: "<head>", with: "<head><style>html, body { margin: 0; background: #000000; overflow: hidden; }</style>")

    return PreparedBoard(html: html, missingRequired: missingRequired, omitted: omitted)
}

// MARK: - Rendering

@MainActor
final class BoardRenderer: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    init(pixelWidth: Int, pixelHeight: Int, scale: Int) {
        let frame = NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.pageZoom = CGFloat(scale)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -40_000, y: -40_000))
        window.orderFrontRegardless()
        super.init()
        webView.navigationDelegate = self
    }

    func render(fileURL: URL, pixelWidth: Int, pixelHeight: Int) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.loadFileURL(fileURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
        _ = try await webView.callAsyncJavaScript("""
            await document.fonts.ready;
            await Promise.all(Array.from(document.images).map(image => image.decode().catch(() => {
                throw new Error('Could not decode ' + image.src);
            })));
            document.querySelectorAll('[data-omit-insert]').forEach(marker => {
                let node = marker;
                while (node.parentElement && node.style.position !== 'absolute') node = node.parentElement;
                node.style.display = 'none';
            });
            return true;
            """, arguments: [:], in: nil, contentWorld: .page)
        try await Task.sleep(for: .milliseconds(400))

        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: configuration)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure("Snapshot has no bitmap")
        }
        return try flatten(cgImage, width: pixelWidth, height: pixelHeight)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(error) }
    }

    private func finish(_ error: Error?) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}

/// Redraws the snapshot (whatever the display's backing scale) into an exact-size sRGB bitmap
/// without alpha.
func flatten(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else { throw Failure("Could not create an sRGB canvas") }
    context.interpolationQuality = .high
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let result = context.makeImage() else { throw Failure("Could not finalize the canvas") }
    return result
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw Failure("Could not create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure("Could not write \(url.path)") }
}

// MARK: - Main

@MainActor
func run() async throws {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    let data = try Data(contentsOf: options.copyURL)
    let copy = try JSONDecoder().decode(PlatformCopy.self, from: data)
    guard copy.schemaVersion == 2 else { throw Failure("Unsupported copy schemaVersion \(copy.schemaVersion)") }
    guard copy.supportedLocales.contains(options.locale) else {
        throw Failure("\(options.copyURL.lastPathComponent) has no copy for \(options.locale); supported: \(copy.supportedLocales.joined(separator: ", "))")
    }

    let boardsURL = URL(fileURLWithPath: copy.boardsDirectory, relativeTo: options.copyURL.deletingLastPathComponent()).standardizedFileURL
    let assetsURL = boardsURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)

    // Every board of the platform must be in the JSON, once.
    let boardFiles = try FileManager.default.contentsOfDirectory(atPath: boardsURL.path)
        .filter { $0.hasPrefix(copy.boardPrefix) && $0.hasSuffix(".dc.html") }
        .map { String($0.dropLast(".dc.html".count)) }
    let listed = copy.slides.map(\.board)
    guard Set(boardFiles) == Set(listed), listed.count == Set(listed).count else {
        throw Failure("Boards \(boardFiles.sorted()) and JSON slides \(listed) differ")
    }
    guard Set(copy.slides.map(\.output)).count == copy.slides.count else { throw Failure("Duplicate output names") }

    let slides = copy.slides.filter { options.only.isEmpty || options.only.contains($0.board) }
    guard !slides.isEmpty else { throw Failure("No slides selected") }

    if let outputURL = options.outputURL {
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    }
    let workURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("healthmd-app-store-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workURL) }

    var missing: [String] = []
    for slide in slides {
        guard let english = slide.copy["en-US"] else { throw Failure("\(slide.board): no en-US copy") }
        guard let localized = slide.copy[options.locale] else { throw Failure("\(slide.board): no \(options.locale) copy") }
        let size = slide.size ?? copy.boardSize
        let source = try String(contentsOf: boardsURL.appendingPathComponent("\(slide.board).dc.html"), encoding: .utf8)
        let prepared = try prepareBoard(
            html: source, slide: slide, expectedSize: size, english: english, localized: localized,
            capturesURL: options.capturesURL, assetsURL: assetsURL, placeholder: options.placeholder
        )
        if options.checkOnly {
            print("ok    \(slide.board)")
            continue
        }
        guard prepared.missingRequired.isEmpty else {
            missing += prepared.missingRequired.map { "\(slide.board): \($0)" }
            continue
        }
        let pixelWidth = size.width * copy.scale
        let pixelHeight = size.height * copy.scale
        if let type = copy.appStoreDisplayType, let accepted = acceptedSizes[type],
           !accepted.contains(where: { $0 == (pixelWidth, pixelHeight) }) {
            throw Failure("\(slide.board): \(pixelWidth) x \(pixelHeight) is not an accepted \(type) size")
        }
        let htmlURL = workURL.appendingPathComponent("\(slide.board).html")
        try prepared.html.write(to: htmlURL, atomically: true, encoding: .utf8)
        let renderer = BoardRenderer(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: copy.scale)
        let image = try await renderer.render(fileURL: htmlURL, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let outputURL = options.outputURL!.appendingPathComponent(slide.output)
        try writePNG(image, to: outputURL)
        let omittedNote = prepared.omitted.isEmpty ? "" : "  (left out: \(prepared.omitted.joined(separator: ", ")))"
        print("wrote \(slide.board) -> \(outputURL.path) \(pixelWidth)x\(pixelHeight)\(omittedNote)")
    }
    guard missing.isEmpty else {
        throw Failure("Missing captures (run the capture step, or pass --placeholder for a layout check only):\n  " + missing.joined(separator: "\n  "))
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
Task { @MainActor in
    do {
        try await run()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("compose: \(error)\n".utf8))
        exit(1)
    }
}
application.run()
