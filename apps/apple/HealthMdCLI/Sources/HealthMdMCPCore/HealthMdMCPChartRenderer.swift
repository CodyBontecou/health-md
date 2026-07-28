import AppKit
import Foundation

enum HealthMdMCPChartRenderer {
    private struct Point {
        let date: String
        let value: Double?
        let status: String
    }

    private struct Series {
        let metricID: String
        let displayName: String
        let unit: String
        let points: [Point]
    }

    /// Static PNG fallback for MCP clients that support image content but have
    /// not negotiated MCP Apps. The exact complete JSON remains the first text
    /// content block; this image is a bounded visual summary, never the data contract.
    static func imageContents(_ data: Data) -> [MCPJSONValue] {
        guard let root = try? JSONDecoder().decode(MCPJSONValue.self, from: data),
              let image = render(root) else { return [] }
        return [.object([
            "type": .string("image"),
            "data": .string(image.base64EncodedString()),
            "mimeType": .string("image/png"),
            "_meta": .object(["codex/imageDetail": .string("original")])
        ])]
    }

    private static func render(_ root: MCPJSONValue) -> Data? {
        let series = extractSeries(root)
        guard !series.isEmpty else { return nil }

        let width = 1_200
        let height = 675
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.982, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        drawText(
            "Health.md metric chart",
            x: 48,
            top: 34,
            size: 30,
            weight: .semibold,
            color: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.16, alpha: 1),
            canvasHeight: height
        )
        drawText(
            "Factual local observations · Missing values remain gaps, never zero",
            x: 48,
            top: 76,
            size: 16,
            weight: .regular,
            color: NSColor(calibratedWhite: 0.38, alpha: 1),
            canvasHeight: height
        )

        let shown = Array(series.prefix(6))
        let panelTop = 118.0
        let panelGap = 12.0
        let availableHeight = Double(height) - panelTop - 44
        let panelHeight = (availableHeight - panelGap * Double(max(0, shown.count - 1)))
            / Double(shown.count)
        for (index, value) in shown.enumerated() {
            drawSeries(
                value,
                top: panelTop + Double(index) * (panelHeight + panelGap),
                height: panelHeight,
                width: Double(width),
                canvasHeight: height
            )
        }
        if series.count > shown.count {
            drawText(
                "Showing \(shown.count) of \(series.count) series in this image; the complete typed JSON is attached to the tool result.",
                x: 48,
                top: Double(height) - 26,
                size: 13,
                weight: .regular,
                color: NSColor(calibratedWhite: 0.42, alpha: 1),
                canvasHeight: height
            )
        }

        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func drawSeries(
        _ series: Series,
        top: Double,
        height: Double,
        width: Double,
        canvasHeight: Int
    ) {
        let card = NSRect(
            x: 36,
            y: Double(canvasHeight) - top - height,
            width: width - 72,
            height: height
        )
        let shape = NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14)
        NSColor.white.setFill()
        shape.fill()
        NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        drawText(
            series.displayName,
            x: 56,
            top: top + 16,
            size: 17,
            weight: .semibold,
            color: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.16, alpha: 1),
            canvasHeight: canvasHeight
        )
        let availableCount = series.points.compactMap(\.value).count
        drawText(
            "\(availableCount)/\(series.points.count) numeric · \(series.unit)",
            x: width - 260,
            top: top + 17,
            size: 13,
            weight: .regular,
            color: NSColor(calibratedWhite: 0.42, alpha: 1),
            canvasHeight: canvasHeight
        )

        let plotLeft = 180.0
        let plotRight = width - 58
        let plotTop = top + 16
        let plotBottom = top + height - 16
        let values = series.points.compactMap(\.value)
        guard let rawMinimum = values.min(), let rawMaximum = values.max() else {
            drawText(
                "No numeric observations in this scope",
                x: plotLeft,
                top: top + height / 2 - 8,
                size: 15,
                weight: .regular,
                color: NSColor(calibratedWhite: 0.45, alpha: 1),
                canvasHeight: canvasHeight
            )
            return
        }
        var minimum = rawMinimum
        var maximum = rawMaximum
        if minimum == maximum {
            let padding = abs(minimum == 0 ? 1 : minimum) * 0.08
            minimum -= padding
            maximum += padding
        }

        drawText(
            formatted(maximum),
            x: 56,
            top: plotTop + 5,
            size: 12,
            weight: .regular,
            color: NSColor(calibratedWhite: 0.42, alpha: 1),
            canvasHeight: canvasHeight
        )
        drawText(
            formatted(minimum),
            x: 56,
            top: plotBottom - 16,
            size: 12,
            weight: .regular,
            color: NSColor(calibratedWhite: 0.42, alpha: 1),
            canvasHeight: canvasHeight
        )

        func x(_ index: Int) -> Double {
            guard series.points.count > 1 else { return (plotLeft + plotRight) / 2 }
            return plotLeft + Double(index) * (plotRight - plotLeft)
                / Double(series.points.count - 1)
        }
        func y(_ value: Double) -> Double {
            let fromTop = plotTop + (maximum - value) * (plotBottom - plotTop)
                / (maximum - minimum)
            return Double(canvasHeight) - fromTop
        }

        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: plotLeft, y: Double(canvasHeight) - plotBottom))
        baseline.line(to: NSPoint(x: plotRight, y: Double(canvasHeight) - plotBottom))
        NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
        baseline.lineWidth = 1
        baseline.stroke()

        let accent = NSColor(calibratedRed: 0.08, green: 0.43, blue: 0.82, alpha: 1)
        var segment: [NSPoint] = []
        func strokeSegment() {
            guard !segment.isEmpty else { return }
            if segment.count > 1 {
                let path = NSBezierPath()
                path.move(to: segment[0])
                segment.dropFirst().forEach(path.line(to:))
                accent.setStroke()
                path.lineWidth = 2.5
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                path.stroke()
            }
            segment.removeAll(keepingCapacity: true)
        }

        for (index, point) in series.points.enumerated() {
            guard let value = point.value else {
                strokeSegment()
                continue
            }
            let location = NSPoint(x: x(index), y: y(value))
            segment.append(location)
            accent.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: location.x - 3.5,
                y: location.y - 3.5,
                width: 7,
                height: 7
            )).fill()
        }
        strokeSegment()

        if let first = series.points.first, let last = series.points.last {
            drawText(
                first.date,
                x: plotLeft,
                top: plotBottom + 2,
                size: 11,
                weight: .regular,
                color: NSColor(calibratedWhite: 0.42, alpha: 1),
                canvasHeight: canvasHeight
            )
            drawText(
                last.date,
                x: plotRight - 74,
                top: plotBottom + 2,
                size: 11,
                weight: .regular,
                color: NSColor(calibratedWhite: 0.42, alpha: 1),
                canvasHeight: canvasHeight
            )
        }
    }

    private static func extractSeries(_ root: MCPJSONValue) -> [Series] {
        guard let rootObject = root.objectValue else { return [] }
        let envelopes: [MCPJSONValue]
        if rootObject["schema"]?.stringValue == "healthmd.mcp_query_pages" {
            envelopes = rootObject["pages"]?.arrayValue ?? []
        } else {
            envelopes = [root]
        }

        struct MutableSeries {
            var displayName: String
            var unit: String
            var points: [Point]
        }
        var groups: [String: MutableSeries] = [:]
        for envelope in envelopes {
            guard let items = envelope.objectValue?["items"]?.arrayValue else { continue }
            for item in items {
                guard let object = item.objectValue,
                      object["type"]?.stringValue == "metric",
                      let metric = object["metric"]?.objectValue,
                      let metricID = metric["metric_id"]?.stringValue,
                      let date = metric["owner_date"]?.stringValue else { continue }
                let parsed = numericValue(metric["value"])
                let status = metric["status"]?.stringValue ?? "unknown"
                var group = groups[metricID] ?? MutableSeries(
                    displayName: metric["display_name"]?.stringValue ?? metricID,
                    unit: parsed.unit,
                    points: []
                )
                if group.unit.isEmpty, !parsed.unit.isEmpty { group.unit = parsed.unit }
                group.points.append(Point(
                    date: date,
                    value: isPlottableStatus(status) ? parsed.value : nil,
                    status: status
                ))
                groups[metricID] = group
            }
        }
        return groups.map { metricID, value in
            Series(
                metricID: metricID,
                displayName: value.displayName,
                unit: value.unit,
                points: value.points.sorted { $0.date < $1.date }
            )
        }.sorted { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.metricID < rhs.metricID
        }
    }

    static func isPlottableStatus(_ status: String) -> Bool {
        status == "available"
    }

    private static func numericValue(_ value: MCPJSONValue?) -> (value: Double?, unit: String) {
        guard let object = value?.objectValue,
              let type = object["type"]?.stringValue else { return (nil, "") }
        switch type {
        case "quantity": return (object["value"]?.doubleValue, object["unit"]?.stringValue ?? "")
        case "duration": return (object["seconds"]?.doubleValue, "s")
        case "count": return (object["value"]?.doubleValue, "count")
        default: return (nil, "")
        }
    }

    private static func drawText(
        _ text: String,
        x: Double,
        top: Double,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        canvasHeight: Int
    ) {
        text.draw(
            at: NSPoint(x: x, y: Double(canvasHeight) - top - Double(size) - 3),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color
            ]
        )
    }

    private static func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
