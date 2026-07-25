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

    func testProductionSwiftUIDoesNotForceDarkAppearance() throws {
        let productionRoot = Self.projectRoot.appendingPathComponent("HealthMd")
        let swiftFiles = try Self.swiftFiles(under: productionRoot)
            .filter { !$0.pathComponents.contains("Debug") }

        let disallowedPatterns = [
            ".preferredColorScheme(.dark)",
            ".environment(\\.colorScheme, .dark)",
            ".colorScheme(.dark)",
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
            "Production UI must follow system Light/Dark appearance. Remove or scope dark appearance overrides:\n\(violations.joined(separator: "\n"))"
        )
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
