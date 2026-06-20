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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                enableCard

                if settings.enabled {
                    configurationCard
                } else {
                    disabledStateCard
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Daily Note Injection")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HealthMdPageHeader(
            title: "Merge Health Data Into Existing Notes",
            subtitle: "Write selected metrics into daily note frontmatter, with optional Markdown sections for the note body."
        ) {
            HStack(spacing: Spacing.sm) {
                Text("Daily Notes")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textMuted)

                DailyNoteStatePill(
                    title: settings.enabled ? "Enabled" : "Disabled",
                    color: settings.enabled ? Color.accent : Color.textMuted
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily Note Injection, \(settings.enabled ? "enabled" : "disabled")")
        }
    }

    // MARK: - Enablement

    private var enableCard: some View {
        card {
            Toggle(isOn: $settings.enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inject Into Daily Notes")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Exports update YAML frontmatter in the daily notes you already keep, while normal export files still follow your selected formats.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.accent)
            .accessibilityLabel("Inject health metrics into daily notes")
            .accessibilityValue(settings.enabled ? "Enabled" : "Disabled")
            .accessibilityHint("Double tap to \(settings.enabled ? "disable" : "enable") daily note injection")
        }
    }

    private var disabledStateCard: some View {
        calloutCard(
            icon: "pause.circle",
            title: "Daily Notes Disabled",
            message: "Turn on Daily Note Injection to merge selected metrics into the daily notes you already keep in Obsidian.",
            color: Color.textMuted
        )
    }

    // MARK: - Configuration

    private var configurationCard: some View {
        sectionGroup(title: "Daily Note Settings") {
            VStack(spacing: 0) {
                textFieldRow(
                    title: "Folder",
                    placeholder: "Daily",
                    text: $settings.folderPath,
                    helper: "Vault-relative folder. Leave empty for the vault root.",
                    accessibilityLabel: "Daily notes folder",
                    accessibilityHint: "Enter a vault-relative path, such as Daily or Journal slash Daily. Leave empty for the vault root."
                )

                rowDivider

                textFieldRow(
                    title: "Filename Pattern",
                    placeholder: "{date}",
                    text: $settings.filenamePattern,
                    helper: "Supports {date}, {year}, {month}, {day}, {weekday}, {monthName}, and {quarter}.",
                    accessibilityLabel: "Daily note filename pattern",
                    accessibilityHint: "Enter the filename pattern without an extension."
                )

                if !healthSubfolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        rowDivider
                        infoRow(
                            icon: "folder.badge.questionmark",
                            title: "Vault Root Location",
                            message: "With Folder set to Daily, notes are written to Daily/… at the vault root, not \(healthSubfolder)/Daily/…."
                        )
                    }
                }

                rowDivider

                toggleRow(
                    title: "Create Note If Missing",
                    subtitle: "Leave off if another plugin or template creates daily notes for you.",
                    isOn: $settings.createIfMissing,
                    accessibilityLabel: "Create daily note if missing"
                )

                rowDivider

                toggleRow(
                    title: "Inject Metric Sections",
                    subtitle: "Also writes Sleep, Activity, Heart, and other metric sections into the note body. App-managed sections are replaced on each export.",
                    isOn: $settings.injectMarkdownSections,
                    accessibilityLabel: "Inject metric sections into the note body"
                )

                rowDivider

                metricsRow

                rowDivider

                previewPathRow
            }
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: enabledMetricCount > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(enabledMetricCount > 0 ? Color.accent : Color.warning)
                .frame(width: 32, height: 32)
                .background(Circle().fill((enabledMetricCount > 0 ? Color.accent : Color.warning).opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Metrics To Inject")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Uses the same metric selection configured in Export Settings → Health Metrics.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            DailyNoteStatePill(
                title: enabledMetricCount == 0 ? "No Metrics" : "\(enabledMetricCount) Metric\(enabledMetricCount == 1 ? "" : "s")",
                color: enabledMetricCount > 0 ? Color.accent : Color.warning
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Metrics to inject")
        .accessibilityValue(enabledMetricCount == 0 ? "No metrics enabled" : "\(enabledMetricCount) metrics enabled")
        .accessibilityHint("Change selected metrics from Export Settings, Health Metrics")
    }

    private var previewPathRow: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "doc.text")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accent.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Preview Path")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(settings.previewPath(for: Date()))
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.accent)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily note preview path")
        .accessibilityValue(settings.previewPath(for: Date()))
    }

    // MARK: - Row Helpers

    @ViewBuilder
    private func textFieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        helper: String,
        accessibilityLabel: String,
        accessibilityHint: String
    ) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                fieldLabel(title: title, helper: helper)
                fieldTextField(placeholder: placeholder, text: text, accessibilityLabel: accessibilityLabel, accessibilityHint: accessibilityHint)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                fieldLabel(title: title, helper: helper)
                Spacer(minLength: Spacing.md)
                fieldTextField(placeholder: placeholder, text: text, accessibilityLabel: accessibilityLabel, accessibilityHint: accessibilityHint)
                    .frame(maxWidth: 220)
            }
        }
    }

    private func fieldLabel(title: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text(helper)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldTextField(
        placeholder: String,
        text: Binding<String>,
        accessibilityLabel: String,
        accessibilityHint: String
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.footnote.monospaced())
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(usesAccessibilityLayout ? .leading : .trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.accent)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn.wrappedValue ? "Enabled" : "Disabled")
    }

    private func infoRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Card Helpers

    private func sectionGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel(title)
            card(content: content)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private func calloutCard(icon: String, title: String, message: String, color: Color) -> some View {
        card {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(color.opacity(0.12)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
            .padding(.vertical, Spacing.md)
    }

    // MARK: - Computed helpers

    private var enabledMetricCount: Int {
        metricSelection.totalEnabledCount
    }
}

private struct DailyNoteStatePill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
            .accessibilityHidden(true)
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
