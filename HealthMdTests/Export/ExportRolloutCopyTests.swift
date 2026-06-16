import XCTest
@testable import HealthMd

final class ExportRolloutCopyTests: XCTestCase {
    func testRolloutHelpCopyCoversSchemaGuardrails() {
        XCTAssertTrue(ExportRolloutCopy.versionedExportsHelp.contains("schema \(HealthMdExportSchema.identifier) v\(HealthMdExportSchema.version)"))
        XCTAssertTrue(ExportRolloutCopy.canonicalUnitsHelp.contains("unit_system: metric"))
        XCTAssertTrue(ExportRolloutCopy.dataDictionaryHelp.contains(HealthMdExportSchema.dataDictionaryFilename))
        XCTAssertTrue(ExportRolloutCopy.dataDictionaryHelp.contains("roll-up rules"))
        XCTAssertTrue(ExportRolloutCopy.formatFoldersHelp.contains("off by default"))
        XCTAssertTrue(ExportRolloutCopy.rollupSummariesHelp.contains("off by default"))
        XCTAssertTrue(ExportRolloutCopy.rollupSummariesHelp.contains(HealthRollupExportSchema.identifier))
        XCTAssertTrue(ExportRolloutCopy.rollupSummariesHelp.contains("not daily records"))
        XCTAssertTrue(ExportRolloutCopy.pluginCompatibilityHelp.contains("Obsidian plugin"))
        XCTAssertTrue(ExportRolloutCopy.pluginCompatibilityHelp.contains("mixed-export compatibility smoke test"))
    }
}
