#if os(iOS)
import SwiftUI

/// Synthetic state around the exact production UI pieces, not the protected screens.
/// Register `format` -> FormatA11yScenario centrally. No defaults/model/renderer/service.
struct FormatA11yScenario: View {
    @State private var date = "ISO 8601 (2026-01-13)"
    @State private var time = "24-hour (14:30)"
    @State private var unit = "Metric"
    @State private var selectionCalls = 0
    @State private var emoji = false
    @State private var toggleCalls = 0

    var body: some View {
        NavigationStack {
            FormatPageScroll { _ in
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text(verbatim: "Selections: \(selectionCalls); Toggles: \(toggleCalls)")
                        .accessibilityIdentifier("a11y.format.events")
                    FormatSectionCard(title: "Date, Time, and Units",
                                      subtitle: "These choices affect display values in exported files.") {
                        FormatSelectionControl(
                            title: "Date Format", subtitle: "Preview: 2026-01-13", selection: date,
                            options: ["ISO 8601 (2026-01-13)", "US Short (01/13/2026)", "US Long (January 13, 2026)",
                                      "EU Short (13/01/2026)", "EU Long (13 January 2026)", "Compact (20260113)",
                                      "Friendly (Mon, Jan 13, 2026)"],
                            optionTitle: { $0 }
                        ) { date = $0; selectionCalls += 1 }
                        FormatDivider()
                        FormatSelectionControl(
                            title: "Time Format", subtitle: "Preview: 14:30", selection: time,
                            options: ["24-hour (14:30)", "24-hour with seconds (14:30:45)",
                                      "12-hour (2:30 PM)", "12-hour with seconds (2:30:45 PM)"],
                            optionTitle: { $0 }
                        ) { time = $0; selectionCalls += 1 }
                        FormatDivider()
                        FormatSelectionControl(
                            title: "Unit System", subtitle: "Kilometers, kilograms, Celsius", selection: unit,
                            options: ["Metric", "Imperial"], optionTitle: { $0 }
                        ) { unit = $0; selectionCalls += 1 }
                        FormatDivider()
                        FormatToggleControl(
                            title: "Use Emoji in Headers", subtitle: "Adds category emoji to Markdown headings.",
                            isOn: Binding(get: { emoji }, set: { emoji = $0; toggleCalls += 1 }),
                            accessibilityLabel: "Use emoji in section headers"
                        )
                    }
                    NavigationLink {
                        FormatFrontmatterScenarioContent()
                    } label: {
                        FormatNavigationRow(icon: "number.square", title: "Frontmatter Fields",
                                            subtitle: "Synthetic metadata only", status: "Schema-Safe")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("a11y.format.frontmatter")
                    NavigationLink {
                        FormatTemplateScenarioContent()
                    } label: {
                        FormatNavigationRow(icon: "doc.plaintext", title: "Markdown Template",
                                            subtitle: "Synthetic template only", status: "Custom")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("a11y.format.template")
                }
            }
            .navigationTitle("Format Components")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FormatFrontmatterScenarioContent: View {
    private let original = "synthetic_original_output_key_with_a_long_unbroken_identifier"
    private let renamed = "synthetic_renamed_output_key_preserved_without_truncation"
    private let customKey = "synthetic_custom_metadata_key_for_accessibility"
    private let customValue = "Synthetic metadata only: this complete value stays readable at the chosen text and display size."
    private let placeholderKey = "synthetic_placeholder_key_for_manual_review"
    @State private var enabled = true
    @State private var customExists = true
    @State private var placeholderExists = true
    @State private var toggleCalls = 0
    @State private var renameCalls = 0
    @State private var deleteCalls = 0
    @State private var addCalls = 0
    @State private var dateKey = ""
    @State private var typeKey = "synthetic_type"
    @State private var typeValue = "  synthetic_long_type_value_preserved_with_its_original_spaces_and_identifier  "

    var body: some View {
        FormatPageScroll { _ in
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(verbatim: "Toggle: \(toggleCalls); Rename: \(renameCalls); Delete: \(deleteCalls); Add: \(addCalls)")
                    .accessibilityIdentifier("a11y.format.frontmatter.events")
                FormatSectionCard(title: "Health Metric Fields") {
                    FormatFrontmatterFieldContent(
                        originalKey: original, customKey: renamed,
                        isEnabled: Binding(get: { enabled }, set: { enabled = $0; toggleCalls += 1 })
                    ) {
                        FormatInlineButton(title: "Rename Field", systemImage: "pencil") { renameCalls += 1 }
                            .accessibilityLabel("Rename \(original)")
                            .accessibilityHint("Double tap to enter a custom name for this field")
                            .accessibilityIdentifier("a11y.format.rename")
                    }
                }
                FormatSectionCard(title: "Custom Static Fields", subtitle: "Fixed values added to every export, like tags or author.") {
                    if customExists {
                        FormatFrontmatterEntry(key: customKey, value: customValue, deleteLabel: "Delete custom field \(customKey)") {
                            customExists = false
                            deleteCalls += 1
                        }
                    }
                    // Counters prove invocation only, not dialog fields or live protection.
                    FormatInlineButton(title: "Add Custom Field", systemImage: "plus.circle") { addCalls += 1 }
                        .accessibilityIdentifier("a11y.format.add-custom")
                }
                FormatSectionCard(title: "Placeholder Fields", subtitle: "Empty fields for values you fill in manually after export.") {
                    if placeholderExists {
                        FormatFrontmatterEntry(key: placeholderKey, value: "Empty on export", deleteLabel: "Delete placeholder field \(placeholderKey)") {
                            placeholderExists = false
                            deleteCalls += 1
                        }
                    }
                    FormatInlineButton(title: "Add Placeholder Field", systemImage: "plus.circle") { addCalls += 1 }
                        .accessibilityIdentifier("a11y.format.add-placeholder")
                }
                FormatSectionCard(title: "Core Metadata") {
                    FormatTextFieldControl(title: "Date Field Name", placeholder: "date", text: $dateKey,
                                           defaultValue: "date", accessibilityLabel: "Date field name")
                    FormatTextFieldControl(title: "Type Field Name", placeholder: "type", text: $typeKey,
                                           defaultValue: "type", accessibilityLabel: "Type field name")
                    FormatTextFieldControl(title: "Type Field Value", placeholder: "health-data", text: $typeValue,
                                           defaultValue: "health-data", accessibilityLabel: "Type field value")
                }
            }
        }
        .navigationTitle("Frontmatter Fields")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FormatTemplateScenarioContent: View {
    @State private var template = "# Synthetic {{date}}\n{{metrics}}\n"
    @State private var templateWrites = 0

    var body: some View {
        FormatPageScroll { height in
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FormatTemplateEditor(text: Binding(get: { template }, set: {
                    template = $0
                    templateWrites += 1
                }), availableHeight: height)
                FormatSectionCard(title: "Synthetic Bound Text", subtitle: "Raw editing evidence, not a renderer preview.") {
                    FormatCodeBlock(text: template)
                        .accessibilityIdentifier("a11y.format.template.echo")
                    Text(verbatim: "writes:\(templateWrites)")
                        .accessibilityIdentifier("a11y.format.template.writes")
                }
            }
        }
        .navigationTitle("Markdown Template")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
