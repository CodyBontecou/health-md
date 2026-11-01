import SwiftUI
import UIKit

// MARK: - Geist Status Pill

struct StatusPill: View {
    enum Status {
        case connected
        case disconnected
        case pending

        var color: Color {
            switch self {
            case .connected: return .success
            case .disconnected: return .textMuted
            case .pending: return .warning
            }
        }

        var textColor: Color {
            switch self {
            case .connected: return .successText
            case .disconnected, .pending: return .textSecondary
            }
        }

        var label: String {
            switch self {
            case .connected: return "Connected"
            case .disconnected: return "Not Connected"
            case .pending: return "Pending"
            }
        }
    }

    let status: Status
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Circle()
                .fill(status.color)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)

            Text(status.label)
                .font(Typography.label())
                .foregroundStyle(status.textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(status.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(status.color.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
        .accessibilityValue(status == .connected ? "Active" : "Inactive")
    }
}

// MARK: - Symbol Containers

struct PulsingHeartIcon: View {
    let isConnected: Bool
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var iconContainerSize: CGFloat = 48

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: glyphSize, weight: .medium, design: .default))
            .foregroundStyle(Color.primary)
            .frame(width: iconContainerSize, height: iconContainerSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Health connection")
            .accessibilityValue(isConnected ? "Connected" : "Not connected")
    }
}

struct VaultIcon: View {
    let isSelected: Bool
    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 20
    @ScaledMetric(relativeTo: .title2) private var iconContainerSize: CGFloat = 48

    var body: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: glyphSize, weight: .medium, design: .default))
            .foregroundStyle(Color.primary)
            .frame(width: iconContainerSize, height: iconContainerSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vault folder")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - Export Toast

/// The export result toast, styled to the Liquid Glass designs. It only uses tokens the
/// isolated accessibility host compiles, so its glass colours are mirrored here.
struct ExportStatusBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    enum StatusType {
        case success(String)
        case warning(String)
        case error(String)
    }

    let status: StatusType
    let onDismiss: () -> Void
    var exportFileName: String? = nil
    var onPreview: (() -> Void)? = nil
    var onBrowseFolder: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    /// Hosts that inspect the toast over time, such as the accessibility harness, turn this off.
    var autoDismisses = true

    @State private var isVisible = false
    @State private var offset: CGFloat = 80
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false

    private var hasExportActions: Bool {
        onPreview != nil || onBrowseFolder != nil
    }

    /// Seconds before the toast leaves on its own; nil keeps it until dismissed. A toast
    /// that opens details when tapped stays, as its owner manages its expiry.
    private var resolvedAutoDismissDelay: TimeInterval? {
        // Give VoiceOver users and UI tests the time they need; they can still dismiss.
        guard autoDismisses, onTap == nil, !voiceOverEnabled,
              !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        switch status {
        case .success: return 6
        case .warning, .error: return 10
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: statusIcon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(statusColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(statusColor.opacity(0.18)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    statusMessage

                    if hasExportActions, let exportFileName {
                        Text(exportFileName)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Self.muted)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Exported file: \(exportFileName)")
                    }
                }

                Spacer(minLength: Spacing.s2)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Self.muted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Self.surface))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -6)
                .padding(.trailing, -8)
                .accessibilityLabel("Dismiss export status")
            }

            if hasExportActions {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.s2) {
                        exportActionButtons
                    }
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        exportActionButtons
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                        .fill(Self.glass)
                )
                .accessibilityHidden(true)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Self.edge, lineWidth: 1)
                .accessibilityHidden(true)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: (reduceMotion ? 0 : offset) + dragOffset)
        .contentShape(Rectangle())
        .gesture(swipeToDismiss)
        .accessibilityAction(named: Text("Dismiss export status"), dismiss)
        .onAppear {
            withOptionalMotionAnimation(AnimationTimings.standard) {
                isVisible = true
                offset = 0
            }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        .task(id: resolvedAutoDismissDelay) {
            guard let delay = resolvedAutoDismissDelay else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Swipe down (or sideways) to send the toast away early.
    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 40 || abs(value.translation.width) > 80
                    || value.predictedEndTranslation.height > 120 {
                    dismiss()
                } else {
                    withOptionalMotionAnimation(AnimationTimings.standard) { dragOffset = 0 }
                }
            }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let onTap {
            Button {
                // The tapped content may present an in-tree detail overlay. Let that
                // owner decide when to clear the source state instead of racing the
                // presentation with this badge's dismissal callback.
                onTap()
            } label: {
                statusMessageText
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Status.exportStatusBadge)
            .accessibilityValue(statusAccessibilityValue)
            .accessibilityHint("Review export issues")
        } else {
            statusMessageText
                .padding(.top, 6)
                .accessibilityIdentifier(AccessibilityID.Status.exportStatusBadge)
                .accessibilityValue(statusAccessibilityValue)
        }
    }

    private var statusMessageText: some View {
        Text(message)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Self.text)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var exportActionButtons: some View {
        if let onPreview {
            Button(action: onPreview) {
                Label("View Exported File", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Self.accent))
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.preview-file")
        }

        if let onBrowseFolder {
            Button(action: onBrowseFolder) {
                Label("Browse Export Folder", systemImage: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Self.surface))
                    .overlay(Capsule().strokeBorder(Self.edge, lineWidth: 1))
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("export.browse-folder")
        }
    }

    private var message: String {
        switch status {
        case .success(let msg), .warning(let msg), .error(let msg): return msg
        }
    }

    private var statusIcon: String {
        switch status {
        case .success: return "checkmark"
        case .warning: return "exclamationmark"
        case .error: return "xmark"
        }
    }

    private var statusColor: Color {
        switch status {
        case .success: return Self.ok
        case .warning, .error: return Self.coral
        }
    }

    private var statusAccessibilityValue: String {
        switch status {
        case .success: return "Success"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        withOptionalMotionAnimation(AnimationTimings.standard) {
            isVisible = false
            offset = 80
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.2)) {
            onDismiss()
        }
    }

    private func withOptionalMotionAnimation(_ animation: Animation, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    // Mirrors of `GlassPalette` (docs/design/liquid-glass/tokens.json) for this host-free view.
    private static let radius: CGFloat = 26
    private static let text = glassColor(light: 0x14101D, dark: 0xFFFFFF)
    private static let muted = glassColor(light: 0x575070, dark: 0xB3ABC6)
    private static let accent = glassColor(light: 0x6A3FE0, dark: 0xCDB6FF)
    private static let accentInk = glassColor(light: 0xFFFFFF, dark: 0x1A0F33)
    private static let ok = glassColor(light: 0x15803D, dark: 0x8BF0B4)
    private static let coral = glassColor(light: 0xB93C0A, dark: 0xFFA184)
    private static let surface = glassColor(light: 0xFFFFFF, lightAlpha: 0.85, dark: 0xFFFFFF, darkAlpha: 0.18)
    private static let glass = glassColor(light: 0xFFFFFF, lightAlpha: 0.72, dark: 0xFFFFFF, darkAlpha: 0.08)
    private static let edge = glassColor(light: 0x14101D, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.14)

    private static func glassColor(
        light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1
    ) -> Color {
        func rgb(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? rgb(dark, darkAlpha) : rgb(light, lightAlpha)
        })
    }
}

/// A warning toast that expands into partial-export details or Health permission guidance.
struct PartialExportNoticeToast: View {
    @Environment(\.openURL) private var openURL
    @Binding var notice: PartialExportNotice?
    let bottomPadding: CGFloat
    let onDismiss: () -> Void
    let requestHealthAuthorization: @MainActor () async throws -> HealthKitManager.AuthorizationRequestOutcome

    @State private var presentedNotice: PartialExportNotice?

    var body: some View {
        Group {
            if let notice {
                ExportStatusBadge(
                    status: .warning(notice.toastMessage),
                    onDismiss: {
                        clearNotice()
                    },
                    onTap: {
                        presentedNotice = notice
                    }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, bottomPadding)
            }
        }
        // Expand to the full proposed area so the dialog scrim covers the screen;
        // the toast badge itself stays pinned to the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .geistDialog(
            isPresented: Binding(
                get: { presentedNotice != nil },
                set: {
                    guard !$0 else { return }
                    presentedNotice = nil
                    clearNotice()
                }
            ),
            title: Text(presentedNotice?.permissionGuidance != nil ? "Health Permissions Needed" : "Partial Export"),
            message: presentedNotice.map { notice in
                if let guidance = notice.permissionGuidance {
                    return Text(notice.permissionAlertMessage(instructions: guidance.iOSInstructions))
                }
                return Text(notice.genericAlertMessage)
            },
            actions: presentedNotice?.permissionGuidance != nil
                ? [
                    .action("Request Access") {
                        requestAdditionalHealthAccess()
                    },
                    .action("Open Health App") {
                        openHealthApp()
                    }
                ]
                : [.action("OK", role: .secondary)]
        )
        // Opening the dialog cancels the toast's expiry. Permission guidance
        // stays available until the user chooses an action or dismisses it.
        .task(id: presentedNotice == nil ? notice?.id : nil) {
            guard notice != nil, presentedNotice == nil else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, presentedNotice == nil else { return }
            clearNotice()
        }
    }

    private func clearNotice() {
        guard notice != nil else { return }
        notice = nil
        onDismiss()
    }

    private func requestAdditionalHealthAccess() {
        Task { @MainActor in
            do {
                if try await requestHealthAuthorization() == .unnecessary {
                    openHealthApp()
                }
            } catch {
                openHealthApp()
            }
        }
    }

    private func openHealthApp() {
        if let healthURL = URL(string: "x-apple-health://") {
            openURL(healthURL)
        }
    }
}
