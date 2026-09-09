#if os(iOS)
import SwiftUI

/// Reading-width driven reflow. The first candidate asks for complete labels,
/// not their compressed widths; the fallback gives each child the whole row.
struct SchedulingAdaptiveStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.s2) { content() }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: Spacing.s2) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SchedulingChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

/// Segmented-style native buttons when every label fits; otherwise a native
/// menu with the complete current value. No UIKit segmented-label compression.
struct SchedulingChoicePicker<Value: Hashable>: View {
    let title: String
    let choices: [SchedulingChoice<Value>]
    @Binding var selection: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s1) {
                ForEach(choices) { choice in
                    Button {
                        if selection != choice.value { selection = choice.value }
                    } label: {
                        Text(LocalizedStringKey(choice.title))
                            .font(Typography.bodyEmphasis())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Spacing.s3)
                            .padding(.vertical, Spacing.s2)
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundStyle(Color.textPrimary)
                            .background(selection == choice.value ? Color.selectedBackground : Color.bgSecondary,
                                        in: RoundedRectangle(cornerRadius: GeistRadius.sm))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selection == choice.value ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selection == choice.value ? .isSelected : [])
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(LocalizedStringKey(title))

            SchedulingValueMenu(
                title: title, choices: choices,
                selection: Binding(get: { selection }, set: { if selection != $0 { selection = $0 } })
            )
        }
    }
}

struct SchedulingMenuLabel: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(LocalizedStringKey(title))
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s2) {
                Text(LocalizedStringKey(value))
                    .font(monospaced ? Typography.monoEmphasis() : Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.s2)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: GeistRadius.sm).strokeBorder(Color.borderSubtle, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct SchedulingValueMenu<Value: Hashable>: View {
    let title: String
    let choices: [SchedulingChoice<Value>]
    @Binding var selection: Value
    var selectedTitle: String? = nil
    var monospaced = false

    private var value: String { selectedTitle ?? choices.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        A11ySelectionMenu(
            selection: selection,
            options: choices.map(\.value),
            optionLabel: { option in Text(LocalizedStringKey(choices.first { $0.value == option }?.title ?? "")) },
            // Unlike a Picker, the legacy time/unit menus also dispatch when
            // the current option is tapped. Keep that exact callback path.
            onSelect: { selection = $0 }
        ) {
            SchedulingMenuLabel(title: title, value: value, monospaced: monospaced)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStringKey(title))
        .accessibilityValue(Text(LocalizedStringKey(value)))
    }
}

/// Bounds and persistence are supplied by the caller. Each native Button owns
/// its entire 44pt label; decoration outside a Stepper is not a hit-target fix.
struct SchedulingNumberControl: View {
    let title: String
    @Binding var value: Int
    let bounds: ClosedRange<Int>
    let identifier: String
    var valueDescription: String? = nil

    var body: some View {
        SchedulingAdaptiveStack {
            Text(LocalizedStringKey(valueDescription ?? title))
                .font(Typography.body())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            SchedulingAdaptiveStack {
                Button {
                    if value > bounds.lowerBound { value -= 1 }
                } label: {
                    numberActionLabel("minus")
                }
                .disabled(value <= bounds.lowerBound)
                .accessibilityLabel(Text("Decrease \(title)"))
                .accessibilityValue("\(value)")
                .accessibilityIdentifier(identifier + ".decrement")

                Text("\(value)")
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize()
                    .accessibilityLabel(LocalizedStringKey(title))
                    .accessibilityIdentifier(identifier + ".value")
                    .accessibilityValue("\(value)")

                Button {
                    if value < bounds.upperBound { value += 1 }
                } label: {
                    numberActionLabel("plus")
                }
                .disabled(value >= bounds.upperBound)
                .accessibilityLabel(Text("Increase \(title)"))
                .accessibilityValue("\(value)")
                .accessibilityIdentifier(identifier + ".increment")
            }
            .buttonStyle(.plain)
            .buttonRepeatBehavior(.enabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func numberActionLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(Color.textPrimary)
            .padding(Spacing.s2)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: GeistRadius.sm).strokeBorder(Color.borderSubtle, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// The legacy screen retains its 12↔24-hour conversion. These are three
/// independent native menus, never one combined accessibility action.
struct SchedulingTimeControls: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var period: String
    let hourIdentifier: String
    let minuteIdentifier: String
    let periodIdentifier: String

    var body: some View {
        SchedulingAdaptiveStack {
            SchedulingValueMenu(
                title: "Hour", choices: (1...12).map { SchedulingChoice(value: $0, title: String(format: "%d", $0)) },
                selection: $hour, monospaced: true
            )
            .accessibilityIdentifier(hourIdentifier)
            .accessibilityHint("Double tap to select hour")
            SchedulingValueMenu(
                title: "Minute", choices: stride(from: 0, to: 60, by: 5).map { SchedulingChoice(value: $0, title: String(format: "%02d", $0)) },
                selection: $minute, selectedTitle: String(format: "%02d", minute), monospaced: true
            )
            .accessibilityIdentifier(minuteIdentifier)
            .accessibilityHint("Double tap to select minute")
            SchedulingValueMenu(
                title: "Period", choices: ["AM", "PM"].map { SchedulingChoice(value: $0, title: $0) },
                selection: $period, monospaced: true
            )
            .accessibilityIdentifier(periodIdentifier)
            .accessibilityHint("Double tap to switch between AM and PM")
        }
        .accessibilityElement(children: .contain)
    }
}

struct SchedulingInfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(Spacing.s2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("schedule.todayRefresh.info")
        .accessibilityLabel("About Today Refresh")
        .accessibilityHint("Explains how the refresh interval is scheduled")
    }
}

/// This callback clears immediately on Apple. Protection/deletion still lives
/// in ScheduleSettingsView; this component must not introduce a confirmation.
struct SchedulingHistoryHeading: View {
    let showsClear: Bool
    let onClear: () -> Void

    var body: some View {
        SchedulingAdaptiveStack {
            Text("Export History")
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if showsClear {
                Button(action: onClear) {
                    Text("Clear History")
                        .font(Typography.label())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s2)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Color.bgPrimary, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear export history")
                .accessibilityIdentifier("schedule.history.clear")
            }
        }
    }
}

/// Only Edit and Enable exist in Apple's Schedule card. Delete remains the
/// separate guarded/confirmed management action in ExportProfilesView.
struct SchedulingProfileRow: View {
    let name: String
    let summary: String
    @Binding var isEnabled: Bool
    let identifier: String
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(name)
                .font(Typography.body())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier + ".name")
            Text(summary)
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier + ".summary")
            Button(action: onEdit) {
                Label("Edit Schedule", systemImage: "pencil")
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.s2)
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit schedule for \(name)"))
            .accessibilityIdentifier(identifier + ".edit")
            Toggle(isOn: $isEnabled) {
                Text("Enabled")
                    .font(Typography.body())
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .toggleStyle(A11ySwitchToggleStyle())
            .tint(Color.accent)
            .accessibilityLabel(Text("Schedule \(name)"))
            .accessibilityIdentifier(identifier + ".enabled")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Read-only profile facts have their own width; no icon or disclosure gutter
/// can truncate a profile name, destination, cadence or formats summary.
struct SchedulingProfileSummary: View {
    let name: String
    let destination: String
    let cadence: String
    let formats: String
    let isActive: Bool
    let cadenceColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            if isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accent.opacity(0.14)))
            }
            Text(destination).font(.footnote).foregroundStyle(Color.textSecondary)
            Text(cadence).font(.footnote).foregroundStyle(cadenceColor)
            Text(formats).font(.caption).foregroundStyle(Color.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SchedulingProfileFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(title).font(.footnote).foregroundStyle(Color.textSecondary)
            Text(value.isEmpty ? "—" : value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textPrimary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The screen retains the guard, confirmation, last-profile refusal and action
/// ordering. Only the button's growing, named target is shared with probes.
struct SchedulingProfileManagementAction: View {
    let icon: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isDestructive ? Color.errorText : Color.textPrimary)
            .padding(.vertical, Spacing.s2)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SchedulingDatePreset<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let hint: String
    let identifier: String
    var id: Value { value }
}

struct SchedulingDatePresets<Value: Hashable>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let options: [SchedulingDatePreset<Value>]
    let selection: Value
    let onSelect: (Value) -> Void

    private var usesExpandedLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    var body: some View {
        Group {
            if usesExpandedLayout {
                // Each pair measures its complete labels at the current locale/size.
                // Width-only constraints trigger exactly the same one-column fallback.
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(Array(stride(from: 0, to: options.count, by: 2)), id: \.self) { index in
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Spacing.s2) {
                                expandedPresetButton(options[index])
                                if index + 1 < options.count { expandedPresetButton(options[index + 1]) }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            VStack(spacing: Spacing.s2) {
                                expandedPresetButton(options[index])
                                if index + 1 < options.count { expandedPresetButton(options[index + 1]) }
                            }
                        }
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 0
                ) {
                    ForEach(options) { option in
                        compactPresetButton(option)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactPresetButton(_ option: SchedulingDatePreset<Value>) -> some View {
        let selected = selection == option.value
        return Button { onSelect(option.value) } label: {
            HStack(spacing: Spacing.s1) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.headline())
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(option.title))
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.accent : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, Spacing.s2)
            .background(selected ? Color.accent.opacity(0.18) : Color.bgSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accent.opacity(0.45) : Color.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .modifier(SchedulingDatePresetAccessibility(option: option, selected: selected))
    }

    private func expandedPresetButton(_ option: SchedulingDatePreset<Value>) -> some View {
        let selected = selection == option.value
        return Button { onSelect(option.value) } label: {
            HStack(spacing: Spacing.s1) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.headline())
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(option.title))
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(Spacing.s2)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background(selected ? Color.accent.opacity(0.18) : Color.bgSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accent.opacity(0.45) : Color.borderSubtle, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SchedulingDatePresetAccessibility(option: option, selected: selected))
    }
}

private struct SchedulingDatePresetAccessibility<Value: Hashable>: ViewModifier {
    let option: SchedulingDatePreset<Value>
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(option.identifier)
            .accessibilityLabel(LocalizedStringKey(option.title))
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityHint(LocalizedStringKey(option.hint))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Standard sizes retain the native compact date/time presentation. At XXXL
/// and accessibility sizes, full readback labels sit above native wheels so
/// every value can grow while preserving the caller's binding and bounds.
struct SchedulingLabeledControl<Control: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var value: Text? = nil
    @ViewBuilder var control: () -> Control

    private var usesExpandedLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    @ViewBuilder
    var body: some View {
        if usesExpandedLayout {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(LocalizedStringKey(title))
                    .font(Typography.body())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let value {
                    value
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Native date wheels have a non-compressible intrinsic width.
                // Horizontal scrolling keeps every column reachable in narrow
                // windows; the complete current value above remains wrapping copy.
                ScrollView(.horizontal) {
                    control()
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(minHeight: 44, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Keep the native compact presentation used by the standard UI.
            // The containing row is still allocated a 44pt interaction height.
            control()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}

struct SchedulingExportActions: View {
    let previewIdentifier: String
    let exportIdentifier: String
    let previewHint: String
    let exportHint: String
    let onPreview: () -> Void
    let onExport: () -> Void

    var body: some View {
        SchedulingAdaptiveStack {
            Button(action: onPreview) {
                actionLabel("Preview", icon: "eye", primary: false)
            }
            .accessibilityIdentifier(previewIdentifier)
            .accessibilityLabel("Preview Export")
            .accessibilityHint(Text(previewHint))
            Button(action: onExport) {
                actionLabel("Export Data", icon: "arrow.up", primary: true)
            }
            .accessibilityIdentifier(exportIdentifier)
            .accessibilityLabel("Export Health Data")
            .accessibilityHint(Text(exportHint))
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: LocalizedStringKey, icon: String, primary: Bool) -> some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(primary ? Color.bgPrimary : Color.textPrimary)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, 12)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
        .background(primary ? Color.textPrimary : Color.bgSecondary,
                    in: RoundedRectangle(cornerRadius: GeistRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: GeistRadius.sm)
            .strokeBorder(primary ? Color.textPrimary.opacity(0.08) : Color.borderSubtle, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct SchedulingExportFooter<Actions: View>: View {
    let freeExportsRemaining: Int?
    let freeExportsIdentifier: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Spacing.s2) {
            if let remaining = freeExportsRemaining {
                Text(remaining == 1 ? "1 free export remaining" : "\(remaining) free exports remaining")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(freeExportsIdentifier)
                    .accessibilityLabel("\(remaining) free export\(remaining == 1 ? "" : "s") remaining before purchase required")
            }
            actions()
        }
        .padding(Spacing.s2)
        .background(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous).fill(Color.bgPrimary))
        .overlay(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous).strokeBorder(Color.borderSubtle, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.s3)
        .padding(.bottom, Spacing.s2)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.bgPrimary.opacity(0), Color.bgPrimary], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

private struct SchedulingFooterHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Keep the native measured safe-area inset when there is reading room. In a
/// short window (including large text at normal width), move the same footer
/// into the single scroll surface rather than pinning away most of its height.
struct SchedulingExportScroll<Content: View, Footer: View>: View {
    let showsFooter: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let scrollsFooter = footerHeight > geometry.size.height * 0.4
            ScrollView {
                VStack(spacing: 0) {
                    content()
                    if showsFooter && scrollsFooter { measuredFooter }
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsFooter && !scrollsFooter { measuredFooter }
            }
        }
        .onPreferenceChange(SchedulingFooterHeight.self) { footerHeight = $0 }
    }

    private var measuredFooter: some View {
        footer()
            .background(GeometryReader { geometry in
                Color.clear.preference(key: SchedulingFooterHeight.self, value: geometry.size.height)
            })
    }
}
#endif
