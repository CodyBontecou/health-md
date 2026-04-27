//
//  DailyNoteInjectionView.swift
//  Health.md
//
//  Settings UI for injecting health metrics into the YAML frontmatter of daily notes.
//

#if os(iOS)
import SwiftUI

struct DailyNoteInjectionView: View {
    @ObservedObject var settings: DailyNoteInjectionSettings
    let metricSelection: MetricSelectionState
    var healthSubfolder: String = ""

    var body: some View {
        Form {
            // MARK: — Enable / Disable
            Section {
                Toggle("Inject into Daily Notes", isOn: $settings.enabled)
                    .tint(Color.accent)
                    .accessibilityLabel("Inject health metrics into daily notes")
                    .accessibilityValue(settings.enabled ? "Enabled" : "Disabled")
            } header: {
                Text("Daily Note Injection")
                    .font(Typography.caption())
                    .foregroundColor(Color.textSecondary)
            } footer: {
                Text("When enabled, your selected health metrics are merged into the YAML frontmatter of your existing daily notes on every export. By default the note body is left alone — turn on \"Inject metric sections\" below to also write Sleep, Activity, etc. into the note body.")
                    .font(Typography.caption())
                    .foregroundColor(Color.textMuted)
            }

            if settings.enabled {
                // MARK: — Location
                Section {
                    HStack {
                        Text("Folder")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("Daily", text: $settings.folderPath)
                            .font(.subheadline.monospaced())
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 200)
                            .accessibilityLabel("Daily notes folder")
                            .accessibilityHint("Vault-relative path, e.g. Daily or Journal/Daily. Leave empty for vault root.")
                    }

                    HStack {
                        Text("Filename")
                            .foregroundColor(Color.textSecondary)
                        Spacer()
                        TextField("{date}", text: $settings.filenamePattern)
                            .font(.subheadline.monospaced())
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 200)
                            .accessibilityLabel("Daily note filename pattern")
                            .accessibilityHint("Without extension. Supports {date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}")
                    }
                } header: {
                    Text("Location")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Placeholders: {date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)

                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundColor(Color.accent)
                            Text(settings.previewPath(for: Date(), healthSubfolder: healthSubfolder))
                                .font(.caption.monospaced())
                                .foregroundColor(Color.accent)
                        }
                    }
                }

                // MARK: — Options
                Section {
                    Toggle("Create note if missing", isOn: $settings.createIfMissing)
                        .tint(Color.accent)
                        .accessibilityLabel("Create daily note if it does not exist")
                        .accessibilityValue(settings.createIfMissing ? "Enabled" : "Disabled")

                    Toggle("Inject metric sections", isOn: $settings.injectMarkdownSections)
                        .tint(Color.accent)
                        .accessibilityLabel("Inject markdown sections into the note body")
                        .accessibilityValue(settings.injectMarkdownSections ? "Enabled" : "Disabled")
                } header: {
                    Text("Options")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leave \"Create note if missing\" off if you create your daily notes manually or via a template.")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)
                        Text("\"Inject metric sections\" also writes Sleep, Activity, Heart, etc. into the note body — same sections as a markdown export. App-managed sections are replaced on each export; your own headings are preserved.")
                            .font(Typography.caption())
                            .foregroundColor(Color.textMuted)
                    }
                }

                // MARK: — Which metrics
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Metrics to Inject")
                                .font(Typography.body())
                            Text("\(enabledMetricCount) metric\(enabledMetricCount == 1 ? "" : "s") enabled")
                                .font(Typography.caption())
                                .foregroundColor(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(enabledMetricCount > 0 ? Color.accent : Color.textMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Metrics to inject: \(enabledMetricCount) enabled")
                } header: {
                    Text("Metrics")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("The metrics injected into your daily note match exactly what you've enabled in Export Settings → Health Metrics. Change your metric selection there to control what gets injected.")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }

                // MARK: — Preview
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Frontmatter Preview")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(Color.textSecondary)

                        Text(frontmatterPreview)
                            .font(.caption.monospaced())
                            .foregroundColor(Color.textPrimary)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Frontmatter preview: \(frontmatterPreview)")
                } header: {
                    Text("Preview")
                        .font(Typography.caption())
                        .foregroundColor(Color.textSecondary)
                } footer: {
                    Text("Sample values shown. Existing frontmatter properties you've written manually are always preserved.")
                        .font(Typography.caption())
                        .foregroundColor(Color.textMuted)
                }
            }
        }
        .navigationTitle("Daily Note Injection")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Computed helpers

    private var enabledMetricCount: Int {
        metricSelection.totalEnabledCount
    }

    private var frontmatterPreview: String {
        guard enabledMetricCount > 0 else { return "(no metrics enabled)" }

        let sampleValues: [String: String] = [
            "sleep_total_hours": "7.50",
            "sleep_deep_hours": "1.75",
            "sleep_rem_hours": "1.92",
            "steps": "8432",
            "active_calories": "420",
            "exercise_minutes": "45",
            "resting_heart_rate": "58",
            "hrv_ms": "52.3",
            "weight_kg": "72.4",
            "dietary_calories": "2100",
            "mindful_minutes": "20",
            "blood_oxygen": "98",
            "respiratory_rate": "14.2",
        ]

        let enabledKeys = DailyNoteInjector.frontmatterKeys(enabledIn: metricSelection)
        let previewKeys = Array(enabledKeys.prefix(8))

        var lines = ["---"]
        for key in previewKeys {
            let value = sampleValues[key] ?? "…"
            lines.append("\(key): \(value)")
        }
        if enabledKeys.count > 8 {
            lines.append("# … \(enabledKeys.count - 8) more")
        }
        lines.append("---")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DailyNoteInjectionView(
            settings: DailyNoteInjectionSettings(),
            metricSelection: MetricSelectionState()
        )
    }
}

#endif // os(iOS)
