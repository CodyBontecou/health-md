import SwiftUI

/// Separate test application. No HealthKit, production stores, billing,
/// destinations, pairing, analytics, scheduling or Health.md app bootstrap.
/// The real configuration guard uses only a uniquely named synthetic defaults suite.
@main
struct A11ySyntheticApp: App {
    var body: some Scene {
        WindowGroup {
            A11yScenarioContainer { scenario }
        }
    }

    @ViewBuilder private var scenario: some View {
        switch ProcessInfo.processInfo.environment["A11Y_SCENARIO"] ?? "foundation" {
        case "foundation": A11yFoundationScenario()
        case "dialogs": DialogsA11yScenario()
        case "format": FormatA11yScenario()
        case "reading": ReadingA11yScenario()
        case "scheduling": SchedulingA11yScenario()
        case "onboarding": OnboardingA11yScenario()
        default: Text("Unknown accessibility scenario").accessibilityIdentifier("a11y.unknown-scenario")
        }
    }
}

/// Environment/viewport only, never a replacement for production controls.
struct A11yScenarioContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var viewport = CGRect.zero
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var size: DynamicTypeSize {
        switch environment["A11Y_SIZE"] {
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility5": return .accessibility5
        default: return .large
        }
    }
    private var theme: ColorScheme { environment["A11Y_THEME"] == "dark" ? .dark : .light }

    var body: some View {
        GeometryReader { geometry in
            content()
                .frame(width: min(CGFloat(Double(environment["A11Y_WIDTH"] ?? "") ?? Double(geometry.size.width)), geometry.size.width),
                       height: min(CGFloat(Double(environment["A11Y_HEIGHT"] ?? "") ?? Double(geometry.size.height)), geometry.size.height))
                .background {
                    GeometryReader { allocated in
                        Color.clear.preference(key: A11yViewportPreference.self, value: allocated.frame(in: .global))
                    }
                }
                .onPreferenceChange(A11yViewportPreference.self) { viewport = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("a11y.scenario.viewport")
                .accessibilityValue(Text(verbatim: "\(viewport.minX),\(viewport.minY),\(viewport.width),\(viewport.height)"))
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: environment["A11Y_LOCALE"] ?? "en_US"))
                .environment(\.layoutDirection, (environment["A11Y_LOCALE"] ?? "").hasPrefix("ar") ? .rightToLeft : .leftToRight)
                .preferredColorScheme(theme)
                // Match the shipping iOS root's native button environment
                // (HealthMdApp.swift), rather than the OS's default capsule.
                .buttonBorderShape(.roundedRectangle(radius: GeistRadius.sm))
        }
    }
}

private struct A11yViewportPreference: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 { value = next }
    }
}

struct A11yFoundationScenario: View {
    @State private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Callbacks: \(count)")
                .accessibilityIdentifier("a11y.callback-count")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Read health notes").font(Typography.heading24())
                        .accessibilityIdentifier("a11y.heading")
                    Text("Full explanations remain readable at your chosen text size.")
                        .font(Typography.body()).fixedSize(horizontal: false, vertical: true)
                    SecondaryButton("Choose a different destination folder", icon: "folder") { count += 1 }
                        .accessibilityIdentifier("a11y.secondary")
                    DestructiveButton(title: "Remove the selected destination", action: { count += 10 })
                        .accessibilityIdentifier("a11y.destructive")
                    PrimaryButton("Create My First Export", icon: "arrow.right") { count += 100 }
                        .accessibilityIdentifier("a11y.primary")
                    PrimaryButton("Disabled export", icon: "arrow.right", isDisabled: true) { count += 1000 }
                        .accessibilityIdentifier("a11y.disabled")
                    PrimaryButton("Loading export", icon: "arrow.right", isLoading: true) { count += 1000 }
                        .accessibilityIdentifier("a11y.loading")
                    IconButton(icon: "xmark", accessibilityLabel: "Close synthetic example") { count += 10000 }
                        .accessibilityIdentifier("a11y.icon")
                    StatusPill(status: .connected)
                    StatusPill(status: .disconnected)
                    StatusPill(status: .pending)
                    ExportStatusBadge(status: .success("Your synthetic archive is ready to inspect. This is a complete status explanation."), onDismiss: { count += 100000 }, exportFileName: "synthetic-archive-with-a-complete-readable-file-name.md", onPreview: { count += 1000000 }, onBrowseFolder: { count += 10000000 })
                }
                .frame(maxWidth: 320, alignment: .leading)
                .padding(16)
            }
        }
        .font(.body)
        .foregroundStyle(Color.textPrimary)
        .background(Color.bgPrimary)
    }
}
