//
//  AppearanceRegressionTests.swift
//  HealthMdTests
//
//  Guards the app's system-appearance behavior.
//

import XCTest

final class AppearanceRegressionTests: XCTestCase {

    private static let projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Utilities
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // project root
    }()

    func testProductionSwiftUIDoesNotForceAppearance() throws {
        let productionRoots = ["HealthMd", "HealthMdWidgets", "HealthMdWatch"]
        let swiftFiles = try productionRoots.flatMap {
            try Self.swiftFiles(under: Self.projectRoot.appendingPathComponent($0))
        }
            .filter { !$0.pathComponents.contains("Debug") }

        let disallowedPatterns = [
            ".preferredColorScheme(.dark)",
            ".environment(\\.colorScheme, .dark)",
            ".colorScheme(.dark)",
            ".preferredColorScheme(.light)",
            ".environment(\\.colorScheme, .light)",
            ".colorScheme(.light)",
        ]

        let violations = try swiftFiles.flatMap { file -> [String] in
            let content = try String(contentsOf: file, encoding: .utf8)
            return disallowedPatterns.compactMap { pattern in
                guard content.contains(pattern) else { return nil }
                return file.path.replacingOccurrences(of: Self.projectRoot.path + "/", with: "") + ": \(pattern)"
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Production UI must follow system Light/Dark appearance. Remove or scope appearance overrides:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testLiveActivityUsesSystemBackgroundAndActionColors() throws {
        let source = try String(contentsOf: Self.projectRoot.appendingPathComponent(
            "HealthMdWidgets/CLIExportLiveActivityWidget.swift"
        ), encoding: .utf8)
        XCTAssertFalse(source.contains(".activityBackgroundTint("))
        XCTAssertFalse(source.contains(".activitySystemActionForegroundColor("))
    }

    func testAppearanceAuditDocumentsDarkOnlyScope() throws {
        let auditURL = Self.projectRoot.appendingPathComponent("docs/testing/appearance-audit.md")
        let content = try String(contentsOf: auditURL, encoding: .utf8)

        XCTAssertTrue(content.contains("## Dark-only Scope"))
        XCTAssertTrue(content.contains("No production UI currently forces a dark color scheme."))
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }
}
