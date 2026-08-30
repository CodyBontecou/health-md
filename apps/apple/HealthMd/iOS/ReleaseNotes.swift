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

    private static var zipExportFilesVideoURL: URL {
        Bundle.main.url(
            forResource: "zip-export-files-notelet",
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
            version: "3.2.1",
            items: [
                .list(
                    title: "More dependable exports",
                    rows: [
                        .init(
                            symbolSystemName: "clock.badge.checkmark",
                            title: "History remembers each destination",
                            description: "Scheduled export history now keeps the exact profile and destination used by every run and retry."
                        ),
                        .init(
                            symbolSystemName: "folder.badge.gearshape",
                            title: "Folder changes stay saved",
                            description: "A new local, iCloud Drive, or Dropbox folder becomes active only after access is saved successfully. If access is denied, Health.md keeps your previous valid destination."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.2",
            items: [
                .list(
                    title: "Exports you can stop",
                    rows: [
                        .init(
                            symbolSystemName: "stop.circle.fill",
                            title: "Stop running exports",
                            description: "A single banner now owns export progress. Stop cancels the running scheduled, Shortcut, or manual export — completed dates stay completed, and schedules remain enabled."
                        ),
                        .init(
                            symbolSystemName: "list.bullet.rectangle.fill",
                            title: "Detailed Time-Series, separated",
                            description: "Export Data Detail now separates Detailed Time-Series from Lossless Health Records, so per-sample data no longer drags along the much larger canonical archive. New presets are available in the Export tab and export profiles."
                        ),
                        .init(
                            symbolSystemName: "arrow.triangle.2.circlepath",
                            title: "Self-healing Direct CLI Access",
                            description: "Connections recover automatically after your Mac sleeps, the app quits, or the network changes — no manual disconnect or repeated Pair tap required."
                        ),
                        .init(
                            symbolSystemName: "internaldrive.fill",
                            title: "Local folders stay selected",
                            description: "Folders on “On My iPhone” storage keep their saved selection across restarts, so automatic exports and Shortcuts keep working."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.1.1",
            items: [
                .list(
                    title: "Cloud folders stay selected",
                    rows: [
                        .init(
                            symbolSystemName: "icloud.fill",
                            title: "Cloud folders stay selected",
                            description: "Export folders on iCloud Drive, Dropbox, and similar cloud locations no longer lose their selection when the app restarts, so automatic exports and Shortcuts keep working without re-selecting the folder."
                        ),
                        .init(
                            symbolSystemName: "checkmark.circle.fill",
                            title: "Honest export toasts",
                            description: "A completed export shows the success toast with its Preview and Browse actions again instead of a red error."
                        ),
                        .init(
                            symbolSystemName: "text.badge.checkmark",
                            title: "Clearer failure reasons",
                            description: "Scheduled exports targeting an API endpoint with no configured URL now say exactly what to fix, and choosing the iCloud Drive root shows its real name."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.1",
            items: [
                .list(
                    title: "Profiles, fully editable",
                    rows: [
                        .init(
                            symbolSystemName: "slider.horizontal.3",
                            title: "One-place profile editor",
                            description: "Edit every export profile setting — target, destination folder or endpoint, formats, write mode, templates, and metrics — from a single editor with a system folder picker and inline endpoint creation."
                        ),
                        .init(
                            symbolSystemName: "exclamationmark.triangle",
                            title: "Overlap warnings",
                            description: "Health.md warns live when a new profile would write the same files as an existing one, before your data lands in the wrong place."
                        ),
                        .init(
                            symbolSystemName: "clock.badge.checkmark",
                            title: "Dependable scheduled exports",
                            description: "Profile schedules and the classic schedule run side by side, preserved retries survive interruptions, and notification taps resume the exact export."
                        ),
                        .init(
                            symbolSystemName: "figure.run",
                            title: "Clearer workout warnings",
                            description: "When a workout's structured plan can't be read on your device you'll see plain-language detail, and partial-export warnings can now be copied for bug reports."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.0.5",
            items: [
                .list(
                    title: "Share a clearer health story",
                    rows: [
                        .init(
                            symbolSystemName: "heart.text.clipboard",
                            title: "Clinician-ready reports",
                            description: "Turn selected Apple Health metrics into a focused report for the last 7, 30, or 90 days—or a custom date range."
                        ),
                        .init(
                            symbolSystemName: "doc.richtext",
                            title: "Preview before sharing",
                            description: "Review summaries and detailed readings, then create an accessible Letter or A4 PDF with clear source and availability context."
                        ),
                        .init(
                            symbolSystemName: "hand.raised.fill",
                            title: "Private by design",
                            description: "Reports are generated on your device and stay private until you explicitly share or save them."
                        ),
                        .init(
                            symbolSystemName: "qrcode.viewfinder",
                            title: "Faster Direct CLI pairing",
                            description: "Scan a pairing QR inside Health.md to validate and start a trusted private-LAN or Tailscale connection."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.0.4",
            items: [
                .list(
                    title: "Health.md in your language",
                    rows: [
                        .init(
                            symbolSystemName: "globe",
                            title: "Fully localized",
                            description: "Export, scheduling, formatting, preview, tracking, and Mac destination screens now support nine additional languages."
                        ),
                        .init(
                            symbolSystemName: "sparkles",
                            title: "A clearer first export",
                            description: "Improved onboarding guides you from Apple Health and folder setup to a ready-to-run preview."
                        ),
                        .init(
                            symbolSystemName: "doc.badge.gearshape",
                            title: "Control every export",
                            description: "Choose whether to include the Health.md data dictionary, and use the same free allowance for manual or scheduled exports."
                        ),
                        .init(
                            symbolSystemName: "hand.raised.fill",
                            title: "Clear privacy details",
                            description: "Updated privacy and analytics explanations spell out what limited product events contain—and what they never include."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.0.3",
            items: [
                .list(
                    title: "Clearer, more reliable exports",
                    rows: [
                        .init(
                            symbolSystemName: "heart.text.clipboard",
                            title: "Simpler Health access",
                            description: "Clinical Health Records are temporarily unavailable. Ordinary Apple Health metrics and lossless source-sample exports remain available."
                        ),
                        .init(
                            symbolSystemName: "bolt.fill",
                            title: "A faster first export",
                            description: "New installs begin with summary-only exports. Lossless Health Records remains available when you need the complete canonical source archive."
                        ),
                        .init(
                            symbolSystemName: "ipad",
                            title: "Reliable iPad exports",
                            description: "Preview and Export Data stay visible, and empty Apple Health libraries now show clear date-range and permission guidance instead of a generic error."
                        ),
                        .init(
                            symbolSystemName: "checkmark.circle.fill",
                            title: "One completion message",
                            description: "Multi-file exports now show the exported-file success view only after the entire export finishes."
                        ),
                        .init(
                            symbolSystemName: "arrow.trianglehead.2.clockwise.rotate.90",
                            title: "More resilient Mac exports",
                            description: "Connected iPhone-to-Mac exports recover more reliably and use less memory while preparing large summaries."
                        ),
                        .init(
                            symbolSystemName: "calendar.badge.checkmark",
                            title: "Accurate roll-up planning",
                            description: "Weekly, monthly, and yearly estimates and progress now reflect their complete calendar windows."
                        ),
                        .init(
                            symbolSystemName: "key.fill",
                            title: "Quieter Mac launch",
                            description: "The Mac app no longer accesses Keychain during ordinary launch; encrypted context status loads only when requested."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.0.2",
            items: [
                .list(
                    title: "A more complete health archive",
                    rows: [
                        .init(
                            symbolSystemName: "archivebox.fill",
                            title: "Lossless Health Records",
                            description: "Preserve original Apple Health samples with their sources, devices, timestamps, metadata, relationships, and available attachments."
                        ),
                        .init(
                            symbolSystemName: "checkmark.shield.fill",
                            title: "Honest export diagnostics",
                            description: "Capture results and warnings make missing permissions, unavailable records, and partial exports clear."
                        ),
                        .init(
                            symbolSystemName: "note.text.badge.plus",
                            title: "Daily Notes Only",
                            description: "Update or create Obsidian daily notes without adding aggregate files, ZIPs, roll-ups, individual entries, or provider sidecars."
                        ),
                        .init(
                            symbolSystemName: "calendar.badge.plus",
                            title: "Flexible schedules",
                            description: "Run exports every few days, weeks, or months from a start date."
                        ),
                        .init(
                            symbolSystemName: "link.badge.plus",
                            title: "Trusted Mac reconnects",
                            description: "Saved manual IP connections reconnect securely after the first pairing without requiring another code."
                        ),
                        .init(
                            symbolSystemName: "textformat.123",
                            title: "Two-digit year filenames",
                            description: "Use {YR} for years such as 26 in export filenames, folder templates, and Daily Note Injection."
                        ),
                        .init(
                            symbolSystemName: "creditcard.fill",
                            title: "One-time lifetime purchases",
                            description: "Full Access uses Individual Lifetime, Family Lifetime, and Family Upgrade purchases."
                        ),
                        .init(
                            symbolSystemName: "wrench.and.screwdriver.fill",
                            title: "Clearer recovery",
                            description: "Export History explains failures, suggests recovery steps, and keeps technical details available for troubleshooting."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.0.1",
            items: [
                .list(
                    title: "More reliable Mac exports",
                    rows: [
                        .init(
                            symbolSystemName: "link.badge.plus",
                            title: "Trusted reconnects",
                            description: "After the first pairing, saved manual IP connections can reconnect securely without requiring a new code each time."
                        ),
                        .init(
                            symbolSystemName: "arrow.trianglehead.2.clockwise.rotate.90",
                            title: "Resumable large exports",
                            description: "Large and multi-year iPhone-to-Mac exports use durable transfers and incremental file writing for better recovery and lower memory pressure."
                        ),
                        .init(
                            symbolSystemName: "calendar.badge.checkmark",
                            title: "Schedules keep their intent",
                            description: "Daily Notes Only, custom schedules, and interrupted connected jobs preserve their intended destination and export dates more consistently."
                        ),
                        .init(
                            symbolSystemName: "wrench.and.screwdriver.fill",
                            title: "Clearer recovery",
                            description: "Failed or interrupted connected exports provide better retry behavior and more useful recovery details."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "3.0",
            items: [
                .list(
                    title: "Lossless Health Records",
                    rows: [
                        .init(
                            symbolSystemName: "archivebox.fill",
                            title: "A more complete Apple Health archive",
                            description: "Capture original samples and their sources, devices, timestamps, metadata, relationships, and available attachments—not only daily totals."
                        ),
                        .init(
                            symbolSystemName: "checkmark.shield.fill",
                            title: "Honest export diagnostics",
                            description: "Export schema v7 reports missing permissions, unavailable records, and partial captures so incomplete exports no longer look complete."
                        ),
                        .init(
                            symbolSystemName: "doc.text.magnifyingglass",
                            title: "Complete data, readable notes",
                            description: "JSON and CSV preserve the source archive while Markdown and Obsidian Bases remain readable daily summaries."
                        ),
                        .init(
                            symbolSystemName: "note.text.badge.plus",
                            title: "Daily notes without extra files",
                            description: "Daily Notes Only updates or creates your Obsidian daily notes while keeping aggregate files, ZIPs, roll-ups, individual entries, and provider sidecars out of the vault."
                        ),
                        .init(
                            symbolSystemName: "calendar.badge.plus",
                            title: "Schedules that fit your routine",
                            description: "Run exports every few days, weeks, or months from a start date, including routines such as every other day or monthly."
                        ),
                        .init(
                            symbolSystemName: "creditcard.fill",
                            title: "One-time lifetime unlocks",
                            description: "Full Access offers Individual Lifetime, Family Lifetime, and Family Upgrade purchases for this release."
                        ),
                        .init(
                            symbolSystemName: "exclamationmark.triangle.fill",
                            title: "Clearer failures and recovery",
                            description: "Export History explains what failed, suggests what to try next, and keeps technical details available for better bug reports."
                        ),
                        .init(
                            symbolSystemName: "arrow.triangle.2.circlepath",
                            title: "More accurate and reliable exports",
                            description: "VO2 Max, Stand metrics, vitamins and minerals, blood pressure, timezone roll-ups, permission recovery, missed schedules, and connected iPhone-to-Mac exports are more consistent."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.9.2",
            items: [
                .list(
                    title: "Workout exports keep their identity",
                    rows: [
                        .init(
                            symbolSystemName: "figure.run.square.stack",
                            title: "Every HealthKit workout type",
                            description: "Markdown, Obsidian Bases, JSON, and CSV now preserve readable activity names, stable sport values, HealthKit cases, and original raw values—including Rolling and future unknown types."
                        ),
                        .init(
                            symbolSystemName: "clock.badge.checkmark",
                            title: "Timezones stay explicit",
                            description: "Exported dates and display times keep their captured calendar timezone, while complete machine-readable timestamps remain in UTC across iPhone and Mac."
                        ),
                        .init(
                            symbolSystemName: "doc.badge.gearshape",
                            title: "Versioned schema v4 exports",
                            description: "Existing files remain readable and compatible. Re-export dates for the new fields, and update the Health.md Obsidian plugin before enabling roll-up summaries or format folders."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.9",
            items: [
                .list(
                    title: "Scheduled exports, your way",
                    rows: [
                        .init(
                            symbolSystemName: "arrow.clockwise",
                            title: "Refresh today more often",
                            description: "Today Refresh can update the current day’s export every 3, 6, or 12 hours after your preferred schedule time."
                        ),
                        .init(
                            symbolSystemName: "target",
                            title: "Choose where schedules export",
                            description: "Scheduled runs can now write to your iPhone folder, send JSON to your API Endpoint, or deliver files to a connected Mac."
                        ),
                        .init(
                            symbolSystemName: "calendar.badge.clock",
                            title: "Smarter daily and weekly runs",
                            description: "Schedules can include the past 1–30 complete days, and retries keep the same dates and destination if iOS delays a run."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.8",
            items: [
                .list(
                    title: "More reliable roll-up summaries",
                    rows: [
                        .init(
                            symbolSystemName: "calendar.badge.clock",
                            title: "Archive and ZIP fixes",
                            description: "Weekly, monthly, and yearly roll-up summaries now write correctly inside archived and zipped exports."
                        ),
                        .init(
                            symbolSystemName: "desktopcomputer",
                            title: "Better Mac exports",
                            description: "Mac exports preserve roll-up settings more consistently when your iPhone prepares the data."
                        ),
                        .init(
                            symbolSystemName: "text.quote",
                            title: "Cleaner Markdown",
                            description: "Roll-up metric names, metadata, and summary tables are escaped more safely so your notes stay readable."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.7.1",
            items: [
                .list(
                    title: "Simpler lifetime unlock options",
                    rows: [
                        .init(
                            symbolSystemName: "creditcard.fill",
                            title: "Cleaner unlock options",
                            description: "The unlock screen shows lifetime Individual and Family plans alongside the free export allowance."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.7",
            items: [
                .list(
                    title: "API endpoints and more ways to unlock",
                    rows: [
                        .init(
                            symbolSystemName: "network",
                            title: "Export to your own API endpoint",
                            description: "Send selected Apple Health exports directly to an HTTP or HTTPS endpoint you control, using your metric and granular-data settings."
                        ),
                        .init(
                            symbolSystemName: "creditcard.fill",
                            title: "More unlock options",
                            description: "Health.md Pro supports lifetime Individual and Family Sharing plans while existing premium access stays grandfathered."
                        ),
                        .init(
                            symbolSystemName: "terminal.fill",
                            title: "Export from Terminal on Mac",
                            description: "Install the healthmd command from the Mac app, check readiness, and trigger iPhone Apple Health exports from scripts or automations."
                        ),
                        .init(
                            symbolSystemName: "iphone.and.arrow.forward",
                            title: "Mac to iPhone export requests",
                            description: "When your iPhone is open and connected, Health.md for Mac can ask it to export yesterday, recent days, or a custom date range to your Mac folder."
                        ),
                        .init(
                            symbolSystemName: "archivebox.fill",
                            title: "Archive roll-ups are more reliable",
                            description: "Weekly, monthly, and yearly summary files now land correctly in archived and zipped exports across iPhone, iPad, and Mac."
                        ),
                        .init(
                            symbolSystemName: "text.quote",
                            title: "Safer Markdown output",
                            description: "Metric names, roll-up summaries, and export metadata are escaped more carefully so generated notes stay readable in Obsidian and other Markdown tools."
                        )
                    ]
                )
            ]
        ),
        .init(
            version: "2.4.1",
            items: [
                .media(
                    kind: .video,
                    url: zipExportFilesVideoURL,
                    title: "Zip every export format",
                    description: "Bundle Markdown, Obsidian Bases, JSON, CSV, and the data dictionary into one portable archive for easier iCloud and vault moves."
                ),
                .list(
                    title: "Also in this release",
                    rows: [
                        .init(
                            symbolSystemName: "archivebox.fill",
                            title: "Zip export files",
                            description: "Turn on Zip Export Files to write one archive instead of loose files for the formats you selected."
                        ),
                        .init(
                            symbolSystemName: "sidebar.leading",
                            title: "Redesigned iPad app",
                            description: "A refreshed iPad layout makes export settings, history, schedule, sync, and account tools easier to scan on larger screens."
                        ),
                        .init(
                            symbolSystemName: "checkmark.seal",
                            title: "Cleaner export settings",
                            description: "The export format controls are easier to read, with Zip support presented alongside Markdown, Obsidian Bases, JSON, and CSV."
                        )
                    ]
                )
            ]
        ),
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
        guard !TestMode.isUITesting || TestMode.showsReleaseNotes else { return nil }

        #if DEBUG
        guard !MarketingCapture.isActive else { return nil }
        #endif

        return .current
    }

    /// First-run onboarding already introduces the current app version. Mark it
    /// seen before replacing onboarding with the export UI so Notelet cannot
    /// race and replace the requested first-export preview.
    static func markCurrentVersionAsSeenAfterOnboarding() {
        NoteletStorage.markCurrentVersionAsSeen()
    }

    static func resetSeenVersionForUITesting() {
        guard TestMode.isUITesting else { return }
        NoteletStorage.resetSeenVersion()
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
