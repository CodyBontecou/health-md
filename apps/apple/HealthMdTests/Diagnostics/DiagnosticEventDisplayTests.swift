import Foundation
import XCTest
@testable import HealthMd

final class DiagnosticEventDisplayTests: XCTestCase {
    private func event(_ id: DiagnosticEventID, severity: String, fields: [String: DiagnosticValue] = [:], timestamp: String = "2026-10-30T18:41:00.000Z") -> DiagnosticEvent {
        DiagnosticEvent(
            schema: "healthmd.diagnostic_event", schema_version: 1, timestamp: timestamp,
            session_id: "00000000-0000-0000-0000-000000000001", sequence: 1, monotonic_ms: 1,
            platform: "ios", event_id: id, subsystem: id.subsystem, severity: severity,
            source: "HealthMd/Test.swift:1", fields: fields, omitted_fields: [:]
        )
    }

    func testSeverityTagsAndAttention() {
        XCTAssertEqual(DiagnosticEventDisplay.severityLabel("warning"), "WARN")
        XCTAssertEqual(DiagnosticEventDisplay.severityLabel("error"), "ERROR")
        XCTAssertEqual(DiagnosticEventDisplay.severityLabel("info"), "INFO")
        XCTAssertTrue(DiagnosticEventDisplay.needsAttention("warning"))
        XCTAssertTrue(DiagnosticEventDisplay.needsAttention("error"))
        XCTAssertFalse(DiagnosticEventDisplay.needsAttention("debug"))
    }

    func testSummaryListsFieldsInStableOrderAndSkipsInvalid() {
        let summary = DiagnosticEventDisplay.summary(
            eventID: "export.result",
            fields: ["status": .text("ok"), "days": .integer(7), "bad": .invalid, "retry": .boolean(false)]
        )
        XCTAssertEqual(summary, "export.result days=7 retry=false status=ok")
    }

    func testTimeLabelShowsTimeTodayAndDateOtherwise() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(DiagnosticRecorder.parseTimestamp("2026-10-30T20:00:00.000Z"))
        let today = DiagnosticEventDisplay.timeLabel("2026-10-30T18:41:00.000Z", now: now, calendar: calendar)
        let earlier = DiagnosticEventDisplay.timeLabel("2026-10-28T18:41:00.000Z", now: now, calendar: calendar)
        XCTAssertTrue(today.contains("41"), today)
        XCTAssertNotEqual(today, earlier)
        XCTAssertEqual(DiagnosticEventDisplay.timeLabel("not a timestamp", now: now, calendar: calendar), "—")
    }

    func testDiagnosticSummaryCountsIssuesAndNeverIncludesFields() {
        let events = [
            event(.appStarted, severity: DiagnosticEventID.appStarted.severity),
            event(.transportError, severity: "warning", fields: ["peer_name": .text("SECRET_PEER")]),
            event(.notificationFailed, severity: "error")
        ]
        let text = DiagnosticSummary.text(events: events, recordingEnabled: true)
        XCTAssertTrue(text.contains("Events: 3 · warnings: 1 · errors: 1"), text)
        XCTAssertTrue(text.contains("WARN sync.transport_error"))
        XCTAssertTrue(text.contains("ERROR notification.request_failed"))
        XCTAssertFalse(text.contains("SECRET_PEER"))
        XCTAssertFalse(text.contains("app.started"), "Only warnings and errors are listed")
    }
}
