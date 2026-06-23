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

    private static var healthWidgetsImageURL: URL {
        Bundle.main.url(
            forResource: "health-widgets-notelet",
            withExtension: "png"
        ) ?? Bundle.main.bundleURL
    }

    static let notes: [NoteletVersionNotes] = [
        .init(
            version: "2.4",
            items: [
                .media(
                    kind: .image,
                    url: healthWidgetsImageURL,
                    title: "Health.md on Apple Watch",
                    description: "A quick look at the Apple Watch experience, plus new widgets and complications for watch faces."
                ),
                .list(
                    title: "Also in this release",
                    rows: [
                        .init(
                            symbolSystemName: "applewatch",
                            title: "Apple Watch app",
                            description: "Check recent activity, recovery, sleep, and heart metrics right from your wrist."
                        ),
                        .init(
                            symbolSystemName: "rectangle.stack.fill",
                            title: "Watch widgets and complications",
                            description: "Pin focused Health.md metrics to supported watch faces for faster daily check-ins."
                        ),
                        .init(
                            symbolSystemName: "sparkles",
                            title: "Refreshed visual design",
                            description: "Updated app screens and widget previews match the new Health.md look across iPhone, iPad, Mac, and watchOS."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.3.1",
            items: [
                .media(
                    kind: .video,
                    url: fileTypeFoldersVideoURL,
                    title: "Organize exports by file type",
                    description: "Keep Markdown, Obsidian Bases, JSON, and CSV in their own folders before date folders when your vault is ready for the new layout."
                ),
                .list(
                    title: "Medication exports upgraded",
                    rows: [
                        .init(
                            symbolSystemName: "checkmark.seal",
                            title: "Health.md schema v2",
                            description: "Markdown, Obsidian Bases, JSON, and CSV now identify schema v2 for the richer medication archive format."
                        ),
                        .init(
                            symbolSystemName: "pills.fill",
                            title: "Full medication context",
                            description: "Exports include medication identifiers, display and export names, forms, active or archived state, schedules, related codings, and RxNorm codes when available."
                        ),
                        .init(
                            symbolSystemName: "calendar.badge.clock",
                            title: "Detailed dose events",
                            description: "Dose exports now preserve statuses, quantities, scheduled quantities, timestamps, schedule type, stable IDs, and Health metadata."
                        ),
                        .init(
                            symbolSystemName: "lock.doc",
                            title: "Safer metadata escaping",
                            description: "Medication names and metadata are sorted deterministically and escaped more carefully so Markdown, CSV, and individual-entry notes stay readable."
                        )
                    ]
                ),
                .list(
                    title: "Also in this release",
                    rows: [
                        .init(
                            symbolSystemName: "chart.bar.xaxis",
                            title: "Weekly, monthly, and yearly roll-ups",
                            description: "Opt in to summary files that aggregate your selected metrics across every export format without changing your daily notes."
                        ),
                        .init(
                            symbolSystemName: "moon.zzz",
                            title: "Sleep lands on the right day",
                            description: "Exporting Yesterday after waking now includes the sleep session that started the previous night."
                        ),
                        .init(
                            symbolSystemName: "person.2",
                            title: "Family Lifetime unlock",
                            description: "A new Family Sharing purchase option lets households share unlimited exports with a single one-time purchase."
                        ),
                        .init(
                            symbolSystemName: "wrench.and.screwdriver.fill",
                            title: "Family plan restore fix",
                            description: "Fixed a Family Lifetime plan configuration bug that could prevent restoring access on another Apple Family device."
                        ),
                        .init(
                            symbolSystemName: "folder",
                            title: "Folder access is more resilient",
                            description: "Temporary Files or cloud-provider errors no longer clear your selected vault, and exports write more safely."
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
