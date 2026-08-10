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
    typealias ProgressHandler = @Sendable (_ progress: Double) -> Void

    func pdfData(
        report: ClinicianReportData,
        pageSize: ClinicianReportPageSize = .forLocale(),
        progress: ProgressHandler = { _ in }
    ) -> Data {
        progress(0)
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
                context.cgContext.addDocumentMetadata(metadata as CFData)
            }
            let continuationSubtitle = [
                report.displayName,
                "\(report.metadataPeriodLabel): \(report.dateRangeLabel)"
            ]
            .compactMap { $0 }
            .joined(separator: " • ")
            let layout = Layout(
                context: context,
                bounds: bounds,
                pageFooterTemplate: report.pageFooterTemplate,
                continuationTitle: report.title,
                continuationSubtitle: continuationSubtitle
            )
            layout.startPage()
            layout.document(language: report.languageTag, title: report.title) {
            progress(0.05)

        layout.title(report.title)
        layout.group {
            layout.metadata(label: report.metadataPeriodLabel, value: report.dateRangeLabel)
            layout.metadata(label: report.metadataGeneratedLabel, value: report.generatedLabel)
            layout.metadata(label: report.metadataTimeZoneLabel, value: report.timeZoneLabel)
            if let displayName = report.displayName {
                layout.metadata(label: report.metadataPatientLabel, value: displayName)
            }
        }
        progress(0.10)
        let availableSections = report.availableSections
        let availabilityMessages = report.warnings + [report.unavailableMeasurementsSummary].compactMap { $0 }
        if !availabilityMessages.isEmpty {
            layout.group {
                layout.section(report.availabilityNoteTitle)
                availabilityMessages.forEach(layout.paragraph)
            }
        }

        if availableSections.isEmpty {
            layout.group {
                layout.section(report.summaryTableTitle)
                layout.paragraph(report.noReportableDataMessage)
            }
        } else {
            let summaryRows = availableSections.map { section in
                [
                    section.localizedTitle,
                    coverageValue(section.availabilitySummary),
                    conciseSummary(section)
                ]
            }
            layout.group {
                layout.table(ReportTable(
                    title: report.summaryTableTitle,
                    columns: [
                        report.summaryTableTitle,
                        report.availabilityColumnLabel,
                        report.summaryColumnLabel
                    ],
                    rows: summaryRows
                ))
            }
        }
        progress(0.25)

        let detailedSections = availableSections.filter { $0.table != nil }
        let sectionWorkUnits = detailedSections.map { max($0.table?.rows.count ?? 0, 1) }
        let totalSectionWorkUnits = max(sectionWorkUnits.reduce(0, +), 1)
        var completedSectionWorkUnits = 0
        for (index, section) in detailedSections.enumerated() {
            if Task.isCancelled { break }
            let currentSectionWorkUnits = sectionWorkUnits[index]
            layout.group {
                layout.section(
                    section.localizedTitle,
                    detail: section.availabilitySummary,
                    keepWith: section.facts,
                    or: nil
                )
                if let table = section.table {
                    layout.table(table) { completedRows, totalRows in
                        let rowFraction = totalRows > 0
                            ? Double(completedRows) / Double(totalRows)
                            : 1
                        let completedWork = Double(completedSectionWorkUnits)
                            + (Double(currentSectionWorkUnits) * rowFraction)
                        progress(0.25 + (0.65 * completedWork / Double(totalSectionWorkUnits)))
                    }
                }
            }
            completedSectionWorkUnits += currentSectionWorkUnits
            progress(0.25 + (0.65 * Double(completedSectionWorkUnits) / Double(totalSectionWorkUnits)))
        }
        if detailedSections.isEmpty { progress(0.90) }
        layout.aboutSection(
            title: report.aboutTitle,
            disclaimer: report.disclaimer,
            attribution: report.attribution,
            practiceLine: report.practiceLine
        )
        progress(0.95)
        layout.finish()
            }
        progress(1)
        }
    }

    private func coverageValue(_ availabilitySummary: String) -> String {
        availabilitySummary
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .last
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? availabilitySummary
    }

    private func conciseSummary(_ section: MetricReportSummary) -> String {
        let facts = section.facts.suffix(2)
        guard !facts.isEmpty else { return section.availabilitySummary }
        return facts.map { "\($0.label): \($0.value)" }.joined(separator: "; ")
    }

    func renderArtifact(
        report: ClinicianReportData,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        pageSize: ClinicianReportPageSize = .forLocale(),
        fileManager: FileManager = .default,
        progress: ProgressHandler = { _ in }
    ) throws -> ExportArtifactFile {
        progress(0)
        try Task.checkCancellation()
        let root = fileManager.temporaryDirectory.appendingPathComponent("clinician-reports", isDirectory: true)
        let ownerDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: ownerDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ownerDirectory.path)
        let filename = "\(filenameComponent(report.title))_\(isoDate(startDate, calendar: calendar))_\(isoDate(endDate, calendar: calendar)).pdf"
        let url = ownerDirectory.appendingPathComponent(filename, isDirectory: false)
        let data = pdfData(report: report, pageSize: pageSize) { pdfProgress in
            progress(pdfProgress * 0.90)
        }
        do {
            try Task.checkCancellation()
            guard fileManager.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            progress(0.95)
            try Task.checkCancellation()
            let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            progress(1)
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
        private let continuationTitle: String
        private let continuationSubtitle: String
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
            let languageText: String?
            let titleText: String?
        }

        private var y: CGFloat = 44
        private var page = 0
        private var hasPage = false
        /// Logical tags currently surrounding the caller's layout closure. Page transitions
        /// temporarily close these tags before the footer and reopen continuation siblings on
        /// the new page, so no marked-content sequence crosses a page boundary.
        private var activeSemanticTags: [SemanticTag] = []

        init(
            context: UIGraphicsPDFRendererContext,
            bounds: CGRect,
            pageFooterTemplate: String,
            continuationTitle: String,
            continuationSubtitle: String
        ) {
            self.context = context
            self.bounds = bounds
            self.pageFooterTemplate = pageFooterTemplate
            self.continuationTitle = continuationTitle
            self.continuationSubtitle = continuationSubtitle
        }

        private var contentWidth: CGFloat { bounds.width - margin * 2 }
        private var contentBottom: CGFloat { bounds.height - footerHeight }

        func group(_ body: () -> Void) {
            tagged(.section, body: body)
        }

        func document(language: String, title: String, body: () -> Void) {
            tagged(.document, languageText: language, titleText: title, body: body)
        }

        func aboutSection(
            title: String,
            disclaimer: String,
            attribution: String,
            practiceLine: String?
        ) {
            let sectionHeight: CGFloat = 42
            let requiredHeight = sectionHeight
                + paragraphHeight(disclaimer, font: bodyFont)
                + paragraphHeight(attribution, font: bodyFont)
                + (practiceLine.map { paragraphHeight($0, font: bodyFont) } ?? 0)
            let pageContentHeight = contentBottom - margin
            ensure(min(requiredHeight, pageContentHeight))
            if requiredHeight <= pageContentHeight {
                y = contentBottom - requiredHeight
            }

            group {
                section(title)
                paragraph(disclaimer)
                paragraph(attribution)
                if let practiceLine { paragraph(practiceLine) }
            }
        }

        func startPage() {
            let isContinuation = hasPage
            let hasDocumentRoot = activeSemanticTags.first?.type == .document
            if isContinuation {
                suspendSemanticTags(excludingDocumentRoot: hasDocumentRoot)
                footer()
                if hasDocumentRoot { CGPDFContextEndTag(context.cgContext) }
            }
            context.beginPage()
            page += 1
            hasPage = true
            y = margin
            if isContinuation {
                if hasDocumentRoot, let documentRoot = activeSemanticTags.first {
                    beginTag(documentRoot)
                }
                continuationHeader()
                resumeSemanticTags(excludingDocumentRoot: hasDocumentRoot)
            }
        }

        func finish() {
            precondition(
                activeSemanticTags.count == 1 && activeSemanticTags.first?.type == .document,
                "PDF layout finished outside its document tag"
            )
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

        func section(
            _ text: String,
            detail: String? = nil,
            keepWith facts: [ReportFact] = [],
            or paragraph: String? = nil
        ) {
            let sectionHeight: CGFloat = detail == nil ? 42 : 54
            let firstFactsHeight = facts.prefix(2).reduce(CGFloat.zero) { partial, fact in
                partial + factRowHeight(label: fact.label, value: fact.value) + 2
            }
            let allFactsHeight = facts.reduce(CGFloat.zero) { partial, fact in
                partial + factRowHeight(label: fact.label, value: fact.value) + 2
            }
            let paragraphHeight = paragraph.map {
                min(height($0, width: contentWidth, font: bodyFont) + 4, bodyFont.lineHeight * 3 + 4)
            } ?? 0
            let pageContentHeight = contentBottom - margin
            let factsToKeep = sectionHeight + allFactsHeight <= pageContentHeight
                ? allFactsHeight
                : firstFactsHeight
            ensure(sectionHeight + max(factsToKeep, paragraphHeight))
            y += 14
            tagged(.header2, actualText: [text, detail].compactMap { $0 }.joined(separator: ", ")) {
                draw(text, rect: CGRect(x: margin, y: y, width: contentWidth, height: 18), font: headingFont, color: accent)
                if let detail {
                    draw(detail, rect: CGRect(x: margin, y: y + 17, width: contentWidth, height: 13), font: mutedFont, color: muted)
                }
                line(at: y + sectionHeight - 21)
            }
            y += sectionHeight - 14
        }

        func fact(label: String, value: String) {
            let labelWidth: CGFloat = 120
            let rowHeight = factRowHeight(label: label, value: value)
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

        private func factRowHeight(label: String, value: String) -> CGFloat {
            let labelWidth: CGFloat = 120
            let labelHeight = height(label, width: labelWidth - 6, font: bodyMediumFont)
            let valueHeight = height(value, width: contentWidth - labelWidth, font: bodyFont)
            return max(14, max(labelHeight, valueHeight))
        }

        private func paragraphHeight(_ text: String, font: UIFont) -> CGFloat {
            text.isEmpty ? 4 : height(text, width: contentWidth, font: font) + 4
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

        func table(
            _ table: ReportTable,
            progress: (_ completedRows: Int, _ totalRows: Int) -> Void = { _, _ in }
        ) {
            let count = max(1, table.columns.count)
            let totalRows = table.rows.count
            let progressInterval = max(totalRows / 100, 1)
            progress(0, totalRows)
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
                for (index, row) in table.rows.enumerated() {
                    if Task.isCancelled { return }
                    defer {
                        let completedRows = index + 1
                        if completedRows == totalRows || completedRows.isMultiple(of: progressInterval) {
                            progress(completedRows, totalRows)
                        }
                    }
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
            beginTag(SemanticTag(type: .nonStructure, actualText: "", languageText: nil, titleText: nil))
            divider.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: bounds.height - 38))
            path.addLine(to: CGPoint(x: bounds.width - margin, y: bounds.height - 38))
            path.lineWidth = 0.7
            path.stroke()
            let text = pageFooterTemplate.replacingOccurrences(of: "%1$d", with: "\(page)")
            draw(text, rect: CGRect(x: margin, y: bounds.height - 32, width: contentWidth, height: 14), font: mutedFont, color: muted)
            CGPDFContextEndTag(context.cgContext)
        }

        private func continuationHeader() {
            beginTag(SemanticTag(type: .nonStructure, actualText: "", languageText: nil, titleText: nil))
            draw(
                continuationTitle,
                rect: CGRect(x: margin, y: y, width: contentWidth, height: 14),
                font: bodyMediumFont,
                color: ink,
                lineBreak: .byTruncatingTail
            )
            draw(
                continuationSubtitle,
                rect: CGRect(x: margin, y: y + 14, width: contentWidth, height: 13),
                font: mutedFont,
                color: muted,
                lineBreak: .byTruncatingTail
            )
            line(at: y + 31)
            CGPDFContextEndTag(context.cgContext)
            y += 39
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
            languageText: String? = nil,
            titleText: String? = nil,
            body: () -> Void
        ) {
            let descriptor = SemanticTag(
                type: tag,
                actualText: actualText,
                languageText: languageText,
                titleText: titleText
            )
            activeSemanticTags.append(descriptor)
            beginTag(descriptor)
            body()
            CGPDFContextEndTag(context.cgContext)
            activeSemanticTags.removeLast()
        }

        private func beginTag(_ descriptor: SemanticTag) {
            var properties: [CGPDFTagProperty: String] = [:]
            if let actualText = descriptor.actualText {
                properties[.actualText] = actualText
            }
            if let languageText = descriptor.languageText {
                properties[.languageText] = languageText
            }
            if let titleText = descriptor.titleText {
                properties[.titleText] = titleText
            }
            CGPDFContextBeginTag(context.cgContext, descriptor.type, properties as CFDictionary)
        }

        private func suspendSemanticTags(excludingDocumentRoot: Bool) {
            let tags = excludingDocumentRoot ? activeSemanticTags.dropFirst() : activeSemanticTags[...]
            for _ in tags.reversed() { CGPDFContextEndTag(context.cgContext) }
        }

        private func resumeSemanticTags(excludingDocumentRoot: Bool) {
            let tags = excludingDocumentRoot ? activeSemanticTags.dropFirst() : activeSemanticTags[...]
            for descriptor in tags { beginTag(descriptor) }
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
