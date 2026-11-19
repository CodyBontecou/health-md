import XCTest
@testable import HealthMd

/// v3.5 parity M-10: the Frontmatter "Enable All Fields", "Disable All Fields" and
/// "Reset Names" actions.
final class FrontmatterBulkOperationTests: XCTestCase {
    func testDisableAllThenEnableAllTogglesEveryMetricFieldOnly() {
        let config = FrontmatterConfiguration()
        config.customFields = ["tags": "health"]
        config.placeholderFields = ["mood"]
        XCTAssertFalse(config.fields.isEmpty)

        config.setAllFieldsEnabled(false)
        XCTAssertTrue(config.fields.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(config.includeDate, "core metadata is not a metric field")
        XCTAssertTrue(config.includeType)
        XCTAssertEqual(config.customFields, ["tags": "health"])
        XCTAssertEqual(config.placeholderFields, ["mood"])

        config.setAllFieldsEnabled(true)
        XCTAssertTrue(config.fields.allSatisfy(\.isEnabled))
    }

    func testResetNamesRestoresSnakeCaseKeysAndKeepsEnablement() throws {
        let config = FrontmatterConfiguration()
        config.applyKeyStyle(.camelCase)
        let renamedIndex = try XCTUnwrap(config.fields.indices.first)
        config.fields[renamedIndex].customKey = "my_custom_name"
        config.fields[renamedIndex].isEnabled = false

        config.resetFieldNames()

        XCTAssertEqual(config.keyStyle, .snakeCase)
        XCTAssertEqual(
            config.fields.map(\.customKey),
            config.fields.map { FrontmatterKeyStyle.snakeCase.apply(to: $0.originalKey) }
        )
        XCTAssertNotEqual(config.fields[renamedIndex].customKey, "my_custom_name")
        XCTAssertFalse(config.fields[renamedIndex].isEnabled, "Reset Names changes names only")
    }
}
