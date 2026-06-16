import SwiftUI
import Notelet

// MARK: - In-app release notes

enum HealthMdReleaseNotes {
    private static var fileTypeFoldersVideoURL: URL {
        Bundle.main.url(
            forResource: "file-type-folders-notelet",
            withExtension: "mp4"
        ) ?? Bundle.main.bundleURL
    }

    static let notes: [NoteletVersionNotes] = [
        .init(
            version: "2.1.10",
            items: [
                .media(
                    kind: .video,
                    url: fileTypeFoldersVideoURL,
                    title: "Keep export files organized",
                    description: "Group Markdown, Obsidian Bases, JSON, and CSV into their own folders before your date folders."
                ),
                .list(
                    title: "Export schema rollout",
                    rows: [
                        .init(
                            symbolSystemName: "checkmark.seal",
                            title: "Exports are now versioned",
                            description: "Markdown, Obsidian Bases, JSON, and CSV identify Health.md schema v1 so existing files keep working and newer tools can read the format safely."
                        ),
                        .init(
                            symbolSystemName: "ruler",
                            title: "Structured units stay canonical",
                            description: "Frontmatter, Bases, JSON, and CSV store canonical metric values while human-readable Markdown can still follow your Metric or Imperial display preference."
                        ),
                        .init(
                            symbolSystemName: "puzzlepiece.extension",
                            title: "Plugin-safe opt-ins",
                            description: "Update the Obsidian plugin before enabling roll-up summaries or file type folders; both settings stay off until you turn them on."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.1.9",
            items: [
                .list(
                    title: "What’s new in Health.md",
                    rows: [
                        .init(
                            symbolSystemName: "figure.run.square.stack",
                            title: "Workout exports are easier to read",
                            description: "Markdown now shows rich workout details in clean tables instead of inline YAML, including heart-rate zones, splits, samples, routes, elevation, power, cadence, and metadata."
                        ),
                        .init(
                            symbolSystemName: "tablecells.badge.ellipsis",
                            title: "Obsidian Bases gets workout detail",
                            description: "Bases files now include structured per-workout frontmatter so your health dashboards can query laps, splits, zones, route counts, and sample counts from each day."
                        ),
                        .init(
                            symbolSystemName: "doc.badge.gearshape",
                            title: "Separate workout notes stay optional",
                            description: "Individual Entry Tracking still creates one file per workout only when you enable Workouts; otherwise, detailed workout data stays in the daily exports."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.1.8",
            items: [
                .list(
                    title: "What’s new in Health.md",
                    rows: [
                        .init(
                            symbolSystemName: "ruler",
                            title: "Imperial distance exports are clearer",
                            description: "Miles now export under mile-specific frontmatter fields, so Obsidian Bases no longer shows mile values with kilometer labels."
                        ),
                        .init(
                            symbolSystemName: "slider.horizontal.3",
                            title: "Your field settings carry forward",
                            description: "Custom keys, disabled fields, and camelCase distance settings automatically migrate to the new mile fields."
                        ),
                        .init(
                            symbolSystemName: "checkmark.seal",
                            title: "Export units are more consistent",
                            description: "Markdown, CSV, JSON, and Obsidian Bases exports now share safer distance unit handling across metric and imperial settings."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.1.7",
            items: [
                .list(
                    title: "What’s new in Health.md",
                    rows: [
                        .init(
                            symbolSystemName: "heart.text.square",
                            title: "Blood Pressure permissions are safer",
                            description: "Health.md no longer opens an extra Health permissions sheet while exporting when Blood Pressure access is disabled."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.1.6",
            items: [
                .list(
                    title: "What’s new in Health.md",
                    rows: [
                        .init(
                            symbolSystemName: "checkmark.shield.fill",
                            title: "Export screens stay responsive",
                            description: "Health.md no longer shows a stuck Health permissions bar while previewing or exporting your health data."
                        ),
                        .init(
                            symbolSystemName: "heart.text.square",
                            title: "Health permission handling is safer",
                            description: "Exports now skip unavailable Health metrics without opening surprise system permission prompts."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.1.5",
            items: [
                .list(
                    title: "What’s new in Health.md",
                    rows: [
                        .init(
                            symbolSystemName: "doc.text.magnifyingglass",
                            title: "Frontmatter fields now export",
                            description: "Markdown previews and exports now include your enabled Health Metric frontmatter fields, not just the core date and type metadata."
                        ),
                        .init(
                            symbolSystemName: "slider.horizontal.3",
                            title: "Your field choices are respected",
                            description: "Custom frontmatter keys, snake_case or camelCase styles, and disabled metric fields now behave consistently in Markdown output."
                        ),
                        .init(
                            symbolSystemName: "checkmark.seal",
                            title: "Preview matches the file",
                            description: "Markdown and Obsidian Bases now share the same frontmatter renderer so what you preview is what gets written."
                        )
                    ]
                )
            ]
        ),
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
