import SwiftUI

/// Separate test application. It does not link HealthKit, stores, billing,
/// destinations, pairing, analytics, scheduling or the Health.md app bootstrap.
@main
struct A11ySyntheticApp: App {
    var body: some Scene {
        WindowGroup {
            A11yScenarioContainer { A11yFoundationScenario() }
        }
    }
}

/// Environment/viewport only, never a replacement for production controls.
/// Lanes provide their own named scenario; central integration registers routing.
struct A11yScenarioContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
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
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: environment["A11Y_LOCALE"] ?? "en_US"))
                .environment(\.layoutDirection, (environment["A11Y_LOCALE"] ?? "").hasPrefix("ar") ? .rightToLeft : .leftToRight)
                .preferredColorScheme(theme)
        }
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
