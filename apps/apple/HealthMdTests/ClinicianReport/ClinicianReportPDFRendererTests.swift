#if os(iOS)
import CoreGraphics
import PDFKit
import XCTest
@testable import HealthMd

private struct ClinicianReportMarkedContentBalance {
    var depth = 0
    var minimumDepth = 0
    var begins = 0
    var ends = 0
}

@MainActor
final class ClinicianReportPDFRendererTests: XCTestCase {
    func testSummaryLayoutUsesCompactTableAndPinsAboutAboveFooter() throws {
        let copy = ClinicianReportCopy(locale: Locale(identifier: "en_US"))
        let precedingFacts = (1...30).map {
            ReportFact(label: "Reading \($0)", value: "72 bpm")
        }
        let report = ClinicianReportData(
            title: copy.string(.title),
            displayName: "Jordan Lee",
            dateRangeLabel: "Jul 11 – Aug 9, 2026",
            generatedLabel: "Aug 9, 2026",
            timeZoneLabel: "Atlantic Time (GMT−04:00)",
            sections: [
                MetricReportSummary(
                    metric: .heartRate,
                    facts: precedingFacts,
                    availabilitySummary: "Days with data: 30/30",
                    noDataMessage: nil,
                    table: nil,
                    localizedTitle: "Heart Rate",
                    detailReadingsDescription: "30 readings"
                ),
                MetricReportSummary(
                    metric: .respiratoryRate,
                    facts: [
                        ReportFact(label: "Readings", value: "30"),
                        ReportFact(label: "Median", value: "14.2 breaths/min"),
                        ReportFact(label: "Range", value: "12.0–17.0 breaths/min")
                    ],
                    availabilitySummary: "Days with data: 30/30",
                    noDataMessage: nil,
                    table: nil,
                    localizedTitle: "Respiratory Rate",
                    detailReadingsDescription: "30 readings"
                ),
                MetricReportSummary(
                    metric: .steps,
                    facts: [
                        ReportFact(label: "Readings", value: "30"),
                        ReportFact(label: "Average on days with data", value: "8,432 steps"),
                        ReportFact(label: "Range", value: "4,102–12,991 steps")
                    ],
                    availabilitySummary: "Days with data: 30/30",
                    noDataMessage: nil,
                    table: nil,
                    localizedTitle: "Steps",
                    detailReadingsDescription: "30 readings"
                )
            ],
            completeness: .complete,
            disclaimer: copy.string(.disclaimer),
            attribution: copy.string(.attribution),
            practiceLine: copy.practiceLine,
            languageTag: "en-US",
            pdfSubject: copy.string(.entry_subtitle),
            pdfKeywords: [copy.string(.title), "Health.md"],
            metadataPeriodLabel: copy.string(.metadata_period),
            metadataGeneratedLabel: copy.string(.metadata_generated),
            metadataTimeZoneLabel: copy.string(.metadata_timezone),
            metadataPatientLabel: copy.string(.metadata_patient),
            aboutTitle: copy.string(.about),
            pageFooterTemplate: copy.string(.page_footer),
            availabilityColumnLabel: copy.string(.fact_days_with_data),
            summaryTableTitle: copy.string(.metrics),
            summaryColumnLabel: copy.string(.summary)
        )

        let data = ClinicianReportPDFRenderer().pdfData(report: report, pageSize: .letter)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1)
        let pageStrings = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let respiratoryPage = try XCTUnwrap(pageStrings.firstIndex { $0.contains("Respiratory Rate") })
        XCTAssertEqual(respiratoryPage, 0)
        XCTAssertTrue(pageStrings[respiratoryPage].contains("Median"))
        XCTAssertTrue(pageStrings[respiratoryPage].contains("Range"))
        XCTAssertTrue(pageStrings[respiratoryPage].contains("14.2 breaths/min"))
        let documentText = pageStrings.joined(separator: "\n")
        let normalizedDocumentText = documentText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        XCTAssertTrue(normalizedDocumentText.contains("Average on days with data"))
        XCTAssertTrue(normalizedDocumentText.contains("8,432 steps"))
        XCTAssertTrue(normalizedDocumentText.contains("Reading 29"))
        XCTAssertTrue(normalizedDocumentText.contains("Reading 30"))
        XCTAssertFalse(normalizedDocumentText.contains("Reading 1:"))
        XCTAssertTrue(normalizedDocumentText.contains("healthmd.app/practice"))
        let aboutSelection = try XCTUnwrap(document.findString("About this report", withOptions: []).first)
        let aboutPage = try XCTUnwrap(aboutSelection.pages.first)
        let lastPage = try XCTUnwrap(document.page(at: document.pageCount - 1))
        XCTAssertEqual(aboutPage, lastPage)
        let practiceSelection = try XCTUnwrap(document.findString("healthmd.app/practice", withOptions: []).first)
        XCTAssertEqual(practiceSelection.pages.first, lastPage)
        let aboutBounds = aboutSelection.bounds(for: aboutPage)
        let practiceBounds = practiceSelection.bounds(for: lastPage)
        XCTAssertGreaterThan(aboutBounds.minY, practiceBounds.maxY)
        XCTAssertLessThan(aboutBounds.maxY, 200)
        XCTAssertGreaterThan(practiceBounds.minY, 38)
        XCTAssertLessThan(practiceBounds.minY, 70)
    }

    func testEmptyMeasurementsAreConsolidatedInsteadOfRepeated() throws {
        let copy = ClinicianReportCopy(locale: Locale(identifier: "en_US"))
        let sections = [ReportMetric.bloodPressure, .bloodGlucose, .weight].map { metric in
            MetricReportSummary(
                metric: metric,
                facts: [],
                availabilitySummary: "Days with data: 0/30",
                noDataMessage: copy.string(.no_data),
                table: nil,
                localizedTitle: metric.displayName(using: copy)
            )
        }
        let report = ClinicianReportData(
            title: copy.string(.title),
            displayName: nil,
            dateRangeLabel: "Jul 11 – Aug 9, 2026",
            generatedLabel: "Aug 9, 2026",
            timeZoneLabel: "Atlantic Time (GMT−04:00)",
            sections: sections,
            completeness: .complete,
            disclaimer: copy.string(.disclaimer),
            attribution: copy.string(.attribution),
            practiceLine: nil,
            languageTag: "en-US",
            pdfSubject: copy.string(.entry_subtitle),
            pdfKeywords: [copy.string(.title), "Health.md"],
            metadataPeriodLabel: copy.string(.metadata_period),
            metadataGeneratedLabel: copy.string(.metadata_generated),
            metadataTimeZoneLabel: copy.string(.metadata_timezone),
            metadataPatientLabel: copy.string(.metadata_patient),
            aboutTitle: copy.string(.about),
            pageFooterTemplate: copy.string(.page_footer),
            availabilityNoteTitle: copy.string(.availability_note),
            availabilityColumnLabel: copy.string(.fact_days_with_data),
            summaryTableTitle: copy.string(.metrics),
            summaryColumnLabel: copy.string(.summary),
            noReportableDataMessage: copy.string(.no_reportable_data),
            unavailableMeasurementsSummary: copy.format(
                .unavailable_measurements,
                sections.map(\.localizedTitle).joined(separator: ", ")
            )
        )

        let document = try XCTUnwrap(PDFDocument(data: ClinicianReportPDFRenderer().pdfData(report: report, pageSize: .letter)))
        XCTAssertEqual(document.pageCount, 1)
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains(copy.string(.no_reportable_data)))
        XCTAssertTrue(text.contains("No data: Blood Pressure, Blood Glucose, Weight"))
        XCTAssertFalse(text.contains(copy.string(.no_data)))
    }

    func testLetterAndA4ProduceTaggedMultipagePDFsWithLogicalTables() throws {
        XCTAssertEqual(ClinicianReportPageSize.forRegion("US"), .letter)
        XCTAssertEqual(ClinicianReportPageSize.forRegion("CA"), .letter)
        XCTAssertEqual(ClinicianReportPageSize.forRegion("MX"), .letter)
        XCTAssertEqual(ClinicianReportPageSize.forRegion("DE"), .a4)
        XCTAssertEqual(ClinicianReportPageSize.forRegion(nil), .a4)
        let copy = ClinicianReportCopy(locale: Locale(identifier: "en_US"))
        var rows = (0..<600).map { ["Jan 1, 2026", "8:00 AM", "\(60 + $0 % 20) bpm"] }
        // Exercises both ordinary table pagination and the oversized-cell paragraph path.
        rows.insert(["Jan 2, 2026", "9:00 AM", String(repeating: "72 bpm details ", count: 500)], at: 300)
        let report = ClinicianReportData(
            title: copy.string(.title),
            displayName: "Jordan Lee",
            dateRangeLabel: "Jan 1 – Jan 30, 2026",
            generatedLabel: "Jan 31, 2026",
            timeZoneLabel: "UTC",
            sections: [MetricReportSummary(
                metric: .heartRate,
                facts: [ReportFact(label: copy.string(.fact_readings), value: "600")],
                availabilitySummary: "\(copy.string(.fact_days_with_data)): 30/30",
                noDataMessage: nil,
                table: ReportTable(
                    title: copy.format(.table_metric_readings, copy.string(.metric_heart_rate)),
                    columns: [copy.string(.column_date), copy.string(.column_time), copy.string(.column_value)],
                    rows: rows
                ),
                localizedTitle: copy.string(.metric_heart_rate),
                detailReadingsDescription: copy.format(.detail_readings_count, "600")
            )],
            completeness: .complete,
            disclaimer: copy.string(.disclaimer),
            attribution: copy.string(.attribution),
            practiceLine: nil,
            languageTag: "en-US",
            pdfSubject: copy.string(.entry_subtitle),
            pdfKeywords: [copy.string(.title), "Health.md"],
            metadataPeriodLabel: copy.string(.metadata_period),
            metadataGeneratedLabel: copy.string(.metadata_generated),
            metadataTimeZoneLabel: copy.string(.metadata_timezone),
            metadataPatientLabel: copy.string(.metadata_patient),
            aboutTitle: copy.string(.about),
            pageFooterTemplate: copy.string(.page_footer),
            availabilityColumnLabel: copy.string(.fact_days_with_data),
            summaryTableTitle: copy.string(.metrics),
            summaryColumnLabel: copy.string(.summary)
        )
        let renderer = ClinicianReportPDFRenderer()
        for size in ClinicianReportPageSize.allCases {
            let data = renderer.pdfData(report: report, pageSize: size)
            XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
            let provider = CGDataProvider(data: data as CFData)
            let document = provider.flatMap { CGPDFDocument($0) }
            XCTAssertNotNil(document)
            XCTAssertGreaterThan(document?.numberOfPages ?? 0, 1)

            let pdfDocument = try XCTUnwrap(PDFDocument(data: data))
            for pageIndex in 1..<pdfDocument.pageCount {
                let pageText = pdfDocument.page(at: pageIndex)?.string ?? ""
                XCTAssertTrue(pageText.contains(copy.string(.title)))
                XCTAssertTrue(pageText.contains("Jordan Lee"))
                XCTAssertTrue(pageText.contains("Jan 1 – Jan 30, 2026"))
            }

            let catalog = try XCTUnwrap(document?.catalog)
            var structureTree: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &structureTree))
            var parentTree: CGPDFDictionaryRef?
            let hasParentTree = CGPDFDictionaryGetDictionary(try XCTUnwrap(structureTree), "ParentTree", &parentTree)
            if !hasParentTree {
                // Core Graphics 26 emits the structure tree and balanced marked content but
                // reserves dangling ParentTree/IDTree references in its xref table. Keep the
                // stronger assertion on older runtimes and accept either result once Apple
                // repairs the iOS 26 writer.
                XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
            }
            var markInfo: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "MarkInfo", &markInfo))
            var marked: CGPDFBoolean = 0
            XCTAssertTrue(CGPDFDictionaryGetBoolean(try XCTUnwrap(markInfo), "Marked", &marked))
            XCTAssertNotEqual(marked, 0)

            if let parentTree {
                XCTAssertGreaterThan(parentTreeEntryCount(parentTree), 0)
            }

            var roles = Set<String>()
            var nonStructureViolations: [[String]] = []
            walkStructureTree(
                dictionary: try XCTUnwrap(structureTree),
                ancestors: [],
                roles: &roles,
                nonStructureViolations: &nonStructureViolations
            )
            for role in ["Document", "Sect", "H1", "H2", "H3", "P", "Table", "TR", "TH", "TD", "NonStruct"] {
                XCTAssertTrue(roles.contains(role), "Missing logical role \(role)")
            }
            XCTAssertTrue(nonStructureViolations.isEmpty, "Running/decorative structure nested under semantic content: \(nonStructureViolations)")

            for pageIndex in 1...(document?.numberOfPages ?? 0) {
                let page = try XCTUnwrap(document?.page(at: pageIndex))
                let pageDictionary = try XCTUnwrap(page.dictionary)
                var structParents: CGPDFInteger = -1
                let hasStructParents = CGPDFDictionaryGetInteger(pageDictionary, "StructParents", &structParents)
                if hasStructParents {
                    XCTAssertGreaterThanOrEqual(structParents, 0)
                } else {
                    XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 26)
                }
                let balance = markedContentBalance(in: page)
                XCTAssertGreaterThan(balance.begins, 0)
                XCTAssertEqual(balance.begins, balance.ends, "Unbalanced marked content on page \(pageIndex)")
                XCTAssertEqual(balance.depth, 0, "Marked content crosses page \(pageIndex) boundary")
                XCTAssertGreaterThanOrEqual(balance.minimumDepth, 0)
            }

            var metadataStream: CGPDFStreamRef?
            XCTAssertTrue(CGPDFDictionaryGetStream(catalog, "Metadata", &metadataStream))
            var dataFormat: CGPDFDataFormat = .raw
            let metadata = try XCTUnwrap(metadataStream.flatMap { CGPDFStreamCopyData($0, &dataFormat) }) as Data
            let xmp = try XCTUnwrap(String(data: metadata, encoding: .utf8))
            XCTAssertTrue(xmp.contains("dc:language"))
            XCTAssertTrue(xmp.contains("en-US"))
            XCTAssertFalse(xmp.contains("pdfuaid"), "Tagged output must not make an unproven PDF/UA claim")
        }
    }

    private func markedContentBalance(in page: CGPDFPage) -> ClinicianReportMarkedContentBalance {
        guard let table = CGPDFOperatorTableCreate() else { return ClinicianReportMarkedContentBalance() }
        let content = CGPDFContentStreamCreateWithPage(page)
        var balance = ClinicianReportMarkedContentBalance()
        CGPDFOperatorTableSetCallback(table, "BDC") { _, info in
            guard let pointer = info?.assumingMemoryBound(to: ClinicianReportMarkedContentBalance.self) else { return }
            pointer.pointee.depth += 1
            pointer.pointee.begins += 1
        }
        CGPDFOperatorTableSetCallback(table, "BMC") { _, info in
            guard let pointer = info?.assumingMemoryBound(to: ClinicianReportMarkedContentBalance.self) else { return }
            pointer.pointee.depth += 1
            pointer.pointee.begins += 1
        }
        CGPDFOperatorTableSetCallback(table, "EMC") { _, info in
            guard let pointer = info?.assumingMemoryBound(to: ClinicianReportMarkedContentBalance.self) else { return }
            pointer.pointee.depth -= 1
            pointer.pointee.ends += 1
            pointer.pointee.minimumDepth = min(pointer.pointee.minimumDepth, pointer.pointee.depth)
        }
        return withUnsafeMutablePointer(to: &balance) { pointer in
            let scanner = CGPDFScannerCreate(content, table, pointer)
            _ = CGPDFScannerScan(scanner)
            return pointer.pointee
        }
    }

    private func parentTreeEntryCount(_ dictionary: CGPDFDictionaryRef) -> Int {
        var total = 0
        var numbers: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Nums", &numbers), let numbers {
            total += CGPDFArrayGetCount(numbers) / 2
        }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Kids", &kids), let kids {
            for index in 0..<CGPDFArrayGetCount(kids) {
                var child: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, index, &child), let child {
                    total += parentTreeEntryCount(child)
                }
            }
        }
        return total
    }

    private func walkStructureTree(
        dictionary: CGPDFDictionaryRef,
        ancestors: [String],
        roles: inout Set<String>,
        nonStructureViolations: inout [[String]]
    ) {
        var rolePointer: UnsafePointer<CChar>?
        let role: String?
        if CGPDFDictionaryGetName(dictionary, "S", &rolePointer), let rolePointer {
            role = String(cString: rolePointer)
        } else {
            role = nil
        }
        let path = role.map { ancestors + [$0] } ?? ancestors
        if let role {
            roles.insert(role)
            let forbiddenAncestors: Set<String> = ["Sect", "Table", "TR", "TH", "TD", "P", "H1", "H2", "H3", "H4", "H5", "H6"]
            if role == "NonStruct", ancestors.contains(where: forbiddenAncestors.contains) {
                nonStructureViolations.append(path)
            }
        }

        var kidsObject: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(dictionary, "K", &kidsObject), let kidsObject {
            walkStructureObject(
                kidsObject,
                ancestors: path,
                roles: &roles,
                nonStructureViolations: &nonStructureViolations
            )
        }
    }

    private func walkStructureObject(
        _ object: CGPDFObjectRef,
        ancestors: [String],
        roles: inout Set<String>,
        nonStructureViolations: inout [[String]]
    ) {
        switch CGPDFObjectGetType(object) {
        case .dictionary:
            var dictionary: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary {
                walkStructureTree(
                    dictionary: dictionary,
                    ancestors: ancestors,
                    roles: &roles,
                    nonStructureViolations: &nonStructureViolations
                )
            }
        case .array:
            var array: CGPDFArrayRef?
            if CGPDFObjectGetValue(object, .array, &array), let array {
                for index in 0..<CGPDFArrayGetCount(array) {
                    var child: CGPDFObjectRef?
                    if CGPDFArrayGetObject(array, index, &child), let child {
                        walkStructureObject(
                            child,
                            ancestors: ancestors,
                            roles: &roles,
                            nonStructureViolations: &nonStructureViolations
                        )
                    }
                }
            }
        default:
            break
        }
    }
}
#endif
