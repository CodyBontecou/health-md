#if os(iOS)
import CoreGraphics
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
    func testLetterAndA4ProduceTaggedMultipagePDFsWithLogicalTables() throws {
        XCTAssertEqual(ClinicianReportPageSize.forRegion("US"), .letter)
        XCTAssertEqual(ClinicianReportPageSize.forRegion("CA"), .letter)
        XCTAssertEqual(ClinicianReportPageSize.forRegion("MX"), .letter)
        XCTAssertEqual(ClinicianReportPageSize.forRegion("DE"), .a4)
        XCTAssertEqual(ClinicianReportPageSize.forRegion(nil), .a4)
        let copy = ClinicianReportCopy(locale: Locale(identifier: "en_US"))
        var rows = (0..<600).map { ["Jan 1, 2026", "8:00 AM", "\(60 + $0 % 20) bpm", "Synthetic Source"] }
        // Exercises both ordinary table pagination and the oversized-cell paragraph path.
        rows.insert(["Jan 2, 2026", "9:00 AM", "72 bpm", String(repeating: "Synthetic source details ", count: 500)], at: 300)
        let sources = copy.format(.sources, "Synthetic Source")
        let report = ClinicianReportData(
            title: copy.string(.document_title),
            displayName: nil,
            dateRangeLabel: "Jan 1 – Jan 30, 2026",
            generatedLabel: "Jan 31, 2026",
            timeZoneLabel: "UTC",
            sections: [MetricReportSummary(
                metric: .heartRate,
                facts: [ReportFact(label: copy.string(.fact_readings), value: "600")],
                sources: ["Synthetic Source"],
                coverageDisclosure: copy.format(.coverage, "30", "30", "0"),
                noDataMessage: nil,
                table: ReportTable(
                    title: copy.format(.table_metric_readings, copy.string(.metric_heart_rate)),
                    columns: [copy.string(.column_date), copy.string(.column_time), copy.string(.column_value), copy.string(.column_source)],
                    rows: rows
                ),
                localizedTitle: copy.string(.metric_heart_rate),
                sourcesDisclosure: sources,
                detailReadingsDescription: copy.format(.detail_readings_count, "600")
            )],
            warnings: [],
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
            availabilityNoteTitle: copy.string(.availability_note),
            aboutTitle: copy.string(.about),
            pageFooterTemplate: copy.string(.page_footer)
        )
        let renderer = ClinicianReportPDFRenderer()
        for size in ClinicianReportPageSize.allCases {
            let data = renderer.pdfData(report: report, pageSize: size)
            XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
            let provider = CGDataProvider(data: data as CFData)
            let document = provider.flatMap { CGPDFDocument($0) }
            XCTAssertNotNil(document)
            XCTAssertGreaterThan(document?.numberOfPages ?? 0, 1)

            let catalog = try XCTUnwrap(document?.catalog)
            var structureTree: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &structureTree))
            var parentTree: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(structureTree), "ParentTree", &parentTree))
            XCTAssertNotNil(parentTree)
            var markInfo: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "MarkInfo", &markInfo))
            var marked: CGPDFBoolean = 0
            XCTAssertTrue(CGPDFDictionaryGetBoolean(try XCTUnwrap(markInfo), "Marked", &marked))
            XCTAssertNotEqual(marked, 0)

            let parentTreeDictionary = try XCTUnwrap(parentTree)
            XCTAssertGreaterThan(parentTreeEntryCount(parentTreeDictionary), 0)

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
                var structParents: CGPDFInteger = -1
                XCTAssertTrue(CGPDFDictionaryGetInteger(page.dictionary, "StructParents", &structParents))
                XCTAssertGreaterThanOrEqual(structParents, 0)
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
