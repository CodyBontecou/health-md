#if os(iOS)
import SwiftUI

/// Actual production rows/editing layouts, with synthetic values and callbacks.
/// Protection uses the real manager in an isolated defaults suite. There is no
/// HealthKit, transport, folder, billing, analytics or shipping-app bootstrap.
struct ReadingA11yScenario: View {
    @Environment(\.locale) private var locale
    @StateObject private var protection: ConfigurationProtectionManager
    @State private var suite: String

    @State private var expanded = true
    @State private var selected = false
    @State private var metricCalls = 0
    @State private var metricAttempts = 0
    @State private var expansionCalls = 0
    @State private var settingCalls = 0
    @State private var protectionCalls = 0
    @State private var blockedCalls = 0
    @State private var connectCalls = 0
    @State private var disconnectCalls = 0
    @State private var host = "synthetic-mac-with-a-long-name.example.invalid"
    @State private var port = "65535"
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case host, port }

    init() {
        let suite = "org.healthmd.a11y.reading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        _suite = State(initialValue: suite)
        _protection = StateObject(wrappedValue: ConfigurationProtectionManager(userDefaults: defaults))
    }

    // Synthetic translations stress reading width/RTL; these are NOT catalog translations.
    private var metricName: String {
        switch locale.language.languageCode?.identifier {
        case "de": return "Herzfrequenzvariabilität beim Gehen"
        case "ar": return "تباين معدل ضربات القلب أثناء المشي"
        case "ja": return "歩行中の心拍変動と心肺機能の測定"
        default: return "Heart Rate Variability During Walking"
        }
    }

    private var categoryName: String {
        switch locale.language.languageCode?.identifier {
        case "de": return "Herzgesundheit und Beweglichkeit"
        case "ar": return "صحة القلب والقدرة على الحركة"
        case "ja": return "心臓の健康と歩行の安定性"
        default: return "Heart Health and Walking Stability"
        }
    }

    private var categorySubtitle: String {
        switch locale.language.languageCode?.identifier {
        case "de": return "Separate Apple-Berechtigung erforderlich"
        case "ar": return "يتطلب إذناً منفصلاً من Apple"
        case "ja": return "Appleの個別のアクセス許可が必要です"
        default: return "Separate Apple permission required"
        }
    }

    private var settingsDescription: String {
        "Analytics never includes health values, metric names, health dates, exported files, paths, peer names, or credentials. It is not used for advertising or cross-app tracking."
    }

    var body: some View {
        TabView {
            metrics
                .tabItem { Label("Metrics", systemImage: "heart") }
            settings
                .tabItem { Label("Settings", systemImage: "gearshape") }
            connection
                .tabItem { Label("Connection", systemImage: "network") }
        }
        .environmentObject(protection)
        .onChange(of: protection.blockedChangeToastID) { _, value in
            if value != nil { blockedCalls += 1 }
        }
        .onDisappear {
            protection.dismissBlockedChangeToast()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private var metrics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                receipt("reading.metric-calls", metricCalls)
                receipt("reading.metric-attempts", metricAttempts)
                receipt("reading.expansion-calls", expansionCalls)
                ReadingMetricCategoryHeader(
                    title: categoryName,
                    subtitle: categorySubtitle,
                    icon: "heart",
                    isExpanded: expanded,
                    accessibilityLabel: categoryName,
                    onExpand: { expanded.toggle(); expansionCalls += 1 }
                ) {
                    ReadingMetricCategoryStatus(label: selected ? "Enabled" : "Off", icon: selected ? "checkmark" : "circle", tint: selected ? .success : .textMuted, textColor: selected ? .successText : .textSecondary)
                }
                .accessibilityIdentifier("reading.category")
                if expanded {
                    ReadingMetricToggle(
                        name: metricName,
                        detail: "SDNN · ms",
                        isOn: Binding(get: { selected }, set: { value in
                            metricAttempts += 1
                            protection.performConfigurationChange { selected = value; metricCalls += 1 }
                        }),
                        accessibilityHint: "Synthetic metric selection"
                    )
                    .accessibilityIdentifier("reading.metric")
                    ReadingMetricToggle(
                        name: "Unavailable synthetic metric",
                        detail: "Requires a newer operating system",
                        isOn: Binding(get: { false }, set: { _ in metricAttempts += 100 }),
                        isUnavailable: true,
                        accessibilityHint: "Requires a newer operating system"
                    )
                    .accessibilityIdentifier("reading.metric.unavailable")
                }
            }
            .padding(Spacing.s4)
        }
        .background(Color.bgPrimary)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                receipt("reading.setting-calls", settingCalls)
                receipt("reading.protection-calls", protectionCalls)
                receipt("reading.blocked-calls", blockedCalls)
                Text("Keep your saved configuration from being changed by mistake. Manual exports and syncs remain available.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ReadingProtectionRow(
                    isEnabled: Binding(get: { protection.isEnabled }, set: { value in
                        protectionCalls += 1
                        protection.setEnabled(value)
                    }),
                    accessibilityIdentifier: "configurationProtection.toggle"
                )
                SettingsRow(icon: "hand.raised.fill", title: "Privacy Policy", subtitle: settingsDescription, isActive: true, accessibilityIdentifier: "reading.settings.action") {
                    settingCalls += 1
                }
                .configurationChangesProtected()

                // The same label used inside SettingsRow, exposed without a combined
                // button so native frame checks can inspect its full reading width.
                ReadingSettingsRowLabel(icon: "folder.fill", title: "Synthetic Settings Label", subtitle: settingsDescription, status: "A long current destination status", statusTone: .success, identifier: "reading.settings.probe")

                // Native full-width text controls distinguish actual line wrapping
                // from AX's tight glyph rectangle (which need not fill the row).
                Text(LocalizedStringKey(settingsDescription))
                    .font(Typography.caption())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reading.settings.description-reference")
                    .padding(.horizontal, Spacing.md)
                Text(protection.isEnabled ? "Configuration changes are blocked on this device." : "Configuration can be edited normally.")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reading.protection.description-reference")
                    .padding(.horizontal, Spacing.md)
            }
            .padding(Spacing.s4)
        }
        .background(Color.bgPrimary)
    }

    private var connection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                receipt("reading.connect-calls", connectCalls)
                receipt("reading.disconnect-calls", disconnectCalls)
                ReadingConnectionEntry(title: "Mac IP address or hostname", value: host, identifier: "reading.host") {
                    TextField("Mac Tailscale IP or hostname", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .host)
                }
                ReadingConnectionEntry(title: "Manual IP port", value: port, identifier: "reading.port") {
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .port)
                }
                ReadingConnectionActions(
                    primaryTitle: "Connect to the selected Mac",
                    primaryIcon: "network",
                    isEnabled: true,
                    onPrimary: { focusedField = nil; connectCalls += 1 },
                    secondaryTitle: "Disconnect from the selected Mac",
                    onSecondary: { disconnectCalls += 1 }
                )
                ReadingConnectionActions(primaryTitle: "Pairing is unavailable", primaryIcon: "link", isEnabled: false, onPrimary: { connectCalls += 100 }, identifierPrefix: "reading.connection.disabled")
            }
            .padding(Spacing.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgPrimary)
    }

    private func receipt(_ identifier: String, _ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(Typography.monoCaption())
            .accessibilityIdentifier(identifier)
    }
}
#endif
