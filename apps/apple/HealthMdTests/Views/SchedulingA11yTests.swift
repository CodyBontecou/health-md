#if os(iOS)
import XCTest
import SwiftUI
@testable import HealthMd

/// ADDED / NOT RUN by the source-only scheduling lane. These are actual
/// production components with synthetic bindings, not a scheduling/guard gate.
@MainActor
final class SchedulingA11yTests: XCTestCase {
    private let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility5]
    private let longName = "A complete weekly archive for a family with a descriptive profile name"

    private var actions: some View {
        SchedulingExportActions(
            previewIdentifier: "test.preview", exportIdentifier: "test.export",
            previewHint: "Synthetic preview", exportHint: "Synthetic export", onPreview: {}, onExport: {}
        )
    }

    private var samples: [(String, AnyView)] { [
        ("choices", AnyView(SchedulingChoicePicker(
            title: "Frequency", choices: ["Daily", "Weekly", "Custom"].map { SchedulingChoice(value: $0, title: $0) },
            selection: .constant("Custom")
        ))),
        ("menu", AnyView(SchedulingValueMenu(
            title: "Today Refresh interval", choices: [SchedulingChoice(value: 12, title: "Every 12 hours")], selection: .constant(12)
        ))),
        ("number", AnyView(SchedulingNumberControl(title: "Custom frequency interval", value: .constant(365),
                                                 bounds: 1...365, identifier: "test.number"))),
        ("time", AnyView(SchedulingTimeControls(hour: .constant(12), minute: .constant(55), period: .constant("PM"),
                                               hourIdentifier: "test.hour", minuteIdentifier: "test.minute", periodIdentifier: "test.period"))),
        ("info", AnyView(SchedulingInfoButton(action: {}))),
        ("history", AnyView(SchedulingHistoryHeading(showsClear: true, onClear: {}))),
        ("profile", AnyView(SchedulingProfileRow(name: longName, summary: "Every 365 months at 23:55. Today Refresh every 12 hours.",
                                               isEnabled: .constant(true), identifier: "test.profile", onEdit: {}))),
        ("summary", AnyView(SchedulingProfileSummary(name: longName, destination: "Folder: The entire named synthetic family archive",
                                                    cadence: "Weekly · Wednesday · 11:55 PM", formats: "Markdown · JSON · CSV · 123 metrics",
                                                    isActive: true, cadenceColor: .textSecondary))),
        ("fact", AnyView(SchedulingProfileFact(title: "Folder structure", value: "{year}/{month}/{day}/complete-archive"))),
        ("management", AnyView(SchedulingProfileManagementAction(icon: "trash", title: "Delete Profile…", isDestructive: true, action: {}))),
        ("presets", AnyView(SchedulingDatePresets(options: [
            SchedulingDatePreset(value: 0, title: "Today", hint: "Today", identifier: "test.today"),
            SchedulingDatePreset(value: 1, title: "Yesterday", hint: "Yesterday", identifier: "test.yesterday"),
            SchedulingDatePreset(value: 2, title: "All Time", hint: "All available health data", identifier: "test.allTime"),
            SchedulingDatePreset(value: 3, title: "Custom", hint: "Custom export range", identifier: "test.custom")
        ], selection: 1, onSelect: { _ in }))),
        ("date", AnyView(SchedulingLabeledControl(title: "Start Date", value: Text(Date(timeIntervalSince1970: 0), style: .date)) {
            DatePicker("Start Date", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date)
                .datePickerStyle(.compact)
        })),
        ("actions", AnyView(actions)),
        ("footer", AnyView(SchedulingExportFooter(freeExportsRemaining: 3, freeExportsIdentifier: "test.free") { actions }))
    ] }

    func testProductionComponentsFitNarrowAndLandscapeReadingWidths() {
        for size in sizes {
            for width: CGFloat in [192, 280, 568] {
                for (name, component) in samples {
                    let host = A11yHosting(component.environment(\.dynamicTypeSize, size), size: CGSize(width: width, height: 640))
                    let measured = host.measured(proposal: CGSize(width: width, height: 10_000))
                    host.close()
                    XCTAssertLessThanOrEqual(measured.width, width + 1, "\(name) at \(width), \(size)")
                    XCTAssertGreaterThan(measured.height, 0, name)
                }
            }
        }
    }

    func testProductionActionsHaveMinimumBounds() {
        for size in sizes {
            for component in [
                AnyView(SchedulingInfoButton(action: {})),
                AnyView(SchedulingProfileManagementAction(icon: "trash", title: "Delete Profile…", isDestructive: true, action: {})),
                AnyView(SchedulingValueMenu(title: "Minute", choices: [SchedulingChoice(value: 55, title: "55")], selection: .constant(55)))
            ] {
                let host = A11yHosting(component.environment(\.dynamicTypeSize, size))
                let measured = host.measured(proposal: CGSize(width: 280, height: 2000))
                host.close()
                XCTAssertGreaterThanOrEqual(measured.width, 44)
                XCTAssertGreaterThanOrEqual(measured.height, 44)
            }
        }
    }

    func testTimeAndExportActionsReflowOnLiveTextSizeChanges() {
        for (name, component) in samples where ["time", "actions", "footer"].contains(name) {
            let host = A11yHosting(component.environment(\.dynamicTypeSize, .large))
            defer { host.close() }
            let proposal = CGSize(width: 280, height: 2000)
            let baseline = host.measured(proposal: proposal)
            host.update(component.environment(\.dynamicTypeSize, .accessibility5))
            let enlarged = host.measured(proposal: proposal)
            XCTAssertGreaterThan(enlarged.height, baseline.height * 1.5, name)
            XCTAssertLessThanOrEqual(enlarged.width, 281, name)
            host.update(component.environment(\.dynamicTypeSize, .large))
            XCTAssertEqual(host.measured(proposal: proposal).height, baseline.height, accuracy: 1, name)
        }
    }

    func testCompleteProfileFactsGainHeightRatherThanLosingTextWidth() {
        let view = SchedulingProfileFact(title: "Complete destination", value: longName)
            .environment(\.dynamicTypeSize, .accessibility5)
        let host = A11yHosting(view)
        defer { host.close() }
        let wide = host.measured(proposal: CGSize(width: 568, height: 3000))
        let narrow = host.measured(proposal: CGSize(width: 192, height: 3000))
        XCTAssertLessThanOrEqual(narrow.width, 193)
        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    func testNativeUIKitCapturesInBothThemesAtAllTextSizes() {
        for size in sizes {
            for theme in [ColorScheme.light, .dark] {
                let view = ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SchedulingTimeControls(hour: .constant(12), minute: .constant(55), period: .constant("PM"),
                                               hourIdentifier: "test.hour", minuteIdentifier: "test.minute", periodIdentifier: "test.period")
                        SchedulingHistoryHeading(showsClear: true, onClear: {})
                        actions
                    }.padding(16)
                }
                .environment(\.dynamicTypeSize, size)
                .preferredColorScheme(theme)
                .background(Color.bgPrimary)
                let host = A11yHosting(view)
                let image = host.capture()
                host.close()
                XCTAssertGreaterThan(image.size.height, 0)
                let capture = XCTAttachment(image: image)
                capture.name = "scheduling-native-components-\(size)-\(theme)"
                capture.lifetime = .keepAlways
                add(capture)
            }
        }
    }
}
#endif
