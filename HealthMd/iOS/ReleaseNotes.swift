import SwiftUI
import Notelet

// MARK: - In-app release notes

enum HealthMdReleaseNotes {
    static let notes: [NoteletVersionNotes] = [
        .init(
            version: "2.1.3",
            items: [
                .list(
                    title: "What’s new in Health.md",
                    rows: [
                        .init(
                            symbolSystemName: "calendar.badge.clock",
                            title: "Export dates stay put",
                            description: "Health.md now remembers your last export date range so repeat exports start exactly where you left off."
                        ),
                        .init(
                            symbolSystemName: "eye",
                            title: "Large previews behave better",
                            description: "Long export previews are more reliable when you’re checking bigger date ranges before writing files."
                        ),
                        .init(
                            symbolSystemName: "figure.run.square.stack",
                            title: "Richer workout data",
                            description: "JSON exports can include workout metadata, route details, time-series samples, and indoor workout context."
                        ),
                        .init(
                            symbolSystemName: "waveform.path.ecg.rectangle",
                            title: "More granular context",
                            description: "Granular samples preserve HealthKit metadata so downstream notes and analysis keep more of the original signal."
                        )
                    ]
                )
            ]
        )
    ]

    static var presentedVersion: NoteletPresentedVersion? {
        guard !TestMode.isUITesting else { return nil }

        #if DEBUG
        guard !MarketingCapture.isActive else { return nil }
        #endif

        return .current
    }

    static let configuration = NoteletConfiguration(
        nextButtonLabel: "Next",
        doneButtonLabel: "Done",
        accentColor: .accent
    )
}

extension View {
    func healthMdReleaseNotesSheet() -> some View {
        noteletSheet(
            notes: HealthMdReleaseNotes.notes,
            version: HealthMdReleaseNotes.presentedVersion,
            configuration: HealthMdReleaseNotes.configuration
        )
    }
}
