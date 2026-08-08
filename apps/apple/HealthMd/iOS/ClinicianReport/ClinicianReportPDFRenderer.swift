import CryptoKit
import Foundation
import UIKit

nonisolated enum ClinicianReportPageSize: CaseIterable, Equatable, Sendable {
    case letter
    case a4

    var size: CGSize {
        switch self {
        case .letter: return CGSize(width: 612, height: 792)
        case .a4: return CGSize(width: 595, height: 842)
        }
    }

    static func forRegion(_ regionCode: String?) -> ClinicianReportPageSize {
        ["US", "CA", "MX"].contains(regionCode?.uppercased() ?? "") ? .letter : .a4
    }

    static func forLocale(_ locale: Locale = .current) -> ClinicianReportPageSize {
        forRegion(locale.region?.identifier)
    }
}

nonisolated struct ClinicianReportPDFRenderer: Sendable {
    func pdfData(
        report: ClinicianReportData,
        pageSize: ClinicianReportPageSize = .forLocale()
    ) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize.size)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: report.title,
            kCGPDFContextAuthor as String: "Health.md",
            kCGPDFContextCreator as String: "Health.md",
            kCGPDFContextSubject as String: report.pdfSubject,
            kCGPDFContextKeywords as String: report.pdfKeywords
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            if let metadata = xmpMetadata(for: report) {
                CGPDFContextAddDocumentMetadata(context.cgContext, metadata as CFData)
            }
            let layout = Layout(context: context, bounds: bounds, pageFooterTemplate: report.pageFooterTemplate)
            layout.startPage()
            let documentProperties = [
                kCGPDFTagPropertyLanguageText: report.languageTag,
                kCGPDFTagPropertyTitleText: report.title
            ] as CFDictionary
            context.cgContext.beginTag(.document, properties: documentProperties)
            defer { context.cgContext.endTag() }

            layout.title(report.title)
            layout.group {
                layout.metadata(label: report.metadataPeriodLabel, value: report.dateRangeLabel)
                layout.metadata(label: report.metadataGeneratedLabel, value: report.generatedLabel)
                layout.metadata(label: report.metadataTimeZoneLabel, value: report.timeZoneLabel)
                if let displayName = report.displayName {
                    layout.metadata(label: report.metadataPatientLabel, value: displayName)
                }
            }
            if !report.warnings.isEmpty {
                layout.group {
                    layout.section(report.availabilityNoteTitle)
                    report.warnings.forEach(layout.paragraph)
                }
            }
            for section in report.sections {
                if Task.isCancelled { break }
                layout.group {
                    layout.section(section.localizedTitle)
                    if let noData = section.noDataMessage { layout.paragraph(noData) }
                    for fact in section.facts { layout.fact(label: fact.label, value: fact.value) }
                    if let coverage = section.coverageDisclosure { layout.paragraph(coverage) }
                    if let sources = section.sourcesDisclosure { layout.paragraph(sources) }
                    if let table = section.table { layout.table(table) }
                }
            }
            layout.group {
                layout.section(report.aboutTitle)
                layout.paragraph(report.disclaimer)
                layout.paragraph(report.attribution)
                if let practiceLine = report.practiceLine { layout.smallParagraph(practiceLine) }
            }
            layout.finish()
        }
    }

    func renderArtifact(
        report: ClinicianReportData,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        pageSize: ClinicianReportPageSize = .forLocale(),
        fileManager: FileManager = .default
    ) throws -> ExportArtifactFile {
        try Task.checkCancellation()
        let root = fileManager.temporaryDirectory.appendingPathComponent("clinician-reports", isDirectory: true)
        let ownerDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: ownerDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ownerDirectory.path)
        let filename = "\(filenameComponent(report.title))_\(isoDate(startDate, calendar: calendar))_\(isoDate(endDate, calendar: calendar)).pdf"
        let url = ownerDirectory.appendingPathComponent(filename, isDirectory: false)
        let data = pdfData(report: report, pageSize: pageSize)
        do {
            try Task.checkCancellation()
            guard fileManager.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try Task.checkCancellation()
            let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return ExportArtifactFile(
                descriptor: ExportArtifactDescriptor(byteCount: UInt64(data.count), sha256: sha256, mediaType: "application/pdf"),
                lease: RestrictedArtifactFileLease(url: url, removesParentDirectoryIfEmpty: true)
            )
        } catch {
            try? fileManager.removeItem(at: ownerDirectory)
            throw error
        }
    }

    private func filenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.replacingOccurrences(of: " ", with: "-").unicodeScalars.map {
            allowed.contains($0) ? String($0) : "-"
        }.joined()
        let collapsed = scalars.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((collapsed.isEmpty ? "HealthMd" : collapsed).prefix(60))
    }

    private func isoDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func xmpMetadata(for report: ClinicianReportData) -> Data? {
        let title = xmlEscaped(report.title)
        let subject = xmlEscaped(report.pdfSubject)
        let language = xmlEscaped(report.languageTag)
        let keywords = xmlEscaped(report.pdfKeywords.joined(separator: ", "))
        let xml = """
        <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:pdf="http://ns.adobe.com/pdf/1.3/" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
              <dc:title><rdf:Alt><rdf:li xml:lang="\(language)">\(title)</rdf:li></rdf:Alt></dc:title>
              <dc:description><rdf:Alt><rdf:li xml:lang="\(language)">\(subject)</rdf:li></rdf:Alt></dc:description>
              <dc:language><rdf:Bag><rdf:li>\(language)</rdf:li></rdf:Bag></dc:language>
              <pdf:Keywords>\(keywords)</pdf:Keywords>
              <xmp:CreatorTool>Health.md</xmp:CreatorTool>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        return xml.data(using: .utf8)
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    nonisolated private final class Layout {
        private let context: UIGraphicsPDFRendererContext
        private let bounds: CGRect
        private let pageFooterTemplate: String
        private let margin: CGFloat = 44
        private let footerHeight: CGFloat = 42
        private let titleFont = UIFont.systemFont(ofSize: 22, weight: .semibold)
        private let headingFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        private let bodyFont = UIFont.systemFont(ofSize: 9.5)
        private let bodyMediumFont = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        private let mutedFont = UIFont.systemFont(ofSize: 8.5)
        private let tableFont = UIFont.monospacedSystemFont(ofSize: 7.3, weight: .regular)
        private let tableHeaderFont = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
        private let ink = UIColor(white: 0.09, alpha: 1)
        private let muted = UIColor(white: 0.32, alpha: 1)
        private let accent = UIColor(red: 0.40, green: 0.28, blue: 0.56, alpha: 1)
        private let divider = UIColor(white: 0.86, alpha: 1)
        private struct SemanticTag {
            let type: CGPDFTagType
            let actualText: String?
        }

        private var y: CGFloat = 44
        private var page = 0
        private var hasPage = false
        /// Logical tags currently surrounding the caller's layout closure. Page transitions
        /// temporarily close these tags before the footer and reopen continuation siblings on
        /// the new page, so no marked-content sequence crosses a page boundary.
        private var activeSemanticTags: [SemanticTag] = []

        init(context: UIGraphicsPDFRendererContext, bounds: CGRect, pageFooterTemplate: String) {
            self.context = context
            self.bounds = bounds
            self.pageFooterTemplate = pageFooterTemplate
        }

        private var contentWidth: CGFloat { bounds.width - margin * 2 }
        private var contentBottom: CGFloat { bounds.height - footerHeight }

        func group(_ body: () -> Void) {
            tagged(.section, body: body)
        }

        func startPage() {
            let isContinuation = hasPage
            if isContinuation {
                suspendSemanticTags()
                footer()
            }
            context.beginPage()
            page += 1
            hasPage = true
            y = margin
            if isContinuation { resumeSemanticTags() }
        }

        func finish() {
            precondition(activeSemanticTags.isEmpty, "PDF layout finished with unbalanced semantic tags")
            if hasPage { footer() }
        }

        func title(_ text: String) {
            ensure(42)
            tagged(.header1, actualText: text) {
                draw(text, rect: CGRect(x: margin, y: y, width: contentWidth, height: 30), font: titleFont, color: ink)
                line(at: y + 34)
            }
            y += 44
        }

        func metadata(label: String, value: String) {
            let labelWidth: CGFloat = 84
            let valueHeight = height(value, width: contentWidth - labelWidth, font: bodyFont)
            guard valueHeight <= contentBottom - margin else {
                paragraph("\(label): \(value)", font: bodyFont, color: ink)
                return
            }
            ensure(max(14, valueHeight))
            tagged(.paragraph, actualText: "\(label): \(value)") {
                draw("\(label):", rect: CGRect(x: margin, y: y, width: labelWidth - 4, height: 14), font: bodyMediumFont, color: ink)
                draw(value, rect: CGRect(x: margin + labelWidth, y: y, width: contentWidth - labelWidth, height: max(14, valueHeight)), font: bodyFont, color: ink)
            }
            y += max(14, valueHeight)
        }

        func section(_ text: String) {
            ensure(42)
            y += 14
            tagged(.header2, actualText: text) {
                draw(text, rect: CGRect(x: margin, y: y, width: contentWidth, height: 18), font: headingFont, color: accent)
                line(at: y + 21)
            }
            y += 28
        }

        func fact(label: String, value: String) {
            let labelWidth: CGFloat = 120
            let rowHeight = max(14, height(value, width: contentWidth - labelWidth, font: bodyFont))
            guard rowHeight <= contentBottom - margin else {
                paragraph("\(label): \(value)", font: bodyFont, color: ink)
                return
            }
            ensure(rowHeight + 2)
            tagged(.paragraph, actualText: "\(label): \(value)") {
                draw(label, rect: CGRect(x: margin, y: y, width: labelWidth - 6, height: rowHeight), font: bodyMediumFont, color: ink)
                draw(value, rect: CGRect(x: margin + labelWidth, y: y, width: contentWidth - labelWidth, height: rowHeight), font: bodyFont, color: ink)
            }
            y += rowHeight + 2
        }

        func paragraph(_ text: String) { paragraph(text, font: bodyFont, color: ink) }
        func smallParagraph(_ text: String) { paragraph(text, font: mutedFont, color: muted) }

        private func paragraph(_ text: String, font: UIFont, color: UIColor) {
            var remaining = Array(text)
            while !remaining.isEmpty {
                if Task.isCancelled { return }
                var available = contentBottom - y
                if available < font.lineHeight {
                    startPage()
                    available = contentBottom - y
                }
                let whole = String(remaining)
                let measured = height(whole, width: contentWidth, font: font)
                if measured <= available {
                    tagged(.paragraph, actualText: whole) {
                        draw(whole, rect: CGRect(x: margin, y: y, width: contentWidth, height: measured), font: font, color: color)
                    }
                    y += measured + 4
                    return
                }

                var lower = 1
                var upper = remaining.count
                while lower < upper {
                    let candidate = (lower + upper + 1) / 2
                    let candidateHeight = height(String(remaining.prefix(candidate)), width: contentWidth, font: font)
                    if candidateHeight <= available { lower = candidate } else { upper = candidate - 1 }
                }
                var fittingCount = max(1, lower)
                if fittingCount < remaining.count {
                    var wordBoundary = fittingCount
                    while wordBoundary > 1 && !remaining[wordBoundary - 1].isWhitespace {
                        wordBoundary -= 1
                    }
                    if wordBoundary > 1 { fittingCount = wordBoundary }
                }
                let pageText = String(remaining.prefix(fittingCount))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let pageHeight = height(pageText, width: contentWidth, font: font)
                tagged(.paragraph, actualText: pageText) {
                    draw(pageText, rect: CGRect(x: margin, y: y, width: contentWidth, height: pageHeight), font: font, color: color)
                }
                y += pageHeight
                remaining.removeFirst(fittingCount)
                while remaining.first?.isWhitespace == true { remaining.removeFirst() }
                if !remaining.isEmpty { startPage() }
            }
            y += 4
        }

        func table(_ table: ReportTable) {
            let count = max(1, table.columns.count)
            let columnWidth = contentWidth / CGFloat(count)
            let maximumRowHeight = contentBottom - margin - 19
            func naturalRowHeight(_ row: [String]) -> CGFloat {
                let heights = (0..<count).map { index in
                    height(index < row.count ? row[index] : "", width: columnWidth - 6, font: tableFont)
                }
                return max(17, (heights.max() ?? 12) + 6)
            }
            let naturalFirstRowHeight = table.rows.first.map(naturalRowHeight) ?? 0
            let firstRowHeight = naturalFirstRowHeight > maximumRowHeight ? 17 : naturalFirstRowHeight
            ensure(7 + 21 + 19 + firstRowHeight)
            y += 7
            tagged(.header3, actualText: table.title) {
                draw(table.title, rect: CGRect(x: margin, y: y, width: contentWidth, height: 18), font: headingFont, color: accent)
            }
            y += 21
            tagged(.table) {
                tableHeader(table.columns)
                for row in table.rows {
                    if Task.isCancelled { return }
                    let naturalHeight = naturalRowHeight(row)
                    if naturalHeight > maximumRowHeight {
                        tagged(.tableRow) {
                            for index in 0..<count {
                                let label = index < table.columns.count ? table.columns[index] : ""
                                let text = index < row.count ? row[index] : ""
                                tagged(.tableDataCell) {
                                    paragraph("\(label): \(text)", font: tableFont, color: ink)
                                }
                            }
                            line()
                        }
                        continue
                    }
                    let rowHeight = naturalHeight
                    if y + rowHeight > contentBottom {
                        startPage()
                        tableHeader(table.columns)
                    }
                    tagged(.tableRow) {
                        for index in 0..<count {
                            let text = index < row.count ? row[index] : ""
                            tagged(.tableDataCell, actualText: text) {
                                draw(text, rect: CGRect(x: margin + CGFloat(index) * columnWidth + 3, y: y + 3, width: columnWidth - 6, height: rowHeight - 5), font: tableFont, color: ink)
                            }
                        }
                        line(at: y + rowHeight)
                    }
                    y += rowHeight
                }
            }
        }

        private func tableHeader(_ columns: [String]) {
            let count = max(1, columns.count)
            let width = contentWidth / CGFloat(count)
            ensure(19)
            tagged(.tableRow) {
                // The background is non-text paint in the row's marked content and therefore
                // adds no separate logical structure node.
                UIColor(red: 0.96, green: 0.94, blue: 0.97, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 17))
                for (index, label) in columns.enumerated() {
                    tagged(.tableHeaderCell, actualText: label) {
                        draw(label, rect: CGRect(x: margin + CGFloat(index) * width + 3, y: y + 3, width: width - 6, height: 12), font: tableHeaderFont, color: ink, lineBreak: .byTruncatingTail)
                    }
                }
            }
            y += 19
        }

        private func ensure(_ required: CGFloat) {
            if y + required > contentBottom { startPage() }
        }

        private func footer() {
            // startPage() has suspended every child semantic tag, so this running content is
            // always a direct child of Document rather than a child of a section or table.
            // Core Graphics exposes NonStruct rather than a public Artifact authoring API.
            beginTag(SemanticTag(type: .nonStructure, actualText: ""))
            divider.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: bounds.height - 38))
            path.addLine(to: CGPoint(x: bounds.width - margin, y: bounds.height - 38))
            path.lineWidth = 0.7
            path.stroke()
            let text = pageFooterTemplate.replacingOccurrences(of: "%1$d", with: "\(page)")
            draw(text, rect: CGRect(x: margin, y: bounds.height - 32, width: contentWidth, height: 14), font: mutedFont, color: muted)
            context.cgContext.endTag()
        }

        private func line(at lineY: CGFloat? = nil) {
            // Decorative rules do not create a logical child. They remain non-text paint in the
            // heading or row marked-content sequence that visually owns them.
            let lineY = lineY ?? y
            divider.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: lineY))
            path.addLine(to: CGPoint(x: bounds.width - margin, y: lineY))
            path.lineWidth = 0.7
            path.stroke()
        }

        private func tagged(
            _ tag: CGPDFTagType,
            actualText: String? = nil,
            body: () -> Void
        ) {
            let descriptor = SemanticTag(type: tag, actualText: actualText)
            activeSemanticTags.append(descriptor)
            beginTag(descriptor)
            body()
            context.cgContext.endTag()
            activeSemanticTags.removeLast()
        }

        private func beginTag(_ descriptor: SemanticTag) {
            let properties: CFDictionary?
            if let actualText = descriptor.actualText {
                properties = [kCGPDFTagPropertyActualText: actualText] as CFDictionary
            } else {
                properties = nil
            }
            context.cgContext.beginTag(descriptor.type, properties: properties)
        }

        private func suspendSemanticTags() {
            for _ in activeSemanticTags.reversed() { context.cgContext.endTag() }
        }

        private func resumeSemanticTags() {
            for descriptor in activeSemanticTags { beginTag(descriptor) }
        }

        private func height(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            return max(font.lineHeight, ceil((text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height))
        }

        private func draw(
            _ text: String,
            rect: CGRect,
            font: UIFont,
            color: UIColor,
            lineBreak: NSLineBreakMode = .byWordWrapping
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = lineBreak
            (text as NSString).draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
                context: nil
            )
        }
    }
}
