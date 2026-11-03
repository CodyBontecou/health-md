import Foundation
import Testing
@testable import HealthMd

@MainActor
struct ReleaseNotesContentTests {
    private let current = ReleaseVersionNotes(version: "3.5.0", items: [
        .list(title: "Current changes", rows: [
            .init(symbolSystemName: "folder", title: "Export", description: "Current release details"),
        ]),
        .media(kind: .image, url: URL(fileURLWithPath: "/bundled-preview.png"),
               title: "Preview", description: "Current release preview"),
    ])

    @Test func unseenCurrentReleaseKeepsItsListAndMediaPages() throws {
        let notes = try #require(ReleaseVersionNotes.pending(
            currentVersion: "3.5.0", lastSeenVersion: "3.4.4", isEnabled: true,
            catalog: [.init(version: "3.4.4", items: []), current]
        ))
        #expect(notes.version == "3.5.0")
        #expect(notes.items.count == 2)
        guard case .list(_, let rows) = notes.items[0],
              case .media(.image, let url, _, _) = notes.items[1] else {
            Issue.record("The renderer must receive the original ordered list and media pages")
            return
        }
        #expect(rows.count == 1)
        #expect(rows.first?.symbolSystemName == "folder")
        #expect(url.path == "/bundled-preview.png")
    }

    @Test func onboardingAcknowledgementPreventsFirstExportInterruption() {
        #expect(ReleaseVersionNotes.pending(
            currentVersion: current.version, lastSeenVersion: current.version,
            isEnabled: true, catalog: [current]
        ) == nil)
    }

    @Test func disabledPatchAndAutomationGatesDoNotPresent() {
        #expect(ReleaseVersionNotes.pending(
            currentVersion: current.version, lastSeenVersion: "3.4.4",
            isEnabled: false, catalog: [current]
        ) == nil)
    }

    @Test func missingOrEmptyReleaseDoesNotBlockTheNextPresentation() {
        #expect(ReleaseVersionNotes.pending(
            currentVersion: "3.5.1", lastSeenVersion: nil,
            isEnabled: true, catalog: [current]
        ) == nil)
        #expect(ReleaseVersionNotes.pending(
            currentVersion: "3.5.0", lastSeenVersion: nil,
            isEnabled: true, catalog: [.init(version: "3.5.0", items: [])]
        ) == nil)
    }

}
